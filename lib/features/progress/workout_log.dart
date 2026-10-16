import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_db.dart';
import '../plan/plan_models.dart';
import 'muscle_group.dart';

@immutable
class SetEntry {
  const SetEntry({required this.reps, this.weightKg = 0});

  final int reps;

  /// 0 = peso corporal.
  final double weightKg;

  Map<String, dynamic> toJson() => {'reps': reps, 'weightKg': weightKg};

  factory SetEntry.fromJson(Map<String, dynamic> j) => SetEntry(
        reps: ((j['reps'] as num?) ?? 0).clamp(0, 500).toInt(),
        weightKg: ((j['weightKg'] as num?) ?? 0).clamp(0, 1000).toDouble(),
      );
}

@immutable
class LoggedExercise {
  const LoggedExercise({
    required this.name,
    required this.kind,
    required this.muscles,
    this.sets = const [],
    this.durationSec,
    this.distanceKm,
  });

  final String name;
  final ExerciseKind kind;
  final List<MuscleGroup> muscles;
  final List<SetEntry> sets;
  final int? durationSec;
  final double? distanceKm;

  /// Carga de trabajo comparable entre sesiones del mismo ejercicio/músculo.
  /// Fuerza: Σ repeticiones × kg (peso corporal ≈ 60 % del peso del usuario).
  /// Cardio: minutos × 10 + km × 60.
  double volume(double bodyweightKg) {
    if (kind == ExerciseKind.cardio) {
      final minutes = (durationSec ?? 0) / 60;
      return minutes * 10 + (distanceKm ?? 0) * 60;
    }
    var total = 0.0;
    for (final s in sets) {
      final load = s.weightKg > 0 ? s.weightKg : bodyweightKg * 0.6;
      total += s.reps * load;
    }
    if (total == 0 && durationSec != null) total = durationSec! * 2.0;
    return total;
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': kind.name,
        'muscles': muscles.map((m) => m.name).toList(),
        'sets': sets.map((s) => s.toJson()).toList(),
        'durationSec': durationSec,
        'distanceKm': distanceKm,
      };

  factory LoggedExercise.fromJson(Map<String, dynamic> j) => LoggedExercise(
        name: (j['name'] as String?) ?? '',
        kind: ExerciseKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => ExerciseKind.strength,
        ),
        muscles: ((j['muscles'] as List?) ?? const [])
            .map(MuscleGroupX.tryParse)
            .whereType<MuscleGroup>()
            .toList(),
        sets: ((j['sets'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SetEntry.fromJson)
            .toList(),
        durationSec: (j['durationSec'] as num?)?.toInt(),
        distanceKm: (j['distanceKm'] as num?)?.toDouble(),
      );
}

@immutable
class WorkoutSession {
  const WorkoutSession({
    required this.id,
    required this.date,
    required this.title,
    required this.exercises,
  });

  final String id;
  final DateTime date;
  final String title;
  final List<LoggedExercise> exercises;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'title': title,
        'exercises': exercises.map((e) => e.toJson()).toList(),
      };

  static WorkoutSession? tryParse(Map<String, dynamic> j) {
    final date = DateTime.tryParse('${j['date']}');
    if (date == null) return null;
    return WorkoutSession(
      id: (j['id'] as String?) ?? date.millisecondsSinceEpoch.toString(),
      date: date,
      title: (j['title'] as String?) ?? 'Sesión',
      exercises: ((j['exercises'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LoggedExercise.fromJson)
          .toList(),
    );
  }
}

class WorkoutLogController extends StateNotifier<List<WorkoutSession>> {
  WorkoutLogController() : super(_load());

  static List<WorkoutSession> _load() {
    final list = LocalDb.readAllJson(LocalDb.workoutLogs)
        .map(WorkoutSession.tryParse)
        .whereType<WorkoutSession>()
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  Future<void> add(WorkoutSession session) async {
    await LocalDb.writeJson(LocalDb.workoutLogs, session.id, session.toJson());
    state = [...state, session]..sort((a, b) => a.date.compareTo(b.date));
  }

  Future<void> remove(String id) async {
    await LocalDb.box(LocalDb.workoutLogs).delete(id);
    state = state.where((s) => s.id != id).toList();
  }

  bool hasSessionOn(DateTime day) => state.any((s) =>
      s.date.year == day.year &&
      s.date.month == day.month &&
      s.date.day == day.day);

  void reset() => state = const [];
}

final workoutLogProvider =
    StateNotifierProvider<WorkoutLogController, List<WorkoutSession>>(
  (ref) => WorkoutLogController(),
);
