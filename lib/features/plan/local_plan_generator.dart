import 'dart:math';

import '../checkin/benchmarks.dart';
import '../onboarding/user_profile.dart';
import '../progress/muscle_group.dart';
import 'goal_analyzer.dart';
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

class _Phase {
  const _Phase(this.name, this.focus, this.from, this.to, {this.taper = false});
  final String name;
  final String focus;
  final int from;
  final int to;
  final bool taper;
}

/// Contexto de una semana concreta para los constructores de rutinas.
class _Ctx {
  _Ctx({
    required this.week,
    required this.total,
    required this.peakWeek,
    required this.phaseIndex,
    required this.phase,
  });

  final int week;
  final int total;
  final int peakWeek;
  final int phaseIndex;
  final _Phase phase;

  bool get taper => phase.taper;
  bool get isLast => week == total;
  int get block => (week - 1) ~/ 4;
  int get weekInBlock => (week - 1) % 4 + 1;
  int get weekInPhase => week - phase.from + 1;

  /// 0 → 1 desde la semana 1 hasta la semana pico.
  double get t =>
      peakWeek <= 1 ? 1 : ((week - 1) / (peakWeek - 1)).clamp(0.0, 1.0).toDouble();

  double ramp(num from, num to) => from + (to - from) * t;
}

/// Generador de planes 100 % offline basado en reglas y guías consolidadas
/// (Mifflin-St Jeor / Katch-McArdle, ACSM, ISSN para proteína).
///
/// El plan es **periodizado**: se divide en fases según el objetivo y la
/// fecha límite, cada semana progresa (duración, distancia, carga o series),
/// los ejercicios rotan por bloque y cada 4.ª semana es de descarga.
class LocalPlanGenerator {
  LocalPlanGenerator._();

  static const int maxWeeks = 52;

  static FitnessPlan generate(UserProfile p, {DateTime? now}) {
    final created = now ?? DateTime.now();
    final spec = GoalAnalyzer.analyze(p);
    return FitnessPlan(
      training: _training(p, spec, created),
      nutrition: _nutrition(p, spec),
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

  static MacroTargets targets(UserProfile p, [GoalSpec? spec]) {
    final g = spec ?? GoalAnalyzer.analyze(p);
    final b = bmr(p);
    final tdee = b * p.activity.factor;
    var factor = switch (g.type) {
      GoalType.fatLoss => 0.80,
      GoalType.muscle => 1.10,
      GoalType.strength => 1.05,
      GoalType.mountain || GoalType.running || GoalType.general => 1.0,
    };
    // Déficit según la meta de kilos (7,700 kcal ≈ 1 kg), con tope de 25 %.
    final change = g.weightChangeKg;
    if (g.type == GoalType.fatLoss && change != null && change < 0) {
      final daily = (-change * 7700) / (p.goal.weeksLeft * 7);
      factor = (1 - daily / tdee).clamp(0.75, 0.9).toDouble();
    }
    // Más energía para cargas de resistencia largas.
    if (g.type == GoalType.mountain || g.type == GoalType.running) factor = 1.05;

    // Nunca por debajo de 1.1 × BMR (déficits agresivos no son seguros).
    var kcal = max(tdee * factor, b * 1.1);
    kcal = (kcal / 50).round() * 50.0;

    final proteinPerKg = switch (g.type) {
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

  /// Meta de pasos sugerida según el objetivo.
  static int defaultStepGoal(GoalType type, ActivityLevel activity) {
    final base = switch (type) {
      GoalType.mountain => 12000,
      GoalType.fatLoss => 10000,
      GoalType.general => 9000,
      GoalType.running => 8000,
      GoalType.muscle => 8000,
      GoalType.strength => 7000,
    };
    // Quien parte sedentario empieza con una meta alcanzable.
    return activity == ActivityLevel.sedentary ? min(base, 7000) : base;
  }

  // ---------------------------------------------------------- entrenamiento

  static int _r5(num v) => ((v / 5).round() * 5).toInt();
  static int _r15(num v) => ((v / 15).round() * 15).toInt();
  static double _rHalf(num v) => (v * 2).round() / 2;

  static List<_Phase> _layout(GoalType type, int total) {
    switch (type) {
      case GoalType.mountain:
      case GoalType.running:
        final taperWeeks = total >= 10 && type == GoalType.running
            ? 2
            : (total >= 4 ? 1 : 0);
        final available = total - taperWeeks;
        var base = max(1, (available * 0.45).round());
        var build = max(available >= 3 ? 1 : 0, (available * 0.35).round());
        if (base + build > available) build = max(0, available - base);
        final specific = available - base - build;
        final names = type == GoalType.mountain
            ? const ['Base aeróbica', 'Fuerza de montaña', 'Específica', 'Puesta a punto']
            : const ['Base', 'Construcción', 'Específica', 'Afinamiento'];
        final focus = type == GoalType.mountain
            ? const [
                'Construir resistencia aeróbica y la fuerza básica de piernas.',
                'Cuestas, escaleras y trabajo excéntrico para las bajadas.',
                'Simular la ruta: caminatas largas con la mochila real.',
                'Bajar volumen para llegar fresco al ascenso.',
              ]
            : const [
                'Kilómetros suaves y técnica: el motor aeróbico.',
                'Series y fuerza para correr más rápido.',
                'Ritmo de carrera y tiradas largas.',
                'Menos volumen, misma intensidad: llegar descansado.',
              ];
        final out = <_Phase>[];
        var w = 1;
        void add(int n, int i, {bool taper = false}) {
          if (n <= 0) return;
          out.add(_Phase(names[i], focus[i], w, w + n - 1, taper: taper));
          w += n;
        }
        add(base, 0);
        add(build, 1);
        add(specific, 2);
        add(taperWeeks, 3, taper: true);
        return out;
      case GoalType.muscle:
        return [
          for (var b = 0; b * 4 < total; b++)
            _Phase(
              'Bloque ${b + 1} · ${b.isEven ? 'Acumulación' : 'Intensificación'}',
              b.isEven
                  ? 'Más series en rangos de 10–12 reps: volumen para crecer.'
                  : 'Más carga en 6–8 reps: fuerza para seguir creciendo.',
              b * 4 + 1,
              min(total, b * 4 + 4),
            ),
        ];
      case GoalType.strength:
        final vol = max(1, (total * 0.4).round());
        final str = max(total > 2 ? 1 : 0, (total * 0.4).round());
        final peak = max(0, total - vol - str);
        return [
          _Phase('Volumen', 'Series de 6–8 para ganar base y técnica.', 1, vol),
          if (str > 0)
            _Phase('Fuerza', 'Series de 3–5 con más peso.', vol + 1, vol + str),
          if (peak > 0)
            _Phase('Pico', 'Cargas cercanas al máximo y prueba final.',
                vol + str + 1, total),
        ];
      case GoalType.fatLoss:
        final adapt = min(3, total);
        return [
          _Phase('Adaptación', 'Crear el hábito: fuerza, pasos y comidas ordenadas.', 1, adapt),
          if (total > adapt)
            _Phase('Déficit activo', 'Más cardio y densidad de entrenamiento; la fuerza conserva el músculo.',
                adapt + 1, total),
        ];
      case GoalType.general:
        final base = min(4, total);
        return [
          _Phase('Base', 'Técnica y constancia en los patrones básicos.', 1, base),
          if (total > base)
            _Phase('Progresión', 'Variantes más exigentes y más volumen.', base + 1, total),
        ];
    }
  }

  static TrainingPlan _training(UserProfile p, GoalSpec g, DateTime created) {
    final total = p.goal.weeksLeft.clamp(1, maxWeeks).toInt();
    final layout = _layout(g.type, total);
    final peakWeek = layout.lastWhere((ph) => !ph.taper, orElse: () => layout.last).to;
    final lib = _Library(p);

    final weeks = <TrainingWeek>[];
    final peak = _PeakTracker();
    for (var w = 1; w <= total; w++) {
      var pi = 0;
      for (var i = 0; i < layout.length; i++) {
        if (layout[i].from <= w) pi = i;
      }
      final ctx = _Ctx(
        week: w,
        total: total,
        peakWeek: peakWeek,
        phaseIndex: pi,
        phase: layout[pi],
      );
      final days = switch (g.type) {
        GoalType.mountain => _mountainWeek(ctx, lib, p, g, peak),
        GoalType.running => _runningWeek(ctx, lib, p, g, peak),
        GoalType.muscle => _muscleWeek(ctx, lib),
        GoalType.strength => _strengthWeek(ctx, lib, p, g),
        GoalType.fatLoss => _fatLossWeek(ctx, lib),
        GoalType.general => _generalWeek(ctx, lib),
      };
      var week = TrainingWeek(
        number: w,
        phase: ctx.phase.name,
        focus: ctx.phase.focus,
        days: days,
      );
      final deload = total >= 6 && w % 4 == 0 && w < peakWeek;
      if (deload) week = week.asDeload();
      weeks.add(week);
    }

    final injuryNote = p.injuries.isEmpty
        ? ''
        : ' Se adaptaron ejercicios por: "${p.injuries}". Detén cualquier ejercicio que cause dolor y consulta a un profesional.';

    final facts = [...g.facts];
    final targets = <GoalTarget>[];
    GoalTarget target(String id, double value, {bool higher = true}) {
      final b = Benchmarks.byId(id)!;
      return GoalTarget(
        benchmarkId: id,
        label: b.label,
        unit: b.unit,
        target: value,
        higherIsBetter: higher,
      );
    }

    switch (g.type) {
      case GoalType.mountain:
        facts.add('Tu caminata larga pasará de ${GoalAnalyzer.fmtHours(peak.hikeStart / 60)} '
            'a ${GoalAnalyzer.fmtHours(peak.hikeMax / 60)}, con mochila de '
            '${peak.packStart.round()} → ${peak.packMax.round()} kg.');
        targets
          ..add(target('hike_min', peak.hikeMax.toDouble()))
          ..add(target('pack_kg', peak.packMax))
          ..add(target('gain_m', (g.elevationGainM ?? 1000).toDouble()));
      case GoalType.running:
        facts.add('Tu tirada larga pasará de ${peak.longStart.toStringAsFixed(1)} '
            'a ${peak.longMax.toStringAsFixed(1)} km.');
        targets
          ..add(target('long_run_km', peak.longMax))
          ..add(target('week_km', peak.weekKmMax));
        if (g.raceMinutes != null && g.distanceKm != null) {
          final racePace = g.raceMinutes! * 60 / g.distanceKm!;
          targets.add(target('pace_1k', (racePace * 0.93).roundToDouble(), higher: false));
        }
      case GoalType.muscle:
      case GoalType.fatLoss:
        final change = g.weightChangeKg ?? 0;
        targets.add(target('body_kg', double.parse((p.weightKg + change).toStringAsFixed(1)),
            higher: change > 0));
      case GoalType.strength:
        if (g.liftBenchmark != null && g.liftTargetKg != null) {
          targets.add(target(g.liftBenchmark!, g.liftTargetKg!));
        }
      case GoalType.general:
        break;
    }

    final progression = switch (g.type) {
      GoalType.muscle =>
        'Doble progresión: cuando completes el tope de repeticiones en todas las series, sube 2.5–5 % la carga. Cada 4.ª semana es de descarga y en el bloque siguiente cambian los ejercicios.',
      GoalType.strength =>
        'Sube 2.5 kg en tren superior y 5 kg en inferior cada semana mientras la técnica sea limpia. Si fallas dos sesiones seguidas, baja 10 % y vuelve a subir.',
      GoalType.fatLoss =>
        'Mantén o sube las cargas (conservar músculo es la prioridad). El cardio y los intervalos crecen cada semana; revisa tu peso en el check-in: −0.5 a −1 % por semana.',
      GoalType.running =>
        'El volumen sube como máximo ~10 % por semana. Cada 4.ª semana se reduce para asimilar. Las últimas semanas bajan volumen (afinamiento) y la última termina con tu carrera.',
      GoalType.mountain =>
        'Cada semana la caminata larga y la mochila crecen un poco hasta simular la ruta. Las escaleras progresan en series y duración. La última semana es suave para llegar fresco al ascenso.',
      GoalType.general =>
        'Añade una repetición por serie cada semana; al llegar al tope, sube la carga o usa la variante más difícil del bloque siguiente.',
    };

    return TrainingPlan(
      title: switch (g.type) {
        GoalType.mountain => 'Preparación de montaña',
        GoalType.running => 'Plan de carrera',
        GoalType.fatLoss => 'Recomposición y pérdida de grasa',
        GoalType.muscle => 'Hipertrofia torso/pierna',
        GoalType.strength => 'Fuerza torso/pierna',
        GoalType.general => 'Condición general cuerpo completo',
      },
      summary:
          'Plan de $total semanas para "${p.goal.description}" (${p.equipment.label.toLowerCase()}). '
          'Fases: ${layout.map((ph) => ph.name).join(' → ')}.$injuryNote',
      weeks: weeks,
      progression: progression,
      goalHeadline: g.headline,
      goalFacts: facts.take(8).toList(),
      targets: targets,
      source: 'local',
      createdAt: created,
      startDate: mondayOf(created),
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

  static const _lowerMuscles = [
    MuscleGroup.quads,
    MuscleGroup.glutes,
    MuscleGroup.hamstrings,
    MuscleGroup.calves,
  ];

  static Exercise _cardio(
    String name, {
    int? minutes,
    int? seconds,
    double? km,
    int sets = 1,
    String reps = '',
    int restSec = 0,
    String notes = '',
    List<MuscleGroup> muscles = _lowerMuscles,
  }) =>
      Exercise(
        name: name,
        kind: ExerciseKind.cardio,
        sets: sets,
        reps: reps.isEmpty ? 'continuo' : reps,
        restSec: restSec,
        durationSec: seconds ?? (minutes == null ? null : minutes * 60),
        distanceKm: km,
        muscles: muscles,
        notes: notes,
      );

  // ------------------------------------------------------------- montaña

  static List<TrainingDay> _mountainWeek(
      _Ctx c, _Library l, UserProfile p, GoalSpec g, _PeakTracker peak) {
    final beginner = p.activity == ActivityLevel.sedentary ||
        p.activity == ActivityLevel.light;
    final peakHike = _r15(((g.ascentHours ?? 4) * 60 * 0.8).clamp(90, 300));
    final startHike = min(beginner ? 60 : 90, peakHike);
    final pack = g.packKg ?? 7;
    final startPack = min(beginner ? 2.0 : 3.0, pack);

    final hike = c.taper ? _r15(peakHike * 0.5) : _r15(c.ramp(startHike, peakHike));
    final packKg = c.taper ? max(2, (pack * 0.5).round()) : c.ramp(startPack, pack).round();
    final zone2 = c.taper ? 30 : _r5(c.ramp(30, 60));
    peak.hike(hike, packKg.toDouble(), first: c.week == 1);

    final v = c.block;
    final sets = c.taper ? 2 : 3;
    final reps = c.phaseIndex == 0 ? '10–12' : '8–10';

    final legs = c.phaseIndex == 0
        ? [
            l.move(_P.squat, v, sets, reps, 75),
            l.move(_P.hinge, v, sets, reps, 75),
            l.move(_P.stepUp, v, sets, '10–12 por pierna', 60),
            l.move(_P.calves, v, 3, '15–20', 45),
            l.move(_P.core, v, 3, '30–45 s', 45),
          ]
        : [
            l.move(_P.stepUp, v, sets, '10–12 por pierna', 60,
                notes: 'Con la mochila de la semana ($packKg kg) si te sientes bien.'),
            l.move(_P.eccentric, v, sets, '8–10 por pierna', 60,
                notes: 'Baja en 3 segundos: prepara las rodillas para el descenso.'),
            l.move(_P.lunge, v, sets, '10 por pierna', 60),
            l.move(_P.calves, v, 3, '15–20', 45),
            l.move(_P.core, v + 1, 3, '30–45 s', 45),
          ];

    final Exercise climbs;
    if (c.taper) {
      climbs = _cardio('Subidas suaves de escaleras o cuesta',
          sets: 4, seconds: 90, restSec: 90, reps: '90 s',
          notes: 'Ritmo cómodo: solo mantener las piernas activas.');
    } else if (c.phaseIndex == 0) {
      climbs = _cardio('Caminata continua en cuesta o caminadora inclinada',
          minutes: _r5(c.ramp(25, 40)),
          notes: 'Ritmo en el que puedas hablar en frases cortas.');
    } else if (c.phaseIndex == 1) {
      climbs = _cardio('Subidas de escaleras o cuesta (baja caminando)',
          sets: min(10, 5 + c.weekInPhase), seconds: 90, restSec: 90, reps: '90 s subida',
          muscles: const [MuscleGroup.quads, MuscleGroup.glutes, MuscleGroup.calves]);
    } else {
      climbs = _cardio('Subidas con mochila de $packKg kg',
          sets: min(12, 7 + c.weekInPhase), seconds: 180, restSec: 120, reps: '3 min subida',
          muscles: const [MuscleGroup.quads, MuscleGroup.glutes, MuscleGroup.calves],
          notes: 'Paso corto y constante, como en el volcán.');
    }

    final finalDay = c.isLast && c.total >= 3;
    return [
      TrainingDay(
        weekday: 1,
        title: 'Piernas de montaña',
        focus: c.phaseIndex == 0 ? 'Fuerza básica de piernas' : 'Fuerza excéntrica para las bajadas',
        exercises: legs,
      ),
      TrainingDay(
        weekday: 2,
        title: 'Cardio zona 2',
        focus: 'Base aeróbica',
        requiresStepGoal: true,
        exercises: [
          _cardio('Caminata rápida en subida, bici o elíptica', minutes: zone2,
              notes: 'Debes poder hablar en frases completas.'),
        ],
      ),
      TrainingDay(
        weekday: 3,
        title: 'Torso y core',
        focus: 'Espalda fuerte para cargar la mochila',
        exercises: [
          l.move(_P.pullH, v, sets, reps, 60),
          l.move(_P.pushH, v, sets, reps, 60),
          l.move(_P.pullV, v, sets, reps, 60),
          l.move(_P.carry, v, 3, '40 m', 60),
          l.move(_P.core, v + 2, 3, '30–45 s', 45),
        ],
      ),
      TrainingDay(
        weekday: 4,
        title: c.phaseIndex == 0 ? 'Cuesta continua' : 'Escaleras / cuestas',
        focus: 'Potencia aeróbica en subida',
        requiresStepGoal: true,
        exercises: [
          _cardio('Calentamiento', minutes: 10),
          climbs,
        ],
      ),
      _rest(5),
      if (finalDay)
        TrainingDay(
          weekday: 6,
          title: 'Día del ascenso 🏔️',
          focus: g.headline,
          requiresStepGoal: true,
          exercises: [
            _cardio('Ascenso objetivo', minutes: ((g.ascentHours ?? 4) * 60).round(),
                notes: 'Sal temprano, hidrátate cada 30 min, come algo cada hora y baja con calma.'),
          ],
        )
      else
        TrainingDay(
          weekday: 6,
          title: 'Caminata larga con mochila',
          focus: 'Simula la ruta: $packKg kg y el mismo calzado del día de la meta',
          requiresStepGoal: true,
          exercises: [
            _cardio('Caminata con desnivel y mochila de $packKg kg', minutes: hike,
                notes: 'Busca subidas reales. Bebe agua cada 20–30 min.'),
          ],
        ),
      _rest(7, title: 'Descanso'),
    ];
  }

  // ------------------------------------------------------------- carrera

  static List<TrainingDay> _runningWeek(
      _Ctx c, _Library l, UserProfile p, GoalSpec g, _PeakTracker peak) {
    final d = g.distanceKm ?? 10;
    final beginner = p.activity == ActivityLevel.sedentary ||
        p.activity == ActivityLevel.light;
    final peakLong = d <= 5
        ? 7.0
        : d <= 10
            ? 12.0
            : d <= 21.1
                ? max(14.0, d * 0.85)
                : min(32.0, d * 0.75);
    final startLong = beginner ? 3.0 : min(6.0, peakLong * 0.5);
    final long = c.taper ? _rHalf(peakLong * 0.6) : _rHalf(c.ramp(startLong, peakLong));
    final easyPeak = d <= 5 ? 5.0 : (d <= 10 ? 7.0 : 9.0);
    final easy = c.taper ? _rHalf(easyPeak * 0.6) : _rHalf(c.ramp(beginner ? 2.5 : 4, easyPeak));
    final v = c.block;

    final Exercise quality;
    if (c.taper) {
      quality = _cardio('Repeticiones a ritmo de carrera', sets: 4, km: 0.4, restSec: 90,
          reps: '400 m', notes: 'Rápido pero cómodo: mantener la chispa.');
    } else if (c.phaseIndex == 0) {
      quality = beginner
          ? _cardio('Correr / caminar', sets: min(10, 5 + c.weekInPhase), seconds: 60,
              restSec: 120, reps: '1 min trote · 2 min caminar')
          : _cardio('Fartlek', sets: min(10, 5 + c.weekInPhase), seconds: 60, restSec: 60,
              reps: '1 min rápido · 1 min suave');
    } else if (c.phaseIndex == 1) {
      quality = _cardio(d >= 21 ? 'Series de 800 m' : 'Series de 400 m',
          sets: min(10, 5 + c.weekInPhase), km: d >= 21 ? 0.8 : 0.4,
          restSec: 90, reps: d >= 21 ? '800 m' : '400 m',
          notes: 'Ritmo de 5k: duro pero controlado.');
    } else {
      quality = d >= 21
          ? _cardio('Tramo a ritmo de carrera', km: _rHalf(c.ramp(4, d * 0.4)),
              notes: 'Practica el ritmo, la hidratación y los geles de la carrera.')
          : _cardio('Tempo', minutes: _r5(c.ramp(15, 30)),
              notes: 'Ritmo "cómodamente duro": hablas solo palabras sueltas.');
    }

    final days = <TrainingDay>[
      TrainingDay(
        weekday: 1,
        title: 'Rodaje suave',
        requiresStepGoal: true,
        exercises: [_cardio('Trote suave', km: easy, notes: 'Ritmo conversacional.')],
      ),
      TrainingDay(
        weekday: 2,
        title: 'Fuerza para corredores',
        focus: 'Prevención de lesiones y economía de carrera',
        exercises: [
          l.move(_P.squat, v, c.taper ? 2 : 3, '8–10', 75),
          l.move(_P.hinge, v, c.taper ? 2 : 3, '8–10', 75),
          l.move(_P.stepUp, v, 3, '10 por pierna', 60),
          l.move(_P.calves, v, 3, '15–20', 45),
          l.move(_P.core, v, 3, '30–45 s', 45),
        ],
      ),
      TrainingDay(
        weekday: 3,
        title: c.phaseIndex == 0 ? 'Calidad suave' : 'Calidad',
        focus: c.phase.focus,
        exercises: [
          _cardio('Calentamiento', minutes: 10),
          quality,
          _cardio('Vuelta a la calma', minutes: 5),
        ],
      ),
      _rest(4),
      if (beginner)
        _rest(5, title: 'Movilidad')
      else
        TrainingDay(
          weekday: 5,
          title: 'Rodaje + técnica',
          requiresStepGoal: true,
          exercises: [
            _cardio('Trote suave', km: _rHalf(easy * 0.8)),
            _cardio('Progresivos', sets: 6, seconds: 20, restSec: 60, reps: '80 m',
                notes: 'Acelera suave hasta casi sprint y relaja.'),
          ],
        ),
      if (c.isLast && c.total >= 3)
        TrainingDay(
          weekday: 6,
          title: 'Día de la carrera 🏁',
          focus: g.headline,
          exercises: [
            _cardio('Carrera objetivo', km: d,
                notes: 'Calienta 10 min. Sal 5–10 s/km más lento los primeros 2 km.'),
          ],
        )
      else
        TrainingDay(
          weekday: 6,
          title: 'Tirada larga',
          requiresStepGoal: true,
          exercises: [_cardio('Carrera larga', km: long, notes: 'Ritmo suave y constante.')],
        ),
      _rest(7, title: 'Descanso'),
    ];

    var weekKm = 0.0;
    for (final day in days) {
      for (final e in day.exercises) {
        if (e.distanceKm != null) weekKm += e.distanceKm! * e.sets;
      }
    }
    peak.run(long, weekKm, first: c.week == 1, countsForPeak: !c.isLast);
    return days;
  }

  // ---------------------------------------------------------- hipertrofia

  static List<TrainingDay> _muscleWeek(_Ctx c, _Library l) {
    final accumulation = c.block.isEven;
    final reps = accumulation ? '10–12' : '6–8';
    final rest = accumulation ? 90 : 120;
    final main = min(5, 3 + c.weekInBlock - 1);
    final acc = 3;
    final v = c.block;
    final rir = accumulation ? 'Deja 2–3 repeticiones en reserva.' : 'Deja 1–2 repeticiones en reserva.';
    return [
      TrainingDay(weekday: 1, title: 'Pierna A', focus: 'Sentadilla y cadena posterior', exercises: [
        l.move(_P.squat, v, main, reps, rest, notes: rir),
        l.move(_P.hinge, v + 1, main, reps, rest),
        l.move(_P.lunge, v, acc, '10 por pierna', 75),
        l.move(_P.calves, v, acc, '12–15', 45),
        l.move(_P.core, v, acc, '30–45 s', 45),
      ]),
      TrainingDay(weekday: 2, title: 'Torso A', focus: 'Empujes y tirones horizontales', exercises: [
        l.move(_P.pushH, v, main, reps, rest, notes: rir),
        l.move(_P.pullH, v, main, reps, rest),
        l.move(_P.pushV, v, acc, '10–12', 75),
        l.move(_P.pullV, v, acc, '10–12', 75),
        l.move(_P.arms, v, acc, '12–15', 60),
      ]),
      _rest(3),
      TrainingDay(weekday: 4, title: 'Pierna B', focus: 'Bisagra de cadera y unilateral', exercises: [
        l.move(_P.hinge, v, main, reps, rest, notes: rir),
        l.move(_P.squat, v + 1, main, reps, rest),
        l.move(_P.stepUp, v, acc, '10 por pierna', 60),
        l.move(_P.calves, v + 1, acc, '12–15', 45),
        l.move(_P.core, v + 1, acc, '30–45 s', 45),
      ]),
      TrainingDay(weekday: 5, title: 'Torso B', focus: 'Empujes y tirones verticales', exercises: [
        l.move(_P.pushV, v + 1, main, reps, rest, notes: rir),
        l.move(_P.pullV, v + 1, main, reps, rest),
        l.move(_P.pushH, v + 1, acc, '10–12', 75),
        l.move(_P.pullH, v + 1, acc, '10–12', 75),
        l.move(_P.arms, v + 1, acc, '12–15', 60),
      ]),
      TrainingDay(
        weekday: 6,
        title: 'Cardio zona 2',
        focus: 'Salud cardiovascular y recuperación',
        requiresStepGoal: true,
        exercises: [_cardio('Caminata rápida o bici', minutes: 30)],
      ),
      _rest(7, title: 'Descanso'),
    ];
  }

  // -------------------------------------------------------------- fuerza

  static List<TrainingDay> _strengthWeek(_Ctx c, _Library l, UserProfile p, GoalSpec g) {
    final (sets, reps, rest) = switch (c.phaseIndex) {
      0 => (4, '6–8', 150),
      1 => (5, '3–5', 180),
      _ => (5, '2–3', 210),
    };
    final mainSets = c.weekInPhase == 1 ? sets - 1 : sets;
    final v = c.block;
    final testWeek = c.isLast && c.total >= 6;
    final gym = p.equipment == Equipment.gym;

    if (testWeek) {
      final testReps = gym ? '1RM (con ayudante)' : 'máximo de repeticiones';
      const note = 'Calienta bien y sube en 4–5 intentos progresivos.';
      return [
        TrainingDay(weekday: 1, title: 'Prueba: pierna', focus: g.headline, exercises: [
          l.move(_P.squat, 0, 1, testReps, 240, notes: note),
          l.move(_P.hinge, 0, 1, testReps, 240, notes: note),
        ]),
        _rest(2),
        TrainingDay(weekday: 3, title: 'Prueba: torso', focus: g.headline, exercises: [
          l.move(_P.pushH, 0, 1, testReps, 240, notes: note),
          l.move(_P.pullH, 0, 1, testReps, 240, notes: note),
        ]),
        _rest(4),
        _rest(5),
        _rest(6, title: 'Celebración activa'),
        _rest(7, title: 'Descanso'),
      ];
    }

    return [
      TrainingDay(weekday: 1, title: 'Pierna pesada', focus: c.phase.focus, exercises: [
        l.move(_P.squat, 0, mainSets, reps, rest),
        l.move(_P.hinge, v + 1, 3, '6–8', 120),
        l.move(_P.lunge, v, 3, '8 por pierna', 90),
        l.move(_P.core, v, 3, '30–45 s', 45),
      ]),
      TrainingDay(weekday: 2, title: 'Torso pesado', focus: c.phase.focus, exercises: [
        l.move(_P.pushH, 0, mainSets, reps, rest),
        l.move(_P.pullH, 0, mainSets, reps, rest),
        l.move(_P.pushV, v, 3, '6–8', 120),
        l.move(_P.arms, v, 2, '10–12', 60),
      ]),
      _rest(3),
      TrainingDay(weekday: 4, title: 'Pierna: bisagra', focus: c.phase.focus, exercises: [
        l.move(_P.hinge, 0, mainSets, reps, rest),
        l.move(_P.squat, v + 1, 3, '6–8', 120),
        l.move(_P.calves, v, 3, '10–12', 60),
        l.move(_P.carry, v, 3, '30 m', 90),
      ]),
      TrainingDay(weekday: 5, title: 'Torso: vertical', focus: c.phase.focus, exercises: [
        l.move(_P.pushV, 0, mainSets, reps, rest),
        l.move(_P.pullV, 0, mainSets, reps, rest),
        l.move(_P.pushH, v + 1, 3, '6–8', 120),
        l.move(_P.core, v + 1, 3, '30–45 s', 45),
      ]),
      TrainingDay(
        weekday: 6,
        title: 'Cardio suave',
        requiresStepGoal: true,
        exercises: [_cardio('Caminata o bici', minutes: 30)],
      ),
      _rest(7, title: 'Descanso'),
    ];
  }

  // ------------------------------------------------------- pérdida de grasa

  static List<TrainingDay> _fatLossWeek(_Ctx c, _Library l) {
    final v = c.block;
    final rounds = min(10, 6 + (c.week - 1) ~/ 2);
    final work = c.week <= 4 ? 30 : 40;
    final zone2 = _r5(c.ramp(30, 45));
    final walk = _r5(c.ramp(45, 75));
    final sets = c.phaseIndex == 0 ? 3 : 4;
    return [
      TrainingDay(weekday: 1, title: 'Fuerza A', focus: c.phase.focus, exercises: [
        l.move(_P.squat, v, sets, '10–15', 60),
        l.move(_P.pushH, v, sets, '10–15', 60),
        l.move(_P.pullH, v, sets, '10–15', 60),
        l.move(_P.core, v, 3, '30–45 s', 45),
      ]),
      TrainingDay(
        weekday: 2,
        title: 'HIIT',
        focus: 'Úsalo con el modo Objetivo del timer',
        requiresStepGoal: true,
        exercises: [
          _cardio('Intervalos (burpees, jumping jacks, escaladores, sentadilla con salto)',
              sets: rounds, seconds: work, restSec: 60 - work,
              reps: '$work s trabajo / ${60 - work} s descanso',
              muscles: const [MuscleGroup.quads, MuscleGroup.glutes, MuscleGroup.shoulders, MuscleGroup.abs]),
        ],
      ),
      TrainingDay(weekday: 3, title: 'Fuerza B', focus: c.phase.focus, exercises: [
        l.move(_P.hinge, v, sets, '10–15', 60),
        l.move(_P.pushV, v, sets, '10–15', 60),
        l.move(_P.pullV, v, sets, '10–15', 60),
        l.move(_P.lunge, v, 3, '10 por pierna', 60),
      ]),
      TrainingDay(
        weekday: 4,
        title: 'Cardio zona 2',
        requiresStepGoal: true,
        exercises: [_cardio('Caminata inclinada, trote suave o bici', minutes: zone2)],
      ),
      TrainingDay(weekday: 5, title: 'Fuerza C', focus: c.phase.focus, exercises: [
        l.move(_P.squat, v + 1, sets, '10–15', 60),
        l.move(_P.pushH, v + 1, sets, '10–15', 60),
        l.move(_P.pullV, v + 1, sets, '10–15', 60),
        l.move(_P.calves, v, 3, '15–20', 45),
        l.move(_P.core, v + 1, 3, '30–45 s', 45),
      ]),
      TrainingDay(
        weekday: 6,
        title: 'Caminata larga',
        requiresStepGoal: true,
        exercises: [_cardio('Caminata al aire libre', minutes: walk)],
      ),
      _rest(7, title: 'Descanso'),
    ];
  }

  // -------------------------------------------------------------- general

  static List<TrainingDay> _generalWeek(_Ctx c, _Library l) {
    final v = c.block;
    final sets = c.block == 0 ? 3 : 4;
    final reps = c.phaseIndex == 0 ? '10–12' : '8–12';
    return [
      TrainingDay(weekday: 1, title: 'Cuerpo completo A', focus: c.phase.focus, exercises: [
        l.move(_P.squat, v, sets, reps, 75),
        l.move(_P.pushH, v, sets, reps, 75),
        l.move(_P.pullH, v, sets, reps, 75),
        l.move(_P.core, v, 3, '30–45 s', 45),
      ]),
      _rest(2),
      TrainingDay(weekday: 3, title: 'Cuerpo completo B', focus: c.phase.focus, exercises: [
        l.move(_P.hinge, v, sets, reps, 75),
        l.move(_P.pushV, v, sets, reps, 75),
        l.move(_P.pullV, v, sets, reps, 75),
        l.move(_P.calves, v, 3, '12–15', 45),
      ]),
      TrainingDay(
        weekday: 4,
        title: 'Cardio zona 2',
        requiresStepGoal: true,
        exercises: [_cardio('Caminata rápida, trote suave o bici', minutes: _r5(c.ramp(25, 40)))],
      ),
      TrainingDay(weekday: 5, title: 'Cuerpo completo C', focus: c.phase.focus, exercises: [
        l.move(_P.lunge, v, sets, '10 por pierna', 75),
        l.move(_P.pushH, v + 1, sets, reps, 75),
        l.move(_P.pullH, v + 1, sets, reps, 75),
        l.move(_P.core, v + 1, 3, '30–45 s', 45),
      ]),
      TrainingDay(
        weekday: 6,
        title: 'Caminata larga',
        requiresStepGoal: true,
        exercises: [_cardio('Caminata', minutes: _r5(c.ramp(40, 60)))],
      ),
      _rest(7, title: 'Descanso'),
    ];
  }

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

  static NutritionPlan _nutrition(UserProfile p, GoalSpec spec) {
    final t = targets(p, spec);
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


/// Registra los valores inicial y máximo de las variables clave del plan
/// para describir la progresión y fijar las metas del check-in.
class _PeakTracker {
  int hikeStart = 0;
  int hikeMax = 0;
  double packStart = 0;
  double packMax = 0;
  double longStart = 0;
  double longMax = 0;
  double weekKmMax = 0;

  void hike(int minutes, double packKg, {required bool first}) {
    if (first) {
      hikeStart = minutes;
      packStart = packKg;
    }
    hikeMax = max(hikeMax, minutes);
    packMax = max(packMax, packKg);
  }

  void run(double longKm, double weekKm,
      {required bool first, required bool countsForPeak}) {
    if (first) longStart = longKm;
    if (!countsForPeak) return;
    longMax = max(longMax, longKm);
    weekKmMax = max(weekKmMax, double.parse(weekKm.toStringAsFixed(1)));
  }
}

/// Patrones de movimiento.
enum _P {
  squat,
  hinge,
  pushH,
  pushV,
  pullH,
  pullV,
  lunge,
  stepUp,
  eccentric,
  calves,
  core,
  arms,
  carry,
}

typedef _Opt = (String name, List<MuscleGroup> muscles, String? reps);

/// Biblioteca de ejercicios: elige la variante de cada patrón según el
/// equipo, las lesiones y el bloque (las variantes rotan cada 4 semanas para
/// que la rutina no sea siempre igual).
class _Library {
  _Library(this.p)
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

  static const _legs = [MuscleGroup.quads, MuscleGroup.glutes];
  static const _post = [MuscleGroup.hamstrings, MuscleGroup.glutes, MuscleGroup.lowerBack];
  static const _glutes = [MuscleGroup.glutes, MuscleGroup.hamstrings];
  static const _pushH = [MuscleGroup.chest, MuscleGroup.triceps, MuscleGroup.shoulders];
  static const _pushV = [MuscleGroup.shoulders, MuscleGroup.triceps];
  static const _pullH = [MuscleGroup.lats, MuscleGroup.traps, MuscleGroup.biceps];
  static const _pullV = [MuscleGroup.lats, MuscleGroup.biceps, MuscleGroup.forearms];
  static const _lunge = [MuscleGroup.quads, MuscleGroup.glutes, MuscleGroup.hamstrings];
  static const _step = [MuscleGroup.quads, MuscleGroup.glutes, MuscleGroup.calves];
  static const _core = [MuscleGroup.abs, MuscleGroup.obliques];
  static const _arms = [MuscleGroup.biceps, MuscleGroup.triceps, MuscleGroup.forearms];
  static const _carry = [MuscleGroup.forearms, MuscleGroup.traps, MuscleGroup.abs];

  List<_Opt> _options(_P pattern) {
    final eq = p.equipment;
    switch (pattern) {
      case _P.squat:
        if (_knee || _back) {
          return const [
            ('Sentadilla a cajón (rango cómodo)', _legs, null),
            ('Sentadilla isométrica en pared', _legs, '30–45 s'),
          ];
        }
        return switch (eq) {
          Equipment.gym => const [
              ('Sentadilla con barra', _legs, null),
              ('Sentadilla frontal', _legs, null),
              ('Prensa de piernas', _legs, null),
              ('Sentadilla goblet con pausa', _legs, null),
            ],
          Equipment.calisthenics => const [
              ('Sentadilla búlgara en banca', _legs, '8–12 por pierna'),
              ('Pistol asistida a banca', _legs, '6–10 por pierna'),
              ('Sentadilla cosaca', _legs, '8 por lado'),
            ],
          Equipment.home => const [
              ('Sentadilla con pausa de 2 s', _legs, null),
              ('Sentadilla búlgara en silla', _legs, '8–12 por pierna'),
              ('Sentadilla 1½ (media repetición extra)', _legs, null),
              ('Sentadilla con mochila', _legs, null),
            ],
        };
      case _P.hinge:
        if (_back) {
          return const [
            ('Puente de glúteo', _glutes, null),
            ('Bird dog (cuadrupedia alterna)', [MuscleGroup.lowerBack, MuscleGroup.abs, MuscleGroup.glutes], '8 por lado'),
          ];
        }
        return switch (eq) {
          Equipment.gym => const [
              ('Peso muerto rumano', _post, null),
              ('Hip thrust con barra', _glutes, null),
              ('Peso muerto convencional (técnico)', _post, null),
              ('Curl femoral + buenos días', _post, null),
            ],
          Equipment.calisthenics => const [
              ('Puente de glúteo a una pierna', _glutes, '10–15 por pierna'),
              ('Curl nórdico asistido', _post, '5–8'),
              ('Hip thrust a una pierna en banca', _glutes, '10–12 por pierna'),
            ],
          Equipment.home => const [
              ('Peso muerto rumano con mochila', _post, null),
              ('Puente de glúteo a una pierna', _glutes, '10–15 por pierna'),
              ('Peso muerto a una pierna (equilibrio)', _post, '8–10 por pierna'),
            ],
        };
      case _P.pushH:
        return switch (eq) {
          Equipment.gym => const [
              ('Press de banca', _pushH, null),
              ('Press inclinado con mancuernas', _pushH, null),
              ('Press de banca con mancuernas', _pushH, null),
              ('Fondos en paralelas', _pushH, null),
            ],
          Equipment.calisthenics => const [
              ('Fondos en paralelas', _pushH, null),
              ('Flexiones con pies elevados', _pushH, null),
              ('Flexiones arqueras', _pushH, '6–10 por lado'),
            ],
          Equipment.home => const [
              ('Flexiones', _pushH, null),
              ('Flexiones con pies elevados', _pushH, null),
              ('Flexiones con pausa abajo', _pushH, null),
              ('Flexiones diamante', _pushH, null),
            ],
        };
      case _P.pushV:
        if (_shoulder) {
          return const [
            ('Y-T-W boca abajo (sin peso)', [MuscleGroup.shoulders, MuscleGroup.traps], '8 de cada letra'),
            ('Elevaciones laterales ligeras', [MuscleGroup.shoulders], '12–15'),
          ];
        }
        return switch (eq) {
          Equipment.gym => const [
              ('Press militar con mancuernas', _pushV, null),
              ('Press militar con barra', _pushV, null),
              ('Press Arnold', _pushV, null),
            ],
          Equipment.calisthenics || Equipment.home => const [
              ('Flexiones pike', _pushV, null),
              ('Flexiones pike con pies elevados', _pushV, null),
              ('Pino asistido en pared (sostener)', _pushV, '20–40 s'),
            ],
        };
      case _P.pullH:
        return switch (eq) {
          Equipment.gym => const [
              ('Remo con barra', _pullH, null),
              ('Remo en polea baja', _pullH, null),
              ('Remo con mancuerna a una mano', _pullH, null),
            ],
          Equipment.calisthenics => const [
              ('Remo australiano en barra baja', _pullH, null),
              ('Remo australiano con pies elevados', _pullH, null),
            ],
          Equipment.home => const [
              ('Remo con mochila a una mano', _pullH, '10–15 por brazo'),
              ('Remo invertido bajo una mesa firme', _pullH, null),
            ],
        };
      case _P.pullV:
        return switch (eq) {
          Equipment.gym => const [
              ('Jalón al pecho', _pullV, null),
              ('Dominadas asistidas', _pullV, null),
              ('Jalón agarre neutro', _pullV, null),
            ],
          Equipment.calisthenics => const [
              ('Dominadas (o negativas lentas)', _pullV, 'máx. técnico'),
              ('Dominadas agarre supino', _pullV, 'máx. técnico'),
              ('Dominadas con pausa arriba', _pullV, 'máx. técnico'),
            ],
          Equipment.home => const [
              ('Remo invertido bajo una mesa firme', _pullV, null),
              ('Remo con mochila a dos manos', _pullV, null),
              ('Superman con jalón de toalla', _pullV, '12–15'),
            ],
        };
      case _P.lunge:
        if (_knee) {
          return const [
            ('Puente de glúteo con pausa', _glutes, null),
            ('Elevación de cadera en banca o silla', _glutes, null),
          ];
        }
        return switch (eq) {
          Equipment.gym => const [
              ('Zancadas con mancuernas', _lunge, '10 por pierna'),
              ('Zancada búlgara con mancuernas', _lunge, '8–10 por pierna'),
              ('Zancada caminando', _lunge, '10 por pierna'),
            ],
          Equipment.calisthenics || Equipment.home => const [
              ('Zancadas hacia atrás', _lunge, '10–12 por pierna'),
              ('Zancada caminando', _lunge, '10 por pierna'),
              ('Zancada lateral', _lunge, '8–10 por lado'),
            ],
        };
      case _P.stepUp:
        final low = _knee ? ' (escalón bajo)' : '';
        return switch (eq) {
          Equipment.gym => [
              ('Step-up con mancuernas$low', _step, null),
              ('Step-up alto con mancuernas$low', _step, null),
            ],
          Equipment.calisthenics => [
              ('Subidas a banca del parque$low', _step, null),
              ('Subidas laterales a banca$low', _step, null),
            ],
          Equipment.home => [
              ('Subidas a escalón o silla firme$low', _step, null),
              ('Subidas a escalón con mochila$low', _step, null),
            ],
        };
      case _P.eccentric:
        return [
          ('Bajadas excéntricas de escalón (3 s)${_knee ? ' — escalón bajo' : ''}', _step, null),
          ('Sentadilla excéntrica lenta (4 s abajo)', _legs, null),
          ('Zancada hacia atrás con bajada lenta', _lunge, null),
        ];
      case _P.calves:
        return [
          if (eq == Equipment.gym) ('Elevación de talones en máquina', const [MuscleGroup.calves], null),
          ('Elevación de talones a una pierna en escalón', const [MuscleGroup.calves], null),
          ('Elevación de talones con pausa arriba', const [MuscleGroup.calves], null),
        ];
      case _P.core:
        return eq == Equipment.calisthenics
            ? const [
                ('Elevación de rodillas colgado', _core, '10–15'),
                ('Elevación de piernas colgado', _core, '8–12'),
                ('L-sit en paralelas', _core, '15–30 s'),
              ]
            : const [
                ('Plancha frontal + lateral', _core, null),
                ('Dead bug', _core, '8–10 por lado'),
                ('Roll-out con toalla o rueda', _core, '8–12'),
                ('Plancha con toque de hombro', _core, '10 por lado'),
              ];
      case _P.arms:
        return eq == Equipment.gym
            ? const [
                ('Curl con barra + extensión de tríceps en polea', _arms, null),
                ('Curl martillo + press francés', _arms, null),
              ]
            : const [
                ('Flexiones diamante + curl con mochila', _arms, null),
                ('Fondos en silla + curl con toalla', _arms, null),
              ];
      case _P.carry:
        return eq == Equipment.gym
            ? const [
                ('Paseo del granjero con mancuernas', _carry, null),
                ('Paseo con una mano (maleta)', _carry, null),
              ]
            : const [
                ('Paseo con mochila cargada', _carry, null),
                ('Paseo con mochila al frente', _carry, null),
              ];
    }
  }

  Exercise move(_P pattern, int variant, int sets, String reps, int restSec,
      {String notes = ''}) {
    final options = _options(pattern);
    final (name, muscles, fixedReps) = options[variant % options.length];
    final isTest = reps.contains('1RM') || reps.contains('máximo');
    return Exercise(
      name: name,
      kind: ExerciseKind.strength,
      sets: sets,
      reps: isTest ? reps : (fixedReps ?? reps),
      restSec: restSec,
      muscles: muscles,
      notes: notes.isEmpty && _knee && pattern == _P.squat
          ? 'Rango sin dolor; detente si la rodilla molesta.'
          : notes,
    );
  }
}
