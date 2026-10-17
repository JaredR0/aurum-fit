import 'package:flutter/foundation.dart';

import '../../core/security/input_sanitizer.dart';
import '../progress/muscle_group.dart';

// ---------------------------------------------------------------------------
// Parsing defensivo: todo lo que viene de la IA se trata como NO confiable.
// Cada campo se valida, se acota y se limpia; lo desconocido se descarta.
// ---------------------------------------------------------------------------

String _s(Object? v, {int max = 120, String fallback = ''}) {
  if (v is! String) return fallback;
  final t = InputSanitizer.clean(v, maxLength: max).text;
  return t.isEmpty ? fallback : t;
}

int _i(Object? v, {required int min, required int max, required int fallback}) {
  final n = v is num ? v : num.tryParse('$v');
  if (n == null || n.isNaN || n.isInfinite) return fallback;
  return n.round().clamp(min, max).toInt();
}

double? _dOpt(Object? v, {required double min, required double max}) {
  if (v == null) return null;
  final n = v is num ? v : num.tryParse('$v');
  if (n == null || n.isNaN || n.isInfinite) return null;
  return n.toDouble().clamp(min, max).toDouble();
}

List<T> _list<T>(Object? v, T? Function(Object?) parse, {int max = 40}) {
  if (v is! List) return <T>[];
  final out = <T>[];
  for (final item in v.take(max)) {
    final parsed = parse(item);
    if (parsed != null) out.add(parsed);
  }
  return out;
}

Map<String, dynamic>? _map(Object? v) => v is Map<String, dynamic> ? v : null;

enum ExerciseKind { strength, cardio, mobility }

ExerciseKind _kind(Object? v) => switch (v) {
      'cardio' => ExerciseKind.cardio,
      'mobility' || 'movilidad' => ExerciseKind.mobility,
      _ => ExerciseKind.strength,
    };

@immutable
class Exercise {
  const Exercise({
    required this.name,
    required this.kind,
    this.sets = 3,
    this.reps = '10',
    this.restSec = 60,
    this.durationSec,
    this.distanceKm,
    this.muscles = const [],
    this.notes = '',
  });

  final String name;
  final ExerciseKind kind;
  final int sets;

  /// Texto porque puede ser "8–12", "AMRAP", "30 s por lado".
  final String reps;
  final int restSec;
  final int? durationSec;
  final double? distanceKm;
  final List<MuscleGroup> muscles;
  final String notes;

  static String _minutes(int seconds) {
    if (seconds < 90) return '$seconds s';
    final m = (seconds / 60).round();
    if (m < 90) return '$m min';
    final h = m ~/ 60;
    final r = m % 60;
    return r == 0 ? '$h h' : '$h h $r min';
  }

  String get prescription {
    if (kind == ExerciseKind.cardio) {
      final parts = <String>[];
      if (distanceKm != null) parts.add('${_km(distanceKm!)} km');
      if (durationSec != null) parts.add(_minutes(durationSec!));
      final base = parts.isEmpty ? reps : parts.join(' · ');
      if (sets > 1) {
        return '$sets × $base${restSec > 0 ? ' · pausa ${restSec}s' : ''}';
      }
      return base;
    }
    if (durationSec != null) {
      return '$sets × ${_minutes(durationSec!)} · descanso ${restSec}s';
    }
    return '$sets × $reps · descanso ${restSec}s';
  }

  static String _km(double km) =>
      km == km.roundToDouble() ? km.round().toString() : km.toStringAsFixed(1);

  Exercise copyWith({
    String? name,
    int? sets,
    String? reps,
    int? restSec,
    int? durationSec,
    double? distanceKm,
    String? notes,
  }) =>
      Exercise(
        name: name ?? this.name,
        kind: kind,
        sets: sets ?? this.sets,
        reps: reps ?? this.reps,
        restSec: restSec ?? this.restSec,
        durationSec: durationSec ?? this.durationSec,
        distanceKm: distanceKm ?? this.distanceKm,
        muscles: muscles,
        notes: notes ?? this.notes,
      );

  /// Escala el volumen de cardio (duración/distancia) por [factor].
  Exercise scaledCardio(double factor) {
    if (kind != ExerciseKind.cardio) return this;
    int? d;
    if (durationSec != null) {
      final raw = durationSec! * factor;
      d = raw >= 300 ? (raw / 60).round() * 60 : (raw / 5).round() * 5;
      d = d.clamp(5, 6 * 3600).toInt();
    }
    double? km;
    if (distanceKm != null) {
      km = distanceKm! >= 2
          ? ((distanceKm! * factor) * 2).round() / 2
          : double.parse((distanceKm! * factor).toStringAsFixed(1));
      km = km.clamp(0.1, 60).toDouble();
    }
    return copyWith(durationSec: d, distanceKm: km);
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': kind.name,
        'sets': sets,
        'reps': reps,
        'restSec': restSec,
        'durationSec': durationSec,
        'distanceKm': distanceKm,
        'muscles': muscles.map((m) => m.name).toList(),
        'notes': notes,
      };

  static Exercise? tryParse(Object? raw) {
    final j = _map(raw);
    if (j == null) return null;
    final name = _s(j['name'], max: 80);
    if (name.isEmpty) return null;
    return Exercise(
      name: name,
      kind: _kind(j['kind']),
      sets: _i(j['sets'], min: 1, max: 12, fallback: 3),
      reps: _s(j['reps'], max: 24, fallback: '10'),
      restSec: _i(j['restSec'], min: 0, max: 600, fallback: 60),
      durationSec: j['durationSec'] == null
          ? null
          : _i(j['durationSec'], min: 5, max: 6 * 3600, fallback: 60),
      distanceKm: _dOpt(j['distanceKm'], min: 0.1, max: 60),
      muscles: _list<MuscleGroup>(j['muscles'], (m) => MuscleGroupX.tryParse(m),
          max: 8),
      notes: _s(j['notes'], max: 200),
    );
  }
}

@immutable
class TrainingDay {
  const TrainingDay({
    required this.weekday,
    required this.title,
    required this.exercises,
    this.focus = '',
    this.requiresStepGoal = false,
  });

  /// 1 = lunes … 7 = domingo.
  final int weekday;
  final String title;
  final String focus;
  final List<Exercise> exercises;

  /// Si es true, el día solo cuenta como cumplido al llegar a la meta de pasos.
  final bool requiresStepGoal;

  bool get isRest => exercises.isEmpty;

  TrainingDay copyWith({
    String? title,
    String? focus,
    List<Exercise>? exercises,
  }) =>
      TrainingDay(
        weekday: weekday,
        title: title ?? this.title,
        focus: focus ?? this.focus,
        exercises: exercises ?? this.exercises,
        requiresStepGoal: requiresStepGoal,
      );

  Map<String, dynamic> toJson() => {
        'weekday': weekday,
        'title': title,
        'focus': focus,
        'requiresStepGoal': requiresStepGoal,
        'exercises': exercises.map((e) => e.toJson()).toList(),
      };

  static TrainingDay? tryParse(Object? raw) {
    final j = _map(raw);
    if (j == null) return null;
    return TrainingDay(
      weekday: _i(j['weekday'], min: 1, max: 7, fallback: 1),
      title: _s(j['title'], max: 60, fallback: 'Entrenamiento'),
      focus: _s(j['focus'], max: 160),
      requiresStepGoal: j['requiresStepGoal'] == true,
      exercises: _list<Exercise>(j['exercises'], Exercise.tryParse, max: 14),
    );
  }

  /// Un día por número de semana, ordenados de lunes a domingo.
  static List<TrainingDay> parseWeek(Object? raw) {
    final days = _list<TrainingDay>(raw, TrainingDay.tryParse, max: 7);
    final byDay = <int, TrainingDay>{for (final d in days) d.weekday: d};
    return byDay.values.toList()..sort((a, b) => a.weekday.compareTo(b.weekday));
  }
}

/// Una semana concreta del plan (las semanas cambian: fases, progresión y
/// descargas).
@immutable
class TrainingWeek {
  const TrainingWeek({
    required this.number,
    required this.phase,
    required this.days,
    this.focus = '',
    this.deload = false,
  });

  /// 1 = primera semana del plan.
  final int number;
  final String phase;
  final String focus;
  final bool deload;
  final List<TrainingDay> days;

  int get sessions => days.where((d) => !d.isRest).length;

  TrainingDay? dayFor(int weekday) {
    for (final d in days) {
      if (d.weekday == weekday) return d;
    }
    return null;
  }

  /// Semana de descarga: ~40 % menos volumen para asimilar el entrenamiento.
  TrainingWeek asDeload({String? reason}) {
    if (deload) return this;
    final lighter = [
      for (final d in days)
        d.copyWith(
          exercises: [
            for (final e in d.exercises)
              e.kind == ExerciseKind.cardio
                  ? e.scaledCardio(0.65)
                  : e.copyWith(sets: e.sets > 1 ? (e.sets * 0.6).round().clamp(1, 12).toInt() : 1),
          ],
        ),
    ];
    return TrainingWeek(
      number: number,
      phase: phase,
      focus: reason ??
          'Descarga: menos volumen, misma técnica. El cuerpo se adapta al descansar.',
      deload: true,
      days: lighter,
    );
  }

  Map<String, dynamic> toJson() => {
        'number': number,
        'phase': phase,
        'focus': focus,
        'deload': deload,
        'days': days.map((d) => d.toJson()).toList(),
      };

  static TrainingWeek? tryParse(Object? raw) {
    final j = _map(raw);
    if (j == null) return null;
    final days = TrainingDay.parseWeek(j['days']);
    if (days.isEmpty) return null;
    return TrainingWeek(
      number: _i(j['number'], min: 1, max: 104, fallback: 1),
      phase: _s(j['phase'], max: 40, fallback: 'Plan'),
      focus: _s(j['focus'], max: 200),
      deload: j['deload'] == true,
      days: days,
    );
  }
}

/// Meta medible del objetivo, ligada a una prueba del check-in semanal.
@immutable
class GoalTarget {
  const GoalTarget({
    required this.benchmarkId,
    required this.label,
    required this.unit,
    required this.target,
    this.higherIsBetter = true,
  });

  final String benchmarkId;
  final String label;
  final String unit;
  final double target;
  final bool higherIsBetter;

  Map<String, dynamic> toJson() => {
        'benchmarkId': benchmarkId,
        'label': label,
        'unit': unit,
        'target': target,
        'higherIsBetter': higherIsBetter,
      };

  static GoalTarget? tryParse(Object? raw) {
    final j = _map(raw);
    if (j == null) return null;
    final id = _s(j['benchmarkId'], max: 32);
    final target = _dOpt(j['target'], min: 0, max: 100000);
    if (id.isEmpty || target == null) return null;
    return GoalTarget(
      benchmarkId: id,
      label: _s(j['label'], max: 60, fallback: id),
      unit: _s(j['unit'], max: 12),
      target: target,
      higherIsBetter: j['higherIsBetter'] != false,
    );
  }
}

DateTime _dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

DateTime mondayOf(DateTime d) {
  final day = _dateOnly(d);
  return day.subtract(Duration(days: day.weekday - 1));
}

@immutable
class TrainingPlan {
  const TrainingPlan({
    required this.title,
    required this.summary,
    required this.weeks,
    required this.source,
    required this.createdAt,
    required this.startDate,
    this.progression = '',
    this.references = const [],
    this.goalHeadline = '',
    this.goalFacts = const [],
    this.targets = const [],
    this.schemaVersion = currentSchema,
  });

  static const int currentSchema = 2;

  final String title;
  final String summary;
  final List<TrainingWeek> weeks;

  /// Regla de sobrecarga progresiva semana a semana.
  final String progression;

  /// URLs o citas de evidencia que devolvió la búsqueda web de la IA.
  final List<String> references;

  /// Análisis del objetivo: "Volcán Acatenango · 3,976 m" y datos clave.
  final String goalHeadline;
  final List<String> goalFacts;
  final List<GoalTarget> targets;

  /// 'ai' o 'local'.
  final String source;
  final DateTime createdAt;

  /// Lunes de la semana 1.
  final DateTime startDate;
  final int schemaVersion;

  int get totalWeeks => weeks.length;

  /// Semana del plan para [date] (1…totalWeeks). Antes del inicio → 1;
  /// después del final → la última.
  int weekNumberFor(DateTime date) {
    final raw = rawWeekNumber(date);
    return raw.clamp(1, totalWeeks).toInt();
  }

  /// Sin acotar: puede ser > totalWeeks si el plan ya terminó.
  int rawWeekNumber(DateTime date) {
    final days = mondayOf(date).difference(mondayOf(startDate)).inDays;
    return days ~/ 7 + 1;
  }

  TrainingWeek week(int number) =>
      weeks[(number - 1).clamp(0, weeks.length - 1).toInt()];

  TrainingWeek weekFor(DateTime date) => week(weekNumberFor(date));

  TrainingDay? dayFor(DateTime date) => weekFor(date).dayFor(date.weekday);

  /// Fases en orden de aparición.
  List<String> get phases {
    final out = <String>[];
    for (final w in weeks) {
      if (!out.contains(w.phase)) out.add(w.phase);
    }
    return out;
  }

  /// Completa un plan (p. ej. de la IA) con el análisis del objetivo hecho
  /// en el teléfono.
  TrainingPlan withGoal({
    required String headline,
    required List<String> facts,
    required List<GoalTarget> goalTargets,
  }) =>
      TrainingPlan(
        title: title,
        summary: summary,
        weeks: weeks,
        source: source,
        createdAt: createdAt,
        startDate: startDate,
        progression: progression,
        references: references,
        goalHeadline: goalHeadline.isEmpty ? headline : goalHeadline,
        goalFacts: goalFacts.isEmpty ? facts : goalFacts,
        targets: targets.isEmpty ? goalTargets : targets,
        schemaVersion: currentSchema,
      );

  TrainingPlan copyWithWeeks(List<TrainingWeek> newWeeks) => TrainingPlan(
        title: title,
        summary: summary,
        weeks: newWeeks,
        source: source,
        createdAt: createdAt,
        startDate: startDate,
        progression: progression,
        references: references,
        goalHeadline: goalHeadline,
        goalFacts: goalFacts,
        targets: targets,
        schemaVersion: schemaVersion,
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'title': title,
        'summary': summary,
        'progression': progression,
        'references': references,
        'goalHeadline': goalHeadline,
        'goalFacts': goalFacts,
        'targets': targets.map((t) => t.toJson()).toList(),
        'source': source,
        'createdAt': createdAt.toIso8601String(),
        'startDate': startDate.toIso8601String(),
        'weeks': weeks.map((w) => w.toJson()).toList(),
      };

  /// Acepta tres formatos:
  /// * `weeks`  — plan completo semana a semana (generador local, guardado).
  /// * `phases` — fases con una semana modelo cada una (IA); se expanden.
  /// * `days`   — una sola semana (formato antiguo).
  static TrainingPlan? tryParse(Object? raw, {String? source}) {
    final j = _map(raw);
    if (j == null) return null;

    var weeks = _list<TrainingWeek>(j['weeks'], TrainingWeek.tryParse, max: 104);
    if (weeks.isEmpty && j['phases'] is List) {
      weeks = _expandPhases(j['phases'] as List,
          _i(j['weeks'], min: 1, max: 52, fallback: 8));
    }
    if (weeks.isEmpty) {
      final days = TrainingDay.parseWeek(j['days']);
      if (days.isEmpty) return null;
      weeks = [TrainingWeek(number: 1, phase: 'Plan', days: days)];
    }
    weeks = [
      for (var i = 0; i < weeks.length; i++)
        TrainingWeek(
          number: i + 1,
          phase: weeks[i].phase,
          focus: weeks[i].focus,
          deload: weeks[i].deload,
          days: weeks[i].days,
        ),
    ];

    final created = DateTime.tryParse('${j['createdAt']}') ?? DateTime.now();
    final start = DateTime.tryParse('${j['startDate']}') ?? created;
    return TrainingPlan(
      title: _s(j['title'], max: 80, fallback: 'Plan de entrenamiento'),
      summary: _s(j['summary'], max: 700),
      progression: _s(j['progression'], max: 500),
      references: _list<String>(j['references'], (r) {
        final s = r is String ? r.trim() : '';
        final uri = Uri.tryParse(s);
        return (uri != null && uri.scheme == 'https' && s.length < 300) ? s : null;
      }, max: 10),
      goalHeadline: _s(j['goalHeadline'], max: 80),
      goalFacts: _list<String>(
          j['goalFacts'], (f) => f is String ? _s(f, max: 120) : null,
          max: 8),
      targets: _list<GoalTarget>(j['targets'], GoalTarget.tryParse, max: 8),
      source: source ?? _s(j['source'], max: 10, fallback: 'local'),
      createdAt: created,
      startDate: mondayOf(start),
      schemaVersion: _i(j['schemaVersion'], min: 1, max: 99, fallback: 1),
      weeks: weeks,
    );
  }

  /// Expande fases de la IA a semanas con progresión genérica: el cardio
  /// crece ~7 % por semana dentro de la fase y cada 4.ª semana es descarga.
  static List<TrainingWeek> _expandPhases(List<dynamic> rawPhases, int total) {
    final phases = <({String name, String focus, int from, int to, List<TrainingDay> days})>[];
    for (final p in rawPhases.take(6)) {
      final j = _map(p);
      if (j == null) continue;
      final days = TrainingDay.parseWeek(j['days']);
      if (days.isEmpty) continue;
      final from = _i(j['weekFrom'], min: 1, max: 52, fallback: 1);
      final to = _i(j['weekTo'], min: from, max: 52, fallback: from);
      phases.add((
        name: _s(j['name'], max: 40, fallback: 'Fase ${phases.length + 1}'),
        focus: _s(j['focus'], max: 200),
        from: from,
        to: to,
        days: days,
      ));
    }
    if (phases.isEmpty) return const [];
    phases.sort((a, b) => a.from.compareTo(b.from));
    final last = phases.map((p) => p.to).reduce((a, b) => a > b ? a : b);
    final weeksCount = last > total ? last : total;

    final out = <TrainingWeek>[];
    for (var w = 1; w <= weeksCount.clamp(1, 52); w++) {
      var phase = phases.first;
      for (final p in phases) {
        if (p.from <= w) phase = p;
      }
      final k = (w - phase.from).clamp(0, 52);
      final factor = (1 + 0.07 * k).clamp(1.0, 1.4).toDouble();
      final week = TrainingWeek(
        number: w,
        phase: phase.name,
        focus: phase.focus,
        days: [
          for (final d in phase.days)
            d.copyWith(exercises: [
              for (final e in d.exercises) e.scaledCardio(factor),
            ]),
        ],
      );
      final isDeload = w % 4 == 0 && w != weeksCount;
      out.add(isDeload ? week.asDeload() : week);
    }
    return out;
  }
}

// --------------------------------------------------------------- Nutrición

enum MealSlot { breakfast, snackAm, lunch, snackPm, dinner }

extension MealSlotX on MealSlot {
  String get label => switch (this) {
        MealSlot.breakfast => 'Desayuno',
        MealSlot.snackAm => 'Colación AM',
        MealSlot.lunch => 'Almuerzo',
        MealSlot.snackPm => 'Colación PM',
        MealSlot.dinner => 'Cena',
      };

  static MealSlot parse(Object? v) {
    for (final s in MealSlot.values) {
      if (s.name == v) return s;
    }
    return MealSlot.lunch;
  }
}

@immutable
class Meal {
  const Meal({
    required this.slot,
    required this.time,
    required this.name,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.description = '',
    this.alternatives = const [],
  });

  final MealSlot slot;

  /// "HH:mm"
  final String time;
  final String name;
  final String description;
  final int kcal;
  final int proteinG;
  final int carbsG;
  final int fatG;
  final List<String> alternatives;

  int get hour => int.tryParse(time.split(':').first) ?? 12;
  int get minute =>
      int.tryParse(time.split(':').length > 1 ? time.split(':')[1] : '0') ?? 0;

  Map<String, dynamic> toJson() => {
        'slot': slot.name,
        'time': time,
        'name': name,
        'description': description,
        'kcal': kcal,
        'proteinG': proteinG,
        'carbsG': carbsG,
        'fatG': fatG,
        'alternatives': alternatives,
      };

  static Meal? tryParse(Object? raw) {
    final j = _map(raw);
    if (j == null) return null;
    final name = _s(j['name'], max: 80);
    if (name.isEmpty) return null;
    final time = '${j['time']}';
    final valid = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(time);
    return Meal(
      slot: MealSlotX.parse(j['slot']),
      time: valid ? time : '12:00',
      name: name,
      description: _s(j['description'], max: 300),
      kcal: _i(j['kcal'], min: 0, max: 3000, fallback: 0),
      proteinG: _i(j['proteinG'], min: 0, max: 300, fallback: 0),
      carbsG: _i(j['carbsG'], min: 0, max: 500, fallback: 0),
      fatG: _i(j['fatG'], min: 0, max: 250, fallback: 0),
      alternatives: _list<String>(
          j['alternatives'], (a) => a is String ? _s(a, max: 120) : null,
          max: 4),
    );
  }
}

@immutable
class NutritionDay {
  const NutritionDay({required this.weekday, required this.meals});

  final int weekday;
  final List<Meal> meals;

  int get kcal => meals.fold(0, (sum, m) => sum + m.kcal);

  Map<String, dynamic> toJson() => {
        'weekday': weekday,
        'meals': meals.map((m) => m.toJson()).toList(),
      };

  static NutritionDay? tryParse(Object? raw) {
    final j = _map(raw);
    if (j == null) return null;
    final meals = _list<Meal>(j['meals'], Meal.tryParse, max: 6)
      ..sort((a, b) => a.time.compareTo(b.time));
    if (meals.isEmpty) return null;
    return NutritionDay(
      weekday: _i(j['weekday'], min: 1, max: 7, fallback: 1),
      meals: meals,
    );
  }
}

@immutable
class NutritionPlan {
  const NutritionPlan({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.days,
    this.notes = const [],
  });

  final int calories;
  final int proteinG;
  final int carbsG;
  final int fatG;
  final List<NutritionDay> days;
  final List<String> notes;

  NutritionDay? dayFor(DateTime date) {
    for (final d in days) {
      if (d.weekday == date.weekday) return d;
    }
    return days.isEmpty ? null : days.first;
  }

  Map<String, dynamic> toJson() => {
        'calories': calories,
        'proteinG': proteinG,
        'carbsG': carbsG,
        'fatG': fatG,
        'notes': notes,
        'days': days.map((d) => d.toJson()).toList(),
      };

  static NutritionPlan? tryParse(Object? raw) {
    final j = _map(raw);
    if (j == null) return null;
    final days = _list<NutritionDay>(j['days'], NutritionDay.tryParse, max: 7);
    if (days.isEmpty) return null;
    return NutritionPlan(
      calories: _i(j['calories'], min: 1000, max: 6000, fallback: 2000),
      proteinG: _i(j['proteinG'], min: 20, max: 400, fallback: 120),
      carbsG: _i(j['carbsG'], min: 20, max: 800, fallback: 220),
      fatG: _i(j['fatG'], min: 20, max: 250, fallback: 65),
      notes: _list<String>(
          j['notes'], (n) => n is String ? _s(n, max: 240) : null,
          max: 8),
      days: days,
    );
  }
}

/// Plan completo guardado en la base cifrada.
@immutable
class FitnessPlan {
  const FitnessPlan({required this.training, required this.nutrition});

  final TrainingPlan training;
  final NutritionPlan nutrition;

  Map<String, dynamic> toJson() => {
        'training': training.toJson(),
        'nutrition': nutrition.toJson(),
      };

  static FitnessPlan? tryParse(Object? raw, {String? source}) {
    final j = _map(raw);
    if (j == null) return null;
    final training = TrainingPlan.tryParse(j['training'], source: source);
    final nutrition = NutritionPlan.tryParse(j['nutrition']);
    if (training == null || nutrition == null) return null;
    return FitnessPlan(training: training, nutrition: nutrition);
  }
}
