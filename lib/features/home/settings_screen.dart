import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/security/input_sanitizer.dart';
import '../../core/security/secure_vault.dart';
import '../../core/storage/local_db.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/units.dart';
import '../auth/auth_controller.dart';
import '../auth/pin_setup_screen.dart';
import '../checkin/checkin_models.dart';
import '../hydration/hydration_controller.dart';
import '../notifications/notification_service.dart';
import '../onboarding/profile_controller.dart';
import '../onboarding/user_profile.dart';
import '../photos/photo_controller.dart';
import '../plan/plan_api.dart';
import '../plan/plan_controller.dart';
import '../progress/workout_log.dart';
import '../steps/step_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  ReminderSettings _reminders = NotificationService.loadSettings();
  bool _hasAccessCode = false;

  @override
  void initState() {
    super.initState();
    PlanApi.hasAccessCode().then((v) {
      if (mounted) setState(() => _hasAccessCode = v);
    });
  }

  Future<String?> _prompt(String title, String initial,
      {bool number = true, bool obscure = false}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          obscureText: obscure,
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          inputFormatters: [
            if (number) FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            LengthLimitingTextInputFormatter(number ? 7 : 64),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, c.text),
              child: const Text('Guardar')),
        ],
      ),
    );
  }

  Future<void> _updateProfile(UserProfile p) async {
    await ref.read(profileProvider.notifier).save(p);
  }

  Future<void> _applyReminders(ReminderSettings s) async {
    if (s.any) {
      final granted = await NotificationService.requestPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Sin permiso de notificaciones.')));
        }
        return;
      }
    }
    await NotificationService.saveSettings(s);
    await NotificationService.reschedule(s, ref.read(planProvider).plan);
    setState(() => _reminders = s);
  }

  Future<void> _wipeEverything() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar todos mis datos?'),
        content: const Text(
          'Se eliminan perfil, planes, entrenamientos, pasos, agua, fotos, el PIN '
          'y las llaves de cifrado. No se puede deshacer.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AurumColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar todo'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await NotificationService.cancelAll();
    await LocalDb.wipeAll();
    await SecureVault.wipe();
    await LocalDb.init(); // base nueva, con llave nueva
    ref.invalidate(stepProvider);
    ref.invalidate(profileProvider);
    ref.invalidate(planProvider);
    ref.invalidate(workoutLogProvider);
    ref.invalidate(photoProvider);
    ref.invalidate(hydrationProvider);
    ref.invalidate(checkinProvider);
    ref.read(authProvider.notifier).reset();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final auth = ref.watch(authProvider);
    if (profile == null) return const Scaffold();
    final imperial = profile.units == UnitSystem.imperial;

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          const _Section('Perfil'),
          ListTile(
            leading: const Icon(Icons.monitor_weight_outlined),
            title: const Text('Peso actual'),
            subtitle: Text(imperial
                ? '${Units.kgToLb(profile.weightKg).toStringAsFixed(1)} lb'
                : '${profile.weightKg.toStringAsFixed(1)} kg'),
            onTap: () async {
              final raw = await _prompt(
                  imperial ? 'Peso (lb)' : 'Peso (kg)', '');
              final v = InputSanitizer.number(raw,
                  min: imperial ? 66 : 30, max: imperial ? 660 : 300);
              if (v == null) return;
              await _updateProfile(profile.copyWith(
                  weightKg: imperial ? Units.lbToKg(v) : v));
            },
          ),
          ListTile(
            leading: const Icon(Icons.directions_walk),
            title: const Text('Meta diaria de pasos'),
            subtitle: Text('${profile.dailyStepGoal}'),
            onTap: () async {
              final v = InputSanitizer.number(
                  await _prompt('Pasos por día', '${profile.dailyStepGoal}'),
                  min: 1000,
                  max: 50000);
              if (v != null) {
                await _updateProfile(profile.copyWith(dailyStepGoal: v.round()));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.water_drop_outlined),
            title: const Text('Meta diaria de agua'),
            subtitle: Text('${profile.effectiveWaterGoalMl} ml'),
            onTap: () async {
              final v = InputSanitizer.number(
                  await _prompt('Agua (ml)', '${profile.effectiveWaterGoalMl}'),
                  min: 500,
                  max: 8000);
              if (v != null) {
                await _updateProfile(profile.copyWith(waterGoalMl: v.round()));
              }
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.straighten),
            title: const Text('Usar lb / ft'),
            value: imperial,
            onChanged: (v) => _updateProfile(profile.copyWith(
                units: v ? UnitSystem.imperial : UnitSystem.metric)),
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Recalcular plan local'),
            subtitle: const Text('Usa tu peso y metas actuales, sin internet'),
            onTap: () async {
              await ref.read(planProvider.notifier).generateLocal(profile);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Plan actualizado')));
              }
            },
          ),
          const _Section('Recordatorios'),
          SwitchListTile(
            title: const Text('Horas de comida'),
            value: _reminders.meals,
            onChanged: (v) => _applyReminders(_reminders.copyWith(meals: v)),
          ),
          SwitchListTile(
            title: const Text('Hidratación (cada 2 h, 8:00–20:00)'),
            value: _reminders.water,
            onChanged: (v) => _applyReminders(_reminders.copyWith(water: v)),
          ),
          SwitchListTile(
            title: const Text('Entrenamiento'),
            subtitle: Text(
                '${_reminders.workoutHour.toString().padLeft(2, '0')}:${_reminders.workoutMinute.toString().padLeft(2, '0')}'),
            value: _reminders.workout,
            onChanged: (v) => _applyReminders(_reminders.copyWith(workout: v)),
          ),
          SwitchListTile(
            title: const Text('Check-in semanal'),
            subtitle: const Text('Sábado 10:00 — qué lograste en la semana'),
            value: _reminders.checkin,
            onChanged: (v) => _applyReminders(_reminders.copyWith(checkin: v)),
          ),
          ListTile(
            title: const Text('Cambiar hora del entrenamiento'),
            trailing: const Icon(Icons.schedule),
            onTap: () async {
              final t = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(
                    hour: _reminders.workoutHour,
                    minute: _reminders.workoutMinute),
              );
              if (t != null) {
                await _applyReminders(_reminders.copyWith(
                    workoutHour: t.hour, workoutMinute: t.minute));
              }
            },
          ),
          const _Section('Seguridad'),
          if (auth.biometricsAvailable)
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint),
              title: const Text('Desbloqueo biométrico'),
              value: auth.biometricsEnabled,
              onChanged: (v) =>
                  ref.read(authProvider.notifier).setBiometricsEnabled(v),
            ),
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Cambiar PIN'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const PinSetupScreen(isChange: true))),
          ),
          ListTile(
            leading: const Icon(Icons.lock_clock_outlined),
            title: const Text('Bloquear ahora'),
            onTap: () => ref.read(authProvider.notifier).lock(),
          ),
          const _Section('IA'),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('Servidor de IA'),
            subtitle: Text(Env.hasProxy
                ? Env.proxyUri.host
                : 'No configurado en esta compilación'),
          ),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('Código de acceso'),
            subtitle: Text(_hasAccessCode
                ? 'Guardado de forma segura'
                : 'Pídeselo a quien administra el servidor'),
            onTap: () async {
              final code = await _prompt('Código de acceso', '',
                  number: false, obscure: true);
              if (code == null) return;
              await PlanApi.saveAccessCode(code);
              final has = await PlanApi.hasAccessCode();
              if (mounted) setState(() => _hasAccessCode = has);
            },
          ),
          const _Section('Privacidad'),
          const ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('Tus datos'),
            subtitle: Text(
              'Perfil, entrenamientos, pasos, agua y fotos se guardan cifrados '
              '(AES-256) solo en este teléfono. Al pedir un plan a la IA se envían '
              'únicamente datos anónimos del perfil. No se usa ubicación ni micrófono.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined,
                color: AurumColors.danger),
            title: const Text('Borrar todos mis datos',
                style: TextStyle(color: AurumColors.danger)),
            onTap: _wipeEverything,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: AurumColors.gold,
            fontSize: 12,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}
