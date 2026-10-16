import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/security/input_sanitizer.dart';
import '../../core/security/pin_hasher.dart';
import '../../core/security/secure_vault.dart';

enum AuthStatus { loading, needsSetup, locked, unlocked }

enum PinResult { ok, wrong, lockedOut, invalid }

@immutable
class AuthState {
  const AuthState({
    required this.status,
    this.biometricsAvailable = false,
    this.biometricsEnabled = false,
    this.failedAttempts = 0,
    this.lockedUntil,
  });

  final AuthStatus status;
  final bool biometricsAvailable;
  final bool biometricsEnabled;
  final int failedAttempts;
  final DateTime? lockedUntil;

  bool get isLockedOut =>
      lockedUntil != null && DateTime.now().isBefore(lockedUntil!);

  AuthState copyWith({
    AuthStatus? status,
    bool? biometricsAvailable,
    bool? biometricsEnabled,
    int? failedAttempts,
    DateTime? lockedUntil,
    bool clearLockedUntil = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      biometricsAvailable: biometricsAvailable ?? this.biometricsAvailable,
      biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lockedUntil: clearLockedUntil ? null : (lockedUntil ?? this.lockedUntil),
    );
  }
}

/// Autenticación local: PIN (PBKDF2 en Keystore/Keychain) + biometría opcional.
///
/// La app no tiene cuentas en servidor: todos los datos viven cifrados en el
/// teléfono, así que "autenticarse" significa demostrar que eres el dueño del
/// dispositivo antes de mostrar datos biométricos y fotos.
class AuthController extends StateNotifier<AuthState> {
  AuthController() : super(const AuthState(status: AuthStatus.loading)) {
    _load();
  }

  final LocalAuthentication _localAuth = LocalAuthentication();

  static const String _hashKey = 'aurum.pin.hash';
  static const String _saltKey = 'aurum.pin.salt';
  static const String _bioKey = 'aurum.pin.biometrics';
  static const String _failsKey = 'aurum.pin.fails';
  static const String _lockKey = 'aurum.pin.locked_until';

  static const int _freeAttempts = 5;

  Future<void> _load() async {
    final hash = await SecureVault.read(_hashKey);
    final bio = await SecureVault.read(_bioKey) == 'true';
    final fails = int.tryParse(await SecureVault.read(_failsKey) ?? '') ?? 0;
    final lockMs = int.tryParse(await SecureVault.read(_lockKey) ?? '');
    final available = await _biometricsAvailable();

    state = AuthState(
      status: hash == null ? AuthStatus.needsSetup : AuthStatus.locked,
      biometricsAvailable: available,
      biometricsEnabled: bio && available,
      failedAttempts: fails,
      lockedUntil:
          lockMs == null ? null : DateTime.fromMillisecondsSinceEpoch(lockMs),
    );
  }

  Future<bool> _biometricsAvailable() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return supported && canCheck;
    } on PlatformException {
      return false;
    }
  }

  Future<String> _hash(String pin, String salt) {
    return compute(PinHasher.hashForIsolate, <String, String>{
      'pin': pin,
      'salt': salt,
      'iterations': '${PinHasher.iterations}',
    });
  }

  /// Crea o cambia el PIN.
  Future<PinResult> setPin(String pin, {required bool enableBiometrics}) async {
    if (!InputSanitizer.isValidPin(pin)) return PinResult.invalid;
    final salt = base64UrlEncode(SecureVault.randomBytes(16));
    final hash = await _hash(pin, salt);
    await SecureVault.write(_saltKey, salt);
    await SecureVault.write(_hashKey, hash);
    await SecureVault.write(_failsKey, '0');
    await SecureVault.delete(_lockKey);
    final bio = enableBiometrics && state.biometricsAvailable;
    await SecureVault.write(_bioKey, bio ? 'true' : 'false');
    state = state.copyWith(
      status: AuthStatus.unlocked,
      biometricsEnabled: bio,
      failedAttempts: 0,
      clearLockedUntil: true,
    );
    return PinResult.ok;
  }

  Future<PinResult> unlockWithPin(String pin) async {
    if (state.isLockedOut) return PinResult.lockedOut;
    if (!InputSanitizer.isValidPin(pin)) return PinResult.invalid;

    final salt = await SecureVault.read(_saltKey);
    final stored = await SecureVault.read(_hashKey);
    if (salt == null || stored == null) {
      state = state.copyWith(status: AuthStatus.needsSetup);
      return PinResult.invalid;
    }

    final candidate = await _hash(pin, salt);
    if (PinHasher.constantTimeEquals(candidate, stored)) {
      await SecureVault.write(_failsKey, '0');
      await SecureVault.delete(_lockKey);
      state = state.copyWith(
        status: AuthStatus.unlocked,
        failedAttempts: 0,
        clearLockedUntil: true,
      );
      return PinResult.ok;
    }

    final fails = state.failedAttempts + 1;
    await SecureVault.write(_failsKey, '$fails');
    DateTime? until;
    if (fails >= _freeAttempts) {
      // 30 s, 60 s, 2 min, 4 min… con tope de 1 hora.
      final seconds = min(3600, 30 * pow(2, fails - _freeAttempts).toInt());
      until = DateTime.now().add(Duration(seconds: seconds));
      await SecureVault.write(_lockKey, '${until.millisecondsSinceEpoch}');
    }
    state = state.copyWith(failedAttempts: fails, lockedUntil: until);
    return until != null ? PinResult.lockedOut : PinResult.wrong;
  }

  Future<bool> unlockWithBiometrics() async {
    if (!state.biometricsEnabled) return false;
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Desbloquea Aurum Fit',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (ok) {
        await SecureVault.write(_failsKey, '0');
        state = state.copyWith(
          status: AuthStatus.unlocked,
          failedAttempts: 0,
          clearLockedUntil: true,
        );
      }
      return ok;
    } on PlatformException {
      return false;
    }
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    final value = enabled && state.biometricsAvailable;
    await SecureVault.write(_bioKey, value ? 'true' : 'false');
    state = state.copyWith(biometricsEnabled: value);
  }

  void lock() {
    if (state.status == AuthStatus.unlocked) {
      state = state.copyWith(status: AuthStatus.locked);
    }
  }

  /// Tras "borrar todos mis datos".
  void reset() {
    state = AuthState(
      status: AuthStatus.needsSetup,
      biometricsAvailable: state.biometricsAvailable,
    );
  }
}

final authProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(),
);
