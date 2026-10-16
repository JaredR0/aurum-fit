import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme/app_theme.dart';
import 'interval_engine.dart';
import 'voice_coach.dart';

/// Asistente de circuito / HIIT / boxeo con números gigantes, voz, tonos y
/// vibración. Mantiene la pantalla encendida mientras corre.
class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key, this.program});

  /// Si viene de un día del plan, se usa ese circuito.
  final IntervalProgram? program;

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  final VoiceCoach _coach = VoiceCoach();
  late IntervalProgram _program = widget.program ?? IntervalProgram.hiit();
  IntervalSession? _session;
  Timer? _ticker;
  final Stopwatch _clock = Stopwatch();
  Duration _lastTick = Duration.zero;
  bool _running = false;

  // Configuración del modo personalizado
  int _work = 45;
  int _rest = 15;
  int _rounds = 8;

  @override
  void initState() {
    super.initState();
    _coach.init();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _coach.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  void _select(IntervalProgram p) {
    _stop();
    setState(() => _program = p);
  }

  void _start() {
    final session = _session ?? IntervalSession(_program);
    final isNew = _session == null;
    _session = session;
    _running = true;
    _clock.start();
    _lastTick = _clock.elapsed;
    WakelockPlus.enable();
    if (isNew) _handle(session.start());
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    setState(() {});
  }

  void _pause() {
    _ticker?.cancel();
    _clock.stop();
    _running = false;
    _coach.stop();
    WakelockPlus.disable();
    setState(() {});
  }

  void _stop() {
    _ticker?.cancel();
    _clock
      ..stop()
      ..reset();
    _lastTick = Duration.zero;
    _running = false;
    _session = null;
    _coach.stop();
    WakelockPlus.disable();
    if (mounted) setState(() {});
  }

  void _tick() {
    final now = _clock.elapsed;
    final dt = now - _lastTick;
    _lastTick = now;
    final s = _session;
    if (s == null) return;
    _handle(s.advance(dt));
    if (mounted) setState(() {});
  }

  void _skip() {
    final s = _session;
    if (s == null) return;
    _handle(s.skip());
    setState(() {});
  }

  void _handle(List<IntervalEvent> events) {
    for (final e in events) {
      switch (e) {
        case PhaseStarted(:final phase):
          _coach.phaseChange(work: phase.kind == PhaseKind.work);
          _coach.say(phase.spoken);
        case CountdownTick(:final secondsLeft):
          _coach.countdown(secondsLeft);
        case SessionFinished():
          _coach.phaseChange(work: false);
          _coach.say('¡Sesión completada! Buen trabajo.');
          _ticker?.cancel();
          _clock.stop();
          _running = false;
          WakelockPlus.disable();
      }
    }
  }

  Color _phaseColor(IntervalPhase? p) => switch (p?.kind) {
        PhaseKind.work => AurumColors.work,
        PhaseKind.rest => AurumColors.rest,
        _ => AurumColors.textMuted,
      };

  String _fmt(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return m > 0 ? '$m:${s.toString().padLeft(2, '0')}' : '$s';
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    final phase = s?.phase;
    final color = _phaseColor(phase);
    final finished = s?.finished ?? false;

    final bigText = s == null
        ? _fmt(_program.phases.first.seconds ?? 0)
        : finished
            ? '✓'
            : (s.remainingSeconds != null
                ? _fmt(s.remainingSeconds!)
                : _fmt(s.elapsedInPhase.inSeconds));

    return Scaffold(
      appBar: AppBar(
        title: Text(_program.name),
        actions: [
          IconButton(
            tooltip: 'Voz',
            icon: Icon(_coach.voiceEnabled
                ? Icons.record_voice_over
                : Icons.voice_over_off),
            onPressed: () =>
                setState(() => _coach.voiceEnabled = !_coach.voiceEnabled),
          ),
          IconButton(
            tooltip: 'Tonos',
            icon: Icon(_coach.beepEnabled
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined),
            onPressed: () =>
                setState(() => _coach.beepEnabled = !_coach.beepEnabled),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (widget.program == null && s == null) _presets(),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        finished
                            ? 'Completado'
                            : (phase?.label ?? 'Listo para empezar'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 280,
                      height: 280,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CircularProgressIndicator(
                            value: s == null || finished ? 0 : s.phaseProgress,
                            strokeWidth: 10,
                            color: color,
                            backgroundColor: AurumColors.surfaceHigh,
                          ),
                          Center(
                            child: FittedBox(
                              child: Padding(
                                padding: const EdgeInsets.all(28),
                                child: Text(
                                  bigText,
                                  style: TextStyle(
                                    fontSize: 120,
                                    fontWeight: FontWeight.w800,
                                    color: color,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (phase != null && phase.seconds == null && !finished)
                      const Text(
                        'Fase libre: toca "Siguiente" al terminar',
                        style: TextStyle(color: AurumColors.textMuted),
                      ),
                    if (s?.nextPhase != null && !finished)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Siguiente: ${s!.nextPhase!.label}',
                          style: const TextStyle(color: AurumColors.textMuted),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton.filledTonal(
                    iconSize: 32,
                    tooltip: 'Detener',
                    onPressed: s == null ? null : _stop,
                    icon: const Icon(Icons.stop),
                  ),
                  SizedBox(
                    width: 88,
                    height: 88,
                    child: IconButton.filled(
                      iconSize: 44,
                      tooltip: _running ? 'Pausa' : 'Iniciar',
                      onPressed: finished
                          ? _stop
                          : (_running ? _pause : _start),
                      icon: Icon(finished
                          ? Icons.replay
                          : (_running ? Icons.pause : Icons.play_arrow)),
                    ),
                  ),
                  IconButton.filledTonal(
                    iconSize: 32,
                    tooltip: 'Siguiente',
                    onPressed: s == null || finished ? null : _skip,
                    icon: const Icon(Icons.skip_next),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _presets() {
    final presets = <(String, IntervalProgram Function())>[
      ('HIIT 40/20', IntervalProgram.hiit),
      ('Tabata', IntervalProgram.tabata),
      ('Boxeo 3′', () => IntervalProgram.boxing()),
      ('Cuerda', IntervalProgram.jumpRope),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final (label, build) in presets)
            ChoiceChip(
              label: Text(label),
              selected: _program.name == build().name,
              onSelected: (_) => _select(build()),
            ),
          ActionChip(
            avatar: const Icon(Icons.tune, size: 18),
            label: const Text('Personalizado'),
            onPressed: _customSheet,
          ),
        ],
      ),
    );
  }

  Future<void> _customSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          Widget stepper(String label, int value, int step, int min, int max,
                  ValueChanged<int> onChanged) =>
              ListTile(
                title: Text(label),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: value - step >= min
                          ? () => setSheet(() => onChanged(value - step))
                          : null,
                    ),
                    SizedBox(
                      width: 48,
                      child: Text('$value',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: value + step <= max
                          ? () => setSheet(() => onChanged(value + step))
                          : null,
                    ),
                  ],
                ),
              );

          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                stepper('Trabajo (s)', _work, 5, 5, 600, (v) => _work = v),
                stepper('Descanso (s)', _rest, 5, 0, 300, (v) => _rest = v),
                stepper('Rondas', _rounds, 1, 1, 50, (v) => _rounds = v),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton(
                    onPressed: () {
                      _select(IntervalProgram.intervals(
                        name: 'Personalizado $_work/$_rest × $_rounds',
                        workSec: _work,
                        restSec: _rest,
                        rounds: _rounds,
                      ));
                      Navigator.of(context).pop();
                    },
                    child: const Text('Usar este intervalo'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
