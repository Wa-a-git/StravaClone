import 'package:hive_flutter/hive_flutter.dart';
import '../models/hr_efficiency_point.dart';

/// Historique de l'efficacité cardiaque, un point par course — même esprit
/// que `Vo2EstimateStore`, boîte Hive séparée.
class HrEfficiencyStore {
  static const String boxName = 'hr_efficiency';

  static Box get _box => Hive.box(boxName);

  static Future<void> upsert(HrEfficiencyPoint point) async {
    await _box.put(point.key, point.toMap());
  }

  /// Tous les enregistrements, triés du plus ancien au plus récent.
  static List<HrEfficiencyPoint> all() {
    final list = _box.values
        .whereType<Map>()
        .map((m) => HrEfficiencyPoint.fromMap(m))
        .toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  /// Les [n] derniers points (les plus récents), triés du plus ancien au
  /// plus récent (ordre chronologique, prêt pour `TrendChart`).
  static List<HrEfficiencyPoint> recent(int n) {
    final everything = all();
    if (everything.length <= n) return everything;
    return everything.sublist(everything.length - n);
  }
}
