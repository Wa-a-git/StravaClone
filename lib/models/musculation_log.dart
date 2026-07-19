// lib/models/musculation_log.dart
import '../data/exercise_library.dart';

/// Un exercice loggé pour un jour donné (séries × répétitions). Persisté en
/// Map simple (toMap/fromMap), même style que DailyHealthRecord — pas de
/// génération de code Hive, plus rapide à itérer pour un flux volontairement
/// minimal ("un truc rapide").
class MusculationLogEntry {
  final DateTime date;
  final String exerciseId;
  final String exerciseName;
  final ExerciseCategory category;
  final int sets;
  final int reps;
  /// Charge par répétition, en kg. 0 = poids du corps / non renseignée (les
  /// entrées créées avant l'ajout de ce champ retombent sur 0, sans casser
  /// leur affichage — juste pas de volume calculable pour elles).
  final double chargeKg;
  /// Identifiant de séance en direct (= horodatage de son début, en ms).
  /// 0 = entrée du log rapide "classique", hors séance (comportement
  /// antérieur à l'ajout du chrono de séance).
  final int sessionId;
  /// Repos pris juste après cette série, avant la suivante. 0 = non
  /// chronométré (log rapide classique, ou dernière série d'une séance).
  final int restSeconds;

  const MusculationLogEntry({
    required this.date,
    required this.exerciseId,
    required this.exerciseName,
    required this.category,
    required this.sets,
    required this.reps,
    this.chargeKg = 0,
    this.sessionId = 0,
    this.restSeconds = 0,
  });

  /// Volume total de la série : séries × répétitions × charge — mesure
  /// standard en musculation pour comparer l'effort d'une séance à l'autre.
  double get volumeKg => sets * reps * chargeKg;

  /// Clé de jour : 'yyyy-MM-dd'.
  static String keyFor(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String get dayKey => keyFor(date);

  Map<String, dynamic> toMap() => {
        'date': date.millisecondsSinceEpoch,
        'exerciseId': exerciseId,
        'exerciseName': exerciseName,
        'category': category.index,
        'sets': sets,
        'reps': reps,
        'chargeKg': chargeKg,
        'sessionId': sessionId,
        'restSeconds': restSeconds,
      };

  factory MusculationLogEntry.fromMap(Map<dynamic, dynamic> m) {
    final categoryIndex = (m['category'] as num?)?.toInt() ?? 0;
    return MusculationLogEntry(
      date: DateTime.fromMillisecondsSinceEpoch(
          (m['date'] as num?)?.toInt() ?? 0),
      exerciseId: (m['exerciseId'] ?? '').toString(),
      exerciseName: (m['exerciseName'] ?? '').toString(),
      category: ExerciseCategory
          .values[categoryIndex.clamp(0, ExerciseCategory.values.length - 1)],
      sets: (m['sets'] as num?)?.toInt() ?? 0,
      reps: (m['reps'] as num?)?.toInt() ?? 0,
      chargeKg: (m['chargeKg'] as num?)?.toDouble() ?? 0,
      sessionId: (m['sessionId'] as num?)?.toInt() ?? 0,
      restSeconds: (m['restSeconds'] as num?)?.toInt() ?? 0,
    );
  }
}
