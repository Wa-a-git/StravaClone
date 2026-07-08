// lib/screens/shell_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'sport_screen.dart';
import 'system_screen.dart';
import 'health_dashboard_screen.dart';
import 'home_screen.dart' show startRun;
import 'musculation_screen.dart' show openMusculationQuickLog;
import 'interval_game_screen.dart';
import 'pace_zone_game_screen.dart';
import 'profile_screen.dart';
import '../theme.dart';
import '../widgets/ui_kit.dart';

/// Index de l'onglet courant (permet de naviguer depuis n'importe quel écran).
/// 0 = Santé, 1 = Sport, 2 = Niveau, 3 = Profil.
final shellIndexProvider = StateProvider<int>((ref) => 0);

class ShellScreen extends ConsumerWidget {
  const ShellScreen({super.key});

  static const _tabs = [
    HealthDashboardScreen(),
    SportScreen(),
    SystemScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(shellIndexProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: kNeonPink,
        onPressed: () => _openQuickLaunch(context, ref),
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: IndexedStack(
        index: currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: _BottomNav(
        currentIndex: currentIndex,
        onTabTap: (i) => ref.read(shellIndexProvider.notifier).state = i,
      ),
    );
  }

  /// Lancement rapide (+), visible sur les 4 onglets. Sur l'onglet Sport
  /// avec le sous-onglet Musculation sélectionné, ouvre directement le flux
  /// de log — partout ailleurs, propose le choix Course (libre / 5 km /
  /// fractionné / zone d'allure).
  Future<void> _openQuickLaunch(BuildContext context, WidgetRef ref) async {
    final onMusculationTab = ref.read(shellIndexProvider) == 1 &&
        ref.read(sportTabProvider) == SportTab.musculation;
    if (onMusculationTab) {
      await openMusculationQuickLog(context);
      return;
    }
    final choice = await showAppSheet<String>(
      context: context,
      child: const CourseQuickLaunchSheet(),
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case 'free':
        startRun(context);
        break;
      case '5k':
        startRun(context, targetKm: 5.0);
        break;
      case 'interval':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const IntervalGameScreen()));
        break;
      case 'pace':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PaceZoneGameScreen()));
        break;
    }
  }
}

// ── Custom Bottom Navigation ──────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabTap;

  const _BottomNav({required this.currentIndex, required this.onTabTap});

  static const _items = [
    (icon: Icons.health_and_safety_rounded, label: 'Santé'),
    (icon: Icons.directions_run_rounded, label: 'Sport'),
    (icon: Icons.military_tech_rounded, label: 'Niveau'),
    (icon: Icons.person_rounded, label: 'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 1.0)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: _NavItem(
                    icon: _items[i].icon,
                    label: _items[i].label,
                    isActive: currentIndex == i,
                    onTap: () => onTabTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? kNeonCyan : AppColors.textSecondary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedScale(
            scale: isActive ? 1.1 : 1.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              color: color,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}
