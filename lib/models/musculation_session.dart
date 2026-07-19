// lib/models/musculation_session.dart
// Une séance de musculation en direct : juste l'enveloppe temporelle et les
// données montre pour toute la séance (FC, calories) — les séries elles-mêmes
// restent des MusculationLogEntry rattachées par sessionId, pas dupliquées ici.
class MusculationSession {
  /// = date.millisecondsSinceEpoch — sert aussi de sessionId pour les
  /// MusculationLogEntry rattachées.
  final DateTime date;
  final DateTime endDate;
  final double avgHr;
  final double minHr;
  final double maxHr;
  final double activeCalories;

  const MusculationSession({
    required this.date,
    required this.endDate,
    this.avgHr = 0,
    this.minHr = 0,
    this.maxHr = 0,
    this.activeCalories = 0,
  });

  int get sessionId => date.millisecondsSinceEpoch;
  int get durationSeconds => endDate.difference(date).inSeconds;
  bool get hasHr => avgHr > 0;

  Map<String, dynamic> toMap() => {
        'date': date.millisecondsSinceEpoch,
        'endDate': endDate.millisecondsSinceEpoch,
        'avgHr': avgHr,
        'minHr': minHr,
        'maxHr': maxHr,
        'activeCalories': activeCalories,
      };

  factory MusculationSession.fromMap(Map<dynamic, dynamic> m) {
    return MusculationSession(
      date: DateTime.fromMillisecondsSinceEpoch(
          (m['date'] as num?)?.toInt() ?? 0),
      endDate: DateTime.fromMillisecondsSinceEpoch(
          (m['endDate'] as num?)?.toInt() ?? 0),
      avgHr: (m['avgHr'] as num?)?.toDouble() ?? 0,
      minHr: (m['minHr'] as num?)?.toDouble() ?? 0,
      maxHr: (m['maxHr'] as num?)?.toDouble() ?? 0,
      activeCalories: (m['activeCalories'] as num?)?.toDouble() ?? 0,
    );
  }
}
