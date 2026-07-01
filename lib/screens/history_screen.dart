// lib/screens/history_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/activity.dart';
import '../providers/activity_provider.dart';
import '../services/export_service.dart';
import '../theme.dart';
import '../widgets/ui_kit.dart';
import 'detail_screen.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activities = ref.watch(activityListProvider);
    final notifier = ref.read(activityListProvider.notifier);

    // Classement all-time par distance → médailles pour le top 3
    final ranked = [...activities]
      ..sort((a, b) => b.distanceKmValue.compareTo(a.distanceKmValue));
    const medalEmojis = ['🥇', '🥈', '🥉'];
    final medals = <dynamic, String>{};
    for (var i = 0; i < ranked.length && i < 3; i++) {
      if (ranked[i].distanceKmValue > 0) {
        medals[ranked[i].key] = medalEmojis[i];
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            backgroundColor: AppColors.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
            actions: [
              if (activities.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 16, top: 8),
                  child: GestureDetector(
                    onTap: () => _confirmClearAll(context, notifier),
                    child: const Text(
                      'Tout effacer',
                      style: TextStyle(
                      color: Color(0xFFF55CBD),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
            flexibleSpace: const FlexibleSpaceBar(
              titlePadding: EdgeInsets.only(left: 20, bottom: 14),
              title: Text(
                'HIGH SCORES',
                style: TextStyle(
                  fontFamily: kArcadeFont,
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                  shadows: [Shadow(color: Color(0xFF00FFFF), blurRadius: 12)],
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
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: _HistorySummaryCard(activities: activities),
              ),
            ),
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
                        medal: medals[activity.key],
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                DetailScreen(activity: activity),
                          ),
                        ),
                        onDelete: () =>
                            _confirmDelete(context, activity, notifier),
                        onRename: () =>
                            _renameActivity(context, activity, notifier),
                        onExport: () async {
                          final path = await ExportService.saveActivityAsMarkdown(
                            activity,
                            useDownloads: true,
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                path != null
                                    ? 'Export .md créé : $path'
                                    : 'Impossible d’exporter le fichier Markdown.',
                              ),
                              duration: const Duration(seconds: 4),
                            ),
                          );
                        },
                      ),
                    );
                  },
                  childCount: activities.length,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const EmptyState(
      icon: Icons.directions_run_rounded,
      title: 'Aucune activité pour le moment',
      subtitle: 'Lance ta première sortie pour la voir ici.',
      accent: kNeonPink,
    );
  }

  Widget _HistorySummaryCard({required List<Activity> activities}) {
    final totalDistance = activities.fold<double>(0, (sum, activity) => sum + activity.distanceKmValue);
    final totalDuration = activities.fold<Duration>(Duration.zero, (sum, activity) => sum + Duration(seconds: activity.duration));
    final totalSeconds = totalDuration.inSeconds;
    // Allure moyenne réelle = temps total / distance totale (min/km), pas une moyenne de moyennes
    final averagePaceSeconds = totalDistance > 0 ? (totalSeconds / totalDistance).round() : 0;
    // Vitesse moyenne réelle = distance totale / temps total
    final averageSpeed = totalSeconds > 0 ? totalDistance / (totalSeconds / 3600) : 0.0;
    final totalElevation = activities.fold<double>(0, (sum, activity) => sum + activity.elevationGainValue);
    final activityCount = activities.length;

    return AppPanel(
      accent: kNeonPink,
      hero: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelTitle('RÉSUMÉ', color: kNeonPink),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SummaryValue(
                label: 'Total',
                value: '${totalDistance.toStringAsFixed(1)} km',
              ),
              _SummaryValue(
                label: 'Sorties',
                value: '$activityCount',
              ),
              _SummaryValue(
                label: 'Allure moy.',
                value: '${averagePaceSeconds ~/ 60}:${(averagePaceSeconds % 60).toString().padLeft(2, '0')} /km',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SummaryValue(
                label: 'Vitesse moy.',
                value: '${averageSpeed.toStringAsFixed(1)} km/h',
              ),
              _SummaryValue(
                label: 'Durée tot.',
                value: '${totalDuration.inHours}h ${totalDuration.inMinutes.remainder(60)}m',
              ),
              _SummaryValue(
                label: 'Dénivelé +',
                value: '${totalElevation.round()} m',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _SummaryValue({required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: kArcadeFont,
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Future<void> _renameActivity(
      BuildContext context,
      Activity activity,
      ActivityListNotifier notifier,
      ) async {
    final controller = TextEditingController(text: activity.name ?? '');
    final newName = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF141419),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF333333),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Renommer la course',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  shadows: [Shadow(color: Color(0xFF00FFFF), blurRadius: 8)],
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
                decoration: InputDecoration(
                  hintText: 'Nom de la course...',
                  hintStyle: const TextStyle(color: Color(0xFF555555)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1E1E24),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FFFF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Enregistrer',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (newName != null) {
      await notifier.renameActivity(activity, newName);
    }
  }

  Future<void> _confirmDelete(
      BuildContext context,
      Activity activity,
      ActivityListNotifier notifier,
      ) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF141419),
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
              color: const Color(0xFF333333),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Delete Activity?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                shadows: [Shadow(color: Color(0xFFF55CBD), blurRadius: 8)],
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'This action cannot be undone.',
              style: TextStyle(fontSize: 15, color: Color(0xFFAAAAAA)),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF003C),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Delete',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
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
                    color: Color(0xFF00FFFF),
                    shadows: [Shadow(color: Color(0xFF00FFFF), blurRadius: 5)],
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
      backgroundColor: const Color(0xFF141419),
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
              color: const Color(0xFF333333),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Clear All Activities?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                shadows: [Shadow(color: Color(0xFFF55CBD), blurRadius: 8)],
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'All activities will be permanently deleted.',
              style: TextStyle(fontSize: 15, color: Color(0xFFAAAAAA)),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF003C),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Clear All',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
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
                    color: Color(0xFF00FFFF),
                    shadows: [Shadow(color: Color(0xFF00FFFF), blurRadius: 5)],
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
  final String? medal;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onRename;
  final VoidCallback onExport;

  const _ActivityCard({
    required this.activity,
    required this.index,
    required this.medal,
    required this.onTap,
    required this.onDelete,
    required this.onRename,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.all(18),
      onTap: onTap,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row : identifiant + badge à gauche, actions à droite.
            // En Wrap pour ne jamais déborder (medal + badge + date + 3 boutons).
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Text(
                  '#$index',
                  style: const TextStyle(
                    fontFamily: kArcadeFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (medal != null)
                  Text(medal!, style: const TextStyle(fontSize: 16)),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color:
                    const Color(0xFFF55CBD).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.directions_run_rounded,
                          size: 13, color: Color(0xFFF55CBD)),
                      SizedBox(width: 4),
                      Text(
                        'Running',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF55CBD),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  _formatDate(activity.date),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFAAAAAA),
                  ),
                ),
                GestureDetector(
                  onTap: onRename,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E24),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.edit_rounded,
                      size: 14,
                      color: Color(0xFFF8FF00),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onExport,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E24),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.download_rounded,
                      size: 14,
                      color: Color(0xFF00FFFF),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onDelete,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E24),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: Color(0xFFFF003C),
                    ),
                  ),
                ),
              ],
            ),
            if (activity.name?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  activity.name!,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),

            const SizedBox(height: 14),

            // Distance (big)
            Text(
              '${activity.distanceKm} km',
              style: const TextStyle(
                fontFamily: kArcadeFont,
                fontSize: 25,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                shadows: [Shadow(color: Color(0xFFF55CBD), blurRadius: 12)],
                letterSpacing: 0.5,
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
                    color: const Color(0xFF333333),
                    margin: const EdgeInsets.symmetric(horizontal: 16)),
                _MiniStat(
                  label: 'Avg Pace',
                  value: '${activity.avgPace}/km',
                ),
                Container(
                    width: 0.5,
                    height: 28,
                    color: const Color(0xFF333333),
                    margin: const EdgeInsets.symmetric(horizontal: 16)),
                activity.hasElevation
                    ? _MiniStat(
                        label: 'Dénivelé +',
                        value: '${activity.elevationGain} m',
                      )
                    : _MiniStat(
                        label: 'GPS pts',
                        value: activity.route.length.toString(),
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
            color: Colors.white,
            letterSpacing: -0.3,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF00FFFF),
          ),
        ),
      ],
    );
  }
}