import 'package:aurum_fit/features/plan/plan_models.dart';
import 'package:aurum_fit/features/timer/interval_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HIIT: fases, cuenta regresiva 5→1 y fin', () {
    final program = IntervalProgram.intervals(
        name: 't', workSec: 10, restSec: 5, rounds: 2, activity: 'Saltos');
    // prepara(10) + trabajo(10) + descanso(5) + trabajo(10)
    expect(program.phases.length, 4);
    expect(program.timedSeconds, 35);

    final s = IntervalSession(program);
    final events = <IntervalEvent>[...s.start()];
    for (var i = 0; i < 400; i++) {
      events.addAll(s.advance(const Duration(milliseconds: 100)));
    }
    expect(s.finished, isTrue);
    expect(events.whereType<PhaseStarted>().length, 4);
    expect(events.whereType<SessionFinished>().length, 1);

    // La primera fase (10 s) anuncia 5, 4, 3, 2, 1.
    final firstCountdown = events
        .takeWhile((e) => !(e is PhaseStarted && e.index == 1))
        .whereType<CountdownTick>()
        .map((e) => e.secondsLeft)
        .toList();
    expect(firstCountdown, [5, 4, 3, 2, 1]);
  });

  test('un salto grande de tiempo atraviesa varias fases', () {
    final s = IntervalSession(IntervalProgram.tabata());
    s.start();
    final events = s.advance(const Duration(seconds: 45)); // 10 + 20 + 10 + 5
    expect(s.index, 3);
    expect(events.whereType<PhaseStarted>().length, 3);
  });

  test('fases abiertas esperan a "Siguiente"', () {
    const day = TrainingDay(weekday: 1, title: 'Carrera', exercises: [
      Exercise(name: 'Carrera', kind: ExerciseKind.cardio, sets: 1, distanceKm: 1, restSec: 0),
    ]);
    final program = IntervalProgram.fromTrainingDay(day);
    expect(program.phases[1].spoken, '¡Corre 1 kilómetro!');
    expect(program.phases[1].seconds, isNull);

    final s = IntervalSession(program);
    s.start();
    s.advance(const Duration(seconds: 10)); // termina "Prepárate"
    s.advance(const Duration(minutes: 30));
    expect(s.finished, isFalse);
    expect(s.skip().single, isA<SessionFinished>());
  });

  test('el descanso anuncia la siguiente actividad', () {
    const day = TrainingDay(weekday: 1, title: 'Fuerza', exercises: [
      Exercise(name: 'Flexiones', kind: ExerciseKind.strength, sets: 2, reps: '10', restSec: 15),
      Exercise(name: 'Saltos de cuerda', kind: ExerciseKind.cardio, sets: 1, durationSec: 45, restSec: 0),
    ]);
    final program = IntervalProgram.fromTrainingDay(day);
    final spoken = program.phases.map((p) => p.spoken).toList();
    expect(spoken, contains('¡Descanso de 15 segundos! Siguiente: Saltos de cuerda'));
    expect(spoken.last, '¡Saltos de cuerda por 45 segundos!');
  });
}
