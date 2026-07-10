import 'package:hive_flutter/hive_flutter.dart';
import '../models/training_load_point.dart';

/// Historique de la charge d'entraînement (dérive cardiaque + TRIMP), un
/// point par course — même esprit que `HrEfficiencyStore`, boîte Hive séparée.
class TrainingLoadStore {
  static const String boxName = 'training_load';

  static Box get _box => Hive.box(boxName);

  static Future<void> upsert(TrainingLoadPoint point) async {
    await _box.put(point.key, point.toMap());
  }

  /// Tous les enregistrements, triés du plus ancien au plus récent.
  static List<TrainingLoadPoint> all() {
    final list = _box.values
        .whereType<Map>()
        .map((m) => TrainingLoadPoint.fromMap(m))
        .toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  /// Les [n] derniers points (les plus récents), triés du plus ancien au
  /// plus récent (ordre chronologique, prêt pour `TrendChart`).
  static List<TrainingLoadPoint> recent(int n) {
    final everything = all();
    if (everything.length <= n) return everything;
    return everything.sublist(everything.length - n);
  }
}
