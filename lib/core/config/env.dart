/// Configuración inyectada en tiempo de compilación con --dart-define.
///
/// Aquí NO hay ninguna clave secreta: todo lo que se compila dentro del APK
/// puede extraerse con herramientas de ingeniería inversa. La clave de la IA
/// vive solo en el proxy (carpeta proxy/).
class Env {
  Env._();

  /// URL base del proxy, p. ej. https://aurum-proxy.usuario.workers.dev
  static const String proxyUrl = String.fromEnvironment('PROXY_URL');

  /// Solo se acepta HTTPS; cualquier otro valor desactiva la IA remota.
  static bool get hasProxy {
    final uri = Uri.tryParse(proxyUrl);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  static Uri get proxyUri => Uri.parse(proxyUrl);
}
