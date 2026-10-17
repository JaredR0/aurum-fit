import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../onboarding/profile_controller.dart';
import '../plan/plan_controller.dart';
import '../plan/plan_models.dart';
import '../progress/progress_engine.dart';
import 'benchmarks.dart';
import 'checkin_logic.dart';
import 'checkin_models.dart';
import 'checkin_screen.dart';

/// Pestaña "Logros": check-in semanal, preparación para la meta, récords,
/// insignias e historial.
class AchievementsTab extends ConsumerWidget {
  const AchievementsTab({super.key});

  static const _months = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];

  static String _date(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(planProvider).plan?.training;
    final profile = ref.watch(profileProvider);
    final checkins = ref.watch(checkinProvider);
    if (plan == null || profile == null) {
      return const Center(child: Text('Crea tu plan para empezar a medir logros.'));
    }

    final now = DateTime.now();
    final pending = CheckinLogic.pendingWeek(plan, checkins, now);
    final current = plan.weekNumberFor(now);
    final planCheckins = CheckinLogic.forPlan(plan, checkins);
    double? startWeight;
    for (final c in planCheckins) {
      if (c.bodyWeightKg != null) {
        startWeight = c.bodyWeightKg;
        break;
      }
    }
    final targets = CheckinLogic.targetProgress(plan, planCheckins,
        startWeightKg: startWeight ?? profile.weightKg);
    final readiness = CheckinLogic.readiness(targets);
    final records = CheckinLogic.records(checkins);
    final achievements =
        CheckinLogic.achievements(plan, planCheckins, targets, records, now);
    final unlocked = achievements.where((a) => a.unlocked).length;

    void open(int week) => Navigator.of(context).push(MaterialPageRoute<bool>(
          builder: (_) => CheckinScreen(week: week),
        ));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _CheckinCard(
          pending: pending,
          current: current,
          total: plan.totalWeeks,
          onOpen: open,
        ),
        const SizedBox(height: 16),
        _ReadinessCard(plan: plan, targets: targets, readiness: readiness),
        const SizedBox(height: 24),
        Text('Récords personales', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (records.isEmpty)
          const Text(
            'Aparecen cuando repites una prueba del check-in.',
            style: TextStyle(color: AurumColors.textMuted),
          )
        else
          for (final r in records)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                r.improvement > 0.001 ? Icons.trending_up : Icons.horizontal_rule,
                color: r.improvement > 0.001
                    ? ProgressEngine.colorFor(
                        (r.improvement / r.benchmark.fullScoreGain).clamp(0.3, 1.0).toDouble())
                    : AurumColors.textMuted,
              ),
              title: Text(r.benchmark.label),
              subtitle: Text(
                'Inicio ${r.benchmark.format(r.baseline)} → mejor ${r.benchmark.format(r.best)}'
                '${r.benchmark.input == BenchmarkInput.weightReps ? ' (1RM estimado)' : ''}',
              ),
              trailing: Text(
                r.improvement > 0.001 ? '+${(r.improvement * 100).round()} %' : '—',
                style: const TextStyle(
                    color: AurumColors.gold, fontWeight: FontWeight.w700),
              ),
            ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text('Insignias',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            Text('$unlocked de ${achievements.length}',
                style: const TextStyle(color: AurumColors.textMuted)),
          ],
        ),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.55,
          children: [for (final a in achievements) _AchievementTile(a: a)],
        ),
        const SizedBox(height: 24),
        Text('Historial', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (checkins.isEmpty)
          const Text('Aún no hay check-ins.',
              style: TextStyle(color: AurumColors.textMuted))
        else
          for (final c in checkins.reversed)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ExpansionTile(
                shape: const Border(),
                title: Text(c.isBaseline ? 'Evaluación inicial' : 'Semana ${c.week}'),
                subtitle: Text(
                  '${_date(c.date)} · energía ${c.energy}/5'
                  '${c.isBaseline ? '' : ' · ${c.sessionsDone}/${c.sessionsPlanned} sesiones'}'
                  '${c.pain ? ' · dolor' : ''}',
                  style: const TextStyle(color: AurumColors.textMuted, fontSize: 12),
                ),
                children: [
                  if (c.bodyWeightKg != null)
                    _historyRow('Peso', '${c.bodyWeightKg!.toStringAsFixed(1)} kg'),
                  for (final e in c.display.entries)
                    _historyRow(Benchmarks.byId(e.key)?.label ?? e.key, e.value),
                  if (c.painNote.isNotEmpty) _historyRow('Molestia', c.painNote),
                  if (c.note.isNotEmpty) _historyRow('Notas', c.note),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => open(c.week),
                        child: const Text('Rehacer este check-in'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  static Widget _historyRow(String label, String value) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: AurumColors.textMuted, fontSize: 13)),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ],
        ),
      );
}

class _CheckinCard extends StatelessWidget {
  const _CheckinCard({
    required this.pending,
    required this.current,
    required this.total,
    required this.onOpen,
  });

  final int? pending;
  final int current;
  final int total;
  final void Function(int week) onOpen;

  @override
  Widget build(BuildContext context) {
    final p = pending;
    final due = p != null;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: due ? AurumColors.gold : AurumColors.outline,
          width: due ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(due ? Icons.assignment_late_outlined : Icons.assignment_turned_in_outlined,
                    color: AurumColors.gold),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    !due
                        ? 'Check-in al día'
                        : (p == 0 ? 'Evaluación inicial pendiente' : 'Check-in de la semana $p'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              !due
                  ? 'Estás en la semana $current de $total. El próximo check-in se abre el sábado.'
                  : (p == 0
                      ? 'Mide tu punto de partida para que la app pueda contar tus logros.'
                      : 'Cuéntale a la app qué lograste: así se actualizan tu mapa, tus récords y la semana siguiente.'),
              style: const TextStyle(color: AurumColors.textMuted),
            ),
            const SizedBox(height: 12),
            if (due)
              FilledButton.icon(
                onPressed: () => onOpen(p!),
                icon: const Icon(Icons.edit_note),
                label: Text(p == 0 ? 'Hacer evaluación inicial' : 'Hacer check-in'),
              )
            else
              OutlinedButton.icon(
                onPressed: () => onOpen(current),
                icon: const Icon(Icons.edit_note),
                label: Text('Adelantar check-in de la semana $current'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({
    required this.plan,
    required this.targets,
    required this.readiness,
  });

  final TrainingPlan plan;
  final List<TargetProgress> targets;
  final double? readiness;

  @override
  Widget build(BuildContext context) {
    final r = readiness;
    final color = ProgressEngine.colorFor(r ?? 0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: r ?? 0,
                        strokeWidth: 6,
                        color: color,
                        backgroundColor: AurumColors.surfaceHigh,
                      ),
                      Center(
                        child: Text(
                          r == null ? '—' : '${(r * 100).round()}%',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16, color: color),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Preparación para tu meta',
                          style: TextStyle(color: AurumColors.textMuted, fontSize: 12)),
                      Text(
                        plan.goalHeadline.isEmpty ? plan.title : plan.goalHeadline,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (targets.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Tu objetivo se mide por constancia y por tus récords en las pruebas semanales.',
                  style: TextStyle(color: AurumColors.textMuted),
                ),
              ),
            for (final t in targets) _targetRow(t),
          ],
        ),
      ),
    );
  }

  Widget _targetRow(TargetProgress t) {
    final b = Benchmarks.byId(t.target.benchmarkId);
    String f(double v) => b?.format(v) ?? v.toStringAsFixed(0);
    final value = t.latest == null
        ? 'sin datos · meta ${f(t.target.target)}'
        : '${t.baseline != null && t.baseline != t.latest ? '${f(t.baseline!)} → ' : ''}'
            '${f(t.latest!)} / ${f(t.target.target)}';
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(t.target.label, style: const TextStyle(fontSize: 13))),
              Text(value, style: const TextStyle(color: AurumColors.textMuted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: t.fraction ?? 0,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
            color: ProgressEngine.colorFor(t.fraction ?? 0),
            backgroundColor: AurumColors.surfaceHigh,
          ),
        ],
      ),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({required this.a});

  final Achievement a;

  @override
  Widget build(BuildContext context) {
    final color = a.unlocked ? AurumColors.gold : AurumColors.textMuted;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: a.unlocked ? AurumColors.surfaceHigh : AurumColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: a.unlocked ? AurumColors.gold.withValues(alpha: 0.6) : AurumColors.outline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(a.unlocked ? a.icon : Icons.lock_outline, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  a.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: a.unlocked ? AurumColors.text : AurumColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Text(
              a.detail,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AurumColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
