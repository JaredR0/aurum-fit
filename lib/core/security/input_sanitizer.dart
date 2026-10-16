/// Resultado de limpiar un texto libre del usuario.
class SanitizedText {
  const SanitizedText(this.text, {this.suspicious = false});

  final String text;

  /// true si el texto parece intentar dar órdenes al modelo de IA.
  final bool suspicious;
}

/// Limpieza de entradas antes de guardarlas o enviarlas al proxy de IA.
///
/// Es la primera de tres capas contra inyección de prompts:
///   1. Aquí: se eliminan caracteres de control/invisibles y marcas de formato,
///      se acota la longitud y se detectan patrones típicos de inyección.
///   2. Proxy: el texto del usuario va delimitado como DATO, nunca como
///      instrucción, y el prompt de sistema le ordena ignorar órdenes ahí dentro.
///   3. Proxy + app: la respuesta de la IA se valida contra un esquema JSON
///      estricto; cualquier campo inesperado se descarta.
class InputSanitizer {
  InputSanitizer._();

  // Control (salvo \n y \t), anchos cero y marcas bidi usadas para ocultar texto.
  static final RegExp _invisible = RegExp(
    r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F'
    r'​-‏‪-‮⁠-⁤⁦-⁩﻿]',
  );

  // Caracteres de marcado que no aportan nada a una meta de entrenamiento.
  static final RegExp _markup = RegExp(r'[<>{}\[\]`\\|^~$]');

  static final RegExp _spaces = RegExp(r'[ \t]+');
  static final RegExp _newlines = RegExp(r'\n{3,}');

  static final List<RegExp> _injectionPatterns = [
    RegExp(r'ignor[ae]\w*\s+(las\s+|todas\s+las\s+)?(instrucciones|reglas|indicaciones)', caseSensitive: false),
    RegExp(r'ignore\s+(all\s+|the\s+)?(previous|prior|above)', caseSensitive: false),
    RegExp(r'(system|developer)\s*prompt', caseSensitive: false),
    RegExp(r'(prompt|mensaje)\s+(de|del)\s+sistema', caseSensitive: false),
    RegExp(r'\b(you\s+are\s+now|act\s+as|act[uú]a\s+como|ahora\s+eres)\b', caseSensitive: false),
    RegExp(r'\b(jailbreak|DAN\s+mode|modo\s+desarrollador)\b', caseSensitive: false),
    RegExp(r'(api[\s_-]?key|clave\s+de\s+api|token|contrase[nñ]a)', caseSensitive: false),
    RegExp(r'</?\s*(system|assistant|user|instructions?)\s*>', caseSensitive: false),
  ];

  /// Limpia texto libre (metas, lesiones, notas).
  static SanitizedText clean(String? input, {int maxLength = 400}) {
    if (input == null) return const SanitizedText('');
    final original = input;
    var text = input
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(_invisible, '');

    final suspicious = _injectionPatterns.any((p) => p.hasMatch(text)) ||
        _injectionPatterns.any((p) => p.hasMatch(original));

    text = text
        .replaceAll(_markup, ' ')
        .replaceAll(_spaces, ' ')
        .replaceAll(_newlines, '\n\n')
        .trim();

    if (text.length > maxLength) {
      text = text.substring(0, maxLength).trimRight();
    }
    return SanitizedText(text, suspicious: suspicious);
  }

  /// Valida un número dentro de un rango fisiológicamente razonable.
  static double? number(String? raw, {required double min, required double max}) {
    if (raw == null) return null;
    final value = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (value == null || value.isNaN || value.isInfinite) return null;
    if (value < min || value > max) return null;
    return value;
  }

  /// Solo dígitos, con longitud acotada (PIN).
  static bool isValidPin(String pin) => RegExp(r'^\d{4,8}$').hasMatch(pin);
}
