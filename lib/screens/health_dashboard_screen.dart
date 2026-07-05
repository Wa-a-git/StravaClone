import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/activity.dart';
import '../models/daily_health_record.dart';
import '../models/health_snapshot.dart';
import '../providers/activity_provider.dart';
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
import '../widgets/ui_kit.dart';
import 'shell_screen.dart';
import 'health_history_screen.dart';
import 'health_metric_detail_screen.dart';
import 'sleep_detail_screen.dart';
import 'detail_screen.dart';

class HealthDashboardScreen extends ConsumerWidget {
  const HealthDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(healthDataProvider);
    final scores = st.scores;

    // Courses GPS enregistrées aujourd'hui (pour le feed "Activité suivie").
    final now = DateTime.now();
    final todayRuns = ref
        .watch(activityListProvider)
        .where((a) =>
            a.date.year == now.year &&
            a.date.month == now.month &&
            a.date.day == now.day)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

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
                    if (_wearableDataMissing(st.snapshot)) ...[
                      _SyncHintBanner(
                        onRefresh: () => ref
                            .read(healthDataProvider.notifier)
                            .fetchDailyData(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    // ── CADRAN : résumé du jour en un coup d'œil, pas de
                    // narratif ici — juste les chiffres, comme un tableau de
                    // bord (inspiré de l'onglet "Aujourd'hui" de Fitbit). ──
                    FadeSlideIn(child: _BioScorePanel(scores: scores)),
                    const SizedBox(height: 14),
                    _WeekDotsStrip(history: st.history),
                    const SizedBox(height: 14),
                    _SubScoresRow(scores: scores),
                    const SizedBox(height: 12),
                    _MetricsGrid(snapshot: st.snapshot),
                    const SizedBox(height: 12),
                    _HealthXpBanner(
                      xpToday: st.healthXpToday,
                      onTap: () => ref
                          .read(shellIndexProvider.notifier)
                          .state = 2,
                    ),
                    const SizedBox(height: 28),

                    // ── FEED : narratif chronologique de la journée ──
                    _FeedHeader(
                      time: _wakeLabel(st.snapshot.sleep) ?? 'CETTE NUIT',
                      title: 'Sommeil',
                      accent: kNeonViolet,
                    ),
                    const _FeedConnector(color: kNeonViolet),
                    FadeSlideIn(
                      child: _SleepPanel(
                          sleep: st.snapshot.sleep, score: scores.sleepScore),
                    ),
                    if (st.stepsStreak > 0 || st.sleepStreak > 0) ...[
                      const SizedBox(height: 12),
                      _StreaksRow(
                          stepsStreak: st.stepsStreak,
                          sleepStreak: st.sleepStreak),
                    ],
                    const SizedBox(height: 24),

                    // Courses GPS du jour, si tu en as enregistré.
                    if (todayRuns.isNotEmpty) ...[
                      _FeedHeader(
                        time: _timeLabel(todayRuns.first.date),
                        title: todayRuns.length > 1
                            ? '${todayRuns.length} activités suivies'
                            : 'Activité suivie',
                        accent: kNeonPink,
                      ),
                      const _FeedConnector(color: kNeonPink),
                      for (final run in todayRuns) ...[
                        _ActivityFeedCard(
                          activity: run,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => DetailScreen(activity: run)),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 14),
                    ],

                    const _FeedHeader(time: 'ANALYSE', title: 'Recommandations', accent: kNeonGreen),
                    const _FeedConnector(color: kNeonGreen),
                    _InsightsPanel(
                      insights: st.insights,
                      onFeedback: () =>
                          ref.read(healthDataProvider.notifier).refreshInsights(),
                    ),
                    const SizedBox(height: 24),

                    _buildQuestPanels(context, ref, st),
                    const SizedBox(height: 20),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const HealthHistoryScreen()),
                        ),
                        child: const Text('Voir tout l\'historique santé →'),
                      ),
                    ),
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
    return const PageHeading(eyebrow: 'Données Fitbit', title: 'Aptitude du Jour');
  }

  /// Heure de réveil formatée (HH:mm) pour l'en-tête de feed du sommeil.
  static String? _wakeLabel(SleepBreakdown sleep) {
    final w = sleep.wakeTime;
    if (w == null) return null;
    return '${w.hour.toString().padLeft(2, '0')}:${w.minute.toString().padLeft(2, '0')}';
  }

  /// Heure (HH:mm) d'un événement pour l'en-tête de feed.
  static String _timeLabel(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

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

/// Heuristique : si aucune donnée « montre » (FC repos, HRV, SpO2, sommeil)
/// n'est présente, c'est que le bracelet ne synchronise pas encore vers Health
/// Connect (on ne voit que les pas du téléphone).
bool _wearableDataMissing(HealthSnapshot s) {
  return s.restingHeartRate <= 0 &&
      s.hrv <= 0 &&
      s.spo2 <= 0 &&
      s.sleep.totalAsleepMin <= 0;
}

// ── Bannière d'aide à la synchro ──────────────────────────────────────────────
class _SyncHintBanner extends StatelessWidget {
  final VoidCallback onRefresh;
  const _SyncHintBanner({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFFFC107);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppColors.surface,
        border: Border.all(color: amber.withOpacity(0.55), width: 1.2),
        boxShadow: [BoxShadow(color: amber.withOpacity(0.10), blurRadius: 16)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.watch_rounded, color: amber, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'EN ATTENTE DE TA CHARGE 6',
                  style: TextStyle(
                    fontFamily: kArcadeFont,
                    color: amber,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Seuls les pas du téléphone remontent pour l\'instant. Pour débloquer '
            'la fréquence cardiaque, le sommeil, la HRV et la SpO2, active le '
            'partage vers Health Connect dans l\'app Fitbit, puis synchronise ta montre.',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 12.5, height: 1.45),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRefresh,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: amber,
                    side: BorderSide(color: amber.withOpacity(0.6)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Réessayer la synchro',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
  const _BioScorePanel({required this.scores});

  @override
  Widget build(BuildContext context) {
    final tier = scores.tier;
    final bioTrend = HealthScoreService.trend(
      HealthMetric.bioScore,
      scores.bioScore.toDouble(),
      HealthStore.baseline(HealthMetric.bioScore),
    );

    return _HPanel(
      accent: tier.color,
      hero: true,
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
        ],
      ),
    );
  }
}

// ── Bandeau hebdo : 7 points (L-D), rempli si l'objectif de pas du jour est
// atteint. Uniquement le fait (atteint/pas atteint), avec le chiffre réel en
// légende — pas de verdict, juste "combien de jours" cette semaine. ──────────
class _WeekDotsStrip extends StatelessWidget {
  final List<DailyHealthRecord> history;
  const _WeekDotsStrip({required this.history});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = GameService.startOfWeek(now);
    final byKey = {for (final r in history) r.key: r};
    const labels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final active = days
        .map((d) =>
            (byKey[DailyHealthRecord.keyFor(d)]?.steps ?? 0) >=
            HealthGameService.stepsGoal)
        .toList();
    final activeCount = active.where((a) => a).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$activeCount jour${activeCount > 1 ? 's' : ''} ≥ 10 000 pas cette semaine',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(7, (i) {
            final isFuture = days[i].isAfter(today);
            final isActive = active[i];
            return Expanded(
              child: Column(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive ? kNeonGreen : AppColors.surfaceLight,
                      border: Border.all(
                          color: isActive ? kNeonGreen : AppColors.border),
                    ),
                    child: isActive
                        ? const Icon(Icons.directions_walk_rounded,
                            size: 13, color: Colors.black)
                        : null,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    labels[i],
                    style: TextStyle(
                        fontSize: 10,
                        color: isFuture
                            ? AppColors.muted
                            : AppColors.textSecondary),
                  ),
                ],
              ),
            );
          }),
        ),
      ],
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
List<_MetricSpec> _allMetricSpecs(HealthSnapshot snapshot) => [
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
      // VO2 max / Poids : sources premium ou peu fréquentes, affichées
      // seulement s'il y a une valeur réelle (pas de carte "--" pour une
      // donnée jamais connectée).
      if (snapshot.vo2Max > 0)
        _MetricSpec(
            'VO2 max',
            HealthMetric.vo2Max,
            snapshot.vo2Max.toStringAsFixed(1),
            'ml/kg/min',
            Icons.speed_rounded,
            kNeonGreen),
      if (snapshot.weightKg > 0)
        _MetricSpec(
            'Poids',
            HealthMetric.weightKg,
            snapshot.weightKg.toStringAsFixed(1),
            'kg',
            Icons.monitor_weight_rounded,
            kNeonAmber),
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

class _MetricsGrid extends StatefulWidget {
  final HealthSnapshot snapshot;
  const _MetricsGrid({required this.snapshot});

  @override
  State<_MetricsGrid> createState() => _MetricsGridState();
}

class _MetricsGridState extends State<_MetricsGrid> {
  @override
  Widget build(BuildContext context) {
    final all = _allMetricSpecs(widget.snapshot);
    final visible =
        all.where((m) => !MetricsPreferenceStore.isHidden(m.metric)).toList();

    return _HPanel(
      accent: kNeonCyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HPanelTitle(
            'MÉTRIQUES & TENDANCES',
            trailing: GestureDetector(
              onTap: () => _openCustomize(context, all),
              behavior: HitTestBehavior.opaque,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune_rounded, size: 14, color: AppColors.textSecondary),
                  SizedBox(width: 4),
                  Text('Personnaliser',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Toutes les métriques sont masquées.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 10.0;
                // 2 colonnes fiables : on retire une marge de sécurité pour
                // éviter que l'arrondi ne fasse déborder sur une 3e « ligne ».
                final cardW = (constraints.maxWidth - spacing) / 2 - 0.5;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: visible
                      .map((m) => SizedBox(
                            width: cardW,
                            child: _MetricCard(spec: m),
                          ))
                      .toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _openCustomize(BuildContext context, List<_MetricSpec> all) async {
    await showAppSheet(context: context, child: _MetricsCustomizeSheet(specs: all));
    if (mounted) setState(() {});
  }
}

// ── Feuille "Personnaliser" : masque/affiche des cartes de la grille ─────────
class _MetricsCustomizeSheet extends StatefulWidget {
  final List<_MetricSpec> specs;
  const _MetricsCustomizeSheet({required this.specs});

  @override
  State<_MetricsCustomizeSheet> createState() => _MetricsCustomizeSheetState();
}

class _MetricsCustomizeSheetState extends State<_MetricsCustomizeSheet> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PERSONNALISER',
          style: TextStyle(
              fontFamily: kArcadeFont,
              color: kNeonCyan,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 1),
        ),
        const SizedBox(height: 4),
        const Text('Choisis les cartes affichées dans le dashboard.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 10),
        for (final spec in widget.specs)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(spec.title,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
            activeThumbColor: spec.color,
            value: !MetricsPreferenceStore.isHidden(spec.metric),
            onChanged: (v) {
              MetricsPreferenceStore.setHidden(spec.metric, !v);
              setState(() {});
            },
          ),
      ],
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
    final noData = spec.value == '--';
    final series = HealthStore.series(spec.metric, 7)
        .map((e) => e.value)
        .where((v) => v > 0)
        .toList();
    final current = series.isNotEmpty ? series.last : 0.0;
    final baseline = HealthStore.baseline(spec.metric);
    final trend = HealthScoreService.trend(
      spec.metric,
      current,
      baseline,
      unit: '',
      fractionDigits: spec.metric == HealthMetric.distanceKm ? 1 : 0,
    );

    // Carte « en attente » : couleurs atténuées pour ne pas ressembler à un bug.
    final accent = noData ? AppColors.muted : spec.color;
    final valueColor = noData ? AppColors.muted : Colors.white;

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
          border: Border.all(
              color: noData
                  ? AppColors.border
                  : spec.color.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(spec.icon, color: accent, size: 14),
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
                // Poids exclu : une hausse/baisse n'est ni bonne ni mauvaise
                // dans l'absolu (dépend de l'objectif de chacun) — la flèche
                // colorée serait un verdict qu'on n'a pas les moyens d'affirmer.
                if (!noData && spec.metric != HealthMetric.weightKg)
                  TrendArrow(dir: trend.dir, good: trend.good),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  spec.value,
                  style: TextStyle(
                    fontFamily: kArcadeFont,
                    color: valueColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(spec.unit,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: accent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            if (noData) ...[
              const SizedBox(height: 4),
              const Text('en attente',
                  style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 9,
                      fontStyle: FontStyle.italic)),
            ]
            // Sparkline seulement s'il y a un historique à tracer.
            else if (series.length >= 2) ...[
              const SizedBox(height: 6),
              Sparkline(values: series, color: spec.color, height: 28),
            ],
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
    final hasSegments = sleep.segments.isNotEmpty;
    return _HPanel(
      accent: kNeonViolet,
      child: InkWell(
        onTap: total > 0
            ? () {
                HapticFeedback.selectionClick();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SleepDetailScreen()),
                );
              }
            : null,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _HPanelTitle('SOMMEIL', color: kNeonViolet),
                Row(
                  children: [
                    Text('Score $score/100',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11)),
                    if (total > 0) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right_rounded,
                          color: kNeonViolet, size: 18),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (total <= 0)
              const Text('Aucune donnée de sommeil trouvée pour cette nuit.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12))
            else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_fmt(total),
                      style: const TextStyle(
                          fontFamily: kArcadeFont,
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('Efficacité ${sleep.efficiency.toStringAsFixed(0)}%',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Hypnogramme si on a le détail chronologique, sinon la barre
              // empilée classique (compat. anciens enregistrements).
              if (hasSegments)
                Hypnogram(segments: sleep.segments, height: 96, showAxis: true)
              else
                _stackedBar(),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  _SleepLegend('Profond', _fmt(sleep.deepMin), kNeonViolet),
                  _SleepLegend('Paradoxal', _fmt(sleep.remMin), kNeonCyan),
                  _SleepLegend('Léger', _fmt(sleep.lightMin), SleepStage.light.color),
                  _SleepLegend('Éveil', _fmt(sleep.awakeMin), AppColors.muted),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stackedBar() {
    return ClipRRect(
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
                  flex: (sleep.lightMin * 100).round().clamp(1, 1000000),
                  child: Container(color: SleepStage.light.color)),
            if (sleep.awakeMin > 0)
              Expanded(
                  flex: (sleep.awakeMin * 100).round().clamp(1, 1000000),
                  child: Container(color: AppColors.muted)),
          ],
        ),
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

// ── Connecteur vertical discret entre la pastille d'un en-tête de feed et son
// panneau — donne un vrai fil chronologique au lieu de blocs isolés.
class _FeedConnector extends StatelessWidget {
  final Color color;
  const _FeedConnector({required this.color});

  @override
  Widget build(BuildContext context) {
    // La colonne parente est en CrossAxisAlignment.stretch (pour que les
    // panneaux prennent toute la largeur) : sans Align, ce Container hériterait
    // des contraintes strictes et s'étirerait sur toute la largeur au lieu de
    // rester un fin trait vertical sous la pastille.
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 3.5),
        child: Container(width: 1.5, height: 14, color: color.withOpacity(0.35)),
      ),
    );
  }
}

// ── En-tête de section « feed » (pastille + heure + titre) ────────────────────
class _FeedHeader extends StatelessWidget {
  final String time;
  final String title;
  final Color accent;
  const _FeedHeader({required this.time, required this.title, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: accent,
            shape: BoxShape.circle,
            boxShadow: softGlow(accent, blur: 8, opacity: 0.7),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          time,
          style: AppText.sectionLabel.copyWith(color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Carte d'activité dans le feed santé ───────────────────────────────────────
class _ActivityFeedCard extends StatelessWidget {
  final Activity activity;
  final VoidCallback onTap;
  const _ActivityFeedCard({required this.activity, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      accent: kNeonPink,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: kNeonPink.withOpacity(0.14),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(Icons.directions_run_rounded,
                color: kNeonPink, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(activity.title,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('${activity.distanceKm} km',
                        style: const TextStyle(
                            fontFamily: kArcadeFont,
                            color: kNeonPink,
                            fontSize: 13,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(width: 10),
                    Text(
                      '${activity.durationFormatted} · ${activity.avgPace}/km',
                      style: AppText.caption,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: kNeonPink, size: 20),
        ],
      ),
    );
  }
}

// ── Insights & streaks ────────────────────────────────────────────────────────
class _InsightsPanel extends StatelessWidget {
  final List<HealthInsight> insights;
  final VoidCallback onFeedback;
  const _InsightsPanel({required this.insights, required this.onFeedback});

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) return const SizedBox.shrink();
    return _HPanel(
      accent: kNeonGreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < insights.length; i++) ...[
            if (i > 0)
              const Divider(height: 20, color: AppColors.border, thickness: 0.5),
            _InsightTile(insight: insights[i], onFeedback: onFeedback),
          ],
        ],
      ),
    );
  }
}

/// Un insight avec feedback pouce haut / pouce bas.
class _InsightTile extends StatefulWidget {
  final HealthInsight insight;
  final VoidCallback onFeedback;
  const _InsightTile({required this.insight, required this.onFeedback});

  @override
  State<_InsightTile> createState() => _InsightTileState();
}

class _InsightTileState extends State<_InsightTile> {
  @override
  Widget build(BuildContext context) {
    final ins = widget.insight;
    final liked = HealthFeedbackStore.isLiked(ins.id);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(ins.icon, color: ins.color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(ins.text,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 12.5, height: 1.35)),
        ),
        const SizedBox(width: 8),
        // Pouce haut : "utile" (ack, mise en avant discrète)
        _FeedbackButton(
          icon: liked ? Icons.thumb_up_rounded : Icons.thumb_up_off_alt_rounded,
          active: liked,
          color: kNeonGreen,
          onTap: () async {
            HapticFeedback.selectionClick();
            if (liked) {
              await HealthFeedbackStore.undoLike(ins.id);
            } else {
              await HealthFeedbackStore.like(ins.id);
            }
            if (mounted) setState(() {});
          },
        ),
        const SizedBox(width: 4),
        // Pouce bas : masque l'insight pour la journée
        _FeedbackButton(
          icon: Icons.thumb_down_off_alt_rounded,
          active: false,
          color: AppColors.textSecondary,
          onTap: () async {
            HapticFeedback.mediumImpact();
            await HealthFeedbackStore.dismiss(ins.id);
            widget.onFeedback();
          },
        ),
      ],
    );
  }
}

class _FeedbackButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  const _FeedbackButton({
    required this.icon,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon,
            size: 17,
            color: active ? color : AppColors.muted),
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
                progress: progress,
                accent: accent,
                weekRecords: weekRecords,
                onClaim: () => onClaim(q));
          }),
        ],
      ),
    );
  }
}

class _HealthQuestTile extends StatelessWidget {
  final HealthQuestProgress progress;
  final Color accent;
  final List<DailyHealthRecord> weekRecords;
  final VoidCallback onClaim;
  const _HealthQuestTile({
    required this.progress,
    required this.accent,
    required this.weekRecords,
    required this.onClaim,
  });

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
          if (q.isWeekly) ...[
            const SizedBox(height: 12),
            _WeeklyQuestBars(quest: q, weekRecords: weekRecords, color: accent),
          ],
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

// ── Barres quotidiennes d'une quête hebdo : 7 barres (L-D) + coche sur les
// jours où le seuil journalier de référence est atteint. Chaque barre porte
// la valeur réelle du jour (via sa hauteur) — pas d'interprétation, juste la
// progression jour par jour vers l'objectif de la semaine. ──────────────────
class _WeeklyQuestBars extends StatelessWidget {
  final HealthQuestDef quest;
  final List<DailyHealthRecord> weekRecords;
  final Color color;
  const _WeeklyQuestBars(
      {required this.quest, required this.weekRecords, required this.color});

  @override
  Widget build(BuildContext context) {
    final weekStart = GameService.startOfWeek(DateTime.now());
    final byKey = {for (final r in weekRecords) r.key: r};
    const labels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

    final values = <double>[];
    final met = <bool>[];
    for (int i = 0; i < 7; i++) {
      final day = weekStart.add(Duration(days: i));
      final rec = byKey[DailyHealthRecord.keyFor(day)];
      switch (quest.metric) {
        case HealthQuestMetric.weekSteps:
          final steps = rec?.steps ?? 0;
          values.add(steps.toDouble());
          met.add(steps >= HealthGameService.stepsGoal);
          break;
        case HealthQuestMetric.weekSleepNights:
          final hours = (rec?.totalSleepMin ?? 0) / 60.0;
          values.add(hours);
          met.add(hours >= 7);
          break;
        default:
          values.add(0);
          met.add(false);
      }
    }
    final maxV = values.fold<double>(1, math.max);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(7, (i) {
        final barH = (values[i] / maxV * 32).clamp(3.0, 32.0);
        return Expanded(
          child: Column(
            children: [
              SizedBox(
                height: 14,
                child: met[i]
                    ? Icon(Icons.check_circle_rounded, size: 13, color: color)
                    : null,
              ),
              const SizedBox(height: 3),
              Container(
                height: barH,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: met[i] ? color : AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 4),
              Text(labels[i],
                  style:
                      const TextStyle(color: AppColors.textSecondary, fontSize: 9)),
            ],
          ),
        );
      }),
    );
  }
}

// ── Cadre de panneau réutilisable (alias du design system, garde le nom
// historique pour limiter le diff dans ce fichier) ────────────────────────────
class _HPanel extends AppPanel {
  const _HPanel({required super.child, required super.accent, super.hero});
}

class _HPanelTitle extends PanelTitle {
  const _HPanelTitle(super.text, {super.color = kNeonCyan, super.trailing});
}
