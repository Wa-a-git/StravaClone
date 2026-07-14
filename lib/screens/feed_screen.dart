// lib/screens/feed_screen.dart
// Fil d'activité : calendrier minimaliste + historique fusionné (courses +
// journées santé), du plus récent au plus ancien. Anciennement affiché en
// bas de l'onglet Santé — extrait dans son propre onglet pour que Santé se
// concentre sur "aujourd'hui" et que le Feed soit "ce qui s'est passé",
// comme un vrai fil d'activité plutôt qu'un journal.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/activity.dart';
import '../models/daily_health_record.dart';
import '../providers/activity_provider.dart';
import '../providers/game_provider.dart';
import '../providers/health_provider.dart';
import '../services/game_service.dart';
import '../services/health_game_service.dart';
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: const _ArcadeHudCard(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
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

// ── HUD d'arcade : résumé du jour en tête du Feed — score/niveau, sprite
// temporaire qui rebondit en continu (le vrai personnage prendra sa place
// plus tard, même mécanique d'animation), jauges Bio-Score/Pas, indicateurs
// du jour groupés par catégorie (Santé/Sport) et aperçu des quêtes du jour.
// Toutes les données affichées sont réelles — aucune stat inventée. ─────────
class _ArcadeHudCard extends ConsumerStatefulWidget {
  const _ArcadeHudCard();

  @override
  ConsumerState<_ArcadeHudCard> createState() => _ArcadeHudCardState();
}

class _ArcadeHudCardState extends ConsumerState<_ArcadeHudCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hop;

  @override
  void initState() {
    super.initState();
    _hop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    )..repeat();
  }

  @override
  void dispose() {
    _hop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final health = ref.watch(healthDataProvider);
    final profile = ref.watch(playerProfileProvider);
    final activities = ref.watch(activityListProvider);
    final now = DateTime.now();

    final scores = health.scores;
    final snapshot = health.snapshot;
    final bioScore = scores?.bioScore ?? 0;
    final steps = snapshot.steps;

    final todayRecord = HealthStore.recordFor(now);
    final dailyQuests = HealthQuestService.daily(now);
    final dayKey = GameService.dayKey(now);
    final questsDone = dailyQuests
        .where((q) =>
            HealthQuestService.current(q, todayRecord, const []) >= q.target)
        .length;

    final lastRun = activities.isNotEmpty ? activities.first : null;
    final runStreak = _hudRunStreak(activities);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kNeonPink.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
              color: kNeonPink.withOpacity(0.18),
              blurRadius: 40,
              offset: const Offset(0, 18)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1A0E2C), Color(0xFF150A24), Color(0xFF0F0819)],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.8),
                  radius: 1.1,
                  colors: [kNeonViolet.withOpacity(0.22), kNeonViolet.withOpacity(0)],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _topBar(
                healthXpToday: health.healthXpToday,
                level: profile.level,
                questsDone: questsDone,
                questsTotal: dailyQuests.length,
              ),
              _scene(),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Column(
                  children: [
                    _bar(
                      label: 'BIO-SCORE',
                      value: bioScore / 100,
                      valueText: '$bioScore/100',
                      colors: const [Color(0xFF1FBF5C), kNeonGreen],
                    ),
                    const SizedBox(height: 9),
                    _bar(
                      label: 'PAS',
                      value:
                          (steps / HealthGameService.stepsGoal).clamp(0.0, 1.0),
                      valueText: '${_hudFmtK(steps)}/10k',
                      colors: const [Color(0xFFC99400), kNeonAmber],
                    ),
                  ],
                ),
              ),
              _divider(),
              _section(
                label: 'Santé',
                color: kNeonViolet,
                perRow: 2,
                chips: [
                  _HudChipData(
                    icon: Icons.bedtime_rounded,
                    iconColor: kNeonViolet,
                    value: _hudFmtDuration(snapshot.sleep.totalAsleepMin),
                    label: 'Sommeil',
                  ),
                  // Méditation : pas encore de source de données (ni Health
                  // Connect, ni flux de log) — affiché en attente jusqu'à
                  // décision sur l'origine de la donnée.
                  const _HudChipData(
                    icon: Icons.self_improvement_rounded,
                    iconColor: kNeonCyan,
                    value: '--',
                    label: 'Méditation',
                  ),
                  _HudChipData(
                    icon: Icons.favorite_rounded,
                    iconColor: kNeonPink,
                    value: snapshot.restingHeartRate > 0
                        ? snapshot.restingHeartRate.round().toString()
                        : '--',
                    label: 'FC repos',
                  ),
                  _HudChipData(
                    icon: Icons.monitor_heart_rounded,
                    iconColor: kNeonCyan,
                    value:
                        snapshot.hrv > 0 ? snapshot.hrv.round().toString() : '--',
                    label: 'HRV',
                  ),
                ],
              ),
              _section(
                label: 'Sport',
                color: kNeonCyan,
                perRow: 3,
                chips: [
                  _HudChipData(
                    icon: Icons.local_fire_department_rounded,
                    iconColor: kNeonPink,
                    value: snapshot.activeCalories > 0
                        ? snapshot.activeCalories.toStringAsFixed(0)
                        : '--',
                    label: 'Kcal',
                  ),
                  _HudChipData(
                    icon: Icons.location_on_rounded,
                    iconColor: kNeonGreen,
                    value: lastRun != null ? '${lastRun.distanceKm} km' : '--',
                    label: 'Course',
                  ),
                  _HudChipData(
                    icon: Icons.local_fire_department_rounded,
                    iconColor: kNeonAmber,
                    value: runStreak > 0 ? '$runStreak j' : '--',
                    label: 'Série',
                  ),
                ],
              ),
              _divider(),
              _quests(dailyQuests, todayRecord, dayKey),
              const SizedBox(height: 14),
            ],
          ),
        ],
      ),
    );
  }

  Widget _topBar({
    required int healthXpToday,
    required int level,
    required int questsDone,
    required int questsTotal,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: healthXpToday.toDouble()),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => Text(
                    value.round().toString().padLeft(6, '0'),
                    style: const TextStyle(
                      fontFamily: kArcadeFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text('NIV. $level',
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: kNeonAmber)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.28),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Text(_hudDateLabel(DateTime.now()),
                style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: AppColors.textSecondary)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.28),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kNeonAmber.withOpacity(0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.emoji_events_rounded, size: 13, color: kNeonAmber),
                const SizedBox(width: 4),
                Text('$questsDone/$questsTotal',
                    style: const TextStyle(
                        fontFamily: kArcadeFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: kNeonAmber)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scene() {
    return SizedBox(
      height: 150,
      child: AnimatedBuilder(
        animation: _hop,
        builder: (context, child) {
          final t = _hop.value;
          final rise = 34.0 * math.sin(math.pi * t);
          // 1 = au sol (écrasement), -1 = pic du saut (étirement).
          final phase = math.cos(2 * math.pi * t);
          final scaleY = 1.0 - 0.18 * phase;
          final scaleX = 1.0 + 0.16 * phase;
          final shadowScale = (1.0 + 0.22 * phase).clamp(0.35, 1.3);
          final shadowOpacity = (0.5 - 0.16 * phase).clamp(0.15, 0.6);
          return Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                bottom: 26,
                child: Transform.scale(
                  scaleX: shadowScale,
                  child: Container(
                    width: 76,
                    height: 16,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: RadialGradient(colors: [
                        Colors.black.withOpacity(shadowOpacity),
                        Colors.black.withOpacity(0),
                      ]),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 30 + rise,
                child: Transform(
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.identity()..scale(scaleX, scaleY),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [kNeonPink, Color(0xFFC6187E)],
                      ),
                      boxShadow: [
                        BoxShadow(color: kNeonPink.withOpacity(0.55), blurRadius: 22),
                      ],
                    ),
                  ),
                ),
              ),
              const Positioned(
                bottom: 4,
                child: Text(
                  'sprite temporaire',
                  style: TextStyle(
                      fontSize: 8, letterSpacing: 0.6, color: AppColors.muted),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _bar({
    required String label,
    required double value,
    required String valueText,
    required List<Color> colors,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 62,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: AppColors.textSecondary)),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 12,
              color: Colors.black.withOpacity(0.4),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.clamp(0.0, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: LinearGradient(colors: colors)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 9),
        SizedBox(
          width: 74,
          child: Text(valueText,
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontFamily: kArcadeFont,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ),
      ],
    );
  }

  Widget _divider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [Colors.transparent, Colors.white.withOpacity(0.12), Colors.transparent]),
      ),
    );
  }

  Widget _section({
    required String label,
    required Color color,
    required int perRow,
    required List<_HudChipData> chips,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: color, blurRadius: 6)],
                ),
              ),
              const SizedBox(width: 6),
              Text(label.toUpperCase(),
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: color)),
            ],
          ),
          const SizedBox(height: 7),
          _chipGrid(chips, perRow),
        ],
      ),
    );
  }

  Widget _chipGrid(List<_HudChipData> chips, int perRow) {
    final rows = <Widget>[];
    for (var i = 0; i < chips.length; i += perRow) {
      final rowItems = chips.skip(i).take(perRow).toList();
      final slots = <Widget>[];
      for (var j = 0; j < perRow; j++) {
        if (j > 0) slots.add(const SizedBox(width: 6));
        slots.add(Expanded(
          child: j < rowItems.length ? _chip(rowItems[j]) : const SizedBox.shrink(),
        ));
      }
      rows.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
        child: Row(children: slots),
      ));
    }
    return Column(children: rows);
  }

  Widget _chip(_HudChipData c) {
    final noData = c.value == '--';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.26),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(c.icon, size: 14, color: noData ? AppColors.muted : c.iconColor),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(c.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: kArcadeFont,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: noData ? AppColors.muted : Colors.white)),
                Text(c.label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 7.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quests(
      List<HealthQuestDef> quests, DailyHealthRecord? today, String dayKey) {
    if (quests.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: kNeonAmber,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: kNeonAmber, blurRadius: 6)],
                ),
              ),
              const SizedBox(width: 6),
              const Text('QUÊTES DU JOUR',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: kNeonAmber)),
            ],
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < quests.length; i++) ...[
            if (i > 0)
              const Divider(height: 18, color: AppColors.border, thickness: 0.5),
            _questRow(quests[i], today, dayKey),
          ],
        ],
      ),
    );
  }

  Widget _questRow(HealthQuestDef q, DailyHealthRecord? today, String dayKey) {
    final current = HealthQuestService.current(q, today, const []);
    final claimed = GameStore.isClaimed('hq:$dayKey:${q.id}');
    final completed = current >= q.target;
    final fmt =
        q.unit == 'h' ? current.toStringAsFixed(1) : current.toStringAsFixed(0);
    final done = claimed || completed;
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? kNeonGreen : Colors.transparent,
            border: Border.all(color: done ? kNeonGreen : AppColors.border, width: 1.5),
          ),
          child: done ? const Icon(Icons.check_rounded, size: 13, color: Colors.black) : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(q.title,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: claimed ? AppColors.textSecondary : Colors.white,
                      decoration: claimed ? TextDecoration.lineThrough : null)),
              Text('$fmt/${q.target.toStringAsFixed(0)} ${q.unit}',
                  style: const TextStyle(fontSize: 10, color: AppColors.muted)),
            ],
          ),
        ),
        Text('+${q.reward} XP',
            style: const TextStyle(
                fontFamily: kArcadeFont,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: kNeonAmber)),
      ],
    );
  }
}

class _HudChipData {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  const _HudChipData({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });
}

String _hudFmtK(int steps) {
  if (steps >= 1000) {
    return '${(steps / 1000).toStringAsFixed(1).replaceAll('.', ',')}k';
  }
  return steps.toString();
}

String _hudFmtDuration(double minutes) {
  if (minutes <= 0) return '--';
  final h = minutes ~/ 60;
  final m = (minutes % 60).round();
  return '${h}h${m.toString().padLeft(2, '0')}';
}

String _hudDateLabel(DateTime d) {
  const months = [
    'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
    'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'
  ];
  return '${d.day} ${months[d.month - 1]}';
}

/// Jours consécutifs (terminant aujourd'hui ou hier) avec ≥ 5 km courus —
/// même logique que `_runStreak` dans health_dashboard_screen.dart, mais
/// dupliquée ici : la préfixe `_` rend ces fonctions privées à leur propre
/// fichier (bibliothèque Dart), pas partageables entre écrans.
int _hudRunStreak(List<Activity> activities) {
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
