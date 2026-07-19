// lib/screens/musculation_screen.dart
// Musculation : bibliothèque d'exercices par catégorie (référence, pas de
// log direct depuis ici) + lancement d'une séance en direct chronométrée
// (live_musculation_screen.dart) où se fait tout le log réel.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/exercise_library.dart';
import '../models/musculation_log.dart';
import '../providers/game_provider.dart' show musculationRevisionProvider;
import '../services/export_service.dart';
import '../services/musculation_store.dart';
import '../theme.dart';
import '../widgets/ui_kit.dart';
import 'live_musculation_screen.dart';

/// Lance une séance en direct — appelable depuis le bouton "DÉMARRER UNE
/// SÉANCE" de cet écran ou depuis le bouton + de lancement rapide du hub
/// Sport.
Future<void> openMusculationQuickLog(BuildContext context) {
  return Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const LiveMusculationScreen()),
  );
}

/// Réexporte toute la séance du jour vers le vault (mycelium) — appelé après
/// chaque ajout/suppression d'exercice, best-effort et fire-and-forget comme
/// le reste des exports (santé, activités). Contrairement à celles-ci, la
/// musculation n'avait jusqu'ici aucun export : rien ne remontait dans la
/// note du jour côté Marble.
void _syncMusculationDayToVault() {
  final today = MusculationStore.todayEntries().map((e) => e.value).toList();
  unawaited(ExportService.saveMusculationDayAsMarkdown(DateTime.now(), today));
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

  @override
  Widget build(BuildContext context) {
    final exercises = kExerciseLibrary
        .where((e) => _filter == null || e.category == _filter)
        .toList();

    final byCategory = <ExerciseCategory, List<Exercise>>{};
    for (final e in exercises) {
      byCategory.putIfAbsent(e.category, () => []).add(e);
    }

    final todayEntries = MusculationStore.todayEntries();

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
          if (todayEntries.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            const Text('Séance du jour', style: AppText.screenTitle),
            const SizedBox(height: AppSpacing.md),
            for (final entry in todayEntries)
              _LoggedEntryTile(
                logKey: entry.key,
                entry: entry.value,
                onDeleted: () => setState(() {}),
              ),
          ],
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

// ── Entrée loggée aujourd'hui (avec suppression) ──────────────────────────────
class _LoggedEntryTile extends ConsumerWidget {
  final String logKey;
  final MusculationLogEntry entry;
  final VoidCallback onDeleted;
  const _LoggedEntryTile(
      {required this.logKey, required this.entry, required this.onDeleted});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: entry.category.color.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(entry.category.icon, color: entry.category.color, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(entry.exerciseName, style: AppText.body),
          ),
          Text(_entrySummary(entry),
              style: TextStyle(
                  fontFamily: kArcadeFont,
                  color: entry.category.color,
                  fontSize: 13,
                  fontWeight: FontWeight.w800)),
          IconButton(
            icon: const Icon(Icons.close_rounded,
                color: AppColors.textSecondary, size: 18),
            onPressed: () async {
              await MusculationStore.deleteEntry(logKey);
              _syncMusculationDayToVault();
              ref.read(musculationRevisionProvider.notifier).state++;
              onDeleted();
            },
          ),
        ],
      ),
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

/// Formate une charge sans décimale inutile ("40" plutôt que "40.0", mais
/// "42.5" reste tel quel).
String _formatCharge(double kg) =>
    kg == kg.roundToDouble() ? kg.toInt().toString() : kg.toStringAsFixed(1);

/// Résumé compact d'une entrée loggée — durée/distance pour le cardio (sets
/// vaut toujours 1 pour ces entrées-là, sans intérêt à afficher), reps ×
/// charge sinon.
String _entrySummary(MusculationLogEntry entry) {
  if (entry.category.isCardio) {
    final m = entry.durationSeconds ~/ 60;
    final s = entry.durationSeconds % 60;
    final duration = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return entry.distanceKm > 0
        ? '$duration · ${entry.distanceKm.toStringAsFixed(1)} km'
        : duration;
  }
  return entry.chargeKg > 0
      ? '${entry.sets} × ${entry.reps} · ${_formatCharge(entry.chargeKg)} kg'
      : '${entry.sets} × ${entry.reps}';
}
