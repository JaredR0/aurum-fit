import 'package:flutter/foundation.dart';

import '../plan/plan_models.dart';

enum PhaseKind { prepare, work, rest }

@immutable
class IntervalPhase {
  const IntervalPhase({
    required this.label,
    required this.spoken,
    required this.kind,
    this.seconds,
  });

  final String label;

  /// Lo que dice el asistente de voz al empezar la fase.
  final String spoken;
  final PhaseKind kind;

  /// null = fase abierta (p. ej. "Corre 1 km"): cuenta hacia arriba y se
  /// avanza tocando "Siguiente".
  final int? seconds;
}

@immutable
class IntervalProgram {
  const IntervalProgram({required this.name, required this.phases});

  final String name;
  final List<IntervalPhase> phases;

  int get timedSeconds =>
      phases.fold(0, (sum, p) => sum + (p.seconds ?? 0));

  static IntervalPhase _prepare(String first) => IntervalPhase(
        label: 'Prepárate',
        spoken: 'Prepárate. Empezamos con $first',
        kind: PhaseKind.prepare,
        seconds: 10,
      );

  /// Intervalos de trabajo/descanso repetidos (HIIT, Tabata, saltar cuerda…).
  factory IntervalProgram.intervals({
    required String name,
    required int workSec,
    required int restSec,
    required int rounds,
    String activity = 'trabajo',
  }) {
    final phases = <IntervalPhase>[_prepare(activity)];
    for (var r = 1; r <= rounds; r++) {
      phases.add(IntervalPhase(
        label: 'Ronda $r/$rounds',
        spoken: '¡$activity por $workSec segundos!',
        kind: PhaseKind.work,
        seconds: workSec,
      ));
      if (r < rounds && restSec > 0) {
        phases.add(IntervalPhase(
          label: 'Descanso',
          spoken: '¡Descanso de $restSec segundos!',
          kind: PhaseKind.rest,
          seconds: restSec,
        ));
      }
    }
    return IntervalProgram(name: name, phases: phases);
  }

  factory IntervalProgram.hiit() => IntervalProgram.intervals(
      name: 'HIIT 40/20', workSec: 40, restSec: 20, rounds: 8, activity: 'Trabajo');

  factory IntervalProgram.tabata() => IntervalProgram.intervals(
      name: 'Tabata', workSec: 20, restSec: 10, rounds: 8, activity: 'Máxima intensidad');

  factory IntervalProgram.boxing({int rounds = 6}) => IntervalProgram.intervals(
      name: 'Boxeo', workSec: 180, restSec: 60, rounds: rounds, activity: 'Golpea el saco');

  factory IntervalProgram.jumpRope() => IntervalProgram.intervals(
      name: 'Cuerda', workSec: 45, restSec: 15, rounds: 10, activity: 'Saltos de cuerda');

  /// Circuito guiado a partir de un día del plan.
  factory IntervalProgram.fromTrainingDay(TrainingDay day) {
    final exercises = day.exercises;
    if (exercises.isEmpty) {
      return IntervalProgram(name: day.title, phases: [_prepare('movilidad')]);
    }
    final phases = <IntervalPhase>[_prepare(exercises.first.name)];
    for (var i = 0; i < exercises.length; i++) {
      final e = exercises[i];
      final next = i + 1 < exercises.length ? exercises[i + 1].name : null;
      for (var s = 1; s <= e.sets; s++) {
        final isLastSet = s == e.sets;
        phases.add(IntervalPhase(
          label: e.sets > 1 ? '${e.name} · serie $s/${e.sets}' : e.name,
          spoken: _instruction(e, s),
          kind: PhaseKind.work,
          seconds: e.durationSec,
        ));
        final isLastPhase = isLastSet && next == null;
        if (!isLastPhase && e.restSec > 0) {
          final upcoming = isLastSet ? next! : '${e.name}, serie ${s + 1}';
          phases.add(IntervalPhase(
            label: 'Descanso',
            spoken: '¡Descanso de ${e.restSec} segundos! Siguiente: $upcoming',
            kind: PhaseKind.rest,
            seconds: e.restSec,
          ));
        }
      }
    }
    return IntervalProgram(name: day.title, phases: phases);
  }

  static String _instruction(Exercise e, int set) {
    if (e.kind == ExerciseKind.cardio) {
      if (e.distanceKm != null) {
        final km = e.distanceKm!;
        final kmText = km == km.roundToDouble()
            ? km.round().toString()
            : km.toStringAsFixed(1);
        return '¡Corre $kmText ${km == 1 ? 'kilómetro' : 'kilómetros'}!';
      }
      if (e.durationSec != null) {
        return '¡${e.name} por ${_durationWords(e.durationSec!)}!';
      }
      return '¡${e.name}!';
    }
    if (e.durationSec != null) {
      return '¡${e.name} por ${_durationWords(e.durationSec!)}!';
    }
    return '${e.name}. Serie $set: ${e.reps} repeticiones. Toca siguiente al terminar.';
  }

  static String _durationWords(int seconds) {
    if (seconds < 90) return '$seconds segundos';
    final minutes = (seconds / 60).round();
    return '$minutes minutos';
  }
}

sealed class IntervalEvent {
  const IntervalEvent();
}

class PhaseStarted extends IntervalEvent {
  const PhaseStarted(this.index, this.phase);
  final int index;
  final IntervalPhase phase;
}

class CountdownTick extends IntervalEvent {
  const CountdownTick(this.secondsLeft);
  final int secondsLeft;
}

class SessionFinished extends IntervalEvent {
  const SessionFinished();
}

/// Máquina de estados del temporizador, sin dependencias de UI ni de reloj
/// real (se avanza con [advance]), para que sea 100 % testeable.
class IntervalSession {
  IntervalSession(this.program) : assert(program.phases.isNotEmpty);

  final IntervalProgram program;

  int _index = 0;
  Duration _elapsed = Duration.zero;
  int? _lastAnnounced;
  bool _started = false;
  bool _finished = false;

  int get index => _index;
  bool get finished => _finished;
  IntervalPhase get phase => program.phases[_index];
  IntervalPhase? get nextPhase =>
      _index + 1 < program.phases.length ? program.phases[_index + 1] : null;
  Duration get elapsedInPhase => _elapsed;

  /// Segundos restantes de la fase (null en fases abiertas).
  int? get remainingSeconds {
    final total = phase.seconds;
    if (total == null) return null;
    final ms = total * 1000 - _elapsed.inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  /// 0 → 1 dentro de la fase actual.
  double get phaseProgress {
    final total = phase.seconds;
    if (total == null || total == 0) return 0;
    return (_elapsed.inMilliseconds / (total * 1000)).clamp(0.0, 1.0).toDouble();
  }

  List<IntervalEvent> start() {
    if (_started) return const [];
    _started = true;
    return [PhaseStarted(_index, phase)];
  }

  List<IntervalEvent> advance(Duration dt) {
    if (!_started || _finished) return const [];
    final events = <IntervalEvent>[];
    _elapsed += dt;

    while (!_finished) {
      final total = phase.seconds;
      if (total == null) break; // fase abierta: espera a skip()

      final remainingMs = total * 1000 - _elapsed.inMilliseconds;
      if (remainingMs > 0) {
        final secondsLeft = (remainingMs / 1000).ceil();
        final countFrom = total >= 8 ? 5 : 3;
        if (secondsLeft <= countFrom && secondsLeft != _lastAnnounced) {
          _lastAnnounced = secondsLeft;
          events.add(CountdownTick(secondsLeft));
        }
        break;
      }
      // Fase terminada: se arrastra el sobrante a la siguiente.
      final overflow = Duration(milliseconds: -remainingMs);
      events.addAll(_moveNext(overflow));
    }
    return events;
  }

  /// Pasa a la siguiente fase (botón "Siguiente" o fase abierta terminada).
  List<IntervalEvent> skip() {
    if (!_started || _finished) return const [];
    return _moveNext(Duration.zero);
  }

  List<IntervalEvent> _moveNext(Duration carry) {
    _lastAnnounced = null;
    if (_index + 1 >= program.phases.length) {
      _finished = true;
      _elapsed = Duration.zero;
      return const [SessionFinished()];
    }
    _index++;
    _elapsed = carry;
    return [PhaseStarted(_index, phase)];
  }
}
