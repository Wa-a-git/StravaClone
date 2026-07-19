import 'package:flutter_test/flutter_test.dart';
import 'package:arcade_health/models/health_snapshot.dart';
import 'package:arcade_health/services/health_score_service.dart';

void main() {
  group('HealthScoreService.activityScore — crédit musculation', () {
    test('aucune donnée montre, aucune séance : score à zéro', () {
      expect(HealthScoreService.activityScore(const HealthSnapshot()), 0);
    });

    test('séance complète (≥ objectif) sans donnée montre : score > 0', () {
      final score = HealthScoreService.activityScore(const HealthSnapshot(),
          musculationMinutes: HealthScoreTuning.musculationGoalMinutes);
      // 30% du score vient de la part musculation, plafonnée à 100.
      expect(score, 30);
    });

    test('séance longue ne dépasse jamais le plafond de sa part (30%)', () {
      final score = HealthScoreService.activityScore(const HealthSnapshot(),
          musculationMinutes: HealthScoreTuning.musculationGoalMinutes * 3);
      expect(score, 30);
    });

    test('pas + séance s\'additionnent plutôt que de s\'exclure', () {
      const snapshot = HealthSnapshot(steps: 10000); // objectif pas atteint
      final stepsOnly = HealthScoreService.activityScore(snapshot);
      final stepsAndSession = HealthScoreService.activityScore(snapshot,
          musculationMinutes: HealthScoreTuning.musculationGoalMinutes);
      expect(stepsOnly, 35); // 35% de la formule
      expect(stepsAndSession, 65); // 35% pas + 30% séance
    });
  });
}
