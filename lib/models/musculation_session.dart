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
  /// Série FC/temps sur toute la séance (mêmes échantillons Health Connect
  /// que ceux qui donnent avgHr/minHr/maxHr) — sert au graphe FC de l'écran
  /// détail, comme pour une course. Deux listes parallèles (Hive ne stocke
  /// pas de tuples) plutôt qu'un HrPoint : hrTimesMs[i] correspond à hrBpm[i].
  final List<int> hrTimesMs;
  final List<double> hrBpm;

  const MusculationSession({
    required this.date,
    required this.endDate,
    this.avgHr = 0,
    this.minHr = 0,
    this.maxHr = 0,
    this.activeCalories = 0,
    this.hrTimesMs = const [],
    this.hrBpm = const [],
  });

  int get sessionId => date.millisecondsSinceEpoch;
  int get durationSeconds => endDate.difference(date).inSeconds;
  bool get hasHr => avgHr > 0;
  List<DateTime> get hrDates =>
      [for (final ms in hrTimesMs) DateTime.fromMillisecondsSinceEpoch(ms)];

  Map<String, dynamic> toMap() => {
        'date': date.millisecondsSinceEpoch,
        'endDate': endDate.millisecondsSinceEpoch,
        'avgHr': avgHr,
        'minHr': minHr,
        'maxHr': maxHr,
        'activeCalories': activeCalories,
        'hrTimesMs': hrTimesMs,
        'hrBpm': hrBpm,
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
      hrTimesMs: (m['hrTimesMs'] as List?)?.map((e) => (e as num).toInt()).toList() ?? const [],
      hrBpm: (m['hrBpm'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? const [],
    );
  }
}
