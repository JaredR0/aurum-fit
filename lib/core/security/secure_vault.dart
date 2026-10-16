import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Almacén de secretos respaldado por hardware:
/// - Android: Android Keystore (AES-256-GCM vía EncryptedSharedPreferences).
/// - iOS: Keychain, accesible solo en este dispositivo tras el primer desbloqueo.
///
/// Guarda la llave maestra de la base de datos, el hash del PIN, el código de
/// acceso al proxy y el identificador anónimo de instalación.
class SecureVault {
  SecureVault._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const String _dbKeyName = 'aurum.db_key.v1';
  static const String _installIdName = 'aurum.install_id.v1';

  static Future<String?> read(String key) => _storage.read(key: key);

  static Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  static Future<void> delete(String key) => _storage.delete(key: key);

  /// Llave AES-256 (32 bytes) de la base de datos local. Se genera con un
  /// RNG criptográfico la primera vez y nunca sale del almacén seguro.
  static Future<List<int>> databaseKey() async {
    final existing = await _storage.read(key: _dbKeyName);
    if (existing != null) {
      final decoded = base64Url.decode(existing);
      if (decoded.length == 32) return decoded;
    }
    final key = randomBytes(32);
    await _storage.write(key: _dbKeyName, value: base64UrlEncode(key));
    return key;
  }

  /// Identificador aleatorio y anónimo de esta instalación. Solo sirve para
  /// que el proxy aplique límites de uso; no contiene datos personales.
  static Future<String> installId() async {
    final existing = await _storage.read(key: _installIdName);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = base64UrlEncode(randomBytes(18)).replaceAll('=', '');
    await _storage.write(key: _installIdName, value: id);
    return id;
  }

  /// Borra todos los secretos (usado en "Borrar todos mis datos").
  static Future<void> wipe() => _storage.deleteAll();

  static List<int> randomBytes(int length) {
    final rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }
}
