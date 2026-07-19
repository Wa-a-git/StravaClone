// lib/data/exercise_library.dart
// Bibliothèque statique d'exercices de musculation, groupés par catégorie
// d'équipement. Ébauche volontairement simple : pas de suivi de charge
// progressive pour l'instant, juste de quoi composer une séance.
import 'package:flutter/material.dart';
import '../theme.dart';

enum ExerciseCategory { bodyweight, dumbbell, barbell, machine, cardio }

extension ExerciseCategoryX on ExerciseCategory {
  String get label => switch (this) {
        ExerciseCategory.bodyweight => 'Poids du corps',
        ExerciseCategory.dumbbell => 'Haltères',
        ExerciseCategory.barbell => 'Barre',
        ExerciseCategory.machine => 'Machines',
        ExerciseCategory.cardio => 'Cardio',
      };

  IconData get icon => switch (this) {
        ExerciseCategory.bodyweight => Icons.accessibility_new_rounded,
        ExerciseCategory.dumbbell => Icons.fitness_center_rounded,
        ExerciseCategory.barbell => Icons.sports_gymnastics_rounded,
        ExerciseCategory.machine => Icons.settings_rounded,
        ExerciseCategory.cardio => Icons.monitor_heart_rounded,
      };

  Color get color => switch (this) {
        ExerciseCategory.bodyweight => kNeonGreen,
        ExerciseCategory.dumbbell => kNeonCyan,
        ExerciseCategory.barbell => kNeonPink,
        ExerciseCategory.machine => kNeonViolet,
        ExerciseCategory.cardio => kNeonAmber,
      };

  /// Cardio se loggue en durée/distance (+ fractionné ou non), pas en
  /// séries/répétitions/charge — voir live_musculation_screen.dart.
  bool get isCardio => this == ExerciseCategory.cardio;
}

class Exercise {
  final String id;
  final String name;
  final ExerciseCategory category;
  final String muscleGroup;

  const Exercise({
    required this.id,
    required this.name,
    required this.category,
    required this.muscleGroup,
  });
}

/// Liste statique — suffisante pour composer une séance dans cette première
/// ébauche. Sera enrichie / rendue dynamique dans une prochaine passe.
const List<Exercise> kExerciseLibrary = [
  // Poids du corps
  Exercise(id: 'pushup', name: 'Pompes', category: ExerciseCategory.bodyweight, muscleGroup: 'Pectoraux'),
  Exercise(id: 'squat_bw', name: 'Squats', category: ExerciseCategory.bodyweight, muscleGroup: 'Jambes'),
  Exercise(id: 'pullup', name: 'Tractions', category: ExerciseCategory.bodyweight, muscleGroup: 'Dos'),
  Exercise(id: 'dips', name: 'Dips', category: ExerciseCategory.bodyweight, muscleGroup: 'Triceps'),
  Exercise(id: 'plank', name: 'Gainage', category: ExerciseCategory.bodyweight, muscleGroup: 'Sangle abdominale'),
  Exercise(id: 'lunge', name: 'Fentes', category: ExerciseCategory.bodyweight, muscleGroup: 'Jambes'),
  Exercise(id: 'crunch', name: 'Crunchs', category: ExerciseCategory.bodyweight, muscleGroup: 'Abdominaux'),

  // Haltères
  Exercise(id: 'db_curl', name: 'Curl haltères', category: ExerciseCategory.dumbbell, muscleGroup: 'Biceps'),
  Exercise(id: 'db_press', name: 'Développé haltères', category: ExerciseCategory.dumbbell, muscleGroup: 'Pectoraux'),
  Exercise(id: 'db_row', name: 'Rowing haltère', category: ExerciseCategory.dumbbell, muscleGroup: 'Dos'),
  Exercise(id: 'db_shoulder', name: 'Développé épaules', category: ExerciseCategory.dumbbell, muscleGroup: 'Épaules'),
  Exercise(id: 'db_lunge', name: 'Fentes haltères', category: ExerciseCategory.dumbbell, muscleGroup: 'Jambes'),

  // Barre
  Exercise(id: 'bb_squat', name: 'Squat barre', category: ExerciseCategory.barbell, muscleGroup: 'Jambes'),
  Exercise(id: 'bb_deadlift', name: 'Soulevé de terre', category: ExerciseCategory.barbell, muscleGroup: 'Chaîne postérieure'),
  Exercise(id: 'bb_bench', name: 'Développé couché', category: ExerciseCategory.barbell, muscleGroup: 'Pectoraux'),
  Exercise(id: 'bb_row', name: 'Rowing barre', category: ExerciseCategory.barbell, muscleGroup: 'Dos'),

  // Machines
  Exercise(id: 'leg_press', name: 'Presse à cuisses', category: ExerciseCategory.machine, muscleGroup: 'Jambes'),
  Exercise(id: 'lat_pulldown', name: 'Tirage vertical', category: ExerciseCategory.machine, muscleGroup: 'Dos'),
  Exercise(id: 'chest_press', name: 'Presse pectoraux', category: ExerciseCategory.machine, muscleGroup: 'Pectoraux'),
  Exercise(id: 'leg_curl', name: 'Leg curl', category: ExerciseCategory.machine, muscleGroup: 'Ischio-jambiers'),

  // Cardio — au même titre que les autres catégories : utilisables dans une
  // séance en direct (ex. un bloc vélo au milieu d'une séance muscu), avec
  // durée/distance chronométrées au lieu de séries/reps (voir
  // live_musculation_screen.dart, ExerciseCategoryX.isCardio).
  Exercise(id: 'rowing_erg', name: 'Rameur', category: ExerciseCategory.cardio, muscleGroup: 'Cardio'),
  Exercise(id: 'bike', name: 'Vélo', category: ExerciseCategory.cardio, muscleGroup: 'Cardio'),
  Exercise(id: 'jump_rope', name: 'Corde à sauter', category: ExerciseCategory.cardio, muscleGroup: 'Cardio'),
  Exercise(id: 'treadmill_run', name: 'Course', category: ExerciseCategory.cardio, muscleGroup: 'Cardio'),
  Exercise(id: 'stair_climber', name: 'Escalier', category: ExerciseCategory.cardio, muscleGroup: 'Cardio'),
];
