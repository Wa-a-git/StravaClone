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

  /// Nombre de courses distinctes ayant fourni au moins une paire — peut
  /// être inférieur à [sampleCount] (une course en fractionné fournit
  /// plusieurs paires, une répétition par palier d'effort).
  final int activityCount;

  /// FC min/max observées parmi les paires utilisées (bpm) — pour montrer
  /// concrètement sur quel intervalle d'effort le calcul s'appuie.
  final double hrMinBpm;
  final double hrMaxBpm;

  /// Allure min/max (sec/km) parmi les paires utilisées — même intention
  /// que la plage de FC, côté vitesse.
  final double paceMinSecPerKm;
  final double paceMaxSecPerKm;

  const Vo2Estimate({
    required this.date,
    required this.value,
    required this.sampleCount,
    this.activityCount = 0,
    this.hrMinBpm = 0,
    this.hrMaxBpm = 0,
    this.paceMinSecPerKm = 0,
    this.paceMaxSecPerKm = 0,
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
        'activityCount': activityCount,
        'hrMinBpm': hrMinBpm,
        'hrMaxBpm': hrMaxBpm,
        'paceMinSecPerKm': paceMinSecPerKm,
        'paceMaxSecPerKm': paceMaxSecPerKm,
      };

  /// Champs de détail absents pour les estimations enregistrées avant leur
  /// introduction — repli à 0 plutôt qu'un crash de désérialisation.
  factory Vo2Estimate.fromMap(Map<dynamic, dynamic> m) => Vo2Estimate(
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        value: (m['value'] as num).toDouble(),
        sampleCount: m['sampleCount'] as int,
        activityCount: (m['activityCount'] as num?)?.toInt() ?? 0,
        hrMinBpm: (m['hrMinBpm'] as num?)?.toDouble() ?? 0,
        hrMaxBpm: (m['hrMaxBpm'] as num?)?.toDouble() ?? 0,
        paceMinSecPerKm: (m['paceMinSecPerKm'] as num?)?.toDouble() ?? 0,
        paceMaxSecPerKm: (m['paceMaxSecPerKm'] as num?)?.toDouble() ?? 0,
      );
}
