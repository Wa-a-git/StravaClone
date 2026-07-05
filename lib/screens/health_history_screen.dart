// lib/screens/health_history_screen.dart
// Historique santé : une fiche par jour, symétrique de HistoryScreen (Sport).
// Sert aussi de cible au deep-link `arcadehealth://sante/<date>` depuis Marble.
import 'package:flutter/material.dart';
import '../models/daily_health_record.dart';
import '../services/health_score_service.dart';
import '../services/health_store.dart';
import '../theme.dart';
import '../widgets/health_charts.dart';
import '../widgets/ui_kit.dart';

class HealthHistoryScreen extends StatelessWidget {
  const HealthHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final days = HealthStore.all().reversed.toList(); // plus récent d'abord

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text(
          'HISTORIQUE SANTÉ',
          style: TextStyle(
            fontFamily: kArcadeFont,
            color: kNeonCyan,
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            shadows: [Shadow(color: kNeonCyan, blurRadius: 10)],
          ),
        ),
      ),
      body: days.isEmpty
          ? const EmptyState(
              icon: Icons.favorite_border_rounded,
              title: 'Aucune journée enregistrée',
              subtitle: 'Reviens demain, ton historique se construit chaque jour.',
              accent: kNeonCyan,
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: days.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _DayRow(
                record: days[i],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HealthDayDetailScreen(record: days[i]),
                  ),
                ),
              ),
            ),
    );
  }
}

class _DayRow extends StatelessWidget {
  final DailyHealthRecord record;
  final VoidCallback onTap;
  const _DayRow({required this.record, required this.onTap});

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final tier = HealthScoreService.tierFor(record.bioScore);
    final h = record.totalSleepMin ~/ 60;
    final m = (record.totalSleepMin % 60).round();

    return AppPanel(
      accent: tier.color,
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          HealthRing(score: record.bioScore, color: tier.color, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_fmtDate(record.date),
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  '${record.steps} pas · sommeil ${h}h${m.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.textSecondary, size: 20),
        ],
      ),
    );
  }
}

/// Fiche santé d'un jour passé — lecture seule, même esprit visuel que le
/// dashboard santé du jour mais sans dépendance au provider live. Cible du
/// deep-link `arcadehealth://sante/<yyyy-MM-dd>` et de l'historique santé.
class HealthDayDetailScreen extends StatelessWidget {
  final DailyHealthRecord record;
  const HealthDayDetailScreen({super.key, required this.record});

  String _fmtDate(DateTime d) {
    const mois = [
      'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
      'août', 'septembre', 'octobre', 'novembre', 'décembre'
    ];
    return '${d.day} ${mois[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final tier = HealthScoreService.tierFor(record.bioScore);
    final h = record.totalSleepMin ~/ 60;
    final m = (record.totalSleepMin % 60).round();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(
          _fmtDate(record.date).toUpperCase(),
          style: TextStyle(
            fontFamily: kArcadeFont,
            color: tier.color,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
            shadows: [Shadow(color: tier.color, blurRadius: 10)],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppPanel(
            accent: tier.color,
            hero: true,
            child: Row(
              children: [
                HealthRing(
                    score: record.bioScore,
                    color: tier.color,
                    size: 96,
                    centerLabel: 'BIO'),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const PanelTitle('BIO-SCORE'),
                      const SizedBox(height: 6),
                      Text(
                        tier.name,
                        style: TextStyle(
                          fontFamily: kArcadeFont,
                          color: tier.color,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          shadows: [Shadow(color: tier.color, blurRadius: 10)],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _ScoreCard(
                      label: 'SOMMEIL', score: record.sleepScore, color: kNeonViolet)),
              const SizedBox(width: 10),
              Expanded(
                  child: _ScoreCard(
                      label: 'RÉCUP', score: record.recoveryScore, color: kNeonCyan)),
              const SizedBox(width: 10),
              Expanded(
                  child: _ScoreCard(
                      label: 'ACTIVITÉ', score: record.activityScore, color: kNeonGreen)),
            ],
          ),
          const SizedBox(height: 16),
          AppPanel(
            accent: kNeonViolet,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PanelTitle('SOMMEIL', color: kNeonViolet),
                const SizedBox(height: 12),
                if (record.totalSleepMin <= 0)
                  const Text('Aucune donnée de sommeil pour cette nuit.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12))
                else ...[
                  Text('${h}h${m.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                          fontFamily: kArcadeFont,
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900)),
                  if (record.sleepSegments.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Hypnogram(segments: record.sleepSegments, height: 90),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppPanel(
            accent: kNeonCyan,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PanelTitle('INDICATEURS'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _Stat('Pas', record.steps.toString(), kNeonGreen),
                    _Stat('Distance', '${record.distanceKm.toStringAsFixed(2)} km', kNeonGreen),
                    _Stat('Cal. actives', '${record.activeCalories.toStringAsFixed(0)} kcal', kNeonPink),
                    if (record.restingHeartRate > 0)
                      _Stat('FC repos', '${record.restingHeartRate.round()} bpm', kNeonCyan),
                    if (record.hrv > 0)
                      _Stat('HRV', '${record.hrv.round()} ms', kNeonCyan),
                    if (record.spo2 > 0)
                      _Stat('SpO2', '${record.spo2.round()}%', kNeonViolet),
                    if (record.vo2Max > 0)
                      _Stat('VO2 max', record.vo2Max.toStringAsFixed(1), kNeonGreen),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final String label;
  final int score;
  final Color color;
  const _ScoreCard({required this.label, required this.score, required this.color});

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      accent: color,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Column(
        children: [
          HealthRing(score: score, color: color, size: 52),
          const SizedBox(height: 8),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Stat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontFamily: kArcadeFont,
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
          Text(label,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
        ],
      ),
    );
  }
}
