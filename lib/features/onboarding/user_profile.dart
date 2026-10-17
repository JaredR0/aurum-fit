import 'package:flutter/foundation.dart';

enum Sex { male, female, other }

enum ActivityLevel { sedentary, light, moderate, active, veryActive }

enum Equipment { gym, calisthenics, home }

enum GoalType { mountain, running, muscle, fatLoss, strength, general }

enum UnitSystem { metric, imperial }

extension SexLabel on Sex {
  String get label => switch (this) {
        Sex.male => 'Hombre',
        Sex.female => 'Mujer',
        Sex.other => 'Prefiero no decir',
      };
}

extension ActivityLevelX on ActivityLevel {
  String get label => switch (this) {
        ActivityLevel.sedentary => 'Sedentario',
        ActivityLevel.light => 'Ligero (1–2 días/sem)',
        ActivityLevel.moderate => 'Moderado (3–4 días/sem)',
        ActivityLevel.active => 'Activo (5–6 días/sem)',
        ActivityLevel.veryActive => 'Muy activo (doble sesión / trabajo físico)',
      };

  /// Factor de actividad para el gasto energético total (TDEE).
  double get factor => switch (this) {
        ActivityLevel.sedentary => 1.2,
        ActivityLevel.light => 1.375,
        ActivityLevel.moderate => 1.55,
        ActivityLevel.active => 1.725,
        ActivityLevel.veryActive => 1.9,
      };
}

extension EquipmentX on Equipment {
  String get label => switch (this) {
        Equipment.gym => 'Gimnasio completo',
        Equipment.calisthenics => 'Calistenia / parque',
        Equipment.home => 'Casa sin equipo',
      };
}

extension GoalTypeX on GoalType {
  String get label => switch (this) {
        GoalType.mountain => 'Montaña / senderismo',
        GoalType.running => 'Carrera (5k, 10k, 21k)',
        GoalType.muscle => 'Ganar masa muscular',
        GoalType.fatLoss => 'Perder grasa',
        GoalType.strength => 'Fuerza máxima',
        GoalType.general => 'Salud y condición general',
      };
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

double _clampD(Object? v, double min, double max, double fallback) {
  final d = v is num ? v.toDouble() : double.tryParse('$v');
  if (d == null || d.isNaN) return fallback;
  return d.clamp(min, max).toDouble();
}

@immutable
class Goal {
  const Goal({
    required this.type,
    required this.description,
    required this.deadline,
  });

  final GoalType type;

  /// Texto libre ya sanitizado, p. ej. "Subir el Acatenango en 3 meses".
  final String description;
  final DateTime deadline;

  int get weeksLeft {
    final days = deadline.difference(DateTime.now()).inDays;
    return (days / 7).ceil().clamp(1, 104).toInt();
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'description': description,
        'deadline': deadline.toIso8601String(),
      };

  factory Goal.fromJson(Map<String, dynamic> j) => Goal(
        type: _enumByName(GoalType.values, j['type'], GoalType.general),
        description: (j['description'] as String?) ?? '',
        deadline: DateTime.tryParse('${j['deadline']}') ??
            DateTime.now().add(const Duration(days: 84)),
      );
}

/// Perfil biométrico. Siempre se guarda en unidades métricas; la conversión
/// a lb/ft es solo de presentación.
@immutable
class UserProfile {
  const UserProfile({
    required this.sex,
    required this.age,
    required this.weightKg,
    required this.heightCm,
    required this.activity,
    required this.equipment,
    required this.goal,
    this.bodyFatPct,
    this.injuries = '',
    this.units = UnitSystem.metric,
    this.dailyStepGoal = 10000,
    this.waterGoalMl,
  });

  final Sex sex;
  final int age;
  final double weightKg;
  final double heightCm;
  final double? bodyFatPct;
  final ActivityLevel activity;
  final Equipment equipment;
  final Goal goal;
  final String injuries;
  final UnitSystem units;
  final int dailyStepGoal;
  final int? waterGoalMl;

  /// Meta de agua: la elegida por el usuario o ~35 ml por kg.
  int get effectiveWaterGoalMl =>
      waterGoalMl ?? ((weightKg * 35) / 250).round() * 250;

  double get bmi => weightKg / ((heightCm / 100) * (heightCm / 100));

  UserProfile copyWith({
    double? weightKg,
    double? bodyFatPct,
    ActivityLevel? activity,
    Equipment? equipment,
    Goal? goal,
    String? injuries,
    UnitSystem? units,
    int? dailyStepGoal,
    int? waterGoalMl,
    bool clearWaterGoal = false,
  }) {
    return UserProfile(
      sex: sex,
      age: age,
      weightKg: weightKg ?? this.weightKg,
      heightCm: heightCm,
      bodyFatPct: bodyFatPct ?? this.bodyFatPct,
      activity: activity ?? this.activity,
      equipment: equipment ?? this.equipment,
      goal: goal ?? this.goal,
      injuries: injuries ?? this.injuries,
      units: units ?? this.units,
      dailyStepGoal: dailyStepGoal ?? this.dailyStepGoal,
      waterGoalMl: clearWaterGoal ? null : (waterGoalMl ?? this.waterGoalMl),
    );
  }

  Map<String, dynamic> toJson() => {
        'sex': sex.name,
        'age': age,
        'weightKg': weightKg,
        'heightCm': heightCm,
        'bodyFatPct': bodyFatPct,
        'activity': activity.name,
        'equipment': equipment.name,
        'goal': goal.toJson(),
        'injuries': injuries,
        'units': units.name,
        'dailyStepGoal': dailyStepGoal,
        'waterGoalMl': waterGoalMl,
      };

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        sex: _enumByName(Sex.values, j['sex'], Sex.other),
        age: _clampD(j['age'], 13, 100, 30).round(),
        weightKg: _clampD(j['weightKg'], 30, 300, 70),
        heightCm: _clampD(j['heightCm'], 120, 230, 170),
        bodyFatPct: j['bodyFatPct'] == null
            ? null
            : _clampD(j['bodyFatPct'], 3, 70, 20),
        activity: _enumByName(
            ActivityLevel.values, j['activity'], ActivityLevel.moderate),
        equipment: _enumByName(Equipment.values, j['equipment'], Equipment.home),
        goal: j['goal'] is Map<String, dynamic>
            ? Goal.fromJson(j['goal'] as Map<String, dynamic>)
            : Goal(
                type: GoalType.general,
                description: '',
                deadline: DateTime.now().add(const Duration(days: 84)),
              ),
        injuries: (j['injuries'] as String?) ?? '',
        units: _enumByName(UnitSystem.values, j['units'], UnitSystem.metric),
        dailyStepGoal: _clampD(j['dailyStepGoal'], 1000, 50000, 10000).round(),
        waterGoalMl: j['waterGoalMl'] == null
            ? null
            : _clampD(j['waterGoalMl'], 500, 8000, 2500).round(),
      );

  /// Lo mínimo que necesita la IA para planificar. Sin nombre, sin fechas
  /// exactas, sin fotos ni historial: minimización de datos.
  Map<String, dynamic> toAnonymizedJson() => {
        'sex': sex.name,
        'age': age,
        'weightKg': double.parse(weightKg.toStringAsFixed(1)),
        'heightCm': heightCm.round(),
        'bodyFatPct': bodyFatPct?.round(),
        'activity': activity.name,
        'equipment': equipment.name,
        'injuries': injuries,
        'goalType': goal.type.name,
        'goalText': goal.description,
        'weeksAvailable': goal.weeksLeft,
        'dailyStepGoal': dailyStepGoal,
      };
}
