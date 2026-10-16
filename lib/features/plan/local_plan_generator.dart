import 'dart:math';

import '../onboarding/user_profile.dart';
import '../progress/muscle_group.dart';
import 'plan_models.dart';

/// Objetivos diarios de energía y macronutrientes.
class MacroTargets {
  const MacroTargets({
    required this.bmr,
    required this.tdee,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  final int bmr;
  final int tdee;
  final int calories;
  final int proteinG;
  final int carbsG;
  final int fatG;
}

/// Generador de planes 100 % offline basado en reglas y guías consolidadas
/// (Mifflin-St Jeor / Katch-McArdle, ACSM, ISSN para proteína).
///
/// Se usa cuando no hay internet, cuando el proxy de IA no está configurado
/// o si la respuesta de la IA no pasa la validación.
class LocalPlanGenerator {
  LocalPlanGenerator._();

  static FitnessPlan generate(UserProfile p, {DateTime? now}) {
    final created = now ?? DateTime.now();
    return FitnessPlan(
      training: _training(p, created),
      nutrition: _nutrition(p),
    );
  }

  // ---------------------------------------------------------------- energía

  static double bmr(UserProfile p) {
    final bf = p.bodyFatPct;
    if (bf != null) {
      // Katch-McArdle: más precisa si se conoce el % de grasa.
      final leanMass = p.weightKg * (1 - bf / 100);
      return 370 + 21.6 * leanMass;
    }
    // Mifflin-St Jeor.
    final base = 10 * p.weightKg + 6.25 * p.heightCm - 5 * p.age;
    return switch (p.sex) {
      Sex.male => base + 5,
      Sex.female => base - 161,
      Sex.other => base - 78,
    };
  }

  static MacroTargets targets(UserProfile p) {
    final b = bmr(p);
    final tdee = b * p.activity.factor;
    final factor = switch (p.goal.type) {
      GoalType.fatLoss => 0.80,
      GoalType.muscle => 1.10,
      GoalType.strength => 1.05,
      GoalType.mountain || GoalType.running || GoalType.general => 1.0,
    };
    // Nunca por debajo de 1.1 × BMR (déficits agresivos no son seguros).
    var kcal = max(tdee * factor, b * 1.1);
    kcal = (kcal / 50).round() * 50.0;

    final proteinPerKg = switch (p.goal.type) {
      GoalType.fatLoss => 2.0,
      GoalType.muscle || GoalType.strength => 1.8,
      GoalType.mountain || GoalType.running => 1.5,
      GoalType.general => 1.4,
    };
    // Con IMC alto se usa un peso de referencia (IMC 27.5) para no inflar la proteína.
    final h = p.heightCm / 100;
    final refWeight = min(p.weightKg, 27.5 * h * h);
    final protein = (proteinPerKg * refWeight).round();
    final fat = (kcal * 0.27 / 9).round();
    final carbs = max(50, ((kcal - protein * 4 - fat * 9) / 4).round());

    return MacroTargets(
      bmr: b.round(),
      tdee: tdee.round(),
      calories: kcal.round(),
      proteinG: protein,
      carbsG: carbs,
      fatG: fat,
    );
  }

  // ---------------------------------------------------------- entrenamiento

  static const _lower = [
    MuscleGroup.quads,
    MuscleGroup.hamstrings,
    MuscleGroup.glutes,
    MuscleGroup.calves,
  ];

  static TrainingPlan _training(UserProfile p, DateTime created) {
    final lib = _ExerciseLibrary(p);
    final weeks = p.goal.weeksLeft;
    final days = switch (p.goal.type) {
      GoalType.mountain => _mountainWeek(lib, p),
      GoalType.running => _runningWeek(lib, weeks),
      GoalType.fatLoss => _fatLossWeek(lib),
      GoalType.muscle || GoalType.strength => _upperLowerWeek(lib),
      GoalType.general => _fullBodyWeek(lib),
    };

    final progression = switch (p.goal.type) {
      GoalType.muscle =>
        'Doble progresión: cuando completes el tope de repeticiones en todas las series, sube 2.5–5 % la carga. Cada 4.ª semana reduce el volumen 40 % (descarga).',
      GoalType.strength =>
        'Sube 2.5 kg en tren superior y 5 kg en inferior cada semana mientras la técnica sea limpia. Si fallas dos sesiones seguidas, baja 10 % y vuelve a subir.',
      GoalType.fatLoss =>
        'Mantén las cargas (preservar músculo es la prioridad) y aumenta 5 min de cardio por semana hasta 40 min. Revisa peso semanal: objetivo −0.5 a −1 % por semana.',
      GoalType.running =>
        'Aumenta el volumen semanal como máximo 10 %. La tirada larga sube 1 km por semana; cada 4.ª semana se reduce. Las 2 últimas semanas antes de la meta: reduce volumen 30–40 % (tapering).',
      GoalType.mountain =>
        'Cada semana suma 15 min a la caminata larga y 1–2 kg a la mochila hasta 8–10 kg. Las escaleras/cuestas progresan de 6 a 12 repeticiones. Última semana: solo caminatas suaves.',
      GoalType.general =>
        'Añade una repetición por serie cada semana; al llegar al tope, sube la carga o usa una variante más difícil.',
    };

    final injuryNote = p.injuries.isEmpty
        ? ''
        : ' Se adaptaron ejercicios por: "${p.injuries}". Detén cualquier ejercicio que cause dolor y consulta a un profesional.';

    return TrainingPlan(
      title: switch (p.goal.type) {
        GoalType.mountain => 'Preparación de montaña',
        GoalType.running => 'Plan de carrera',
        GoalType.fatLoss => 'Recomposición y pérdida de grasa',
        GoalType.muscle => 'Hipertrofia torso/pierna',
        GoalType.strength => 'Fuerza torso/pierna',
        GoalType.general => 'Condición general cuerpo completo',
      },
      summary:
          'Plan de $weeks semanas para "${p.goal.description}" (${p.equipment.label.toLowerCase()}).$injuryNote',
      weeks: weeks,
      progression: progression,
      source: 'local',
      createdAt: created,
      days: days,
    );
  }

  static TrainingDay _rest(int weekday, {String title = 'Descanso activo'}) =>
      TrainingDay(
        weekday: weekday,
        title: title,
        focus: 'Movilidad suave y llegar a tu meta de pasos',
        requiresStepGoal: true,
        exercises: const [],
      );

  static Exercise _cardio(
    String name, {
    int? minutes,
    double? km,
    int sets = 1,
    String reps = '',
    int restSec = 0,
    String notes = '',
    List<MuscleGroup> muscles = _lower,
  }) =>
      Exercise(
        name: name,
        kind: ExerciseKind.cardio,
        sets: sets,
        reps: reps.isEmpty ? 'continuo' : reps,
        restSec: restSec,
        durationSec: minutes == null ? null : minutes * 60,
        distanceKm: km,
        muscles: muscles,
        notes: notes,
      );

  static List<TrainingDay> _upperLowerWeek(_ExerciseLibrary l) => [
        TrainingDay(weekday: 1, title: 'Pierna A', focus: 'Sentadilla y cadena posterior', exercises: [
          l.squat(), l.hinge(), l.lunge(), l.calves(), l.core(),
        ]),
        TrainingDay(weekday: 2, title: 'Torso A', focus: 'Empujes y tirones horizontales', exercises: [
          l.pushH(), l.pullH(), l.pushV(), l.pullV(), l.arms(),
        ]),
        _rest(3),
        TrainingDay(weekday: 4, title: 'Pierna B', focus: 'Bisagra de cadera y unilateral', exercises: [
          l.hinge(), l.squat(), l.stepUp(), l.calves(), l.core(),
        ]),
        TrainingDay(weekday: 5, title: 'Torso B', focus: 'Empujes y tirones verticales', exercises: [
          l.pushV(), l.pullV(), l.pushH(), l.pullH(), l.arms(),
        ]),
        TrainingDay(
          weekday: 6,
          title: 'Cardio zona 2',
          focus: 'Base aeróbica',
          requiresStepGoal: true,
          exercises: [_cardio('Caminata rápida o bici', minutes: 35, notes: 'Debes poder hablar en frases completas.')],
        ),
        _rest(7, title: 'Descanso'),
      ];

  static List<TrainingDay> _fullBodyWeek(_ExerciseLibrary l) => [
        TrainingDay(weekday: 1, title: 'Cuerpo completo A', exercises: [
          l.squat(), l.pushH(), l.pullH(), l.core(),
        ]),
        _rest(2),
        TrainingDay(weekday: 3, title: 'Cuerpo completo B', exercises: [
          l.hinge(), l.pushV(), l.pullV(), l.calves(),
        ]),
        _rest(4),
        TrainingDay(weekday: 5, title: 'Cuerpo completo C', exercises: [
          l.lunge(), l.pushH(), l.pullH(), l.core(),
        ]),
        TrainingDay(
          weekday: 6,
          title: 'Caminata larga',
          requiresStepGoal: true,
          exercises: [_cardio('Caminata', minutes: 45)],
        ),
        _rest(7, title: 'Descanso'),
      ];

  static List<TrainingDay> _fatLossWeek(_ExerciseLibrary l) => [
        TrainingDay(weekday: 1, title: 'Fuerza cuerpo completo A', exercises: [
          l.squat(), l.pushH(), l.pullH(), l.core(),
        ]),
        TrainingDay(
          weekday: 2,
          title: 'HIIT',
          focus: 'Usa el modo HIIT del timer',
          requiresStepGoal: true,
          exercises: [
            _cardio('Intervalos 40/20 (burpees, jumping jacks, sentadilla con salto, escaladores)',
                sets: 8, reps: '40 s trabajo / 20 s descanso', minutes: 8,
                muscles: const [MuscleGroup.quads, MuscleGroup.glutes, MuscleGroup.shoulders, MuscleGroup.abs]),
          ],
        ),
        TrainingDay(weekday: 3, title: 'Fuerza cuerpo completo B', exercises: [
          l.hinge(), l.pushV(), l.pullV(), l.lunge(),
        ]),
        TrainingDay(
          weekday: 4,
          title: 'Cardio zona 2',
          requiresStepGoal: true,
          exercises: [_cardio('Caminata inclinada, trote suave o bici', minutes: 30)],
        ),
        TrainingDay(weekday: 5, title: 'Fuerza cuerpo completo C', exercises: [
          l.squat(), l.pushH(), l.pullV(), l.calves(), l.core(),
        ]),
        TrainingDay(
          weekday: 6,
          title: 'Caminata larga',
          requiresStepGoal: true,
          exercises: [_cardio('Caminata al aire libre', minutes: 60)],
        ),
        _rest(7, title: 'Descanso'),
      ];

  static List<TrainingDay> _runningWeek(_ExerciseLibrary l, int weeks) {
    final longKm = min(16.0, 5.0 + weeks * 0.25);
    return [
      TrainingDay(
        weekday: 1,
        title: 'Rodaje suave',
        requiresStepGoal: true,
        exercises: [_cardio('Trote suave', km: 5, notes: 'Ritmo conversacional.')],
      ),
      TrainingDay(weekday: 2, title: 'Fuerza para corredores', exercises: [
        l.squat(), l.hinge(), l.stepUp(), l.calves(), l.core(),
      ]),
      TrainingDay(
        weekday: 3,
        title: 'Series',
        focus: 'Velocidad',
        exercises: [
          _cardio('Calentamiento', minutes: 10),
          _cardio('Series de 400 m a ritmo 5k', sets: 6, reps: '400 m', restSec: 90, km: 0.4),
          _cardio('Vuelta a la calma', minutes: 10),
        ],
      ),
      _rest(4),
      TrainingDay(
        weekday: 5,
        title: 'Tempo',
        exercises: [
          _cardio('Calentamiento', minutes: 10),
          _cardio('Tempo a ritmo "cómodamente duro"', minutes: 20),
          _cardio('Vuelta a la calma', minutes: 5),
        ],
      ),
      TrainingDay(
        weekday: 6,
        title: 'Tirada larga',
        requiresStepGoal: true,
        exercises: [_cardio('Carrera larga', km: double.parse(longKm.toStringAsFixed(1)))],
      ),
      _rest(7, title: 'Descanso'),
    ];
  }

  static List<TrainingDay> _mountainWeek(_ExerciseLibrary l, UserProfile p) => [
        TrainingDay(weekday: 1, title: 'Piernas de montaña', focus: 'Fuerza excéntrica para bajadas', exercises: [
          l.stepUp(), l.squat(), l.lunge(), l.calves(), l.core(),
        ]),
        TrainingDay(
          weekday: 2,
          title: 'Cardio zona 2',
          requiresStepGoal: true,
          exercises: [_cardio('Caminata rápida en cuesta o bici', minutes: 40)],
        ),
        TrainingDay(weekday: 3, title: 'Torso y core', exercises: [
          l.pullH(), l.pushH(), l.pullV(), l.carry(), l.core(),
        ]),
        TrainingDay(
          weekday: 4,
          title: 'Cuestas / escaleras',
          focus: 'Potencia aeróbica',
          requiresStepGoal: true,
          exercises: [
            _cardio('Calentamiento', minutes: 10),
            _cardio('Subidas fuertes de escaleras o cuesta (baja caminando)',
                sets: 8, reps: '90 s subida', restSec: 90,
                muscles: const [MuscleGroup.quads, MuscleGroup.glutes, MuscleGroup.calves]),
          ],
        ),
        _rest(5),
        TrainingDay(
          weekday: 6,
          title: 'Caminata larga con mochila',
          focus: 'Simulación de ruta',
          requiresStepGoal: true,
          exercises: [
            _cardio('Caminata con desnivel y mochila de 5–10 kg', minutes: 120,
                notes: 'Usa las botas y la mochila que llevarás el día de la meta.'),
          ],
        ),
        _rest(7, title: 'Descanso'),
      ];

  // ------------------------------------------------------------- nutrición

  static const _times = {
    MealSlot.breakfast: '07:00',
    MealSlot.snackAm: '10:00',
    MealSlot.lunch: '13:00',
    MealSlot.snackPm: '16:30',
    MealSlot.dinner: '19:30',
  };

  static const _shares = {
    MealSlot.breakfast: 0.25,
    MealSlot.snackAm: 0.10,
    MealSlot.lunch: 0.35,
    MealSlot.snackPm: 0.10,
    MealSlot.dinner: 0.20,
  };

  static const Map<MealSlot, List<String>> _menu = {
    MealSlot.breakfast: [
      'Huevos revueltos con frijoles volteados y 2 tortillas de maíz',
      'Mosh (avena) con leche, banano y una cucharada de crema de maní',
      'Omelette de espinaca y queso fresco con pan integral',
      'Licuado de leche, avena y papaya + 2 huevos duros',
      'Yogur griego con granola y fruta de temporada',
      'Panqueques de avena y huevo con fresas',
      'Huevos rancheros con frijol y aguacate',
    ],
    MealSlot.snackAm: [
      'Fruta + puñado de manías',
      'Yogur natural con canela',
      'Incaparina con leche',
      'Pan integral con aguacate',
      'Queso fresco con piña',
      'Elote cocido',
      'Mango con limón y semillas',
    ],
    MealSlot.lunch: [
      'Pollo a la plancha con arroz, frijoles y ensalada',
      'Pepián de pollo sin piel con arroz y güisquil',
      'Tilapia a la plancha con papas y verduras',
      'Carne guisada magra con arroz y vegetales',
      'Caldo de res con verduras y tortillas',
      'Pasta integral con atún y salsa de tomate',
      'Hilachas de res con arroz y ensalada',
    ],
    MealSlot.snackPm: [
      'Atún con galletas integrales',
      'Batido de leche y banano',
      'Huevo duro + fruta',
      'Yogur con avena',
      'Requesón con tortilla tostada',
      'Pan con frijol y queso fresco',
      'Manías + mandarina',
    ],
    MealSlot.dinner: [
      'Tortillas con frijol, huevo y aguacate',
      'Ensalada de pollo deshebrado con pan integral',
      'Tostadas de guacamol con pollo',
      'Sopa de verduras con queso fresco',
      'Omelette de vegetales con tortillas',
      'Wrap de pollo y verduras',
      'Arroz con huevo, frijol y plátano cocido',
    ],
  };

  static NutritionPlan _nutrition(UserProfile p) {
    final t = targets(p);
    final days = <NutritionDay>[];
    for (var day = 1; day <= 7; day++) {
      final meals = <Meal>[];
      for (final slot in MealSlot.values) {
        final options = _menu[slot]!;
        final share = _shares[slot]!;
        final main = options[(day - 1) % options.length];
        final alt1 = options[(day + 2) % options.length];
        final alt2 = options[(day + 4) % options.length];
        meals.add(Meal(
          slot: slot,
          time: _times[slot]!,
          name: main,
          description:
              'Ajusta las porciones para acercarte a ${(t.calories * share).round()} kcal.',
          kcal: (t.calories * share).round(),
          proteinG: (t.proteinG * share).round(),
          carbsG: (t.carbsG * share).round(),
          fatG: (t.fatG * share).round(),
          alternatives: [alt1, alt2],
        ));
      }
      days.add(NutritionDay(weekday: day, meals: meals));
    }

    return NutritionPlan(
      calories: t.calories,
      proteinG: t.proteinG,
      carbsG: t.carbsG,
      fatG: t.fatG,
      days: days,
      notes: [
        'Metabolismo basal estimado: ${t.bmr} kcal · gasto total: ${t.tdee} kcal.',
        'Reparte la proteína en todas las comidas (20–40 g por toma).',
        'Toma agua durante el día: meta de ${p.effectiveWaterGoalMl} ml.',
        'Estimaciones generales; si tienes una condición médica, valida con un nutricionista.',
      ],
    );
  }
}

/// Selecciona el ejercicio de cada patrón según el equipo y las lesiones.
class _ExerciseLibrary {
  _ExerciseLibrary(this.p)
      : _knee = RegExp(r'rodill|menisc|ligament|patel|condromal', caseSensitive: false)
            .hasMatch(p.injuries),
        _shoulder = RegExp(r'hombro|manguito|rotador', caseSensitive: false)
            .hasMatch(p.injuries),
        _back = RegExp(r'espalda|lumbar|hernia|ci[aá]tic|disco', caseSensitive: false)
            .hasMatch(p.injuries);

  final UserProfile p;
  final bool _knee;
  final bool _shoulder;
  final bool _back;

  Equipment get _eq => p.equipment;

  ({int sets, String reps, int rest}) get _scheme => switch (p.goal.type) {
        GoalType.strength => (sets: 5, reps: '3–5', rest: 180),
        GoalType.muscle => (sets: 4, reps: '8–12', rest: 90),
        GoalType.fatLoss => (sets: 3, reps: '10–15', rest: 45),
        GoalType.mountain => (sets: 3, reps: '10–12', rest: 60),
        GoalType.running => (sets: 3, reps: '8–10', rest: 60),
        GoalType.general => (sets: 3, reps: '8–12', rest: 75),
      };

  Exercise _ex(String name, List<MuscleGroup> muscles,
      {String? reps, int? sets, int? rest, String notes = ''}) {
    final s = _scheme;
    return Exercise(
      name: name,
      kind: ExerciseKind.strength,
      sets: sets ?? s.sets,
      reps: reps ?? s.reps,
      restSec: rest ?? s.rest,
      muscles: muscles,
      notes: notes,
    );
  }

  Exercise squat() {
    const m = [MuscleGroup.quads, MuscleGroup.glutes];
    if (_back || _knee) {
      return _ex('Sentadilla a cajón (rango cómodo)', m,
          notes: 'Baja controlado hasta tocar el cajón o la silla.');
    }
    return switch (_eq) {
      Equipment.gym => _ex('Sentadilla con barra', m),
      Equipment.calisthenics => _ex('Sentadilla búlgara en banca', m, reps: '8–12 por pierna'),
      Equipment.home => _ex('Sentadilla con pausa de 2 s', m),
    };
  }

  Exercise hinge() {
    const m = [MuscleGroup.hamstrings, MuscleGroup.glutes, MuscleGroup.lowerBack];
    if (_back) {
      return _ex('Puente de glúteo', const [MuscleGroup.glutes, MuscleGroup.hamstrings]);
    }
    return switch (_eq) {
      Equipment.gym => _ex('Peso muerto rumano', m),
      Equipment.calisthenics => _ex('Puente de glúteo a una pierna', m, reps: '10–15 por pierna'),
      Equipment.home => _ex('Peso muerto rumano con mochila', m),
    };
  }

  Exercise pushH() {
    const m = [MuscleGroup.chest, MuscleGroup.triceps, MuscleGroup.shoulders];
    return switch (_eq) {
      Equipment.gym => _ex('Press de banca', m),
      Equipment.calisthenics => _ex('Fondos en paralelas (o flexiones)', m),
      Equipment.home => _ex('Flexiones (pies elevados si son fáciles)', m),
    };
  }

  Exercise pushV() {
    const m = [MuscleGroup.shoulders, MuscleGroup.triceps];
    if (_shoulder) {
      return _ex('Y-T-W boca abajo (sin peso)', const [MuscleGroup.shoulders, MuscleGroup.traps],
          reps: '8 de cada letra', notes: 'Movimiento lento y sin dolor.');
    }
    return switch (_eq) {
      Equipment.gym => _ex('Press militar con mancuernas', m),
      Equipment.calisthenics || Equipment.home => _ex('Flexiones pike', m),
    };
  }

  Exercise pullH() {
    const m = [MuscleGroup.lats, MuscleGroup.traps, MuscleGroup.biceps];
    return switch (_eq) {
      Equipment.gym => _ex('Remo con barra', m),
      Equipment.calisthenics => _ex('Remo australiano en barra baja', m),
      Equipment.home => _ex('Remo con mochila a una mano', m, reps: '10–15 por brazo'),
    };
  }

  Exercise pullV() {
    const m = [MuscleGroup.lats, MuscleGroup.biceps, MuscleGroup.forearms];
    return switch (_eq) {
      Equipment.gym => _ex('Jalón al pecho', m),
      Equipment.calisthenics => _ex('Dominadas (o negativas lentas)', m, reps: 'máx. técnico'),
      Equipment.home => _ex('Remo invertido bajo una mesa firme', m),
    };
  }

  Exercise lunge() {
    const m = [MuscleGroup.quads, MuscleGroup.glutes, MuscleGroup.hamstrings];
    if (_knee) {
      return _ex('Puente de glúteo con pausa', const [MuscleGroup.glutes, MuscleGroup.hamstrings]);
    }
    return switch (_eq) {
      Equipment.gym => _ex('Zancadas con mancuernas', m, reps: '10 por pierna'),
      Equipment.calisthenics || Equipment.home =>
        _ex('Zancadas hacia atrás', m, reps: '10–12 por pierna'),
    };
  }

  Exercise stepUp() {
    const m = [MuscleGroup.quads, MuscleGroup.glutes, MuscleGroup.calves];
    final low = _knee ? ' (escalón bajo)' : '';
    return switch (_eq) {
      Equipment.gym => _ex('Step-up con mancuernas$low', m, reps: '10 por pierna'),
      Equipment.calisthenics => _ex('Subidas a banca del parque$low', m, reps: '12 por pierna'),
      Equipment.home => _ex('Subidas a escalón o silla firme$low', m, reps: '12 por pierna'),
    };
  }

  Exercise calves() => _ex(
        _eq == Equipment.gym
            ? 'Elevación de talones en máquina'
            : 'Elevación de talones a una pierna en escalón',
        const [MuscleGroup.calves],
        reps: '12–20',
        rest: 45,
      );

  Exercise core() => _ex(
        _eq == Equipment.calisthenics
            ? 'Elevación de rodillas colgado'
            : 'Plancha frontal + lateral',
        const [MuscleGroup.abs, MuscleGroup.obliques],
        reps: _eq == Equipment.calisthenics ? '10–15' : '30–45 s cada una',
        rest: 45,
      );

  Exercise arms() => _ex(
        _eq == Equipment.gym
            ? 'Curl con barra + extensión de tríceps en polea'
            : 'Flexiones diamante + curl con mochila',
        const [MuscleGroup.biceps, MuscleGroup.triceps, MuscleGroup.forearms],
        sets: 3,
        reps: '10–15',
        rest: 60,
      );

  Exercise carry() => _ex(
        _eq == Equipment.gym
            ? 'Paseo del granjero con mancuernas'
            : 'Paseo con mochila cargada',
        const [MuscleGroup.forearms, MuscleGroup.traps, MuscleGroup.abs],
        reps: '40 m',
        rest: 60,
      );
}
