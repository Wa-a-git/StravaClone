// lib/screens/feed_screen.dart
// Fil d'activité : calendrier minimaliste + historique fusionné (courses +
// journées santé), du plus récent au plus ancien. Anciennement affiché en
// bas de l'onglet Santé — extrait dans son propre onglet pour que Santé se
// concentre sur "aujourd'hui" et que le Feed soit "ce qui s'est passé",
// comme un vrai fil d'activité plutôt qu'un journal.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/exercise_library.dart' show ExerciseCategoryX;
import '../models/activity.dart';
import '../models/daily_health_record.dart';
import '../models/health_snapshot.dart';
import '../models/musculation_session.dart';
import '../providers/activity_provider.dart';
import '../providers/game_provider.dart';
import '../providers/health_provider.dart';
import '../services/health_game_service.dart';
import '../services/health_store.dart';
import '../services/meditation_store.dart';
import '../services/musculation_session_store.dart';
import '../services/musculation_store.dart';
import '../theme.dart';
import '../widgets/health_charts.dart';
import '../widgets/mascot_sprites.dart';
import '../widgets/ui_kit.dart';
import 'detail_screen.dart';
import 'health_dashboard_screen.dart' show RawStatsRow;
import 'health_history_screen.dart' show HealthDayDetailScreen;
import 'meditation_screen.dart';
import 'musculation_session_detail_screen.dart';
import 'sleep_detail_screen.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  // Une clé stable par entrée (id = type + jour + horodatage exact), pour
  // que le calendrier puisse faire défiler la liste jusqu'au bon post au
  // lieu de se contenter d'un simple affichage visuel. Conservées d'un
  // build à l'autre (contrairement à des GlobalKey créées à la volée dans
  // build(), qui casseraient le rattachement des éléments).
  final Map<String, GlobalKey> _entryKeys = {};

  GlobalKey _keyFor(_HistoryEntry e) {
    final id = '${e.kind.name}_${e.date.year}-${e.date.month}-${e.date.day}'
        '_${e.sortTime.millisecondsSinceEpoch}';
    return _entryKeys.putIfAbsent(id, () => GlobalKey());
  }

  void _scrollToDay(DateTime day, List<_HistoryEntry> entries) {
    for (final e in entries) {
      if (e.date != day) continue;
      final ctx = _keyFor(e).currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          alignment: 0.08,
        );
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final activities = ref.watch(activityListProvider);
    final days = HealthStore.all();
    ref.watch(musculationRevisionProvider);
    final musculationSessions = MusculationSessionStore.all();
    final entries = _buildHistoryEntries(activities, days, musculationSessions);

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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: const _WeighInCard(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: _FeedCalendar(
                activities: activities,
                days: days,
                onDayTap: (day) => _scrollToDay(day, entries),
              ),
            ),
          ),
          if (entries.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: EmptyState(
                  icon: Icons.dynamic_feed_rounded,
                  title: 'Rien pour l\'instant',
                  subtitle:
                      'Tes courses, séances et journées santé apparaîtront ici.',
                  accent: kNeonCyan,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              // Colonne non-virtualisée plutôt qu'un SliverList paresseux :
              // le calendrier doit pouvoir faire défiler jusqu'à une entrée
              // même très bas dans l'historique, ce qui exige que son
              // BuildContext existe déjà (Scrollable.ensureVisible ne peut
              // rien faire sur un item jamais construit hors viewport).
              // Volume raisonnable pour un journal personnel — pas de souci
              // de perf attendu.
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    for (final e in entries)
                      Padding(
                        key: _keyFor(e),
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _historyEntryPost(context, e),
                      ),
                  ],
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
      case _FeedKind.musculation:
        final s = e.musculationSession!;
        return _FeedPost(
          icon: Icons.fitness_center_rounded,
          time: _dayLabel(s.date),
          title: 'Séance musculation',
          accent: kNeonViolet,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(
                  builder: (_) => MusculationSessionDetailScreen(session: s))),
          child: _MusculationFeedContent(session: s),
        );
      case _FeedKind.sleep:
        final d = e.day!;
        return _FeedPost(
          icon: Icons.bedtime_rounded,
          time: _dayLabel(d.date),
          title: 'Sommeil',
          accent: kNeonViolet,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(
                  builder: (_) => SleepDetailScreen(initialDay: d.date))),
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

// ── Carte de pesée : point d'entrée pour saisir le poids depuis le Feed, et
// rappel visuel qui devient de plus en plus pressant plus la dernière pesée
// est ancienne — sans notification système (juste un état bien visible dès
// l'ouverture du Feed, l'onglet par défaut au lancement de l'app). ─────────
class _WeighInCard extends StatefulWidget {
  const _WeighInCard();

  @override
  State<_WeighInCard> createState() => _WeighInCardState();
}

class _WeighInCardState extends State<_WeighInCard> {
  DailyHealthRecord? _lastWeightRecord() {
    final days = HealthStore.all(); // trié du plus ancien au plus récent
    for (var i = days.length - 1; i >= 0; i--) {
      if (days[i].weightKg > 0) return days[i];
    }
    return null;
  }

  Future<void> _enterWeight() async {
    final ctrl = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Pesée du jour',
            style: TextStyle(
                fontFamily: kArcadeFont, color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(labelText: 'Poids', suffixText: 'kg'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kNeonGreen),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enregistrer', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final kg = double.tryParse(ctrl.text.replaceAll(',', '.'));
    if (kg == null || kg <= 0) return;
    await HealthStore.setManualWeightToday(kg);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final last = _lastWeightRecord();
    final daysSince = last == null ? null : today.difference(last.date).inDays;

    final urgent = daysSince == null || daysSince >= 2;
    final accent = urgent ? kNeonAmber : kNeonGreen;

    String message;
    if (last == null) {
      message = 'Aucun poids enregistré — pèse-toi pour démarrer le suivi.';
    } else if (daysSince == 0) {
      message = 'Poids du jour enregistré : ${last.weightKg.toStringAsFixed(1)} kg';
    } else if (daysSince == 1) {
      message = 'Dernière pesée hier (${last.weightKg.toStringAsFixed(1)} kg).';
    } else {
      message =
          'Pas pesé(e) depuis $daysSince jours — pèse-toi ce matin !';
    }

    return GestureDetector(
      onTap: _enterWeight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withOpacity(urgent ? 0.7 : 0.35),
              width: urgent ? 1.6 : 1),
          boxShadow: urgent
              ? [
                  BoxShadow(
                    color: accent.withOpacity(0.22),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(Icons.monitor_weight_rounded, color: accent, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: urgent ? FontWeight.w700 : FontWeight.w600,
                  color: urgent ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: accent, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── HUD d'arcade : résumé du jour en tête du Feed — score/niveau, sprite
// temporaire qui rebondit en continu (le vrai personnage prendra sa place
// plus tard, même mécanique d'animation), jauges Bio-Score/Pas, indicateurs
// du jour groupés par catégorie (Santé/Sport), et les quêtes du jour + de la
// semaine (réclamables → XP), qui vivent ici plutôt que dans une carte à
// part : c'est l'aspect jeu de l'app, à côté du personnage, pas noyé dans
// l'état du jour du dashboard Santé. Toutes les données affichées sont
// réelles — aucune stat inventée. ───────────────────────────────────────────
/// Humeur du mascot HUD — reflète l'état de santé réel du jour plutôt que
/// de tourner en boucle sur une seule pose. Priorité, du plus ponctuel/rare
/// au plus permanent : célébration (quêtes du jour bouclées) > fierté (série
/// de jours consécutifs) > contente-fatiguée (course déjà faite aujourd'hui)
/// > fatigue (alerte sommeil, à ne pas masquer) > méditation (état calme)
/// > course par défaut.
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

    final todayRunKm = activities
        .where((a) =>
            a.date.year == now.year &&
            a.date.month == now.month &&
            a.date.day == now.day)
        .fold<double>(0, (s, a) => s + a.distanceKmValue);
    final todayMusculationDone = MusculationStore.todayEntries().isNotEmpty;
    final todayMeditationSeconds = MeditationStore.todayEntries()
        .fold<int>(0, (s, e) => s + e.value.durationSeconds);

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
              ),
              _scene(pickMascotMood(
                scores: scores,
                todayMusculationDone: todayMusculationDone,
                runStreak: runStreak,
                todayRunKm: todayRunKm,
              )),
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
                  _HudChipData(
                    icon: Icons.self_improvement_rounded,
                    iconColor: kNeonCyan,
                    value: _hudFmtMeditation(todayMeditationSeconds),
                    label: 'Méditation',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MeditationScreen()),
                    ).then((_) {
                      if (mounted) setState(() {});
                    }),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                child: _TrainingTodayRow(
                  done: todayRunKm > 0 || todayMusculationDone,
                ),
              ),
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
        ],
      ),
    );
  }

  Widget _scene(MascotMood mood) {
    final (dir, prefix, frameCount) = kMascotSprites[mood]!;
    return SizedBox(
      height: 340,
      child: AnimatedBuilder(
        animation: _hop,
        builder: (context, child) {
          final t = _hop.value;
          final frame = (t * frameCount).floor() % frameCount + 1;
          return Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                bottom: 26,
                child: Container(
                  width: 76,
                  height: 16,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: RadialGradient(colors: [
                      Colors.black.withOpacity(0.4),
                      Colors.black.withOpacity(0),
                    ]),
                  ),
                ),
              ),
              Positioned(
                bottom: 30,
                child: Image.asset(
                  'assets/$dir/${prefix}_$frame.png',
                  height: 300,
                  filterQuality: FilterQuality.none,
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
    final chip = Container(
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
    if (c.onTap == null) return chip;
    return GestureDetector(onTap: c.onTap, child: chip);
  }
}

// ── Entraînement du jour : simple indicateur fait/pas fait (course ou
// musculation), sans mécanique de quête/réclamation — juste la question
// "j'ai bougé aujourd'hui ?". ────────────────────────────────────────────────
class _TrainingTodayRow extends StatelessWidget {
  final bool done;
  const _TrainingTodayRow({required this.done});

  @override
  Widget build(BuildContext context) {
    final color = done ? kNeonGreen : AppColors.textSecondary;
    return Row(
      children: [
        Icon(
          done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 8),
        Text(
          done ? 'Entraînement du jour fait' : 'Pas encore d\'entraînement aujourd\'hui',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: done ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _HudChipData {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final VoidCallback? onTap;
  const _HudChipData({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    this.onTap,
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

/// Format court pour la chip Méditation : minutes en dessous d'une heure
/// (la plupart des séances), sinon même format Xh0Y que Sommeil.
String _hudFmtMeditation(int totalSeconds) {
  if (totalSeconds <= 0) return '--';
  final totalMinutes = totalSeconds ~/ 60;
  if (totalMinutes < 60) return '${totalMinutes}min';
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
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
  final ValueChanged<DateTime> onDayTap;
  const _FeedCalendar(
      {required this.activities, required this.days, required this.onDayTap});

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
              return GestureDetector(
                onTap: () => widget.onDayTap(date),
                behavior: HitTestBehavior.opaque,
                child: Container(
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

// ── Historique fusionné (courses + musculation + sommeil + résumé du jour),
// trié du plus récent au plus ancien. Sommeil et résumé du jour sont deux
// posts distincts (pas fusionnés dans une même carte), même si les deux
// viennent du même DailyHealthRecord. ─────────────────────────────────────
enum _FeedKind { activity, musculation, sleep, dayStats }

class _HistoryEntry {
  final DateTime date; // jour civil, pour le regroupement/tri par journée
  final DateTime sortTime; // horodatage exact, pour l'ordre au sein d'un jour
  final _FeedKind kind;
  final Activity? activity;
  final DailyHealthRecord? day;
  final MusculationSession? musculationSession;

  _HistoryEntry.activity(Activity a)
      : date = DateTime(a.date.year, a.date.month, a.date.day),
        sortTime = a.date,
        kind = _FeedKind.activity,
        activity = a,
        day = null,
        musculationSession = null;

  _HistoryEntry.musculation(MusculationSession s)
      : date = DateTime(s.date.year, s.date.month, s.date.day),
        sortTime = s.date,
        kind = _FeedKind.musculation,
        activity = null,
        day = null,
        musculationSession = s;

  _HistoryEntry.sleep(DailyHealthRecord d)
      : date = DateTime(d.date.year, d.date.month, d.date.day),
        sortTime = d.date,
        kind = _FeedKind.sleep,
        activity = null,
        day = d,
        musculationSession = null;

  _HistoryEntry.dayStats(DailyHealthRecord d)
      : date = DateTime(d.date.year, d.date.month, d.date.day),
        sortTime = d.date,
        kind = _FeedKind.dayStats,
        activity = null,
        day = d,
        musculationSession = null;
}

/// Fusionne courses, musculation, sommeil et résumé du jour en une seule
/// liste triée du plus récent au plus ancien — au sein d'une même journée :
/// courses, puis musculation, puis sommeil, puis résumé du jour. Le post
/// sommeil n'existe que s'il y a effectivement du sommeil enregistré ce
/// jour-là.
List<_HistoryEntry> _buildHistoryEntries(
    List<Activity> activities,
    List<DailyHealthRecord> days,
    List<MusculationSession> musculationSessions) {
  final items = <_HistoryEntry>[
    for (final a in activities) _HistoryEntry.activity(a),
    for (final s in musculationSessions) _HistoryEntry.musculation(s),
    for (final d in days) ...[
      if (d.sleep.totalAsleepMin > 0) _HistoryEntry.sleep(d),
      _HistoryEntry.dayStats(d),
    ],
  ];
  const rank = {
    _FeedKind.activity: 0,
    _FeedKind.musculation: 1,
    _FeedKind.sleep: 2,
    _FeedKind.dayStats: 3,
  };
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

/// Contenu compact d'un post "musculation" dans l'historique — relit les
/// blocs de la séance via MusculationStore (l'enveloppe MusculationSession
/// ne duplique pas les séries, voir models/musculation_session.dart).
class _MusculationFeedContent extends StatelessWidget {
  final MusculationSession session;
  const _MusculationFeedContent({required this.session});

  @override
  Widget build(BuildContext context) {
    final sets = MusculationStore.entriesForSession(session.sessionId)
        .map((e) => e.value)
        .toList();
    final strengthSets = sets.where((e) => !e.category.isCardio).toList();
    final cardioSets = sets.where((e) => e.category.isCardio).toList();
    final totalVolume = strengthSets.fold<double>(0, (s, e) => s + e.volumeKg);
    final totalCardioDistance = cardioSets.fold<double>(0, (s, e) => s + e.distanceKm);
    final h = session.durationSeconds ~/ 3600;
    final m = (session.durationSeconds % 3600) ~/ 60;
    final duration = h > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '${m}m';
    final exerciseCount = sets.map((e) => e.exerciseName).toSet().length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(duration,
                style: const TextStyle(
                    fontFamily: kArcadeFont,
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900)),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                  '$exerciseCount exercice${exerciseCount > 1 ? 's' : ''} · ${sets.length} bloc${sets.length > 1 ? 's' : ''}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            if (totalVolume > 0)
              SleepLegend('Volume', '${totalVolume.toStringAsFixed(0)} kg', kNeonAmber),
            if (totalCardioDistance > 0)
              SleepLegend('Cardio', '${totalCardioDistance.toStringAsFixed(1)} km', kNeonGreen),
            if (session.hasHr)
              SleepLegend('FC moy.', '${session.avgHr.round()} bpm', kNeonPink),
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
