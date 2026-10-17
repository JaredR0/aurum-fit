import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../checkin/checkin_logic.dart';
import '../checkin/checkin_models.dart';
import '../onboarding/profile_controller.dart';
import '../timer/interval_engine.dart';
import '../timer/timer_screen.dart';
import 'plan_api.dart';
import 'plan_controller.dart';
import 'plan_models.dart';
import 'session_log_screen.dart';

const _weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  Future<void> _askAi(BuildContext context, WidgetRef ref) async {
    final profile = ref.read(profileProvider);
    if (profile == null) return;

    if (!PlanApi.isConfigured) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('IA no configurada'),
          content: const Text(
            'Esta compilación no tiene la URL del proxy de IA (PROXY_URL). '
            'Sigue usando el plan local o revisa el README para activarla.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }

    final controller = TextEditingController();
    final request = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generar plan con IA'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'La IA busca evidencia científica y arma tu rutina y dieta. '
              'Solo se envían datos anónimos: edad, sexo, medidas, nivel, equipo, '
              'lesiones y objetivo. Nunca fotos, nombre ni ubicación.',
              style: TextStyle(color: AurumColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLength: 300,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Preferencias (opcional)',
                hintText: 'Ej.: solo 45 min por sesión, no como cerdo…',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Generar'),
          ),
        ],
      ),
    );
    // No se hace dispose aquí: el diálogo aún anima su salida con este controller.
    if (request == null) return;
    final progress =
        CheckinLogic.firstAndLast(ref.read(checkinProvider)).last;
    await ref
        .read(planProvider.notifier)
        .generateWithAi(profile, request: request, progress: progress);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(planProvider);
    final plan = state.plan;

    ref.listen<PlanState>(planProvider, (prev, next) {
      final msg = next.message;
      if (msg != null && msg != prev?.message) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        ref.read(planProvider.notifier).clearMessage();
      }
    });

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mi plan'),
          actions: [
            IconButton(
              tooltip: 'Generar con IA',
              onPressed: state.loading ? null : () => _askAi(context, ref),
              icon: const Icon(Icons.auto_awesome),
            ),
          ],
          bottom: const TabBar(
            tabs: [Tab(text: 'Entrenamiento'), Tab(text: 'Nutrición')],
          ),
        ),
        body: Column(
          children: [
            if (state.loading) const LinearProgressIndicator(),
            Expanded(
              child: plan == null
                  ? Center(
                      child: FilledButton(
                        onPressed: () {
                          final p = ref.read(profileProvider);
                          if (p != null) {
                            ref.read(planProvider.notifier).generateLocal(p);
                          }
                        },
                        child: const Text('Crear plan'),
                      ),
                    )
                  : TabBarView(
                      children: [
                        _TrainingTab(plan: plan.training),
                        _NutritionTab(plan: plan.nutrition),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrainingTab extends ConsumerStatefulWidget {
  const _TrainingTab({required this.plan});

  final TrainingPlan plan;

  @override
  ConsumerState<_TrainingTab> createState() => _TrainingTabState();
}

class _TrainingTabState extends ConsumerState<_TrainingTab> {
  int? _week;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final checkins = ref.watch(checkinProvider);
    final now = DateTime.now();
    final currentWeek = plan.weekNumberFor(now);
    final weekNumber = (_week ?? currentWeek).clamp(1, plan.totalWeeks).toInt();
    final week = CheckinLogic.effectiveWeek(plan, weekNumber, checkins);
    final isCurrent = weekNumber == currentWeek;
    final today = now.weekday;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _goalCard(context, plan),
        const SizedBox(height: 16),
        _phaseStrip(plan, weekNumber),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Semana anterior',
                      onPressed: weekNumber > 1
                          ? () => setState(() => _week = weekNumber - 1)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            'Semana $weekNumber de ${plan.totalWeeks}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${week.phase}${isCurrent ? ' · esta semana' : ''}',
                            style: const TextStyle(color: AurumColors.gold, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Semana siguiente',
                      onPressed: weekNumber < plan.totalWeeks
                          ? () => setState(() => _week = weekNumber + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                if (week.deload)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Chip(
                      avatar: Icon(Icons.battery_charging_full, size: 16, color: AurumColors.rest),
                      label: Text('Semana de descarga'),
                    ),
                  ),
                if (week.focus.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Text(
                      week.focus,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AurumColors.textMuted, fontSize: 13),
                    ),
                  ),
                if (!isCurrent)
                  TextButton(
                    onPressed: () => setState(() => _week = null),
                    child: const Text('Volver a esta semana'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final day in week.days)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ExpansionTile(
                key: PageStorageKey('w$weekNumber-d${day.weekday}'),
                initiallyExpanded: isCurrent && day.weekday == today,
                shape: const Border(),
                leading: CircleAvatar(
                  backgroundColor: isCurrent && day.weekday == today
                      ? AurumColors.gold
                      : AurumColors.surfaceHigh,
                  foregroundColor: isCurrent && day.weekday == today
                      ? AurumColors.background
                      : AurumColors.text,
                  child: Text(_weekdays[day.weekday - 1],
                      style: const TextStyle(fontSize: 12)),
                ),
                title: Text(day.title),
                subtitle: Text(
                  [
                    if (day.focus.isNotEmpty) day.focus,
                    if (day.requiresStepGoal) 'requiere meta de pasos',
                  ].join(' · '),
                  style: const TextStyle(color: AurumColors.textMuted, fontSize: 12),
                ),
                children: [
                  for (final e in day.exercises)
                    ListTile(
                      dense: true,
                      title: Text(e.name),
                      subtitle: Text(
                        [e.prescription, if (e.notes.isNotEmpty) e.notes].join('\n'),
                      ),
                    ),
                  if (day.exercises.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => TimerScreen(
                                    program: IntervalProgram.fromTrainingDay(day),
                                    logDay: day,
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.timer_outlined),
                              label: const Text('Circuito guiado'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(40)),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<bool>(
                                  builder: (_) => SessionLogScreen(day: day),
                                ),
                              ),
                              icon: const Icon(Icons.edit_note),
                              label: const Text('Registrar'),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (plan.progression.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Cómo progresa tu plan',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(plan.progression,
                      style: const TextStyle(color: AurumColors.textMuted)),
                ],
              ),
            ),
          ),
        if (plan.references.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Evidencia consultada',
              style: TextStyle(fontWeight: FontWeight.w600)),
          for (final r in plan.references)
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: r));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enlace copiado')),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  r,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AurumColors.amber, fontSize: 12),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _goalCard(BuildContext context, TrainingPlan plan) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan.goalHeadline.isEmpty ? plan.title : plan.goalHeadline,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(
                    plan.source == 'ai' ? Icons.auto_awesome : Icons.offline_bolt,
                    size: 16,
                    color: AurumColors.gold,
                  ),
                  label: Text(plan.source == 'ai' ? 'IA' : 'Local'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(plan.title, style: const TextStyle(color: AurumColors.gold)),
            const SizedBox(height: 8),
            for (final f in plan.goalFacts)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6, right: 8),
                      child: Icon(Icons.circle, size: 6, color: AurumColors.gold),
                    ),
                    Expanded(child: Text(f, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
            if (plan.summary.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(plan.summary,
                  style: const TextStyle(color: AurumColors.textMuted, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  /// Barra con las fases del plan y la semana visible marcada.
  Widget _phaseStrip(TrainingPlan plan, int weekNumber) {
    final phases = <({String name, int from, int count})>[];
    for (final w in plan.weeks) {
      if (phases.isEmpty || phases.last.name != w.phase) {
        phases.add((name: w.phase, from: w.number, count: 1));
      } else {
        final last = phases.removeLast();
        phases.add((name: last.name, from: last.from, count: last.count + 1));
      }
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final ph in phases)
          Expanded(
            flex: ph.count,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: weekNumber >= ph.from && weekNumber < ph.from + ph.count
                          ? AurumColors.gold
                          : (weekNumber >= ph.from + ph.count
                              ? AurumColors.bronze
                              : AurumColors.surfaceHigh),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ph.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: weekNumber >= ph.from && weekNumber < ph.from + ph.count
                          ? AurumColors.gold
                          : AurumColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _NutritionTab extends StatefulWidget {
  const _NutritionTab({required this.plan});

  final NutritionPlan plan;

  @override
  State<_NutritionTab> createState() => _NutritionTabState();
}

class _NutritionTabState extends State<_NutritionTab> {
  int _weekday = DateTime.now().weekday;

  Widget _macro(String label, String value, Color color) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: color)),
            Text(label,
                style: const TextStyle(fontSize: 12, color: AurumColors.textMuted)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    NutritionDay? day;
    for (final d in plan.days) {
      if (d.weekday == _weekday) day = d;
    }
    day ??= plan.days.first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                _macro('kcal', '${plan.calories}', AurumColors.gold),
                _macro('proteína', '${plan.proteinG} g', AurumColors.goldBright),
                _macro('carbohidratos', '${plan.carbsG} g', AurumColors.amber),
                _macro('grasas', '${plan.fatG} g', AurumColors.bronze),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var w = 1; w <= 7; w++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(_weekdays[w - 1]),
                    selected: _weekday == w,
                    onSelected: (_) => setState(() => _weekday = w),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final m in day.meals)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('${m.time} · ${m.slot.label}',
                            style: const TextStyle(
                                color: AurumColors.gold,
                                fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('${m.kcal} kcal',
                            style: const TextStyle(color: AurumColors.textMuted)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(m.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (m.description.isNotEmpty)
                      Text(m.description,
                          style: const TextStyle(
                              color: AurumColors.textMuted, fontSize: 13)),
                    const SizedBox(height: 6),
                    Text('P ${m.proteinG} g · C ${m.carbsG} g · G ${m.fatG} g',
                        style: const TextStyle(fontSize: 12)),
                    if (m.alternatives.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('Alternativas: ${m.alternatives.join(' / ')}',
                          style: const TextStyle(
                              color: AurumColors.textMuted, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        for (final n in plan.notes)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('• $n',
                style: const TextStyle(color: AurumColors.textMuted, fontSize: 12)),
          ),
      ],
    );
  }
}
