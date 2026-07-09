import 'package:flutter_test/flutter_test.dart';
import 'package:arcade_health/models/activity.dart';
import 'package:arcade_health/services/game_service.dart';

void main() {
  group('GameService.statsFor — fusion Force (dénivelé + musculation)', () {
    test('dénivelé seul (pas de musculation) : comportement inchangé', () {
      final acts = [
        Activity(
            date: DateTime(2026, 1, 1),
            distance: 5000,
            duration: 1800,
            route: const [],
            elevations: const [0, 100, 200, 500]),
      ];
      final stats = GameService.statsFor(acts);
      expect(stats.force, (500 / 10).round());
    });

    test('musculation seule (pas de course) : contribue à la Force', () {
      final stats = GameService.statsFor(const [], musculationVolumeKg: 5000);
      expect(stats.force, (5000 / 100).round());
    });

    test('fusion : dénivelé + volume musculation s\'additionnent', () {
      final acts = [
        Activity(
            date: DateTime(2026, 1, 1),
            distance: 5000,
            duration: 1800,
            route: const [],
            elevations: const [0, 100, 200, 500]),
      ];
      final stats =
          GameService.statsFor(acts, musculationVolumeKg: 1000);
      expect(stats.force, (500 / 10 + 1000 / 100).round());
    });

    test('aucune donnée : Force à zéro', () {
      final stats = GameService.statsFor(const []);
      expect(stats.force, 0);
    });
  });
}
