import 'package:aurum_fit/core/theme/app_theme.dart';
import 'package:aurum_fit/features/plan/plan_models.dart';
import 'package:aurum_fit/features/progress/muscle_group.dart';
import 'package:aurum_fit/features/progress/progress_engine.dart';
import 'package:aurum_fit/features/progress/workout_log.dart';
import 'package:flutter_test/flutter_test.dart';

WorkoutSession _squat(DateTime date, double kg) => WorkoutSession(
      id: date.toIso8601String(),
      date: date,
      title: 'Pierna',
      exercises: [
        LoggedExercise(
          name: 'Sentadilla',
          kind: ExerciseKind.strength,
          muscles: const [MuscleGroup.quads, MuscleGroup.glutes],
          sets: [for (var i = 0; i < 3; i++) SetEntry(reps: 10, weightKg: kg)],
        ),
      ],
    );

void main() {
  final now = DateTime(2026, 10, 16);

  test('sin entrenamientos todo es bronce opaco', () {
    final map = ProgressEngine.compute(const [], bodyweightKg: 70, now: now);
    expect(map.length, MuscleGroup.values.length);
    expect(ProgressEngine.overall(map), 0);
    expect(ProgressEngine.colorFor(0), AurumColors.bronzeDull);
  });

  test('consistencia + sobrecarga progresiva suben el puntaje hacia oro', () {
    final sessions = [
      // 16 sesiones en 8 semanas, de 40 kg a 70 kg.
      for (var i = 0; i < 16; i++)
        _squat(now.subtract(Duration(days: 56 - i * 3.5 ~/ 1)), 40 + i * 2.0),
    ];
    final map = ProgressEngine.compute(sessions, bodyweightKg: 70, now: now);
    final quads = map[MuscleGroup.quads]!;
    expect(quads.consistency, closeTo(7 / 8, 1e-9)); // 7 sesiones en 28 días
    expect(quads.progression, 1.0); // > +50 % de volumen
    expect(quads.score, greaterThan(0.7));
    expect(map[MuscleGroup.chest]!.score, 0);
  });

  test('sin entrenar 60 días el dorado se apaga', () {
    final old = [
      for (var i = 0; i < 16; i++)
        _squat(now.subtract(Duration(days: 120 - i * 3)), 40 + i * 2.0),
    ];
    final fresh = [
      for (var i = 0; i < 16; i++)
        _squat(now.subtract(Duration(days: 50 - i * 3)), 40 + i * 2.0),
    ];
    final faded = ProgressEngine.compute(old, bodyweightKg: 70, now: now);
    final active = ProgressEngine.compute(fresh, bodyweightKg: 70, now: now);
    expect(faded[MuscleGroup.quads]!.score,
        lessThan(active[MuscleGroup.quads]!.score));
  });

  test('escala de color y niveles', () {
    expect(ProgressEngine.colorFor(1), AurumColors.goldBright);
    expect(ProgressEngine.tierFor(0.1), 'Bronce opaco');
    expect(ProgressEngine.tierFor(0.95), 'Oro brillante');
  });
}
