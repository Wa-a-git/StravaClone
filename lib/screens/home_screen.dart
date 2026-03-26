// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/activity.dart';
import '../providers/activity_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activities = ref.watch(activityListProvider);
    final count = activities.length;

    // Compute totals
    final totalDistanceKm = activities.fold<double>(
      0.0,
          (sum, a) => sum + a.distance / 1000,
    );
    final totalDurationMin = activities.fold<int>(
      0,
          (sum, a) => sum + a.duration ~/ 60,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: CustomScrollView(
        slivers: [
          // ── iOS large-title style app bar ────────────────────────────────
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            backgroundColor: const Color(0xFFF2F2F7),
            elevation: 0,
            scrolledUnderElevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding:
              const EdgeInsets.only(left: 20, bottom: 14),
              title: const Text(
                'Strava',
                style: TextStyle(
                  color: Color(0xFF1C1C1E),
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.0,
                ),
              ),
              expandedTitleScale: 1.0,
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16, top: 8),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFC4C02),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.directions_run_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Greeting ──────────────────────────────────────────────
                  _buildGreeting(count),
                  const SizedBox(height: 20),

                  // ── Stats row ─────────────────────────────────────────────
                  _buildStatsRow(
                      count, totalDistanceKm, totalDurationMin),
                  const SizedBox(height: 20),

                  // ── Recent run card ───────────────────────────────────────
                  if (activities.isNotEmpty) ...[
                    _SectionHeader(title: 'Latest Activity'),
                    const SizedBox(height: 10),
                    _LatestActivityCard(activity: activities.first),
                    const SizedBox(height: 20),
                  ],

                  // ── Motivational banner ───────────────────────────────────
                  _buildMotivationCard(count),
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
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final dayName = days[now.weekday - 1];
    final dateStr = '${months[now.month - 1]} ${now.day}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$dayName, $dateStr',
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF8E8E93),
            fontWeight: FontWeight.w400,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          count == 0 ? 'Start your journey.' : "You've got this.",
          style: const TextStyle(
            fontSize: 22,
            color: Color(0xFF1C1C1E),
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow(
      int count, double totalKm, int totalMin) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Runs',
            value: count.toString(),
            icon: Icons.flag_rounded,
            iconColor: const Color(0xFFFC4C02),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Total km',
            value: totalKm.toStringAsFixed(1),
            icon: Icons.route_rounded,
            iconColor: const Color(0xFF30D158),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Minutes',
            value: totalMin.toString(),
            icon: Icons.timer_rounded,
            iconColor: const Color(0xFF0A84FF),
          ),
        ),
      ],
    );
  }

  Widget _buildMotivationCard(int count) {
    final (emoji, title, sub) = count == 0
        ? ('🏃', 'Every run starts with one step.', '')
        : count < 5
        ? ('🔥', 'Building the habit.', 'Consistency beats intensity.')
        : ('💪', 'You\'re on a streak.', 'Keep showing up.');

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF5A1F), Color(0xFFE63D00)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFC4C02).withOpacity(0.38),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            // Decorative circle — top right
            Positioned(
              top: -20,
              right: -20,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // Decorative circle — bottom left
            Positioned(
              bottom: -28,
              left: -16,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  shape: BoxShape.circle,
                ),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(emoji,
                          style: const TextStyle(fontSize: 26)),
                    ),
                  ),
                  const SizedBox(width: 16),
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
                            letterSpacing: -0.3,
                            height: 1.3,
                          ),
                        ),
                        if (sub.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            sub,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.72),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ],
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
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1C1C1E),
        letterSpacing: -0.5,
      ),
    );
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1C1C1E),
              letterSpacing: -0.5,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF8E8E93),
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Latest activity card ──────────────────────────────────────────────────────

class _LatestActivityCard extends StatelessWidget {
  final Activity activity;

  const _LatestActivityCard({required this.activity});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFC4C02).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.directions_run_rounded,
                        size: 13, color: Color(0xFFFC4C02)),
                    SizedBox(width: 4),
                    Text(
                      'Running',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFC4C02),
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
                  color: Color(0xFF8E8E93),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _InlineMetric(
                  label: 'Distance',
                  value: '${activity.distanceKm}',
                  unit: 'km',
                ),
              ),
              Container(
                  width: 0.5,
                  height: 36,
                  color: const Color(0xFFE5E5EA)),
              Expanded(
                child: _InlineMetric(
                  label: 'Time',
                  value: activity.durationFormatted,
                  unit: '',
                ),
              ),
              Container(
                  width: 0.5,
                  height: 36,
                  color: const Color(0xFFE5E5EA)),
              Expanded(
                child: _InlineMetric(
                  label: 'Pace',
                  value: activity.avgPace,
                  unit: '/km',
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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}';
  }
}

class _InlineMetric extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _InlineMetric(
      {required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1C1C1E),
                  letterSpacing: -0.5,
                ),
              ),
              if (unit.isNotEmpty)
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF8E8E93),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF8E8E93),
          ),
        ),
      ],
    );
  }
}