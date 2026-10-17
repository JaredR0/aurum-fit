import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../security/secure_vault.dart';

/// Base de datos local cifrada (Hive + AES-256-CBC, llave de 32 bytes guardada
/// en el Keystore/Keychain a través de [SecureVault]).
///
/// Toda la app funciona offline contra estas cajas. Los registros se guardan
/// como JSON en texto (cifrado en disco) para no depender de generadores de
/// código ni adaptadores.
class LocalDb {
  LocalDb._();

  static const String profile = 'profile';
  static const String plans = 'plans';
  static const String workoutLogs = 'workout_logs';
  static const String hydration = 'hydration';
  static const String steps = 'steps';
  static const String settings = 'settings';
  static const String photoMeta = 'photo_meta';
  static const String checkins = 'checkins';

  /// Las fotos van en una caja "lazy": no se cargan todas a memoria.
  static const String photos = 'photos';

  static const List<String> _boxes = [
    profile,
    plans,
    workoutLogs,
    hydration,
    steps,
    settings,
    photoMeta,
    checkins,
  ];

  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    await Hive.initFlutter('aurum_secure');
    final cipher = HiveAesCipher(await SecureVault.databaseKey());
    for (final name in _boxes) {
      await Hive.openBox<dynamic>(name, encryptionCipher: cipher);
    }
    await Hive.openLazyBox<dynamic>(photos, encryptionCipher: cipher);
    _ready = true;
  }

  static Box<dynamic> box(String name) => Hive.box<dynamic>(name);

  static LazyBox<dynamic> get photoBox => Hive.lazyBox<dynamic>(photos);

  static Map<String, dynamic>? readJson(String boxName, String key) {
    final raw = box(boxName).get(key);
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeJson(
    String boxName,
    String key,
    Map<String, dynamic> value,
  ) =>
      box(boxName).put(key, jsonEncode(value));

  /// Todos los registros JSON de una caja, en orden de inserción.
  static List<Map<String, dynamic>> readAllJson(String boxName) {
    final out = <Map<String, dynamic>>[];
    for (final raw in box(boxName).values) {
      if (raw is! String) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) out.add(decoded);
      } catch (_) {
        // Registro corrupto: se ignora en lugar de tumbar la app.
      }
    }
    return out;
  }

  /// Borra los archivos de las cajas sin necesidad de abrirlas (útil cuando
  /// la llave se perdió y ya no se pueden descifrar).
  static Future<void> nukeFromDisk() async {
    await Hive.initFlutter('aurum_secure');
    for (final name in [..._boxes, photos]) {
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    _ready = false;
  }

  /// Borra físicamente todas las cajas del disco.
  static Future<void> wipeAll() async {
    for (final name in _boxes) {
      await box(name).deleteFromDisk();
    }
    await photoBox.deleteFromDisk();
    _ready = false;
  }
}
