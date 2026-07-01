// lib/services/health_store.dart
// Persistance des instantanés santé quotidiens + calculs dérivés
// (baselines, séries temporelles, streaks). Calqué sur GameStore : boîte Hive
// simple, aucune génération d'adaptateur.
import 'package:hive_flutter/hive_flutter.dart';
import '../models/daily_health_record.dart';

class HealthStore {
  static const String boxName = 'health_history';

  static Box get _box => Hive.box(boxName);

  /// Enregistre / met à jour le jour donné.
  static Future<void> upsertDay(DailyHealthRecord record) async {
    await _box.put(record.key, record.toMap());
  }

  /// Enregistrement d'un jour précis (null si absent).
  static DailyHealthRecord? recordFor(DateTime day) {
    final raw = _box.get(DailyHealthRecord.keyFor(day));
    if (raw is Map) return DailyHealthRecord.fromMap(raw);
    return null;
  }

  static bool hasDay(DateTime day) =>
      _box.containsKey(DailyHealthRecord.keyFor(day));

  /// Tous les enregistrements triés du plus ancien au plus récent.
  static List<DailyHealthRecord> all() {
    final list = _box.values
        .whereType<Map>()
        .map((m) => DailyHealthRecord.fromMap(m))
        .toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  /// Les [n] derniers jours (calendaires) jusqu'à aujourd'hui inclus, dans
  /// l'ordre chronologique. Les jours sans donnée sont omis.
  static List<DailyHealthRecord> lastNDays(int n) {
    final all = HealthStore.all();
    if (all.isEmpty) return [];
    final cutoff = DateTime.now().subtract(Duration(days: n - 1));
    final cutoffDay = DateTime(cutoff.year, cutoff.month, cutoff.day);
    return all.where((r) => !r.date.isBefore(cutoffDay)).toList();
  }

  static int get dayCount => _box.length;

  /// Moyenne glissante d'une métrique sur les [window] derniers jours,
  /// en excluant éventuellement aujourd'hui (pour comparer « aujourd'hui vs
  /// baseline »). Ignore les valeurs nulles/zéro non pertinentes.
  static double baseline(
    HealthMetric metric, {
    int window = 7,
    bool excludeToday = true,
  }) {
    final records = lastNDays(window + (excludeToday ? 1 : 0));
    final todayKey = DailyHealthRecord.keyFor(DateTime.now());
    final vals = <double>[];
    for (final r in records) {
      if (excludeToday && r.key == todayKey) continue;
      final v = metric.valueOf(r);
      if (v > 0) vals.add(v);
    }
    if (vals.isEmpty) return 0;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  /// Série (date, valeur) d'une métrique sur les [n] derniers jours.
  static List<MapEntry<DateTime, double>> series(HealthMetric metric, int n) {
    return lastNDays(n)
        .map((r) => MapEntry(r.date, metric.valueOf(r)))
        .toList();
  }

  /// Nombre de jours consécutifs (en terminant aujourd'hui ou hier) où
  /// [test] est vrai. Sert aux streaks.
  static int streak(bool Function(DailyHealthRecord) test) {
    final all = HealthStore.all();
    if (all.isEmpty) return 0;
    final byKey = {for (final r in all) r.key: r};

    int count = 0;
    var cursor = DateTime.now();
    // Tolère que la journée en cours ne soit pas encore « validée » :
    // on démarre le comptage à partir du dernier jour qui satisfait le test.
    for (int i = 0; i < 400; i++) {
      final key = DailyHealthRecord.keyFor(cursor);
      final r = byKey[key];
      final ok = r != null && test(r);
      if (ok) {
        count++;
      } else if (i == 0) {
        // aujourd'hui pas encore atteint : on ne casse pas, on regarde hier
      } else {
        break;
      }
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return count;
  }

  static Future<void> clearAll() async => _box.clear();
}
