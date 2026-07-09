// lib/screens/musculation_screen.dart
// Musculation : bibliothèque d'exercices par catégorie + flux rapide de log
// (recherche → exercice → séries/répétitions → persisté immédiatement).
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/exercise_library.dart';
import '../models/musculation_log.dart';
import '../providers/game_provider.dart' show musculationRevisionProvider;
import '../services/export_service.dart';
import '../services/musculation_store.dart';
import '../theme.dart';
import '../widgets/ui_kit.dart';

/// Ouvre le flux rapide d'ajout d'exercice — appelable depuis le bouton
/// "NOUVELLE SÉANCE" de cet écran ou depuis le bouton + de lancement rapide
/// du hub Sport.
Future<void> openMusculationQuickLog(BuildContext context) {
  return showAppSheet(context: context, child: const _QuickLogSheet());
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
            label: 'AJOUTER UN EXERCICE',
            icon: Icons.add_rounded,
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
          Text(
              entry.chargeKg > 0
                  ? '${entry.sets} × ${entry.reps} · ${_formatCharge(entry.chargeKg)} kg'
                  : '${entry.sets} × ${entry.reps}',
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

// ── Feuille de log rapide : recherche + catégories + tap = ajouter ───────────
class _QuickLogSheet extends StatefulWidget {
  const _QuickLogSheet();

  @override
  State<_QuickLogSheet> createState() => _QuickLogSheetState();
}

class _QuickLogSheetState extends State<_QuickLogSheet> {
  ExerciseCategory? _filter;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final query = _search.trim().toLowerCase();
    final exercises = kExerciseLibrary.where((e) {
      if (_filter != null && e.category != _filter) return false;
      if (query.isNotEmpty && !e.name.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ajouter un exercice',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Cherche, tape sur un exercice, indique séries et répétitions.',
            style: AppText.caption,
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            onChanged: (v) => setState(() => _search = v),
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Rechercher un exercice…',
              prefixIcon: Icon(Icons.search_rounded, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 10),
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
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: exercises.isEmpty
                ? const Center(
                    child: Text('Aucun exercice trouvé.', style: AppText.caption),
                  )
                : ListView.builder(
                    itemCount: exercises.length,
                    itemBuilder: (context, i) =>
                        _LoggableExerciseTile(exercise: exercises[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LoggableExerciseTile extends ConsumerWidget {
  final Exercise exercise;
  const _LoggableExerciseTile({required this.exercise});

  Future<void> _logIt(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<(int, int, double)>(
      context: context,
      builder: (_) => _SetsRepsDialog(exercise: exercise),
    );
    if (result == null) return;
    await MusculationStore.addEntry(MusculationLogEntry(
      date: DateTime.now(),
      exerciseId: exercise.id,
      exerciseName: exercise.name,
      category: exercise.category,
      sets: result.$1,
      reps: result.$2,
      chargeKg: result.$3,
    ));
    _syncMusculationDayToVault();
    ref.read(musculationRevisionProvider.notifier).state++;
    if (context.mounted) {
      final chargeLabel =
          result.$3 > 0 ? ' à ${_formatCharge(result.$3)} kg' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${exercise.name} ajouté : ${result.$1} × ${result.$2}$chargeLabel'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _logIt(context, ref),
      child: Container(
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
              child: Icon(exercise.category.icon,
                  color: exercise.category.color, size: 17),
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
            Icon(Icons.add_circle_outline_rounded,
                color: exercise.category.color, size: 22),
          ],
        ),
      ),
    );
  }
}

class _SetsRepsDialog extends StatefulWidget {
  final Exercise exercise;
  const _SetsRepsDialog({required this.exercise});

  @override
  State<_SetsRepsDialog> createState() => _SetsRepsDialogState();
}

class _SetsRepsDialogState extends State<_SetsRepsDialog> {
  int _sets = 3;
  int _reps = 10;
  double _charge = 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(widget.exercise.name,
          style: const TextStyle(
              fontFamily: kArcadeFont, color: AppColors.textPrimary, fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperRow(
              label: 'Séries',
              value: _sets,
              onChanged: (v) => setState(() => _sets = v)),
          const SizedBox(height: 14),
          _StepperRow(
              label: 'Répétitions',
              value: _reps,
              onChanged: (v) => setState(() => _reps = v)),
          const SizedBox(height: 14),
          _ChargeStepperRow(
              value: _charge, onChanged: (v) => setState(() => _charge = v)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: widget.exercise.category.color),
          onPressed: () => Navigator.pop(context, (_sets, _reps, _charge)),
          child: const Text('Ajouter', style: TextStyle(color: Colors.black)),
        ),
      ],
    );
  }
}

/// Charge par répétition — poids du corps par défaut (0, affiché "--"),
/// incréments de 2,5 kg (le pas usuel d'une paire de disques).
class _ChargeStepperRow extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _ChargeStepperRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Charge (kg)',
            style: TextStyle(color: AppColors.textSecondary)),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded,
                  color: AppColors.textSecondary),
              onPressed:
                  value > 0 ? () => onChanged(max(0, value - 2.5)) : null,
            ),
            SizedBox(
              width: 44,
              child: Text(
                value > 0 ? _formatCharge(value) : '--',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: kArcadeFont,
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded,
                  color: AppColors.textSecondary),
              onPressed: () => onChanged(value + 2.5),
            ),
          ],
        ),
      ],
    );
  }
}

/// Formate une charge sans décimale inutile ("40" plutôt que "40.0", mais
/// "42.5" reste tel quel).
String _formatCharge(double kg) =>
    kg == kg.roundToDouble() ? kg.toInt().toString() : kg.toStringAsFixed(1);

class _StepperRow extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  const _StepperRow(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded,
                  color: AppColors.textSecondary),
              onPressed: value > 1 ? () => onChanged(value - 1) : null,
            ),
            SizedBox(
              width: 30,
              child: Text('$value',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: kArcadeFont,
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded,
                  color: AppColors.textSecondary),
              onPressed: () => onChanged(value + 1),
            ),
          ],
        ),
      ],
    );
  }
}
