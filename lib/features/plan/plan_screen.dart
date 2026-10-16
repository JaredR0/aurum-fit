import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
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
    await ref
        .read(planProvider.notifier)
        .generateWithAi(profile, request: request);
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

class _TrainingTab extends StatelessWidget {
  const _TrainingTab({required this.plan});

  final TrainingPlan plan;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().weekday;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(plan.title,
                          style: Theme.of(context).textTheme.titleLarge),
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
                const SizedBox(height: 8),
                Text(plan.summary,
                    style: const TextStyle(color: AurumColors.textMuted)),
                if (plan.progression.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Sobrecarga progresiva',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(plan.progression),
                ],
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
                          style: const TextStyle(
                              color: AurumColors.amber, fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (final day in plan.days)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ExpansionTile(
                initiallyExpanded: day.weekday == today,
                shape: const Border(),
                leading: CircleAvatar(
                  backgroundColor: day.weekday == today
                      ? AurumColors.gold
                      : AurumColors.surfaceHigh,
                  foregroundColor: day.weekday == today
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
