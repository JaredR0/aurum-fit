import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/input_sanitizer.dart';
import '../../core/theme/app_theme.dart';
import '../checkin/checkin_logic.dart';
import '../checkin/checkin_models.dart';
import '../checkin/checkin_screen.dart';
import '../hydration/hydration_controller.dart';
import '../hydration/water_math.dart';
import '../onboarding/profile_controller.dart';
import '../onboarding/user_profile.dart';
import '../plan/plan_controller.dart';
import '../plan/plan_models.dart';
import '../plan/session_log_screen.dart';
import '../progress/progress_engine.dart';
import '../progress/workout_log.dart';
import '../steps/step_service.dart';
import 'settings_screen.dart';

/// Pantalla "Hoy": semana del plan, check-in pendiente, entrenamiento del día,
/// pasos y agua con su meta, y la próxima comida.
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

  static String _thousands(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  static String _liters(int ml) {
    final l = ml / 1000;
    return l == l.roundToDouble() ? '${l.round()} L' : '${l.toStringAsFixed(ml % 100 == 0 ? 1 : 2)} L';
  }

  Future<int?> _askNumber(String title, String suffix, int initial,
      {required double min, required double max, String? extraAction}) {
    final c = TextEditingController(text: '$initial');
    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: InputDecoration(suffixText: suffix),
        ),
        actions: [
          if (extraAction != null)
            TextButton(
              onPressed: () => Navigator.pop(context, -1),
              child: Text(extraAction),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final v = InputSanitizer.number(c.text, min: min, max: max);
              Navigator.pop(context, v?.round());
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final plan = ref.watch(planProvider).plan;
    final steps = ref.watch(stepProvider);
    final water = ref.watch(hydrationProvider);
    final sessions = ref.watch(workoutLogProvider);
    final checkins = ref.watch(checkinProvider);
    final overall = ProgressEngine.overall(ref.watch(progressProvider));

    final now = DateTime.now();
    final training = plan?.training;
    final week = training == null
        ? null
        : CheckinLogic.effectiveWeek(training, training.weekNumberFor(now), checkins);
    final day = week?.dayFor(now.weekday);
    final pending =
        training == null ? null : CheckinLogic.pendingWeek(training, checkins, now);
    final trainedToday = sessions.any((s) =>
        s.date.year == now.year &&
        s.date.month == now.month &&
        s.date.day == now.day);
    final stepGoal = profile?.dailyStepGoal ?? 10000;

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
          if (profile != null && training != null && week != null)
            _goalBanner(training, week, profile, overall),
          if (pending != null) ...[
            const SizedBox(height: 12),
            _checkinCard(pending),
          ],
          const SizedBox(height: 12),
          _todayWorkout(day, trainedToday, steps.today >= stepGoal),
          const SizedBox(height: 12),
          if (profile != null) _stepsCard(steps, profile, day),
          const SizedBox(height: 12),
          if (profile != null) _waterCard(water, profile, day, now),
          const SizedBox(height: 12),
          if (plan != null) _nextMeal(plan.nutrition, now),
        ],
      ),
    );
  }

  Widget _goalBanner(
      TrainingPlan plan, TrainingWeek week, UserProfile profile, double overall) {
    final color = ProgressEngine.colorFor(overall);
    final weeksLeft = plan.totalWeeks - week.number;
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
                  Text(
                    plan.goalHeadline.isEmpty ? profile.goal.description : plan.goalHeadline,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Semana ${week.number} de ${plan.totalWeeks} · ${week.phase}'
                    '${week.deload ? ' · descarga' : ''}',
                    style: const TextStyle(color: AurumColors.gold, fontSize: 13),
                  ),
                  Text(
                    '${weeksLeft <= 0 ? 'Última semana' : 'Quedan $weeksLeft semanas'} · nivel ${ProgressEngine.tierFor(overall)}',
                    style: const TextStyle(color: AurumColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkinCard(int pending) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AurumColors.gold, width: 2),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const Icon(Icons.assignment_late_outlined, color: AurumColors.gold),
        title: Text(pending == 0
            ? 'Haz tu evaluación inicial'
            : 'Check-in de la semana $pending'),
        subtitle: Text(pending == 0
            ? 'Mide tu punto de partida para contar tus logros.'
            : '¿Qué lograste esta semana? Toma 2 minutos.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<bool>(
          builder: (_) => CheckinScreen(week: pending),
        )),
      ),
    );
  }

  Widget _todayWorkout(TrainingDay? day, bool trained, bool stepsDone) {
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
              for (final e in day!.exercises.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('• ${e.name} — ${e.prescription}',
                      style: const TextStyle(fontSize: 13)),
                ),
            if (hasWorkout)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  trained ? '✓ Entrenamiento registrado' : 'Pendiente de registrar',
                  style: TextStyle(
                    color: trained ? AurumColors.gold : AurumColors.textMuted,
                    fontSize: 13,
                  ),
                ),
              ),
            if (requiresSteps)
              Text(
                stepsDone
                    ? '✓ Meta de pasos cumplida'
                    : 'Este día requiere tu meta de pasos',
                style: TextStyle(
                  color: stepsDone ? AurumColors.gold : AurumColors.textMuted,
                  fontSize: 13,
                ),
              ),
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

  Widget _cardHeader(IconData icon, Color color, String title, String goalLabel,
      VoidCallback onEdit) {
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        TextButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: Text(goalLabel),
        ),
      ],
    );
  }

  Widget _stepsCard(StepsState steps, UserProfile profile, TrainingDay? day) {
    final goal = profile.dailyStepGoal;
    final remaining = (goal - steps.today).clamp(0, goal).toInt();
    final strideM = profile.heightCm * 0.415 / 100;
    final km = remaining * strideM / 1000;
    final minutes = (remaining / 100).round();
    final source = switch (steps.source) {
      StepSource.healthConnect => 'Health Connect',
      StepSource.healthKit => 'Apple Salud',
      StepSource.sensor => 'sensor del teléfono',
      StepSource.none => steps.permissionDenied ? 'sin permiso de actividad física' : 'esperando datos',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardHeader(Icons.directions_walk, AurumColors.gold, 'Pasos',
                'Meta ${_thousands(goal)}', () async {
              final v = await _askNumber('Meta diaria de pasos', 'pasos', goal,
                  min: 1000, max: 50000);
              if (v != null && v > 0) {
                await ref.read(profileProvider.notifier)
                    .save(profile.copyWith(dailyStepGoal: v));
              }
            }),
            const SizedBox(height: 4),
            RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  TextSpan(
                    text: _thousands(steps.today),
                    style: const TextStyle(
                        fontSize: 34, fontWeight: FontWeight.w800, color: AurumColors.gold),
                  ),
                  TextSpan(
                    text: '  de ${_thousands(goal)} pasos',
                    style: const TextStyle(color: AurumColors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (steps.today / goal).clamp(0.0, 1.0).toDouble(),
              minHeight: 10,
              borderRadius: BorderRadius.circular(5),
              color: AurumColors.gold,
              backgroundColor: AurumColors.surfaceHigh,
            ),
            const SizedBox(height: 8),
            Text(
              remaining == 0
                  ? '¡Meta de hoy cumplida! 🎉'
                  : 'Te faltan ${_thousands(remaining)} pasos '
                      '(≈ ${km.toStringAsFixed(1)} km · $minutes min caminando)',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (day?.requiresStepGoal ?? false)
              const Text(
                'Hoy tu plan exige llegar a la meta para dar el día por cumplido.',
                style: TextStyle(color: AurumColors.amber, fontSize: 12),
              ),
            Text('Fuente: $source',
                style: const TextStyle(color: AurumColors.textMuted, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _waterCard(int ml, UserProfile profile, TrainingDay? day, DateTime now) {
    final goal = WaterMath.goalFor(profile, day);
    final remaining = (goal.ml - ml).clamp(0, goal.ml).toInt();
    final glassesTotal = (goal.ml / WaterMath.glassMl).ceil();
    final glassesDone = (ml / WaterMath.glassMl).floor();
    final glassesLeft = (remaining / WaterMath.glassMl).ceil();
    final expected = WaterMath.expectedByNow(goal.ml, now);
    final behind = expected - ml;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardHeader(Icons.water_drop_outlined, AurumColors.rest, 'Agua',
                'Meta ${_liters(goal.ml)}', () async {
              final v = await _askNumber('Meta diaria de agua', 'ml', goal.ml,
                  min: 500, max: 8000, extraAction: 'Automática');
              if (v == null) return;
              await ref.read(profileProvider.notifier).save(v == -1
                  ? profile.copyWith(clearWaterGoal: true)
                  : profile.copyWith(waterGoalMl: v));
            }),
            const SizedBox(height: 4),
            RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  TextSpan(
                    text: _liters(ml),
                    style: const TextStyle(
                        fontSize: 34, fontWeight: FontWeight.w800, color: AurumColors.rest),
                  ),
                  TextSpan(
                    text: '  de ${_liters(goal.ml)}',
                    style: const TextStyle(color: AurumColors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (var i = 0; i < glassesTotal.clamp(1, 20); i++)
                  Icon(
                    i < glassesDone ? Icons.local_drink : Icons.local_drink_outlined,
                    size: 22,
                    color: i < glassesDone ? AurumColors.rest : AurumColors.outline,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              remaining == 0
                  ? '¡Meta de agua cumplida! 💧'
                  : 'Te faltan ${_liters(remaining)} ($glassesLeft ${glassesLeft == 1 ? 'vaso' : 'vasos'} de 250 ml)',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (remaining > 0 && behind >= WaterMath.glassMl)
              Text(
                'A esta hora deberías llevar ~${_liters(expected)}: tómate ${(behind / WaterMath.glassMl).ceil()} vaso(s) ahora.',
                style: const TextStyle(color: AurumColors.amber, fontSize: 12),
              ),
            Text(goal.explanation,
                style: const TextStyle(color: AurumColors.textMuted, fontSize: 11)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => ref.read(hydrationProvider.notifier).add(250),
                    icon: const Icon(Icons.local_drink_outlined),
                    label: const Text('Vaso 250 ml'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => ref.read(hydrationProvider.notifier).add(500),
                    icon: const Icon(Icons.water_drop_outlined),
                    label: const Text('Botella 500'),
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar 250 ml',
                  onPressed: ml > 0
                      ? () => ref.read(hydrationProvider.notifier).add(-250)
                      : null,
                  icon: const Icon(Icons.undo),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _nextMeal(NutritionPlan nutrition, DateTime now) {
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
