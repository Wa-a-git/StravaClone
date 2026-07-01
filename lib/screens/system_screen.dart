// lib/screens/system_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/activity_provider.dart';
import '../providers/game_provider.dart';
import '../services/game_service.dart';
import '../widgets/arcade_fx.dart';
import '../widgets/system_window.dart';
import '../theme.dart';

class SystemScreen extends ConsumerWidget {
  const SystemScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(playerProfileProvider);
    final activities = ref.watch(activityListProvider);
    final now = DateTime.now();

    final weekActs = GameService.activitiesThisWeek(activities, now);
    final todayActs = GameService.activitiesToday(activities, now);
    final weeklyQuests = GameService.weeklyQuests(now);
    final dailyQuests = GameService.dailyQuests(now);
    final weekKey = GameService.weekKey(now);
    final dayKey = GameService.dayKey(now);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 110,
            pinned: true,
            backgroundColor: AppColors.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
            flexibleSpace: const FlexibleSpaceBar(
              titlePadding: EdgeInsets.only(left: 20, bottom: 14),
              title: Text(
                'PROGRESSION',
                style: TextStyle(
                  fontFamily: kArcadeFont,
                  color: kNeonCyan,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  shadows: [Shadow(color: kNeonCyan, blurRadius: 14)],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatusPanel(profile: profile),
                  const SizedBox(height: 18),
                  _StatsPanel(stats: profile.stats),
                  const SizedBox(height: 18),
                  _QuestsPanel(
                    title: 'QUÊTES DU JOUR',
                    accent: kNeonGreen,
                    quests: dailyQuests,
                    acts: todayActs,
                    keyPrefix: dayKey,
                    resetIn: _timeUntilMidnight(now),
                    onClaim: (q) => _claimQuest(context, ref, dayKey, q),
                  ),
                  const SizedBox(height: 18),
                  _QuestsPanel(
                    title: 'QUÊTES HEBDO',
                    accent: kNeonPink,
                    quests: weeklyQuests,
                    acts: weekActs,
                    keyPrefix: weekKey,
                    resetIn: _timeUntilWeekReset(now),
                    onClaim: (q) => _claimQuest(context, ref, weekKey, q),
                  ),
                  const SizedBox(height: 18),
                  _UnlocksPanel(level: profile.level),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _timeUntilMidnight(DateTime now) {
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final diff = tomorrow.difference(now);
    return '${diff.inHours}h ${diff.inMinutes % 60}min';
  }

  String _timeUntilWeekReset(DateTime now) {
    final nextMonday = GameService.startOfWeek(now).add(const Duration(days: 7));
    final diff = nextMonday.difference(now);
    final d = diff.inDays;
    final h = diff.inHours % 24;
    return d > 0 ? '${d}j ${h}h' : '${h}h';
  }

  Future<void> _claimQuest(
      BuildContext context, WidgetRef ref, String keyPrefix, QuestDef q) async {
    final uid = '$keyPrefix:${q.id}';
    final added = await GameStore.claim(uid, q.reward);
    if (added <= 0) return;
    ref.read(questBonusProvider.notifier).state = GameStore.questBonusXp;
    HapticFeedback.mediumImpact();
    if (context.mounted) {
      await showSystemWindow(
        context,
        heading: 'QUÊTE ACCOMPLIE',
        lines: [q.title, '+$added XP'],
        accent: kNeonGreen,
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Panneau de statut (niveau, palier, XP)
// ─────────────────────────────────────────────────────────────────────────────
class _StatusPanel extends StatelessWidget {
  final PlayerProfile profile;
  const _StatusPanel({required this.profile});

  @override
  Widget build(BuildContext context) {
    final tier = profile.tier;
    return _Panel(
      accent: kNeonCyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle('PROFIL'),
          const SizedBox(height: 16),
          Row(
            children: [
              _LevelMedallion(level: profile.level, color: tier.color),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tier.name,
                      style: TextStyle(
                        fontFamily: kArcadeFont,
                        color: tier.color,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        shadows: [Shadow(color: tier.color, blurRadius: 10)],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.nextTier != null
                          ? 'Palier suivant : ${profile.nextTier!.name} (niv. ${profile.nextTier!.minLevel})'
                          : 'Palier maximum atteint 🎉',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _XpBar(profile: profile),
        ],
      ),
    );
  }
}

class _LevelMedallion extends StatelessWidget {
  final int level;
  final Color color;
  const _LevelMedallion({required this.level, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
        boxShadow: [BoxShadow(color: color.withOpacity(0.6), blurRadius: 16)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'NIV',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          AnimatedCounter(
            value: level.toDouble(),
            style: TextStyle(
              fontFamily: kArcadeFont,
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              shadows: [Shadow(color: color, blurRadius: 10)],
            ),
          ),
        ],
      ),
    );
  }
}

class _XpBar extends StatelessWidget {
  final PlayerProfile profile;
  const _XpBar({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'EXPÉRIENCE',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            Text(
              '${profile.xpInLevel} / ${profile.xpForLevel} XP',
              style: const TextStyle(
                fontFamily: kArcadeFont,
                color: kNeonCyan,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            children: [
              Container(height: 14, color: AppColors.surfaceLight),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: profile.levelProgress),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => FractionallySizedBox(
                  widthFactor: v,
                  child: Container(
                    height: 14,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [kNeonPink, kNeonCyan],
                      ),
                      boxShadow: [BoxShadow(color: kNeonCyan, blurRadius: 10)],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Total : ${profile.totalXp} XP',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Panneau de stats
// ─────────────────────────────────────────────────────────────────────────────
class _StatsPanel extends StatelessWidget {
  final GameStats stats;
  const _StatsPanel({required this.stats});

  @override
  Widget build(BuildContext context) {
    final maxVal = [stats.force, stats.endurance, stats.agilite, stats.vitalite]
        .fold<int>(1, (m, v) => v > m ? v : m);
    return _Panel(
      accent: kNeonPink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle('CARACTÉRISTIQUES', color: kNeonPink),
          const SizedBox(height: 14),
          _StatRow(label: 'FORCE', sub: 'dénivelé', value: stats.force, max: maxVal, color: kNeonGreen),
          _StatRow(label: 'ENDURANCE', sub: 'distance', value: stats.endurance, max: maxVal, color: kNeonCyan),
          _StatRow(label: 'AGILITÉ', sub: 'allure', value: stats.agilite, max: maxVal, color: kNeonPink),
          _StatRow(label: 'VITALITÉ', sub: 'temps', value: stats.vitalite, max: maxVal, color: const Color(0xFFFFC107)),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String sub;
  final int value;
  final int max;
  final Color color;
  const _StatRow({
    required this.label,
    required this.sub,
    required this.value,
    required this.max,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: kArcadeFont,
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(sub,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 10)),
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Container(height: 10, color: AppColors.surfaceLight),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: (value / max).clamp(0.05, 1.0)),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => FractionallySizedBox(
                      widthFactor: v,
                      child: Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          boxShadow: [
                            BoxShadow(color: color.withOpacity(0.7), blurRadius: 8)
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 36,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: kArcadeFont,
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Panneau de quêtes (réutilisé pour quotidien & hebdo)
// ─────────────────────────────────────────────────────────────────────────────
class _QuestsPanel extends StatelessWidget {
  final String title;
  final Color accent;
  final List<QuestDef> quests;
  final List acts;
  final String keyPrefix;
  final String resetIn;
  final void Function(QuestDef) onClaim;

  const _QuestsPanel({
    required this.title,
    required this.accent,
    required this.quests,
    required this.acts,
    required this.keyPrefix,
    required this.resetIn,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _PanelTitle(title, color: accent),
              Row(
                children: [
                  const Icon(Icons.timer_outlined,
                      color: AppColors.textSecondary, size: 14),
                  const SizedBox(width: 4),
                  Text('Reset $resetIn',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...quests.map((q) {
            final current = GameService.questCurrent(q, acts.cast());
            final claimed = GameStore.isClaimed('$keyPrefix:${q.id}');
            final progress =
                QuestProgress(def: q, current: current, claimed: claimed);
            return _QuestTile(
                progress: progress, accent: accent, onClaim: () => onClaim(q));
          }),
        ],
      ),
    );
  }
}

class _QuestTile extends StatelessWidget {
  final QuestProgress progress;
  final Color accent;
  final VoidCallback onClaim;
  const _QuestTile(
      {required this.progress, required this.accent, required this.onClaim});

  @override
  Widget build(BuildContext context) {
    final q = progress.def;
    final fmt = q.unit == 'km'
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
                        ? const Color(0xFFFFC107)
                        : AppColors.textSecondary),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  q.title,
                  style: TextStyle(
                    color: progress.claimed
                        ? AppColors.textSecondary
                        : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    decoration:
                        progress.claimed ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              Text(
                '+${q.reward}',
                style: TextStyle(
                  fontFamily: kArcadeFont,
                  color: accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
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
              Text(
                '$fmt / $tgt ${q.unit}',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Panneau des déblocages
// ─────────────────────────────────────────────────────────────────────────────
class _UnlocksPanel extends StatelessWidget {
  final int level;
  const _UnlocksPanel({required this.level});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      accent: kNeonViolet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle('DÉBLOCAGES', color: kNeonViolet),
          const SizedBox(height: 14),
          ...kUnlocks.map((u) {
            final unlocked = level >= u.level;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    unlocked ? Icons.lock_open_rounded : Icons.lock_rounded,
                    color: unlocked ? kNeonGreen : AppColors.textSecondary,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          u.title,
                          style: TextStyle(
                            color: unlocked
                                ? Colors.white
                                : AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          u.description,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (unlocked ? kNeonGreen : AppColors.textSecondary)
                          .withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Niv.${u.level}',
                      style: TextStyle(
                        fontFamily: kArcadeFont,
                        color: unlocked ? kNeonGreen : AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cadre de panneau réutilisable
// ─────────────────────────────────────────────────────────────────────────────
class _Panel extends StatelessWidget {
  final Widget child;
  final Color accent;
  const _Panel({required this.child, required this.accent});

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

class _PanelTitle extends StatelessWidget {
  final String text;
  final Color color;
  const _PanelTitle(this.text, {this.color = kNeonCyan});

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
