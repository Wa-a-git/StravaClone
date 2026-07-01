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

enum SportTab { course, musculation }

extension on SportTab {
  String get label => switch (this) {
        SportTab.course => 'Course',
        SportTab.musculation => 'Musculation',
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
              },
            ),
          ),
        ],
      ),
    );
  }
}
