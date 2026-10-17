import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;

import '../onboarding/user_profile.dart';
import '../plan/goal_analyzer.dart';
import '../plan/plan_models.dart';
import '../progress/muscle_group.dart';
import 'interval_engine.dart';

enum CircuitCategory { gym, calisthenics, home, hiit, boxing, cardio, mobility, core }

extension CircuitCategoryX on CircuitCategory {
  String get label => switch (this) {
        CircuitCategory.gym => 'Gimnasio',
        CircuitCategory.calisthenics => 'Calistenia',
        CircuitCategory.home => 'En casa',
        CircuitCategory.hiit => 'HIIT',
        CircuitCategory.boxing => 'Boxeo',
        CircuitCategory.cardio => 'Cardio',
        CircuitCategory.mobility => 'Movilidad',
        CircuitCategory.core => 'Core',
      };

  IconData get icon => switch (this) {
        CircuitCategory.gym => Icons.fitness_center,
        CircuitCategory.calisthenics => Icons.sports_gymnastics,
        CircuitCategory.home => Icons.home_outlined,
        CircuitCategory.hiit => Icons.bolt,
        CircuitCategory.boxing => Icons.sports_mma,
        CircuitCategory.cardio => Icons.directions_run,
        CircuitCategory.mobility => Icons.self_improvement,
        CircuitCategory.core => Icons.center_focus_strong,
      };
}

/// Un ejercicio del circuito: por tiempo ([seconds]) o por repeticiones.
@immutable
class CircuitStep {
  const CircuitStep(
    this.name, {
    this.seconds,
    this.reps,
    this.muscles = const [],
    this.cue = '',
  });

  final String name;
  final int? seconds;
  final String? reps;
  final List<MuscleGroup> muscles;
  final String cue;
}

@immutable
class Circuit {
  const Circuit({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.steps,
    this.rounds = 3,
    this.restBetweenSteps = 15,
    this.restBetweenRounds = 60,
    this.level = 'Todos los niveles',
  });

  final String id;
  final String name;
  final CircuitCategory category;
  final String description;
  final List<CircuitStep> steps;
  final int rounds;
  final int restBetweenSteps;
  final int restBetweenRounds;
  final String level;

  /// Minutos aproximados (las repeticiones se estiman en ~40 s por serie).
  int get estimatedMinutes {
    var s = 10;
    for (var r = 0; r < rounds; r++) {
      for (var i = 0; i < steps.length; i++) {
        s += steps[i].seconds ?? 40;
        if (i < steps.length - 1) s += restBetweenSteps;
      }
      if (r < rounds - 1) s += restBetweenRounds;
    }
    return max(1, (s / 60).round());
  }

  static String _secondsWords(int s) {
    if (s < 90) return '$s segundos';
    final m = s / 60;
    return m == m.roundToDouble() ? '${m.round()} minutos' : '${m.toStringAsFixed(1)} minutos';
  }

  IntervalProgram toProgram() {
    final phases = <IntervalPhase>[
      IntervalPhase(
        label: 'Prepárate',
        spoken: 'Prepárate. $name: $rounds ${rounds == 1 ? 'ronda' : 'rondas'}. '
            'Empezamos con ${steps.first.name}.',
        kind: PhaseKind.prepare,
        seconds: 10,
      ),
    ];
    for (var r = 1; r <= rounds; r++) {
      for (var i = 0; i < steps.length; i++) {
        final st = steps[i];
        final roundLabel = rounds > 1 ? ' · ronda $r/$rounds' : '';
        final cue = st.cue.isEmpty ? '' : ' ${st.cue}';
        phases.add(IntervalPhase(
          label: '${st.name}$roundLabel',
          spoken: st.seconds != null
              ? '¡${st.name} por ${_secondsWords(st.seconds!)}!$cue'
              : '${st.name}: ${st.reps ?? 'a tu ritmo'}.$cue Toca siguiente al terminar.',
          kind: PhaseKind.work,
          seconds: st.seconds,
        ));
        final lastStep = i == steps.length - 1;
        if (!lastStep && restBetweenSteps > 0) {
          phases.add(IntervalPhase(
            label: 'Descanso',
            spoken: '¡Descanso de $restBetweenSteps segundos! Siguiente: ${steps[i + 1].name}',
            kind: PhaseKind.rest,
            seconds: restBetweenSteps,
          ));
        }
        if (lastStep && r < rounds && restBetweenRounds > 0) {
          phases.add(IntervalPhase(
            label: 'Descanso entre rondas',
            spoken: 'Ronda $r completa. Descanso de ${_secondsWords(restBetweenRounds)}.',
            kind: PhaseKind.rest,
            seconds: restBetweenRounds,
          ));
        }
      }
    }
    return IntervalProgram(name: name, phases: phases);
  }

  /// Para registrar la sesión y que cuente en el mapa del cuerpo.
  TrainingDay toTrainingDay() => TrainingDay(
        weekday: DateTime.now().weekday,
        title: name,
        focus: category.label,
        exercises: [
          for (final st in steps)
            st.seconds != null
                ? Exercise(
                    name: st.name,
                    kind: ExerciseKind.cardio,
                    sets: 1,
                    reps: 'por tiempo',
                    restSec: 0,
                    durationSec: st.seconds! * rounds,
                    muscles: st.muscles,
                  )
                : Exercise(
                    name: st.name,
                    kind: ExerciseKind.strength,
                    sets: rounds,
                    reps: st.reps ?? '10',
                    restSec: restBetweenRounds,
                    muscles: st.muscles,
                  ),
        ],
      );
}

// Grupos musculares frecuentes.
const _legs = [MuscleGroup.quads, MuscleGroup.glutes];
const _legsFull = [MuscleGroup.quads, MuscleGroup.glutes, MuscleGroup.hamstrings, MuscleGroup.calves];
const _post = [MuscleGroup.hamstrings, MuscleGroup.glutes, MuscleGroup.lowerBack];
const _push = [MuscleGroup.chest, MuscleGroup.triceps, MuscleGroup.shoulders];
const _shoulders = [MuscleGroup.shoulders, MuscleGroup.triceps];
const _pull = [MuscleGroup.lats, MuscleGroup.biceps, MuscleGroup.traps];
const _arms = [MuscleGroup.biceps, MuscleGroup.triceps, MuscleGroup.forearms];
const _core = [MuscleGroup.abs, MuscleGroup.obliques];
const _calves = [MuscleGroup.calves];
const _full = [MuscleGroup.quads, MuscleGroup.glutes, MuscleGroup.shoulders, MuscleGroup.abs];
const _boxing = [MuscleGroup.shoulders, MuscleGroup.chest, MuscleGroup.obliques, MuscleGroup.calves];
const _back = [MuscleGroup.lowerBack, MuscleGroup.abs, MuscleGroup.glutes];

/// Biblioteca del modo libre / mantenimiento: entrena lo que quieras hoy,
/// sin depender del plan.
class CircuitLibrary {
  CircuitLibrary._();

  static const List<Circuit> all = [
    // ---------------------------------------------------------- gimnasio
    Circuit(
      id: 'gym_5x5',
      name: 'Fuerza 5×5 cuerpo completo',
      category: CircuitCategory.gym,
      description: 'Los tres básicos alternados. Elige un peso que puedas mover 5 veces con técnica limpia.',
      level: 'Intermedio',
      rounds: 5,
      restBetweenSteps: 90,
      restBetweenRounds: 90,
      steps: [
        CircuitStep('Sentadilla con barra', reps: '5', muscles: _legs),
        CircuitStep('Press de banca', reps: '5', muscles: _push),
        CircuitStep('Remo con barra', reps: '5', muscles: _pull),
      ],
    ),
    Circuit(
      id: 'gym_legs',
      name: 'Pierna en gimnasio',
      category: CircuitCategory.gym,
      description: 'Cuádriceps, femorales, glúteos y pantorrillas.',
      rounds: 3,
      restBetweenSteps: 60,
      restBetweenRounds: 90,
      steps: [
        CircuitStep('Prensa de piernas', reps: '10–12', muscles: _legs),
        CircuitStep('Peso muerto rumano', reps: '8–10', muscles: _post),
        CircuitStep('Zancada búlgara con mancuernas', reps: '10 por pierna', muscles: _legs),
        CircuitStep('Curl femoral', reps: '12', muscles: [MuscleGroup.hamstrings]),
        CircuitStep('Elevación de talones', reps: '15', muscles: _calves),
      ],
    ),
    Circuit(
      id: 'gym_upper',
      name: 'Torso: empuje y tirón',
      category: CircuitCategory.gym,
      description: 'Pecho, espalda y hombros en superseries.',
      rounds: 3,
      restBetweenSteps: 45,
      restBetweenRounds: 90,
      steps: [
        CircuitStep('Press inclinado con mancuernas', reps: '10', muscles: _push),
        CircuitStep('Jalón al pecho', reps: '10', muscles: _pull),
        CircuitStep('Press militar con mancuernas', reps: '10', muscles: _shoulders),
        CircuitStep('Remo en polea baja', reps: '12', muscles: _pull),
        CircuitStep('Fondos en paralelas', reps: '8–12', muscles: _push),
      ],
    ),
    Circuit(
      id: 'gym_arms',
      name: 'Brazos y hombros (bombeo)',
      category: CircuitCategory.gym,
      description: 'Descansos cortos para un buen bombeo.',
      rounds: 3,
      restBetweenSteps: 30,
      restBetweenRounds: 60,
      steps: [
        CircuitStep('Curl con barra', reps: '12', muscles: _arms),
        CircuitStep('Extensión de tríceps en polea', reps: '12', muscles: _arms),
        CircuitStep('Elevaciones laterales', reps: '15', muscles: [MuscleGroup.shoulders]),
        CircuitStep('Curl martillo', reps: '12', muscles: _arms),
        CircuitStep('Face pull', reps: '15', muscles: [MuscleGroup.shoulders, MuscleGroup.traps]),
      ],
    ),
    Circuit(
      id: 'gym_db_full',
      name: 'Cuerpo completo con mancuernas',
      category: CircuitCategory.gym,
      description: 'Para cuando el gimnasio está lleno: solo un par de mancuernas.',
      rounds: 4,
      restBetweenSteps: 30,
      restBetweenRounds: 75,
      steps: [
        CircuitStep('Sentadilla goblet', reps: '12', muscles: _legs),
        CircuitStep('Press de banca con mancuernas', reps: '10', muscles: _push),
        CircuitStep('Remo con mancuerna', reps: '10 por brazo', muscles: _pull),
        CircuitStep('Peso muerto rumano con mancuernas', reps: '12', muscles: _post),
        CircuitStep('Plancha', seconds: 40, muscles: _core),
      ],
    ),
    // -------------------------------------------------------- calistenia
    Circuit(
      id: 'cal_basic',
      name: 'Calistenia básica',
      category: CircuitCategory.calisthenics,
      description: 'Barra, paralelas y banca: cuerpo completo en el parque.',
      rounds: 3,
      restBetweenSteps: 30,
      restBetweenRounds: 90,
      steps: [
        CircuitStep('Dominadas (o negativas lentas)', reps: 'máximo técnico', muscles: _pull),
        CircuitStep('Fondos en paralelas', reps: '8–12', muscles: _push),
        CircuitStep('Remo australiano', reps: '12', muscles: _pull),
        CircuitStep('Sentadilla búlgara en banca', reps: '10 por pierna', muscles: _legs),
        CircuitStep('Elevación de rodillas colgado', reps: '12', muscles: _core),
      ],
    ),
    Circuit(
      id: 'cal_push',
      name: 'Empuje en paralelas',
      category: CircuitCategory.calisthenics,
      description: 'Pecho, hombros y tríceps con tu peso.',
      rounds: 4,
      restBetweenSteps: 30,
      restBetweenRounds: 75,
      steps: [
        CircuitStep('Fondos en paralelas', reps: '8–12', muscles: _push),
        CircuitStep('Flexiones con pies elevados', reps: '12', muscles: _push),
        CircuitStep('Flexiones pike', reps: '8–10', muscles: _shoulders),
        CircuitStep('Plancha', seconds: 45, muscles: _core),
      ],
    ),
    Circuit(
      id: 'cal_pull',
      name: 'Tirón en barra',
      category: CircuitCategory.calisthenics,
      description: 'Espalda y bíceps; agarre más fuerte.',
      rounds: 4,
      restBetweenSteps: 30,
      restBetweenRounds: 90,
      steps: [
        CircuitStep('Dominadas', reps: 'máximo técnico', muscles: _pull),
        CircuitStep('Remo australiano con pies elevados', reps: '10', muscles: _pull),
        CircuitStep('Dominada isométrica arriba', seconds: 20, muscles: _pull),
        CircuitStep('Colgado activo', seconds: 30, muscles: [MuscleGroup.forearms, MuscleGroup.lats]),
      ],
    ),
    Circuit(
      id: 'cal_legs',
      name: 'Piernas en el parque',
      category: CircuitCategory.calisthenics,
      description: 'Potencia y resistencia de piernas con una banca.',
      rounds: 3,
      restBetweenSteps: 20,
      restBetweenRounds: 90,
      steps: [
        CircuitStep('Sentadilla con salto', reps: '12', muscles: _legs),
        CircuitStep('Zancadas caminando', reps: '20 pasos', muscles: _legsFull),
        CircuitStep('Subidas a banca', reps: '12 por pierna', muscles: _legs),
        CircuitStep('Pistol asistida a banca', reps: '6 por pierna', muscles: _legs),
        CircuitStep('Sentadilla isométrica en pared', seconds: 45, muscles: _legs),
      ],
    ),
    // ----------------------------------------------------------- en casa
    Circuit(
      id: 'home_full',
      name: 'Cuerpo completo en casa',
      category: CircuitCategory.home,
      description: 'Sin equipo, unos 20 minutos.',
      rounds: 3,
      restBetweenSteps: 20,
      restBetweenRounds: 60,
      steps: [
        CircuitStep('Sentadillas', reps: '15', muscles: _legs),
        CircuitStep('Flexiones', reps: '10–12', muscles: _push),
        CircuitStep('Zancadas hacia atrás', reps: '10 por pierna', muscles: _legsFull),
        CircuitStep('Remo invertido bajo una mesa', reps: '10', muscles: _pull),
        CircuitStep('Plancha', seconds: 40, muscles: _core),
      ],
    ),
    Circuit(
      id: 'home_legs',
      name: 'Pierna y glúteo en casa',
      category: CircuitCategory.home,
      description: 'Tren inferior completo sin equipo.',
      rounds: 3,
      restBetweenSteps: 20,
      restBetweenRounds: 60,
      steps: [
        CircuitStep('Sentadilla 1½', reps: '12', muscles: _legs),
        CircuitStep('Puente de glúteo a una pierna', reps: '12 por lado', muscles: _post),
        CircuitStep('Zancada lateral', reps: '10 por lado', muscles: _legs),
        CircuitStep('Sentadilla isométrica en pared', seconds: 45, muscles: _legs),
        CircuitStep('Elevación de talones', reps: '20', muscles: _calves),
      ],
    ),
    Circuit(
      id: 'home_upper',
      name: 'Tren superior en casa',
      category: CircuitCategory.home,
      description: 'Pecho, hombros, espalda y core con una silla.',
      rounds: 3,
      restBetweenSteps: 20,
      restBetweenRounds: 60,
      steps: [
        CircuitStep('Flexiones', reps: '10–15', muscles: _push),
        CircuitStep('Fondos en silla', reps: '12', muscles: _arms),
        CircuitStep('Flexiones pike', reps: '8–10', muscles: _shoulders),
        CircuitStep('Superman', reps: '15', muscles: _back),
        CircuitStep('Plancha con toque de hombro', reps: '20', muscles: _core),
      ],
    ),
    Circuit(
      id: 'home_express',
      name: 'Express 10 minutos',
      category: CircuitCategory.home,
      description: 'Cuando no hay tiempo: 40 s de trabajo, 20 s de pausa.',
      rounds: 3,
      restBetweenSteps: 20,
      restBetweenRounds: 20,
      steps: [
        CircuitStep('Sentadillas', seconds: 40, muscles: _legs),
        CircuitStep('Flexiones', seconds: 40, muscles: _push),
        CircuitStep('Escaladores', seconds: 40, muscles: _core),
        CircuitStep('Zancadas alternas', seconds: 40, muscles: _legsFull),
      ],
    ),
    // --------------------------------------------------------------- HIIT
    Circuit(
      id: 'hiit_4020',
      name: 'HIIT 40/20',
      category: CircuitCategory.hiit,
      description: 'Cinco ejercicios, dos vueltas. Intenso y corto.',
      level: 'Intermedio',
      rounds: 2,
      restBetweenSteps: 20,
      restBetweenRounds: 60,
      steps: [
        CircuitStep('Burpees', seconds: 40, muscles: _full),
        CircuitStep('Sentadilla con salto', seconds: 40, muscles: _legs),
        CircuitStep('Escaladores', seconds: 40, muscles: _core),
        CircuitStep('Jumping jacks', seconds: 40, muscles: _calves),
        CircuitStep('Flexiones', seconds: 40, muscles: _push),
      ],
    ),
    Circuit(
      id: 'hiit_tabata',
      name: 'Tabata',
      category: CircuitCategory.hiit,
      description: '8 intervalos de 20 s a tope con 10 s de pausa.',
      level: 'Avanzado',
      rounds: 4,
      restBetweenSteps: 10,
      restBetweenRounds: 10,
      steps: [
        CircuitStep('Sentadilla con salto', seconds: 20, muscles: _legs),
        CircuitStep('Escaladores', seconds: 20, muscles: _core),
      ],
    ),
    Circuit(
      id: 'hiit_3030',
      name: 'HIIT 30/30 principiante',
      category: CircuitCategory.hiit,
      description: 'Mismo tiempo de trabajo que de descanso.',
      level: 'Principiante',
      rounds: 3,
      restBetweenSteps: 30,
      restBetweenRounds: 60,
      steps: [
        CircuitStep('Jumping jacks', seconds: 30, muscles: _calves),
        CircuitStep('Sentadillas', seconds: 30, muscles: _legs),
        CircuitStep('Rodillas altas', seconds: 30, muscles: _legsFull),
        CircuitStep('Plancha', seconds: 30, muscles: _core),
      ],
    ),
    // -------------------------------------------------------------- boxeo
    Circuit(
      id: 'box_3x3',
      name: 'Boxeo 6 rounds de 3′',
      category: CircuitCategory.boxing,
      description: 'Saco o sombra, con 1 minuto de descanso entre rounds.',
      level: 'Intermedio',
      rounds: 2,
      restBetweenSteps: 60,
      restBetweenRounds: 60,
      steps: [
        CircuitStep('Jab y recto', seconds: 180, muscles: _boxing, cue: 'Guardia arriba, gira la cadera.'),
        CircuitStep('Ganchos y uppercuts', seconds: 180, muscles: _boxing, cue: 'Rodillas flexionadas.'),
        CircuitStep('Combinaciones libres', seconds: 180, muscles: _boxing, cue: 'Muévete y respira.'),
      ],
    ),
    Circuit(
      id: 'box_shadow',
      name: 'Sombra para principiantes',
      category: CircuitCategory.boxing,
      description: 'Rounds de 2 minutos para aprender las combinaciones.',
      level: 'Principiante',
      rounds: 3,
      restBetweenSteps: 45,
      restBetweenRounds: 45,
      steps: [
        CircuitStep('Jab, jab, recto', seconds: 120, muscles: _boxing),
        CircuitStep('Jab, recto, gancho', seconds: 120, muscles: _boxing),
      ],
    ),
    Circuit(
      id: 'box_core',
      name: 'Boxeo + core',
      category: CircuitCategory.boxing,
      description: 'Golpes al saco alternados con trabajo de abdomen.',
      rounds: 4,
      restBetweenSteps: 15,
      restBetweenRounds: 45,
      steps: [
        CircuitStep('Golpes al saco sin parar', seconds: 120, muscles: _boxing),
        CircuitStep('Plancha', seconds: 45, muscles: _core),
        CircuitStep('Giros rusos', seconds: 30, muscles: _core),
      ],
    ),
    // ------------------------------------------------------------- cardio
    Circuit(
      id: 'cardio_rope',
      name: 'Cuerda 10×45″',
      category: CircuitCategory.cardio,
      description: 'Coordinación y pantorrillas.',
      rounds: 10,
      restBetweenSteps: 0,
      restBetweenRounds: 15,
      steps: [CircuitStep('Saltos de cuerda', seconds: 45, muscles: _calves)],
    ),
    Circuit(
      id: 'cardio_fartlek',
      name: 'Fartlek 1′/1′',
      category: CircuitCategory.cardio,
      description: 'Corriendo, en bici o caminando rápido.',
      rounds: 8,
      restBetweenSteps: 0,
      restBetweenRounds: 0,
      steps: [
        CircuitStep('Rápido', seconds: 60, muscles: _legsFull),
        CircuitStep('Suave', seconds: 60, muscles: _legsFull),
      ],
    ),
    Circuit(
      id: 'cardio_walk',
      name: 'Caminata rápida 30′',
      category: CircuitCategory.cardio,
      description: 'Zona 2: puedes hablar, pero no cantar.',
      level: 'Principiante',
      rounds: 1,
      steps: [
        CircuitStep('Caminata rápida', seconds: 900, muscles: _legsFull, cue: 'Ritmo constante.'),
        CircuitStep('Caminata rápida, segunda mitad', seconds: 900, muscles: _legsFull, cue: 'Bebe un poco de agua.'),
      ],
      restBetweenSteps: 0,
    ),
    Circuit(
      id: 'cardio_stairs',
      name: 'Escaleras 8×1′',
      category: CircuitCategory.cardio,
      description: 'Sube rápido, baja caminando.',
      rounds: 8,
      restBetweenSteps: 0,
      restBetweenRounds: 60,
      steps: [CircuitStep('Sube escaleras', seconds: 60, muscles: _legsFull)],
    ),
    // ---------------------------------------------------------- movilidad
    Circuit(
      id: 'mob_total',
      name: 'Movilidad total',
      category: CircuitCategory.mobility,
      description: 'Para días de descanso o antes de entrenar.',
      level: 'Principiante',
      rounds: 1,
      restBetweenSteps: 10,
      steps: [
        CircuitStep('Gato-camello', seconds: 45, muscles: _back),
        CircuitStep('Rotaciones torácicas', seconds: 60, muscles: [MuscleGroup.obliques, MuscleGroup.lats]),
        CircuitStep('Estocada con rotación', seconds: 60, muscles: _legs),
        CircuitStep('Cadera 90/90', seconds: 60, muscles: [MuscleGroup.glutes]),
        CircuitStep('Sentadilla profunda sostenida', seconds: 45, muscles: _legs),
        CircuitStep('Estiramiento de isquiotibiales', seconds: 60, muscles: [MuscleGroup.hamstrings]),
      ],
    ),
    Circuit(
      id: 'mob_post',
      name: 'Estiramiento post-entreno',
      category: CircuitCategory.mobility,
      description: 'Bajar pulsaciones y relajar.',
      level: 'Principiante',
      rounds: 1,
      restBetweenSteps: 5,
      steps: [
        CircuitStep('Cuádriceps de pie (cada pierna)', seconds: 60, muscles: [MuscleGroup.quads]),
        CircuitStep('Isquiotibiales sentado', seconds: 60, muscles: [MuscleGroup.hamstrings]),
        CircuitStep('Pantorrilla en pared', seconds: 60, muscles: _calves),
        CircuitStep('Pecho en marco de puerta', seconds: 45, muscles: [MuscleGroup.chest]),
        CircuitStep('Postura del niño', seconds: 60, muscles: _back),
      ],
    ),
    Circuit(
      id: 'mob_knees',
      name: 'Rodillas y tobillos',
      category: CircuitCategory.mobility,
      description: 'Prepara las articulaciones para bajadas y carrera.',
      rounds: 2,
      restBetweenSteps: 10,
      restBetweenRounds: 30,
      steps: [
        CircuitStep('Tobillo a la pared', seconds: 45, muscles: _calves),
        CircuitStep('Bajadas lentas de escalón', reps: '8 por pierna', muscles: _legs),
        CircuitStep('Elevación de talones lenta', reps: '12', muscles: _calves),
        CircuitStep('Sentadilla isométrica en pared', seconds: 40, muscles: _legs),
      ],
    ),
    // --------------------------------------------------------------- core
    Circuit(
      id: 'core_10',
      name: 'Core 10′',
      category: CircuitCategory.core,
      description: 'Abdomen y zona media sin equipo.',
      rounds: 2,
      restBetweenSteps: 15,
      restBetweenRounds: 45,
      steps: [
        CircuitStep('Plancha frontal', seconds: 40, muscles: _core),
        CircuitStep('Dead bug', reps: '10 por lado', muscles: _core),
        CircuitStep('Plancha lateral derecha', seconds: 30, muscles: _core),
        CircuitStep('Plancha lateral izquierda', seconds: 30, muscles: _core),
        CircuitStep('Hollow hold', seconds: 25, muscles: _core),
        CircuitStep('Superman', reps: '12', muscles: _back),
      ],
    ),
    Circuit(
      id: 'core_bar',
      name: 'Abdomen en barra',
      category: CircuitCategory.core,
      description: 'Para el parque de calistenia.',
      level: 'Intermedio',
      rounds: 3,
      restBetweenSteps: 20,
      restBetweenRounds: 60,
      steps: [
        CircuitStep('Elevación de rodillas colgado', reps: '12', muscles: _core),
        CircuitStep('L-sit en paralelas', seconds: 15, muscles: _core),
        CircuitStep('Limpiaparabrisas (rodillas)', reps: '8 por lado', muscles: _core),
      ],
    ),
  ];

  static List<Circuit> byCategory(CircuitCategory c) =>
      all.where((x) => x.category == c).toList();
}

/// Circuitos del modo Objetivo: pensados para tu meta y escalados a la
/// semana del plan en la que estás.
class GoalCircuits {
  GoalCircuits._();

  static List<Circuit> forPlan(UserProfile p, TrainingPlan plan, TrainingWeek week) {
    final g = GoalAnalyzer.analyze(p);
    final t = plan.totalWeeks <= 1 ? 1.0 : (week.number - 1) / (plan.totalWeeks - 1);
    int lerp(num a, num b) => (a + (b - a) * t).round();
    final deload = week.deload;

    switch (g.type) {
      case GoalType.mountain:
        final pack = (g.packKg ?? 7) * (0.3 + 0.7 * t);
        var hikeMin = 60;
        for (final d in week.days) {
          for (final e in d.exercises) {
            if (e.name.startsWith('Caminata con desnivel') && e.durationSec != null) {
              hikeMin = (e.durationSec! / 60).round();
            }
          }
        }
        final blocks = max(2, (hikeMin / 15).round());
        return [
          Circuit(
            id: 'goal_stairs',
            name: 'Escaleras de montaña · semana ${week.number}',
            category: CircuitCategory.cardio,
            description: 'Sube a ritmo de volcán con mochila de ~${pack.round()} kg y baja caminando. '
                'Escaleras de edificio, gradas de estadio o una cuesta.',
            rounds: deload ? 4 : lerp(6, 12),
            restBetweenSteps: 0,
            restBetweenRounds: 90,
            steps: [
              CircuitStep('Sube escaleras o cuesta', seconds: deload ? 60 : lerp(60, 180),
                  muscles: _legsFull, cue: 'Paso corto y constante.'),
            ],
          ),
          Circuit(
            id: 'goal_descent',
            name: 'Piernas para la bajada',
            category: CircuitCategory.home,
            description: 'Fuerza excéntrica: protege las rodillas en el descenso, donde ocurren la mayoría de lesiones.',
            rounds: deload ? 2 : 3,
            restBetweenSteps: 20,
            restBetweenRounds: 60,
            steps: [
              const CircuitStep('Bajadas excéntricas de escalón (3 s)', reps: '10 por pierna', muscles: _legs),
              const CircuitStep('Sentadilla lenta (4 s abajo)', reps: '10', muscles: _legs),
              const CircuitStep('Zancada hacia atrás', reps: '10 por pierna', muscles: _legsFull),
              CircuitStep('Sentadilla isométrica en pared', seconds: lerp(40, 75), muscles: _legs),
              const CircuitStep('Elevación de talones', reps: '20', muscles: _calves),
            ],
          ),
          const Circuit(
            id: 'goal_pack_core',
            name: 'Core y espalda para la mochila',
            category: CircuitCategory.core,
            description: 'Tronco estable para cargar peso muchas horas.',
            rounds: 3,
            restBetweenSteps: 15,
            restBetweenRounds: 45,
            steps: [
              CircuitStep('Plancha', seconds: 45, muscles: _core),
              CircuitStep('Bird dog', reps: '10 por lado', muscles: _back),
              CircuitStep('Superman', reps: '12', muscles: _back),
              CircuitStep('Plancha lateral', seconds: 30, muscles: _core),
              CircuitStep('Paseo con mochila cargada', seconds: 60, muscles: [MuscleGroup.traps, MuscleGroup.forearms, MuscleGroup.abs]),
            ],
          ),
          Circuit(
            id: 'goal_hike',
            name: 'Caminata guiada con mochila · ${GoalAnalyzer.fmtHours(blocks * 15 / 60)}',
            category: CircuitCategory.cardio,
            description: 'La caminata larga de esta semana, en bloques de 15 minutos con recordatorios de agua.',
            rounds: blocks,
            restBetweenSteps: 0,
            restBetweenRounds: 0,
            steps: const [
              CircuitStep('Bloque de caminata', seconds: 900, muscles: _legsFull,
                  cue: 'Ritmo constante. Bebe unos tragos de agua.'),
            ],
          ),
          CircuitLibrary.all.firstWhere((c) => c.id == 'mob_knees'),
        ];
      case GoalType.running:
        return [
          Circuit(
            id: 'goal_fartlek',
            name: 'Fartlek de la semana ${week.number}',
            category: CircuitCategory.cardio,
            description: 'Cambios de ritmo para ganar velocidad sin series formales.',
            rounds: deload ? 5 : lerp(6, 10),
            restBetweenSteps: 0,
            restBetweenRounds: 0,
            steps: [
              CircuitStep('Rápido', seconds: lerp(45, 90), muscles: _legsFull, cue: 'Ritmo de 5k.'),
              const CircuitStep('Suave', seconds: 60, muscles: _legsFull),
            ],
          ),
          const Circuit(
            id: 'goal_run_strength',
            name: 'Fuerza para corredores',
            category: CircuitCategory.home,
            description: 'Pantorrillas, glúteo medio y core: menos lesiones y mejor zancada.',
            rounds: 3,
            restBetweenSteps: 15,
            restBetweenRounds: 60,
            steps: [
              CircuitStep('Elevación de talones a una pierna', reps: '15 por pierna', muscles: _calves),
              CircuitStep('Sentadilla búlgara', reps: '10 por pierna', muscles: _legs),
              CircuitStep('Puente de glúteo a una pierna', reps: '12 por lado', muscles: _post),
              CircuitStep('Plancha lateral', seconds: 30, muscles: _core),
              CircuitStep('Saltos a la comba o en el sitio', seconds: 40, muscles: _calves),
            ],
          ),
          const Circuit(
            id: 'goal_run_drills',
            name: 'Técnica de carrera',
            category: CircuitCategory.cardio,
            description: 'Antes de un rodaje: skipping, talones y progresivos.',
            rounds: 2,
            restBetweenSteps: 20,
            restBetweenRounds: 45,
            steps: [
              CircuitStep('Skipping (rodillas altas)', seconds: 20, muscles: _legsFull),
              CircuitStep('Talones al glúteo', seconds: 20, muscles: [MuscleGroup.hamstrings]),
              CircuitStep('Zancada saltada', seconds: 20, muscles: _legsFull),
              CircuitStep('Progresivo de 80 m', seconds: 20, muscles: _legsFull),
            ],
          ),
          CircuitLibrary.all.firstWhere((c) => c.id == 'mob_knees'),
        ];
      case GoalType.fatLoss:
        return [
          Circuit(
            id: 'goal_hiit',
            name: 'HIIT de la semana ${week.number}',
            category: CircuitCategory.hiit,
            description: 'Intervalos que crecen cada semana.',
            rounds: deload ? 4 : lerp(6, 10),
            restBetweenSteps: 0,
            restBetweenRounds: 60 - (week.number <= 4 ? 30 : 40),
            steps: [
              CircuitStep('Burpees / escaladores / sentadilla con salto',
                  seconds: week.number <= 4 ? 30 : 40, muscles: _full),
            ],
          ),
          Circuit(
            id: 'goal_metabolic',
            name: 'Circuito metabólico',
            category: CircuitCategory.home,
            description: 'Fuerza y cardio a la vez, con descansos cortos.',
            rounds: deload ? 2 : lerp(3, 5),
            restBetweenSteps: 15,
            restBetweenRounds: 60,
            steps: const [
              CircuitStep('Sentadillas', seconds: 40, muscles: _legs),
              CircuitStep('Flexiones', seconds: 40, muscles: _push),
              CircuitStep('Zancadas alternas', seconds: 40, muscles: _legsFull),
              CircuitStep('Remo invertido o con mochila', seconds: 40, muscles: _pull),
              CircuitStep('Escaladores', seconds: 40, muscles: _core),
            ],
          ),
          CircuitLibrary.all.firstWhere((c) => c.id == 'cardio_walk'),
          CircuitLibrary.all.firstWhere((c) => c.id == 'core_10'),
        ];
      case GoalType.muscle:
      case GoalType.strength:
        final finisher = switch (p.equipment) {
          Equipment.gym => CircuitLibrary.all.firstWhere((c) => c.id == 'gym_arms'),
          Equipment.calisthenics => CircuitLibrary.all.firstWhere((c) => c.id == 'cal_push'),
          Equipment.home => CircuitLibrary.all.firstWhere((c) => c.id == 'home_upper'),
        };
        return [
          finisher,
          const Circuit(
            id: 'goal_lift_mobility',
            name: 'Movilidad para levantar',
            category: CircuitCategory.mobility,
            description: 'Cadera, tobillos y hombros listos para sentadilla y press.',
            rounds: 1,
            restBetweenSteps: 10,
            steps: [
              CircuitStep('Sentadilla profunda sostenida', seconds: 45, muscles: _legs),
              CircuitStep('Tobillo a la pared', seconds: 45, muscles: _calves),
              CircuitStep('Dislocaciones de hombro con toalla', reps: '12', muscles: [MuscleGroup.shoulders]),
              CircuitStep('Cadera 90/90', seconds: 60, muscles: [MuscleGroup.glutes]),
              CircuitStep('Rotaciones torácicas', seconds: 45, muscles: [MuscleGroup.obliques]),
            ],
          ),
          CircuitLibrary.all.firstWhere((c) => c.id == 'core_10'),
        ];
      case GoalType.general:
        final base = switch (p.equipment) {
          Equipment.gym => CircuitLibrary.all.firstWhere((c) => c.id == 'gym_db_full'),
          Equipment.calisthenics => CircuitLibrary.all.firstWhere((c) => c.id == 'cal_basic'),
          Equipment.home => CircuitLibrary.all.firstWhere((c) => c.id == 'home_full'),
        };
        return [
          base,
          CircuitLibrary.all.firstWhere((c) => c.id == 'hiit_3030'),
          CircuitLibrary.all.firstWhere((c) => c.id == 'mob_total'),
        ];
    }
  }
}
