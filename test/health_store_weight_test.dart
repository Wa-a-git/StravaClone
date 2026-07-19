import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:arcade_health/services/health_store.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('strava_health_store_');
    Hive.init(tmp.path);
    await Hive.openBox('settings');
    await Hive.openBox(HealthStore.boxName);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('HealthStore.setManualWeightToday', () {
    test('une deuxième saisie le même jour écrase la première', () async {
      await HealthStore.setManualWeightToday(80.0);
      expect(HealthStore.recordFor(DateTime.now())?.weightKg, 80.0);

      await HealthStore.setManualWeightToday(79.5);
      expect(HealthStore.recordFor(DateTime.now())?.weightKg, 79.5);
    });

    test('met aussi à jour HealthProfileStore à chaque saisie', () async {
      await HealthStore.setManualWeightToday(80.0);
      await HealthStore.setManualWeightToday(79.5);
      expect(HealthProfileStore.weightKg, 79.5);
    });

    test('première saisie du jour crée l\'enregistrement', () async {
      expect(HealthStore.recordFor(DateTime.now()), isNull);
      await HealthStore.setManualWeightToday(82.3);
      expect(HealthStore.recordFor(DateTime.now())?.weightKg, 82.3);
    });
  });
}
