// lib/models/meditation_session.dart
// Une séance de méditation chronométrée. Persistée en Map simple, même style
// que MusculationLogEntry — pas de génération de code Hive.
class MeditationSession {
  final DateTime date;
  final int durationSeconds;
  /// FC moyenne/min/max pendant la séance, lues depuis Health Connect sur la
  /// fenêtre [date, date + durationSeconds]. 0 = pas de donnée (montre non
  /// portée, permission refusée, etc.) — jamais bloquant pour l'enregistrement.
  final double avgHr;
  final double minHr;
  final double maxHr;

  const MeditationSession({
    required this.date,
    required this.durationSeconds,
    this.avgHr = 0,
    this.minHr = 0,
    this.maxHr = 0,
  });

  bool get hasHr => avgHr > 0;

  /// Clé de jour : 'yyyy-MM-dd'.
  static String keyFor(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String get dayKey => keyFor(date);

  Map<String, dynamic> toMap() => {
        'date': date.millisecondsSinceEpoch,
        'durationSeconds': durationSeconds,
        'avgHr': avgHr,
        'minHr': minHr,
        'maxHr': maxHr,
      };

  factory MeditationSession.fromMap(Map<dynamic, dynamic> m) {
    return MeditationSession(
      date: DateTime.fromMillisecondsSinceEpoch(
          (m['date'] as num?)?.toInt() ?? 0),
      durationSeconds: (m['durationSeconds'] as num?)?.toInt() ?? 0,
      avgHr: (m['avgHr'] as num?)?.toDouble() ?? 0,
      minHr: (m['minHr'] as num?)?.toDouble() ?? 0,
      maxHr: (m['maxHr'] as num?)?.toDouble() ?? 0,
    );
  }
}
