import 'package:hive_flutter/hive_flutter.dart';
import '../models/vo2_estimate.dart';

/// Historique des estimations VO2 max locales (une par jour de recalcul) —
/// même esprit que `HealthStore`, boîte Hive séparée pour ne pas mélanger
/// avec `DailyHealthRecord` (qui porte le VO2 max cloud, une donnée distincte).
class Vo2EstimateStore {
  static const String boxName = 'vo2_estimates';

  static Box get _box => Hive.box(boxName);

  static Future<void> upsertDay(Vo2Estimate estimate) async {
    await _box.put(estimate.key, estimate.toMap());
  }

  static Vo2Estimate? recordFor(DateTime day) {
    final raw = _box.get(Vo2Estimate.keyFor(day));
    if (raw is Map) return Vo2Estimate.fromMap(raw);
    return null;
  }

  /// Tous les enregistrements, triés du plus ancien au plus récent.
  static List<Vo2Estimate> all() {
    final list = _box.values
        .whereType<Map>()
        .map((m) => Vo2Estimate.fromMap(m))
        .toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  /// Les [n] derniers jours (calendaires) jusqu'à aujourd'hui inclus.
  static List<Vo2Estimate> lastNDays(int n) {
    final everything = all();
    if (everything.isEmpty) return [];
    final cutoff = DateTime.now().subtract(Duration(days: n - 1));
    final cutoffDay = DateTime(cutoff.year, cutoff.month, cutoff.day);
    return everything.where((e) => !e.date.isBefore(cutoffDay)).toList();
  }

  /// Série (date, valeur) sur les [n] derniers jours — pour `TrendChart`.
  static List<MapEntry<DateTime, double>> series(int n) {
    return lastNDays(n).map((e) => MapEntry(e.date, e.value)).toList();
  }
}
