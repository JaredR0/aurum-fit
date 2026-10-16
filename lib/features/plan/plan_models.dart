import 'package:flutter/foundation.dart';

import '../../core/security/input_sanitizer.dart';
import '../progress/muscle_group.dart';

// ---------------------------------------------------------------------------
// Parsing defensivo: todo lo que viene de la IA se trata como NO confiable.
// Cada campo se valida, se acota y se limpia; lo desconocido se descarta.
// ---------------------------------------------------------------------------

String _s(Object? v, {int max = 120, String fallback = ''}) {
  if (v is! String) return fallback;
  final t = InputSanitizer.clean(v, maxLength: max).text;
  return t.isEmpty ? fallback : t;
}

int _i(Object? v, {required int min, required int max, required int fallback}) {
  final n = v is num ? v : num.tryParse('$v');
  if (n == null || n.isNaN || n.isInfinite) return fallback;
  return n.round().clamp(min, max).toInt();
}

double? _dOpt(Object? v, {required double min, required double max}) {
  if (v == null) return null;
  final n = v is num ? v : num.tryParse('$v');
  if (n == null || n.isNaN || n.isInfinite) return null;
  return n.toDouble().clamp(min, max).toDouble();
}

List<T> _list<T>(Object? v, T? Function(Object?) parse, {int max = 40}) {
  if (v is! List) return <T>[];
  final out = <T>[];
  for (final item in v.take(max)) {
    final parsed = parse(item);
    if (parsed != null) out.add(parsed);
  }
  return out;
}

Map<String, dynamic>? _map(Object? v) => v is Map<String, dynamic> ? v : null;

enum ExerciseKind { strength, cardio, mobility }

ExerciseKind _kind(Object? v) => switch (v) {
      'cardio' => ExerciseKind.cardio,
      'mobility' || 'movilidad' => ExerciseKind.mobility,
      _ => ExerciseKind.strength,
    };

@immutable
class Exercise {
  const Exercise({
    required this.name,
    required this.kind,
    this.sets = 3,
    this.reps = '10',
    this.restSec = 60,
    this.durationSec,
    this.distanceKm,
    this.muscles = const [],
    this.notes = '',
  });

  final String name;
  final ExerciseKind kind;
  final int sets;

  /// Texto porque puede ser "8–12", "AMRAP", "30 s por lado".
  final String reps;
  final int restSec;
  final int? durationSec;
  final double? distanceKm;
  final List<MuscleGroup> muscles;
  final String notes;

  String get prescription {
    if (kind == ExerciseKind.cardio) {
      final parts = <String>[];
      if (distanceKm != null) parts.add('${distanceKm!.toStringAsFixed(1)} km');
      if (durationSec != null) parts.add('${(durationSec! / 60).round()} min');
      if (sets > 1) parts.insert(0, '$sets ×');
      return parts.isEmpty ? reps : parts.join(' ');
    }
    if (durationSec != null) return '$sets × ${durationSec}s · descanso ${restSec}s';
    return '$sets × $reps · descanso ${restSec}s';
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': kind.name,
        'sets': sets,
        'reps': reps,
        'restSec': restSec,
        'durationSec': durationSec,
        'distanceKm': distanceKm,
        'muscles': muscles.map((m) => m.name).toList(),
        'notes': notes,
      };

  static Exercise? tryParse(Object? raw) {
    final j = _map(raw);
    if (j == null) return null;
    final name = _s(j['name'], max: 80);
    if (name.isEmpty) return null;
    return Exercise(
      name: name,
      kind: _kind(j['kind']),
      sets: _i(j['sets'], min: 1, max: 12, fallback: 3),
      reps: _s(j['reps'], max: 24, fallback: '10'),
      restSec: _i(j['restSec'], min: 0, max: 600, fallback: 60),
      durationSec: j['durationSec'] == null
          ? null
          : _i(j['durationSec'], min: 5, max: 4 * 3600, fallback: 60),
      distanceKm: _dOpt(j['distanceKm'], min: 0.1, max: 60),
      muscles: _list<MuscleGroup>(j['muscles'], (m) => MuscleGroupX.tryParse(m),
          max: 8),
      notes: _s(j['notes'], max: 200),
    );
  }
}

@immutable
class TrainingDay {
  const TrainingDay({
    required this.weekday,
    required this.title,
    required this.exercises,
    this.focus = '',
    this.requiresStepGoal = false,
  });

  /// 1 = lunes … 7 = domingo.
  final int weekday;
  final String title;
  final String focus;
  final List<Exercise> exercises;

  /// Si es true, el día solo cuenta como cumplido al llegar a la meta de pasos.
  final bool requiresStepGoal;

  bool get isRest => exercises.isEmpty;

  Map<String, dynamic> toJson() => {
        'weekday': weekday,
        'title': title,
        'focus': focus,
        'requiresStepGoal': requiresStepGoal,
        'exercises': exercises.map((e) => e.toJson()).toList(),
      };

  static TrainingDay? tryParse(Object? raw) {
    final j = _map(raw);
    if (j == null) return null;
    return TrainingDay(
      weekday: _i(j['weekday'], min: 1, max: 7, fallback: 1),
      title: _s(j['title'], max: 60, fallback: 'Entrenamiento'),
      focus: _s(j['focus'], max: 120),
      requiresStepGoal: j['requiresStepGoal'] == true,
      exercises: _list<Exercise>(j['exercises'], Exercise.tryParse, max: 14),
    );
  }
}

@immutable
class TrainingPlan {
  const TrainingPlan({
    required this.title,
    required this.summary,
    required this.weeks,
    required this.days,
    required this.source,
    required this.createdAt,
    this.progression = '',
    this.references = const [],
  });

  final String title;
  final String summary;
  final int weeks;
  final List<TrainingDay> days;

  /// Regla de sobrecarga progresiva semana a semana.
  final String progression;

  /// URLs o citas de evidencia que devolvió la búsqueda web de la IA.
  final List<String> references;

  /// 'ai' o 'local'.
  final String source;
  final DateTime createdAt;

  TrainingDay? dayFor(DateTime date) {
    for (final d in days) {
      if (d.weekday == date.weekday) return d;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'summary': summary,
        'weeks': weeks,
        'progression': progression,
        'references': references,
        'source': source,
        'createdAt': createdAt.toIso8601String(),
        'days': days.map((d) => d.toJson()).toList(),
      };

  static TrainingPlan? tryParse(Object? raw, {String? source}) {
    final j = _map(raw);
    if (j == null) return null;
    final days = _list<TrainingDay>(j['days'], TrainingDay.tryParse, max: 7);
    if (days.isEmpty) return null;
    // Un solo bloque por día de la semana.
    final byDay = <int, TrainingDay>{for (final d in days) d.weekday: d};
    final sorted = byDay.values.toList()
      ..sort((a, b) => a.weekday.compareTo(b.weekday));
    return TrainingPlan(
      title: _s(j['title'], max: 80, fallback: 'Plan de entrenamiento'),
      summary: _s(j['summary'], max: 600),
      weeks: _i(j['weeks'], min: 1, max: 104, fallback: 8),
      progression: _s(j['progression'], max: 400),
      references: _list<String>(j['references'], (r) {
        final s = r is String ? r.trim() : '';
        final uri = Uri.tryParse(s);
        return (uri != null && uri.scheme == 'https' && s.length < 300) ? s : null;
      }, max: 10),
      source: source ?? _s(j['source'], max: 10, fallback: 'local'),
      createdAt: DateTime.tryParse('${j['createdAt']}') ?? DateTime.now(),
      days: sorted,
    );
  }
}

// --------------------------------------------------------------- Nutrición

enum MealSlot { breakfast, snackAm, lunch, snackPm, dinner }

extension MealSlotX on MealSlot {
  String get label => switch (this) {
        MealSlot.breakfast => 'Desayuno',
        MealSlot.snackAm => 'Colación AM',
        MealSlot.lunch => 'Almuerzo',
        MealSlot.snackPm => 'Colación PM',
        MealSlot.dinner => 'Cena',
      };

  static MealSlot parse(Object? v) {
    for (final s in MealSlot.values) {
      if (s.name == v) return s;
    }
    return MealSlot.lunch;
  }
}

@immutable
class Meal {
  const Meal({
    required this.slot,
    required this.time,
    required this.name,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.description = '',
    this.alternatives = const [],
  });

  final MealSlot slot;

  /// "HH:mm"
  final String time;
  final String name;
  final String description;
  final int kcal;
  final int proteinG;
  final int carbsG;
  final int fatG;
  final List<String> alternatives;

  int get hour => int.tryParse(time.split(':').first) ?? 12;
  int get minute =>
      int.tryParse(time.split(':').length > 1 ? time.split(':')[1] : '0') ?? 0;

  Map<String, dynamic> toJson() => {
        'slot': slot.name,
        'time': time,
        'name': name,
        'description': description,
        'kcal': kcal,
        'proteinG': proteinG,
        'carbsG': carbsG,
        'fatG': fatG,
        'alternatives': alternatives,
      };

  static Meal? tryParse(Object? raw) {
    final j = _map(raw);
    if (j == null) return null;
    final name = _s(j['name'], max: 80);
    if (name.isEmpty) return null;
    final time = '${j['time']}';
    final valid = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(time);
    return Meal(
      slot: MealSlotX.parse(j['slot']),
      time: valid ? time : '12:00',
      name: name,
      description: _s(j['description'], max: 300),
      kcal: _i(j['kcal'], min: 0, max: 3000, fallback: 0),
      proteinG: _i(j['proteinG'], min: 0, max: 300, fallback: 0),
      carbsG: _i(j['carbsG'], min: 0, max: 500, fallback: 0),
      fatG: _i(j['fatG'], min: 0, max: 250, fallback: 0),
      alternatives: _list<String>(
          j['alternatives'], (a) => a is String ? _s(a, max: 120) : null,
          max: 4),
    );
  }
}

@immutable
class NutritionDay {
  const NutritionDay({required this.weekday, required this.meals});

  final int weekday;
  final List<Meal> meals;

  int get kcal => meals.fold(0, (sum, m) => sum + m.kcal);

  Map<String, dynamic> toJson() => {
        'weekday': weekday,
        'meals': meals.map((m) => m.toJson()).toList(),
      };

  static NutritionDay? tryParse(Object? raw) {
    final j = _map(raw);
    if (j == null) return null;
    final meals = _list<Meal>(j['meals'], Meal.tryParse, max: 6)
      ..sort((a, b) => a.time.compareTo(b.time));
    if (meals.isEmpty) return null;
    return NutritionDay(
      weekday: _i(j['weekday'], min: 1, max: 7, fallback: 1),
      meals: meals,
    );
  }
}

@immutable
class NutritionPlan {
  const NutritionPlan({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.days,
    this.notes = const [],
  });

  final int calories;
  final int proteinG;
  final int carbsG;
  final int fatG;
  final List<NutritionDay> days;
  final List<String> notes;

  NutritionDay? dayFor(DateTime date) {
    for (final d in days) {
      if (d.weekday == date.weekday) return d;
    }
    return days.isEmpty ? null : days.first;
  }

  Map<String, dynamic> toJson() => {
        'calories': calories,
        'proteinG': proteinG,
        'carbsG': carbsG,
        'fatG': fatG,
        'notes': notes,
        'days': days.map((d) => d.toJson()).toList(),
      };

  static NutritionPlan? tryParse(Object? raw) {
    final j = _map(raw);
    if (j == null) return null;
    final days = _list<NutritionDay>(j['days'], NutritionDay.tryParse, max: 7);
    if (days.isEmpty) return null;
    return NutritionPlan(
      calories: _i(j['calories'], min: 1000, max: 6000, fallback: 2000),
      proteinG: _i(j['proteinG'], min: 20, max: 400, fallback: 120),
      carbsG: _i(j['carbsG'], min: 20, max: 800, fallback: 220),
      fatG: _i(j['fatG'], min: 20, max: 250, fallback: 65),
      notes: _list<String>(
          j['notes'], (n) => n is String ? _s(n, max: 240) : null,
          max: 8),
      days: days,
    );
  }
}

/// Plan completo guardado en la base cifrada.
@immutable
class FitnessPlan {
  const FitnessPlan({required this.training, required this.nutrition});

  final TrainingPlan training;
  final NutritionPlan nutrition;

  Map<String, dynamic> toJson() => {
        'training': training.toJson(),
        'nutrition': nutrition.toJson(),
      };

  static FitnessPlan? tryParse(Object? raw, {String? source}) {
    final j = _map(raw);
    if (j == null) return null;
    final training = TrainingPlan.tryParse(j['training'], source: source);
    final nutrition = NutritionPlan.tryParse(j['nutrition']);
    if (training == null || nutrition == null) return null;
    return FitnessPlan(training: training, nutrition: nutrition);
  }
}
