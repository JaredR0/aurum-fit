import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifications/notification_service.dart';
import '../onboarding/profile_controller.dart';
import '../photos/photos_screen.dart';
import '../plan/plan_controller.dart';
import '../plan/plan_screen.dart';
import '../progress/progress_screen.dart';
import '../timer/timer_home_screen.dart';
import 'dashboard_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Primer arranque tras el onboarding: plan local inmediato y offline.
      final profile = ref.read(profileProvider);
      if (profile != null && ref.read(planProvider).plan == null) {
        await ref.read(planProvider.notifier).generateLocal(profile);
      }
      // Reprograma recordatorios (las horas de comida cambian por día).
      final reminders = NotificationService.loadSettings();
      if (reminders.any) {
        await NotificationService.reschedule(
            reminders, ref.read(planProvider).plan);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [
          DashboardScreen(),
          PlanScreen(),
          TimerHomeScreen(),
          ProgressScreen(),
          PhotosScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Hoy'),
          NavigationDestination(icon: Icon(Icons.fitness_center_outlined), selectedIcon: Icon(Icons.fitness_center), label: 'Plan'),
          NavigationDestination(icon: Icon(Icons.timer_outlined), selectedIcon: Icon(Icons.timer), label: 'Timer'),
          NavigationDestination(icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events), label: 'Progreso'),
          NavigationDestination(icon: Icon(Icons.photo_library_outlined), selectedIcon: Icon(Icons.photo_library), label: 'Fotos'),
        ],
      ),
    );
  }
}
