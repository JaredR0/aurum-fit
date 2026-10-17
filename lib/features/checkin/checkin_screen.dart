import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/input_sanitizer.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/units.dart';
import '../notifications/notification_service.dart';
import '../onboarding/profile_controller.dart';
import '../onboarding/user_profile.dart';
import '../plan/goal_analyzer.dart';
import '../plan/plan_controller.dart';
import '../progress/workout_log.dart';
import '../steps/step_service.dart';
import 'benchmarks.dart';
import 'checkin_logic.dart';
import 'checkin_models.dart';

/// Check-in semanal: qué lograste esta semana. Con esto se calculan tus
/// récords, la preparación para tu meta y el color del mapa del cuerpo.
class CheckinScreen extends ConsumerStatefulWidget {
  const CheckinScreen({super.key, required this.week});

  /// Semana del plan que se cierra (0 = evaluación inicial).
  final int week;

  @override
  ConsumerState<CheckinScreen> createState() => _CheckinScreenState();
}

class _Inputs {
  _Inputs(this.benchmark);
  final Benchmark benchmark;
  final TextEditingController a = TextEditingController();
  final TextEditingController b = TextEditingController();
  void dispose() {
    a.dispose();
    b.dispose();
  }
}

class _CheckinScreenState extends ConsumerState<CheckinScreen> {
  final Map<String, _Inputs> _inputs = {};
  final _weight = TextEditingController();
  final _painNote = TextEditingController();
  final _note = TextEditingController();
  int _energy = 3;
  bool _pain = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final i in _inputs.values) {
      i.dispose();
    }
    _weight.dispose();
    _painNote.dispose();
    _note.dispose();
    super.dispose();
  }

  _Inputs _inputsFor(Benchmark b) => _inputs.putIfAbsent(b.id, () => _Inputs(b));

  /// "5:40" → 340 s; "5.5" → 330 s.
  double? _parseTime(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    if (t.contains(':')) {
      final parts = t.split(':');
      final m = int.tryParse(parts[0]);
      final s = int.tryParse(parts.length > 1 ? parts[1] : '0');
      if (m == null || s == null || s >= 60) return null;
      final total = m * 60 + s;
      return total > 0 && total < 6 * 3600 ? total.toDouble() : null;
    }
    final minutes = InputSanitizer.number(t, min: 0.5, max: 300);
    return minutes == null ? null : (minutes * 60).roundToDouble();
  }

  Future<void> _save(UserProfile profile, List<Benchmark> benchmarks,
      int sessionsDone, int sessionsPlanned, int stepDays) async {
    final values = <String, double>{};
    final display = <String, String>{};

    for (final b in benchmarks) {
      final i = _inputsFor(b);
      switch (b.input) {
        case BenchmarkInput.number:
          if (i.a.text.trim().isEmpty) break;
          final v = InputSanitizer.number(i.a.text, min: 0, max: 100000);
          if (v == null) {
            setState(() => _error = 'Revisa el valor de "${b.label}".');
            return;
          }
          values[b.id] = v;
          display[b.id] = b.format(v);
        case BenchmarkInput.weightReps:
          if (i.a.text.trim().isEmpty && i.b.text.trim().isEmpty) break;
          final kg = InputSanitizer.number(i.a.text, min: 1, max: 500);
          final reps = InputSanitizer.number(i.b.text, min: 1, max: 30)?.round();
          if (kg == null || reps == null) {
            setState(() => _error = 'En "${b.label}" escribe peso y repeticiones (1–30).');
            return;
          }
          final oneRm = Benchmark.epley(kg, reps);
          values[b.id] = double.parse(oneRm.toStringAsFixed(1));
          display[b.id] = '${kg.toStringAsFixed(kg == kg.roundToDouble() ? 0 : 1)} kg × $reps';
        case BenchmarkInput.time:
          if (i.a.text.trim().isEmpty) break;
          final s = _parseTime(i.a.text);
          if (s == null) {
            setState(() => _error = 'En "${b.label}" usa el formato mm:ss (por ejemplo 5:40).');
            return;
          }
          values[b.id] = s;
          display[b.id] = b.format(s);
      }
    }

    double? weightKg;
    if (_weight.text.trim().isNotEmpty) {
      final imperial = profile.units == UnitSystem.imperial;
      final v = InputSanitizer.number(_weight.text,
          min: imperial ? 66 : 30, max: imperial ? 660 : 300);
      if (v == null) {
        setState(() => _error = 'Revisa tu peso.');
        return;
      }
      weightKg = imperial ? Units.lbToKg(v) : v;
    }

    final pain = InputSanitizer.clean(_painNote.text, maxLength: 200);
    final note = InputSanitizer.clean(_note.text, maxLength: 300);

    setState(() {
      _saving = true;
      _error = null;
    });

    final previous = ref.read(checkinProvider);
    final now = DateTime.now();
    final checkin = WeeklyCheckin(
      id: now.microsecondsSinceEpoch.toString(),
      week: widget.week,
      date: now,
      values: values,
      display: display,
      bodyWeightKg: weightKg == null ? null : double.parse(weightKg.toStringAsFixed(1)),
      energy: _energy,
      pain: _pain,
      painNote: pain.text,
      sessionsDone: sessionsDone,
      sessionsPlanned: sessionsPlanned,
      stepDays: stepDays,
      note: note.text,
    );
    await ref.read(checkinProvider.notifier).save(checkin);
    if (weightKg != null) {
      await ref.read(profileProvider.notifier).save(profile.copyWith(weightKg: weightKg));
    }
    // Tras la evaluación inicial se activa el recordatorio del sábado.
    final reminders = NotificationService.loadSettings();
    if (widget.week == 0 && !reminders.checkin) {
      final granted = await NotificationService.requestPermission();
      if (granted) {
        final updated = reminders.copyWith(checkin: true);
        await NotificationService.saveSettings(updated);
        await NotificationService.reschedule(updated, ref.read(planProvider).plan);
      }
    }
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    await _showSummary(checkin, previous, benchmarks);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _showSummary(
    WeeklyCheckin c,
    List<WeeklyCheckin> previous,
    List<Benchmark> benchmarks,
  ) {
    final lines = <(String, String, bool?)>[];
    for (final b in [...benchmarks, Benchmarks.byId('body_kg')!]) {
      final now = c.value(b.id);
      if (now == null) continue;
      double? before;
      for (final p in previous) {
        final v = p.value(b.id);
        if (v != null && p.week != c.week) before = v;
      }
      if (before == null) {
        lines.add((b.label, b.format(now), null));
      } else {
        final imp = b.improvement(before, now);
        lines.add((
          b.label,
          '${b.format(before)} → ${b.format(now)}',
          imp.abs() < 0.005 ? null : (b.id == 'body_kg' ? null : imp > 0),
        ));
      }
    }

    final String advice;
    if (c.isBaseline) {
      advice = 'Este es tu punto de partida. Cada semana repetirás estas pruebas para ver tu avance.';
    } else if (c.recommendsDeload) {
      advice = c.pain
          ? 'Reportaste dolor: la semana ${c.week + 1} se ajustó a descarga. Si persiste, consulta a un profesional.'
          : 'Reportaste poca energía: la semana ${c.week + 1} se ajustó a descarga para recuperarte.';
    } else if (c.sessionsPlanned > 0 && c.sessionsDone * 2 < c.sessionsPlanned) {
      advice = 'Completaste ${c.sessionsDone} de ${c.sessionsPlanned} sesiones. Esta semana mantén las mismas cargas antes de subir.';
    } else {
      advice = '¡Buen trabajo! Sigue con la progresión de la semana ${c.week + 1}.';
    }

    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(c.isBaseline ? 'Evaluación guardada' : 'Semana ${c.week} cerrada'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (label, value, better) in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        better == null
                            ? Icons.remove
                            : (better ? Icons.trending_up : Icons.trending_down),
                        size: 18,
                        color: better == null
                            ? AurumColors.textMuted
                            : (better ? AurumColors.gold : AurumColors.danger),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
                      Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text(advice, style: const TextStyle(color: AurumColors.textMuted)),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Listo'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final plan = ref.watch(planProvider).plan?.training;
    if (profile == null || plan == null) return const Scaffold();

    final checkins = ref.watch(checkinProvider);
    final sessions = ref.watch(workoutLogProvider);
    final steps = ref.watch(stepProvider);
    final spec = GoalAnalyzer.analyze(profile);
    final benchmarks = Benchmarks.forProfile(profile, spec.type);
    final week = widget.week;
    final baseline = week == 0;

    final planned = baseline
        ? 0
        : CheckinLogic.effectiveWeek(plan, week, checkins).sessions;
    final done = CheckinLogic.sessionsInWeek(plan, week, sessions);
    var stepDays = 0;
    if (!baseline) {
      final start = CheckinLogic.weekStart(plan, week);
      for (var i = 0; i < 7; i++) {
        final d = start.add(Duration(days: i));
        if ((steps.history[Units.dayKey(d)] ?? 0) >= profile.dailyStepGoal) stepDays++;
      }
    }

    Map<String, String> lastDisplay = {};
    for (final c in checkins) {
      if (c.week != week) lastDisplay = {...lastDisplay, ...c.display};
    }
    final imperial = profile.units == UnitSystem.imperial;

    return Scaffold(
      appBar: AppBar(
        title: Text(baseline ? 'Evaluación inicial' : 'Check-in · semana $week'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: baseline
                  ? const Text(
                      'Mide tu punto de partida. Haz las pruebas que puedas esta semana '
                      'y escribe el resultado. Cada semana las repetirás para ver cuánto '
                      'avanzas: con eso se doran los músculos del mapa y se calcula tu '
                      'preparación para la meta.',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Resumen automático de la semana $week',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        _summaryRow(Icons.fitness_center,
                            'Sesiones registradas', '$done de $planned'),
                        _summaryRow(Icons.directions_walk,
                            'Días con meta de pasos', '$stepDays de 7'),
                        if (done < planned)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text(
                              '¿Entrenaste sin registrarlo? Regístralo en Plan → Registrar para que cuente.',
                              style: TextStyle(color: AurumColors.textMuted, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          _section('Peso corporal'),
          TextField(
            controller: _weight,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: InputDecoration(
              labelText: 'Peso de hoy (opcional)',
              suffixText: imperial ? 'lb' : 'kg',
              helperText: 'Actual en tu perfil: ${imperial ? '${Units.kgToLb(profile.weightKg).toStringAsFixed(1)} lb' : '${profile.weightKg.toStringAsFixed(1)} kg'}',
            ),
          ),
          _section(baseline ? 'Pruebas de tu objetivo' : '¿Qué lograste esta semana?'),
          Text(
            spec.headline,
            style: const TextStyle(color: AurumColors.gold, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            'Deja vacío lo que no hayas hecho.',
            style: TextStyle(color: AurumColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          for (final b in benchmarks) _benchmarkCard(b, lastDisplay[b.id]),
          _section('¿Cómo te sentiste?'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (v, label) in const [
                (1, '😫 Agotado'),
                (2, '😕 Cansado'),
                (3, '😐 Normal'),
                (4, '🙂 Bien'),
                (5, '💪 Excelente'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _energy == v,
                  onSelected: (_) => setState(() => _energy = v),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _pain,
            onChanged: (v) => setState(() => _pain = v),
            title: const Text('Tuve dolor o molestia'),
            subtitle: const Text('Ajusta la semana siguiente a descarga'),
          ),
          if (_pain)
            TextField(
              controller: _painNote,
              maxLength: 200,
              decoration: const InputDecoration(labelText: '¿Dónde y cuándo?'),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            maxLength: 300,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notas (opcional)'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: AurumColors.danger)),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _saving
                ? null
                : () => _save(profile, benchmarks, done, planned, stepDays),
            icon: const Icon(Icons.check),
            label: Text(baseline ? 'Guardar evaluación' : 'Cerrar semana $week'),
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AurumColors.gold),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _numField(TextEditingController c, String label,
          {String? suffix, bool decimal = true, bool time = false}) =>
      TextField(
        controller: c,
        keyboardType: time
            ? TextInputType.datetime
            : TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
              RegExp(time ? r'[0-9:.,]' : (decimal ? r'[0-9.,]' : r'[0-9]'))),
          LengthLimitingTextInputFormatter(7),
        ],
        decoration: InputDecoration(labelText: label, suffixText: suffix, isDense: true),
      );

  Widget _benchmarkCard(Benchmark b, String? last) {
    final i = _inputsFor(b);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(b.label, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(b.hint,
                  style: const TextStyle(color: AurumColors.textMuted, fontSize: 12)),
              if (last != null)
                Text('Anterior: $last',
                    style: const TextStyle(color: AurumColors.amber, fontSize: 12)),
              const SizedBox(height: 10),
              switch (b.input) {
                BenchmarkInput.weightReps => Row(
                    children: [
                      Expanded(child: _numField(i.a, 'Peso', suffix: 'kg')),
                      const SizedBox(width: 12),
                      Expanded(child: _numField(i.b, 'Repeticiones', decimal: false)),
                    ],
                  ),
                BenchmarkInput.time =>
                  _numField(i.a, 'Tiempo (mm:ss)', time: true),
                BenchmarkInput.number => _numField(i.a, 'Resultado',
                    suffix: b.unit.isEmpty ? null : b.unit,
                    decimal: b.decimals > 0),
              },
            ],
          ),
        ),
      ),
    );
  }
}
