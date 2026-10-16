import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import 'auth_controller.dart';
import 'pin_pad.dart';

/// Pantalla de bloqueo. Se superpone a toda la app cuando el estado es
/// [AuthStatus.locked], así que la navegación no se pierde al bloquear.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  static const int _pinLength = 6;
  String _pin = '';
  String? _message;
  bool _busy = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Refresca la cuenta regresiva del bloqueo temporal.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ref.read(authProvider).isLockedOut) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometrics());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _tryBiometrics() async {
    final auth = ref.read(authProvider);
    if (!auth.biometricsEnabled || auth.isLockedOut) return;
    await ref.read(authProvider.notifier).unlockWithBiometrics();
  }

  Future<void> _onDigit(String d) async {
    if (_busy) return;
    setState(() {
      _pin += d;
      _message = null;
    });
    if (_pin.length < _pinLength) return;

    setState(() => _busy = true);
    final result = await ref.read(authProvider.notifier).unlockWithPin(_pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pin = '';
      _message = switch (result) {
        PinResult.ok => null,
        PinResult.wrong => 'PIN incorrecto',
        PinResult.lockedOut => 'Demasiados intentos',
        PinResult.invalid => 'PIN inválido',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final remaining = auth.lockedUntil?.difference(DateTime.now());
    final lockedOut = auth.isLockedOut && remaining != null;

    return Scaffold(
      backgroundColor: AurumColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 40, color: AurumColors.gold),
                const SizedBox(height: 16),
                Text(
                  'Aurum Fit',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AurumColors.gold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  lockedOut
                      ? 'Intenta de nuevo en ${remaining!.inSeconds + 1} s'
                      : (_message ?? 'Ingresa tu PIN de 6 dígitos'),
                  style: TextStyle(
                    color: _message != null || lockedOut
                        ? AurumColors.danger
                        : AurumColors.textMuted,
                  ),
                ),
                const SizedBox(height: 32),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                PinPad(
                  length: _pin.length,
                  maxLength: _pinLength,
                  enabled: !_busy && !lockedOut,
                  onDigit: _onDigit,
                  onDelete: () {
                    if (_pin.isNotEmpty) {
                      setState(() => _pin = _pin.substring(0, _pin.length - 1));
                    }
                  },
                  onBiometric: auth.biometricsEnabled && !lockedOut
                      ? _tryBiometrics
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
