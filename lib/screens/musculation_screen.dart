// lib/screens/musculation_screen.dart
// Musculation : bibliothèque d'exercices par catégorie (référence, pas de
// log direct depuis ici) + lancement d'une séance en direct chronométrée
// (live_musculation_screen.dart) où se fait tout le log réel.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/exercise_library.dart';
import '../models/musculation_session.dart';
import '../services/musculation_session_store.dart';
import '../theme.dart';
import '../widgets/ui_kit.dart';
import 'live_musculation_screen.dart';
import 'musculation_history_screen.dart';
import 'musculation_session_detail_screen.dart';

/// Lance une séance en direct — appelable depuis le bouton "DÉMARRER UNE
/// SÉANCE" de cet écran ou depuis le bouton + de lancement rapide du hub
/// Sport.
Future<void> openMusculationQuickLog(BuildContext context) {
  return Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const LiveMusculationScreen()),
  );
}

/// Contenu du sous-onglet "Musculation" du hub Sport.
class MusculationSection extends ConsumerStatefulWidget {
  const MusculationSection({super.key});

  @override
  ConsumerState<MusculationSection> createState() =>
      _MusculationSectionState();
}

class _MusculationSectionState extends ConsumerState<MusculationSection> {
  ExerciseCategory? _filter;

  Future<void> _openQuickLog() async {
    await openMusculationQuickLog(context);
    if (mounted) setState(() {}); // rafraîchit "Séance du jour"
  }

  Future<void> _openSession(MusculationSession session) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => MusculationSessionDetailScreen(session: session)),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final exercises = kExerciseLibrary
        .where((e) => _filter == null || e.category == _filter)
        .toList();

    final byCategory = <ExerciseCategory, List<Exercise>>{};
    for (final e in exercises) {
      byCategory.putIfAbsent(e.category, () => []).add(e);
    }

    final todaySessions = MusculationSessionStore.forDay(DateTime.now());

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlowButton(
            label: 'DÉMARRER UNE SÉANCE',
            icon: Icons.play_circle_fill_rounded,
            color: kNeonViolet,
            foreground: Colors.white,
            onPressed: _openQuickLog,
          ),
          if (todaySessions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            const Text('Séance du jour', style: AppText.screenTitle),
            const SizedBox(height: AppSpacing.md),
            for (final session in todaySessions)
              _TodaySessionCard(
                session: session,
                onTap: () => _openSession(session),
              ),
          ],
          const SizedBox(height: AppSpacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Historique', style: AppText.screenTitle),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MusculationHistoryScreen()),
                ),
                child: const Text('Tout voir →'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('Bibliothèque d\'exercices', style: AppText.screenTitle),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _CategoryChip(
                  label: 'Tout',
                  color: AppColors.textSecondary,
                  selected: _filter == null,
                  onTap: () => setState(() => _filter = null),
                ),
                for (final c in ExerciseCategory.values) ...[
                  const SizedBox(width: 8),
                  _CategoryChip(
                    label: c.label,
                    color: c.color,
                    selected: _filter == c,
                    onTap: () => setState(() => _filter = c),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final entry in byCategory.entries) ...[
            PanelTitle(entry.key.label.toUpperCase(), color: entry.key.color),
            const SizedBox(height: AppSpacing.sm),
            ...entry.value.map((e) => _ExerciseTile(exercise: e)),
            const SizedBox(height: AppSpacing.lg),
          ],
        ],
      ),
    );
  }
}

// ── Carte "séance du jour" : résumé cliquable vers le détail, plutôt que le
// flot brut de chaque bloc (illisible dès qu'une séance dépasse 3-4
// exercices, et une séance peut désormais compter des dizaines de blocs
// individuels). ───────────────────────────────────────────────────────────
class _TodaySessionCard extends StatelessWidget {
  final MusculationSession session;
  final VoidCallback onTap;
  const _TodaySessionCard({required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final h = session.durationSeconds ~/ 3600;
    final m = (session.durationSeconds % 3600) ~/ 60;
    final duration = h > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '${m}m';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: kNeonViolet.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.fitness_center_rounded, color: kNeonViolet, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${_hour(session.date)} · $duration',
                      style: AppText.body),
                  if (session.hasHr)
                    Text('FC moy. ${session.avgHr.round()} bpm', style: AppText.caption),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: kNeonViolet, size: 20),
          ],
        ),
      ),
    );
  }

  String _hour(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.16) : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color.withOpacity(0.6) : AppColors.border),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  final Exercise exercise;
  const _ExerciseTile({required this.exercise});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: exercise.category.color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(exercise.category.icon, color: exercise.category.color, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exercise.name, style: AppText.body),
                Text(exercise.muscleGroup, style: AppText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

