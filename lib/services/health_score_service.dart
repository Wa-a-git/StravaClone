// lib/services/health_score_service.dart
// Moteur de scores santé "maison" : on ne dépend d'aucun score propriétaire
// (Fitbit Readiness/Stress nécessitent une API + Premium). On calcule tout
// nous-mêmes à partir des données brutes Health Connect.
import 'package:flutter/material.dart';
import '../models/health_snapshot.dart';
import '../models/daily_health_record.dart';
import '../theme.dart';

double _clamp(double v) => v.clamp(0.0, 100.0);

/// Direction d'une tendance vs baseline (couche logique, consommée par l'UI).
enum TrendDir { up, down, flat }

/// Résultat d'une analyse de tendance pour une métrique.
class TrendInfo {
  final TrendDir dir;
  final double delta; // valeur actuelle - baseline
  final bool good; // la direction est-elle favorable ?
  final String label; // ex : "+3", "-0.4 km"
  const TrendInfo({
    required this.dir,
    required this.delta,
    required this.good,
    required this.label,
  });

  static const flat = TrendInfo(
      dir: TrendDir.flat, delta: 0, good: true, label: '—');
}

/// Un insight lisible (texte + accent + icône) pour le panneau d'analyse.
/// [id] est stable par catégorie (ex : 'rhr_high') pour permettre le feedback
/// (masquer un insight jugé inutile).
class HealthInsight {
  final String id;
  final String text;
  final Color color;
  final IconData icon;
  const HealthInsight(this.id, this.text, this.color, this.icon);
}

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

  // ── Tendances ──────────────────────────────────────────────────────────────

  /// Compare une valeur courante à une baseline et produit une tendance.
  /// [threshold] est la variation minimale (en unités de la métrique) pour ne
  /// pas considérer la tendance comme « stable ».
  static TrendInfo trend(
    HealthMetric metric,
    double current,
    double baseline, {
    double threshold = 0,
    String unit = '',
    int fractionDigits = 0,
  }) {
    if (baseline <= 0 || current <= 0) return TrendInfo.flat;
    final delta = current - baseline;
    final minChange = threshold > 0 ? threshold : baseline * 0.03;
    if (delta.abs() < minChange) return TrendInfo.flat;

    final dir = delta > 0 ? TrendDir.up : TrendDir.down;
    // « bon » = va dans le sens favorable de la métrique
    final good = metric.lowerIsBetter ? delta < 0 : delta > 0;
    final sign = delta > 0 ? '+' : '';
    final label = '$sign${delta.toStringAsFixed(fractionDigits)}$unit';
    return TrendInfo(dir: dir, delta: delta, good: good, label: label);
  }

  // ── Insights générés ───────────────────────────────────────────────────────

  /// Analyse le dernier jour vs les baselines et produit des observations
  /// courtes et actionnables.
  static List<HealthInsight> insights({
    required DailyHealthRecord today,
    required double rhrBaseline,
    required double hrvBaseline,
    required double sleepBaselineHours,
    required int stepsStreak,
    required int sleepStreak,
  }) {
    final out = <HealthInsight>[];

    // FC repos
    if (today.restingHeartRate > 0 && rhrBaseline > 0) {
      final d = today.restingHeartRate - rhrBaseline;
      if (d >= 3) {
        out.add(HealthInsight(
            'rhr_high',
            'FC repos +${d.toStringAsFixed(0)} bpm vs ta moyenne 7j : récupération à surveiller.',
            kNeonPink,
            Icons.favorite_border_rounded));
      } else if (d <= -3) {
        out.add(HealthInsight(
            'rhr_low',
            'FC repos -${d.abs().toStringAsFixed(0)} bpm vs 7j : bonne récupération.',
            kNeonGreen,
            Icons.favorite_rounded));
      }
    }

    // HRV
    if (today.hrv > 0 && hrvBaseline > 0) {
      final ratio = today.hrv / hrvBaseline;
      if (ratio >= 1.1) {
        out.add(HealthInsight(
            'hrv_high',
            'HRV au-dessus de ta moyenne : ton corps est bien reposé.',
            kNeonGreen,
            Icons.monitor_heart_rounded));
      } else if (ratio <= 0.85) {
        out.add(HealthInsight(
            'hrv_low',
            'HRV basse aujourd\'hui : privilégie une séance légère.',
            const Color(0xFFFFC107),
            Icons.monitor_heart_rounded));
      }
    }

    // Sommeil
    final sleepH = today.totalSleepMin / 60.0;
    if (sleepH > 0) {
      if (sleepH < 6.5) {
        out.add(HealthInsight(
            'sleep_short',
            'Nuit courte (${sleepH.toStringAsFixed(1)} h) : vise 7-8 h pour recharger.',
            const Color(0xFFFFC107),
            Icons.bedtime_rounded));
      } else if (sleepH >= 7.5) {
        out.add(HealthInsight(
            'sleep_good',
            'Belle nuit de ${sleepH.toStringAsFixed(1)} h : sommeil optimal.',
            kNeonViolet,
            Icons.bedtime_rounded));
      }
    }

    // Streaks
    if (sleepStreak >= 3) {
      out.add(HealthInsight(
          'streak_sleep',
          'Série sommeil ≥ 7 h : $sleepStreak jours d\'affilée 🔥',
          kNeonViolet,
          Icons.local_fire_department_rounded));
    }
    if (stepsStreak >= 3) {
      out.add(HealthInsight(
          'streak_steps',
          'Série 10k pas : $stepsStreak jours d\'affilée 🔥',
          kNeonGreen,
          Icons.local_fire_department_rounded));
    }

    if (out.isEmpty) {
      out.add(const HealthInsight(
          'empty',
          'Continue à enregistrer tes journées : les analyses s\'affinent avec l\'historique.',
          AppColors.textSecondary,
          Icons.insights_rounded));
    }
    return out;
  }
}
