import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../checkin/checkin_logic.dart';
import '../checkin/checkin_models.dart';
import '../onboarding/profile_controller.dart';
import '../plan/plan_controller.dart';
import '../plan/plan_models.dart';
import '../progress/muscle_group.dart';
import 'circuits.dart';
import 'interval_engine.dart';
import 'timer_screen.dart';

/// Pestaña Timer con dos modos:
/// * **Mi objetivo**: la sesión de hoy y circuitos diseñados para tu meta,
///   escalados a tu semana del plan.
/// * **Libre**: entrena lo que quieras hoy (gimnasio, calistenia, casa, HIIT,
///   boxeo, cardio, movilidad, core) sin depender del plan.
class TimerHomeScreen extends ConsumerStatefulWidget {
  const TimerHomeScreen({super.key});

  @override
  ConsumerState<TimerHomeScreen> createState() => _TimerHomeScreenState();
}

class _TimerHomeScreenState extends ConsumerState<TimerHomeScreen> {
  bool _goalMode = true;
  CircuitCategory? _category;

  int _work = 45;
  int _rest = 15;
  int _rounds = 8;

  static const _weekdays = [
    'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo',
  ];

  void _run(IntervalProgram program, TrainingDay? logDay) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TimerScreen(program: program, logDay: logDay),
    ));
  }

  TrainingDay _intervalDay(String name, int seconds) => TrainingDay(
        weekday: DateTime.now().weekday,
        title: name,
        focus: 'Intervalos',
        exercises: [
          Exercise(
            name: name,
            kind: ExerciseKind.cardio,
            sets: 1,
            reps: 'intervalos',
            restSec: 0,
            durationSec: seconds,
            muscles: const [
              MuscleGroup.quads,
              MuscleGroup.glutes,
              MuscleGroup.calves,
              MuscleGroup.abs,
            ],
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Timer')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.flag_outlined),
                    label: Text('Mi objetivo'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.explore_outlined),
                    label: Text('Libre'),
                  ),
                ],
                selected: {_goalMode},
                onSelectionChanged: (s) => setState(() => _goalMode = s.first),
              ),
            ),
          ),
          Expanded(child: _goalMode ? _goalView() : _freeView()),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ objetivo

  Widget _goalView() {
    final profile = ref.watch(profileProvider);
    final plan = ref.watch(planProvider).plan?.training;
    final checkins = ref.watch(checkinProvider);
    if (profile == null || plan == null) {
      return const Center(child: Text('Crea tu plan para ver circuitos de tu objetivo.'));
    }
    final now = DateTime.now();
    final week = CheckinLogic.effectiveWeek(plan, plan.weekNumberFor(now), checkins);
    final today = week.dayFor(now.weekday);
    final others = week.days
        .where((d) => !d.isRest && d.weekday != now.weekday)
        .toList();
    final circuits = GoalCircuits.forPlan(profile, plan, week);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        Text(
          plan.goalHeadline.isEmpty ? plan.title : plan.goalHeadline,
          style: const TextStyle(color: AurumColors.gold, fontWeight: FontWeight.w600),
        ),
        Text(
          'Semana ${week.number} de ${plan.totalWeeks} · ${week.phase}${week.deload ? ' · descarga' : ''}',
          style: const TextStyle(color: AurumColors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        _sectionTitle('Hoy en tu plan'),
        if (today == null || today.isRest)
          Card(
            child: ListTile(
              leading: const Icon(Icons.spa_outlined, color: AurumColors.rest),
              title: Text(today?.title ?? 'Descanso'),
              subtitle: const Text(
                  'Hoy no toca sesión fuerte. Si quieres moverte, prueba la movilidad de abajo o el modo Libre.'),
            ),
          )
        else
          _dayCard(today, highlight: true),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionTitle('Otras sesiones de esta semana'),
          for (final d in others) _dayCard(d),
        ],
        const SizedBox(height: 16),
        _sectionTitle('Circuitos para tu meta'),
        const Text(
          'Diseñados para tu objetivo y ajustados a la semana en la que vas.',
          style: TextStyle(color: AurumColors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        for (final c in circuits) _circuitCard(c),
      ],
    );
  }

  Widget _dayCard(TrainingDay d, {bool highlight = false}) {
    final timed = d.exercises.where((e) => e.durationSec != null).length;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: highlight ? AurumColors.gold : AurumColors.outline,
          width: highlight ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${highlight ? 'Hoy' : _weekdays[d.weekday - 1][0].toUpperCase() + _weekdays[d.weekday - 1].substring(1)} · ${d.title}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (d.focus.isNotEmpty)
              Text(d.focus, style: const TextStyle(color: AurumColors.textMuted, fontSize: 12)),
            const SizedBox(height: 6),
            Text(
              d.exercises.map((e) => e.name).join(' · '),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    timed == d.exercises.length
                        ? 'Por tiempo'
                        : 'Toca "siguiente" al terminar cada serie',
                    style: const TextStyle(color: AurumColors.textMuted, fontSize: 11),
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: () => _run(IntervalProgram.fromTrainingDay(d), d),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Empezar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- libre

  Widget _freeView() {
    final list = _category == null
        ? CircuitLibrary.all
        : CircuitLibrary.byCategory(_category!);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        const Text(
          '¿Hoy quieres entrenar otra cosa? Elige un circuito y listo. '
          'No cambia tu plan, y si lo registras al terminar también dora tu mapa.',
          style: TextStyle(color: AurumColors.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        _sectionTitle('Intervalos rápidos'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.bolt, size: 18),
              label: const Text('HIIT 40/20'),
              onPressed: () => _run(IntervalProgram.hiit(), _intervalDay('HIIT 40/20', 8 * 40)),
            ),
            ActionChip(
              avatar: const Icon(Icons.timer_outlined, size: 18),
              label: const Text('Tabata'),
              onPressed: () => _run(IntervalProgram.tabata(), _intervalDay('Tabata', 8 * 20)),
            ),
            ActionChip(
              avatar: const Icon(Icons.sports_mma, size: 18),
              label: const Text('Boxeo 3′'),
              onPressed: () => _run(IntervalProgram.boxing(), _intervalDay('Boxeo', 6 * 180)),
            ),
            ActionChip(
              avatar: const Icon(Icons.cable, size: 18),
              label: const Text('Cuerda'),
              onPressed: () => _run(IntervalProgram.jumpRope(), _intervalDay('Saltos de cuerda', 10 * 45)),
            ),
            ActionChip(
              avatar: const Icon(Icons.tune, size: 18),
              label: const Text('Personalizado'),
              onPressed: _customSheet,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _sectionTitle('Circuitos'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: const Text('Todos'),
                  selected: _category == null,
                  onSelected: (_) => setState(() => _category = null),
                ),
              ),
              for (final c in CircuitCategory.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    avatar: Icon(c.icon, size: 16),
                    label: Text(c.label),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = c),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        for (final c in list) _circuitCard(c),
      ],
    );
  }

  Widget _circuitCard(Circuit c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ExpansionTile(
          shape: const Border(),
          leading: CircleAvatar(
            backgroundColor: AurumColors.surfaceHigh,
            child: Icon(c.category.icon, color: AurumColors.gold, size: 20),
          ),
          title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            '~${c.estimatedMinutes} min · ${c.rounds} ${c.rounds == 1 ? 'ronda' : 'rondas'} · ${c.level}',
            style: const TextStyle(color: AurumColors.textMuted, fontSize: 12),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.description, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            for (final st in c.steps)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 6, color: AurumColors.gold),
                    const SizedBox(width: 8),
                    Expanded(child: Text(st.name, style: const TextStyle(fontSize: 13))),
                    Text(
                      st.seconds != null ? _secs(st.seconds!) : (st.reps ?? ''),
                      style: const TextStyle(color: AurumColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Text(
              'Descanso: ${c.restBetweenSteps} s entre ejercicios · ${c.restBetweenRounds} s entre rondas',
              style: const TextStyle(color: AurumColors.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: () => _run(c.toProgram(), c.toTrainingDay()),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Empezar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _secs(int s) =>
      s < 90 ? '$s s' : '${(s / 60).toStringAsFixed(s % 60 == 0 ? 0 : 1)} min';

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: Theme.of(context).textTheme.titleMedium),
      );

  Future<void> _customSheet() async {
    final start = await showModalBottomSheet<bool>(
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
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Empezar'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (start != true || !mounted) return;
    final name = 'Intervalos $_work/$_rest × $_rounds';
    _run(
      IntervalProgram.intervals(
        name: name,
        workSec: _work,
        restSec: _rest,
        rounds: _rounds,
      ),
      _intervalDay(name, _work * _rounds),
    );
  }
}
