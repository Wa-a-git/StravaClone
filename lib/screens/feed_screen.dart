// lib/screens/feed_screen.dart
// Fil d'activité : calendrier minimaliste + historique fusionné (courses +
// journées santé), du plus récent au plus ancien. Anciennement affiché en
// bas de l'onglet Santé — extrait dans son propre onglet pour que Santé se
// concentre sur "aujourd'hui" et que le Feed soit "ce qui s'est passé",
// comme un vrai fil d'activité plutôt qu'un journal.
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/activity.dart';
import '../models/daily_health_record.dart';
import '../models/health_snapshot.dart';
import '../providers/activity_provider.dart';
import '../providers/game_provider.dart';
import '../services/export_service.dart';
import '../services/game_service.dart';
import '../services/health_game_service.dart';
import '../services/health_store.dart';
import '../theme.dart';
import '../widgets/health_charts.dart';
import '../widgets/system_window.dart';
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
          // ── Quêtes santé (jour + semaine), réclamables → XP pool commun.
          // Vivent ici plutôt que dans le dashboard Santé : c'est l'aspect
          // jeu de l'app, qui a plus sa place dans le fil que noyé dans
          // l'état du jour. ──────────────────────────────────────────────
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: _QuestsCard(),
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
    switch (e.kind) {
      case _FeedKind.activity:
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
      case _FeedKind.sleep:
        final d = e.day!;
        return _FeedPost(
          icon: Icons.bedtime_rounded,
          time: _dayLabel(d.date),
          title: 'Sommeil',
          accent: kNeonViolet,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => HealthDayDetailScreen(record: d))),
          child: _SleepFeedContent(record: d),
        );
      case _FeedKind.dayStats:
        final d = e.day!;
        final highlight = dayHighlight(d);
        return _FeedPost(
          icon: Icons.query_stats_rounded,
          time: _dayLabel(d.date),
          title: 'Résumé du jour',
          accent: kNeonCyan,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => HealthDayDetailScreen(record: d))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (highlight != null) ...[
                Text(highlight,
                    style: const TextStyle(
                        color: kNeonCyan,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
              ],
              RawStatsRow(
                steps: d.steps,
                distanceKm: d.distanceKm,
                activeCalories: d.activeCalories,
              ),
            ],
          ),
        );
    }
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

// ── Historique fusionné (courses + sommeil + résumé du jour), trié du plus
// récent au plus ancien. Sommeil et résumé du jour sont deux posts distincts
// (pas fusionnés dans une même carte), même si les deux viennent du même
// DailyHealthRecord. ─────────────────────────────────────────────────────────
enum _FeedKind { activity, sleep, dayStats }

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

  _HistoryEntry.sleep(DailyHealthRecord d)
      : date = DateTime(d.date.year, d.date.month, d.date.day),
        sortTime = d.date,
        kind = _FeedKind.sleep,
        activity = null,
        day = d;

  _HistoryEntry.dayStats(DailyHealthRecord d)
      : date = DateTime(d.date.year, d.date.month, d.date.day),
        sortTime = d.date,
        kind = _FeedKind.dayStats,
        activity = null,
        day = d;
}

/// Fusionne courses, sommeil et résumé du jour en une seule liste triée du
/// plus récent au plus ancien — au sein d'une même journée : courses, puis
/// sommeil, puis résumé du jour. Le post sommeil n'existe que s'il y a
/// effectivement du sommeil enregistré ce jour-là.
List<_HistoryEntry> _buildHistoryEntries(
    List<Activity> activities, List<DailyHealthRecord> days) {
  final items = <_HistoryEntry>[
    for (final a in activities) _HistoryEntry.activity(a),
    for (final d in days) ...[
      if (d.sleep.totalAsleepMin > 0) _HistoryEntry.sleep(d),
      _HistoryEntry.dayStats(d),
    ],
  ];
  const rank = {_FeedKind.activity: 0, _FeedKind.sleep: 1, _FeedKind.dayStats: 2};
  items.sort((a, b) {
    final dayCmp = b.date.compareTo(a.date);
    if (dayCmp != 0) return dayCmp;
    if (a.kind != b.kind) return rank[a.kind]!.compareTo(rank[b.kind]!);
    return b.sortTime.compareTo(a.sortTime);
  });
  return items;
}

/// Ligne de mise en avant optionnelle pour la carte "Résumé du jour" — null
/// si rien n'est notable ce jour-là (pas de remplissage artificiel).
/// Compare FC repos et distance à la moyenne 7j (`HealthStore.baseline`,
/// aujourd'hui exclu) ; FC repos prioritaire si les deux qualifient. Seuils
/// calqués sur `HealthScoreService.insights` pour rester cohérent avec le
/// reste de l'app. Top-level (pas une méthode privée d'écran) pour rester
/// testable indépendamment de l'UI.
@visibleForTesting
String? dayHighlight(DailyHealthRecord d) {
  final rhrBaseline = HealthStore.baseline(HealthMetric.restingHeartRate, window: 7);
  if (d.restingHeartRate > 0 && rhrBaseline > 0) {
    final delta = d.restingHeartRate - rhrBaseline;
    if (delta <= -3) {
      return 'FC repos ${d.restingHeartRate.toStringAsFixed(0)} bpm — '
          '${delta.abs().toStringAsFixed(0)} bpm sous ta moyenne 7j';
    }
    if (delta >= 3) {
      return 'FC repos ${d.restingHeartRate.toStringAsFixed(0)} bpm — '
          '+${delta.toStringAsFixed(0)} bpm vs ta moyenne 7j';
    }
  }
  final distBaseline = HealthStore.baseline(HealthMetric.distanceKm, window: 7);
  if (d.distanceKm > 0 && distBaseline > 0) {
    final pct = (d.distanceKm - distBaseline) / distBaseline * 100;
    if (pct.abs() >= 30) {
      final sign = pct > 0 ? '+' : '';
      return 'Distance $sign${pct.toStringAsFixed(0)}% vs ta moyenne 7j';
    }
  }
  return null;
}

/// Contenu compact d'un post "sommeil" dans l'historique — n'existe que pour
/// les jours où du sommeil a été enregistré (voir _buildHistoryEntries).
class _SleepFeedContent extends StatelessWidget {
  final DailyHealthRecord record;
  const _SleepFeedContent({required this.record});

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

// ── Quêtes santé (jour + semaine), réclamables → XP pool commun ───────────────
class _QuestsCard extends ConsumerWidget {
  const _QuestsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final activities = ref.watch(activityListProvider);
    final todayRunKm = activities
        .where((a) =>
            a.date.year == now.year &&
            a.date.month == now.month &&
            a.date.day == now.day)
        .fold<double>(0, (s, a) => s + a.distanceKmValue);
    final weekStart = GameService.startOfWeek(now);
    final weekIntervalCount = activities
        .where((a) =>
            a.workoutType == 'interval' && !a.date.isBefore(weekStart))
        .length;
    final today = HealthStore.recordFor(now);
    final weekRecords =
        HealthStore.all().where((r) => !r.date.isBefore(weekStart)).toList();
    final dayKey = GameService.dayKey(now);
    final weekKey = GameService.weekKey(now);

    return _FeedPost(
      icon: Icons.emoji_events_rounded,
      time: 'AUJOURD\'HUI',
      title: 'Quêtes',
      accent: kNeonGreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelTitle('QUÊTES DU JOUR', color: kNeonGreen),
          const SizedBox(height: 10),
          _QuestsList(
            quests: HealthQuestService.daily(now),
            accent: kNeonGreen,
            today: today,
            weekRecords: const [],
            keyPrefix: dayKey,
            todayRunKm: todayRunKm,
            onClaim: (q) => _claim(context, ref, dayKey, q),
          ),
          const SizedBox(height: 4),
          const Divider(color: AppColors.border, height: 20),
          const PanelTitle('QUÊTES DE LA SEMAINE', color: kNeonPink),
          const SizedBox(height: 10),
          _QuestsList(
            quests: HealthQuestService.weekly(now),
            accent: kNeonPink,
            today: today,
            weekRecords: weekRecords,
            weekIntervalCount: weekIntervalCount,
            keyPrefix: weekKey,
            onClaim: (q) => _claim(context, ref, weekKey, q),
          ),
        ],
      ),
    );
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

    // Note quotidienne (vault) : l'aspect "jeu" de l'app remonte ici — XP
    // gagnée à chaque quête réclamée, passage de niveau si franchi depuis
    // la dernière réclamation. Fire-and-forget, best-effort (voir
    // ExportService.appendDailyNoteLine) : ne bloque jamais le claim déjà
    // confirmé à l'utilisateur ci-dessus.
    unawaited(ExportService.appendDailyNoteLine(
      section: 'Progression',
      line: '- 🎮 Quête réclamée : ${q.title} (+$added XP)',
    ));
    final profile = GameService.profileFor(ref.read(activityListProvider),
        bonusXp: GameStore.questBonusXp);
    if (await GameStore.checkLevelUp(profile.level)) {
      unawaited(ExportService.appendDailyNoteLine(
        section: 'Progression',
        line:
            '- 🎉 Passage au niveau ${profile.level} (${profile.tier.name}) !',
      ));
    }
  }
}

// ── Liste de quêtes réutilisable, sans carte englobante — appelée deux fois
// depuis _QuestsCard (quêtes du jour, quêtes de la semaine), qui fournit déjà
// sa propre carte/titre pour chaque section. ──────────────────────────────────
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
                        ? kNeonAmber
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
