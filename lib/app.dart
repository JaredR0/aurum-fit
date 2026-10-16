import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/lock_screen.dart';
import 'features/auth/pin_setup_screen.dart';
import 'features/home/home_shell.dart';
import 'features/hydration/hydration_controller.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/onboarding/profile_controller.dart';

class AurumApp extends ConsumerStatefulWidget {
  const AurumApp({super.key});

  @override
  ConsumerState<AurumApp> createState() => _AurumAppState();
}

class _AurumAppState extends ConsumerState<AurumApp>
    with WidgetsBindingObserver {
  /// Tiempo en segundo plano tras el cual la app se bloquea sola.
  static const Duration _autoLock = Duration(seconds: 45);
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgroundedAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since != null && DateTime.now().difference(since) > _autoLock) {
          ref.read(authProvider.notifier).lock();
        }
        ref.read(hydrationProvider.notifier).refresh();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(authProvider.select((s) => s.status));

    return MaterialApp(
      title: 'Aurum Fit',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      locale: const Locale('es'),
      supportedLocales: const [Locale('es'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const _RootGate(),
      // La pantalla de bloqueo se superpone sin destruir la navegación.
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          if (child != null) child,
          if (status == AuthStatus.locked) const LockScreen(),
          if (status == AuthStatus.loading)
            const ColoredBox(
              color: AurumColors.background,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _RootGate extends ConsumerStatefulWidget {
  const _RootGate();

  @override
  ConsumerState<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends ConsumerState<_RootGate> {
  /// Hasta el primer desbloqueo no se construye nada sensible (ni se piden
  /// permisos) debajo de la pantalla de bloqueo. Después sí se conserva la
  /// navegación debajo para no perder el estado al re-bloquear.
  bool _unlockedOnce = false;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(authProvider.select((s) => s.status));
    final profile = ref.watch(profileProvider);

    if (status == AuthStatus.needsSetup) {
      _unlockedOnce = false;
      return const PinSetupScreen();
    }
    if (status == AuthStatus.unlocked) _unlockedOnce = true;
    if (!_unlockedOnce) return const SizedBox.shrink();

    if (profile == null) return const OnboardingScreen();
    return const HomeShell();
  }
}
