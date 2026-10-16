import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/config/env.dart';
import '../../core/security/input_sanitizer.dart';
import '../../core/security/pinned_http_client.dart';
import '../../core/security/secure_vault.dart';
import '../onboarding/user_profile.dart';
import 'local_plan_generator.dart';
import 'plan_models.dart';

class PlanApiException implements Exception {
  const PlanApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Cliente del proxy de IA (carpeta proxy/). La app nunca habla directo con
/// el proveedor de IA ni conoce su clave.
///
/// Qué sale del teléfono: edad, sexo, peso, altura, % grasa, nivel de
/// actividad, equipo, lesiones y objetivo (ya sanitizados), las semanas
/// disponibles y los objetivos calóricos calculados en el dispositivo.
/// Nunca: nombre, fotos, ubicación, pasos históricos ni audio.
class PlanApi {
  PlanApi._();

  static const String accessCodeKey = 'aurum.proxy.access_code';
  static const int _maxResponseBytes = 512 * 1024;

  static bool get isConfigured => Env.hasProxy;

  static Future<void> saveAccessCode(String code) async {
    final clean = code.trim();
    if (clean.isEmpty) {
      await SecureVault.delete(accessCodeKey);
    } else {
      await SecureVault.write(accessCodeKey, clean);
    }
  }

  static Future<bool> hasAccessCode() async =>
      (await SecureVault.read(accessCodeKey) ?? '').isNotEmpty;

  static Future<FitnessPlan> generate(
    UserProfile profile, {
    String extraRequest = '',
  }) async {
    if (!Env.hasProxy) {
      throw const PlanApiException(
          'La IA no está configurada en esta compilación (falta PROXY_URL).');
    }

    final extra = InputSanitizer.clean(extraRequest, maxLength: 300);
    if (extra.suspicious) {
      throw const PlanApiException(
          'Tu petición contiene frases que parecen instrucciones para la IA. Reescríbela con tus palabras.');
    }

    final targets = LocalPlanGenerator.targets(profile);
    final payload = jsonEncode({
      'schemaVersion': 1,
      'locale': 'es-GT',
      'profile': profile.toAnonymizedJson(),
      'request': extra.text,
      'targets': {
        'calories': targets.calories,
        'proteinG': targets.proteinG,
        'carbsG': targets.carbsG,
        'fatG': targets.fatG,
      },
    });

    final client = await PinnedHttp.create(allowedHost: Env.proxyUri.host);
    try {
      final installId = await SecureVault.installId();
      final accessCode = await SecureVault.read(accessCodeKey) ?? '';

      final http.Response res = await client
          .post(
            Env.proxyUri.resolve('/v1/plan'),
            headers: {
              'content-type': 'application/json',
              'accept': 'application/json',
              'x-install-id': installId,
              if (accessCode.isNotEmpty) 'x-access-code': accessCode,
            },
            body: payload,
          )
          .timeout(const Duration(seconds: 150));

      switch (res.statusCode) {
        case 200:
          break;
        case 401:
        case 403:
          throw const PlanApiException(
              'Código de acceso inválido. Revísalo en Ajustes → IA.');
        case 429:
          throw const PlanApiException(
              'Alcanzaste el límite de planes por hoy. Intenta mañana.');
        default:
          throw PlanApiException(
              'El servidor respondió ${res.statusCode}. Se usará el plan local.');
      }

      if (res.bodyBytes.length > _maxResponseBytes) {
        throw const PlanApiException('Respuesta demasiado grande; descartada.');
      }

      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      final plan = FitnessPlan.tryParse(decoded, source: 'ai');
      if (plan == null) {
        throw const PlanApiException(
            'La respuesta de la IA no pasó la validación; se descartó.');
      }

      // Control de cordura: la IA no puede desviarse demasiado de las
      // calorías calculadas en el dispositivo.
      final drift = (plan.nutrition.calories - targets.calories).abs() /
          targets.calories;
      if (drift > 0.35) {
        throw const PlanApiException(
            'Las calorías propuestas por la IA eran poco realistas; se descartó el plan.');
      }
      return plan;
    } on PlanApiException {
      rethrow;
    } on HandshakeException {
      throw const PlanApiException(
          'Conexión rechazada: el certificado del servidor no es de confianza (posible intercepción).');
    } on NetworkSecurityException catch (e) {
      throw PlanApiException(e.message);
    } on SocketException {
      throw const PlanApiException('Sin conexión a internet.');
    } on http.ClientException {
      throw const PlanApiException('No se pudo conectar con el servidor.');
    } on TimeoutException {
      throw const PlanApiException('La IA tardó demasiado en responder.');
    } on FormatException {
      throw const PlanApiException('Respuesta inválida del servidor.');
    } finally {
      client.close();
    }
  }
}
