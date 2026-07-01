import 'package:health/health.dart';
import '../models/health_snapshot.dart';
import '../models/daily_health_record.dart';
import 'health_score_service.dart';
import 'health_store.dart';

class HealthConnectService {
  final Health _health = Health();

  HealthConnectService() {
    _health.configure();
  }

  // Types demandés lors de l'autorisation Health Connect.
  final List<HealthDataType> _types = [
    HealthDataType.STEPS,
    HealthDataType.HEART_RATE,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.TOTAL_CALORIES_BURNED,
    HealthDataType.BLOOD_OXYGEN,
    HealthDataType.RESPIRATORY_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    HealthDataType.FLIGHTS_CLIMBED,
    HealthDataType.DISTANCE_DELTA,
  ];

  // Request permissions for Health Connect
  Future<bool> requestPermissions() async {
    bool hasPermissions = await _health.hasPermissions(_types) ?? false;
    if (!hasPermissions) {
      try {
        hasPermissions = await _health.requestAuthorization(_types);
      } catch (e) {
        print("Exception in requestAuthorization: $e");
        hasPermissions = false;
      }
    }
    // Permission additionnelle pour lire plus de 30 jours d'historique.
    // Non bloquante : si refusée, on continue avec les 30 derniers jours.
    try {
      final historyAuthorized = await _health.isHealthDataHistoryAuthorized();
      if (!historyAuthorized) {
        await _health.requestHealthDataHistoryAuthorization();
      }
    } catch (e) {
      print("Exception requesting history authorization: $e");
    }
    return hasPermissions;
  }

  double _sumNumeric(List<HealthDataPoint> points) {
    double total = 0.0;
    for (final p in points) {
      if (p.value is NumericHealthValue) {
        total += (p.value as NumericHealthValue).numericValue.toDouble();
      }
    }
    return total;
  }

  double _averageNumeric(List<HealthDataPoint> points) {
    if (points.isEmpty) return 0.0;
    return _sumNumeric(points) / points.length;
  }

  /// Isole la session de sommeil la plus récente parmi tous les enregistrements
  /// de stades lus. Deux stades espacés de plus de [gapHours] heures sont
  /// considérés comme appartenant à des sessions différentes (ex : sieste de
  /// l'après-midi vs nuit). On renvoie la session dont le réveil est le plus
  /// tardif — c'est « la nuit » pertinente pour l'aptitude du jour.
  List<HealthDataPoint> _latestSleepSession(
    List<HealthDataPoint> points, {
    double gapHours = 3,
  }) {
    if (points.isEmpty) return points;
    final sorted = [...points]
      ..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));

    final sessions = <List<HealthDataPoint>>[];
    var current = <HealthDataPoint>[sorted.first];
    var currentMaxEnd = sorted.first.dateTo;

    for (var i = 1; i < sorted.length; i++) {
      final p = sorted[i];
      final gap = p.dateFrom.difference(currentMaxEnd).inMinutes;
      if (gap > gapHours * 60) {
        sessions.add(current);
        current = <HealthDataPoint>[p];
        currentMaxEnd = p.dateTo;
      } else {
        current.add(p);
        if (p.dateTo.isAfter(currentMaxEnd)) currentMaxEnd = p.dateTo;
      }
    }
    sessions.add(current);

    // Session dont la fin est la plus tardive.
    sessions.sort((a, b) {
      final aEnd = a.map((e) => e.dateTo).reduce((x, y) => x.isAfter(y) ? x : y);
      final bEnd = b.map((e) => e.dateTo).reduce((x, y) => x.isAfter(y) ? x : y);
      return bEnd.compareTo(aEnd);
    });
    return sessions.first;
  }

  /// Instantané des données santé du jour en cours.
  Future<HealthSnapshot> getTodaySnapshot() => getSnapshotForDay(DateTime.now());

  /// Récupère un instantané complet des données santé pour un jour civil donné
  /// (et la nuit précédente pour le sommeil), en interrogeant Health Connect en
  /// parallèle. Fonctionne aussi bien pour aujourd'hui que pour un jour passé
  /// (backfill via la permission READ_HEALTH_DATA_HISTORY).
  Future<HealthSnapshot> getSnapshotForDay(DateTime day) async {
    final now = DateTime.now();
    final midnight = DateTime(day.year, day.month, day.day);
    var dayEnd = midnight.add(const Duration(days: 1));
    if (dayEnd.isAfter(now)) dayEnd = now; // journée en cours : borne à maintenant
    final sleepWindowStart = midnight.subtract(const Duration(hours: 12));
    final baselineStart = midnight.subtract(const Duration(days: 7));

    final results = await Future.wait([
      _health.getTotalStepsInInterval(midnight, dayEnd),
      _health.getHealthDataFromTypes(
          types: [HealthDataType.ACTIVE_ENERGY_BURNED],
          startTime: midnight,
          endTime: dayEnd),
      _health.getHealthDataFromTypes(
          types: [HealthDataType.TOTAL_CALORIES_BURNED],
          startTime: midnight,
          endTime: dayEnd),
      _health.getHealthDataFromTypes(
          types: [HealthDataType.HEART_RATE],
          startTime: midnight,
          endTime: dayEnd),
      _health.getHealthDataFromTypes(
          types: [HealthDataType.RESTING_HEART_RATE],
          startTime: midnight,
          endTime: dayEnd),
      _health.getHealthDataFromTypes(
          types: [HealthDataType.RESTING_HEART_RATE],
          startTime: baselineStart,
          endTime: midnight),
      _health.getHealthDataFromTypes(
          types: [HealthDataType.BLOOD_OXYGEN],
          startTime: sleepWindowStart,
          endTime: dayEnd),
      _health.getHealthDataFromTypes(
          types: [HealthDataType.RESPIRATORY_RATE],
          startTime: sleepWindowStart,
          endTime: dayEnd),
      _health.getHealthDataFromTypes(
          types: [HealthDataType.HEART_RATE_VARIABILITY_RMSSD],
          startTime: sleepWindowStart,
          endTime: dayEnd),
      _health.getHealthDataFromTypes(
          types: [HealthDataType.HEART_RATE_VARIABILITY_RMSSD],
          startTime: baselineStart,
          endTime: sleepWindowStart),
      _health.getHealthDataFromTypes(
          types: [HealthDataType.FLIGHTS_CLIMBED],
          startTime: midnight,
          endTime: dayEnd),
      _health.getHealthDataFromTypes(
          types: [HealthDataType.DISTANCE_DELTA],
          startTime: midnight,
          endTime: dayEnd),
      _health.getHealthDataFromTypes(
          types: [
            HealthDataType.SLEEP_DEEP,
            HealthDataType.SLEEP_LIGHT,
            HealthDataType.SLEEP_REM,
            HealthDataType.SLEEP_AWAKE,
            HealthDataType.SLEEP_ASLEEP,
          ],
          startTime: sleepWindowStart,
          endTime: dayEnd),
    ]);

    final steps = (results[0] as int?) ?? 0;
    final activeCalories = _sumNumeric(results[1] as List<HealthDataPoint>);
    final totalCalories = _sumNumeric(results[2] as List<HealthDataPoint>);
    final avgHeartRate = _averageNumeric(results[3] as List<HealthDataPoint>);
    final restingHeartRate =
        _averageNumeric(results[4] as List<HealthDataPoint>);
    final restingHeartRateBaseline =
        _averageNumeric(results[5] as List<HealthDataPoint>);
    final spo2 = _averageNumeric(results[6] as List<HealthDataPoint>);
    final respiratoryRate =
        _averageNumeric(results[7] as List<HealthDataPoint>);
    final hrv = _averageNumeric(results[8] as List<HealthDataPoint>);
    final hrvBaseline = _averageNumeric(results[9] as List<HealthDataPoint>);
    final flightsClimbed =
        _sumNumeric(results[10] as List<HealthDataPoint>).round();
    final distanceKm =
        _sumNumeric(results[11] as List<HealthDataPoint>) / 1000.0;

    final sleepPoints = results[12] as List<HealthDataPoint>;
    // On ne garde QUE la session de sommeil la plus récente (la nuit).
    // Sinon une sieste de la veille s'ajouterait à la nuit et gonflerait le
    // total (Google Health n'affiche que la session principale).
    final mainSession = _latestSleepSession(sleepPoints);
    double deep = 0, light = 0, rem = 0, awake = 0, asleep = 0;
    for (final p in mainSession) {
      final minutes = p.value is NumericHealthValue
          ? (p.value as NumericHealthValue).numericValue.toDouble()
          : 0.0;
      switch (p.type) {
        case HealthDataType.SLEEP_DEEP:
          deep += minutes;
          break;
        case HealthDataType.SLEEP_LIGHT:
          light += minutes;
          break;
        case HealthDataType.SLEEP_REM:
          rem += minutes;
          break;
        case HealthDataType.SLEEP_AWAKE:
          awake += minutes;
          break;
        case HealthDataType.SLEEP_ASLEEP:
          asleep += minutes;
          break;
        default:
          break;
      }
    }
    // Si l'appareil ne détaille pas les stades mais fournit un total "asleep",
    // on le répartit en léger par défaut pour ne pas perdre la donnée de durée.
    if (deep == 0 && light == 0 && rem == 0 && asleep > 0) {
      light = asleep;
    }

    return HealthSnapshot(
      steps: steps,
      activeCalories: activeCalories,
      totalCalories: totalCalories,
      avgHeartRate: avgHeartRate,
      restingHeartRate: restingHeartRate,
      restingHeartRateBaseline: restingHeartRateBaseline,
      spo2: spo2,
      respiratoryRate: respiratoryRate,
      hrv: hrv,
      hrvBaseline: hrvBaseline,
      flightsClimbed: flightsClimbed,
      distanceKm: distanceKm,
      sleep: SleepBreakdown(
        deepMin: deep,
        lightMin: light,
        remMin: rem,
        awakeMin: awake,
        asleepMin: deep + light + rem,
      ),
    );
  }

  /// Construit et persiste l'enregistrement santé d'un jour donné.
  Future<DailyHealthRecord> syncDay(DateTime day) async {
    final snapshot = await getSnapshotForDay(day);
    final scores = HealthScoreService.computeAll(snapshot);
    final record = DailyHealthRecord.fromSnapshot(
      day,
      snapshot,
      bioScore: scores.bioScore,
      sleepScore: scores.sleepScore,
      recoveryScore: scores.recoveryScore,
      activityScore: scores.activityScore,
    );
    await HealthStore.upsertDay(record);
    return record;
  }

  /// Remplit l'historique sur les [days] derniers jours (aujourd'hui inclus).
  /// Ne re-synchronise que les jours manquants + toujours aujourd'hui (données
  /// encore en cours d'accumulation). Les jours passés déjà stockés sont
  /// laissés tels quels.
  Future<void> backfillHistory({int days = 30}) async {
    final today = DateTime.now();
    for (int i = days - 1; i >= 0; i--) {
      final day = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: i));
      final isToday = i == 0;
      if (!isToday && HealthStore.hasDay(day)) continue;
      try {
        await syncDay(day);
      } catch (e) {
        print("Backfill error for $day: $e");
      }
    }
  }
}
