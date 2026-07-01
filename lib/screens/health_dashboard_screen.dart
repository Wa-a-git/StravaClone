import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/daily_health_record.dart';
import '../models/health_snapshot.dart';
import '../providers/health_provider.dart';
import '../providers/game_provider.dart';
import '../services/game_service.dart';
import '../services/health_game_service.dart';
import '../services/health_score_service.dart';
import '../services/health_store.dart';
import '../theme.dart';
import '../widgets/arcade_fx.dart';
import '../widgets/health_charts.dart';
import '../widgets/system_window.dart';
import 'shell_screen.dart';
import 'health_metric_detail_screen.dart';

class HealthDashboardScreen extends ConsumerWidget {
  const HealthDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(healthDataProvider);
    final scores = st.scores;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            backgroundColor: AppColors.surface,
            elevation: 0,
            flexibleSpace: const FlexibleSpaceBar(
              titlePadding: EdgeInsets.only(left: 20, bottom: 16),
              title: Text(
                'SANTÉ & CORPS',
                style: TextStyle(
                  fontFamily: kArcadeFont,
                  color: AppColors.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                  shadows: [Shadow(color: AppColors.arcadeCyan, blurRadius: 12)],
                ),
              ),
              expandedTitleScale: 1.0,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded,
                    color: AppColors.arcadeCyan),
                onPressed: () =>
                    ref.read(healthDataProvider.notifier).fetchDailyData(),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 20),
                  if (st.isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(
                          child: CircularProgressIndicator(
                              color: AppColors.arcadeCyan)),
                    )
                  else if (!st.hasPermission || scores == null)
                    _PermissionWarning(
                      onTap: () => ref
                          .read(healthDataProvider.notifier)
                          .fetchDailyData(),
                    )
                  else ...[
                    _BioScorePanel(scores: scores, insights: st.insights),
                    const SizedBox(height: 16),
                    _SubScoresRow(scores: scores),
                    const SizedBox(height: 16),
                    _HealthXpBanner(
                      xpToday: st.healthXpToday,
                      onTap: () => ref
                          .read(shellIndexProvider.notifier)
                          .state = 3,
                    ),
                    const SizedBox(height: 16),
                    _MetricsGrid(snapshot: st.snapshot),
                    const SizedBox(height: 16),
                    _SleepPanel(
                        sleep: st.snapshot.sleep, score: scores.sleepScore),
                    const SizedBox(height: 16),
                    if (st.stepsStreak > 0 || st.sleepStreak > 0) ...[
                      _StreaksRow(
                          stepsStreak: st.stepsStreak,
                          sleepStreak: st.sleepStreak),
                      const SizedBox(height: 16),
                    ],
                    _InsightsPanel(insights: st.insights),
                    const SizedBox(height: 16),
                    _buildQuestPanels(context, ref, st),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text('Données Fitbit',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        SizedBox(height: 8),
        Text(
          'Aptitude du Jour',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.1,
          ),
        ),
      ],
    );
  }

  Widget _buildQuestPanels(
      BuildContext context, WidgetRef ref, HealthDataState st) {
    final now = DateTime.now();
    final today = HealthStore.recordFor(now);
    final weekStart = GameService.startOfWeek(now);
    final weekRecords =
        st.history.where((r) => !r.date.isBefore(weekStart)).toList();
    final dayKey = GameService.dayKey(now);
    final weekKey = GameService.weekKey(now);

    return Column(
      children: [
        _HealthQuestsPanel(
          title: 'QUÊTES SANTÉ — JOUR',
          accent: kNeonGreen,
          quests: HealthQuestService.daily(now),
          today: today,
          weekRecords: weekRecords,
          keyPrefix: dayKey,
          onClaim: (q) => _claim(context, ref, dayKey, q),
        ),
        const SizedBox(height: 16),
        _HealthQuestsPanel(
          title: 'QUÊTES SANTÉ — SEMAINE',
          accent: kNeonPink,
          quests: HealthQuestService.weekly(now),
          today: today,
          weekRecords: weekRecords,
          keyPrefix: weekKey,
          onClaim: (q) => _claim(context, ref, weekKey, q),
        ),
      ],
    );
  }

  Future<void> _claim(BuildContext context, WidgetRef ref, String keyPrefix,
      HealthQuestDef q) async {
    final uid = 'hq:$keyPrefix:${q.id}';
    final added = await GameStore.claim(uid, q.reward);
    if (added <= 0) return;
    ref.read(questBonusProvider.notifier).state = GameStore.questBonusXp;
    HapticFeedback.mediumImpact();
    if (context.mounted) {
      await showSystemWindow(
        context,
        heading: 'QUÊTE SANTÉ',
        lines: [q.title, '+$added XP'],
        accent: kNeonGreen,
      );
    }
  }
}

// ── Avertissement permission ──────────────────────────────────────────────────
class _PermissionWarning extends StatelessWidget {
  final VoidCallback onTap;
  const _PermissionWarning({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.arcadePink),
      ),
      child: Column(
        children: [
          const Icon(Icons.health_and_safety,
              size: 48, color: AppColors.arcadePink),
          const SizedBox(height: 16),
          const Text('Health Connect Requis',
              style: TextStyle(
                  fontFamily: kArcadeFont, fontSize: 16, color: Colors.white)),
          const SizedBox(height: 8),
          const Text(
            'Autorisez l\'accès aux données pour synchroniser votre Fitbit.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.arcadeCyan),
            onPressed: onTap,
            child: const Text('Autoriser l\'accès',
                style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }
}

// ── Héros Bio-Score ───────────────────────────────────────────────────────────
class _BioScorePanel extends StatelessWidget {
  final HealthScores scores;
  final List<HealthInsight> insights;
  const _BioScorePanel({required this.scores, required this.insights});

  @override
  Widget build(BuildContext context) {
    final tier = scores.tier;
    final bioTrend = HealthScoreService.trend(
      HealthMetric.bioScore,
      scores.bioScore.toDouble(),
      HealthStore.baseline(HealthMetric.bioScore),
    );
    final topInsight = insights.isNotEmpty ? insights.first : null;

    return _HPanel(
      accent: tier.color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HealthRing(
                  score: scores.bioScore,
                  color: tier.color,
                  size: 104,
                  centerLabel: 'BIO'),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _HPanelTitle('BIO-SCORE'),
                    const SizedBox(height: 6),
                    Text(
                      tier.name,
                      style: TextStyle(
                        fontFamily: kArcadeFont,
                        color: tier.color,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        shadows: [Shadow(color: tier.color, blurRadius: 10)],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        TrendArrow(
                          dir: bioTrend.dir,
                          good: bioTrend.good,
                          label: '${bioTrend.label} vs 7j',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (topInsight != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: topInsight.color.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  Icon(topInsight.icon, color: topInsight.color, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(topInsight.text,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 12)),
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

// ── Sous-scores (tappables) ───────────────────────────────────────────────────
class _SubScoresRow extends StatelessWidget {
  final HealthScores scores;
  const _SubScoresRow({required this.scores});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SubScoreCard(
            label: 'SOMMEIL',
            score: scores.sleepScore,
            color: kNeonViolet,
            metric: HealthMetric.sleepScore,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SubScoreCard(
            label: 'RÉCUP',
            score: scores.recoveryScore,
            color: kNeonCyan,
            metric: HealthMetric.recoveryScore,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SubScoreCard(
            label: 'ACTIVITÉ',
            score: scores.activityScore,
            color: kNeonGreen,
            metric: HealthMetric.activityScore,
          ),
        ),
      ],
    );
  }
}

class _SubScoreCard extends StatelessWidget {
  final String label;
  final int score;
  final Color color;
  final HealthMetric metric;
  const _SubScoreCard({
    required this.label,
    required this.score,
    required this.color,
    required this.metric,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              HealthMetricDetailScreen(metric: metric, accent: color),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Column(
          children: [
            HealthRing(score: score, color: color, size: 56),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bandeau XP santé (lien vers l'onglet Niveau) ──────────────────────────────
class _HealthXpBanner extends StatelessWidget {
  final int xpToday;
  final VoidCallback onTap;
  const _HealthXpBanner({required this.xpToday, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: [
              kNeonPink.withOpacity(0.18),
              kNeonCyan.withOpacity(0.12),
            ],
          ),
          border: Border.all(color: kNeonPink.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.bolt_rounded, color: kNeonPink, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'XP SANTÉ AUJOURD\'HUI',
                    style: TextStyle(
                      fontFamily: kArcadeFont,
                      color: kNeonPink,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Ta santé fait monter ton niveau. Voir ta progression →',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('+',
                    style: TextStyle(
                        fontFamily: kArcadeFont,
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900)),
                AnimatedCounter(
                  value: xpToday.toDouble(),
                  style: const TextStyle(
                    fontFamily: kArcadeFont,
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 3, left: 2),
                  child: Text('XP',
                      style: TextStyle(
                          color: kNeonPink,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Grille de métriques avec sparklines + tendances ───────────────────────────
class _MetricsGrid extends StatelessWidget {
  final HealthSnapshot snapshot;
  const _MetricsGrid({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final metrics = <_MetricSpec>[
      _MetricSpec('Pas', HealthMetric.steps, snapshot.steps.toString(), 'pas',
          Icons.directions_walk_rounded, kNeonGreen),
      _MetricSpec(
          'Distance',
          HealthMetric.distanceKm,
          snapshot.distanceKm.toStringAsFixed(2),
          'km',
          Icons.map_rounded,
          kNeonGreen),
      _MetricSpec(
          'Cal. actives',
          HealthMetric.activeCalories,
          snapshot.activeCalories.toStringAsFixed(0),
          'kcal',
          Icons.local_fire_department_rounded,
          kNeonPink),
      _MetricSpec(
          'FC repos',
          HealthMetric.restingHeartRate,
          snapshot.restingHeartRate > 0
              ? snapshot.restingHeartRate.toStringAsFixed(0)
              : '--',
          'bpm',
          Icons.favorite_border_rounded,
          kNeonCyan),
      _MetricSpec(
          'HRV',
          HealthMetric.hrv,
          snapshot.hrv > 0 ? snapshot.hrv.toStringAsFixed(0) : '--',
          'ms',
          Icons.monitor_heart_rounded,
          kNeonCyan),
      _MetricSpec(
          'SpO2',
          HealthMetric.spo2,
          snapshot.spo2 > 0 ? snapshot.spo2.toStringAsFixed(0) : '--',
          '%',
          Icons.bloodtype_rounded,
          kNeonViolet),
      _MetricSpec(
          'Respiration',
          HealthMetric.respiratoryRate,
          snapshot.respiratoryRate > 0
              ? snapshot.respiratoryRate.toStringAsFixed(1)
              : '--',
          'rpm',
          Icons.air_rounded,
          kNeonViolet),
      _MetricSpec(
          'Étages',
          HealthMetric.flightsClimbed,
          snapshot.flightsClimbed.toString(),
          'étages',
          Icons.stairs_rounded,
          const Color(0xFFFFC107)),
    ];

    return _HPanel(
      accent: kNeonCyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _HPanelTitle('MÉTRIQUES & TENDANCES'),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: metrics
                .map((m) => SizedBox(
                      width: (MediaQuery.of(context).size.width - 32 - 36 - 10) /
                          2,
                      child: _MetricCard(spec: m),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _MetricSpec {
  final String title;
  final HealthMetric metric;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  _MetricSpec(this.title, this.metric, this.value, this.unit, this.icon,
      this.color);
}

class _MetricCard extends StatelessWidget {
  final _MetricSpec spec;
  const _MetricCard({required this.spec});

  @override
  Widget build(BuildContext context) {
    final series = HealthStore.series(spec.metric, 7)
        .map((e) => e.value)
        .where((v) => v > 0)
        .toList();
    final current =
        series.isNotEmpty ? series.last : 0.0;
    final baseline = HealthStore.baseline(spec.metric);
    final trend = HealthScoreService.trend(
      spec.metric,
      current,
      baseline,
      unit: '',
      fractionDigits:
          spec.metric == HealthMetric.distanceKm ? 1 : 0,
    );

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HealthMetricDetailScreen(
              metric: spec.metric, accent: spec.color),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: spec.color.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(spec.icon, color: spec.color, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    spec.title.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TrendArrow(dir: trend.dir, good: trend.good),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  spec.value,
                  style: const TextStyle(
                    fontFamily: kArcadeFont,
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(spec.unit,
                      style: TextStyle(
                          color: spec.color,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Sparkline(values: series, color: spec.color, height: 28),
          ],
        ),
      ),
    );
  }
}

// ── Panneau sommeil ───────────────────────────────────────────────────────────
class _SleepPanel extends StatelessWidget {
  final SleepBreakdown sleep;
  final int score;
  const _SleepPanel({required this.sleep, required this.score});

  String _fmt(double minutes) {
    final h = minutes ~/ 60;
    final m = (minutes % 60).round();
    return '${h}h${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final total = sleep.totalAsleepMin;
    return _HPanel(
      accent: kNeonViolet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const _HPanelTitle('SOMMEIL', color: kNeonViolet),
              Text('Score $score/100',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 12),
          if (total <= 0)
            const Text('Aucune donnée de sommeil trouvée pour cette nuit.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12))
          else ...[
            Text(_fmt(total),
                style: const TextStyle(
                    fontFamily: kArcadeFont,
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900)),
            Text('Efficacité : ${sleep.efficiency.toStringAsFixed(0)}%',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 16,
                child: Row(
                  children: [
                    if (sleep.deepMin > 0)
                      Expanded(
                          flex: (sleep.deepMin * 100).round().clamp(1, 1000000),
                          child: Container(color: kNeonViolet)),
                    if (sleep.remMin > 0)
                      Expanded(
                          flex: (sleep.remMin * 100).round().clamp(1, 1000000),
                          child: Container(color: kNeonCyan)),
                    if (sleep.lightMin > 0)
                      Expanded(
                          flex:
                              (sleep.lightMin * 100).round().clamp(1, 1000000),
                          child: Container(
                              color: AppColors.arcadeViolet.withOpacity(0.35))),
                    if (sleep.awakeMin > 0)
                      Expanded(
                          flex:
                              (sleep.awakeMin * 100).round().clamp(1, 1000000),
                          child: Container(color: AppColors.muted)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _SleepLegend('Profond', _fmt(sleep.deepMin), kNeonViolet),
                _SleepLegend('Paradoxal', _fmt(sleep.remMin), kNeonCyan),
                _SleepLegend('Léger', _fmt(sleep.lightMin), AppColors.arcadeViolet),
                _SleepLegend('Éveil', _fmt(sleep.awakeMin), AppColors.muted),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SleepLegend extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SleepLegend(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$label $value',
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      ],
    );
  }
}

// ── Insights & streaks ────────────────────────────────────────────────────────
class _InsightsPanel extends StatelessWidget {
  final List<HealthInsight> insights;
  const _InsightsPanel({required this.insights});

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) return const SizedBox.shrink();
    return _HPanel(
      accent: kNeonGreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _HPanelTitle('ANALYSE', color: kNeonGreen),
          const SizedBox(height: 12),
          ...insights.map((ins) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(ins.icon, color: ins.color, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(ins.text,
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 12.5)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// ── Streaks (séries en cours) ─────────────────────────────────────────────────
class _StreaksRow extends StatelessWidget {
  final int stepsStreak;
  final int sleepStreak;
  const _StreaksRow({required this.stepsStreak, required this.sleepStreak});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if (sleepStreak > 0) {
      chips.add(_StreakChip(
        label: 'Sommeil ≥ 7 h',
        days: sleepStreak,
        color: kNeonViolet,
      ));
    }
    if (stepsStreak > 0) {
      chips.add(_StreakChip(
        label: '10k pas',
        days: stepsStreak,
        color: kNeonGreen,
      ));
    }
    return Row(
      children: [
        for (int i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: chips[i]),
        ],
      ],
    );
  }
}

class _StreakChip extends StatelessWidget {
  final String label;
  final int days;
  final Color color;
  const _StreakChip(
      {required this.label, required this.days, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_fire_department_rounded,
              color: Color(0xFFFFC107), size: 22),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$days',
                      style: TextStyle(
                          fontFamily: kArcadeFont,
                          color: color,
                          fontSize: 20,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(width: 3),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 3),
                    child: Text('j',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 11)),
                  ),
                ],
              ),
              Text(label,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Panneau de quêtes santé (réclamables → XP pool commun) ────────────────────
class _HealthQuestsPanel extends StatelessWidget {
  final String title;
  final Color accent;
  final List<HealthQuestDef> quests;
  final DailyHealthRecord? today;
  final List<DailyHealthRecord> weekRecords;
  final String keyPrefix;
  final void Function(HealthQuestDef) onClaim;

  const _HealthQuestsPanel({
    required this.title,
    required this.accent,
    required this.quests,
    required this.today,
    required this.weekRecords,
    required this.keyPrefix,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    return _HPanel(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HPanelTitle(title, color: accent),
          const SizedBox(height: 14),
          ...quests.map((q) {
            final current = HealthQuestService.current(q, today, weekRecords);
            final claimed = GameStore.isClaimed('hq:$keyPrefix:${q.id}');
            final progress = HealthQuestProgress(
                def: q, current: current, claimed: claimed);
            return _HealthQuestTile(
                progress: progress, accent: accent, onClaim: () => onClaim(q));
          }),
        ],
      ),
    );
  }
}

class _HealthQuestTile extends StatelessWidget {
  final HealthQuestProgress progress;
  final Color accent;
  final VoidCallback onClaim;
  const _HealthQuestTile(
      {required this.progress, required this.accent, required this.onClaim});

  @override
  Widget build(BuildContext context) {
    final q = progress.def;
    final fmt = q.unit == 'h'
        ? progress.current.toStringAsFixed(1)
        : progress.current.toStringAsFixed(0);
    final tgt = q.target.toStringAsFixed(0);
    final canClaim = progress.completed && !progress.claimed;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: progress.claimed
              ? AppColors.border
              : (progress.completed ? accent : AppColors.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                progress.claimed
                    ? Icons.check_circle_rounded
                    : (progress.completed
                        ? Icons.emoji_events_rounded
                        : Icons.radio_button_unchecked_rounded),
                color: progress.claimed
                    ? kNeonGreen
                    : (progress.completed
                        ? const Color(0xFFFFC107)
                        : AppColors.textSecondary),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  q.title,
                  style: TextStyle(
                    color:
                        progress.claimed ? AppColors.textSecondary : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    decoration:
                        progress.claimed ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              Text('+${q.reward}',
                  style: TextStyle(
                      fontFamily: kArcadeFont,
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    children: [
                      Container(height: 8, color: AppColors.surfaceLight),
                      FractionallySizedBox(
                        widthFactor: progress.ratio,
                        child: Container(height: 8, color: accent),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('$fmt / $tgt ${q.unit}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
            ],
          ),
          if (canClaim) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 38,
              child: ElevatedButton(
                onPressed: onClaim,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'RÉCLAMER LA RÉCOMPENSE',
                  style: TextStyle(
                    fontFamily: kArcadeFont,
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Cadre de panneau réutilisable ─────────────────────────────────────────────
class _HPanel extends StatelessWidget {
  final Widget child;
  final Color accent;
  const _HPanel({required this.child, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.45), width: 1.2),
        boxShadow: [BoxShadow(color: accent.withOpacity(0.12), blurRadius: 16)],
      ),
      child: child,
    );
  }
}

class _HPanelTitle extends StatelessWidget {
  final String text;
  final Color color;
  const _HPanelTitle(this.text, {this.color = kNeonCyan});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: kArcadeFont,
        color: color,
        fontSize: 13,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.5,
        shadows: [Shadow(color: color.withOpacity(0.8), blurRadius: 8)],
      ),
    );
  }
}
