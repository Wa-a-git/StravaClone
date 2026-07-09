import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/activity.dart';
import '../providers/activity_provider.dart';
import '../providers/game_provider.dart';
import '../services/efficiency_trend.dart';
import '../services/game_service.dart';
import '../services/health_score_service.dart' show TrendDir;
import '../services/health_store.dart' show HealthProfileStore;
import '../services/hr_efficiency_store.dart';
import '../services/vo2_estimate_store.dart';
import '../services/vo2_estimator_service.dart';
import '../widgets/arcade_fx.dart';
import '../widgets/health_charts.dart';
import '../widgets/ui_kit.dart';
import '../theme.dart';
import 'shell_screen.dart';
import 'sport_screen.dart' show sportTabProvider, SportTab;
import 'interval_game_screen.dart';
import 'mini_games_screen.dart';
import 'history_screen.dart';
import 'tracking_screen.dart';

enum HomePeriod { week, month, all }

extension on HomePeriod {
  String get label => switch (this) {
        HomePeriod.week => 'Semaine',
        HomePeriod.month => 'Mois',
        HomePeriod.all => 'Tout',
      };
}

/// Période sélectionnée pour filtrer les statistiques de l'accueil.
final homePeriodProvider = StateProvider<HomePeriod>((ref) => HomePeriod.week);

/// Lance une course (GPS libre, ou avec un objectif de distance affiché à
/// titre indicatif — ex. la routine "5 km quotidien"). Public : réutilisé par
/// le bouton "LANCER UNE COURSE" et par le lancement rapide (+) du hub Sport.
void startRun(BuildContext context, {double? targetKm}) {
  HapticFeedback.mediumImpact();
  Navigator.push(
    context,
    PageRouteBuilder(
      pageBuilder: (_, animation, __) => TrackingScreen(targetKm: targetKm),
      transitionsBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 380),
    ),
  );
}

/// Contenu du sous-onglet "Course" du hub Sport (stats, tendance, historique,
/// mini-jeux). N'a pas son propre Scaffold : il est inséré dans SportScreen.
class CourseSection extends ConsumerWidget {
  const CourseSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allActivities = ref.watch(activityListProvider);
    final period = ref.watch(homePeriodProvider);

    final now = DateTime.now();
    final startOfWeek = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final startOfMonth = DateTime(now.year, now.month, 1);

    // Filtre les activités selon la période choisie
    final activities = switch (period) {
      HomePeriod.week =>
        allActivities.where((a) => !a.date.isBefore(startOfWeek)).toList(),
      HomePeriod.month =>
        allActivities.where((a) => !a.date.isBefore(startOfMonth)).toList(),
      HomePeriod.all => allActivities,
    };

    final count = activities.length;
    final totalDistanceKm = activities.fold<double>(
      0.0,
      (sum, activity) => sum + activity.distanceKmValue,
    );
    final totalDurationSeconds = activities.fold<int>(
      0,
      (sum, activity) => sum + activity.duration,
    );
    final totalElevation = activities.fold<double>(
      0.0,
      (sum, activity) => sum + activity.elevationGainValue,
    );
    final avgDistanceKm = count > 0 ? totalDistanceKm / count : 0.0;
    final avgSpeedKmh = totalDurationSeconds > 0
        ? totalDistanceKm / (totalDurationSeconds / 3600)
        : 0.0;
    final avgPaceSeconds = totalDistanceKm > 0
        ? (totalDurationSeconds / totalDistanceKm).round()
        : 0;
    final bestPaceSeconds = activities
        .where((activity) => activity.distanceKmValue > 0)
        .map((activity) => activity.duration / activity.distanceKmValue)
        .fold<double>(double.infinity, min);
    final longestDistanceKm = activities
        .map((activity) => activity.distanceKmValue)
        .fold<double>(0.0, max);
    final recentRuns = activities.take(6).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FadeSlideIn(
            child: GlowButton(
              label: 'LANCER UNE COURSE',
              icon: Icons.play_arrow_rounded,
              color: kNeonPink,
              foreground: Colors.white,
              onPressed: () => startRun(context),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          FadeSlideIn(
            delay: const Duration(milliseconds: 60),
            child: _LevelBanner(
              profile: ref.watch(playerProfileProvider),
              onTap: () {
                ref.read(sportTabProvider.notifier).state =
                    SportTab.progression;
                ref.read(shellIndexProvider.notifier).state = 2;
              },
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SegmentedTabs<HomePeriod>(
            values: HomePeriod.values,
            selected: period,
            labelOf: (p) => p.label,
            onChanged: (p) => ref.read(homePeriodProvider.notifier).state = p,
          ),
          const SizedBox(height: AppSpacing.xl),
          _buildSummaryRow(count, totalDistanceKm, avgDistanceKm, avgSpeedKmh),
          const SizedBox(height: AppSpacing.xxl),
          _buildTrendChart(recentRuns),
          const SizedBox(height: AppSpacing.xxl),
          _buildPerformanceRow(avgPaceSeconds, bestPaceSeconds, longestDistanceKm, totalElevation),
          const SizedBox(height: AppSpacing.xxl),
          _PersonalRecordsCard(activities: allActivities),
          const SizedBox(height: AppSpacing.xxl),
          const _Vo2TrendCard(),
          const SizedBox(height: AppSpacing.lg),
          const _EfficiencyTrendCard(),
          const SizedBox(height: AppSpacing.lg),
          _IntervalSuggestionCard(activities: allActivities),
          const SizedBox(height: AppSpacing.xxl),
          _MiniGamesEntry(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MiniGamesScreen()),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          if (allActivities.isNotEmpty) ...[
            _SectionHeader(
              title: 'Dernière sortie',
              action: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                ),
                child: const Text('Tout voir →'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _LatestActivityCard(activity: allActivities.first),
            const SizedBox(height: AppSpacing.xxl),
          ],
          _buildMotivationCard(allActivities.length),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(int count, double totalDistanceKm, double avgDistanceKm, double avgSpeedKmh) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Courses',
            animateTo: count.toDouble(),
            icon: Icons.timeline_rounded,
            iconColor: AppColors.arcadeCyan,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Km total',
            animateTo: totalDistanceKm,
            fractionDigits: 1,
            icon: Icons.route_rounded,
            iconColor: AppColors.arcadePink,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Vitesse moyenne',
            animateTo: avgSpeedKmh,
            fractionDigits: 1,
            icon: Icons.speed_rounded,
            iconColor: AppColors.arcadeViolet,
          ),
        ),
      ],
    );
  }

  Widget _buildPerformanceRow(int avgPaceSeconds, double bestPaceSeconds, double longestDistanceKm, double totalElevation) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Allure moyenne',
                value: _formatPace(avgPaceSeconds),
                icon: Icons.timer_rounded,
                iconColor: AppColors.arcadeCyan,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Meilleure allure',
                value: bestPaceSeconds.isFinite ? _formatPace(bestPaceSeconds.toInt()) : '--:--',
                icon: Icons.whatshot_rounded,
                iconColor: AppColors.arcadePink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Longue distance',
                animateTo: longestDistanceKm,
                fractionDigits: 1,
                icon: Icons.terrain_rounded,
                iconColor: AppColors.arcadeViolet,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Dénivelé +',
                animateTo: totalElevation,
                suffix: ' m',
                icon: Icons.landscape_rounded,
                iconColor: AppColors.arcadeCyan,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTrendChart(List<Activity> runs) {
    if (runs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Tendance des sorties',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Commence ta première course pour voir le graphique.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    final maxDistance = runs.map((activity) => activity.distanceKmValue).reduce(max);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Graphique des derniers runs',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: runs.map((activity) {
                final heightFactor = maxDistance > 0
                    ? min(1.0, activity.distanceKmValue / maxDistance)
                    : 0.0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: max(30, 120 * heightFactor),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.arcadePink, AppColors.arcadeCyan],
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _shortDate(activity.date),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Dernière : ${runs.first.distanceKm} km',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              Text(
                'Max : ${runs.map((activity) => activity.distanceKmValue).reduce(max).toStringAsFixed(1)} km',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMotivationCard(int count) {
    final emoji = count == 0 ? '🏁' : count < 5 ? '🔥' : '🚀';
    final title = count == 0
        ? 'Ta prochaine sortie démarre maintenant.'
        : count < 5
            ? 'Habitude en construction.'
            : 'Tu es dans le flow.';
    final subtitle = count == 0
        ? 'Ajoute ta première course et tu verras ce tableau s’animer.'
        : count < 5
            ? 'Garde le rythme, chaque session compte.'
            : 'Continue comme ça, les progrès sont visibles.';

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.arcadePink, AppColors.arcadeViolet],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 28)),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatPace(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _shortDate(DateTime date) {
    const days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    return days[date.weekday - 1];
  }
}

// ── Records personnels : records battus, tous confondus (jamais filtrés par
// période) — même logique que la célébration en fin de course
// (_maybeCelebrateRecords dans tracking_screen.dart), affichée en continu
// plutôt qu'une seule fois au moment où le record tombe. ─────────────────────
class _PersonalRecordsCard extends StatelessWidget {
  final List<Activity> activities;
  const _PersonalRecordsCard({required this.activities});

  @override
  Widget build(BuildContext context) {
    if (activities.isEmpty) return const SizedBox.shrink();

    final longest = activities
        .reduce((a, b) => a.distanceKmValue >= b.distanceKmValue ? a : b);

    final pacedRuns =
        activities.where((a) => a.distanceKmValue >= 0.5).toList();
    Activity? bestPaceRun;
    if (pacedRuns.isNotEmpty) {
      bestPaceRun = pacedRuns.reduce((a, b) =>
          (a.duration / a.distanceKmValue) <=
                  (b.duration / b.distanceKmValue)
              ? a
              : b);
    }

    final elevatedRuns = activities
        .where((a) => a.hasElevation && a.elevationGainValue > 0)
        .toList();
    Activity? bestElevationRun;
    if (elevatedRuns.isNotEmpty) {
      bestElevationRun = elevatedRuns.reduce(
          (a, b) => a.elevationGainValue >= b.elevationGainValue ? a : b);
    }

    return AppPanel(
      accent: kNeonAmber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelTitle('RECORDS PERSONNELS', color: kNeonAmber),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _RecordTile(
                  icon: Icons.terrain_rounded,
                  label: 'Plus longue',
                  value: '${longest.distanceKm} km',
                  date: longest.date,
                ),
              ),
              Container(width: 1, height: 48, color: AppColors.border),
              Expanded(
                child: bestPaceRun != null
                    ? _RecordTile(
                        icon: Icons.whatshot_rounded,
                        label: 'Meilleure allure',
                        value: '${bestPaceRun.avgPace}/km',
                        date: bestPaceRun.date,
                      )
                    : const _RecordTilePlaceholder(label: 'Meilleure allure'),
              ),
              Container(width: 1, height: 48, color: AppColors.border),
              Expanded(
                child: bestElevationRun != null
                    ? _RecordTile(
                        icon: Icons.landscape_rounded,
                        label: 'Plus gros D+',
                        value: '${bestElevationRun.elevationGain} m',
                        date: bestElevationRun.date,
                      )
                    : const _RecordTilePlaceholder(label: 'Plus gros D+'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final DateTime date;
  const _RecordTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.date,
  });

  static String _shortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year.toString().substring(2)}';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: kNeonAmber, size: 16),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                fontFamily: kArcadeFont,
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label,
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 9.5)),
        const SizedBox(height: 2),
        Text(_shortDate(date),
            style: const TextStyle(color: AppColors.muted, fontSize: 9)),
      ],
    );
  }
}

class _RecordTilePlaceholder extends StatelessWidget {
  final String label;
  const _RecordTilePlaceholder({required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.remove_rounded, color: AppColors.muted, size: 16),
        const SizedBox(height: 6),
        const Text('--',
            style: TextStyle(
                fontFamily: kArcadeFont,
                color: AppColors.muted,
                fontSize: 14,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label,
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 9.5)),
      ],
    );
  }
}

/// VO2 max estimé localement (régression FC↔VO2 sur les courses suivies) —
/// distinct du VO2 max cloud affiché côté Santé. Rien ne s'affiche tant que
/// l'estimation n'a pas assez de données pour être défendable (voir
/// `Vo2EstimatorService`) : jamais un chiffre nu sans le contexte derrière.
class _Vo2TrendCard extends StatelessWidget {
  const _Vo2TrendCard();

  @override
  Widget build(BuildContext context) {
    final estimates = Vo2EstimateStore.all();
    final vo2Category = estimates.isNotEmpty
        ? Vo2EstimatorService.categoryFor(
            estimates.last.value,
            age: HealthProfileStore.age,
            sex: HealthProfileStore.sex,
          )
        : null;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kNeonCyan.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'VO2 max estimé',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
              ),
              if (estimates.isNotEmpty &&
                  Vo2EstimatorService.confidenceFor(estimates.last)
                      .isProvisional) ...[
                const SizedBox(width: 8),
                const ProvisionalBadge(),
              ],
              if (vo2Category != null) ...[
                const SizedBox(width: 8),
                Vo2CategoryBadge(category: vo2Category),
              ],
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Calculé depuis tes courses (allure + FC), pas depuis le capteur cloud.',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 11.5, height: 1.3),
          ),
          const SizedBox(height: 14),
          if (estimates.isEmpty)
            const Text(
              'Pas encore assez de données — plusieurs courses avec FC, avec '
              'un peu de variété d\'allure (le fractionné aide beaucoup), sont '
              'nécessaires pour une estimation fiable.',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
            )
          else ...[
            TrendChart(
              values: Vo2EstimateStore.series(90).map((e) => e.value).toList(),
              dates: Vo2EstimateStore.series(90).map((e) => e.key).toList(),
              color: kNeonCyan,
              unit: ' ml/kg/min',
              fractionDigits: 1,
              height: 140,
            ),
            const SizedBox(height: 8),
            Text(
              Vo2EstimatorService.confidenceFor(estimates.last).caption,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

/// Signal de progression demandé explicitement : pas la vitesse, mais la FC
/// nécessaire pour une allure donnée. Un ratio qui baisse dans le temps veut
/// dire un cœur plus efficace — le signal pour penser à accélérer.
class _EfficiencyTrendCard extends StatelessWidget {
  const _EfficiencyTrendCard();

  static const int _minPoints = 6;
  static const int _groupSize = 5;

  @override
  Widget build(BuildContext context) {
    final points = HrEfficiencyStore.all();
    Widget? comparison;
    if (points.length >= _minPoints) {
      final n = min(_groupSize, points.length ~/ 2);
      final recent =
          points.sublist(points.length - n).map((p) => p.ratio).toList();
      final previous = points
          .sublist(points.length - 2 * n, points.length - n)
          .map((p) => p.ratio)
          .toList();
      final trend = EfficiencyTrend.compare(
        EfficiencyTrend.average(recent),
        EfficiencyTrend.average(previous),
      );
      if (trend.dir != TrendDir.flat) {
        comparison = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TrendArrow(dir: trend.dir, good: trend.good),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                trend.good
                    ? 'Cœur plus efficace sur tes $n dernières courses (${trend.label} bpm/km/h) — tu peux penser à accélérer.'
                    : 'FC un peu plus haute pour la même allure sur tes $n dernières courses (${trend.label} bpm/km/h).',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11.5, height: 1.3),
              ),
            ),
          ],
        );
      }
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kNeonViolet.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Efficacité cardiaque',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'FC moyenne rapportée à l\'allure moyenne, par course — plus bas '
            'veut dire un cœur qui bat moins vite pour la même vitesse.',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 11.5, height: 1.3),
          ),
          const SizedBox(height: 14),
          if (points.length < _minPoints)
            const Text(
              'Pas encore assez de courses avec FC pour dégager une tendance '
              'fiable.',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
            )
          else ...[
            TrendChart(
              values: points.map((p) => p.ratio).toList(),
              dates: points.map((p) => p.date).toList(),
              color: kNeonViolet,
              unit: ' bpm/km/h',
              fractionDigits: 1,
              height: 140,
            ),
            if (comparison != null) ...[
              const SizedBox(height: 10),
              comparison,
            ],
          ],
        ],
      ),
    );
  }
}

/// Suggestion simple (règle, pas d'IA) : pousse vers le fractionné quand
/// aucune séance à haute intensité n'a eu lieu cette semaine — le protocole
/// le plus documenté pour progresser en VO2 max. Disparaît dès qu'une séance
/// a eu lieu (pas de bruit une fois l'objectif atteint).
class _IntervalSuggestionCard extends StatelessWidget {
  final List<Activity> activities;
  const _IntervalSuggestionCard({required this.activities});

  @override
  Widget build(BuildContext context) {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final didIntervalThisWeek = activities
        .any((a) => a.workoutType == 'interval' && a.date.isAfter(weekAgo));
    if (didIntervalThisWeek) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kNeonPink.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bolt_rounded, color: kNeonPink, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Aucune séance à haute intensité cette semaine',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Le fractionné améliore le VO2 max plus efficacement qu\'une '
            'sortie tranquille — le 4×4 (4 min d\'effort / 3 min de récup, '
            '×4) est l\'un des protocoles les plus documentés.',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const IntervalGameScreen(
                    initialPreset: (work: 240, rest: 180, reps: 4, warmup: 300),
                  ),
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: kNeonPink,
                side: BorderSide(color: kNeonPink.withOpacity(0.6)),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.repeat_rounded, size: 18),
              label: const Text('LANCER LE 4×4',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelBanner extends StatelessWidget {
  final PlayerProfile profile;
  final VoidCallback onTap;
  const _LevelBanner({required this.profile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tier = profile.tier;
    return AppPanel(
      accent: kNeonCyan,
      hero: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: onTap,
      child: Row(
          children: [
            // Médaillon de niveau (couleur du palier)
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tier.color.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(color: tier.color, width: 1.5),
                boxShadow: [
                  BoxShadow(color: tier.color.withOpacity(0.5), blurRadius: 10),
                ],
              ),
              child: Text(
                '${profile.level}',
                style: TextStyle(
                  fontFamily: kArcadeFont,
                  color: tier.color,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'NIVEAU ${profile.level}',
                        style: const TextStyle(
                          fontFamily: kArcadeFont,
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          tier.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tier.color,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      children: [
                        Container(height: 8, color: AppColors.surfaceLight),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: profile.levelProgress),
                          duration: const Duration(milliseconds: 900),
                          curve: Curves.easeOutCubic,
                          builder: (context, v, _) => FractionallySizedBox(
                            widthFactor: v,
                            child: Container(
                              height: 8,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [kNeonPink, kNeonCyan],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right_rounded, color: kNeonCyan, size: 22),
          ],
        ),
    );
  }
}

class _MiniGamesEntry extends StatelessWidget {
  final VoidCallback onTap;
  const _MiniGamesEntry({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.arcadeViolet, AppColors.arcadePink],
          ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: softGlow(AppColors.arcadeViolet, blur: 18, opacity: 0.28),
        ),
        child: Row(
          children: [
            const Text('🎮', style: TextStyle(fontSize: 30)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('MINI-JEUX',
                      style: TextStyle(
                          fontFamily: kArcadeFont,
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1)),
                  SizedBox(height: 4),
                  Text('Zone d\'allure • Fractionné',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 24),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  const _SectionHeader({required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    final text = Text(title, style: AppText.screenTitle);
    if (action == null) return text;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [text, action!],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  // Pour un compteur animé : valeur numérique + décimales + suffixe
  final double? animateTo;
  final int fractionDigits;
  final String suffix;

  const _StatCard({
    required this.label,
    this.value = '',
    required this.icon,
    required this.iconColor,
    this.animateTo,
    this.fractionDigits = 0,
    this.suffix = '',
  });

  @override
  Widget build(BuildContext context) {
    const valueStyle = AppText.cardValue;

    return AppPanel(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.14),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, color: iconColor, size: 17),
          ),
          const SizedBox(height: 10),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: animateTo != null
                ? AnimatedCounter(
                    value: animateTo!,
                    fractionDigits: fractionDigits,
                    suffix: suffix,
                    style: valueStyle,
                  )
                : Text(value, style: valueStyle),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _LatestActivityCard extends StatelessWidget {
  final Activity activity;

  const _LatestActivityCard({required this.activity});

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.arcadePink.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.directions_run_rounded,
                        size: 14, color: AppColors.arcadePink),
                    SizedBox(width: 6),
                    Text(
                      'Running',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.arcadePink,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                _formatDate(activity.date),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            '${activity.distanceKm} km',
            style: const TextStyle(
              fontFamily: kArcadeFont,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              letterSpacing: 0.5,
              shadows: [Shadow(color: AppColors.arcadePink, blurRadius: 12)],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _InlineMetric(
                  label: 'Temps',
                  value: activity.durationFormatted,
                  unit: '',
                ),
              ),
              Container(
                width: 0.5,
                height: 32,
                color: AppColors.border,
                margin: const EdgeInsets.symmetric(horizontal: 14),
              ),
              Expanded(
                child: _InlineMetric(
                  label: 'Allure',
                  value: activity.avgPace,
                  unit: '/km',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Vitesse moyenne',
                  value: '${activity.avgSpeedKmh} km/h',
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: 'Boucles',
                  value: activity.lapCount.toString(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin',
      'Juil', 'Aoû', 'Sep', 'Oct', 'Nov', 'Déc'
    ];
    return '${months[date.month - 1]} ${date.day}';
  }
}

class _InlineMetric extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _InlineMetric({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              if (unit.isNotEmpty)
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
