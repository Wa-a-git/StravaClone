import 'package:flutter_test/flutter_test.dart';
import 'package:arcade_health/models/activity.dart';

void main() {
  Activity baseActivity({
    required List<List<double>> route,
    List<int>? pointSeconds,
  }) =>
      Activity(
        date: DateTime(2026, 7, 6, 7, 0),
        distance: 1000,
        duration: 600,
        route: route,
        pointSeconds: pointSeconds,
      );

  group('Activity.speedSeries', () {
    test('pointSeconds absent -> liste vide (anciennes activités)', () {
      final a = baseActivity(route: [
        [0.0, 0.0],
        [0.0009, 0.0],
      ]);
      expect(a.speedSeries, isEmpty);
    });

    test('pointSeconds et route de tailles différentes -> liste vide', () {
      final a = baseActivity(
        route: [
          [0.0, 0.0],
          [0.0009, 0.0],
          [0.0018, 0.0],
        ],
        pointSeconds: [0, 10],
      );
      expect(a.speedSeries, isEmpty);
    });

    test('deux points, ~100 m en 10 s -> environ 36 km/h', () {
      // 0.0009° de latitude ≈ 100 m à l'équateur.
      final a = baseActivity(
        route: [
          [0.0, 0.0],
          [0.0009, 0.0],
        ],
        pointSeconds: [0, 10],
      );
      final series = a.speedSeries;
      expect(series, hasLength(1));
      expect(series.first.$2, closeTo(36.07, 0.5));
      expect(series.first.$1, 10);
    });

    test('delta de temps nul entre deux points -> point ignoré', () {
      final a = baseActivity(
        route: [
          [0.0, 0.0],
          [0.0009, 0.0],
        ],
        pointSeconds: [10, 10],
      );
      expect(a.speedSeries, isEmpty);
    });

    test('saut GPS aberrant (> 40 km/h) -> point filtré', () {
      // 1° de latitude ≈ 111 km, parcouru en 1 s : bien au-delà du possible.
      final a = baseActivity(
        route: [
          [0.0, 0.0],
          [1.0, 0.0],
        ],
        pointSeconds: [0, 1],
      );
      expect(a.speedSeries, isEmpty);
    });

    test('plusieurs points réguliers -> une série lissée non vide', () {
      final route = <List<double>>[];
      final seconds = <int>[];
      for (var i = 0; i <= 10; i++) {
        route.add([0.0009 * i, 0.0]); // ~100 m entre chaque point
        seconds.add(i * 10); // toutes les 10 s
      }
      final a = baseActivity(route: route, pointSeconds: seconds);
      final series = a.speedSeries;
      expect(series.length, 10); // un delta par paire de points consécutifs
      for (final p in series) {
        expect(p.$2, closeTo(36.07, 1.0)); // vitesse constante attendue
      }
    });
  });
}
