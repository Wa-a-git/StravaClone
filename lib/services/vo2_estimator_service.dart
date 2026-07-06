import 'dart:math' as math;
import '../models/activity.dart';
import '../models/vo2_estimate.dart';
import 'health_connect_service.dart';
import 'health_store.dart';
import 'vo2_estimate_store.dart';

/// Réglages de l'estimateur — regroupés pour pouvoir les ajuster/tester
/// facilement sans fouiller la logique.
class Vo2EstimatorTuning {
  static const int windowDays = 90;
  static const int minPairs = 8;
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

  /// Calcule le VO2 max à partir de paires (VO2, FC) déjà construites.
  /// Renvoie `null` tant que les seuils de confiance ne sont pas atteints —
  /// jamais de chiffre affiché s'il n'est pas défendable.
  /// [ageBasedHrMax] : ancrage de repli si la FC max jamais observée dans
  /// les paires semble trop basse pour être une vraie FC max.
  static double? estimateFromPairs(
    List<(double vo2, double hr)> pairs, {
    double? ageBasedHrMax,
  }) {
    if (pairs.length < Vo2EstimatorTuning.minPairs) return null;

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
  static Future<List<(double, double)>> _pairsForActivity(
      Activity activity, HealthConnectService health) async {
    if (activity.distance <= 0 || activity.duration <= 0) return const [];
    final end = activity.date.add(Duration(seconds: activity.duration));
    final vitals = await health.getActivityVitals(activity.date, end);
    if (!vitals.hasHr) return const [];

    final laps = activity.laps;
    if (activity.workoutType == 'interval' && laps != null && laps.isNotEmpty) {
      final pairs = <(double, double)>[];
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
        final vo2 = vo2AtSpeed(speedMPerMin(lapDistance, lapDuration));
        pairs.add((vo2, avgHr));
      }
      return pairs;
    }

    final vo2 = vo2AtSpeed(speedMPerMin(activity.distance, activity.duration));
    return [(vo2, vitals.avgHr)];
  }

  /// Recalcule l'estimation sur la fenêtre glissante ([activities] = tout
  /// l'historique, le filtrage par fenêtre se fait ici) et l'enregistre si
  /// elle passe les seuils — sinon ne stocke rien. Best-effort : jamais
  /// d'exception propagée (appelé en fire-and-forget depuis les écrans de
  /// suivi, ne doit jamais faire planter la fin d'une séance).
  static Future<Vo2Estimate?> recomputeAndStore(
    List<Activity> activities, {
    HealthConnectService? healthConnect,
  }) async {
    try {
      final health = healthConnect ?? HealthConnectService();
      final cutoff = DateTime.now()
          .subtract(const Duration(days: Vo2EstimatorTuning.windowDays));
      final recent = activities.where((a) => a.date.isAfter(cutoff)).toList();

      final pairs = <(double, double)>[];
      for (final a in recent) {
        pairs.addAll(await _pairsForActivity(a, health));
      }

      final age = HealthProfileStore.age;
      final value = estimateFromPairs(
        pairs,
        ageBasedHrMax: age != null ? ageBasedHrMax(age) : null,
      );
      if (value == null) return null;

      final estimate = Vo2Estimate(
        date: DateTime.now(),
        value: value,
        sampleCount: pairs.length,
      );
      await Vo2EstimateStore.upsertDay(estimate);
      return estimate;
    } catch (_) {
      return null;
    }
  }
}
