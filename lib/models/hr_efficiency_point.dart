/// Efficacité cardiaque d'une course : FC moyenne rapportée à l'allure
/// moyenne (bpm par km/h). **Plus bas = cœur plus efficace** à cette
/// allure — contrairement à la plupart des métriques de l'app où plus haut
/// est meilleur. Un point par course (pas par jour, contrairement à
/// `Vo2Estimate`) — plusieurs courses le même jour restent distinctes.
/// Persistée en Map simple (comme `Vo2Estimate`), pas de codegen Hive.
class HrEfficiencyPoint {
  /// Date/heure de la course.
  final DateTime date;

  /// FC moyenne / vitesse moyenne (bpm par km/h).
  final double ratio;

  const HrEfficiencyPoint({
    required this.date,
    required this.ratio,
  });

  static String keyFor(DateTime date) => date.millisecondsSinceEpoch.toString();

  String get key => keyFor(date);

  Map<String, dynamic> toMap() => {
        'date': date.millisecondsSinceEpoch,
        'ratio': ratio,
      };

  factory HrEfficiencyPoint.fromMap(Map<dynamic, dynamic> m) => HrEfficiencyPoint(
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        ratio: (m['ratio'] as num).toDouble(),
      );
}
