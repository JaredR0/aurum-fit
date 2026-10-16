import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/input_sanitizer.dart';
import '../../core/theme/app_theme.dart';
import '../progress/workout_log.dart';
import 'plan_models.dart';

/// Registro de una sesión: series × repeticiones × kg (fuerza) o minutos/km
/// (cardio). Estos datos alimentan el algoritmo del mapa anatómico.
class SessionLogScreen extends ConsumerStatefulWidget {
  const SessionLogScreen({super.key, required this.day});

  final TrainingDay day;

  @override
  ConsumerState<SessionLogScreen> createState() => _SessionLogScreenState();
}

class _SetControllers {
  _SetControllers(String reps)
      : reps = TextEditingController(text: reps),
        kg = TextEditingController();
  final TextEditingController reps;
  final TextEditingController kg;
  void dispose() {
    reps.dispose();
    kg.dispose();
  }
}

class _ExerciseForm {
  _ExerciseForm(this.exercise)
      : sets = exercise.kind == ExerciseKind.cardio
            ? []
            : List.generate(
                exercise.sets, (_) => _SetControllers(_firstNumber(exercise.reps))),
        minutes = TextEditingController(
          text: exercise.durationSec == null
              ? ''
              : '${(exercise.durationSec! * exercise.sets / 60).round()}',
        ),
        km = TextEditingController(
          text: exercise.distanceKm == null
              ? ''
              : (exercise.distanceKm! * exercise.sets).toStringAsFixed(1),
        );

  final Exercise exercise;
  final List<_SetControllers> sets;
  final TextEditingController minutes;
  final TextEditingController km;
  bool done = true;

  static String _firstNumber(String reps) =>
      RegExp(r'\d+').firstMatch(reps)?.group(0) ?? '';

  void dispose() {
    for (final s in sets) {
      s.dispose();
    }
    minutes.dispose();
    km.dispose();
  }
}

class _SessionLogScreenState extends ConsumerState<SessionLogScreen> {
  late final List<_ExerciseForm> _forms =
      widget.day.exercises.map(_ExerciseForm.new).toList();
  bool _saving = false;

  @override
  void dispose() {
    for (final f in _forms) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final logged = <LoggedExercise>[];
    for (final f in _forms.where((f) => f.done)) {
      final e = f.exercise;
      if (e.kind == ExerciseKind.cardio) {
        final minutes = InputSanitizer.number(f.minutes.text, min: 0, max: 600);
        final km = InputSanitizer.number(f.km.text, min: 0, max: 200);
        if ((minutes ?? 0) == 0 && (km ?? 0) == 0) continue;
        logged.add(LoggedExercise(
          name: e.name,
          kind: e.kind,
          muscles: e.muscles,
          durationSec: minutes == null ? null : (minutes * 60).round(),
          distanceKm: km,
        ));
      } else {
        final sets = <SetEntry>[];
        for (final s in f.sets) {
          final reps = InputSanitizer.number(s.reps.text, min: 0, max: 500);
          final kg = InputSanitizer.number(
              s.kg.text.isEmpty ? '0' : s.kg.text, min: 0, max: 1000);
          if (reps != null && reps > 0) {
            sets.add(SetEntry(reps: reps.round(), weightKg: kg ?? 0));
          }
        }
        if (sets.isEmpty) continue;
        logged.add(LoggedExercise(
          name: e.name,
          kind: e.kind,
          muscles: e.muscles,
          sets: sets,
          durationSec: e.durationSec,
        ));
      }
    }

    if (logged.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registra al menos un ejercicio.')),
      );
      return;
    }

    setState(() => _saving = true);
    final now = DateTime.now();
    await ref.read(workoutLogProvider.notifier).add(WorkoutSession(
          id: now.microsecondsSinceEpoch.toString(),
          date: now,
          title: widget.day.title,
          exercises: logged,
        ));
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Registrar · ${widget.day.title}')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        itemCount: _forms.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _exerciseCard(_forms[i]),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check),
            label: const Text('Guardar sesión'),
          ),
        ),
      ),
    );
  }

  Widget _numField(TextEditingController c, String label, {bool decimal = false}) =>
      Expanded(
        child: TextField(
          controller: c,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.,]' : r'[0-9]')),
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: InputDecoration(labelText: label, isDense: true),
        ),
      );

  Widget _exerciseCard(_ExerciseForm f) {
    final e = f.exercise;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: f.done,
                  onChanged: (v) => setState(() => f.done = v ?? false),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(e.prescription,
                          style: const TextStyle(
                              color: AurumColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            if (f.done) ...[
              const SizedBox(height: 8),
              if (e.kind == ExerciseKind.cardio)
                Row(children: [
                  _numField(f.minutes, 'Minutos', decimal: true),
                  const SizedBox(width: 12),
                  _numField(f.km, 'Km', decimal: true),
                ])
              else
                for (var i = 0; i < f.sets.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      SizedBox(
                        width: 56,
                        child: Text('Serie ${i + 1}',
                            style: const TextStyle(color: AurumColors.textMuted)),
                      ),
                      _numField(f.sets[i].reps, 'Reps'),
                      const SizedBox(width: 12),
                      _numField(f.sets[i].kg, 'Kg (0 = corporal)', decimal: true),
                    ]),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}
