// lib/services/health_score_service.dart
// Moteur de scores santé "maison" : on ne dépend d'aucun score propriétaire
// (Fitbit Readiness/Stress nécessitent une API + Premium). On calcule tout
// nous-mêmes à partir des données brutes Health Connect.
import 'package:flutter/material.dart';
import '../models/health_snapshot.dart';
import '../theme.dart';

double _clamp(double v) => v.clamp(0.0, 100.0);

class HealthTier {
  final String name;
  final Color color;
  final int minScore;
  const HealthTier(this.name, this.color, this.minScore);
}

const List<HealthTier> kHealthTiers = [
  HealthTier('Critique', kNeonPink, 0),
  HealthTier('Instable', Color(0xFFFFC107), 40),
  HealthTier('Stable', kNeonCyan, 60),
  HealthTier('Optimal', kNeonGreen, 75),
  HealthTier('Pic de Forme', kNeonViolet, 90),
];

class HealthScores {
  final int sleepScore;
  final int recoveryScore;
  final int activityScore;
  final int bioScore;
  final HealthTier tier;

  const HealthScores({
    required this.sleepScore,
    required this.recoveryScore,
    required this.activityScore,
    required this.bioScore,
    required this.tier,
  });
}

class HealthScoreTuning {
  static const double sleepTargetHours = 8.0;
  static const double idealDeepRatio = 0.20;
  static const double idealRemRatio = 0.25;

  static const double stepsGoal = 10000;
  static const double activeCaloriesGoal = 500;
  static const double flightsGoal = 10;
}

class HealthScoreService {
  static HealthTier tierFor(int score) {
    HealthTier result = kHealthTiers.first;
    for (final t in kHealthTiers) {
      if (score >= t.minScore) result = t;
    }
    return result;
  }

  // ── Score de sommeil ──────────────────────────────────────────────────────
  static int sleepScore(SleepBreakdown sleep) {
    if (sleep.totalAsleepMin <= 0) return 0;

    final hours = sleep.totalAsleepMin / 60.0;
    final durationScore =
        _clamp(100 - (hours - HealthScoreTuning.sleepTargetHours).abs() * 20);

    final deepRatio = sleep.deepMin / sleep.totalAsleepMin;
    final remRatio = sleep.remMin / sleep.totalAsleepMin;
    final stageScore = _clamp(100 -
        ((deepRatio - HealthScoreTuning.idealDeepRatio).abs() +
                (remRatio - HealthScoreTuning.idealRemRatio).abs()) *
            150);

    final efficiencyScore = _clamp(sleep.efficiency);

    return (durationScore * 0.5 + stageScore * 0.3 + efficiencyScore * 0.2)
        .round();
  }

  // ── Score de récupération (FC repos + HRV vs moyenne des 7 derniers jours) ──
  static int recoveryScore(HealthSnapshot s) {
    double hrScore = 60; // valeur neutre si pas de baseline
    if (s.restingHeartRateBaseline > 0 && s.restingHeartRate > 0) {
      final delta = s.restingHeartRate - s.restingHeartRateBaseline;
      hrScore = _clamp(100 - delta * 6);
    } else if (s.restingHeartRate > 0) {
      // Pas de baseline : on juge sur une échelle absolue (40-80 bpm).
      hrScore = _clamp(100 - (s.restingHeartRate - 55).clamp(0, 40) * 2.5);
    }

    double hrvScore = 60;
    if (s.hrvBaseline > 0 && s.hrv > 0) {
      hrvScore = _clamp((s.hrv / s.hrvBaseline) * 100);
    } else if (s.hrv > 0) {
      hrvScore = _clamp((s.hrv / 50.0) * 100);
    }

    return (hrScore * 0.5 + hrvScore * 0.5).round();
  }

  // ── Score d'activité ───────────────────────────────────────────────────────
  static int activityScore(HealthSnapshot s) {
    final stepsScore = _clamp(s.steps / HealthScoreTuning.stepsGoal * 100);
    final caloriesScore =
        _clamp(s.activeCalories / HealthScoreTuning.activeCaloriesGoal * 100);
    final flightsScore =
        _clamp(s.flightsClimbed / HealthScoreTuning.flightsGoal * 100);

    return (stepsScore * 0.5 + caloriesScore * 0.35 + flightsScore * 0.15)
        .round();
  }

  // ── Bio-score global ───────────────────────────────────────────────────────
  static HealthScores computeAll(HealthSnapshot s) {
    final sleep = sleepScore(s.sleep);
    final recovery = recoveryScore(s);
    final activity = activityScore(s);
    final bio = (sleep * 0.35 + recovery * 0.35 + activity * 0.30).round();

    return HealthScores(
      sleepScore: sleep,
      recoveryScore: recovery,
      activityScore: activity,
      bioScore: bio,
      tier: tierFor(bio),
    );
  }
}
