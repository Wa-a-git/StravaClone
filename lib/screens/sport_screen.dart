// lib/screens/sport_screen.dart
// Hub "Sport" : regroupe Course (ex-Home + historique + mini-jeux) et
// Musculation sous un seul onglet, avec un sélecteur en haut plutôt que
// deux entrées de navigation séparées et incohérentes.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../widgets/ui_kit.dart';
import 'home_screen.dart';
import 'musculation_screen.dart';
import 'system_screen.dart';

enum SportTab { course, musculation, progression }

extension on SportTab {
  String get label => switch (this) {
        SportTab.course => 'Course',
        SportTab.musculation => 'Musculation',
        SportTab.progression => 'Progression',
      };
}

final sportTabProvider = StateProvider<SportTab>((ref) => SportTab.course);

class SportScreen extends ConsumerWidget {
  const SportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(sportTabProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 100,
            pinned: true,
            backgroundColor: AppColors.surface,
            elevation: 0,
            flexibleSpace: const FlexibleSpaceBar(
              titlePadding: EdgeInsets.only(left: 20, bottom: 16),
              title: Text(
                'SPORT',
                style: TextStyle(
                  fontFamily: kArcadeFont,
                  color: AppColors.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  shadows: [Shadow(color: AppColors.arcadePink, blurRadius: 12)],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: SegmentedTabs<SportTab>(
                values: SportTab.values,
                selected: tab,
                labelOf: (t) => t.label,
                onChanged: (t) => ref.read(sportTabProvider.notifier).state = t,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero)
                      .animate(animation),
                  child: child,
                ),
              ),
              child: switch (tab) {
                SportTab.course => const CourseSection(key: ValueKey('course')),
                SportTab.musculation => const MusculationSection(key: ValueKey('muscu')),
                SportTab.progression => const ProgressionSection(key: ValueKey('progression')),
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Feuille de lancement rapide (Course) — publique : le bouton "+" global
// (voir shell_screen.dart) l'ouvre depuis n'importe quel onglet. ─────────────
class CourseQuickLaunchSheet extends StatelessWidget {
  const CourseQuickLaunchSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Lancer une activité',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _QuickLaunchTile(
          icon: Icons.play_arrow_rounded,
          color: kNeonPink,
          title: 'Course libre',
          subtitle: 'Suivi GPS sans objectif',
          onTap: () => Navigator.pop(context, 'free'),
        ),
        _QuickLaunchTile(
          icon: Icons.directions_run_rounded,
          color: kNeonGreen,
          title: '5 km quotidien',
          subtitle: 'Ta routine du jour',
          onTap: () => Navigator.pop(context, '5k'),
        ),
        _QuickLaunchTile(
          icon: Icons.timer_rounded,
          color: kNeonCyan,
          title: 'Fractionné',
          subtitle: 'Intervalles effort/repos guidés',
          onTap: () => Navigator.pop(context, 'interval'),
        ),
        _QuickLaunchTile(
          icon: Icons.speed_rounded,
          color: kNeonViolet,
          title: 'Zone d\'allure',
          subtitle: 'Maintiens une allure cible',
          onTap: () => Navigator.pop(context, 'pace'),
        ),
        _QuickLaunchTile(
          icon: Icons.directions_walk_rounded,
          color: kNeonAmber,
          title: 'Tapis',
          subtitle: 'Course en salle, saisie manuelle',
          onTap: () => Navigator.pop(context, 'treadmill'),
        ),
      ],
    );
  }
}

class _QuickLaunchTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _QuickLaunchTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.body),
                    Text(subtitle, style: AppText.caption),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
