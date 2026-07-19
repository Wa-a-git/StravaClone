import 'package:flutter_test/flutter_test.dart';
import 'package:arcade_health/data/exercise_library.dart';
import 'package:arcade_health/models/musculation_log.dart';

void main() {
  group('MusculationLogEntry.copyWith', () {
    final base = MusculationLogEntry(
      date: DateTime(2026, 7, 10, 18, 30),
      exerciseId: 'db_curl',
      exerciseName: 'Curl haltères',
      category: ExerciseCategory.dumbbell,
      sets: 1,
      reps: 10,
      chargeKg: 12.5,
      sessionId: 1000,
      restSeconds: 60,
      side: 'L',
    );

    test('champs non passés restent inchangés', () {
      final copy = base.copyWith(reps: 12);
      expect(copy.reps, 12);
      expect(copy.chargeKg, 12.5);
      expect(copy.side, 'L');
      expect(copy.date, base.date);
      expect(copy.exerciseId, base.exerciseId);
      expect(copy.sessionId, base.sessionId);
    });

    test('side peut être explicitement effacé (null), pas juste ignoré', () {
      final copy = base.copyWith(side: null);
      expect(copy.side, isNull);
    });

    test('side non passé conserve la valeur d\'origine', () {
      final copy = base.copyWith(reps: 8);
      expect(copy.side, 'L');
    });

    test('champs cardio corrigeables sans toucher au reste', () {
      final cardioBase = MusculationLogEntry(
        date: DateTime(2026, 7, 10, 18, 30),
        exerciseId: 'treadmill_run',
        exerciseName: 'Tapis',
        category: ExerciseCategory.cardio,
        sets: 1,
        reps: 0,
        sessionId: 1000,
        durationSeconds: 600,
        distanceKm: 2.0,
      );
      final copy = cardioBase.copyWith(durationSeconds: 650, distanceKm: 2.2);
      expect(copy.durationSeconds, 650);
      expect(copy.distanceKm, 2.2);
      expect(copy.exerciseId, cardioBase.exerciseId);
    });
  });
}
