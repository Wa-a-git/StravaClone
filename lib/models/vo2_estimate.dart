/// Estimation locale du VO2 max, calculée par régression FC↔VO2 sur les
/// courses suivies (voir `Vo2EstimatorService`) — distincte du `vo2Max` de
/// `DailyHealthRecord` qui vient du cloud (Google Health API/Fitbit).
/// Persistée en Map simple (comme `DailyHealthRecord`), pas de codegen Hive.
class Vo2Estimate {
  /// Jour du calcul (normalisé à minuit).
  final DateTime date;

  /// Estimation en ml/kg/min.
  final double value;

  /// Nombre de paires (VO2, FC) utilisées — sert à juger la confiance qu'on
  /// peut accorder au chiffre, affiché à côté (jamais un chiffre nu).
  final int sampleCount;

  const Vo2Estimate({
    required this.date,
    required this.value,
    required this.sampleCount,
  });

  static String keyFor(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String get key => keyFor(date);

  Map<String, dynamic> toMap() => {
        'date': date.millisecondsSinceEpoch,
        'value': value,
        'sampleCount': sampleCount,
      };

  factory Vo2Estimate.fromMap(Map<dynamic, dynamic> m) => Vo2Estimate(
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        value: (m['value'] as num).toDouble(),
        sampleCount: m['sampleCount'] as int,
      );
}
