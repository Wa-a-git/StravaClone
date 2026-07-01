import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/health_provider.dart';
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
                    const Center(child: CircularProgressIndicator(color: AppColors.arcadeCyan))
                  else if (!healthState.hasPermission)
                    _buildPermissionWarning(ref)
                  else
                    _buildHealthMetrics(healthState),
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

  Widget _buildHealthMetrics(HealthDataState state) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'Pas',
                value: state.steps.toString(),
                unit: 'pas',
                icon: Icons.do_not_step_rounded, // fallback icon
                color: AppColors.arcadeCyan,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: 'Calories',
                value: state.calories.toStringAsFixed(0),
                unit: 'kcal',
                icon: Icons.local_fire_department_rounded,
                color: AppColors.arcadePink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'Cœur (Moy)',
                value: state.avgHeartRate > 0 ? state.avgHeartRate.toStringAsFixed(0) : '--',
                unit: 'bpm',
                icon: Icons.favorite_rounded,
                color: AppColors.arcadeViolet,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: 'Sommeil',
                value: '--', // Will implement sleep later
                unit: 'h',
                icon: Icons.bedtime_rounded,
                color: Colors.blueAccent,
              ),
            ),
          ],
        )
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.10), blurRadius: 12),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontFamily: kArcadeFont,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontFamily: kArcadeFont,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  unit,
                  style: TextStyle(
                    fontSize: 14,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
