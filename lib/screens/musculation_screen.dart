// lib/screens/musculation_screen.dart
// Ébauche de la partie Musculation : bibliothèque d'exercices par catégorie
// + création d'une séance simple (choix d'exercices). Pas de suivi de charge
// progressive pour l'instant — ça viendra dans une prochaine passe.
import 'package:flutter/material.dart';
import '../data/exercise_library.dart';
import '../theme.dart';
import '../widgets/ui_kit.dart';
import '../widgets/system_window.dart';

/// Contenu du sous-onglet "Musculation" du hub Sport.
class MusculationSection extends StatefulWidget {
  const MusculationSection({super.key});

  @override
  State<MusculationSection> createState() => _MusculationSectionState();
}

class _MusculationSectionState extends State<MusculationSection> {
  ExerciseCategory? _filter;

  @override
  Widget build(BuildContext context) {
    final exercises = kExerciseLibrary
        .where((e) => _filter == null || e.category == _filter)
        .toList();

    final byCategory = <ExerciseCategory, List<Exercise>>{};
    for (final e in exercises) {
      byCategory.putIfAbsent(e.category, () => []).add(e);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlowButton(
            label: 'NOUVELLE SÉANCE',
            icon: Icons.add_rounded,
            color: kNeonViolet,
            foreground: Colors.white,
            onPressed: () => _openSessionBuilder(context),
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

  Future<void> _openSessionBuilder(BuildContext context) async {
    final selected = await showAppSheet<Set<String>>(
      context: context,
      child: const _SessionBuilderSheet(),
    );
    if (selected == null || selected.isEmpty || !context.mounted) return;
    await showSystemWindow(
      context,
      heading: 'SÉANCE CRÉÉE',
      lines: [
        '${selected.length} exercice${selected.length > 1 ? 's' : ''} ajouté${selected.length > 1 ? 's' : ''}',
        'Le suivi complet (séries, charges) arrive bientôt.',
      ],
      accent: kNeonViolet,
    );
  }
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

/// Feuille de création de séance : sélection multiple d'exercices dans la
/// bibliothèque. Pas encore de séries/reps/charge — juste la composition.
class _SessionBuilderSheet extends StatefulWidget {
  const _SessionBuilderSheet();

  @override
  State<_SessionBuilderSheet> createState() => _SessionBuilderSheetState();
}

class _SessionBuilderSheetState extends State<_SessionBuilderSheet> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nouvelle séance',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Choisis les exercices de ta séance.',
            style: AppText.caption,
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: ListView(
              children: [
                for (final c in ExerciseCategory.values) ...[
                  PanelTitle(c.label.toUpperCase(), color: c.color),
                  const SizedBox(height: AppSpacing.sm),
                  for (final e in kExerciseLibrary.where((e) => e.category == c))
                    _PickableExerciseTile(
                      exercise: e,
                      selected: _selected.contains(e.id),
                      onTap: () => setState(() {
                        _selected.contains(e.id) ? _selected.remove(e.id) : _selected.add(e.id);
                      }),
                    ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ],
            ),
          ),
          GlowButton(
            label: _selected.isEmpty
                ? 'SÉLECTIONNE AU MOINS UN EXERCICE'
                : 'CRÉER LA SÉANCE (${_selected.length})',
            color: kNeonViolet,
            foreground: Colors.white,
            onPressed: _selected.isEmpty ? null : () => Navigator.pop(context, _selected),
          ),
        ],
      ),
    );
  }
}

class _PickableExerciseTile extends StatelessWidget {
  final Exercise exercise;
  final bool selected;
  final VoidCallback onTap;

  const _PickableExerciseTile({
    required this.exercise,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? kNeonViolet.withOpacity(0.10) : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: selected ? kNeonViolet.withOpacity(0.6) : AppColors.border),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: selected ? kNeonViolet : AppColors.textSecondary,
              size: 20,
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
      ),
    );
  }
}
