import 'dart:math' as math;
import 'package:flutter/material.dart' show Color;
import '../models/activity.dart';
import '../models/daily_health_record.dart' show HealthMetric;
import '../models/hr_efficiency_point.dart';
import '../models/training_load_point.dart';
import '../models/vo2_estimate.dart';
import '../theme.dart';
import 'health_connect_service.dart';
import 'health_store.dart';
import 'hr_efficiency_store.dart';
import 'training_load_service.dart';
import 'training_load_store.dart';
import 'vo2_estimate_store.dart';

/// Réglages de l'estimateur — regroupés pour pouvoir les ajuster/tester
/// facilement sans fouiller la logique.
/// Verdict de confiance pour une estimation VO2 max — voir
/// `Vo2EstimatorService.confidenceFor`.
class Vo2Confidence {
  final bool isProvisional;
  final String caption;
  const Vo2Confidence({required this.isProvisional, required this.caption});
}

/// Catégorie qualitative ("bon/moyen/mauvais") d'un VO2 max, comparé à des
/// références générales par tranche d'âge et sexe — voir
/// `Vo2EstimatorService.categoryFor`.
class Vo2Category {
  final String label;
  final Color color;
  const Vo2Category(this.label, this.color);
}

/// Une tranche d'âge (bornée par [maxAge], inclusif — la dernière tranche
/// sert de repli pour tout âge au-delà) et ses seuils bas de "Moyen / Bon /
/// Excellent / Élite" en ml/kg/min, hommes et femmes séparément (le VO2 max
/// féminin de référence est structurellement ~10-15% plus bas — mélanger les
/// deux donnerait une catégorie trompeuse, voir le commentaire de `ChartZone`
/// dans health_charts.dart sur l'individualité de cette métrique).
/// Valeurs composites à partir de tables de référence usuelles (Cooper
/// Institute / ACSM) pour des coureurs amateurs à confirmés — indicatif, pas
/// un diagnostic médical.
class _Vo2AgeBracket {
  final int maxAge;
  final List<double> men; // [moyen, bon, excellent, elite]
  final List<double> women;
  const _Vo2AgeBracket(this.maxAge, this.men, this.women);
}

const List<_Vo2AgeBracket> _vo2Brackets = [
  _Vo2AgeBracket(29, [39, 46, 52, 57], [33, 39, 44, 49]),
  _Vo2AgeBracket(39, [35, 42, 48, 52], [30, 36, 41, 45]),
  _Vo2AgeBracket(49, [31, 39, 45, 50], [27, 33, 37, 41]),
  _Vo2AgeBracket(59, [27, 36, 41, 45], [24, 29, 33, 37]),
  _Vo2AgeBracket(200, [24, 32, 37, 41], [20, 25, 29, 33]),
];

const List<String> _vo2Labels = ['Faible', 'Moyen', 'Bon', 'Excellent', 'Élite'];
const List<Color> _vo2Colors = [
  kNeonPink,
  kNeonAmber,
  kNeonCyan,
  kNeonGreen,
  kNeonViolet,
];

class Vo2EstimatorTuning {
  static const int windowDays = 90;
  /// Plancher absolu — en dessous, rien ne s'affiche.
  static const int minPairsProvisional = 4;
  /// À partir de ce nombre de paires, l'estimation est étiquetée "fiable"
  /// plutôt que "provisoire".
  static const int minPairsStable = 8;
  static const double minHrSpread = 25; // bpm — sinon rien à extrapoler
  static const int minLapSeconds = 90; // FC pas stabilisée en dessous
  static const double minPlausible = 20; // ml/kg/min
  static const double maxPlausible = 85;
}

/// Estimation locale du VO2 max par régression FC↔VO2 sur les courses
/// suivies — voir le plan "VO2 max estimé par tendance" pour le
/// raisonnement complet. Volontairement séparé en deux couches :
/// - `estimateFromPairs` : pur calcul (régression + seuils), testable sans
///   Health Connect ni Hive.
/// - `recomputeAndStore` : rassemble les paires depuis les vraies activités
///   (Health Connect pour la FC) et persiste le résultat.
class Vo2EstimatorService {
  /// Formule ACSM (course) : VO2 (ml/kg/min) à une vitesse donnée.
  /// [speedMPerMin] : vitesse en mètres/minute. [gradePercent] : pente nette
  /// (dénivelé net / distance) — 0 par défaut, les segments de fractionné
  /// n'ont pas de dénivelé détaillé par répétition.
  static double vo2AtSpeed(double speedMPerMin, {double gradePercent = 0}) {
    return 3.5 + 0.2 * speedMPerMin + 0.9 * speedMPerMin * gradePercent;
  }

  static double speedMPerMin(double distanceM, int durationS) {
    if (durationS <= 0) return 0;
    return (distanceM / durationS) * 60;
  }

  /// Ajuste FC = a + b·VO2 par moindres carrés.
  static (double a, double b)? _linearRegression(List<(double, double)> pairs) {
    final n = pairs.length;
    if (n < 2) return null;
    final vo2Mean = pairs.map((p) => p.$1).reduce((x, y) => x + y) / n;
    final hrMean = pairs.map((p) => p.$2).reduce((x, y) => x + y) / n;
    double num = 0, den = 0;
    for (final p in pairs) {
      num += (p.$1 - vo2Mean) * (p.$2 - hrMean);
      den += (p.$1 - vo2Mean) * (p.$1 - vo2Mean);
    }
    if (den.abs() < 1e-9) return null;
    final b = num / den;
    final a = hrMean - b * vo2Mean;
    return (a, b);
  }

  /// Estimation FC max par âge (Tanaka et al. — plus fidèle que 220-âge).
  static double ageBasedHrMax(int age) => 208 - 0.7 * age;

  /// Libellé de confiance partagé entre les cartes (hub Sport + grille
  /// Santé) — jamais le même texte dupliqué à deux endroits. `isProvisional`
  /// pilote l'affichage d'un badge ; `caption` est le texte sous le graphe.
  static Vo2Confidence confidenceFor(Vo2Estimate estimate) {
    final n = estimate.sampleCount;
    if (n < Vo2EstimatorTuning.minPairsStable) {
      return Vo2Confidence(
        isProvisional: true,
        caption:
            'Estimation provisoire — $n/${Vo2EstimatorTuning.minPairsStable} courses avec FC pour une estimation stable.',
      );
    }
    return Vo2Confidence(
      isProvisional: false,
      caption: 'Basé sur $n points de mesure.',
    );
  }

  /// Calcule le VO2 max à partir de paires (VO2, FC) déjà construites.
  /// Renvoie `null` tant que les seuils de confiance ne sont pas atteints —
  /// jamais de chiffre affiché s'il n'est pas défendable.
  /// [ageBasedHrMax] : ancrage de repli si la FC max jamais observée dans
  /// les paires semble trop basse pour être une vraie FC max.
  static double? estimateFromPairs(
    List<(double vo2, double hr)> pairs, {
    double? ageBasedHrMax,
  }) {
    if (pairs.length < Vo2EstimatorTuning.minPairsProvisional) return null;

    final hrValues = pairs.map((p) => p.$2).toList();
    final hrSpread = hrValues.reduce(math.max) - hrValues.reduce(math.min);
    if (hrSpread < Vo2EstimatorTuning.minHrSpread) return null;

    final reg = _linearRegression(pairs);
    if (reg == null) return null;
    final (a, b) = reg;
    if (b <= 0) return null;

    final observedMaxHr = hrValues.reduce(math.max);
    final hrMaxAnchor = ageBasedHrMax == null
        ? observedMaxHr
        : math.max(observedMaxHr, ageBasedHrMax);

    final vo2max = (hrMaxAnchor - a) / b;
    if (vo2max < Vo2EstimatorTuning.minPlausible ||
        vo2max > Vo2EstimatorTuning.maxPlausible) {
      return null;
    }
    return vo2max;
  }

  /// Paires (VO2, FC) exploitables d'une activité :
  /// - fractionné (laps renseignés) : une paire par répétition d'effort
  ///   d'au moins [Vo2EstimatorTuning.minLapSeconds] secondes (la FC n'a pas
  ///   le temps de se stabiliser en dessous, ça fausserait la paire) ;
  /// - sinon (course libre / zone d'allure) : une seule paire, moyenne de
  ///   toute l'activité.
  /// Une seule requête Health Connect par activité (fenêtre complète) ; le
  /// découpage par répétition se fait localement sur les échantillons FC
  /// horodatés (`hrSeries`), pas de requête supplémentaire par lap.
  /// Renvoie aussi la FC moyenne brute de toute l'activité (second élément)
  /// — réutilisée pour l'efficacité cardiaque sans requête supplémentaire —
  /// et la série FC complète (troisième élément), réutilisée pour la dérive
  /// cardiaque/TRIMP (`TrainingLoadService`), toujours sans requête
  /// supplémentaire : une seule requête Health Connect par activité au total.
  /// Chaque paire porte aussi la vitesse (m/min) qui a servi à calculer son
  /// VO2 — pas utilisée par la régression, seulement pour afficher la plage
  /// d'allure réellement couverte dans l'écran de détail.
  static Future<
      (
        List<(double vo2, double hr, double speedMPerMin)>,
        double?,
        List<HrPoint>
      )> _pairsForActivity(Activity activity, HealthConnectService health) async {
    if (activity.distance <= 0 || activity.duration <= 0) {
      return (const <(double, double, double)>[], null, const <HrPoint>[]);
    }
    final end = activity.date.add(Duration(seconds: activity.duration));
    final vitals = await health.getActivityVitals(activity.date, end);
    if (!vitals.hasHr) {
      return (const <(double, double, double)>[], null, const <HrPoint>[]);
    }

    final laps = activity.laps;
    if (activity.workoutType == 'interval' && laps != null && laps.isNotEmpty) {
      final pairs = <(double, double, double)>[];
      for (final raw in laps) {
        final lap = raw as Map;
        final lapDuration = lap['duration'] as int;
        if (lapDuration < Vo2EstimatorTuning.minLapSeconds) continue;
        final lapDistance = (lap['distance'] as num).toDouble();
        if (lapDistance <= 0) continue;
        final totalAtLap = lap['totalTimeAtLap'] as int;
        final lapStart =
            activity.date.add(Duration(seconds: totalAtLap - lapDuration));
        final lapEnd = activity.date.add(Duration(seconds: totalAtLap));
        final samples = vitals.hrSeries
            .where((s) => !s.$1.isBefore(lapStart) && s.$1.isBefore(lapEnd))
            .map((s) => s.$2)
            .toList();
        if (samples.isEmpty) continue;
        final avgHr = samples.reduce((x, y) => x + y) / samples.length;
        final speed = speedMPerMin(lapDistance, lapDuration);
        pairs.add((vo2AtSpeed(speed), avgHr, speed));
      }
      return (pairs, vitals.avgHr, vitals.hrSeries);
    }

    final speed = speedMPerMin(activity.distance, activity.duration);
    return (
      [(vo2AtSpeed(speed), vitals.avgHr, speed)],
      vitals.avgHr,
      vitals.hrSeries
    );
  }

  /// Recalcule l'estimation sur la fenêtre glissante ([activities] = tout
  /// l'historique, le filtrage par fenêtre se fait ici) et l'enregistre si
  /// elle passe les seuils — sinon ne stocke rien. Au passage, met aussi à
  /// jour `HrEfficiencyStore` (un point par course, FC moyenne déjà
  /// récupérée pour le VO2 max — pas de requête Health Connect en plus).
  /// Best-effort : jamais d'exception propagée (appelé en fire-and-forget
  /// depuis les écrans de suivi, ne doit jamais faire planter la fin d'une
  /// séance).
  static Future<Vo2Estimate?> recomputeAndStore(
    List<Activity> activities, {
    HealthConnectService? healthConnect,
  }) async {
    try {
      final health = healthConnect ?? HealthConnectService();
      final cutoff = DateTime.now()
          .subtract(const Duration(days: Vo2EstimatorTuning.windowDays));
      final recent = activities.where((a) => a.date.isAfter(cutoff)).toList();

      final restingHr = HealthStore.baseline(HealthMetric.restingHeartRate, window: 7);
      final age = HealthProfileStore.age;
      final sex = HealthProfileStore.sex;

      final triples = <(double, double, double)>[];
      var activityCount = 0;
      for (final a in recent) {
        final (activityTriples, avgHr, hrSeries) = await _pairsForActivity(a, health);
        if (activityTriples.isNotEmpty) activityCount++;
        triples.addAll(activityTriples);

        final drift = TrainingLoadService.cardiacDrift(hrSeries);
        final t = restingHr > 0 && age != null
            ? TrainingLoadService.trimp(
                hrSeries: hrSeries,
                restingHr: restingHr,
                maxHr: ageBasedHrMax(age),
                sex: sex,
              )
            : null;
        if (drift != null || t != null) {
          await TrainingLoadStore.upsert(TrainingLoadPoint(
            date: a.date,
            cardiacDriftPct: drift ?? 0,
            trimp: t ?? 0,
          ));
        }

        if (avgHr != null && a.avgSpeedKmhValue > 0) {
          await HrEfficiencyStore.upsert(HrEfficiencyPoint(
            date: a.date,
            ratio: avgHr / a.avgSpeedKmhValue,
          ));
        }
      }
      final pairs = [for (final t in triples) (t.$1, t.$2)];

      final value = estimateFromPairs(
        pairs,
        ageBasedHrMax: age != null ? ageBasedHrMax(age) : null,
      );
      if (value == null) return null;

      final hrValues = triples.map((t) => t.$2).toList();
      final speeds = triples.map((t) => t.$3).where((s) => s > 0).toList();

      final estimate = Vo2Estimate(
        date: DateTime.now(),
        value: value,
        sampleCount: pairs.length,
        activityCount: activityCount,
        hrMinBpm: hrValues.reduce(math.min),
        hrMaxBpm: hrValues.reduce(math.max),
        // Vitesse la plus haute -> allure (sec/km) la plus basse, et inversement.
        paceMinSecPerKm: speeds.isEmpty ? 0 : 60000 / speeds.reduce(math.max),
        paceMaxSecPerKm: speeds.isEmpty ? 0 : 60000 / speeds.reduce(math.min),
      );
      await Vo2EstimateStore.upsertDay(estimate);
      return estimate;
    } catch (_) {
      return null;
    }
  }

  /// Catégorie qualitative ("bon/moyen/mauvais") pour une valeur de VO2 max,
  /// comparée à des références générales par âge et sexe. `null` tant que
  /// l'âge n'est pas renseigné dans le profil — jamais de verdict inventé.
  /// Si le sexe n'est pas renseigné, utilise la moyenne des deux tables de
  /// référence (moins précis, mais préférable à l'absence de repère).
  static Vo2Category? categoryFor(double value, {int? age, String? sex}) {
    if (age == null) return null;
    final bracket = _vo2Brackets.firstWhere(
      (b) => age <= b.maxAge,
      orElse: () => _vo2Brackets.last,
    );
    final thresholds = sex == 'F'
        ? bracket.women
        : sex == 'M'
            ? bracket.men
            : [
                for (int i = 0; i < bracket.men.length; i++)
                  (bracket.men[i] + bracket.women[i]) / 2,
              ];

    var tier = 0;
    for (final t in thresholds) {
      if (value >= t) tier++;
    }
    return Vo2Category(_vo2Labels[tier], _vo2Colors[tier]);
  }
}
