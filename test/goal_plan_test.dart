import 'package:aurum_fit/features/checkin/benchmarks.dart';
import 'package:aurum_fit/features/checkin/checkin_logic.dart';
import 'package:aurum_fit/features/checkin/checkin_models.dart';
import 'package:aurum_fit/features/hydration/water_math.dart';
import 'package:aurum_fit/features/onboarding/user_profile.dart';
import 'package:aurum_fit/features/plan/goal_analyzer.dart';
import 'package:aurum_fit/features/plan/local_plan_generator.dart';
import 'package:aurum_fit/features/plan/plan_models.dart';
import 'package:aurum_fit/features/progress/muscle_group.dart';
import 'package:aurum_fit/features/progress/progress_engine.dart';
import 'package:aurum_fit/features/timer/circuits.dart';
import 'package:aurum_fit/features/timer/interval_engine.dart';
import 'package:flutter_test/flutter_test.dart';

UserProfile _p(
  GoalType type,
  String text, {
  int weeks = 12,
  Equipment eq = Equipment.gym,
  ActivityLevel activity = ActivityLevel.light,
}) =>
    UserProfile(
      sex: Sex.male,
      age: 22,
      weightKg: 70,
      heightCm: 175,
      activity: activity,
      equipment: eq,
      goal: Goal(
        type: type,
        description: text,
        deadline: DateTime.now().add(Duration(days: weeks * 7)),
      ),
    );

Exercise _saturdayMain(TrainingPlan plan, int week) =>
    plan.week(week).dayFor(DateTime.saturday)!.exercises.first;

void main() {
  group('GoalAnalyzer', () {
    test('reconoce volcanes de Guatemala', () {
      final g = GoalAnalyzer.analyze(
          _p(GoalType.mountain, 'Subir el Volcán Acatenango en 3 meses'));
      expect(g.type, GoalType.mountain);
      expect(g.headline, contains('Acatenango'));
      expect(g.elevationGainM, 1500);
      expect(g.packKg, 10);
    });

    test('corrige la categoría si el texto es claro', () {
      final run = GoalAnalyzer.analyze(_p(GoalType.general, 'Correr 10k en 8 semanas'));
      expect(run.type, GoalType.running);
      expect(run.distanceKm, 10);
      final hike = GoalAnalyzer.analyze(_p(GoalType.general, 'subir el Tajumulco'));
      expect(hike.type, GoalType.mountain);
      expect(hike.headline, contains('Tajumulco'));
    });

    test('distancias y kilos', () {
      expect(GoalAnalyzer.analyze(_p(GoalType.running, 'Terminar una media maratón')).distanceKm, 21.1);
      expect(GoalAnalyzer.analyze(_p(GoalType.fatLoss, 'Quiero bajar 8 kg')).weightChangeKg, -8);
      expect(GoalAnalyzer.analyze(_p(GoalType.muscle, 'ganar 4 kilos de músculo')).weightChangeKg, 4);
      final s = GoalAnalyzer.analyze(_p(GoalType.strength, 'press de banca de 100 kg'));
      expect(s.liftBenchmark, 'bench_1rm');
      expect(s.liftTargetKg, 100);
    });
  });

  group('Plan periodizado', () {
    final plan = LocalPlanGenerator.generate(
            _p(GoalType.mountain, 'Subir el Volcán Acatenango en 3 meses'))
        .training;

    test('las semanas cambian: la caminata y la mochila crecen', () {
      expect(plan.totalWeeks, 12);
      final first = _saturdayMain(plan, 1);
      final peak = _saturdayMain(plan, 11);
      expect(first.durationSec, 60 * 60);
      expect(peak.durationSec, greaterThan(4 * 3600));
      expect(first.name, isNot(peak.name)); // la mochila cambia de kg
      expect(plan.phases.length, 4);
    });

    test('descarga cada 4.ª semana y el ascenso al final', () {
      expect(plan.week(4).deload, isTrue);
      expect(plan.week(8).deload, isTrue);
      expect(plan.week(5).deload, isFalse);
      expect(plan.week(12).dayFor(DateTime.saturday)!.title, contains('ascenso'));
    });

    test('metas medibles para el check-in', () {
      final ids = plan.targets.map((t) => t.benchmarkId).toList();
      expect(ids, containsAll(['hike_min', 'pack_kg', 'gain_m']));
      expect(plan.goalFacts.first, contains('1,500'));
    });

    test('objetivos distintos generan rutinas distintas', () {
      final muscle = LocalPlanGenerator.generate(_p(GoalType.muscle, 'ganar músculo')).training;
      final run = LocalPlanGenerator.generate(_p(GoalType.running, 'correr 10k')).training;
      String week1(TrainingPlan p) =>
          p.week(1).days.map((d) => d.title).join('|');
      expect(week1(muscle), isNot(week1(plan)));
      expect(week1(run), isNot(week1(plan)));
      expect(run.week(run.totalWeeks).dayFor(DateTime.saturday)!.title, contains('carrera'));
    });

    test('los ejercicios rotan entre bloques', () {
      final muscle = LocalPlanGenerator.generate(_p(GoalType.muscle, 'hipertrofia')).training;
      final b1 = muscle.week(1).dayFor(DateTime.monday)!.exercises.first.name;
      final b2 = muscle.week(5).dayFor(DateTime.monday)!.exercises.first.name;
      expect(b1, isNot(b2));
    });

    test('las fases de la IA se expanden a semanas', () {
      final parsed = TrainingPlan.tryParse({
        'title': 'IA',
        'weeks': 8,
        'phases': [
          {
            'name': 'Base',
            'weekFrom': 1,
            'weekTo': 4,
            'days': [
              {
                'weekday': 6,
                'title': 'Larga',
                'exercises': [
                  {'name': 'Caminata', 'kind': 'cardio', 'durationSec': 3600},
                ],
              },
            ],
          },
          {
            'name': 'Específica',
            'weekFrom': 5,
            'weekTo': 8,
            'days': [
              {
                'weekday': 6,
                'title': 'Larga',
                'exercises': [
                  {'name': 'Caminata', 'kind': 'cardio', 'durationSec': 7200},
                ],
              },
            ],
          },
        ],
      }, source: 'ai')!;
      expect(parsed.totalWeeks, 8);
      expect(parsed.week(4).deload, isTrue);
      expect(_saturdayMain(parsed, 3).durationSec, greaterThan(3600));
      expect(parsed.week(6).phase, 'Específica');
    });
  });

  group('Check-in semanal', () {
    final plan = LocalPlanGenerator.generate(
            _p(GoalType.mountain, 'Subir el Volcán Acatenango en 3 meses'))
        .training;
    final now = DateTime.now();

    WeeklyCheckin c(int week, Map<String, double> values,
            {bool pain = false, int energy = 4}) =>
        WeeklyCheckin(
          id: 'c$week',
          week: week,
          date: now,
          values: values,
          pain: pain,
          energy: energy,
        );

    test('sin check-ins pide la evaluación inicial', () {
      expect(CheckinLogic.pendingWeek(plan, const [], now), 0);
    });

    test('preparación para la meta', () {
      final hikeTarget =
          plan.targets.firstWhere((t) => t.benchmarkId == 'hike_min').target;
      final list = [
        c(0, {'hike_min': 60}),
        c(1, {'hike_min': hikeTarget / 2}),
      ];
      final progress = CheckinLogic.targetProgress(plan, list);
      final hike = progress.firstWhere((t) => t.target.benchmarkId == 'hike_min');
      expect(hike.fraction, closeTo(0.5, 0.01));
      expect(CheckinLogic.readiness(progress), isNotNull);
    });

    test('dolor → la semana siguiente es de descarga', () {
      final list = [c(0, const {}), c(2, const {}, pain: true)];
      expect(plan.week(3).deload, isFalse);
      expect(CheckinLogic.effectiveWeek(plan, 3, list).deload, isTrue);
    });

    test('récords y puntaje del mapa', () {
      final list = [
        c(0, {'squat_1rm': 80}),
        c(1, {'squat_1rm': 88}),
      ];
      final records = CheckinLogic.records(list);
      expect(records.single.improvement, closeTo(0.1, 0.001));
      final scores = CheckinLogic.benchmarkScores(list);
      expect(scores['squat_1rm'], closeTo(0.5, 0.001));
      final map = ProgressEngine.compute(const [],
          bodyweightKg: 70, benchmarkScores: scores);
      expect(map[MuscleGroup.quads]!.benchmarkProgress, closeTo(0.5, 0.001));
      expect(map[MuscleGroup.quads]!.score, greaterThan(0));
      expect(map[MuscleGroup.chest]!.score, 0);
    });

    test('1RM estimado (Epley)', () {
      expect(Benchmark.epley(100, 5), closeTo(116.67, 0.01));
      expect(Benchmark.epley(100, 1), 100);
    });

    test('pruebas según objetivo y equipo', () {
      final ids = Benchmarks.forProfile(
              _p(GoalType.muscle, 'x', eq: Equipment.calisthenics), GoalType.muscle)
          .map((b) => b.id);
      expect(ids, containsAll(['pullups', 'dips', 'pushups']));
    });
  });

  group('Timer', () {
    test('todos los circuitos libres generan un programa válido', () {
      for (final c in CircuitLibrary.all) {
        final p = c.toProgram();
        expect(p.phases.first.kind, PhaseKind.prepare, reason: c.id);
        expect(p.phases.where((x) => x.kind == PhaseKind.work).length,
            c.steps.length * c.rounds,
            reason: c.id);
        expect(c.toTrainingDay().exercises.length, c.steps.length);
        expect(c.estimatedMinutes, greaterThan(0));
      }
    });

    test('circuitos del objetivo escalan con la semana', () {
      final profile = _p(GoalType.mountain, 'Subir el Volcán Acatenango');
      final plan = LocalPlanGenerator.generate(profile).training;
      Circuit stairs(int w) => GoalCircuits.forPlan(profile, plan, plan.week(w))
          .firstWhere((c) => c.id == 'goal_stairs');
      expect(stairs(10).rounds, greaterThan(stairs(1).rounds));
      expect(stairs(10).steps.first.seconds!, greaterThan(stairs(1).steps.first.seconds!));
    });
  });

  test('meta de agua explicada', () {
    final profile = _p(GoalType.general, 'salud');
    final rest = WaterMath.goalFor(profile, null);
    expect(rest.ml, 2500);
    const training = TrainingDay(weekday: 1, title: 'Fuerza', exercises: [
      Exercise(name: 'Sentadilla', kind: ExerciseKind.strength),
    ]);
    expect(WaterMath.goalFor(profile, training).ml, 3000);
    expect(WaterMath.expectedByNow(2800, DateTime(2026, 1, 1, 14)), 1500);
  });
}
