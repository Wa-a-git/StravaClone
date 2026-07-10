/// Charge d'entraînement d'une course : dérive cardiaque et TRIMP, calculés
/// depuis la série FC continue de la course (voir TrainingLoadService). Un
/// point par course (pas par jour, comme HrEfficiencyPoint) — plusieurs
/// courses le même jour restent distinctes. Persistée en Map simple, pas de
/// codegen Hive.
class TrainingLoadPoint {
  /// Date/heure de la course.
  final DateTime date;

  /// % d'augmentation de la FC moyenne entre la 1re et la 2e moitié de la
  /// course. 0 si non calculable (série trop courte/éparse).
  final double cardiacDriftPct;

  /// Impulsion d'entraînement (TRIMP de Banister). 0 si non calculable.
  final double trimp;

  const TrainingLoadPoint({
    required this.date,
    this.cardiacDriftPct = 0,
    this.trimp = 0,
  });

  static String keyFor(DateTime date) => date.millisecondsSinceEpoch.toString();

  String get key => keyFor(date);

  Map<String, dynamic> toMap() => {
        'date': date.millisecondsSinceEpoch,
        'cardiacDriftPct': cardiacDriftPct,
        'trimp': trimp,
      };

  factory TrainingLoadPoint.fromMap(Map<dynamic, dynamic> m) => TrainingLoadPoint(
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        cardiacDriftPct: (m['cardiacDriftPct'] as num?)?.toDouble() ?? 0,
        trimp: (m['trimp'] as num?)?.toDouble() ?? 0,
      );
}
