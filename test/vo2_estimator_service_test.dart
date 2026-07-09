import 'package:flutter_test/flutter_test.dart';
import 'package:arcade_health/models/vo2_estimate.dart';
import 'package:arcade_health/services/vo2_estimator_service.dart';

void main() {
  group('Vo2EstimatorService.vo2AtSpeed', () {
    test('formule ACSM sans pente', () {
      // 10 km/h = 166,67 m/min -> 3.5 + 0.2*166.67 = 36.83
      final v = Vo2EstimatorService.vo2AtSpeed(166.67);
      expect(v, closeTo(36.83, 0.05));
    });

    test('avec une pente positive, le VO2 augmente', () {
      final flat = Vo2EstimatorService.vo2AtSpeed(150);
      final uphill = Vo2EstimatorService.vo2AtSpeed(150, gradePercent: 0.05);
      expect(uphill, greaterThan(flat));
    });
  });

  group('Vo2EstimatorService.speedMPerMin', () {
    test('5 km en 30 min -> 166,67 m/min', () {
      expect(Vo2EstimatorService.speedMPerMin(5000, 1800),
          closeTo(166.67, 0.05));
    });

    test('durée nulle -> 0 (pas de division par zéro)', () {
      expect(Vo2EstimatorService.speedMPerMin(5000, 0), 0);
    });
  });

  group('Vo2EstimatorService.estimateFromPairs — seuils de confiance', () {
    /// Génère des paires (VO2, FC) parfaitement alignées sur une droite
    /// connue FC = a + b·VO2, pour vérifier que la régression retrouve bien
    /// le VO2 max attendu à une FC max donnée.
    List<(double, double)> _linearPairs(double a, double b, List<double> vo2s) =>
        [for (final v in vo2s) (v, a + b * v)];

    test('pas assez de paires (< minPairs) -> null', () {
      final pairs = _linearPairs(60, 2.0, [30, 35, 40]);
      expect(Vo2EstimatorService.estimateFromPairs(pairs), isNull);
    });

    test('assez de paires mais FC toutes identiques (spread nul) -> null', () {
      final pairs = [for (int i = 0; i < 10; i++) (30.0 + i, 140.0)];
      expect(Vo2EstimatorService.estimateFromPairs(pairs), isNull);
    });

    test('pente négative (incohérent physiologiquement) -> null', () {
      // FC qui baisse quand le VO2 monte : dégénéré, on ne doit rien afficher.
      final pairs = _linearPairs(200, -1.5, [30, 35, 40, 45, 50, 55, 60, 65]);
      expect(Vo2EstimatorService.estimateFromPairs(pairs), isNull);
    });

    test(
        'droite connue + FC max observée dans les paires -> retrouve le VO2 max attendu',
        () {
      // FC = 60 + 2·VO2  =>  VO2max = (FCmax - 60) / 2
      const a = 60.0, b = 2.0;
      final vo2s = [30.0, 35.0, 40.0, 45.0, 50.0, 55.0, 60.0, 65.0];
      final pairs = _linearPairs(a, b, vo2s);
      final fcMaxObserved = a + b * vo2s.reduce((x, y) => x > y ? x : y); // 190
      final expectedVo2Max = (fcMaxObserved - a) / b; // = 65

      final result = Vo2EstimatorService.estimateFromPairs(pairs);
      expect(result, isNotNull);
      expect(result!, closeTo(expectedVo2Max, 0.01));
    });

    test('ancrage FC max par âge utilisé si plus haut que le max observé',
        () {
      const a = 60.0, b = 2.0;
      final vo2s = [30.0, 35.0, 40.0, 45.0, 50.0, 55.0, 60.0, 65.0];
      final pairs = _linearPairs(a, b, vo2s);
      // FC max observée = 190 (VO2=65). On force un ancrage par âge plus haut.
      const ageAnchor = 200.0;
      final expectedVo2Max = (ageAnchor - a) / b; // = 70

      final result = Vo2EstimatorService.estimateFromPairs(pairs,
          ageBasedHrMax: ageAnchor);
      expect(result, isNotNull);
      expect(result!, closeTo(expectedVo2Max, 0.01));
    });

    test('ancrage par âge ignoré si plus bas que le max observé (on ne '
        'sous-estime jamais volontairement)', () {
      const a = 60.0, b = 2.0;
      final vo2s = [30.0, 35.0, 40.0, 45.0, 50.0, 55.0, 60.0, 65.0];
      final pairs = _linearPairs(a, b, vo2s);
      final fcMaxObserved = a + b * 65.0; // 190
      final expectedVo2Max = (fcMaxObserved - a) / b; // 65

      final result = Vo2EstimatorService.estimateFromPairs(pairs,
          ageBasedHrMax: 150); // plus bas que l'observé
      expect(result, isNotNull);
      expect(result!, closeTo(expectedVo2Max, 0.01));
    });

    test('résultat hors plage plausible (ex. régression aberrante) -> null',
        () {
      // Pente minuscule -> extrapolation qui explose bien au-delà de 85.
      const a = 10.0, b = 0.05;
      final vo2s = [30.0, 35.0, 40.0, 45.0, 50.0, 55.0, 60.0, 65.0];
      final pairs = _linearPairs(a, b, vo2s);
      expect(Vo2EstimatorService.estimateFromPairs(pairs), isNull);
    });

    test('entre le seuil provisoire (4) et le seuil fiable (8) -> résultat '
        'non-null quand même (estimation provisoire, pas rien du tout)', () {
      const a = 60.0, b = 2.0;
      final pairs = _linearPairs(a, b, [30, 35, 40, 45, 50, 55]); // 6 paires
      expect(Vo2EstimatorService.estimateFromPairs(pairs), isNotNull);
    });

    test('sous le seuil provisoire (< 4) -> null même avec une droite parfaite',
        () {
      const a = 60.0, b = 2.0;
      final pairs = _linearPairs(a, b, [30, 35, 40]); // 3 paires
      expect(Vo2EstimatorService.estimateFromPairs(pairs), isNull);
    });
  });

  group('Vo2EstimatorService.ageBasedHrMax', () {
    test('formule de Tanaka (208 - 0,7×âge)', () {
      expect(Vo2EstimatorService.ageBasedHrMax(30), closeTo(187, 0.01));
      expect(Vo2EstimatorService.ageBasedHrMax(40), closeTo(180, 0.01));
    });
  });

  group('Vo2EstimatorService.confidenceFor', () {
    Vo2Estimate estimateWith(int sampleCount) => Vo2Estimate(
          date: DateTime(2026, 1, 1),
          value: 45,
          sampleCount: sampleCount,
        );

    test('sous le seuil fiable -> provisoire', () {
      final c = Vo2EstimatorService.confidenceFor(estimateWith(6));
      expect(c.isProvisional, isTrue);
      expect(c.caption, contains('6/8'));
    });

    test('au seuil fiable ou au-dessus -> fiable, pas de mention "provisoire"',
        () {
      final c = Vo2EstimatorService.confidenceFor(estimateWith(8));
      expect(c.isProvisional, isFalse);
      expect(c.caption, isNot(contains('provisoire')));
    });
  });

  group('Vo2EstimatorService.categoryFor', () {
    test('âge inconnu -> null (jamais de verdict inventé)', () {
      expect(Vo2EstimatorService.categoryFor(45, age: null), isNull);
    });

    test('homme 25 ans, VO2 élevé -> Élite', () {
      final c = Vo2EstimatorService.categoryFor(60, age: 25, sex: 'M');
      expect(c!.label, 'Élite');
    });

    test('homme 25 ans, VO2 très bas -> Faible', () {
      final c = Vo2EstimatorService.categoryFor(25, age: 25, sex: 'M');
      expect(c!.label, 'Faible');
    });

    test('femme 25 ans, seuils différents des hommes au même VO2', () {
      final menCat = Vo2EstimatorService.categoryFor(40, age: 25, sex: 'M');
      final womenCat = Vo2EstimatorService.categoryFor(40, age: 25, sex: 'F');
      expect(menCat!.label, isNot(womenCat!.label));
    });

    test('sexe non renseigné -> catégorie tout de même calculée (repli moyenne)',
        () {
      final c = Vo2EstimatorService.categoryFor(45, age: 25, sex: null);
      expect(c, isNotNull);
    });

    test('âge au-delà de la dernière tranche -> repli sur la dernière tranche',
        () {
      expect(() => Vo2EstimatorService.categoryFor(30, age: 120, sex: 'M'),
          returnsNormally);
    });
  });
}
