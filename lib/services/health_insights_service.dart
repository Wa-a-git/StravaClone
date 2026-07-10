import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/daily_health_record.dart';
import '../theme.dart';
import 'health_score_service.dart' show HealthInsight;

/// Indicateurs dérivés supplémentaires — distincts des scores 0-100 de
/// `HealthScoreService` (données brutes/statistiques plutôt qu'un score
/// composite) et du détecteur d'insights ponctuels existant, qu'on complète
/// ici avec une alerte croisant plusieurs signaux à la fois. Fonctions pures,
/// testables sans Hive ni Health Connect (l'appelant passe l'historique déjà
/// lu via `HealthStore`).
class HealthInsightsService {
  /// Nombre minimal de jours d'historique pour qu'un z-score soit défendable.
  static const int minHistoryForZScore = 5;

  /// Écart-type de la VFC du jour par rapport à sa moyenne sur l'historique
  /// fourni (typiquement les 30 derniers jours, aujourd'hui exclu). Proche de
  /// 0 = normal, très négatif = système nerveux sous tension. Null si moins
  /// de 5 jours de données ou écart-type nul (pas de variance à comparer).
  static double? hrvZScore(double todayHrv, List<double> historyHrv) {
    if (todayHrv <= 0) return null;
    final valid = historyHrv.where((v) => v > 0).toList();
    if (valid.length < minHistoryForZScore) return null;
    final mean = valid.reduce((a, b) => a + b) / valid.length;
    final variance =
        valid.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            valid.length;
    final stddev = math.sqrt(variance);
    if (stddev < 1e-9) return null;
    return (todayHrv - mean) / stddev;
  }

  /// Part du sommeil total passée en phase profonde (0..1). Null si aucun
  /// sommeil enregistré ce jour-là.
  static double? deepSleepRatio(DailyHealthRecord r) {
    final total = r.totalSleepMin;
    if (total <= 0) return null;
    return r.sleepDeepMin / total;
  }

  /// Cumul, sur les jours fournis (typiquement les 7 derniers jours avec
  /// données), de l'écart entre le sommeil réel et l'objectif nocturne.
  /// Positif = dette accumulée, négatif = surplus. Les jours sans sommeil
  /// enregistré sont ignorés (pas de dette artificielle sur une absence de
  /// donnée plutôt qu'une vraie nuit courte).
  static double sleepDebtHours(
    List<DailyHealthRecord> days, {
    double targetHoursPerNight = 8.0,
  }) {
    double debt = 0;
    for (final d in days) {
      if (d.totalSleepMin <= 0) continue;
      debt += targetHoursPerNight - (d.totalSleepMin / 60.0);
    }
    return debt;
  }

  /// Alerte physio légère : ne déclenche que si au moins 2 signaux sur 3 (ou
  /// 4 avec la température cutanée si disponible) dévient défavorablement de
  /// leur baseline — évite les faux positifs sur un seul signal bruité.
  /// Approxime une "détection d'épuisement/maladie en incubation" sans
  /// capteur de température cutanée obligatoire (repli silencieux sur 3
  /// signaux si `skinTempDeltaC` est null).
  static HealthInsight? physioAnomalyInsight({
    required DailyHealthRecord today,
    required double rhrBaseline,
    required double hrvBaseline,
    required double respBaseline,
    double? skinTempDeltaC,
  }) {
    var deviating = 0;
    if (today.restingHeartRate > 0 &&
        rhrBaseline > 0 &&
        today.restingHeartRate - rhrBaseline >= 3) {
      deviating++;
    }
    if (today.hrv > 0 && hrvBaseline > 0 && today.hrv / hrvBaseline <= 0.85) {
      deviating++;
    }
    if (today.respiratoryRate > 0 &&
        respBaseline > 0 &&
        (today.respiratoryRate - respBaseline).abs() >= 1.5) {
      deviating++;
    }
    if (skinTempDeltaC != null && skinTempDeltaC >= 0.5) {
      deviating++;
    }
    if (deviating < 2) return null;

    return const HealthInsight(
      'physio_anomaly',
      'Plusieurs signaux (FC repos, VFC, respiration) dévient de ta normale '
          'en même temps — peut annoncer une maladie en incubation ou une '
          'fatigue profonde. Repos conseillé.',
      kNeonPink,
      Icons.warning_amber_rounded,
    );
  }
}
