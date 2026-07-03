import 'health_snapshot.dart';

/// Un instantané santé figé pour un jour donné, persisté dans Hive.
/// Volontairement en Map simple (toMap/fromMap) pour éviter la génération
/// d'adaptateur Hive (codegen).
class DailyHealthRecord {
  /// Date normalisée à minuit (jour civil).
  final DateTime date;

  final int steps;
  final double activeCalories;
  final double totalCalories;
  final double avgHeartRate;
  final double restingHeartRate;
  final double spo2;
  final double respiratoryRate;
  final double hrv;
  final int flightsClimbed;
  final double distanceKm;

  // Sommeil (minutes)
  final double sleepDeepMin;
  final double sleepLightMin;
  final double sleepRemMin;
  final double sleepAwakeMin;

  /// Chronologie détaillée des stades de sommeil (pour l'hypnogramme).
  final List<SleepSegment> sleepSegments;

  // Scores calculés (0-100)
  final int bioScore;
  final int sleepScore;
  final int recoveryScore;
  final int activityScore;

  const DailyHealthRecord({
    required this.date,
    this.steps = 0,
    this.activeCalories = 0,
    this.totalCalories = 0,
    this.avgHeartRate = 0,
    this.restingHeartRate = 0,
    this.spo2 = 0,
    this.respiratoryRate = 0,
    this.hrv = 0,
    this.flightsClimbed = 0,
    this.distanceKm = 0,
    this.sleepDeepMin = 0,
    this.sleepLightMin = 0,
    this.sleepRemMin = 0,
    this.sleepAwakeMin = 0,
    this.sleepSegments = const [],
    this.bioScore = 0,
    this.sleepScore = 0,
    this.recoveryScore = 0,
    this.activityScore = 0,
  });

  /// Clé Hive : 'yyyy-MM-dd'.
  static String keyFor(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String get key => keyFor(date);

  SleepBreakdown get sleep => SleepBreakdown(
        deepMin: sleepDeepMin,
        lightMin: sleepLightMin,
        remMin: sleepRemMin,
        awakeMin: sleepAwakeMin,
        asleepMin: sleepDeepMin + sleepLightMin + sleepRemMin,
        segments: sleepSegments,
      );

  double get totalSleepMin => sleepDeepMin + sleepLightMin + sleepRemMin;

  /// Reconstruit un HealthSnapshot à partir de cet enregistrement stocké
  /// (les baselines ne sont pas persistées — calculées ailleurs via HealthStore).
  HealthSnapshot toSnapshot() => HealthSnapshot(
        steps: steps,
        activeCalories: activeCalories,
        totalCalories: totalCalories,
        avgHeartRate: avgHeartRate,
        restingHeartRate: restingHeartRate,
        spo2: spo2,
        respiratoryRate: respiratoryRate,
        hrv: hrv,
        flightsClimbed: flightsClimbed,
        distanceKm: distanceKm,
        sleep: sleep,
      );

  /// Construit un enregistrement à partir d'un snapshot live + scores calculés.
  factory DailyHealthRecord.fromSnapshot(
    DateTime day,
    HealthSnapshot s, {
    required int bioScore,
    required int sleepScore,
    required int recoveryScore,
    required int activityScore,
  }) {
    return DailyHealthRecord(
      date: DateTime(day.year, day.month, day.day),
      steps: s.steps,
      activeCalories: s.activeCalories,
      totalCalories: s.totalCalories,
      avgHeartRate: s.avgHeartRate,
      restingHeartRate: s.restingHeartRate,
      spo2: s.spo2,
      respiratoryRate: s.respiratoryRate,
      hrv: s.hrv,
      flightsClimbed: s.flightsClimbed,
      distanceKm: s.distanceKm,
      sleepDeepMin: s.sleep.deepMin,
      sleepLightMin: s.sleep.lightMin,
      sleepRemMin: s.sleep.remMin,
      sleepAwakeMin: s.sleep.awakeMin,
      sleepSegments: s.sleep.segments,
      bioScore: bioScore,
      sleepScore: sleepScore,
      recoveryScore: recoveryScore,
      activityScore: activityScore,
    );
  }

  Map<String, dynamic> toMap() => {
        'date': date.millisecondsSinceEpoch,
        'steps': steps,
        'activeCalories': activeCalories,
        'totalCalories': totalCalories,
        'avgHeartRate': avgHeartRate,
        'restingHeartRate': restingHeartRate,
        'spo2': spo2,
        'respiratoryRate': respiratoryRate,
        'hrv': hrv,
        'flightsClimbed': flightsClimbed,
        'distanceKm': distanceKm,
        'sleepDeepMin': sleepDeepMin,
        'sleepLightMin': sleepLightMin,
        'sleepRemMin': sleepRemMin,
        'sleepAwakeMin': sleepAwakeMin,
        'sleepSegments': sleepSegments.map((s) => s.toMap()).toList(),
        'bioScore': bioScore,
        'sleepScore': sleepScore,
        'recoveryScore': recoveryScore,
        'activityScore': activityScore,
      };

  factory DailyHealthRecord.fromMap(Map<dynamic, dynamic> m) {
    double d(String k) => (m[k] as num?)?.toDouble() ?? 0.0;
    int i(String k) => (m[k] as num?)?.toInt() ?? 0;
    final rawSeg = m['sleepSegments'];
    final segs = rawSeg is List
        ? rawSeg.whereType<Map>().map((e) => SleepSegment.fromMap(e)).toList()
        : <SleepSegment>[];
    return DailyHealthRecord(
      date: DateTime.fromMillisecondsSinceEpoch(i('date')),
      steps: i('steps'),
      activeCalories: d('activeCalories'),
      totalCalories: d('totalCalories'),
      avgHeartRate: d('avgHeartRate'),
      restingHeartRate: d('restingHeartRate'),
      spo2: d('spo2'),
      respiratoryRate: d('respiratoryRate'),
      hrv: d('hrv'),
      flightsClimbed: i('flightsClimbed'),
      distanceKm: d('distanceKm'),
      sleepDeepMin: d('sleepDeepMin'),
      sleepLightMin: d('sleepLightMin'),
      sleepRemMin: d('sleepRemMin'),
      sleepAwakeMin: d('sleepAwakeMin'),
      sleepSegments: segs,
      bioScore: i('bioScore'),
      sleepScore: i('sleepScore'),
      recoveryScore: i('recoveryScore'),
      activityScore: i('activityScore'),
    );
  }
}

/// Métriques exposables en série temporelle (pour charts & détails).
enum HealthMetric {
  bioScore,
  sleepScore,
  recoveryScore,
  activityScore,
  steps,
  activeCalories,
  restingHeartRate,
  hrv,
  spo2,
  respiratoryRate,
  sleepHours,
  distanceKm,
  flightsClimbed,
}

extension HealthMetricAccessor on HealthMetric {
  /// Valeur de cette métrique pour un enregistrement donné.
  double valueOf(DailyHealthRecord r) {
    switch (this) {
      case HealthMetric.bioScore:
        return r.bioScore.toDouble();
      case HealthMetric.sleepScore:
        return r.sleepScore.toDouble();
      case HealthMetric.recoveryScore:
        return r.recoveryScore.toDouble();
      case HealthMetric.activityScore:
        return r.activityScore.toDouble();
      case HealthMetric.steps:
        return r.steps.toDouble();
      case HealthMetric.activeCalories:
        return r.activeCalories;
      case HealthMetric.restingHeartRate:
        return r.restingHeartRate;
      case HealthMetric.hrv:
        return r.hrv;
      case HealthMetric.spo2:
        return r.spo2;
      case HealthMetric.respiratoryRate:
        return r.respiratoryRate;
      case HealthMetric.sleepHours:
        return r.totalSleepMin / 60.0;
      case HealthMetric.distanceKm:
        return r.distanceKm;
      case HealthMetric.flightsClimbed:
        return r.flightsClimbed.toDouble();
    }
  }

  /// Pour la plupart des métriques « plus = mieux ». La FC repos et la
  /// respiration sont inversées (moins = mieux).
  bool get lowerIsBetter =>
      this == HealthMetric.restingHeartRate ||
      this == HealthMetric.respiratoryRate;
}
