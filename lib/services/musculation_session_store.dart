// lib/services/musculation_session_store.dart
// Persistance des séances de musculation en direct (enveloppe FC/calories),
// calquée sur MeditationStore.
import 'package:hive_flutter/hive_flutter.dart';
import '../models/musculation_log.dart' show MusculationLogEntry;
import '../models/musculation_session.dart';

class MusculationSessionStore {
  static const String boxName = 'musculation_sessions';
  static Box get _box => Hive.box(boxName);

  static Future<void> addEntry(MusculationSession session) async {
    await _box.put(session.sessionId.toString(), session.toMap());
  }

  static List<MusculationSession> all() {
    return _box.toMap().entries
        .where((e) => e.value is Map)
        .map((e) => MusculationSession.fromMap(e.value as Map))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Séances d'un jour donné, dans l'ordre chronologique — pour le carrousel
  /// "séance du jour" du Sport tab (une carte par séance, pas un flot brut de
  /// séries).
  static List<MusculationSession> forDay(DateTime day) {
    final key = MusculationLogEntry.keyFor(day);
    return all().where((s) => MusculationLogEntry.keyFor(s.date) == key).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  static Future<void> deleteEntry(int sessionId) =>
      _box.delete(sessionId.toString());

  static Future<void> clearAll() => _box.clear();
}
