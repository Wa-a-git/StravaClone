import 'package:flutter_test/flutter_test.dart';
import 'package:arcade_health/models/daily_health_record.dart';
import 'package:arcade_health/services/health_insights_service.dart';

void main() {
  group('HealthInsightsService.hrvZScore', () {
    test('valeur du jour = moyenne de l\'historique -> z-score ~0', () {
      // Historique varié (pas constant, sinon écart-type nul -> null),
      // moyenne exacte = 50.0.
      final history = [45.0, 50.0, 55.0, 48.0, 52.0, 50.0, 49.0, 51.0];
      final z = HealthInsightsService.hrvZScore(50.0, history);
      expect(z, isNotNull);
      expect(z!, closeTo(0, 0.01));
    });

    test('valeur du jour nettement au-dessus de la moyenne -> z-score positif', () {
      final history = [40.0, 42.0, 38.0, 41.0, 39.0, 40.0];
      final z = HealthInsightsService.hrvZScore(60.0, history);
      expect(z, isNotNull);
      expect(z!, greaterThan(1));
    });

    test('moins de 5 jours d\'historique -> null', () {
      final z = HealthInsightsService.hrvZScore(50.0, [40.0, 45.0, 42.0]);
      expect(z, isNull);
    });

    test('écart-type nul (historique constant) -> null', () {
      final z = HealthInsightsService.hrvZScore(55.0, List.filled(10, 40.0));
      expect(z, isNull);
    });

    test('valeur du jour = 0 (pas de mesure) -> null', () {
      final z = HealthInsightsService.hrvZScore(0.0, [40.0, 45.0, 42.0, 44.0, 41.0]);
      expect(z, isNull);
    });
  });

  group('HealthInsightsService.deepSleepRatio', () {
    DailyHealthRecord recordWithSleep({
      double deep = 0,
      double light = 0,
      double rem = 0,
    }) =>
        DailyHealthRecord(
          date: DateTime(2026, 7, 9),
          sleepDeepMin: deep,
          sleepLightMin: light,
          sleepRemMin: rem,
        );

    test('90 min profond sur 480 min total -> ratio 0.1875', () {
      final r = recordWithSleep(deep: 90, light: 300, rem: 90);
      expect(HealthInsightsService.deepSleepRatio(r), closeTo(0.1875, 0.001));
    });

    test('aucun sommeil enregistré -> null', () {
      final r = recordWithSleep();
      expect(HealthInsightsService.deepSleepRatio(r), isNull);
    });
  });

  group('HealthInsightsService.sleepDebtHours', () {
    DailyHealthRecord dayWith(double sleepHours) => DailyHealthRecord(
          date: DateTime(2026, 7, 9),
          sleepDeepMin: sleepHours * 60,
        );

    test('7 nuits de 8h pile -> dette nulle', () {
      final days = List.generate(7, (_) => dayWith(8.0));
      expect(HealthInsightsService.sleepDebtHours(days), closeTo(0, 0.01));
    });

    test('7 nuits de 6h -> 2h de dette par nuit, 14h cumulées', () {
      final days = List.generate(7, (_) => dayWith(6.0));
      expect(HealthInsightsService.sleepDebtHours(days), closeTo(14, 0.01));
    });

    test('nuits plus longues que la cible -> dette négative (surplus)', () {
      final days = List.generate(7, (_) => dayWith(9.0));
      expect(HealthInsightsService.sleepDebtHours(days), closeTo(-7, 0.01));
    });

    test('jours sans sommeil enregistré ignorés (pas de dette artificielle)',
        () {
      final days = [dayWith(8.0), DailyHealthRecord(date: DateTime(2026, 7, 8))];
      expect(HealthInsightsService.sleepDebtHours(days), closeTo(0, 0.01));
    });
  });

  group('HealthInsightsService.physioAnomalyInsight', () {
    DailyHealthRecord baseToday({
      double rhr = 0,
      double hrv = 0,
      double resp = 0,
    }) =>
        DailyHealthRecord(
          date: DateTime(2026, 7, 9),
          restingHeartRate: rhr,
          hrv: hrv,
          respiratoryRate: resp,
        );

    test('un seul signal dévie -> pas d\'alerte (évite les faux positifs)', () {
      final today = baseToday(rhr: 65, hrv: 50, resp: 14);
      final insight = HealthInsightsService.physioAnomalyInsight(
        today: today,
        rhrBaseline: 60, // +5 : dévie
        hrvBaseline: 50, // ratio 1.0 : normal
        respBaseline: 14, // normal
      );
      expect(insight, isNull);
    });

    test('deux signaux dévient (FC repos + VFC) -> alerte déclenchée', () {
      final today = baseToday(rhr: 65, hrv: 35, resp: 14);
      final insight = HealthInsightsService.physioAnomalyInsight(
        today: today,
        rhrBaseline: 60, // +5 : dévie
        hrvBaseline: 50, // ratio 0.7 : dévie
        respBaseline: 14, // normal
      );
      expect(insight, isNotNull);
      expect(insight!.id, 'physio_anomaly');
    });

    test('température cutanée compte comme signal supplémentaire si fournie',
        () {
      // FC repos et VFC dans la norme ; seule la respiration dévie (+4).
      final today = baseToday(rhr: 60, hrv: 50, resp: 18);
      final withoutTemp = HealthInsightsService.physioAnomalyInsight(
        today: today,
        rhrBaseline: 60,
        hrvBaseline: 50,
        respBaseline: 14,
      );
      expect(withoutTemp, isNull);

      final withTemp = HealthInsightsService.physioAnomalyInsight(
        today: today,
        rhrBaseline: 60,
        hrvBaseline: 50,
        respBaseline: 14,
        skinTempDeltaC: 0.8,
      );
      expect(withTemp, isNotNull);
    });

    test('rien ne dévie -> pas d\'alerte', () {
      final today = baseToday(rhr: 60, hrv: 50, resp: 14);
      final insight = HealthInsightsService.physioAnomalyInsight(
        today: today,
        rhrBaseline: 60,
        hrvBaseline: 50,
        respBaseline: 14,
      );
      expect(insight, isNull);
    });
  });
}
