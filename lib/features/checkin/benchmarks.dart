import 'package:flutter/foundation.dart';

import '../onboarding/user_profile.dart';
import '../progress/muscle_group.dart';

enum BenchmarkInput {
  /// Un número (repeticiones, minutos, km, kg…).
  number,

  /// Peso × repeticiones → se guarda el 1RM estimado (fórmula de Epley).
  weightReps,

  /// Tiempo mm:ss → se guarda en segundos.
  time,
}

/// Una prueba medible que el usuario reporta en el check-in semanal.
@immutable
class Benchmark {
  const Benchmark({
    required this.id,
    required this.label,
    required this.unit,
    required this.hint,
    required this.muscles,
    this.input = BenchmarkInput.number,
    this.higherIsBetter = true,
    this.fullScoreGain = 0.3,
    this.decimals = 0,
  });

  final String id;
  final String label;
  final String unit;
  final String hint;
  final List<MuscleGroup> muscles;
  final BenchmarkInput input;
  final bool higherIsBetter;

  /// Mejora relativa que equivale a "progreso completo" en el mapa
  /// (p. ej. +20 % de 1RM o +50 % de minutos de caminata).
  final double fullScoreGain;
  final int decimals;

  String format(double v) {
    if (input == BenchmarkInput.time) {
      final s = v.round();
      return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    }
    final text = v.toStringAsFixed(decimals);
    return unit.isEmpty ? text : '$text $unit';
  }

  /// Mejora relativa entre [baseline] y [latest] (positiva = mejor).
  double improvement(double baseline, double latest) {
    if (baseline <= 0 || latest <= 0) return 0;
    return higherIsBetter ? latest / baseline - 1 : baseline / latest - 1;
  }

  static double epley(double kg, int reps) =>
      reps <= 1 ? kg : kg * (1 + reps / 30);
}

class Benchmarks {
  Benchmarks._();

  static const _legs = [MuscleGroup.quads, MuscleGroup.glutes];
  static const _push = [MuscleGroup.chest, MuscleGroup.triceps, MuscleGroup.shoulders];
  static const _pull = [MuscleGroup.lats, MuscleGroup.biceps, MuscleGroup.traps, MuscleGroup.forearms];
  static const _hinge = [MuscleGroup.hamstrings, MuscleGroup.glutes, MuscleGroup.lowerBack];
  static const _core = [MuscleGroup.abs, MuscleGroup.obliques];
  static const _endurance = [
    MuscleGroup.quads,
    MuscleGroup.glutes,
    MuscleGroup.hamstrings,
    MuscleGroup.calves,
  ];

  static const List<Benchmark> all = [
    // Montaña
    Benchmark(
      id: 'hike_min',
      label: 'Caminata más larga de la semana',
      unit: 'min',
      hint: 'Minutos caminando sin contar paradas largas.',
      muscles: _endurance,
      fullScoreGain: 1.0,
    ),
    Benchmark(
      id: 'pack_kg',
      label: 'Peso de la mochila en esa caminata',
      unit: 'kg',
      hint: 'Pésala en una báscula de baño contigo y sin ella.',
      muscles: [MuscleGroup.traps, MuscleGroup.lowerBack, MuscleGroup.abs],
      fullScoreGain: 1.0,
      decimals: 1,
    ),
    Benchmark(
      id: 'gain_m',
      label: 'Desnivel subido en la semana',
      unit: 'm',
      hint: 'De tu reloj o app de mapas. Sin GPS: pisos de escaleras × 3 m.',
      muscles: _endurance,
      fullScoreGain: 1.0,
    ),
    // Carrera
    Benchmark(
      id: 'long_run_km',
      label: 'Carrera más larga de la semana',
      unit: 'km',
      hint: 'Distancia de tu tirada larga.',
      muscles: _endurance,
      fullScoreGain: 0.8,
      decimals: 1,
    ),
    Benchmark(
      id: 'week_km',
      label: 'Kilómetros totales corridos',
      unit: 'km',
      hint: 'Suma de toda la semana.',
      muscles: _endurance,
      fullScoreGain: 0.8,
      decimals: 1,
    ),
    Benchmark(
      id: 'pace_1k',
      label: 'Mejor tiempo en 1 km',
      unit: '',
      hint: 'mm:ss, por ejemplo 5:40.',
      muscles: [MuscleGroup.calves, MuscleGroup.quads, MuscleGroup.hamstrings],
      input: BenchmarkInput.time,
      higherIsBetter: false,
      fullScoreGain: 0.15,
    ),
    // Fuerza en gimnasio (1RM estimado)
    Benchmark(
      id: 'squat_1rm',
      label: 'Sentadilla: mejor serie',
      unit: 'kg',
      hint: 'Peso y repeticiones de tu serie más pesada; calculamos tu 1RM.',
      muscles: _legs,
      input: BenchmarkInput.weightReps,
      fullScoreGain: 0.2,
    ),
    Benchmark(
      id: 'bench_1rm',
      label: 'Press de banca: mejor serie',
      unit: 'kg',
      hint: 'Peso y repeticiones de tu serie más pesada.',
      muscles: _push,
      input: BenchmarkInput.weightReps,
      fullScoreGain: 0.2,
    ),
    Benchmark(
      id: 'row_1rm',
      label: 'Remo o jalón: mejor serie',
      unit: 'kg',
      hint: 'Peso y repeticiones de tu serie más pesada.',
      muscles: _pull,
      input: BenchmarkInput.weightReps,
      fullScoreGain: 0.2,
    ),
    Benchmark(
      id: 'hinge_1rm',
      label: 'Peso muerto (rumano o normal): mejor serie',
      unit: 'kg',
      hint: 'Peso y repeticiones de tu serie más pesada.',
      muscles: _hinge,
      input: BenchmarkInput.weightReps,
      fullScoreGain: 0.2,
    ),
    // Peso corporal
    Benchmark(
      id: 'pushups',
      label: 'Flexiones seguidas (máximo)',
      unit: 'reps',
      hint: 'Con buena técnica, sin pausas largas.',
      muscles: _push,
      fullScoreGain: 0.5,
    ),
    Benchmark(
      id: 'pullups',
      label: 'Dominadas seguidas (máximo)',
      unit: 'reps',
      hint: 'Si aún no haces ninguna, pon 0 y registra negativas en notas.',
      muscles: _pull,
      fullScoreGain: 0.5,
    ),
    Benchmark(
      id: 'dips',
      label: 'Fondos en paralelas (máximo)',
      unit: 'reps',
      hint: 'Bajando hasta 90° de codo.',
      muscles: _push,
      fullScoreGain: 0.5,
    ),
    Benchmark(
      id: 'inv_rows',
      label: 'Remos invertidos seguidos (máximo)',
      unit: 'reps',
      hint: 'En mesa firme o barra baja.',
      muscles: _pull,
      fullScoreGain: 0.5,
    ),
    Benchmark(
      id: 'squats_60',
      label: 'Sentadillas en 60 segundos',
      unit: 'reps',
      hint: 'Completas, hasta la paralela.',
      muscles: _legs,
      fullScoreGain: 0.4,
    ),
    Benchmark(
      id: 'plank_s',
      label: 'Plancha frontal (máximo)',
      unit: 's',
      hint: 'Hasta que se pierda la postura.',
      muscles: _core,
      fullScoreGain: 0.6,
    ),
    // Composición
    Benchmark(
      id: 'waist_cm',
      label: 'Cintura (a la altura del ombligo)',
      unit: 'cm',
      hint: 'En ayunas, sin apretar la cinta.',
      muscles: [MuscleGroup.abs, MuscleGroup.obliques],
      higherIsBetter: false,
      fullScoreGain: 0.08,
      decimals: 1,
    ),
    Benchmark(
      id: 'body_kg',
      label: 'Peso corporal',
      unit: 'kg',
      hint: 'En ayunas, después de ir al baño.',
      muscles: [],
      decimals: 1,
    ),
    Benchmark(
      id: 'cardio_min',
      label: 'Minutos de cardio en la semana',
      unit: 'min',
      hint: 'Caminar rápido, bici, trote, HIIT…',
      muscles: [MuscleGroup.calves, MuscleGroup.quads],
      fullScoreGain: 1.0,
    ),
  ];

  static Benchmark? byId(String id) {
    for (final b in all) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// Pruebas que se preguntan cada semana según objetivo y equipo.
  static List<Benchmark> forProfile(UserProfile p, GoalType type) {
    final ids = <String>[
      ...switch (type) {
        GoalType.mountain => ['hike_min', 'pack_kg', 'gain_m'],
        GoalType.running => ['long_run_km', 'week_km', 'pace_1k'],
        GoalType.fatLoss => ['waist_cm', 'cardio_min'],
        GoalType.muscle || GoalType.strength || GoalType.general => <String>[],
      },
      ...switch (p.equipment) {
        Equipment.gym => type == GoalType.mountain || type == GoalType.running
            ? ['squat_1rm', 'plank_s']
            : ['squat_1rm', 'bench_1rm', 'row_1rm', 'hinge_1rm'],
        Equipment.calisthenics => type == GoalType.mountain || type == GoalType.running
            ? ['squats_60', 'plank_s']
            : ['pullups', 'dips', 'pushups', 'plank_s'],
        Equipment.home => type == GoalType.mountain || type == GoalType.running
            ? ['squats_60', 'plank_s']
            : ['pushups', 'inv_rows', 'squats_60', 'plank_s'],
      },
    ];
    return [for (final id in ids) byId(id)!];
  }
}
