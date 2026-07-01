import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/activity.dart';
import '../providers/activity_provider.dart';
import '../providers/game_provider.dart';
import '../services/export_service.dart';
import '../services/game_service.dart';
import '../widgets/arcade_fx.dart';
import '../widgets/ui_kit.dart';
import '../theme.dart';
import 'shell_screen.dart';
import 'mini_games_screen.dart';

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

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            backgroundColor: AppColors.surface,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
              title: const Text(
                'WA\'A STRAVA',
                style: TextStyle(
                  fontFamily: kArcadeFont,
                  color: AppColors.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                  shadows: [Shadow(color: AppColors.arcadePink, blurRadius: 12)],
                ),
              ),
              expandedTitleScale: 1.0,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.folder_open_rounded,
                    color: AppColors.textPrimary),
                tooltip: 'Dossier d\'export',
                onPressed: () async {
                  if (await Permission.manageExternalStorage.request().isGranted ||
                      await Permission.storage.request().isGranted) {
                    final selectedDir = await FilePicker.getDirectoryPath(
                      dialogTitle: 'Choisir le dossier d\'export',
                    );
                    if (selectedDir != null) {
                      await ExportService.saveExportDirectory(selectedDir);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Dossier d\'export mis à jour : $selectedDir'),
                          ),
                        );
                      }
                    }
                  }
                },
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildGreeting(allActivities.length),
                  const SizedBox(height: AppSpacing.xl),
                  _LevelBanner(
                    profile: ref.watch(playerProfileProvider),
                    onTap: () =>
                        ref.read(shellIndexProvider.notifier).state = 1,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SegmentedTabs<HomePeriod>(
                    values: HomePeriod.values,
                    selected: period,
                    labelOf: (p) => p.label,
                    onChanged: (p) =>
                        ref.read(homePeriodProvider.notifier).state = p,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _buildSummaryRow(count, totalDistanceKm, avgDistanceKm, avgSpeedKmh),
                  const SizedBox(height: AppSpacing.xxl),
                  _buildTrendChart(recentRuns),
                  const SizedBox(height: AppSpacing.xxl),
                  _buildPerformanceRow(avgPaceSeconds, bestPaceSeconds, longestDistanceKm, totalElevation),
                  const SizedBox(height: AppSpacing.xxl),
                  _MiniGamesEntry(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MiniGamesScreen()),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  if (allActivities.isNotEmpty) ...[
                    const _SectionHeader(title: 'Dernière sortie'),
                    const SizedBox(height: AppSpacing.md),
                    _LatestActivityCard(activity: allActivities.first),
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                  _buildMotivationCard(allActivities.length),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGreeting(int count) {
    final now = DateTime.now();
    const weekdays = [
      'Lundi',
      'Mardi',
      'Mercredi',
      'Jeudi',
      'Vendredi',
      'Samedi',
      'Dimanche'
    ];
    const months = [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre'
    ];

    final dayName = weekdays[now.weekday - 1];
    final dateStr = '${now.day} ${months[now.month - 1]}';

    return PageHeading(
      eyebrow: '$dayName · $dateStr',
      title: count == 0 ? 'Prêt pour ta prochaine course ?' : 'Ton tableau de bord',
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
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title, style: AppText.screenTitle);
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
