import 'dart:math' as math;
import 'health_connect_service.dart' show HrPoint;

/// Calculs purs de charge d'entraînement à partir d'une série FC continue
/// d'une course (`ActivityVitals.hrSeries`) — testables sans Health Connect
/// ni Hive. Réutilise la même série déjà récupérée pour le VO2 max/efficacité
/// cardiaque (voir `Vo2EstimatorService._pairsForActivity`), aucun appel
/// réseau supplémentaire.
class TrainingLoadService {
  /// Nombre minimal d'échantillons FC pour un calcul défendable.
  static const int minSamples = 6;

  /// Durée minimale couverte par la série pour que la dérive/le TRIMP aient
  /// un sens (une course de 2 minutes n'a pas de "première/seconde moitié"
  /// physiologiquement significative).
  static const Duration minSpan = Duration(minutes: 8);

  /// % d'augmentation de la FC moyenne entre la 1re et la 2e moitié de la
  /// série (découpage par durée, pas par nombre d'échantillons — un
  /// échantillonnage irrégulier fausserait un découpage par index). Null si
  /// la série est trop courte/éparse pour être défendable.
  static double? cardiacDrift(List<HrPoint> hrSeries) {
    if (hrSeries.length < minSamples) return null;
    final sorted = [...hrSeries]..sort((a, b) => a.$1.compareTo(b.$1));
    final start = sorted.first.$1;
    final end = sorted.last.$1;
    if (end.difference(start) < minSpan) return null;

    final mid = start.add(end.difference(start) ~/ 2);
    final firstHalf = sorted.where((s) => s.$1.isBefore(mid)).map((s) => s.$2).toList();
    final secondHalf = sorted.where((s) => !s.$1.isBefore(mid)).map((s) => s.$2).toList();
    if (firstHalf.isEmpty || secondHalf.isEmpty) return null;

    final avgFirst = firstHalf.reduce((a, b) => a + b) / firstHalf.length;
    final avgSecond = secondHalf.reduce((a, b) => a + b) / secondHalf.length;
    if (avgFirst <= 0) return null;
    return (avgSecond - avgFirst) / avgFirst * 100;
  }

  /// TRIMP de Banister : intègre la charge de chaque échantillon FC pondérée
  /// par la durée qui lui est implicitement associée (l'écart au prochain
  /// échantillon, plutôt que de supposer un échantillonnage régulier à la
  /// minute — l'échantillonnage Health Connect n'est pas garanti uniforme).
  /// `sex` : 'M'/'F'/null — repli sur les constantes hommes (1.92/0.64) si
  /// non renseigné, même convention que `Vo2EstimatorService.categoryFor`.
  /// Null si la réserve cardiaque (maxHr - restingHr) n'est pas exploitable.
  static double? trimp({
    required List<HrPoint> hrSeries,
    required double restingHr,
    required double maxHr,
    String? sex,
  }) {
    if (hrSeries.length < minSamples) return null;
    final hrReserve = maxHr - restingHr;
    if (hrReserve <= 0) return null;

    final sorted = [...hrSeries]..sort((a, b) => a.$1.compareTo(b.$1));
    final k = sex == 'F' ? 1.67 : 1.92;
    final c = sex == 'F' ? 0.86 : 0.64;

    double total = 0;
    for (var i = 0; i < sorted.length - 1; i++) {
      final durationMin =
          sorted[i + 1].$1.difference(sorted[i].$1).inSeconds / 60.0;
      if (durationMin <= 0 || durationMin > 10) continue; // trou de données : ignoré
      final hrrFraction = ((sorted[i].$2 - restingHr) / hrReserve).clamp(0.0, 1.0);
      total += durationMin * hrrFraction * c * math.exp(k * hrrFraction);
    }
    return total;
  }
}
