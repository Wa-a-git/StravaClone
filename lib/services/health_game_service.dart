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
