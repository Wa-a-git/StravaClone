// lib/services/musculation_session_store.dart
// Persistance des séances de musculation en direct (enveloppe FC/calories),
// calquée sur MeditationStore.
import 'package:hive_flutter/hive_flutter.dart';
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

  static Future<void> clearAll() => _box.clear();
}
