import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../checkin/achievements_tab.dart';
import 'body_map.dart';
import 'muscle_group.dart';
import 'progress_engine.dart';
import 'workout_log.dart';

class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({super.key});

  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  BodySide _side = BodySide.front;
  MuscleGroup? _selected;

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(progressProvider);
    final sessions = ref.watch(workoutLogProvider);
    final overall = ProgressEngine.overall(progress);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Progreso'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Mapa del cuerpo'), Tab(text: 'Logros')],
          ),
        ),
        body: TabBarView(
          children: [
            _mapTab(progress, sessions.length, overall),
            const AchievementsTab(),
          ],
        ),
      ),
    );
  }

  Widget _mapTab(
      Map<MuscleGroup, MuscleProgress> progress, int sessionCount, double overall) {
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _OverallCard(score: overall, sessions: sessionCount),
          const SizedBox(height: 16),
          Center(
            child: SegmentedButton<BodySide>(
              segments: const [
                ButtonSegment(value: BodySide.front, label: Text('Frente')),
                ButtonSegment(value: BodySide.back, label: Text('Espalda')),
              ],
              selected: {_side},
              onSelectionChanged: (s) => setState(() => _side = s.first),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: BodyMap(
                side: _side,
                progress: progress,
                selected: _selected,
                onSelect: (m) => setState(() => _selected = m),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const _Legend(),
          const SizedBox(height: 16),
          if (_selected != null && progress[_selected] != null)
            _MuscleDetail(p: progress[_selected]!)
          else
            const Text(
              'Toca un músculo para ver su nivel.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AurumColors.textMuted),
            ),
          const SizedBox(height: 24),
          Text('Ranking muscular',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...(progress.values.toList()
                ..sort((a, b) => b.score.compareTo(a.score)))
              .map((p) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onTap: () => setState(() => _selected = p.muscle),
                    leading: CircleAvatar(
                      radius: 10,
                      backgroundColor: ProgressEngine.colorFor(p.score),
                    ),
                    title: Text(p.muscle.label),
                    trailing: Text(
                      '${(p.score * 100).round()} % · ${ProgressEngine.tierFor(p.score)}',
                      style: const TextStyle(color: AurumColors.textMuted),
                    ),
                  )),
        ],
      );
  }
}

class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.score, required this.sessions});

  final double score;
  final int sessions;

  @override
  Widget build(BuildContext context) {
    final color = ProgressEngine.colorFor(score);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: score,
                    strokeWidth: 6,
                    color: color,
                    backgroundColor: AurumColors.surfaceHigh,
                  ),
                  Center(
                    child: Text(
                      '${(score * 100).round()}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ProgressEngine.tierFor(score),
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: color, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '$sessions sesiones registradas',
                    style: const TextStyle(color: AurumColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 10,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            gradient: const LinearGradient(colors: [
              AurumColors.bronzeDull,
              AurumColors.bronze,
              AurumColors.amber,
              AurumColors.gold,
              AurumColors.goldBright,
            ]),
          ),
        ),
        const SizedBox(height: 4),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Bronce', style: TextStyle(fontSize: 11, color: AurumColors.textMuted)),
            Text('Ámbar', style: TextStyle(fontSize: 11, color: AurumColors.textMuted)),
            Text('Oro', style: TextStyle(fontSize: 11, color: AurumColors.textMuted)),
          ],
        ),
      ],
    );
  }
}

class _MuscleDetail extends StatelessWidget {
  const _MuscleDetail({required this.p});

  final MuscleProgress p;

  Widget _bar(String label, double value, String hint) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label),
                Text('${(value * 100).round()} %',
                    style: const TextStyle(color: AurumColors.textMuted)),
              ],
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: value,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
              color: ProgressEngine.colorFor(value),
              backgroundColor: AurumColors.surfaceHigh,
            ),
            const SizedBox(height: 2),
            Text(hint,
                style: const TextStyle(fontSize: 12, color: AurumColors.textMuted)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${p.muscle.label} · ${ProgressEngine.tierFor(p.score)}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: ProgressEngine.colorFor(p.score),
                    fontWeight: FontWeight.w700,
                  ),
            ),
            _bar('Consistencia', p.consistency,
                '${p.sessionsLast28} sesiones en 28 días (meta: 8)'),
            _bar('Sobrecarga progresiva', p.progression,
                'Volumen reciente vs. tus primeras sesiones'),
            _bar('Experiencia', p.experience, 'Sesiones acumuladas (meta: 36)'),
            if (p.benchmarkProgress > 0)
              _bar('Récords del check-in', p.benchmarkProgress,
                  'Mejora en tus pruebas semanales ligadas a este músculo'),
            if ((p.daysSinceLast ?? 0) > 14)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Sin trabajarlo hace ${p.daysSinceLast} días: el dorado se está apagando.',
                  style: const TextStyle(color: AurumColors.danger),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
