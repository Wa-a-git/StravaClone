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
import 'detail_screen.dart';
import '../main.dart' show routeObserver;

class HealthDashboardScreen extends ConsumerStatefulWidget {
  const HealthDashboardScreen({super.key});

  @override
  ConsumerState<HealthDashboardScreen> createState() =>
      _HealthDashboardScreenState();
}

class _HealthDashboardScreenState extends ConsumerState<HealthDashboardScreen>
    with RouteAware {
  final _scrollController = ScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _scrollController.dispose();
    super.dispose();
  }

  /// Revenu sur cet écran depuis une fiche poussée par-dessus (ex. détail
  /// d'une métrique) : on retrouve le tableau de bord du jour, pas l'endroit
  /// où on avait laissé le scroll.
  @override
  void didPopNext() => _scrollToTop();

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    // Revenu sur l'onglet Santé depuis un autre onglet (IndexedStack garde
    // l'état, donc aucun événement de route ne se déclenche pour ce cas).
    ref.listen(shellIndexProvider, (prev, next) {
      if (next == 0 && prev != 0) _scrollToTop();
    });

    final st = ref.watch(healthDataProvider);
    final scores = st.scores;

    // Courses GPS enregistrées aujourd'hui (pour le feed "Activité suivie"
    // et la routine "5 km/jour", calculée depuis les activités suivies plutôt
    // que Health Connect — voir mémoire du plan).
    final now = DateTime.now();
    final todayRuns = ref
        .watch(activityListProvider)
        .where((a) =>
            a.date.year == now.year &&
            a.date.month == now.month &&
            a.date.day == now.day)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final todayRunKm =
        todayRuns.fold<double>(0, (s, a) => s + a.distanceKmValue);
    final allActivities = ref.watch(activityListProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        controller: _scrollController,
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
                    // ── FEED : la toute première carte est le gros bloc
                    // "aujourd'hui + cette semaine" (Bio-Score, quêtes,
                    // semaine, sous-scores, métriques, XP, quêtes de la
                    // semaine) — pas un bloc séparé au-dessus du feed, juste
                    // sa première entrée, plus complète que les suivantes.
                    // Ensuite chaque section redevient un post autonome et
                    // bordé façon réseau social, jusqu'à tout l'historique
                    // (courses + journées), du plus récent au plus ancien. ──
                    FadeSlideIn(
                      child: _TodayCard(
                        scores: scores,
                        snapshot: st.snapshot,
                        dailyQuests: HealthQuestService.daily(now),
                        today: HealthStore.recordFor(now),
                        dayKey: GameService.dayKey(now),
                        todayRunKm: todayRunKm,
                        activities: allActivities,
                        sleepStreak: st.sleepStreak,
                        weeklyQuests: HealthQuestService.weekly(now),
                        weekRecords: st.history
                            .where((r) => !r.date
                                .isBefore(GameService.startOfWeek(now)))
                            .toList(),
                        weekIntervalCount: allActivities
                            .where((a) =>
                                a.workoutType == 'interval' &&
                                !a.date.isBefore(GameService.startOfWeek(now)))
                            .length,
                        weekKey: GameService.weekKey(now),
                        xpToday: st.healthXpToday,
                        onXpTap: () =>
                            ref.read(shellIndexProvider.notifier).state = 2,
                        onClaim: (keyPrefix, q) =>
                            _claim(context, ref, keyPrefix, q),
                      ),
                    ),
                    const SizedBox(height: 22),

                    _FeedPost(
                      icon: Icons.insights_rounded,
                      time: 'ANALYSE',
                      title: 'Recommandations',
                      accent: kNeonGreen,
                      child: _InsightsPanel(
                        insights: st.insights,
                        onFeedback: () => ref
                            .read(healthDataProvider.notifier)
                            .refreshInsights(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                ],
              ),
            ),
          ),
          if (!st.isLoading && st.hasPermission && scores != null)
            _buildHistorySliver(context, allActivities),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  /// Historique complet (courses + journées santé), fusionné et trié du plus
  /// récent au plus ancien — construit en liste paresseuse (SliverList) car
  /// il peut contenir des mois d'entrées.
  Widget _buildHistorySliver(BuildContext context, List<Activity> activities) {
    final entries = _buildHistoryEntries(activities, HealthStore.all());
    if (entries.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => Padding(
            padding: const EdgeInsets.only(top: 22),
            child: _historyEntryPost(context, entries[i]),
          ),
          childCount: entries.length,
        ),
      ),
    );
  }

  Widget _historyEntryPost(BuildContext context, _HistoryEntry e) {
    if (e.kind == _FeedKind.activity) {
      final a = e.activity!;
      return _FeedPost(
        icon: Icons.directions_run_rounded,
        time: _dayLabel(a.date),
        title: 'Activité suivie',
        accent: kNeonPink,
        child: _ActivityFeedCard(
          activity: a,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => DetailScreen(activity: a))),
        ),
      );
    }
    final d = e.day!;
    return _FeedPost(
      icon: Icons.bedtime_rounded,
      time: _dayLabel(d.date),
      title: 'Résumé du jour',
      accent: kNeonViolet,
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => HealthDayDetailScreen(record: d))),
      child: _DayFeedContent(record: d),
    );
  }

  /// Libellé relatif (AUJOURD'HUI / HIER) ou date courte pour l'en-tête d'un
  /// post d'historique.
  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final day = DateTime(d.year, d.month, d.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return "AUJOURD'HUI";
    if (diff == 1) return 'HIER';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  Widget _buildHeader() {
    return const PageHeading(eyebrow: 'Données Fitbit', title: 'Aptitude du Jour');
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

/// Nombre de jours consécutifs (en terminant aujourd'hui ou hier) avec au
/// moins 5 km courus, à partir des activités suivies (GPS) — même logique que
/// HealthStore.streak, mais sur des Activity groupées par jour plutôt que sur
/// DailyHealthRecord (le kilométrage couru n'est pas une donnée Health Connect).
int _runStreak(List<Activity> activities) {
  final byDay = <String, double>{};
  for (final a in activities) {
    final key = '${a.date.year}-${a.date.month}-${a.date.day}';
    byDay[key] = (byDay[key] ?? 0) + a.distanceKmValue;
  }
  int count = 0;
  var cursor = DateTime.now();
  for (int i = 0; i < 400; i++) {
    final key = '${cursor.year}-${cursor.month}-${cursor.day}';
    final ok = (byDay[key] ?? 0) >= 5.0;
    if (ok) {
      count++;
    } else if (i == 0) {
      // aujourd'hui pas encore couru : on ne casse pas la série, on regarde hier
    } else {
      break;
    }
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return count;
}

// ── Historique fusionné (courses + journées santé) affiché dans le feed,
// trié du plus récent au plus ancien. ─────────────────────────────────────────
enum _FeedKind { activity, day }

class _HistoryEntry {
  final DateTime date; // jour civil, pour le regroupement/tri par journée
  final DateTime sortTime; // horodatage exact, pour l'ordre au sein d'un jour
  final _FeedKind kind;
  final Activity? activity;
  final DailyHealthRecord? day;

  _HistoryEntry.activity(Activity a)
      : date = DateTime(a.date.year, a.date.month, a.date.day),
        sortTime = a.date,
        kind = _FeedKind.activity,
        activity = a,
        day = null;

  _HistoryEntry.day(DailyHealthRecord d)
      : date = DateTime(d.date.year, d.date.month, d.date.day),
        sortTime = d.date,
        kind = _FeedKind.day,
        activity = null,
        day = d;
}

/// Fusionne courses et journées santé en une seule liste triée du plus
/// récent au plus ancien — au sein d'une même journée, les courses passent
/// avant le résumé du jour.
List<_HistoryEntry> _buildHistoryEntries(
    List<Activity> activities, List<DailyHealthRecord> days) {
  final items = <_HistoryEntry>[
    for (final a in activities) _HistoryEntry.activity(a),
    for (final d in days) _HistoryEntry.day(d),
  ];
  items.sort((a, b) {
    final dayCmp = b.date.compareTo(a.date);
    if (dayCmp != 0) return dayCmp;
    if (a.kind != b.kind) return a.kind == _FeedKind.activity ? -1 : 1;
    return b.sortTime.compareTo(a.sortTime);
  });
  return items;
}

/// Contenu compact d'un post "résumé du jour" dans l'historique — même
/// logique que la carte Sommeil du jour, mais à partir d'un DailyHealthRecord
/// passé plutôt que du snapshot Health Connect en direct.
class _DayFeedContent extends StatelessWidget {
  final DailyHealthRecord record;
  const _DayFeedContent({required this.record});

  String _fmt(double minutes) {
    final h = minutes ~/ 60;
    final m = (minutes % 60).round();
    return '${h}h${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final sleep = record.sleep;
    final total = sleep.totalAsleepMin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (total > 0) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_fmt(total),
                  style: const TextStyle(
                      fontFamily: kArcadeFont,
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                    'sommeil · score ${record.sleepScore}/100 · efficacité ${sleep.efficiency.toStringAsFixed(0)}%',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
              ),
            ],
          ),
          if (sleep.segments.isNotEmpty) ...[
            const SizedBox(height: 10),
            Hypnogram(segments: sleep.segments, height: 72, showAxis: false),
          ],
          const SizedBox(height: 10),
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
          const SizedBox(height: 14),
        ],
        _RawStatsRow(
          steps: record.steps,
          distanceKm: record.distanceKm,
          activeCalories: record.activeCalories,
        ),
      ],
    );
  }
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

// ── Héros Bio-Score + quêtes du jour ("le principal" en une seule carte) ──────
/// Carte unique "aujourd'hui + cette semaine" — Bio-Score, chiffres bruts,
/// quêtes du jour, semaine (points + streaks), sous-scores, métriques,
/// XP et quêtes de la semaine. Tout ce qui n'est pas "historique" vit ici,
/// dans une seule carte qui fait office de première entrée du feed — pas un
/// bloc séparé au-dessus du feed.
class _TodayCard extends StatelessWidget {
  final HealthScores scores;
  final HealthSnapshot snapshot;
  final List<HealthQuestDef> dailyQuests;
  final DailyHealthRecord? today;
  final String dayKey;
  final double todayRunKm;
  final List<Activity> activities;
  final int sleepStreak;
  final List<HealthQuestDef> weeklyQuests;
  final List<DailyHealthRecord> weekRecords;
  final int weekIntervalCount;
  final String weekKey;
  final int xpToday;
  final VoidCallback onXpTap;
  final void Function(String keyPrefix, HealthQuestDef q) onClaim;

  const _TodayCard({
    required this.scores,
    required this.snapshot,
    required this.dailyQuests,
    required this.today,
    required this.dayKey,
    required this.todayRunKm,
    required this.activities,
    required this.sleepStreak,
    required this.weeklyQuests,
    required this.weekRecords,
    required this.weekIntervalCount,
    required this.weekKey,
    required this.xpToday,
    required this.onXpTap,
    required this.onClaim,
  });

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
          const SizedBox(height: 16),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 14),
          _RawStatsRow(
            steps: snapshot.steps,
            distanceKm: snapshot.distanceKm,
            activeCalories: snapshot.activeCalories,
          ),
          if (dailyQuests.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 14),
            const _HPanelTitle('QUÊTES DU JOUR', color: kNeonGreen),
            const SizedBox(height: 10),
            _QuestsList(
              quests: dailyQuests,
              accent: kNeonGreen,
              today: today,
              weekRecords: const [],
              keyPrefix: dayKey,
              todayRunKm: todayRunKm,
              onClaim: (q) => onClaim(dayKey, q),
            ),
          ],
          const SizedBox(height: 16),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 14),
          const _HPanelTitle('CETTE SEMAINE', color: kNeonPink),
          const SizedBox(height: 10),
          _WeekDotsStrip(activities: activities),
          if (sleepStreak > 0 || activities.isNotEmpty) ...[
            const SizedBox(height: 14),
            _StreaksRow(
                sleepStreak: sleepStreak, runStreak: _runStreak(activities)),
          ],
          const SizedBox(height: 16),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 14),
          _SubScoresRow(scores: scores),
          const SizedBox(height: 16),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 14),
          _MetricsGrid(snapshot: snapshot),
          const SizedBox(height: 16),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 14),
          _HealthXpBanner(xpToday: xpToday, onTap: onXpTap),
          if (weeklyQuests.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 14),
            const _HPanelTitle('QUÊTES DE LA SEMAINE', color: kNeonPink),
            const SizedBox(height: 10),
            _QuestsList(
              quests: weeklyQuests,
              accent: kNeonPink,
              today: today,
              weekRecords: weekRecords,
              weekIntervalCount: weekIntervalCount,
              keyPrefix: weekKey,
              onClaim: (q) => onClaim(weekKey, q),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Chiffres bruts du jour, visibles directement dans la carte héros — le
// Bio-Score est un score composite, mais on veut aussi les données brutes
// juste en dessous, sans avoir à descendre jusqu'à "Métriques & tendances". ──
class _RawStatsRow extends StatelessWidget {
  final int steps;
  final double distanceKm;
  final double activeCalories;
  const _RawStatsRow({
    required this.steps,
    required this.distanceKm,
    required this.activeCalories,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RawStat(
            icon: Icons.directions_walk_rounded,
            color: kNeonGreen,
            value: steps.toString(),
            unit: 'pas',
          ),
        ),
        Container(width: 1, height: 30, color: AppColors.border),
        Expanded(
          child: _RawStat(
            icon: Icons.map_rounded,
            color: kNeonGreen,
            value: distanceKm.toStringAsFixed(2),
            unit: 'km',
          ),
        ),
        Container(width: 1, height: 30, color: AppColors.border),
        Expanded(
          child: _RawStat(
            icon: Icons.local_fire_department_rounded,
            color: kNeonPink,
            value: activeCalories.toStringAsFixed(0),
            unit: 'kcal',
          ),
        ),
      ],
    );
  }
}

class _RawStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String unit;
  const _RawStat({
    required this.icon,
    required this.color,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              TextSpan(
                text: ' $unit',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Bandeau hebdo : 7 points (L-D), rempli si ≥5 km ont été courus ce
// jour-là. Uniquement le fait (atteint/pas atteint), avec le chiffre réel en
// légende — pas de verdict, juste "combien de jours" cette semaine. ──────────
class _WeekDotsStrip extends StatelessWidget {
  final List<Activity> activities;
  const _WeekDotsStrip({required this.activities});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = GameService.startOfWeek(now);
    const labels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

    final kmByDay = <String, double>{};
    for (final a in activities) {
      final key = '${a.date.year}-${a.date.month}-${a.date.day}';
      kmByDay[key] = (kmByDay[key] ?? 0) + a.distanceKmValue;
    }

    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final active = days
        .map((d) => (kmByDay['${d.year}-${d.month}-${d.day}'] ?? 0) >= 5.0)
        .toList();
    final activeCount = active.where((a) => a).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$activeCount jour${activeCount > 1 ? 's' : ''} ≥ 5 km cette semaine',
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
                      color: isActive ? kNeonPink : AppColors.surfaceLight,
                      border: Border.all(
                          color: isActive ? kNeonPink : AppColors.border),
                    ),
                    child: isActive
                        ? const Icon(Icons.directions_run_rounded,
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

    // Plus de _HPanel/titre englobant ici : cette grille est désormais une
    // section parmi d'autres à l'intérieur du conteneur "cadran" unifié.
    return Column(
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

// ── Post de feed : en-tête (médaillon + heure + titre) et contenu dans une
// seule carte bordée — chaque section du feed doit se lire comme un post
// autonome de réseau social, pas comme un titre flottant au-dessus d'un
// panneau séparé. ─────────────────────────────────────────────────────────────
class _FeedPost extends StatelessWidget {
  final IconData icon;
  final String time;
  final String title;
  final Color accent;
  final Widget child;
  final VoidCallback? onTap;
  const _FeedPost({
    required this.icon,
    required this.time,
    required this.title,
    required this.accent,
    required this.child,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _HPanel(
      accent: accent,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accent, size: 15),
              ),
              const SizedBox(width: 10),
              Text(time, style: AppText.sectionLabel.copyWith(color: accent)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 12),
          child,
        ],
      ),
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
    // Pas de carte englobante ici : ce panneau est le contenu d'un _FeedPost
    // qui fournit déjà la carte bordée et le titre "Recommandations".
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < insights.length; i++) ...[
          if (i > 0)
            const Divider(height: 20, color: AppColors.border, thickness: 0.5),
          _InsightTile(insight: insights[i], onFeedback: onFeedback),
        ],
      ],
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
  final int runStreak;
  final int sleepStreak;
  const _StreaksRow({required this.runStreak, required this.sleepStreak});

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
    if (runStreak > 0) {
      chips.add(_StreakChip(
        label: 'Course 5 km',
        days: runStreak,
        color: kNeonPink,
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
// ── Liste de quêtes réutilisable, sans carte englobante — appelée depuis la
// carte héros (quêtes du jour) et depuis un _FeedPost (quêtes semaine), qui
// fournissent chacun déjà leur propre carte/titre. ───────────────────────────
class _QuestsList extends StatelessWidget {
  final List<HealthQuestDef> quests;
  final Color accent;
  final DailyHealthRecord? today;
  final List<DailyHealthRecord> weekRecords;
  final String keyPrefix;
  final double todayRunKm;
  final int weekIntervalCount;
  final void Function(HealthQuestDef) onClaim;

  const _QuestsList({
    required this.quests,
    required this.accent,
    required this.today,
    required this.weekRecords,
    required this.keyPrefix,
    this.todayRunKm = 0,
    this.weekIntervalCount = 0,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...quests.map((q) {
          final current = HealthQuestService.current(q, today, weekRecords,
              todayRunKm: todayRunKm, weekIntervalCount: weekIntervalCount);
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
  const _HPanel(
      {required super.child, required super.accent, super.hero, super.onTap});
}

class _HPanelTitle extends PanelTitle {
  const _HPanelTitle(super.text, {super.color = kNeonCyan, super.trailing});
}
