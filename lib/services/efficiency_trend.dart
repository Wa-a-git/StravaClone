import 'health_score_service.dart' show TrendInfo, TrendDir;

/// Compare l'efficacité cardiaque (FC moyenne / allure moyenne) à une
/// baseline. Contrairement à `HealthScoreService.trend` (qui varie selon la
/// métrique via `HealthMetric.lowerIsBetter`), ici **plus bas est toujours
/// meilleur** : un ratio qui baisse veut dire un cœur qui bat moins vite
/// pour la même allure, donc une progression — d'où une fonction dédiée
/// plutôt que de complexifier `trend()` avec un cas particulier.
class EfficiencyTrend {
  static TrendInfo compare(
    double current,
    double baseline, {
    double thresholdRatio = 0.02,
  }) {
    if (baseline <= 0 || current <= 0) return TrendInfo.flat;
    final delta = current - baseline;
    final minChange = baseline * thresholdRatio;
    if (delta.abs() < minChange) return TrendInfo.flat;

    final dir = delta > 0 ? TrendDir.up : TrendDir.down;
    final good = delta < 0; // FC plus basse pour la même allure = mieux
    final sign = delta > 0 ? '+' : '';
    final label = '$sign${delta.toStringAsFixed(1)}';
    return TrendInfo(dir: dir, delta: delta, good: good, label: label);
  }

  /// Moyenne d'une liste de ratios — le garde-fou sur le nombre minimal de
  /// valeurs est de la responsabilité de l'appelant (dépend du contexte :
  /// vue d'ensemble vs comparaison par course).
  static double average(List<double> ratios) =>
      ratios.reduce((a, b) => a + b) / ratios.length;
}
