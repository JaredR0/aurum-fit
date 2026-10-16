import 'package:flutter/material.dart';

/// Paleta "bronce → oro" que da identidad al sistema de progreso.
class AurumColors {
  AurumColors._();

  static const Color background = Color(0xFF14110D);
  static const Color surface = Color(0xFF1F1A14);
  static const Color surfaceHigh = Color(0xFF2A231B);
  static const Color outline = Color(0xFF3D3328);

  static const Color bronzeDull = Color(0xFF5A4630);
  static const Color bronze = Color(0xFF8C6A3F);
  static const Color amber = Color(0xFFC0954E);
  static const Color gold = Color(0xFFE8C468);
  static const Color goldBright = Color(0xFFFFE89A);

  static const Color text = Color(0xFFF3ECE1);
  static const Color textMuted = Color(0xFFA89C8B);

  static const Color work = Color(0xFFE8C468);
  static const Color rest = Color(0xFF6FA8A0);
  static const Color danger = Color(0xFFE07A5F);
}

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AurumColors.gold,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AurumColors.gold,
      onPrimary: const Color(0xFF241A08),
      secondary: AurumColors.amber,
      surface: AurumColors.surface,
      onSurface: AurumColors.text,
      error: AurumColors.danger,
      outline: AurumColors.outline,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AurumColors.background,
      brightness: Brightness.dark,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AurumColors.background,
        foregroundColor: AurumColors.text,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AurumColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AurumColors.outline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AurumColors.surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: AurumColors.surface,
        indicatorColor: AurumColors.surfaceHigh,
        height: 68,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AurumColors.surfaceHigh,
        side: const BorderSide(color: AurumColors.outline),
      ),
    );
  }
}
