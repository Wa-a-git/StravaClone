// lib/screens/musculation_session_detail_screen.dart
// Détail d'une séance musculation/cardio — même esprit que detail_screen.dart
// (courses) : dashboard de stats, graphe FC sur toute la séance, détail
// bloc par bloc groupé par exercice, export Markdown vers le vault.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/exercise_library.dart';
import '../models/musculation_log.dart';
import '../models/musculation_session.dart';
import '../providers/game_provider.dart' show musculationRevisionProvider;
import '../services/export_service.dart';
import '../services/musculation_store.dart';
import '../theme.dart';
import '../widgets/health_charts.dart';

class MusculationSessionDetailScreen extends ConsumerStatefulWidget {
  final MusculationSession session;
  const MusculationSessionDetailScreen({super.key, required this.session});

  @override
  ConsumerState<MusculationSessionDetailScreen> createState() =>
      _MusculationSessionDetailScreenState();
}

class _MusculationSessionDetailScreenState
    extends ConsumerState<MusculationSessionDetailScreen> {
  late List<MapEntry<String, MusculationLogEntry>> _sets =
      MusculationStore.entriesForSession(widget.session.sessionId);

  void _refresh() {
    setState(() {
      _sets = MusculationStore.entriesForSession(widget.session.sessionId);
    });
  }

  Future<void> _deleteSet(String key) async {
    await MusculationStore.deleteEntry(key);
    ref.read(musculationRevisionProvider.notifier).state++;
    _refresh();
    // Ré-exporte la fiche pour refléter la suppression — best-effort, ne
    // bloque jamais l'UI.
    unawaited(ExportService.saveMusculationSessionAsMarkdown(
        widget.session, _sets.map((e) => e.value).toList()));
  }

  Future<void> _exportMarkdown() async {
    final path = await ExportService.saveMusculationSessionAsMarkdown(
        widget.session, _sets.map((e) => e.value).toList());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(path != null
            ? 'Fiche exportée : $path'
            : 'Impossible d\'exporter la fiche.'),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Map<String, List<MapEntry<String, MusculationLogEntry>>> get _byExercise {
    final order = <String>[];
    final grouped = <String, List<MapEntry<String, MusculationLogEntry>>>{};
    for (final s in _sets) {
      final id = s.value.exerciseId;
      if (!grouped.containsKey(id)) order.add(id);
      grouped.putIfAbsent(id, () => []).add(s);
    }
    return {for (final id in order) id: grouped[id]!};
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final strengthSets = _sets.map((e) => e.value).where((e) => !e.category.isCardio).toList();
    final cardioSets = _sets.map((e) => e.value).where((e) => e.category.isCardio).toList();
    final totalVolume = strengthSets.fold<double>(0, (s, e) => s + e.volumeKg);
    final totalCardioDuration = cardioSets.fold<int>(0, (s, e) => s + e.durationSeconds);
    final totalCardioDistance = cardioSets.fold<double>(0, (s, e) => s + e.distanceKm);
    final muscleGroups = <String>{
      for (final e in strengthSets) _muscleGroupFor(e.exerciseId) ?? e.category.label,
    }.toList();

    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xFF09090B),
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF141419),
                  shape: BoxShape.circle,
                  border: Border.all(color: kNeonCyan, width: 1.2),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 16, color: kNeonCyan),
              ),
            ),
            actions: [
              IconButton(
                onPressed: _exportMarkdown,
                icon: const Icon(Icons.download_rounded, color: kNeonCyan),
                tooltip: 'Exporter en Markdown',
              ),
            ],
            title: Column(
              children: [
                const Text('SÉANCE',
                    style: TextStyle(
                        fontFamily: kArcadeFont,
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        shadows: [Shadow(color: kNeonPink, blurRadius: 8)])),
                Text(_formatDateShort(session.date),
                    style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 12)),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                children: [
                  if (muscleGroups.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final g in muscleGroups)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: kNeonViolet.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(g,
                                style: const TextStyle(
                                    color: kNeonViolet, fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  _buildStatsGrid(session, strengthSets.length + cardioSets.length,
                      totalVolume, totalCardioDuration, totalCardioDistance),
                  const SizedBox(height: 16),
                  _buildHrCard(session),
                  const SizedBox(height: 16),
                  ..._byExercise.entries.map((entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ExerciseGroupCard(
                          exerciseName: entry.value.first.value.exerciseName,
                          sets: entry.value,
                          onDelete: _deleteSet,
                        ),
                      )),
                  if (_sets.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text('Plus aucun bloc dans cette séance.',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _muscleGroupFor(String exerciseId) {
    for (final e in kExerciseLibrary) {
      if (e.id == exerciseId) return e.muscleGroup;
    }
    return null;
  }

  Widget _buildStatsGrid(MusculationSession session, int totalBlocs,
      double totalVolume, int totalCardioDuration, double totalCardioDistance) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _DetailStatCard(
                label: 'Durée',
                value: _fmtClock(session.durationSeconds),
                unit: '',
                iconColor: kNeonCyan,
                icon: Icons.timer_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DetailStatCard(
                label: 'Blocs',
                value: '$totalBlocs',
                unit: '',
                iconColor: kNeonPink,
                icon: Icons.format_list_numbered_rounded,
              ),
            ),
          ],
        ),
        if (totalVolume > 0) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DetailStatCard(
                  label: 'Volume total',
                  value: totalVolume.toStringAsFixed(0),
                  unit: 'kg',
                  iconColor: kNeonAmber,
                  icon: Icons.fitness_center_rounded,
                ),
              ),
            ],
          ),
        ],
        if (totalCardioDuration > 0) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DetailStatCard(
                  label: 'Cardio',
                  value: _fmtClock(totalCardioDuration),
                  unit: totalCardioDistance > 0
                      ? '${totalCardioDistance.toStringAsFixed(1)} km'
                      : '',
                  iconColor: kNeonGreen,
                  icon: Icons.directions_run_rounded,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildHrCard(MusculationSession session) {
    if (!session.hasHr) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF141419),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kNeonCyan.withOpacity(0.4), width: 1.2),
        boxShadow: [BoxShadow(color: kNeonCyan.withOpacity(0.10), blurRadius: 12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.watch_rounded, color: kNeonCyan, size: 18),
              const SizedBox(width: 8),
              const Text('Données montre',
                  style: TextStyle(
                      fontFamily: kArcadeFont,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: kNeonCyan,
                      letterSpacing: 0.5,
                      shadows: [Shadow(color: kNeonCyan, blurRadius: 6)])),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _WatchStat(
                    label: 'FC moy.', value: session.avgHr.round().toString(), unit: 'bpm', color: kNeonPink),
              ),
              Expanded(
                child: _WatchStat(
                    label: 'FC max', value: session.maxHr.round().toString(), unit: 'bpm', color: kNeonRed),
              ),
              Expanded(
                child: _WatchStat(
                    label: 'FC min', value: session.minHr.round().toString(), unit: 'bpm', color: kNeonCyan),
              ),
              Expanded(
                child: _WatchStat(
                  label: 'Cal. actives',
                  value: session.activeCalories > 0 ? session.activeCalories.round().toString() : '--',
                  unit: 'kcal',
                  color: kNeonAmber,
                ),
              ),
            ],
          ),
          if (session.hrBpm.length >= 2) ...[
            const SizedBox(height: 18),
            const Text('Fréquence cardiaque pendant la séance',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            const SizedBox(height: 8),
            TrendChart(
              values: session.hrBpm,
              dates: session.hrDates,
              color: kNeonPink,
              unit: ' bpm',
              height: 140,
              xLabelFormatter: (d) =>
                  '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
            ),
          ],
        ],
      ),
    );
  }

  String _formatDateShort(DateTime date) {
    const months = [
      'Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin',
      'Juil', 'Aoû', 'Sep', 'Oct', 'Nov', 'Déc'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year} · '
        '${date.hour.toString().padLeft(2, '0')}h${date.minute.toString().padLeft(2, '0')}';
  }
}

String _fmtClock(int totalSeconds) {
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  if (h > 0) {
    return '${h}h${m.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

// ── Carte d'un exercice : toutes ses séries/blocs, avec suppression ─────────
class _ExerciseGroupCard extends StatelessWidget {
  final String exerciseName;
  final List<MapEntry<String, MusculationLogEntry>> sets;
  final ValueChanged<String> onDelete;

  const _ExerciseGroupCard(
      {required this.exerciseName, required this.sets, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final accent = sets.first.value.category.color;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141419),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.35), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(sets.first.value.category.icon, color: accent, size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Text(exerciseName,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < sets.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text('${i + 1}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ),
                  Expanded(
                    child: Text(_blockSummary(sets[i].value),
                        style: const TextStyle(
                            fontFamily: kArcadeFont,
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ),
                  if (sets[i].value.restSeconds > 0) ...[
                    const Icon(Icons.timer_outlined, color: AppColors.textSecondary, size: 13),
                    const SizedBox(width: 3),
                    Text(_fmtClock(sets[i].value.restSeconds),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(width: 8),
                  ],
                  GestureDetector(
                    onTap: () => onDelete(sets[i].key),
                    child: const Icon(Icons.close_rounded,
                        color: AppColors.textSecondary, size: 16),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _blockSummary(MusculationLogEntry e) {
    if (e.category.isCardio) {
      final parts = <String>[_fmtClock(e.durationSeconds)];
      if (e.distanceKm > 0) parts.add('${e.distanceKm.toStringAsFixed(1)} km');
      if (e.isInterval) parts.add('fractionné');
      return parts.join(' · ');
    }
    final sideSuffix = e.side == 'L' ? ' (G)' : (e.side == 'R' ? ' (D)' : '');
    final base = e.chargeKg > 0
        ? '${e.reps} × ${_formatCharge(e.chargeKg)} kg'
        : '${e.reps} reps';
    return base + sideSuffix;
  }

  String _formatCharge(double kg) =>
      kg == kg.roundToDouble() ? kg.toInt().toString() : kg.toStringAsFixed(1);
}

class _DetailStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color iconColor;
  final IconData icon;

  const _DetailStatCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.iconColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141419),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: iconColor.withOpacity(0.4), width: 1),
        boxShadow: [BoxShadow(color: iconColor.withOpacity(0.12), blurRadius: 10)],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFFAAAAAA), fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: value,
                          style: const TextStyle(
                              fontFamily: kArcadeFont,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white),
                        ),
                        if (unit.isNotEmpty)
                          TextSpan(
                            text: ' $unit',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w500, color: iconColor),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WatchStat extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _WatchStat(
      {required this.label, required this.value, required this.unit, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          alignment: Alignment.centerLeft,
          fit: BoxFit.scaleDown,
          child: RichText(
            text: TextSpan(children: [
              TextSpan(
                  text: value,
                  style: TextStyle(
                      fontFamily: kArcadeFont, fontSize: 19, fontWeight: FontWeight.w900, color: color)),
              TextSpan(
                  text: ' $unit',
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
            ]),
          ),
        ),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
