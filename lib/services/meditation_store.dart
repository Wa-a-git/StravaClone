// lib/services/meditation_store.dart
// Persistance des séances de méditation, calquée sur MusculationStore : boîte
// Hive simple, aucune génération d'adaptateur.
import 'package:hive_flutter/hive_flutter.dart';
import '../models/meditation_session.dart';

class MeditationStore {
  static const String boxName = 'meditation_sessions';
  static Box get _box => Hive.box(boxName);

  /// Clé unique par séance (permet plusieurs séances le même jour sans
  /// s'écraser).
  static Future<void> addEntry(MeditationSession session) async {
    final key =
        '${session.date.millisecondsSinceEpoch}_${DateTime.now().microsecondsSinceEpoch}';
    await _box.put(key, session.toMap());
  }

  static Future<void> deleteEntry(String key) => _box.delete(key);

  /// Séances d'un jour donné, dans l'ordre chronologique.
  static List<MapEntry<String, MeditationSession>> entriesFor(DateTime day) {
    final dayKey = MeditationSession.keyFor(day);
    return _box.toMap().entries
        .where((e) => e.value is Map)
        .map((e) =>
            MapEntry(e.key.toString(), MeditationSession.fromMap(e.value as Map)))
        .where((e) => e.value.dayKey == dayKey)
        .toList()
      ..sort((a, b) => a.value.date.compareTo(b.value.date));
  }

  static List<MapEntry<String, MeditationSession>> todayEntries() =>
      entriesFor(DateTime.now());

  /// Toutes les séances jamais loggées, triées de la plus récente à la plus
  /// ancienne (ordre d'affichage direct pour un historique).
  static List<MapEntry<String, MeditationSession>> all() {
    return _box.toMap().entries
        .where((e) => e.value is Map)
        .map((e) =>
            MapEntry(e.key.toString(), MeditationSession.fromMap(e.value as Map)))
        .toList()
      ..sort((a, b) => b.value.date.compareTo(a.value.date));
  }

  /// Jours consécutifs (terminant aujourd'hui ou hier) avec au moins une
  /// séance — même logique de marche arrière que `HealthStore.streak`.
  static int streak() {
    final byDay = <String>{};
    for (final e in all()) {
      byDay.add(e.value.dayKey);
    }
    if (byDay.isEmpty) return 0;
    int count = 0;
    var cursor = DateTime.now();
    for (int i = 0; i < 400; i++) {
      final ok = byDay.contains(MeditationSession.keyFor(cursor));
      if (ok) {
        count++;
      } else if (i == 0) {
        // aujourd'hui pas encore médité : on ne casse pas la série, on regarde hier
      } else {
        break;
      }
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return count;
  }

  static Future<void> clearAll() => _box.clear();
}
