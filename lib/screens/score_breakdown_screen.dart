// lib/screens/score_breakdown_screen.dart
// Décomposition d'une "note" (Sommeil/Récup/Activité) : le score /100 reste
// affiché sur la carte du dashboard, mais ici on montre les données brutes
// qui le composent, avec un état "reçu/en attente" par donnée du jour — pour
// comprendre si le score est fiable ou calculé avec des données partielles.
import 'package:flutter/material.dart';
import '../models/daily_health_record.dart';
import '../models/health_snapshot.dart';
import '../services/health_score_service.dart';
import '../services/health_store.dart';
import '../theme.dart';
import '../widgets/health_charts.dart';
import 'health_metric_detail_screen.dart';

class ScoreBreakdownScreen extends StatelessWidget {
  final HealthMetric scoreMetric; // sleepScore | recoveryScore | activityScore
  final Color accent;
  final int scoreValue;
  final HealthSnapshot snapshot;

  const ScoreBreakdownScreen({
    super.key,
    required this.scoreMetric,
    required this.accent,
    required this.scoreValue,
    required this.snapshot,
  });

  String get _title => switch (scoreMetric) {
        HealthMetric.sleepScore => 'Score Sommeil',
        HealthMetric.recoveryScore => 'Score Récupération',
        HealthMetric.activityScore => 'Score Activité',
        _ => 'Score',
      };

  @override
  Widget build(BuildContext context) {
    final baseline = HealthStore.baseline(scoreMetric);
    final trend =
        HealthScoreService.trend(scoreMetric, scoreValue.toDouble(), baseline);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(
          _title.toUpperCase(),
          style: TextStyle(
            fontFamily: kArcadeFont,
            color: accent,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            shadows: [Shadow(color: accent, blurRadius: 10)],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              HealthRing(score: scoreValue, color: accent, size: 88),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$scoreValue/100',
                        style: TextStyle(
                          fontFamily: kArcadeFont,
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        )),
                    const SizedBox(height: 6),
                    TrendArrow(
                        dir: trend.dir, good: trend.good, label: '${trend.label} vs 7j'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (scoreMetric == HealthMetric.sleepScore)
            ..._buildSleepSection(context)
          else
            ..._buildComponentsSection(context),
        ],
      ),
    );
  }

  // ── Sommeil : la nuit est une seule source de données (une session) — les
  // 3 pondérations du score (durée/répartition/efficacité) en dérivent
  // toutes, donc un seul statut "reçu/en attente", pas trois lignes
  // redondantes. ────────────────────────────────────────────────────────────
  List<Widget> _buildSleepSection(BuildContext context) {
    final sleep = snapshot.sleep;
    final received = sleep.totalAsleepMin > 0;
    return [
      _DataStatusPanel(items: [
        _DataStatusItem(label: 'Session de sommeil', received: received),
      ]),
      const SizedBox(height: 16),
      _ComponentPanel(
        label: 'Durée de sommeil',
        metric: HealthMetric.sleepHours,
        accent: accent,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => HealthMetricDetailScreen(
                metric: HealthMetric.sleepHours, accent: accent),
          ),
        ),
      ),
      if (received && sleep.segments.isNotEmpty) ...[
        const SizedBox(height: 16),
        _Panel(
          accent: accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('CETTE NUIT',
                  style: TextStyle(
                      fontFamily: kArcadeFont,
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
              const SizedBox(height: 12),
              Hypnogram(segments: sleep.segments, height: 72, showAxis: true),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  SleepLegend('Profond', _fmtMin(sleep.deepMin), kNeonViolet),
                  SleepLegend('Paradoxal', _fmtMin(sleep.remMin), kNeonCyan),
                  SleepLegend(
                      'Léger', _fmtMin(sleep.lightMin), SleepStage.light.color),
                  SleepLegend('Éveil', _fmtMin(sleep.awakeMin), AppColors.muted),
                ],
              ),
            ],
          ),
        ),
      ],
    ];
  }

  // ── Récup / Activité : plusieurs signaux distincts, chacun avec son
  // propre statut et son propre historique. ──────────────────────────────────
  List<Widget> _buildComponentsSection(BuildContext context) {
    final components = switch (scoreMetric) {
      HealthMetric.recoveryScore => [
          _Component('FC au repos', 50, HealthMetric.restingHeartRate,
              snapshot.restingHeartRate),
          _Component('HRV', 50, HealthMetric.hrv, snapshot.hrv),
        ],
      HealthMetric.activityScore => [
          _Component(
              'Pas', 50, HealthMetric.steps, snapshot.steps.toDouble()),
          _Component('Calories actives', 35, HealthMetric.activeCalories,
              snapshot.activeCalories),
          _Component('Étages montés', 15, HealthMetric.flightsClimbed,
              snapshot.flightsClimbed.toDouble()),
        ],
      _ => const <_Component>[],
    };

    return [
      _DataStatusPanel(
        items: [
          for (final c in components)
            _DataStatusItem(
                label: '${c.label} (${c.weightPercent}%)', received: c.value > 0),
        ],
      ),
      for (final c in components) ...[
        const SizedBox(height: 16),
        _ComponentPanel(
          label: c.label,
          metric: c.metric,
          accent: accent,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  HealthMetricDetailScreen(metric: c.metric, accent: accent),
            ),
          ),
        ),
      ],
    ];
  }

  static String _fmtMin(double minutes) {
    final h = minutes ~/ 60;
    final m = (minutes % 60).round();
    return '${h}h${m.toString().padLeft(2, '0')}';
  }
}

class _Component {
  final String label;
  final int weightPercent;
  final HealthMetric metric;
  final double value;
  const _Component(this.label, this.weightPercent, this.metric, this.value);
}

/// "Données du jour : X/Y reçues" + une puce ✓/⏳ par entrée — pour juger si
/// le score du jour est calculé avec des données complètes.
class _DataStatusPanel extends StatelessWidget {
  final List<_DataStatusItem> items;
  const _DataStatusPanel({required this.items});

  @override
  Widget build(BuildContext context) {
    final receivedCount = items.where((i) => i.received).length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DONNÉES DU JOUR — $receivedCount/${items.length} REÇUES',
            style: const TextStyle(
                fontFamily: kArcadeFont,
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6),
          ),
          const SizedBox(height: 12),
          for (final item in items) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    item.received
                        ? Icons.check_circle_rounded
                        : Icons.hourglass_top_rounded,
                    color: item.received ? kNeonGreen : AppColors.muted,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(item.label,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 13)),
                  ),
                  Text(
                    item.received ? 'reçu' : 'en attente',
                    style: TextStyle(
                        color: item.received ? kNeonGreen : AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DataStatusItem {
  final String label;
  final bool received;
  const _DataStatusItem({required this.label, required this.received});
}

/// Graphe compact 7 jours d'une composante, tappable vers le détail complet
/// (7/30/90j) déjà fourni par `HealthMetricDetailScreen`.
class _ComponentPanel extends StatelessWidget {
  final String label;
  final HealthMetric metric;
  final Color accent;
  final VoidCallback onTap;
  const _ComponentPanel({
    required this.label,
    required this.metric,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final series = HealthStore.series(metric, 7)
        .where((e) => e.value > 0)
        .toList();
    final values = series.map((e) => e.value).toList();
    final dates = series.map((e) => e.key).toList();

    return GestureDetector(
      onTap: onTap,
      child: _Panel(
        accent: accent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label.toUpperCase(),
                      style: const TextStyle(
                          fontFamily: kArcadeFont,
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6)),
                ),
                Icon(Icons.chevron_right_rounded, color: accent, size: 18),
              ],
            ),
            const SizedBox(height: 10),
            if (values.length >= 2)
              TrendChart(values: values, color: accent, dates: dates, height: 120)
            else
              const SizedBox(
                height: 60,
                child: Center(
                  child: Text('Pas encore assez de jours pour une courbe.',
                      style:
                          TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  final Color accent;
  const _Panel({required this.child, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.4), width: 1.2),
      ),
      child: child,
    );
  }
}
