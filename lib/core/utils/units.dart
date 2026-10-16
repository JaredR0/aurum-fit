/// Conversiones de unidades. Internamente todo se guarda en kg y cm.
class Units {
  Units._();

  static const double _lbPerKg = 2.2046226218;
  static const double _cmPerInch = 2.54;

  static double kgToLb(double kg) => kg * _lbPerKg;
  static double lbToKg(double lb) => lb / _lbPerKg;

  static double cmToInches(double cm) => cm / _cmPerInch;
  static double inchesToCm(double inches) => inches * _cmPerInch;

  /// 175 cm → "5′ 9″"
  static String cmToFeetLabel(double cm) {
    final totalInches = cmToInches(cm).round();
    return "${totalInches ~/ 12}′ ${totalInches % 12}″";
  }

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
