import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:arcade_health/models/daily_health_record.dart';
import 'package:arcade_health/screens/feed_screen.dart';
import 'package:arcade_health/services/health_store.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('strava_feed_highlight_');
    Hive.init('${tmp.path}/hive');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  DailyHealthRecord dayWith({
    required DateTime date,
    double rhr = 0,
    double distanceKm = 0,
  }) =>
      DailyHealthRecord(date: date, restingHeartRate: rhr, distanceKm: distanceKm);

  Future<void> seedBaseline({double rhr = 60, double distanceKm = 5}) async {
    await Hive.openBox('health_history');
    final today = DateTime.now();
    for (var i = 1; i <= 7; i++) {
      final day = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: i));
      await HealthStore.upsertDay(
          dayWith(date: day, rhr: rhr, distanceKm: distanceKm));
    }
  }

  test('FC repos nettement sous la moyenne 7j -> highlight positif', () async {
    await seedBaseline(rhr: 60);
    final today = dayWith(date: DateTime.now(), rhr: 55);
    final h = dayHighlight(today);
    expect(h, isNotNull);
    expect(h, contains('FC repos'));
    expect(h, contains('sous ta moyenne'));
  });

  test('FC repos nettement au-dessus de la moyenne 7j -> highlight signalé',
      () async {
    await seedBaseline(rhr: 60);
    final today = dayWith(date: DateTime.now(), rhr: 66);
    final h = dayHighlight(today);
    expect(h, isNotNull);
    expect(h, contains('FC repos'));
    expect(h, contains('vs ta moyenne'));
  });

  test('FC repos proche de la moyenne (< 3 bpm d\'écart) -> pas de highlight FC',
      () async {
    await seedBaseline(rhr: 60, distanceKm: 5);
    final today = dayWith(date: DateTime.now(), rhr: 61, distanceKm: 5);
    expect(dayHighlight(today), isNull);
  });

  test('distance nettement au-dessus de la moyenne 7j -> highlight distance',
      () async {
    await seedBaseline(distanceKm: 5);
    final today = dayWith(date: DateTime.now(), distanceKm: 8);
    final h = dayHighlight(today);
    expect(h, isNotNull);
    expect(h, contains('Distance'));
  });

  test('FC repos prioritaire si les deux signaux qualifient', () async {
    await seedBaseline(rhr: 60, distanceKm: 5);
    final today = dayWith(date: DateTime.now(), rhr: 70, distanceKm: 10);
    final h = dayHighlight(today);
    expect(h, isNotNull);
    expect(h, contains('FC repos'));
  });

  test('rien ne dévie -> pas de highlight (pas de remplissage artificiel)',
      () async {
    await seedBaseline(rhr: 60, distanceKm: 5);
    final today = dayWith(date: DateTime.now(), rhr: 60, distanceKm: 5);
    expect(dayHighlight(today), isNull);
  });

  test('pas d\'historique -> pas de highlight (baseline indisponible)', () async {
    await Hive.openBox('health_history');
    final today = dayWith(date: DateTime.now(), rhr: 55, distanceKm: 12);
    expect(dayHighlight(today), isNull);
  });
}
