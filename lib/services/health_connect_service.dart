import 'package:health/health.dart';
import '../models/health_snapshot.dart';
import '../models/daily_health_record.dart';
import 'health_insights_service.dart';
import 'health_score_service.dart';
import 'health_store.dart';

/// Un relevé de FC horodaté — sert à tracer le graphe FC/temps d'une course,
/// avec de vraies heures sur l'axe X plutôt qu'un simple index de point.
typedef HrPoint = (DateTime time, double bpm);

/// Données « montre » rattachées à une activité (fenêtre temporelle donnée) :
/// fréquence cardiaque + calories actives lues depuis Health Connect.
class ActivityVitals {
  final double avgHr;
  final double minHr;
  final double maxHr;
  final double activeCalories;
  final List<double> hrSamples;
  final List<HrPoint> hrSeries;

  const ActivityVitals({
    this.avgHr = 0,
    this.minHr = 0,
    this.maxHr = 0,
    this.activeCalories = 0,
    this.hrSamples = const [],
    this.hrSeries = const [],
  });

  bool get hasHr => hrSamples.isNotEmpty;
  bool get hasData => hasHr || activeCalories > 0;
}

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
    HealthDataType.WEIGHT,
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

  /// Lit les données montre (FC + calories actives) sur la fenêtre temporelle
  /// d'une activité. Renvoie un objet vide en cas d'absence de données ou
  /// d'échec (permission non accordée, etc.) — jamais d'exception.
  Future<ActivityVitals> getActivityVitals(DateTime start, DateTime end) async {
    if (!end.isAfter(start)) return const ActivityVitals();
    try {
      final results = await Future.wait([
        _health.getHealthDataFromTypes(
            types: [HealthDataType.HEART_RATE],
            startTime: start,
            endTime: end),
        _health.getHealthDataFromTypes(
            types: [HealthDataType.ACTIVE_ENERGY_BURNED],
            startTime: start,
            endTime: end),
      ]);

      final hrPoints = results[0] as List<HealthDataPoint>;
      final series = <HrPoint>[];
      for (final p in hrPoints) {
        if (p.value is NumericHealthValue) {
          final v = (p.value as NumericHealthValue).numericValue.toDouble();
          if (v > 0) series.add((p.dateFrom, v));
        }
      }
      series.sort((a, b) => a.$1.compareTo(b.$1));
      final hr = [for (final s in series) s.$2];
      final cal = _sumNumeric(results[1] as List<HealthDataPoint>);

      if (hr.isEmpty) {
        return ActivityVitals(activeCalories: cal);
      }
      final avg = hr.reduce((a, b) => a + b) / hr.length;
      final minV = hr.reduce((a, b) => a < b ? a : b);
      final maxV = hr.reduce((a, b) => a > b ? a : b);
      return ActivityVitals(
        avgHr: avg,
        minHr: minV,
        maxHr: maxV,
        activeCalories: cal,
        hrSamples: hr,
        hrSeries: series,
      );
    } catch (e) {
      print('getActivityVitals error: $e');
      return const ActivityVitals();
    }
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
      // Poids : pesée peu fréquente (balance connectée), on cherche donc le
      // dernier relevé connu jusqu'à ce jour plutôt que seulement "aujourd'hui".
      _health.getHealthDataFromTypes(
          types: [HealthDataType.WEIGHT],
          startTime: midnight.subtract(const Duration(days: 90)),
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
    final segments = <SleepSegment>[];
    for (final p in mainSession) {
      final minutes = p.value is NumericHealthValue
          ? (p.value as NumericHealthValue).numericValue.toDouble()
          : 0.0;
      SleepStage? stage;
      switch (p.type) {
        case HealthDataType.SLEEP_DEEP:
          deep += minutes;
          stage = SleepStage.deep;
          break;
        case HealthDataType.SLEEP_LIGHT:
          light += minutes;
          stage = SleepStage.light;
          break;
        case HealthDataType.SLEEP_REM:
          rem += minutes;
          stage = SleepStage.rem;
          break;
        case HealthDataType.SLEEP_AWAKE:
          awake += minutes;
          stage = SleepStage.awake;
          break;
        case HealthDataType.SLEEP_ASLEEP:
          asleep += minutes;
          break;
        default:
          break;
      }
      // On ne garde comme segment que les stades détaillés (pas le "asleep"
      // générique, sinon il chevaucherait les stades précis).
      if (stage != null && p.dateTo.isAfter(p.dateFrom)) {
        segments.add(SleepSegment(stage: stage, start: p.dateFrom, end: p.dateTo));
      }
    }
    // Si l'appareil ne détaille pas les stades mais fournit un total "asleep",
    // on le répartit en léger par défaut pour ne pas perdre la donnée de durée.
    if (deep == 0 && light == 0 && rem == 0 && asleep > 0) {
      light = asleep;
    }
    segments.sort((a, b) => a.start.compareTo(b.start));

    // Dernier relevé de poids connu jusqu'à ce jour (0 si jamais pesé).
    final weightPoints = results[13] as List<HealthDataPoint>;
    var weightKg = 0.0;
    if (weightPoints.isNotEmpty) {
      final sorted = [...weightPoints]..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
      final last = sorted.last.value;
      if (last is NumericHealthValue) weightKg = last.numericValue.toDouble();
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
      weightKg: weightKg,
      sleep: SleepBreakdown(
        deepMin: deep,
        lightMin: light,
        remMin: rem,
        awakeMin: awake,
        asleepMin: deep + light + rem,
        segments: segments,
      ),
    );
  }

  /// Construit et persiste l'enregistrement santé d'un jour donné.
  Future<DailyHealthRecord> syncDay(DateTime day) async {
    final snapshot = await getSnapshotForDay(day);
    final scores = HealthScoreService.computeAll(snapshot);
    var record = DailyHealthRecord.fromSnapshot(
      day,
      snapshot,
      bioScore: scores.bioScore,
      sleepScore: scores.sleepScore,
      recoveryScore: scores.recoveryScore,
      activityScore: scores.activityScore,
    );

    // Indicateurs dérivés qui ont besoin de l'historique (VFC z-score, dette
    // de sommeil) — fenêtré relativement à [day], jamais à "maintenant" :
    // syncDay est aussi appelé pendant un backfill sur des jours passés, et
    // un jour ancien ne doit jamais être comparé à un historique qui lui est
    // postérieur.
    final dayOnly = DateTime(day.year, day.month, day.day);
    final priorHistory =
        HealthStore.all().where((r) => r.date.isBefore(dayOnly)).toList();

    final hrvCutoff = dayOnly.subtract(const Duration(days: 30));
    final hrvHistory = priorHistory
        .where((r) => !r.date.isBefore(hrvCutoff))
        .map((r) => r.hrv)
        .toList();
    final zScore = HealthInsightsService.hrvZScore(record.hrv, hrvHistory);

    final sleepCutoff = dayOnly.subtract(const Duration(days: 6));
    final sleepWindow = [
      ...priorHistory.where((r) => !r.date.isBefore(sleepCutoff)),
      record, // le jour en cours de synchro compte pour sa propre dette
    ];
    final debt = HealthInsightsService.sleepDebtHours(sleepWindow);

    record = record.copyWith(
      hrvZScore: zScore ?? 0,
      deepSleepRatio: HealthInsightsService.deepSleepRatio(record) ?? 0,
      sleepDebtHours: debt,
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
