import 'dart:math';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../onboarding/profile_controller.dart';
import 'muscle_group.dart';
import 'workout_log.dart';

@immutable
class MuscleProgress {
  const MuscleProgress({
    required this.muscle,
    required this.score,
    required this.consistency,
    required this.progression,
    required this.experience,
    required this.sessionsLast28,
    this.daysSinceLast,
  });

  final MuscleGroup muscle;

  /// 0 = bronce opaco · 1 = oro brillante.
  final double score;
  final double consistency;
  final double progression;
  final double experience;
  final int sessionsLast28;
  final int? daysSinceLast;
}

/// Motor del "Mapa Anatómico Evolutivo".
///
/// Puntaje por músculo (0–1) =
///   (0.40 × consistencia + 0.35 × sobrecarga progresiva + 0.25 × experiencia)
///   × factor de inactividad
///
/// * Consistencia: sesiones que trabajaron el músculo en los últimos 28 días,
///   sobre una meta de 8 (2 por semana).
/// * Sobrecarga progresiva: volumen medio de las 3 sesiones más recientes vs.
///   las 3 primeras de tu historial. +50 % de volumen = puntaje completo.
/// * Experiencia: sesiones acumuladas sobre 36 (≈ 4 meses a 2 por semana).
/// * Inactividad: tras 14 días sin trabajar el músculo, el dorado se apaga
///   gradualmente (hasta un 60 %), igual que la adaptación real.
class ProgressEngine {
  ProgressEngine._();

  static const int _consistencyTarget = 8;
  static const int _experienceTarget = 36;
  static const int _window = 3;

  static Map<MuscleGroup, MuscleProgress> compute(
    List<WorkoutSession> sessions, {
    required double bodyweightKg,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final sorted = [...sessions]..sort((a, b) => a.date.compareTo(b.date));
    final result = <MuscleGroup, MuscleProgress>{};

    for (final muscle in MuscleGroup.values) {
      final volumes = <({DateTime date, double volume})>[];
      for (final s in sorted) {
        var v = 0.0;
        for (final e in s.exercises) {
          if (e.muscles.contains(muscle)) v += e.volume(bodyweightKg);
        }
        if (v > 0) volumes.add((date: s.date, volume: v));
      }

      if (volumes.isEmpty) {
        result[muscle] = MuscleProgress(
          muscle: muscle,
          score: 0,
          consistency: 0,
          progression: 0,
          experience: 0,
          sessionsLast28: 0,
        );
        continue;
      }

      final recent28 = volumes
          .where((v) => today.difference(v.date).inDays < 28)
          .length;
      final consistency = min(1.0, recent28 / _consistencyTarget);
      final experience = min(1.0, volumes.length / _experienceTarget);

      var progression = 0.0;
      if (volumes.length > _window) {
        final baseline = _mean(volumes.take(_window).map((v) => v.volume));
        final latest = _mean(
            volumes.skip(volumes.length - _window).map((v) => v.volume));
        if (baseline > 0) {
          progression = ((latest / baseline - 1) / 0.5).clamp(0.0, 1.0).toDouble();
        }
      }

      final daysSinceLast = today.difference(volumes.last.date).inDays;
      final decay = daysSinceLast <= 14
          ? 1.0
          : max(0.4, 1 - (daysSinceLast - 14) / 60);

      final score =
          ((0.40 * consistency + 0.35 * progression + 0.25 * experience) *
                  decay)
              .clamp(0.0, 1.0)
              .toDouble();

      result[muscle] = MuscleProgress(
        muscle: muscle,
        score: score,
        consistency: consistency,
        progression: progression,
        experience: experience,
        sessionsLast28: recent28,
        daysSinceLast: daysSinceLast,
      );
    }
    return result;
  }

  static double overall(Map<MuscleGroup, MuscleProgress> map) {
    if (map.isEmpty) return 0;
    return map.values.fold(0.0, (sum, m) => sum + m.score) / map.length;
  }

  static double _mean(Iterable<double> values) {
    var sum = 0.0;
    var n = 0;
    for (final v in values) {
      sum += v;
      n++;
    }
    return n == 0 ? 0 : sum / n;
  }

  static const List<(double, Color)> _stops = [
    (0.00, AurumColors.bronzeDull),
    (0.35, AurumColors.bronze),
    (0.65, AurumColors.amber),
    (0.85, AurumColors.gold),
    (1.00, AurumColors.goldBright),
  ];

  /// Interpolación bronce opaco → dorado brillante.
  static Color colorFor(double score) {
    final s = score.clamp(0.0, 1.0).toDouble();
    if (s <= 0) return _stops.first.$2;
    if (s >= 1) return _stops.last.$2;
    for (var i = 1; i < _stops.length; i++) {
      final (t1, c1) = _stops[i];
      if (s <= t1) {
        final (t0, c0) = _stops[i - 1];
        final t = (s - t0) / (t1 - t0);
        return Color.lerp(c0, c1, t)!;
      }
    }
    return AurumColors.goldBright;
  }

  static String tierFor(double score) {
    if (score < 0.20) return 'Bronce opaco';
    if (score < 0.45) return 'Bronce';
    if (score < 0.70) return 'Ámbar';
    if (score < 0.90) return 'Oro';
    return 'Oro brillante';
  }
}

final progressProvider = Provider<Map<MuscleGroup, MuscleProgress>>((ref) {
  final sessions = ref.watch(workoutLogProvider);
  final profile = ref.watch(profileProvider);
  return ProgressEngine.compute(
    sessions,
    bodyweightKg: profile?.weightKg ?? 70,
  );
});
