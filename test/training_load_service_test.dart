import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:arcade_health/services/health_connect_service.dart' show HrPoint;
import 'package:arcade_health/services/training_load_service.dart';

void main() {
  group('TrainingLoadService.cardiacDrift', () {
    List<HrPoint> series(DateTime start, List<double> bpms, Duration step) =>
        [for (var i = 0; i < bpms.length; i++) (start.add(step * i), bpms[i])];

    test('FC constante -> dérive ~0%', () {
      final start = DateTime(2026, 7, 9, 7, 0);
      final s = series(start, List.filled(20, 140.0), const Duration(minutes: 1));
      final drift = TrainingLoadService.cardiacDrift(s);
      expect(drift, isNotNull);
      expect(drift!, closeTo(0, 0.5));
    });

    test('FC en hausse continue -> dérive positive et cohérente', () {
      final start = DateTime(2026, 7, 9, 7, 0);
      // 1re moitié ~130 bpm, 2e moitié ~150 bpm -> dérive ~ (150-130)/130*100
      final bpms = [
        for (var i = 0; i < 20; i++) 130.0 + i * 1.0, // 130..149
      ];
      final s = series(start, bpms, const Duration(minutes: 1));
      final drift = TrainingLoadService.cardiacDrift(s);
      expect(drift, isNotNull);
      expect(drift!, greaterThan(5));
    });

    test('série trop courte (< minSamples) -> null', () {
      final start = DateTime(2026, 7, 9, 7, 0);
      final s = series(start, [130, 135, 140], const Duration(minutes: 3));
      expect(TrainingLoadService.cardiacDrift(s), isNull);
    });

    test('série assez d\'échantillons mais trop courte en durée -> null', () {
      final start = DateTime(2026, 7, 9, 7, 0);
      // 8 échantillons sur seulement 3 minutes (< minSpan de 8 min)
      final s = series(start, List.filled(8, 140.0), const Duration(seconds: 20));
      expect(TrainingLoadService.cardiacDrift(s), isNull);
    });
  });

  group('TrainingLoadService.trimp', () {
    List<HrPoint> constantSeries(
            DateTime start, double bpm, int count, Duration step) =>
        [for (var i = 0; i < count; i++) (start.add(step * i), bpm)];

    test('FC constante à 50% de réserve cardiaque -> TRIMP attendu (Banister, hommes)', () {
      final start = DateTime(2026, 7, 9, 7, 0);
      // restingHr=60, maxHr=190 -> réserve=130 ; FC=125 -> fraction=0.5
      final s = constantSeries(start, 125, 7, const Duration(minutes: 1));
      final t = TrainingLoadService.trimp(
          hrSeries: s, restingHr: 60, maxHr: 190, sex: null);
      expect(t, isNotNull);
      // 6 intervalles d'1 min à fraction 0.5 : 6 * (1 * 0.5 * 0.64 * e^(1.92*0.5))
      final expected = 6 * (1 * 0.5 * 0.64 * math.exp(1.92 * 0.5));
      expect(t!, closeTo(expected, 0.05));
    });

    test('repli sur les constantes hommes si sexe inconnu, différent des femmes',
        () {
      final start = DateTime(2026, 7, 9, 7, 0);
      final s = constantSeries(start, 125, 7, const Duration(minutes: 1));
      final menOrUnknown = TrainingLoadService.trimp(
          hrSeries: s, restingHr: 60, maxHr: 190, sex: null);
      final women = TrainingLoadService.trimp(
          hrSeries: s, restingHr: 60, maxHr: 190, sex: 'F');
      expect(menOrUnknown, isNotNull);
      expect(women, isNotNull);
      expect(menOrUnknown, isNot(closeTo(women!, 0.01)));
    });

    test('trop peu d\'échantillons -> null', () {
      final start = DateTime(2026, 7, 9, 7, 0);
      final s = constantSeries(start, 125, 3, const Duration(minutes: 1));
      expect(
          TrainingLoadService.trimp(
              hrSeries: s, restingHr: 60, maxHr: 190, sex: null),
          isNull);
    });

    test('réserve cardiaque nulle/négative (maxHr <= restingHr) -> null', () {
      final start = DateTime(2026, 7, 9, 7, 0);
      final s = constantSeries(start, 125, 7, const Duration(minutes: 1));
      expect(
          TrainingLoadService.trimp(
              hrSeries: s, restingHr: 190, maxHr: 190, sex: null),
          isNull);
    });
  });
}
