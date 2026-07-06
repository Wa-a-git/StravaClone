// lib/services/musculation_store.dart
// Persistance des exercices loggés (séries/répétitions), calquée sur
// HealthStore : boîte Hive simple, aucune génération d'adaptateur.
import 'package:hive_flutter/hive_flutter.dart';
import '../models/musculation_log.dart';

class MusculationStore {
  static const String boxName = 'musculation_log';
  static Box get _box => Hive.box(boxName);

  /// Clé unique par entrée (permet plusieurs fois le même exercice le même
  /// jour sans s'écraser).
  static Future<void> addEntry(MusculationLogEntry entry) async {
    final key =
        '${entry.date.millisecondsSinceEpoch}_${entry.exerciseId}_${DateTime.now().microsecondsSinceEpoch}';
    await _box.put(key, entry.toMap());
  }

  static Future<void> deleteEntry(String key) => _box.delete(key);

  /// Entrées d'un jour donné, dans l'ordre d'ajout.
  static List<MapEntry<String, MusculationLogEntry>> entriesFor(DateTime day) {
    final dayKey = MusculationLogEntry.keyFor(day);
    return _box.toMap().entries
        .where((e) => e.value is Map)
        .map((e) => MapEntry(
            e.key.toString(), MusculationLogEntry.fromMap(e.value as Map)))
        .where((e) => e.value.dayKey == dayKey)
        .toList()
      ..sort((a, b) => a.value.date.compareTo(b.value.date));
  }

  static List<MapEntry<String, MusculationLogEntry>> todayEntries() =>
      entriesFor(DateTime.now());

  static Future<void> clearAll() => _box.clear();
}
