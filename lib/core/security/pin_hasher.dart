import 'dart:convert';

import 'package:crypto/crypto.dart';

/// PBKDF2-HMAC-SHA256 para derivar el hash del PIN.
///
/// Un PIN de 4–6 dígitos tiene poca entropía, así que la defensa real es:
/// 1) el hash vive en el Keystore/Keychain (no en disco plano),
/// 2) muchas iteraciones encarecen la fuerza bruta,
/// 3) bloqueo progresivo tras intentos fallidos (ver AuthService).
class PinHasher {
  PinHasher._();

  static const int iterations = 120000;
  static const int keyLength = 32;

  /// Argumentos empaquetados para poder correr en un isolate con compute().
  static String hashForIsolate(Map<String, String> args) {
    final salt = base64Url.decode(args['salt']!);
    final out = pbkdf2(
      utf8.encode(args['pin']!),
      salt,
      int.parse(args['iterations']!),
      keyLength,
    );
    return base64UrlEncode(out);
  }

  static List<int> pbkdf2(
    List<int> password,
    List<int> salt,
    int iterations,
    int length,
  ) {
    final hmac = Hmac(sha256, password);
    final output = <int>[];
    var blockIndex = 1;
    while (output.length < length) {
      final blockBytes = <int>[
        (blockIndex >> 24) & 0xff,
        (blockIndex >> 16) & 0xff,
        (blockIndex >> 8) & 0xff,
        blockIndex & 0xff,
      ];
      var u = hmac.convert(<int>[...salt, ...blockBytes]).bytes;
      final t = List<int>.from(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      output.addAll(t);
      blockIndex++;
    }
    return output.sublist(0, length);
  }

  /// Comparación en tiempo constante para no filtrar información por timing.
  static bool constantTimeEquals(String a, String b) {
    final x = utf8.encode(a);
    final y = utf8.encode(b);
    if (x.length != y.length) return false;
    var diff = 0;
    for (var i = 0; i < x.length; i++) {
      diff |= x[i] ^ y[i];
    }
    return diff == 0;
  }
}
