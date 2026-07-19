import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/activity.dart';
import '../models/daily_health_record.dart';
import '../models/health_snapshot.dart';
import '../models/vo2_estimate.dart';
import '../providers/activity_provider.dart';
import '../providers/health_provider.dart';
import '../services/game_service.dart';
import '../services/health_score_service.dart';
import '../services/health_store.dart';
import '../services/meditation_store.dart';
import '../services/vo2_estimate_store.dart';
import '../services/vo2_estimator_service.dart';
import '../theme.dart';
import '../widgets/arcade_fx.dart';
import '../widgets/health_charts.dart';
import '../widgets/ui_kit.dart';
import 'shell_screen.dart';
import 'sport_screen.dart' show sportTabProvider, SportTab;
import 'health_metric_detail_screen.dart';
import 'meditation_screen.dart';
import 'score_breakdown_screen.dart';
import 'sleep_detail_screen.dart';
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
      if (next == 2 && prev != 2) _scrollToTop();
    });

    final st = ref.watch(healthDataProvider);
    final scores = st.scores;
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
                    // ── Héro : Bio-Score + carrousel + équilibre du jour,
                    // remonté en premier — c'est la vue d'ensemble "comment
                    // je vais aujourd'hui", avant le détail indicateur par
                    // indicateur juste en dessous. ───────────────────────────
                    _TodayCard(
                      scores: scores,
                      snapshot: st.snapshot,
                      activities: allActivities,
                      sleepStreak: st.sleepStreak,
                      xpToday: st.healthXpToday,
                      onXpTap: () {
                        ref.read(sportTabProvider.notifier).state =
                            SportTab.progression;
                        ref.read(shellIndexProvider.notifier).state = 3;
                      },
                    ),
                    const SizedBox(height: 18),

                    // ── Court terme : métriques brutes non déjà couvertes par
                    // le héro ci-dessus, avec leur tendance 7 jours. ─────────
                    FadeSlideIn(
                      child: _HPanel(
                        accent: kNeonCyan,
                        child: _MetricsGrid(snapshot: st.snapshot),
                      ),
                    ),

                    if (st.insights.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _HPanel(
                        accent: kNeonGreen,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _HPanelTitle('RECOMMANDATIONS',
                                color: kNeonGreen),
                            const SizedBox(height: 14),
                            _InsightsPanel(
                              insights: st.insights,
                              onFeedback: () => ref
                                  .read(healthDataProvider.notifier)
                                  .refreshInsights(),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 18),
                    _HPanel(
                      accent: kNeonViolet,
                      child: const _SuperpositionCard(),
                    ),
                  ],
                  const SizedBox(height: 22),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return const PageHeading(eyebrow: 'Données Fitbit', title: 'Aptitude du Jour');
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

// ── Bannière d'aide à la synchro ──────────────────────────────────────────────
class _SyncHintBanner extends StatelessWidget {
  final VoidCallback onRefresh;
  const _SyncHintBanner({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    const amber = kNeonAmber;
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

// ── Scores + suivi de la semaine + XP — délibérément discret ──────────────────
/// Bio-Score, sous-scores, semaine (points + streaks) et XP du jour. Les
/// chiffres bruts vivent maintenant dans la section "7 JOURS" juste
/// au-dessus (plus consultée en premier que les scores composites), et les
/// quêtes réclamables ont été déplacées dans le Feed — cette carte n'est
/// donc plus un "hero" (pas de glow, rings compacts) : un simple résumé,
/// pas le point d'attention principal de l'écran.
class _TodayCard extends StatelessWidget {
  final HealthScores scores;
  final HealthSnapshot snapshot;
  final List<Activity> activities;
  final int sleepStreak;
  final int xpToday;
  final VoidCallback onXpTap;

  const _TodayCard({
    required this.scores,
    required this.snapshot,
    required this.activities,
    required this.sleepStreak,
    required this.xpToday,
    required this.onXpTap,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Héro : grand anneau Bio-Score + carrousel de pilules pour les
          // indicateurs déjà affichés dans le Feed (Pas, FC repos, Sommeil,
          // HRV, Cal. actives, Respiration) — Santé ne réaffiche plus leur
          // chiffre du jour en grand ailleurs, seulement leur tendance (voir
          // _allMetricSpecs, qui ne les liste plus). ──────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              HealthRing(
                  score: scores.bioScore,
                  color: tier.color,
                  size: 108,
                  centerLabel: 'BIO-SCORE'),
              const SizedBox(width: 14),
              Expanded(child: _HeroPillCarousel(snapshot: snapshot)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                tier.name,
                style: TextStyle(
                  fontFamily: kArcadeFont,
                  color: tier.color,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              TrendArrow(
                dir: bioTrend.dir,
                good: bioTrend.good,
                label: '${bioTrend.label} vs 7j',
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 14),
          const _HPanelTitle('ÉQUILIBRE DU JOUR', color: kNeonCyan),
          const SizedBox(height: 10),
          _BalanceRadar(scores: scores),
          const SizedBox(height: 16),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 14),
          _SubScoresRow(scores: scores, snapshot: snapshot),
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
          const _MeditationCard(),
          const SizedBox(height: 16),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 14),
          _HealthXpBanner(xpToday: xpToday, onTap: onXpTap),
        ],
      ),
    );
  }
}

class _HeroPillData {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color bg;
  final Color fg;
  final HealthMetric metric;
  /// Écrase la navigation par défaut (écran de détail générique) — utilisé
  /// pour Poids, qui est une métrique de saisie manuelle sans historique
  /// Health Connect à afficher.
  final VoidCallback? onTap;
  const _HeroPillData(this.label, this.value, this.unit, this.icon, this.bg,
      this.fg, this.metric, {this.onTap});
}

/// Carrousel de pilules à droite du Bio-Score — tous les indicateurs du jour
/// (Pas, FC repos, Sommeil, HRV, Cal. actives, Respiration, Distance, Poids,
/// VO2 max), présentés comme chez Fitbit plutôt qu'en petites cartes.
/// Vraiment swipeable (PageView) plutôt qu'un simple tap sur les points —
/// les points restent cliquables pour sauter directement à une page. Chaque
/// pilule ouvre l'écran de détail complet (7 jours → 1 an) de son indicateur,
/// sauf Poids qui ouvre la saisie rapide (pas d'historique montre à montrer).
class _HeroPillCarousel extends StatefulWidget {
  final HealthSnapshot snapshot;
  const _HeroPillCarousel({required this.snapshot});

  @override
  State<_HeroPillCarousel> createState() => _HeroPillCarouselState();
}

class _HeroPillCarouselState extends State<_HeroPillCarousel> {
  final _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _fmtHm(double minutes) {
    if (minutes <= 0) return '--';
    final h = minutes ~/ 60;
    final m = (minutes % 60).round();
    return '${h}h${m.toString().padLeft(2, '0')}';
  }

  void _goToPage(int i) {
    _pageController.animateToPage(i,
        duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.snapshot;
    final weightKg = HealthStore.recordFor(DateTime.now())?.weightKg ?? 0;
    final vo2Estimates = Vo2EstimateStore.all();
    final pages = <List<_HeroPillData>>[
      [
        _HeroPillData(
            'PAS',
            s.steps > 0 ? s.steps.toString() : '--',
            '',
            Icons.directions_walk_rounded,
            const Color(0xFF0E5C48),
            const Color(0xFF8FE3C9),
            HealthMetric.steps),
        _HeroPillData(
            'FC REPOS',
            s.restingHeartRate > 0 ? s.restingHeartRate.toStringAsFixed(0) : '--',
            'bpm',
            Icons.favorite_rounded,
            const Color(0xFF0D4A73),
            const Color(0xFF8AC4EE),
            HealthMetric.restingHeartRate),
        _HeroPillData(
            'SOMMEIL',
            _fmtHm(s.sleep.totalAsleepMin),
            '',
            Icons.bedtime_rounded,
            const Color(0xFF4A2A73),
            const Color(0xFFC9A8E8),
            HealthMetric.sleepHours),
      ],
      [
        _HeroPillData(
            'HRV',
            s.hrv > 0 ? s.hrv.toStringAsFixed(0) : '--',
            'ms',
            Icons.monitor_heart_rounded,
            const Color(0xFF0D4A73),
            const Color(0xFF8AC4EE),
            HealthMetric.hrv),
        _HeroPillData(
            'RESPIRATION',
            s.respiratoryRate > 0 ? s.respiratoryRate.toStringAsFixed(1) : '--',
            'rpm',
            Icons.air_rounded,
            const Color(0xFF4A2A73),
            const Color(0xFFC9A8E8),
            HealthMetric.respiratoryRate),
      ],
      [
        _HeroPillData(
            'DISTANCE',
            s.distanceKm > 0 ? s.distanceKm.toStringAsFixed(2) : '--',
            'km',
            Icons.map_rounded,
            const Color(0xFF0E5C48),
            const Color(0xFF8FE3C9),
            HealthMetric.distanceKm),
        _HeroPillData(
            'POIDS',
            weightKg > 0 ? weightKg.toStringAsFixed(1) : '--',
            'kg',
            Icons.monitor_weight_rounded,
            const Color(0xFF5C4A0E),
            const Color(0xFFE3C98F),
            HealthMetric.weightKg),
        _HeroPillData(
            'VO2 MAX',
            vo2Estimates.isNotEmpty
                ? vo2Estimates.last.value.toStringAsFixed(1)
                : '--',
            'ml/kg/min',
            Icons.speed_rounded,
            const Color(0xFF0D4A73),
            const Color(0xFF8AC4EE),
            HealthMetric.vo2Max),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 176,
          child: PageView.builder(
            controller: _pageController,
            itemCount: pages.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, pageIndex) => Column(
              children: [
                for (final pill in pages[pageIndex])
                  GestureDetector(
                    onTap: pill.onTap ??
                        () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => HealthMetricDetailScreen(
                                    metric: pill.metric, accent: pill.fg),
                              ),
                            ),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                          color: pill.bg, borderRadius: BorderRadius.circular(14)),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(pill.label,
                                    style: TextStyle(
                                        color: pill.fg,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600)),
                                RichText(
                                  text: TextSpan(
                                    children: [
                                      TextSpan(
                                          text: pill.value,
                                          style: const TextStyle(
                                              fontFamily: kArcadeFont,
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800)),
                                      if (pill.unit.isNotEmpty)
                                        TextSpan(
                                            text: ' ${pill.unit}',
                                            style: const TextStyle(
                                                color: Colors.white, fontSize: 9)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(pill.icon, color: pill.fg, size: 18),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(pages.length, (i) {
            return GestureDetector(
              onTap: () => _goToPage(i),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: i == _page ? 14 : 4,
                height: 4,
                decoration: BoxDecoration(
                  color: i == _page ? kNeonCyan : AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// Radar Sommeil/Récup/Activité — le déséquilibre du jour (ex. activité très
/// en retrait alors que sommeil/récup vont bien) saute aux yeux d'un coup
/// d'œil, alors que les 3 anneaux séparés ci-dessous ne le montrent pas aussi
/// directement.
enum _BalanceChartType { radar, bar, donut }

/// L'équilibre du jour (Sommeil/Récup/Activité), affichable sous 3 formes au
/// choix — demandé explicitement plutôt qu'une seule courbe/forme imposée.
/// Radar : la silhouette du déséquilibre. Barres : comparaison directe des
/// hauteurs. Circulaire : part relative de chaque score dans le total du
/// jour (pas une proportion "physique", juste un autre angle visuel).
class _BalanceRadar extends StatefulWidget {
  final HealthScores scores;
  const _BalanceRadar({required this.scores});

  @override
  State<_BalanceRadar> createState() => _BalanceRadarState();
}

class _BalanceRadarState extends State<_BalanceRadar> {
  _BalanceChartType _type = _BalanceChartType.radar;

  @override
  Widget build(BuildContext context) {
    final axes = [
      RadarAxis(
          label: 'Sommeil',
          value: widget.scores.sleepScore.toDouble(),
          color: kNeonViolet),
      RadarAxis(
          label: 'Récup',
          value: widget.scores.recoveryScore.toDouble(),
          color: kNeonCyan),
      RadarAxis(
          label: 'Activité',
          value: widget.scores.activityScore.toDouble(),
          color: kNeonGreen),
    ];

    return Column(
      children: [
        Center(child: _buildChart(axes)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ChartTypeButton(
                icon: Icons.radar_rounded,
                selected: _type == _BalanceChartType.radar,
                onTap: () => setState(() => _type = _BalanceChartType.radar)),
            const SizedBox(width: 10),
            _ChartTypeButton(
                icon: Icons.bar_chart_rounded,
                selected: _type == _BalanceChartType.bar,
                onTap: () => setState(() => _type = _BalanceChartType.bar)),
            const SizedBox(width: 10),
            _ChartTypeButton(
                icon: Icons.donut_large_rounded,
                selected: _type == _BalanceChartType.donut,
                onTap: () => setState(() => _type = _BalanceChartType.donut)),
          ],
        ),
      ],
    );
  }

  Widget _buildChart(List<RadarAxis> axes) {
    switch (_type) {
      case _BalanceChartType.radar:
        return RadarChart(size: 200, axes: axes);
      case _BalanceChartType.bar:
        return BarChart(axes: axes, height: 190);
      case _BalanceChartType.donut:
        final total = axes.fold<double>(0, (s, a) => s + a.value);
        return SegmentedRing(
          size: 180,
          segments: [
            for (final a in axes)
              RingSegmentData(value: a.value, color: a.color, label: a.label),
          ],
          centerValue:
              total > 0 ? (total / axes.length).round().toString() : '--',
          centerLabel: 'MOY.',
        );
    }
  }
}

class _ChartTypeButton extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ChartTypeButton(
      {required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected ? kNeonCyan.withOpacity(0.16) : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? kNeonCyan : AppColors.border),
        ),
        child: Icon(icon, size: 16, color: selected ? kNeonCyan : AppColors.textSecondary),
      ),
    );
  }
}

// ── Chiffres bruts du jour, visibles directement dans la carte héros — le
// Bio-Score est un score composite, mais on veut aussi les données brutes
// juste en dessous, sans avoir à descendre jusqu'à la section "Court terme". ──
class RawStatsRow extends StatelessWidget {
  final int steps;
  final double distanceKm;
  final double activeCalories;
  const RawStatsRow({
    required this.steps,
    required this.distanceKm,
    required this.activeCalories,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: RawStat(
            icon: Icons.directions_walk_rounded,
            color: kNeonGreen,
            value: steps.toString(),
            unit: 'pas',
          ),
        ),
        Container(width: 1, height: 30, color: AppColors.border),
        Expanded(
          child: RawStat(
            icon: Icons.map_rounded,
            color: kNeonGreen,
            value: distanceKm.toStringAsFixed(2),
            unit: 'km',
          ),
        ),
        Container(width: 1, height: 30, color: AppColors.border),
        Expanded(
          child: RawStat(
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

class RawStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String unit;
  const RawStat({
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
  final HealthSnapshot snapshot;
  const _SubScoresRow({required this.scores, required this.snapshot});

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
            snapshot: snapshot,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SubScoreCard(
            label: 'RÉCUP',
            score: scores.recoveryScore,
            color: kNeonCyan,
            metric: HealthMetric.recoveryScore,
            snapshot: snapshot,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SubScoreCard(
            label: 'ACTIVITÉ',
            score: scores.activityScore,
            color: kNeonGreen,
            metric: HealthMetric.activityScore,
            snapshot: snapshot,
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
  final HealthSnapshot snapshot;
  const _SubScoreCard({
    required this.label,
    required this.score,
    required this.color,
    required this.metric,
    required this.snapshot,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Le sommeil a son propre écran de détail (hypnogramme, nuit par
      // nuit) — les autres sous-scores restent sur le détail générique.
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => metric == HealthMetric.sleepScore
              ? const SleepDetailScreen()
              : ScoreBreakdownScreen(
                  scoreMetric: metric,
                  accent: color,
                  scoreValue: score,
                  snapshot: snapshot,
                ),
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

// ── Cadran Méditation : minutes du jour vs objectif, historique semaine/mois
// et série — jusqu'ici la méditation n'était visible que via le chip du Feed
// et son propre écran (meditation_screen.dart), rien sur le dashboard Santé.
// Tap → écran complet (chrono, historique détaillé, FC pendant la séance).
class _MeditationCard extends StatefulWidget {
  const _MeditationCard();

  @override
  State<_MeditationCard> createState() => _MeditationCardState();
}

class _MeditationCardState extends State<_MeditationCard> {
  static const _dailyGoalMinutes = 10;
  int _windowDays = 7;

  @override
  Widget build(BuildContext context) {
    final todayMinutes =
        MeditationStore.todayEntries().fold<int>(0, (s, e) => s + e.value.durationSeconds) ~/
            60;
    final goalScore = ((todayMinutes / _dailyGoalMinutes) * 100).clamp(0, 100).round();
    final streak = MeditationStore.streak();

    final cutoff = DateTime.now().subtract(Duration(days: _windowDays));
    final windowMinutes = MeditationStore.all()
            .where((e) => e.value.date.isAfter(cutoff))
            .fold<int>(0, (s, e) => s + e.value.durationSeconds) ~/
        60;

    return GestureDetector(
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const MeditationScreen())),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          HealthRing(score: goalScore, color: kNeonCyan, size: 64, centerLabel: 'MÉDIT.'),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('MÉDITATION',
                        style: TextStyle(
                            fontFamily: kArcadeFont,
                            color: kNeonCyan,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6)),
                    if (streak > 0) ...[
                      const SizedBox(width: 8),
                      Text('$streak j 🔥',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11)),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                SegmentedTabs<int>(
                  values: const [7, 30],
                  selected: _windowDays,
                  labelOf: (d) => d == 7 ? 'Semaine' : 'Mois',
                  onChanged: (d) => setState(() => _windowDays = d),
                ),
                const SizedBox(height: 8),
                Text(
                  '$windowMinutes min · ${_windowDays == 7 ? 'cette semaine' : 'ce mois-ci'}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
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

// ── Grille de métriques avec sparklines + tendances ────────────────────────
// Un seul groupe reste ici (Récupération avancée) : Activité générale,
// Vitaux & sommeil et Corps ont été retirés — Pas, FC repos, Sommeil, HRV,
// Cal. actives, Respiration, Distance, Poids et VO2 max vivent tous
// maintenant dans le carrousel héros (_HeroPillCarousel), qui les couvre
// déjà en swipant ; les répéter en grand ici ferait doublon.
enum _MetricGroupId { recovery }

List<_MetricSpec> _allMetricSpecs(HealthSnapshot snapshot) {
  // hrvZScore / deepSleepRatio / sleepDebtHours ne vivent que sur
  // DailyHealthRecord (calculés à la synchro, ont besoin d'historique) — pas
  // sur HealthSnapshot, qui ne connaît que le jour brut fraîchement lu.
  final today = HealthStore.recordFor(DateTime.now());
  return [
      // ── Récupération avancée ────────────────────────────────────────────
      // hrvZScore / deepSleepRatio / sleepDebtHours sont calculés à chaque
      // synchro (health_connect_service.dart) mais n'avaient encore aucune
      // carte sur ce dashboard — seulement accessibles via leur écran de
      // détail si on savait qu'ils existaient. HRV brut, lui, est dans le
      // carrousel héros (page 2) — seule sa version normalisée reste ici.
      _MetricSpec(
          'VFC normalisée',
          HealthMetric.hrvZScore,
          (today != null && today.hrvZScore != 0)
              ? today.hrvZScore.toStringAsFixed(1)
              : '--',
          'σ',
          Icons.show_chart_rounded,
          kNeonViolet,
          _MetricGroupId.recovery),
      _MetricSpec(
          'Sommeil profond',
          HealthMetric.deepSleepRatio,
          (today != null && today.deepSleepRatio > 0)
              ? (today.deepSleepRatio * 100).toStringAsFixed(0)
              : '--',
          '%',
          Icons.bedtime_rounded,
          kNeonViolet,
          _MetricGroupId.recovery),
      _MetricSpec(
          'Dette sommeil',
          HealthMetric.sleepDebtHours,
          (today?.sleepDebtHours ?? 0).toStringAsFixed(1),
          'h',
          Icons.hourglass_bottom_rounded,
          kNeonAmber,
          _MetricGroupId.recovery),
    ];
}

class _MetricsGrid extends StatefulWidget {
  final HealthSnapshot snapshot;
  const _MetricsGrid({required this.snapshot});

  @override
  State<_MetricsGrid> createState() => _MetricsGridState();
}

/// Métadonnées d'un groupe (titre, couleur, sous-score représentatif utilisé
/// pour décider si ce groupe mérite d'être remonté en premier).
class _GroupMeta {
  final _MetricGroupId id;
  final String title;
  final String subtitle;
  final Color color;
  final HealthMetric? trendMetric;
  const _GroupMeta(this.id, this.title, this.subtitle, this.color,
      this.trendMetric);
}

const _groupDefs = [
  _GroupMeta(_MetricGroupId.recovery, 'Récupération avancée',
      'Capacité à encaisser l\'effort — se lit sur plusieurs jours, pas au '
      'jour le jour.',
      kNeonViolet, HealthMetric.recoveryScore),
];

class _MetricsGridState extends State<_MetricsGrid> {
  @override
  Widget build(BuildContext context) {
    final all = _allMetricSpecs(widget.snapshot);

    // Priorise le groupe dont le sous-score dévie le plus défavorablement de
    // sa baseline 7j — même mécanique que HealthScoreService.trend(), pas un
    // ordre figé. Le groupe Corps (pas de sous-score) reste toujours en
    // dernier.
    final scores = HealthScoreService.computeAll(widget.snapshot);
    double scoreFor(HealthMetric m) => switch (m) {
          HealthMetric.activityScore => scores.activityScore.toDouble(),
          HealthMetric.sleepScore => scores.sleepScore.toDouble(),
          HealthMetric.recoveryScore => scores.recoveryScore.toDouble(),
          _ => 0,
        };
    final trends = <_MetricGroupId, TrendInfo>{
      for (final g in _groupDefs)
        if (g.trendMetric != null)
          g.id: HealthScoreService.trend(g.trendMetric!,
              scoreFor(g.trendMetric!), HealthStore.baseline(g.trendMetric!)),
    };
    // Priorité : dévie défavorablement (0) > dévie favorablement (1) >
    // stable (2) > pas de sous-score, Corps (3).
    int rank(_GroupMeta g) {
      if (g.trendMetric == null) return 3;
      final t = trends[g.id];
      if (t == null || t.dir == TrendDir.flat) return 2;
      return t.good ? 1 : 0;
    }

    final ordered = [..._groupDefs]..sort((a, b) {
        final ra = rank(a), rb = rank(b);
        if (ra != rb) return ra.compareTo(rb);
        final da = trends[a.id]?.delta.abs() ?? 0;
        final db = trends[b.id]?.delta.abs() ?? 0;
        return db.compareTo(da);
      });
    final topTrend = trends[ordered.first.id];
    final flaggedId = (topTrend != null && topTrend.dir != TrendDir.flat && !topTrend.good)
        ? ordered.first.id
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (flaggedId != null) ...[
          _ObservationCard(group: ordered.first, trend: topTrend!),
          const SizedBox(height: 18),
        ],
        for (final g in ordered) ...[
          _MetricGroupSection(
            meta: g,
            specs: all.where((m) => m.group == g.id).toList(),
            flagged: g.id == flaggedId,
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }

}

/// Une section groupée (titre, sous-titre, grille de cartes) — le groupe
/// Corps ajoute la tuile Poids (saisie manuelle) ; le groupe Récupération
/// ajoute le Score de Préparation composite en dessous de sa grille.
class _MetricGroupSection extends StatelessWidget {
  final _GroupMeta meta;
  final List<_MetricSpec> specs;
  final bool flagged;
  const _MetricGroupSection(
      {required this.meta, required this.specs, required this.flagged});

  @override
  Widget build(BuildContext context) {
    if (specs.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: meta.color.withOpacity(flagged ? 0.7 : 0.25),
            width: flagged ? 1.4 : 1),
        boxShadow: flagged ? softGlow(meta.color) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  meta.title.toUpperCase(),
                  style: TextStyle(
                    color: meta.color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              if (flagged)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: kNeonAmber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: kNeonAmber.withOpacity(0.5)),
                  ),
                  child: const Text('SIGNALÉ',
                      style: TextStyle(
                          color: kNeonAmber,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4)),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(meta.subtitle,
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 10.0;
              final cardW = (constraints.maxWidth - spacing) / 2 - 0.5;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  ...specs.map((m) => SizedBox(
                        width: cardW,
                        child: _MetricCard(spec: m),
                      )),
                ],
              );
            },
          ),
          if (meta.id == _MetricGroupId.recovery) ...[
            const SizedBox(height: 10),
            const _ReadinessCard(),
          ],
        ],
      ),
    );
  }
}

/// Callout "dashboard intelligent" : nomme en langage clair le groupe dont le
/// sous-score dévie le plus défavorablement de sa baseline 7j — seulement
/// affiché quand un signal dévie vraiment (même philosophie que
/// dayHighlight() dans feed_screen.dart), jamais pour occuper de l'espace.
/// Le groupe concerné est aussi remonté en tête de "7 jours" avec le badge
/// SIGNALÉ juste en dessous.
class _ObservationCard extends StatelessWidget {
  final _GroupMeta group;
  final TrendInfo trend;
  const _ObservationCard({required this.group, required this.trend});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kNeonAmber.withOpacity(0.14), kNeonViolet.withOpacity(0.06)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kNeonAmber.withOpacity(0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: kNeonAmber.withOpacity(0.16),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: kNeonAmber.withOpacity(0.5)),
            ),
            child: const Icon(Icons.trending_down_rounded,
                color: kNeonAmber, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CETTE SEMAINE',
                    style: TextStyle(
                        color: kNeonAmber,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6)),
                const SizedBox(height: 3),
                Text(
                  '${group.title} en baisse (${trend.label} vs 7j).',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Groupe remonté en premier dans "7 jours" ci-dessous, avec '
                  'le détail des indicateurs concernés.',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11.5, height: 1.35),
                ),
              ],
            ),
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
  final _MetricGroupId group;
  _MetricSpec(this.title, this.metric, this.value, this.unit, this.icon,
      this.color, this.group);
}

class _MetricCard extends StatelessWidget {
  final _MetricSpec spec;
  const _MetricCard({required this.spec});

  @override
  Widget build(BuildContext context) {
    final noData = spec.value == '--';
    // VO2 max : source locale (Vo2EstimateStore), pas Health Connect —
    // HealthStore n'a jamais rien pour cette métrique dans notre cas d'usage.
    final isVo2Max = spec.metric == HealthMetric.vo2Max;
    final vo2Estimates =
        isVo2Max ? Vo2EstimateStore.all() : const <Vo2Estimate>[];
    final series = isVo2Max
        ? vo2Estimates.map((e) => e.value).toList()
        : HealthStore.series(spec.metric, 7)
            .map((e) => e.value)
            .where((v) => v > 0)
            .toList();
    final current = series.isNotEmpty ? series.last : 0.0;
    final baseline = isVo2Max
        ? (series.length > 1
            ? series.sublist(0, series.length - 1).reduce((a, b) => a + b) /
                (series.length - 1)
            : 0.0)
        : HealthStore.baseline(spec.metric);
    final vo2Provisional = isVo2Max &&
        vo2Estimates.isNotEmpty &&
        Vo2EstimatorService.confidenceFor(vo2Estimates.last).isProvisional;
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
            ] else ...[
              if (vo2Provisional) ...[
                const SizedBox(height: 4),
                const Text('provisoire',
                    style: TextStyle(
                        color: kNeonAmber,
                        fontSize: 9,
                        fontStyle: FontStyle.italic)),
              ],
              // Sparkline seulement s'il y a un historique à tracer.
              if (series.length >= 2) ...[
                const SizedBox(height: 6),
                Sparkline(values: series, color: spec.color, height: 28),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// (Ancienne feuille de saisie rapide _WeighInSheet retirée : la pilule
// Poids du carrousel héros ouvre maintenant HealthMetricDetailScreen comme
// les autres indicateurs, dont l'icône crayon dans l'AppBar sert déjà de
// saisie — voir health_metric_detail_screen.dart _editWeight()).

// ── Score de Préparation "maison" : composite HRV + FC repos (déjà fusionnés
// dans recoveryScore) + sommeil. Explicitement PAS le score EDA propriétaire
// Fitbit (scan manuel 3 min au réveil) — ce capteur n'est jamais exposé via
// Health Connect, irréalisable ici quel que soit l'effort de code (vérifié
// dans health_connect_service.dart). Le badge "Maison" évite toute confusion. ─
class _ReadinessCard extends ConsumerWidget {
  const _ReadinessCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(healthDataProvider);
    final scores = st.scores;
    if (scores == null) return const SizedBox.shrink();

    final readiness =
        (scores.recoveryScore * 0.6 + scores.sleepScore * 0.4).round();
    final tier = HealthScoreService.tierFor(readiness);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kNeonViolet.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HealthRing(score: readiness, color: kNeonViolet, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SCORE DE PRÉPARATION',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6)),
                    const SizedBox(height: 2),
                    Text(tier.name.toUpperCase(),
                        style: TextStyle(
                            fontFamily: kArcadeFont,
                            color: kNeonViolet,
                            fontSize: 13,
                            fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: kNeonViolet.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: kNeonViolet.withOpacity(0.4)),
                ),
                child: const Text('MAISON',
                    style: TextStyle(
                        color: kNeonViolet,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 10),
          const Text(
            'Composite HRV + FC repos + sommeil, calculé sur cet appareil. '
            'Ce n\'est PAS le score EDA (scan manuel au réveil) ni un statut '
            'basé sur la température cutanée — Health Connect n\'expose '
            'aucun des deux, quelle que soit la montre connectée.',
            style: TextStyle(color: AppColors.muted, fontSize: 10.5, height: 1.4),
          ),
        ],
      ),
    );
  }
}

// ── Superposition personnalisable : croise deux métriques au choix sur la
// même période — chacune normalisée sur sa propre échelle (0-1), donc ce
// n'est pas une comparaison quantitative exacte, juste un repère visuel pour
// spotter des liens (ex. sommeil ↔ récupération). Défaut générique pertinent
// plutôt que de forcer l'utilisateur à choisir avant d'avoir vu le résultat. ─
const List<_SuperpositionOption> _superpositionOptions = [
  _SuperpositionOption(HealthMetric.sleepScore, 'Sommeil'),
  _SuperpositionOption(HealthMetric.recoveryScore, 'Récupération'),
  _SuperpositionOption(HealthMetric.activityScore, 'Activité'),
  _SuperpositionOption(HealthMetric.restingHeartRate, 'FC repos'),
  _SuperpositionOption(HealthMetric.hrv, 'HRV'),
  _SuperpositionOption(HealthMetric.steps, 'Pas'),
  _SuperpositionOption(HealthMetric.distanceKm, 'Distance'),
  _SuperpositionOption(HealthMetric.respiratoryRate, 'Respiration'),
  _SuperpositionOption(HealthMetric.weightKg, 'Poids'),
];

class _SuperpositionOption {
  final HealthMetric metric;
  final String label;
  const _SuperpositionOption(this.metric, this.label);
}

class _SuperpositionCard extends StatefulWidget {
  const _SuperpositionCard();

  @override
  State<_SuperpositionCard> createState() => _SuperpositionCardState();
}

class _SuperpositionCardState extends State<_SuperpositionCard> {
  HealthMetric _metricA = HealthMetric.sleepScore;
  HealthMetric _metricB = HealthMetric.recoveryScore;

  String _labelFor(HealthMetric m) =>
      _superpositionOptions.firstWhere((o) => o.metric == m).label;

  @override
  Widget build(BuildContext context) {
    final seriesA = HealthStore.series(_metricA, 30);
    final seriesB = HealthStore.series(_metricB, 30);
    final valuesA = seriesA.map((e) => e.value).toList();
    final valuesB = seriesB.map((e) => e.value).toList();
    final dates = seriesA.map((e) => e.key).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _HPanelTitle('SUPERPOSITION · 30 JOURS', color: kNeonViolet),
        const SizedBox(height: 4),
        const Text(
          'Croise deux métriques sur la même période pour repérer des liens.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _SuperpositionPicker(
                color: kNeonCyan,
                label: _labelFor(_metricA),
                onTap: () => _pick(context, forA: true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SuperpositionPicker(
                color: kNeonPink,
                label: _labelFor(_metricB),
                onTap: () => _pick(context, forA: false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        OverlayTrendChart(
          valuesA: valuesA,
          valuesB: valuesB,
          colorA: kNeonCyan,
          colorB: kNeonPink,
          dates: dates,
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context, {required bool forA}) async {
    final chosen = await showAppSheet<HealthMetric>(
      context: context,
      child: _SuperpositionPickSheet(current: forA ? _metricA : _metricB),
    );
    if (chosen == null) return;
    setState(() {
      if (forA) {
        _metricA = chosen;
      } else {
        _metricB = chosen;
      }
    });
  }
}

class _SuperpositionPicker extends StatelessWidget {
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _SuperpositionPicker(
      {required this.color, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(Icons.unfold_more_rounded,
                size: 15, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _SuperpositionPickSheet extends StatelessWidget {
  final HealthMetric current;
  const _SuperpositionPickSheet({required this.current});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CHOISIR UNE MÉTRIQUE',
          style: TextStyle(
              fontFamily: kArcadeFont,
              color: kNeonCyan,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1),
        ),
        const SizedBox(height: 12),
        for (final opt in _superpositionOptions)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(opt.label,
                style:
                    const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
            trailing: opt.metric == current
                ? const Icon(Icons.check_rounded, color: kNeonCyan)
                : null,
            onTap: () => Navigator.pop(context, opt.metric),
          ),
      ],
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
    // Pas de carte englobante ici : ce panneau est le contenu d'un _HPanel
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
              color: kNeonAmber, size: 22),
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

// ── Cadre de panneau réutilisable (alias du design system, garde le nom
// historique pour limiter le diff dans ce fichier) ────────────────────────────
class _HPanel extends AppPanel {
  const _HPanel(
      {required super.child, required super.accent, super.hero, super.onTap});
}

class _HPanelTitle extends PanelTitle {
  const _HPanelTitle(super.text, {super.color = kNeonCyan, super.trailing});
}
