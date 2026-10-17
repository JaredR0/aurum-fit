import '../onboarding/user_profile.dart';
import '../plan/plan_models.dart';

/// Meta diaria de agua explicada.
class WaterGoal {
  const WaterGoal({required this.ml, required this.explanation});
  final int ml;
  final String explanation;
}

class WaterMath {
  WaterMath._();

  static const int glassMl = 250;

  /// 35 ml por kg de peso (redondeado a vasos), +500 ml en días de
  /// entrenamiento y +750 ml más si hay una sesión de más de 90 minutos.
  /// Si el usuario fijó su propia meta, se respeta.
  static WaterGoal goalFor(UserProfile p, TrainingDay? today) {
    final custom = p.waterGoalMl;
    if (custom != null) {
      return WaterGoal(ml: custom, explanation: 'Meta personalizada.');
    }
    final base = ((p.weightKg * 35) / glassMl).round() * glassMl;
    var extra = 0;
    final parts = <String>['35 ml × ${p.weightKg.round()} kg'];
    if (today != null && !today.isRest) {
      extra += 500;
      parts.add('+500 ml por entrenar hoy');
      final longest = today.exercises
          .map((e) => (e.durationSec ?? 0) * e.sets)
          .fold<int>(0, (a, b) => a > b ? a : b);
      if (longest > 90 * 60) {
        extra += 750;
        parts.add('+750 ml por la sesión larga');
      }
    }
    return WaterGoal(ml: base + extra, explanation: parts.join(' · '));
  }

  /// Lo que convendría llevar a esta hora (de 7:00 a 21:00).
  static int expectedByNow(int goalMl, DateTime now) {
    final hours = now.hour + now.minute / 60;
    final f = ((hours - 7) / 14).clamp(0.0, 1.0);
    return ((goalMl * f) / glassMl).round() * glassMl;
  }
}
