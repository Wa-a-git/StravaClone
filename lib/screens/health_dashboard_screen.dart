import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/health_snapshot.dart';
import '../providers/health_provider.dart';
import '../services/health_score_service.dart';
import '../theme.dart';
import '../widgets/arcade_fx.dart';

class HealthDashboardScreen extends ConsumerStatefulWidget {
  const HealthDashboardScreen({super.key});

  @override
  ConsumerState<HealthDashboardScreen> createState() => _HealthDashboardScreenState();
}

class _HealthDashboardScreenState extends ConsumerState<HealthDashboardScreen> {

  @override
  Widget build(BuildContext context) {
    final healthState = ref.watch(healthDataProvider);
    final scores = healthState.scores;

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
                icon: const Icon(Icons.refresh_rounded, color: AppColors.arcadeCyan),
                onPressed: () => ref.read(healthDataProvider.notifier).fetchDailyData(),
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
                  const SizedBox(height: 24),
                  if (healthState.isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                          child: CircularProgressIndicator(color: AppColors.arcadeCyan)),
                    )
                  else if (!healthState.hasPermission || scores == null)
                    _buildPermissionWarning(ref)
                  else ...[
                    _BioScorePanel(scores: scores),
                    const SizedBox(height: 16),
                    _SubScoresRow(scores: scores),
                    const SizedBox(height: 16),
                    _SleepPanel(sleep: healthState.snapshot.sleep, score: scores.sleepScore),
                    const SizedBox(height: 16),
                    _MetricsPanel(snapshot: healthState.snapshot),
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
        Text(
          'Données Fitbit',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
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

  Widget _buildPermissionWarning(WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.arcadePink),
      ),
      child: Column(
        children: [
          const Icon(Icons.health_and_safety, size: 48, color: AppColors.arcadePink),
          const SizedBox(height: 16),
          const Text(
            'Health Connect Requis',
            style: TextStyle(fontFamily: kArcadeFont, fontSize: 16, color: Colors.white),
          ),
          const SizedBox(height: 8),
          const Text(
            'Autorisez l\'accès aux données pour synchroniser votre Fitbit.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.arcadeCyan),
            onPressed: () => ref.read(healthDataProvider.notifier).fetchDailyData(),
            child: const Text('Autoriser l\'accès', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Panneau Bio-Score (score global, façon jauge d'arcade)
// ─────────────────────────────────────────────────────────────────────────────
class _BioScorePanel extends StatelessWidget {
  final HealthScores scores;
  const _BioScorePanel({required this.scores});

  @override
  Widget build(BuildContext context) {
    final tier = scores.tier;
    return _HPanel(
      accent: tier.color,
      child: Row(
        children: [
          _ScoreRing(score: scores.bioScore, color: tier.color, size: 100),
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
                const SizedBox(height: 4),
                const Text(
                  'Calculé à partir du sommeil, de la récupération\net de l\'activité du jour.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  final int score;
  final Color color;
  final double size;
  const _ScoreRing({required this.score, required this.color, this.size = 72});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: (score / 100).clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => CustomPaint(
          painter: _RingPainter(progress: v, color: color),
          child: Center(
            child: AnimatedCounter(
              value: score.toDouble(),
              style: TextStyle(
                fontFamily: kArcadeFont,
                color: color,
                fontSize: size * 0.28,
                fontWeight: FontWeight.w900,
                shadows: [Shadow(color: color, blurRadius: 10)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 6;
    const startAngle = -math.pi / 2;

    final bgPaint = Paint()
      ..color = AppColors.surfaceLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..shader = null;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      2 * math.pi * progress,
      false,
      fgPaint..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Ligne des 3 sous-scores
// ─────────────────────────────────────────────────────────────────────────────
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
            icon: Icons.bedtime_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SubScoreCard(
            label: 'RÉCUPÉRATION',
            score: scores.recoveryScore,
            color: kNeonCyan,
            icon: Icons.favorite_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SubScoreCard(
            label: 'ACTIVITÉ',
            score: scores.activityScore,
            color: kNeonGreen,
            icon: Icons.local_fire_department_rounded,
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
  final IconData icon;
  const _SubScoreCard({
    required this.label,
    required this.score,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(
            '$score',
            style: TextStyle(
              fontFamily: kArcadeFont,
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Panneau sommeil (répartition des phases)
// ─────────────────────────────────────────────────────────────────────────────
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
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 12),
          if (total <= 0)
            const Text(
              'Aucune donnée de sommeil trouvée pour cette nuit.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            )
          else ...[
            Text(
              _fmt(total),
              style: const TextStyle(
                fontFamily: kArcadeFont,
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text('Efficacité : ${sleep.efficiency.toStringAsFixed(0)}%',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
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
                        child: Container(color: kNeonViolet),
                      ),
                    if (sleep.remMin > 0)
                      Expanded(
                        flex: (sleep.remMin * 100).round().clamp(1, 1000000),
                        child: Container(color: kNeonCyan),
                      ),
                    if (sleep.lightMin > 0)
                      Expanded(
                        flex: (sleep.lightMin * 100).round().clamp(1, 1000000),
                        child: Container(color: AppColors.arcadeViolet.withOpacity(0.35)),
                      ),
                    if (sleep.awakeMin > 0)
                      Expanded(
                        flex: (sleep.awakeMin * 100).round().clamp(1, 1000000),
                        child: Container(color: AppColors.muted),
                      ),
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
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('$label $value',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Grille de métriques brutes
// ─────────────────────────────────────────────────────────────────────────────
class _MetricsPanel extends StatelessWidget {
  final HealthSnapshot snapshot;
  const _MetricsPanel({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final metrics = <_MetricData>[
      _MetricData('Pas', snapshot.steps.toString(), 'pas', Icons.directions_walk_rounded, kNeonGreen),
      _MetricData('Distance', snapshot.distanceKm.toStringAsFixed(2), 'km', Icons.map_rounded, kNeonGreen),
      _MetricData('Calories actives', snapshot.activeCalories.toStringAsFixed(0), 'kcal', Icons.local_fire_department_rounded, kNeonPink),
      _MetricData('Calories totales', snapshot.totalCalories.toStringAsFixed(0), 'kcal', Icons.whatshot_rounded, kNeonPink),
      _MetricData('Fréq. cardiaque', snapshot.avgHeartRate > 0 ? snapshot.avgHeartRate.toStringAsFixed(0) : '--', 'bpm', Icons.favorite_rounded, kNeonCyan),
      _MetricData('FC repos', snapshot.restingHeartRate > 0 ? snapshot.restingHeartRate.toStringAsFixed(0) : '--', 'bpm', Icons.favorite_border_rounded, kNeonCyan),
      _MetricData('SpO2', snapshot.spo2 > 0 ? snapshot.spo2.toStringAsFixed(0) : '--', '%', Icons.bloodtype_rounded, kNeonViolet),
      _MetricData('Respiration', snapshot.respiratoryRate > 0 ? snapshot.respiratoryRate.toStringAsFixed(1) : '--', 'rpm', Icons.air_rounded, kNeonViolet),
      _MetricData('HRV', snapshot.hrv > 0 ? snapshot.hrv.toStringAsFixed(0) : '--', 'ms', Icons.monitor_heart_rounded, kNeonCyan),
      _MetricData('Étages', snapshot.flightsClimbed.toString(), 'étages', Icons.stairs_rounded, const Color(0xFFFFC107)),
    ];

    return _HPanel(
      accent: kNeonCyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _HPanelTitle('MÉTRIQUES DU JOUR'),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: metrics
                .map((m) => SizedBox(
                      width: (MediaQuery.of(context).size.width - 32 - 36 - 20) / 2,
                      child: _MetricTile(data: m),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _MetricData {
  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  _MetricData(this.title, this.value, this.unit, this.icon, this.color);
}

class _MetricTile extends StatelessWidget {
  final _MetricData data;
  const _MetricTile({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: data.color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(data.icon, color: data.color, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  data.title.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                data.value,
                style: TextStyle(
                  fontFamily: kArcadeFont,
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  data.unit,
                  style: TextStyle(color: data.color, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cadre de panneau réutilisable (même style que system_screen.dart)
// ─────────────────────────────────────────────────────────────────────────────
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
