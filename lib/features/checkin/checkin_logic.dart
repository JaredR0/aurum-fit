import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;

import '../plan/plan_models.dart';
import '../progress/workout_log.dart';
import 'benchmarks.dart';
import 'checkin_models.dart';

/// Avance hacia una meta medible del objetivo.
@immutable
class TargetProgress {
  const TargetProgress({
    required this.target,
    this.baseline,
    this.latest,
    this.fraction,
  });

  final GoalTarget target;
  final double? baseline;
  final double? latest;

  /// 0…1, o null si aún no hay datos.
  final double? fraction;
}

@immutable
class PersonalRecord {
  const PersonalRecord({
    required this.benchmark,
    required this.baseline,
    required this.best,
    required this.improvement,
    required this.date,
  });

  final Benchmark benchmark;
  final double baseline;
  final double best;

  /// Mejora relativa (0.15 = +15 %).
  final double improvement;
  final DateTime date;
}

@immutable
class Achievement {
  const Achievement({
    required this.icon,
    required this.title,
    required this.detail,
    required this.unlocked,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool unlocked;
}

class CheckinLogic {
  CheckinLogic._();

  /// Check-ins que pertenecen al plan actual (los anteriores siguen contando
  /// para récords, pero no para el calendario de semanas).
  static List<WeeklyCheckin> forPlan(TrainingPlan plan, List<WeeklyCheckin> all) {
    final start = plan.startDate.subtract(const Duration(days: 7));
    return all.where((c) => c.isBaseline || c.date.isAfter(start)).toList();
  }

  /// Semana cuyo check-in está pendiente (0 = evaluación inicial) o null.
  static int? pendingWeek(
    TrainingPlan plan,
    List<WeeklyCheckin> all,
    DateTime now,
  ) {
    final list = forPlan(plan, all);
    if (!list.any((c) => c.isBaseline)) return 0;
    final done = {for (final c in list) c.week};
    final current = plan.rawWeekNumber(now);
    if (current > plan.totalWeeks + 1) return null;
    // El fin de semana se cierra la semana en curso.
    if (now.weekday >= DateTime.saturday &&
        current <= plan.totalWeeks &&
        !done.contains(current)) {
      return current;
    }
    final previous = current - 1;
    if (previous >= 1 && previous <= plan.totalWeeks && !done.contains(previous)) {
      return previous;
    }
    return null;
  }

  /// Primer día (lunes) de la semana [week] del plan.
  static DateTime weekStart(TrainingPlan plan, int week) =>
      plan.startDate.add(Duration(days: 7 * (week - 1)));

  /// Sesiones registradas en la semana [week] del plan.
  static int sessionsInWeek(
    TrainingPlan plan,
    int week,
    List<WorkoutSession> sessions,
  ) {
    if (week < 1) return 0;
    final start = weekStart(plan, week);
    final end = start.add(const Duration(days: 7));
    final days = <String>{};
    for (final s in sessions) {
      final d = DateTime.utc(s.date.year, s.date.month, s.date.day);
      if (!d.isBefore(start) && d.isBefore(end)) {
        days.add('${d.year}-${d.month}-${d.day}');
      }
    }
    return days.length;
  }

  /// La semana a mostrar, con descarga automática si el check-in anterior
  /// reportó dolor o poca energía.
  static TrainingWeek effectiveWeek(
    TrainingPlan plan,
    int number,
    List<WeeklyCheckin> all,
  ) {
    final week = plan.week(number);
    final list = forPlan(plan, all);
    WeeklyCheckin? previous;
    for (final c in list) {
      if (c.week == number - 1) previous = c;
    }
    if (previous == null || !previous.recommendsDeload || week.deload) {
      return week;
    }
    final why = previous.pain
        ? 'reportaste dolor o molestia'
        : 'reportaste poca energía';
    return week.asDeload(
      reason: 'Ajustada por tu check-in: $why. Menos volumen esta semana; '
          'si el dolor sigue, consulta a un profesional.',
    );
  }

  /// Valor inicial y último de cada prueba.
  static ({Map<String, double> first, Map<String, double> last}) firstAndLast(
    List<WeeklyCheckin> all, {
    double? startWeightKg,
  }) {
    final first = <String, double>{};
    final last = <String, double>{};
    if (startWeightKg != null) first['body_kg'] = startWeightKg;
    for (final c in all) {
      final entries = <String, double>{
        ...c.values,
        if (c.bodyWeightKg != null) 'body_kg': c.bodyWeightKg!,
      };
      for (final e in entries.entries) {
        first.putIfAbsent(e.key, () => e.value);
        last[e.key] = e.value;
      }
    }
    return (first: first, last: last);
  }

  static List<TargetProgress> targetProgress(
    TrainingPlan plan,
    List<WeeklyCheckin> all, {
    double? startWeightKg,
  }) {
    final fl = firstAndLast(all, startWeightKg: startWeightKg);
    return [
      for (final t in plan.targets)
        _progressFor(t, fl.first[t.benchmarkId], fl.last[t.benchmarkId]),
    ];
  }

  static TargetProgress _progressFor(GoalTarget t, double? base, double? latest) {
    if (latest == null) return TargetProgress(target: t, baseline: base);
    double fraction;
    if (t.benchmarkId == 'body_kg' || !t.higherIsBetter) {
      // Metas relativas al punto de partida (bajar/subir de peso, ritmo).
      final b = base ?? latest;
      final span = t.higherIsBetter ? t.target - b : b - t.target;
      final moved = t.higherIsBetter ? latest - b : b - latest;
      fraction = span <= 0 ? (moved >= 0 ? 1.0 : 0.0) : moved / span;
    } else {
      // Metas absolutas: "llevas 120 de 210 minutos".
      fraction = t.target <= 0 ? 0 : latest / t.target;
    }
    return TargetProgress(
      target: t,
      baseline: base,
      latest: latest,
      fraction: fraction.clamp(0.0, 1.0).toDouble(),
    );
  }

  /// Preparación global para el objetivo (promedio de metas con datos).
  static double? readiness(List<TargetProgress> progress) {
    final known = progress.where((p) => p.fraction != null).toList();
    if (known.isEmpty) return null;
    return known.fold<double>(0, (s, p) => s + p.fraction!) / known.length;
  }

  static List<PersonalRecord> records(List<WeeklyCheckin> all) {
    final out = <PersonalRecord>[];
    for (final b in Benchmarks.all) {
      if (b.id == 'body_kg') continue;
      double? baseline;
      double? best;
      DateTime? bestDate;
      for (final c in all) {
        final v = c.values[b.id];
        if (v == null || v <= 0) continue;
        baseline ??= v;
        final better = best == null ||
            (b.higherIsBetter ? v > best : v < best);
        if (better) {
          best = v;
          bestDate = c.date;
        }
      }
      if (baseline != null && best != null && bestDate != null) {
        out.add(PersonalRecord(
          benchmark: b,
          baseline: baseline,
          best: best,
          improvement: b.improvement(baseline, best),
          date: bestDate,
        ));
      }
    }
    out.sort((a, b) => b.improvement.compareTo(a.improvement));
    return out;
  }

  /// Mejora por prueba entre la primera y la última medición, convertida en
  /// 0…1 según lo exigente que es cada prueba.
  static Map<String, double> benchmarkScores(List<WeeklyCheckin> all) {
    final fl = firstAndLast(all);
    final out = <String, double>{};
    for (final e in fl.last.entries) {
      final b = Benchmarks.byId(e.key);
      final base = fl.first[e.key];
      if (b == null || base == null || b.muscles.isEmpty) continue;
      final imp = b.improvement(base, e.value);
      out[e.key] = (imp / b.fullScoreGain).clamp(0.0, 1.0).toDouble();
    }
    return out;
  }

  static int _bestStreak(List<WeeklyCheckin> all) {
    final weeks = all.where((c) => !c.isBaseline).map((c) => c.week).toSet().toList()
      ..sort();
    var best = 0;
    var run = 0;
    int? prev;
    for (final w in weeks) {
      run = (prev != null && w == prev + 1) ? run + 1 : 1;
      if (run > best) best = run;
      prev = w;
    }
    return best;
  }

  static List<Achievement> achievements(
    TrainingPlan plan,
    List<WeeklyCheckin> all,
    List<TargetProgress> targets,
    List<PersonalRecord> records,
    DateTime now,
  ) {
    final weekly = all.where((c) => !c.isBaseline).toList();
    final streak = _bestStreak(all);
    final perfect = weekly.any(
        (c) => c.sessionsPlanned > 0 && c.sessionsDone >= c.sessionsPlanned);
    final current = plan.rawWeekNumber(now);
    final improved = records.where((r) => r.improvement > 0.001).toList();

    final list = <Achievement>[
      Achievement(
        icon: Icons.flag_outlined,
        title: 'Punto de partida',
        detail: 'Completa la evaluación inicial.',
        unlocked: all.any((c) => c.isBaseline),
      ),
      Achievement(
        icon: Icons.event_available_outlined,
        title: 'Primer check-in',
        detail: 'Cierra tu primera semana.',
        unlocked: weekly.isNotEmpty,
      ),
      Achievement(
        icon: Icons.local_fire_department_outlined,
        title: 'Racha de 4 semanas',
        detail: '4 check-ins seguidos.',
        unlocked: streak >= 4,
      ),
      Achievement(
        icon: Icons.whatshot_outlined,
        title: 'Racha de 8 semanas',
        detail: '8 check-ins seguidos.',
        unlocked: streak >= 8,
      ),
      Achievement(
        icon: Icons.check_circle_outline,
        title: 'Semana perfecta',
        detail: 'Todas las sesiones de una semana completadas.',
        unlocked: perfect,
      ),
      Achievement(
        icon: Icons.trending_up,
        title: 'Primer récord personal',
        detail: improved.isEmpty
            ? 'Mejora cualquier prueba respecto a tu evaluación inicial.'
            : '${improved.first.benchmark.label}: +${(improved.first.improvement * 100).round()} %',
        unlocked: improved.isNotEmpty,
      ),
      Achievement(
        icon: Icons.emoji_events_outlined,
        title: 'Tres récords',
        detail: 'Mejora 3 pruebas distintas.',
        unlocked: improved.length >= 3,
      ),
      Achievement(
        icon: Icons.timelapse,
        title: 'Mitad del camino',
        detail: 'Llega a la semana ${(plan.totalWeeks / 2).ceil()} del plan.',
        unlocked: current > (plan.totalWeeks / 2).ceil() && weekly.isNotEmpty,
      ),
    ];

    for (final t in targets) {
      final f = t.fraction ?? 0;
      list
        ..add(Achievement(
          icon: Icons.hiking,
          title: 'A medio camino: ${t.target.label.toLowerCase()}',
          detail: '50 % de la meta (${_fmt(t.target, t.target.target)}).',
          unlocked: f >= 0.5,
        ))
        ..add(Achievement(
          icon: Icons.workspace_premium_outlined,
          title: 'Meta cumplida: ${t.target.label.toLowerCase()}',
          detail: 'Llegaste a ${_fmt(t.target, t.target.target)}.',
          unlocked: f >= 1,
        ));
    }
    // Primero los desbloqueados, conservando el orden.
    return [
      ...list.where((a) => a.unlocked),
      ...list.where((a) => !a.unlocked),
    ];
  }

  static String _fmt(GoalTarget t, double v) {
    final b = Benchmarks.byId(t.benchmarkId);
    return b?.format(v) ?? '${v.round()} ${t.unit}';
  }
}
