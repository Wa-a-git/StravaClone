// lib/screens/shell_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'home_screen.dart';
import 'history_screen.dart';
import 'system_screen.dart';
import 'tracking_screen.dart';
import 'health_dashboard_screen.dart';

/// Index de l'onglet courant (permet de naviguer depuis n'importe quel écran).
final shellIndexProvider = StateProvider<int>((ref) => 0);

class ShellScreen extends ConsumerWidget {
  const ShellScreen({super.key});

  static const _tabs = [
    _HealthTab(),
    _HomeTab(),
    _HistoryTab(),
    _SystemTab(),
  ];

  void _openRecord(BuildContext context) {
    HapticFeedback.mediumImpact();
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => const TrackingScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 380),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(shellIndexProvider);
    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: _BottomNav(
        currentIndex: currentIndex,
        onTabTap: (i) => ref.read(shellIndexProvider.notifier).state = i,
        onRecordTap: () => _openRecord(context),
      ),
    );
  }
}

// ── Tab page wrappers ─────────────────────────────────────────────────────────

class _HealthTab extends StatelessWidget {
  const _HealthTab();

  @override
  Widget build(BuildContext context) => const HealthDashboardScreen();
}

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) => const HomeScreen();
}

class _SystemTab extends StatelessWidget {
  const _SystemTab();

  @override
  Widget build(BuildContext context) => const SystemScreen();
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context) => const HistoryScreen();
}

// ── Custom Bottom Navigation ──────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabTap;
  final VoidCallback onRecordTap;

  const _BottomNav({
    required this.currentIndex,
    required this.onTabTap,
    required this.onRecordTap,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141419),
        border: const Border(
          top: BorderSide(color: Color(0xFF00FFFF), width: 1.0),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00FFFF).withOpacity(0.15),
            blurRadius: 15,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              // Dashboard tab
              Expanded(
                child: _NavItem(
                  icon: Icons.health_and_safety_rounded,
                  label: 'Santé',
                  isActive: currentIndex == 0,
                  onTap: () => onTabTap(0),
                ),
              ),

              // Course tab (L'ancien Home)
              Expanded(
                child: _NavItem(
                  icon: Icons.directions_run_rounded,
                  label: 'Course',
                  isActive: currentIndex == 1,
                  onTap: () => onTabTap(1),
                ),
              ),

              // Record tab — center FAB-style
              SizedBox(
                width: 72,
                child: GestureDetector(
                  onTap: onRecordTap,
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF55CBD),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF55CBD).withOpacity(0.5),
                            blurRadius: 15,
                            offset: const Offset(0, 0),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.directions_run_rounded,
                        color: Colors.black,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ),

              // History tab
              Expanded(
                child: _NavItem(
                  icon: Icons.bar_chart_rounded,
                  label: 'History',
                  isActive: currentIndex == 2,
                  onTap: () => onTabTap(2),
                ),
              ),

              // Progression tab (niveau / XP / quêtes)
              Expanded(
                child: _NavItem(
                  icon: Icons.military_tech_rounded,
                  label: 'Niveau',
                  isActive: currentIndex == 3,
                  onTap: () => onTabTap(3),
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
    final color =
    isActive ? const Color(0xFF00FFFF) : const Color(0xFF555555);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
              color: color,
              letterSpacing: -0.2,
              shadows: isActive ? [Shadow(color: color, blurRadius: 5)] : null,
            ),
          ),
        ],
      ),
    );
  }
}