// lib/screens/musculation_history_screen.dart
// Historique des séances musculation/cardio — même esprit que
// history_screen.dart (courses) : résumé all-time + liste des séances,
// chacune cliquable vers son détail.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/exercise_library.dart';
import '../models/musculation_log.dart';
import '../models/musculation_session.dart';
import '../providers/game_provider.dart' show musculationRevisionProvider;
import '../services/musculation_session_store.dart';
import '../services/musculation_store.dart';
import '../theme.dart';
import '../widgets/ui_kit.dart';
import 'musculation_session_detail_screen.dart';

class MusculationHistoryScreen extends ConsumerStatefulWidget {
  const MusculationHistoryScreen({super.key});

  @override
  ConsumerState<MusculationHistoryScreen> createState() =>
      _MusculationHistoryScreenState();
}

class _MusculationHistoryScreenState
    extends ConsumerState<MusculationHistoryScreen> {
  late List<MusculationSession> _sessions = MusculationSessionStore.all();

  void _refresh() => setState(() => _sessions = MusculationSessionStore.all());

  Future<void> _openSession(MusculationSession session) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => MusculationSessionDetailScreen(session: session)),
    );
    _refresh();
  }

  Future<void> _confirmDelete(MusculationSession session) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF141419),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Supprimer cette séance ?',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    shadows: [Shadow(color: kNeonPink, blurRadius: 8)])),
            const SizedBox(height: 6),
            const Text('Tous ses blocs seront supprimés. Non réversible.',
                style: TextStyle(fontSize: 15, color: Color(0xFFAAAAAA))),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: kNeonRed,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: const Text('Supprimer',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kNeonCyan)),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await MusculationStore.deleteSession(session.sessionId);
    await MusculationSessionStore.deleteEntry(session.sessionId);
    ref.read(musculationRevisionProvider.notifier).state++;
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(
            expandedHeight: 100,
            pinned: true,
            backgroundColor: AppColors.surface,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: EdgeInsets.only(left: 20, bottom: 16),
              title: Text(
                'HISTORIQUE MUSCU',
                style: TextStyle(
                  fontFamily: kArcadeFont,
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                  shadows: [Shadow(color: kNeonViolet, blurRadius: 12)],
                ),
              ),
            ),
          ),
          if (_sessions.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.fitness_center_rounded,
                title: 'Aucune séance pour le moment',
                subtitle: 'Démarre une séance en direct pour la voir ici.',
                accent: kNeonViolet,
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: _HistorySummaryCard(sessions: _sessions),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final session = _sessions[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SessionHistoryCard(
                        session: session,
                        sets: MusculationStore.entriesForSession(session.sessionId)
                            .map((e) => e.value)
                            .toList(),
                        onTap: () => _openSession(session),
                        onDelete: () => _confirmDelete(session),
                      ),
                    );
                  },
                  childCount: _sessions.length,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HistorySummaryCard extends StatelessWidget {
  final List<MusculationSession> sessions;
  const _HistorySummaryCard({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final totalDuration =
        sessions.fold<int>(0, (s, e) => s + e.durationSeconds);
    double totalVolume = 0;
    double totalCardioDistance = 0;
    for (final session in sessions) {
      for (final e in MusculationStore.entriesForSession(session.sessionId)) {
        if (e.value.category.isCardio) {
          totalCardioDistance += e.value.distanceKm;
        } else {
          totalVolume += e.value.volumeKg;
        }
      }
    }
    final h = totalDuration ~/ 3600;
    final m = (totalDuration % 3600) ~/ 60;

    return AppPanel(
      accent: kNeonViolet,
      hero: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelTitle('RÉSUMÉ', color: kNeonViolet),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SummaryValue(label: 'Séances', value: '${sessions.length}'),
              _SummaryValue(label: 'Temps total', value: '${h}h ${m}m'),
              if (totalVolume > 0)
                _SummaryValue(
                    label: 'Volume total', value: '${totalVolume.toStringAsFixed(0)} kg'),
              if (totalVolume == 0 && totalCardioDistance > 0)
                _SummaryValue(
                    label: 'Distance cardio',
                    value: '${totalCardioDistance.toStringAsFixed(1)} km'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: const TextStyle(
                  fontFamily: kArcadeFont,
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      ],
    );
  }
}

class _SessionHistoryCard extends StatelessWidget {
  final MusculationSession session;
  final List<MusculationLogEntry> sets;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SessionHistoryCard({
    required this.session,
    required this.sets,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final strengthSets = sets.where((e) => !e.category.isCardio).toList();
    final cardioSets = sets.where((e) => e.category.isCardio).toList();
    final totalVolume = strengthSets.fold<double>(0, (s, e) => s + e.volumeKg);
    final totalCardioDistance =
        cardioSets.fold<double>(0, (s, e) => s + e.distanceKm);
    final muscleGroups = <String>{
      for (final e in strengthSets) _muscleGroupFor(e.exerciseId) ?? '',
    }.where((g) => g.isNotEmpty).toList();

    return AppPanel(
      padding: const EdgeInsets.all(18),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_formatDate(session.date),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              ),
              GestureDetector(
                onTap: onDelete,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration:
                      const BoxDecoration(color: Color(0xFF1E1E24), shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, size: 13, color: kNeonRed),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (muscleGroups.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final g in muscleGroups)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                        color: kNeonViolet.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(g,
                        style: const TextStyle(
                            color: kNeonViolet, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
              ],
            )
          else if (cardioSets.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                  color: kNeonAmber.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
              child: const Text('Cardio',
                  style: TextStyle(color: kNeonAmber, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              _MiniStat(label: 'Durée', value: _fmtClock(session.durationSeconds)),
              Container(
                  width: 0.5, height: 28, color: const Color(0xFF333333),
                  margin: const EdgeInsets.symmetric(horizontal: 16)),
              _MiniStat(label: 'Blocs', value: '${sets.length}'),
              Container(
                  width: 0.5, height: 28, color: const Color(0xFF333333),
                  margin: const EdgeInsets.symmetric(horizontal: 16)),
              if (totalVolume > 0)
                _MiniStat(label: 'Volume', value: '${totalVolume.toStringAsFixed(0)} kg')
              else if (totalCardioDistance > 0)
                _MiniStat(label: 'Distance', value: '${totalCardioDistance.toStringAsFixed(1)} km')
              else if (session.hasHr)
                _MiniStat(label: 'FC moy.', value: '${session.avgHr.round()} bpm'),
            ],
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

  String _formatDate(DateTime date) {
    const months = [
      'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
      'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'
    ];
    final h = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '${date.day} ${months[date.month - 1]} ${date.year} · $h:$min';
  }

  String _fmtClock(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}';
    return '${m}m';
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
        Text(label, style: const TextStyle(fontSize: 11, color: kNeonViolet)),
      ],
    );
  }
}
