// lib/screens/history_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/activity.dart';
import '../providers/activity_provider.dart';
import 'detail_screen.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activities = ref.watch(activityListProvider);
    final notifier = ref.read(activityListProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: CustomScrollView(
        slivers: [
          // ── iOS large-title app bar ──────────────────────────────────────
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            backgroundColor: const Color(0xFFF2F2F7),
            elevation: 0,
            scrolledUnderElevation: 0,
            actions: [
              if (activities.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 16, top: 8),
                  child: GestureDetector(
                    onTap: () => _confirmClearAll(context, notifier),
                    child: const Text(
                      'Clear All',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
            flexibleSpace: const FlexibleSpaceBar(
              titlePadding: EdgeInsets.only(left: 20, bottom: 14),
              title: Text(
                'History',
                style: TextStyle(
                  color: Color(0xFF1C1C1E),
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.0,
                ),
              ),
              expandedTitleScale: 1.0,
            ),
          ),

          if (activities.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyState(),
            )
          else
            SliverPadding(
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                      (context, index) {
                    final activity = activities[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ActivityCard(
                        activity: activity,
                        index: activities.length - index,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                DetailScreen(activity: activity),
                          ),
                        ),
                        onDelete: () =>
                            _confirmDelete(context, activity, notifier),
                      ),
                    );
                  },
                  childCount: activities.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E5EA),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.directions_run_rounded,
              size: 40,
              color: Color(0xFF8E8E93),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No Activities Yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1C1C1E),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Start your first run to see it here.',
            style: TextStyle(
              fontSize: 15,
              color: Color(0xFF8E8E93),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context,
      Activity activity,
      ActivityListNotifier notifier,
      ) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E5EA),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Delete Activity?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1C1C1E),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'This action cannot be undone.',
              style: TextStyle(fontSize: 15, color: Color(0xFF8E8E93)),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Delete',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8E8E93),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) await notifier.deleteActivity(activity);
  }

  Future<void> _confirmClearAll(
      BuildContext context,
      ActivityListNotifier notifier,
      ) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E5EA),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Clear All Activities?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1C1C1E),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'All activities will be permanently deleted.',
              style: TextStyle(fontSize: 15, color: Color(0xFF8E8E93)),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Clear All',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8E8E93),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) await notifier.clearAll();
  }
}

// ── Activity Card ─────────────────────────────────────────────────────────────

class _ActivityCard extends StatelessWidget {
  final Activity activity;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ActivityCard({
    required this.activity,
    required this.index,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color:
                    const Color(0xFFFC4C02).withOpacity(0.1),
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
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onDelete,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F2F7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Distance (big)
            Text(
              '${activity.distanceKm} km',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1C1C1E),
                letterSpacing: -1,
              ),
            ),

            const SizedBox(height: 12),

            // Stats row
            Row(
              children: [
                _MiniStat(
                  label: 'Time',
                  value: activity.durationFormatted,
                ),
                Container(
                    width: 0.5,
                    height: 28,
                    color: const Color(0xFFE5E5EA),
                    margin: const EdgeInsets.symmetric(horizontal: 16)),
                _MiniStat(
                  label: 'Avg Pace',
                  value: '${activity.avgPace}/km',
                ),
                Container(
                    width: 0.5,
                    height: 28,
                    color: const Color(0xFFE5E5EA),
                    margin: const EdgeInsets.symmetric(horizontal: 16)),
                _MiniStat(
                  label: 'GPS pts',
                  value: activity.route.length.toString(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = date.hour > 12
        ? date.hour - 12
        : (date.hour == 0 ? 12 : date.hour);
    final amPm = date.hour >= 12 ? 'PM' : 'AM';
    final minute = date.minute.toString().padLeft(2, '0');
    return '${months[date.month - 1]} ${date.day}  •  $hour:$minute $amPm';
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1C1C1E),
            letterSpacing: -0.3,
          ),
        ),
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