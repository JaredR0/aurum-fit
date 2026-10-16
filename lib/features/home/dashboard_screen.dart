import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../hydration/hydration_controller.dart';
import '../onboarding/profile_controller.dart';
import '../plan/plan_controller.dart';
import '../plan/plan_models.dart';
import '../plan/session_log_screen.dart';
import '../progress/progress_engine.dart';
import '../progress/workout_log.dart';
import '../steps/step_service.dart';
import 'settings_screen.dart';

/// Pantalla "Hoy": entrenamiento del día, pasos, agua, próxima comida y nivel.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Los permisos de sensores se piden aquí, con contexto, no al instalar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(stepProvider.notifier).start();
      ref.read(hydrationProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final plan = ref.watch(planProvider).plan;
    final steps = ref.watch(stepProvider);
    final water = ref.watch(hydrationProvider);
    final sessions = ref.watch(workoutLogProvider);
    final overall = ProgressEngine.overall(ref.watch(progressProvider));

    final now = DateTime.now();
    final day = plan?.training.dayFor(now);
    final trainedToday = sessions.any((s) =>
        s.date.year == now.year &&
        s.date.month == now.month &&
        s.date.day == now.day);
    final stepGoal = profile?.dailyStepGoal ?? 10000;
    final waterGoal = profile?.effectiveWaterGoalMl ?? 2500;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hoy'),
        actions: [
          IconButton(
            tooltip: 'Ajustes',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (profile != null) _goalBanner(context, profile.goal.description,
              profile.goal.weeksLeft, overall),
          const SizedBox(height: 12),
          _todayWorkout(context, day, trainedToday, steps.today >= stepGoal),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _stepsCard(context, steps, stepGoal)),
              const SizedBox(width: 12),
              Expanded(child: _waterCard(context, water, waterGoal)),
            ],
          ),
          const SizedBox(height: 12),
          if (plan != null) _nextMeal(context, plan.nutrition, now),
        ],
      ),
    );
  }

  Widget _goalBanner(
      BuildContext context, String goal, int weeks, double overall) {
    final color = ProgressEngine.colorFor(overall);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.flag_outlined, color: color, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(goal, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('Quedan $weeks semanas · nivel ${ProgressEngine.tierFor(overall)}',
                      style: TextStyle(color: color, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _todayWorkout(
      BuildContext context, TrainingDay? day, bool trained, bool stepsDone) {
    final requiresSteps = day?.requiresStepGoal ?? false;
    final hasWorkout = day != null && !day.isRest;
    final complete = (hasWorkout ? trained : true) && (!requiresSteps || stepsDone);

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
                    day?.title ?? 'Sin plan para hoy',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (complete && day != null)
                  const Chip(
                    avatar: Icon(Icons.check_circle, color: AurumColors.gold, size: 18),
                    label: Text('Día cumplido'),
                  ),
              ],
            ),
            if (day != null && day.focus.isNotEmpty)
              Text(day.focus, style: const TextStyle(color: AurumColors.textMuted)),
            const SizedBox(height: 8),
            if (hasWorkout)
              Text(
                trained
                    ? '✓ Entrenamiento registrado'
                    : '${day!.exercises.length} ejercicios pendientes',
              ),
            if (requiresSteps)
              Text(stepsDone
                  ? '✓ Meta de pasos cumplida'
                  : 'Este día requiere tu meta de pasos'),
            if (hasWorkout && !trained) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<bool>(
                    builder: (_) => SessionLogScreen(day: day!),
                  ),
                ),
                icon: const Icon(Icons.edit_note),
                label: const Text('Registrar entrenamiento'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _ring(double value, Color color, Widget center) => SizedBox(
        width: 92,
        height: 92,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CircularProgressIndicator(
              value: value.clamp(0.0, 1.0).toDouble(),
              strokeWidth: 8,
              color: color,
              backgroundColor: AurumColors.surfaceHigh,
            ),
            Center(child: center),
          ],
        ),
      );

  Widget _stepsCard(BuildContext context, StepsState steps, int goal) {
    final source = switch (steps.source) {
      StepSource.healthConnect => 'Health Connect',
      StepSource.healthKit => 'Apple Salud',
      StepSource.sensor => 'Sensor del teléfono',
      StepSource.none => steps.permissionDenied ? 'Sin permiso' : '—',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _ring(
              steps.today / goal,
              AurumColors.gold,
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.directions_walk, size: 20),
                  Text('${steps.today}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text('Meta $goal', style: const TextStyle(fontSize: 12)),
            Text(source,
                style: const TextStyle(fontSize: 11, color: AurumColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _waterCard(BuildContext context, int ml, int goal) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _ring(
              ml / goal,
              AurumColors.rest,
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.water_drop_outlined, size: 20),
                  Text('${(ml / 1000).toStringAsFixed(1)} L',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final add in const [250, 500])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text('+$add'),
                      onPressed: () =>
                          ref.read(hydrationProvider.notifier).add(add),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _nextMeal(BuildContext context, NutritionPlan nutrition, DateTime now) {
    final day = nutrition.dayFor(now);
    if (day == null) return const SizedBox.shrink();
    final minutesNow = now.hour * 60 + now.minute;
    Meal? next;
    for (final m in day.meals) {
      if (m.hour * 60 + m.minute >= minutesNow - 30) {
        next = m;
        break;
      }
    }
    if (next == null) return const SizedBox.shrink();
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const Icon(Icons.restaurant_outlined, color: AurumColors.gold),
        title: Text('${next.time} · ${next.slot.label}'),
        subtitle: Text(
            '${next.name}\n${next.kcal} kcal · P ${next.proteinG} g · C ${next.carbsG} g · G ${next.fatG} g'),
        isThreeLine: true,
      ),
    );
  }
}
