// lib/screens/manual_cardio_entry_screen.dart
// Saisie manuelle d'une activité cardio sans GPS : course sur tapis (lancement
// rapide dédié) ou échauffement avant une séance de musculation (tapis /
// course extérieure / autre). Distance + durée suffisent — pas de tracé, pas
// de FC (Health Connect n'a rien à rattacher à une fenêtre non trackée en
// temps réel ici, contrairement à une activité GPS).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/activity.dart';
import '../providers/activity_provider.dart';
import '../services/export_service.dart';
import '../services/hive_service.dart';
import '../theme.dart';
import '../widgets/ui_kit.dart';

enum ManualCardioType { treadmill, run, other }

extension ManualCardioTypeX on ManualCardioType {
  String get label => switch (this) {
        ManualCardioType.treadmill => 'Tapis',
        ManualCardioType.run => 'Course',
        ManualCardioType.other => 'Autre',
      };

  IconData get icon => switch (this) {
        ManualCardioType.treadmill => Icons.directions_walk_rounded,
        ManualCardioType.run => Icons.directions_run_rounded,
        ManualCardioType.other => Icons.fitness_center_rounded,
      };

  /// Valeur stockée dans `Activity.workoutType` — distincte du `null`
  /// historique (course libre trackée GPS) pour ne pas mélanger les deux
  /// dans les stats qui supposent une vraie trace (VO2 max par lap, etc.).
  String get workoutType => switch (this) {
        ManualCardioType.treadmill => 'treadmill',
        ManualCardioType.run => 'run_manual',
        ManualCardioType.other => 'other_cardio',
      };
}

/// [fixedType] : si renseigné, pas de sélecteur (lancement rapide "Tapis").
/// Sinon (échauffement muscu), les 3 types sont proposés.
class ManualCardioEntryScreen extends ConsumerStatefulWidget {
  final String title;
  final ManualCardioType? fixedType;
  final String? defaultName;

  const ManualCardioEntryScreen({
    super.key,
    required this.title,
    this.fixedType,
    this.defaultName,
  });

  @override
  ConsumerState<ManualCardioEntryScreen> createState() =>
      _ManualCardioEntryScreenState();
}

class _ManualCardioEntryScreenState
    extends ConsumerState<ManualCardioEntryScreen> {
  late ManualCardioType _type = widget.fixedType ?? ManualCardioType.treadmill;
  final _distanceCtrl = TextEditingController();
  final _minutesCtrl = TextEditingController();
  final _secondsCtrl = TextEditingController();
  final _inclineCtrl = TextEditingController();
  late final _nameCtrl = TextEditingController(text: widget.defaultName ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _distanceCtrl.dispose();
    _minutesCtrl.dispose();
    _secondsCtrl.dispose();
    _inclineCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  int get _durationSeconds =>
      (int.tryParse(_minutesCtrl.text) ?? 0) * 60 +
      (int.tryParse(_secondsCtrl.text) ?? 0);

  double get _distanceKm => double.tryParse(_distanceCtrl.text.replaceAll(',', '.')) ?? 0;

  /// Uniquement affichée/prise en compte pour le tapis — pas de sens pour une
  /// course extérieure ou une autre activité cardio saisie à la main.
  double? get _inclinePercent =>
      _type == ManualCardioType.treadmill
          ? double.tryParse(_inclineCtrl.text.replaceAll(',', '.'))
          : null;

  bool get _canSave => _durationSeconds > 0;

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    setState(() => _saving = true);
    final name = _nameCtrl.text.trim();
    final activity = Activity(
      date: DateTime.now(),
      distance: _distanceKm * 1000,
      duration: _durationSeconds,
      route: const [],
      name: name.isEmpty ? null : name,
      workoutType: _type.workoutType,
      inclinePercent: _inclinePercent,
    );
    await HiveService.saveActivity(activity);
    // Best-effort, comme le reste des exports (course, santé) — n'empêche
    // jamais la sauvegarde locale si le vault est injoignable.
    // ignore: unawaited_futures
    ExportService.saveActivityAsMarkdown(activity);
    ref.read(activityListProvider.notifier).refresh();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(
          widget.title.toUpperCase(),
          style: const TextStyle(
            fontFamily: kArcadeFont,
            color: kNeonCyan,
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.fixedType == null) ...[
            const PanelTitle('TYPE'),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                for (final t in ManualCardioType.values) ...[
                  if (t != ManualCardioType.values.first)
                    const SizedBox(width: 10),
                  Expanded(child: _TypeChip(
                    type: t,
                    selected: _type == t,
                    onTap: () => setState(() => _type = t),
                  )),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
          AppPanel(
            accent: kNeonCyan,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PanelTitle('DURÉE', color: kNeonCyan),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _minutesCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Minutes',
                          suffixText: 'min',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _secondsCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Secondes',
                          suffixText: 's',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppPanel(
            accent: kNeonViolet,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PanelTitle('DISTANCE (OPTIONNELLE)', color: kNeonViolet),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _distanceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'ex. 5.0',
                    suffixText: 'km',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
          if (_type == ManualCardioType.treadmill) ...[
            const SizedBox(height: AppSpacing.lg),
            AppPanel(
              accent: kNeonAmber,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PanelTitle('INCLINAISON (OPTIONNELLE)', color: kNeonAmber),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _inclineCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'ex. 1.5',
                      suffixText: '%',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PanelTitle('NOM (OPTIONNEL)'),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(hintText: 'ex. Échauffement'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          GlowButton(
            label: 'ENREGISTRER',
            icon: Icons.check_rounded,
            color: kNeonPink,
            foreground: Colors.white,
            busy: _saving,
            onPressed: _canSave ? _save : null,
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final ManualCardioType type;
  final bool selected;
  final VoidCallback onTap;
  const _TypeChip({required this.type, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? kNeonCyan.withOpacity(0.16) : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: selected ? kNeonCyan : AppColors.border),
        ),
        child: Column(
          children: [
            Icon(type.icon, color: selected ? kNeonCyan : AppColors.textSecondary, size: 20),
            const SizedBox(height: 4),
            Text(
              type.label,
              style: TextStyle(
                color: selected ? kNeonCyan : AppColors.textSecondary,
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
