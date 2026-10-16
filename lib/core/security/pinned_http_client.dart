import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class NetworkSecurityException implements Exception {
  const NetworkSecurityException(this.message);
  final String message;
  @override
  String toString() => 'NetworkSecurityException: $message';
}

/// Cliente HTTPS "zero-trust":
///
/// * **Pinning de CA raíz**: ignora por completo el almacén de certificados del
///   sistema (y cualquier CA que un atacante haya instalado en el teléfono) y
///   solo acepta cadenas que terminen en las raíces de `pinned_roots.pem`
///   (las CAs que usa Cloudflare). Un proxy MITM con su propio certificado
///   falla el handshake.
/// * **TLS**: Dart usa BoringSSL y negocia TLS 1.3 cuando el servidor lo ofrece;
///   el proxy en Cloudflare se configura con TLS mínimo 1.2/1.3 (ver README).
/// * **Host bloqueado**: solo se permiten peticiones al host del proxy, sin
///   redirecciones y sin proxies HTTP del sistema.
class PinnedHttp {
  PinnedHttp._();

  static const String _bundle = 'assets/certs/pinned_roots.pem';

  static Future<http.Client> create({required String allowedHost}) async {
    final data = await rootBundle.load(_bundle);
    final context = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );

    final io = HttpClient(context: context)
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 20)
      // Nunca aceptar un certificado que no valide contra las raíces fijadas.
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => false
      // Ignorar proxies configurados en el sistema.
      ..findProxy = (Uri uri) => 'DIRECT';

    return _HostLockedClient(IOClient(io), allowedHost);
  }
}

class _HostLockedClient extends http.BaseClient {
  _HostLockedClient(this._inner, this._allowedHost);

  final http.Client _inner;
  final String _allowedHost;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final url = request.url;
    if (url.scheme != 'https' || url.host != _allowedHost) {
      throw NetworkSecurityException(
        'Destino no permitido: ${url.scheme}://${url.host}',
      );
    }
    // Una redirección podría llevar la petición a otro host.
    request.followRedirects = false;
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
