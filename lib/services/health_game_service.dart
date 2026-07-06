// lib/services/health_game_service.dart
// Fusion santé ↔ moteur arcade : transforme les données santé en XP versée
// dans le MÊME pool que les courses et les quêtes (via GameStore), plus des
// quêtes santé et des streaks.
import '../models/daily_health_record.dart';
import '../models/health_snapshot.dart';
import 'game_service.dart';
import 'health_score_service.dart';

class HealthGameTuning {
  // Objectifs quotidiens
  static const int stepsGoal = 10000;
  static const double sleepGoalHours = 7.0;
  static const double activeCaloriesGoal = 500;
  static const int bioScoreGoal = 75;

  // XP par objectif atteint (versée une seule fois par jour)
  static const int xpSteps = 60;
  static const int xpSleep = 80;
  static const int xpCalories = 50;
  static const int xpBioScore = 90;
}

class HealthGameService {
  static const int stepsGoal = HealthGameTuning.stepsGoal;
  static const double sleepGoalHours = HealthGameTuning.sleepGoalHours;

  /// Verse (idempotent) l'XP santé du jour dans le pool commun GameStore, en
  /// fonction des objectifs atteints. Retourne le total d'XP santé attribué ce
  /// jour (déjà réclamé + nouveau), pour affichage.
  static Future<int> awardDailyXp(
    DateTime day,
    HealthScores scores,
    HealthSnapshot snapshot,
  ) async {
    final dayKey = DailyHealthRecord.keyFor(day);
    int total = 0;

    Future<void> tryAward(String goal, bool reached, int xp) async {
      final uid = 'health:$dayKey:$goal';
      if (!reached) return;
      // claim() est idempotent : ne verse qu'une fois, retourne 0 ensuite.
      final added = await GameStore.claim(uid, xp);
      total += xp; // compte l'objectif atteint (déjà réclamé ou non)
      // (added sert seulement à savoir si c'était nouveau)
      if (added < 0) return;
    }

    await tryAward('steps', snapshot.steps >= HealthGameTuning.stepsGoal,
        HealthGameTuning.xpSteps);
    await tryAward(
        'sleep',
        snapshot.sleep.totalAsleepMin >= HealthGameTuning.sleepGoalHours * 60,
        HealthGameTuning.xpSleep);
    await tryAward(
        'calories',
        snapshot.activeCalories >= HealthGameTuning.activeCaloriesGoal,
        HealthGameTuning.xpCalories);
    await tryAward('bio', scores.bioScore >= HealthGameTuning.bioScoreGoal,
        HealthGameTuning.xpBioScore);

    return total;
  }
}

// ── Quêtes santé ──────────────────────────────────────────────────────────────
enum HealthQuestMetric {
  dayRunKm,
  daySleepHours,
  dayActiveCalories,
  dayBioScore,
  weekSteps,
  weekSleepNights,
}

class HealthQuestDef {
  final String id;
  final String title;
  final HealthQuestMetric metric;
  final double target;
  final String unit;
  final int reward;
  const HealthQuestDef({
    required this.id,
    required this.title,
    required this.metric,
    required this.target,
    required this.unit,
    required this.reward,
  });

  bool get isWeekly =>
      metric == HealthQuestMetric.weekSteps ||
      metric == HealthQuestMetric.weekSleepNights;
}

class HealthQuestProgress {
  final HealthQuestDef def;
  final double current;
  final bool claimed;
  const HealthQuestProgress(
      {required this.def, required this.current, required this.claimed});

  bool get completed => current >= def.target;
  double get ratio =>
      def.target <= 0 ? 0 : (current / def.target).clamp(0.0, 1.0);
}

// Générateurs & évaluation (statiques via classe utilitaire).
class HealthQuestService {
  /// 2 quêtes du jour, l'une fixe + une tournante selon le jour.
  static List<HealthQuestDef> daily(DateTime now) {
    final dayIndex = DateTime(now.year, now.month, now.day)
            .millisecondsSinceEpoch ~/
        (24 * 3600 * 1000);

    HealthQuestDef rotating;
    switch (dayIndex % 3) {
      case 0:
        rotating = const HealthQuestDef(
          id: 'd_sleep',
          title: 'Dors au moins 7 h cette nuit',
          metric: HealthQuestMetric.daySleepHours,
          target: 7,
          unit: 'h',
          reward: 80,
        );
        break;
      case 1:
        rotating = const HealthQuestDef(
          id: 'd_cal',
          title: 'Brûle 500 kcal actives',
          metric: HealthQuestMetric.dayActiveCalories,
          target: 500,
          unit: 'kcal',
          reward: 70,
        );
        break;
      default:
        rotating = const HealthQuestDef(
          id: 'd_bio',
          title: 'Atteins un Bio-Score de 75',
          metric: HealthQuestMetric.dayBioScore,
          target: 75,
          unit: 'pts',
          reward: 90,
        );
    }

    return [
      const HealthQuestDef(
        id: 'd_run5k',
        title: 'Cours 5 km aujourd\'hui',
        metric: HealthQuestMetric.dayRunKm,
        target: 5.0,
        unit: 'km',
        reward: 60,
      ),
      rotating,
    ];
  }

  /// 2 quêtes hebdomadaires.
  static List<HealthQuestDef> weekly(DateTime now) {
    return const [
      HealthQuestDef(
        id: 'w_steps',
        title: 'Cumule 60 000 pas cette semaine',
        metric: HealthQuestMetric.weekSteps,
        target: 60000,
        unit: 'pas',
        reward: 220,
      ),
      HealthQuestDef(
        id: 'w_sleep',
        title: 'Dors ≥ 7 h sur 5 nuits',
        metric: HealthQuestMetric.weekSleepNights,
        target: 5,
        unit: 'nuits',
        reward: 240,
      ),
    ];
  }

  /// Valeur actuelle d'une quête à partir des enregistrements. [todayRunKm]
  /// vient d'une source séparée (activités GPS suivies, pas Health Connect) —
  /// voir HealthDashboardScreen où c'est calculé depuis activityListProvider.
  static double current(
    HealthQuestDef q,
    DailyHealthRecord? today,
    List<DailyHealthRecord> weekRecords, {
    double todayRunKm = 0,
  }) {
    switch (q.metric) {
      case HealthQuestMetric.dayRunKm:
        return todayRunKm;
      case HealthQuestMetric.daySleepHours:
        return (today?.totalSleepMin ?? 0) / 60.0;
      case HealthQuestMetric.dayActiveCalories:
        return today?.activeCalories ?? 0;
      case HealthQuestMetric.dayBioScore:
        return today?.bioScore.toDouble() ?? 0;
      case HealthQuestMetric.weekSteps:
        return weekRecords.fold<double>(0, (s, r) => s + r.steps);
      case HealthQuestMetric.weekSleepNights:
        return weekRecords
            .where((r) => r.totalSleepMin >= 7 * 60)
            .length
            .toDouble();
    }
  }
}
