// lib/screens/feed_screen.dart
// Fil d'activité : calendrier minimaliste + historique fusionné (courses +
// journées santé), du plus récent au plus ancien. Anciennement affiché en
// bas de l'onglet Santé — extrait dans son propre onglet pour que Santé se
// concentre sur "aujourd'hui" et que le Feed soit "ce qui s'est passé",
// comme un vrai fil d'activité plutôt qu'un journal.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/activity.dart';
import '../models/daily_health_record.dart';
import '../providers/activity_provider.dart';
import '../services/health_store.dart';
import '../theme.dart';
import '../widgets/health_charts.dart';
import '../widgets/ui_kit.dart';
import 'detail_screen.dart';
import 'health_dashboard_screen.dart' show RawStatsRow;
import 'health_history_screen.dart' show HealthDayDetailScreen;

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activities = ref.watch(activityListProvider);
    final days = HealthStore.all();
    final entries = _buildHistoryEntries(activities, days);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 100,
            pinned: true,
            backgroundColor: AppColors.surface,
            elevation: 0,
            flexibleSpace: const FlexibleSpaceBar(
              titlePadding: EdgeInsets.only(left: 20, bottom: 16),
              title: Text(
                'FEED',
                style: TextStyle(
                  fontFamily: kArcadeFont,
                  color: AppColors.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  shadows: [Shadow(color: AppColors.arcadeCyan, blurRadius: 12)],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: _FeedCalendar(activities: activities, days: days),
            ),
          ),
          if (entries.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: EmptyState(
                  icon: Icons.dynamic_feed_rounded,
                  title: 'Rien pour l\'instant',
                  subtitle: 'Tes courses et tes journées santé apparaîtront ici.',
                  accent: kNeonCyan,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _historyEntryPost(context, entries[i]),
                  ),
                  childCount: entries.length,
                ),
              ),
            ),
        ],
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
}

// ── Calendrier minimaliste (façon plugin Calendar d'Obsidian) : un point par
// type d'événement présent ce jour-là (course, journée santé). Purement
// visuel/navigation temporelle — la liste en dessous reste la source de
// vérité de ce qui s'est passé. ─────────────────────────────────────────────
class _FeedCalendar extends StatefulWidget {
  final List<Activity> activities;
  final List<DailyHealthRecord> days;
  const _FeedCalendar({required this.activities, required this.days});

  @override
  State<_FeedCalendar> createState() => _FeedCalendarState();
}

class _FeedCalendarState extends State<_FeedCalendar> {
  late DateTime _month;

  static const _monthNames = [
    'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
    'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'
  ];
  static const _dow = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
  }

  void _shift(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final hasActivity = <DateTime, bool>{};
    for (final a in widget.activities) {
      hasActivity[DateTime(a.date.year, a.date.month, a.date.day)] = true;
    }
    final hasHealth = <DateTime, bool>{};
    for (final r in widget.days) {
      if (r.steps > 0 || r.totalSleepMin > 0 || r.bioScore > 0) {
        hasHealth[DateTime(r.date.year, r.date.month, r.date.day)] = true;
      }
    }

    final leadingBlanks = _month.weekday - 1; // lundi = 0
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final totalCells = ((leadingBlanks + daysInMonth) / 7).ceil() * 7;

    return AppPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _navArrow(Icons.chevron_left_rounded, () => _shift(-1)),
              Text(
                '${_monthNames[_month.month - 1]} ${_month.year}',
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
              ),
              _navArrow(Icons.chevron_right_rounded, () => _shift(1)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final d in _dow)
                Expanded(
                  child: Center(
                    child: Text(d,
                        style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: totalCells,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              childAspectRatio: 1.1,
            ),
            itemBuilder: (context, i) {
              final dayNum = i - leadingBlanks + 1;
              if (dayNum < 1 || dayNum > daysInMonth) {
                return const SizedBox.shrink();
              }
              final date = DateTime(_month.year, _month.month, dayNum);
              final isToday = date == today;
              final act = hasActivity[date] ?? false;
              final health = hasHealth[date] ?? false;
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: isToday ? kNeonCyan.withOpacity(0.16) : null,
                  border: isToday
                      ? Border.all(color: kNeonCyan, width: 1.2)
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$dayNum',
                      style: TextStyle(
                        color: isToday ? kNeonCyan : AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight:
                            isToday ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                    if (act || health) ...[
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (act) _dot(kNeonPink),
                          if (act && health) const SizedBox(width: 2),
                          if (health) _dot(kNeonViolet),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _navArrow(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, color: AppColors.textSecondary, size: 20),
      ),
    );
  }

  Widget _dot(Color color) => Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

// ── Historique fusionné (courses + journées santé), trié du plus récent au
// plus ancien. ───────────────────────────────────────────────────────────────
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

/// Contenu compact d'un post "résumé du jour" dans l'historique.
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
              SleepLegend('Profond', _fmt(sleep.deepMin), kNeonViolet),
              SleepLegend('Paradoxal', _fmt(sleep.remMin), kNeonCyan),
              SleepLegend('Léger', _fmt(sleep.lightMin), SleepStage.light.color),
              SleepLegend('Éveil', _fmt(sleep.awakeMin), AppColors.muted),
            ],
          ),
          const SizedBox(height: 14),
        ],
        RawStatsRow(
          steps: record.steps,
          distanceKm: record.distanceKm,
          activeCalories: record.activeCalories,
        ),
      ],
    );
  }
}

// ── Post de feed : en-tête (médaillon + heure + titre) et contenu dans une
// carte bordée façon réseau social. ─────────────────────────────────────────
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
    return AppPanel(
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

// ── Carte d'activité dans le feed ───────────────────────────────────────────
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
