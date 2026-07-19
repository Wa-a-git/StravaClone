// lib/data/exercise_library.dart
// Bibliothèque statique d'exercices de musculation, groupée par groupe
// musculaire puis par équipement (Machines/Haltères/Poulie/Barre/Poids du
// corps) — reflète comment on pense une séance ("aujourd'hui c'est pecs"),
// pas juste l'équipement disponible.
import 'package:flutter/material.dart';
import '../theme.dart';

// L'ordre des valeurs fixe leur index, persisté tel quel dans
// MusculationLogEntry.toMap() ('category': category.index) — cable est
// ajouté en dernier pour ne pas décaler les index déjà enregistrés
// (bodyweight=0, dumbbell=1, barbell=2, machine=3, cardio=4).
enum ExerciseCategory { bodyweight, dumbbell, barbell, machine, cardio, cable }

extension ExerciseCategoryX on ExerciseCategory {
  String get label => switch (this) {
        ExerciseCategory.bodyweight => 'Poids du corps',
        ExerciseCategory.dumbbell => 'Haltères',
        ExerciseCategory.barbell => 'Barre',
        ExerciseCategory.machine => 'Machines',
        ExerciseCategory.cable => 'Poulie',
        ExerciseCategory.cardio => 'Cardio',
      };

  IconData get icon => switch (this) {
        ExerciseCategory.bodyweight => Icons.accessibility_new_rounded,
        ExerciseCategory.dumbbell => Icons.fitness_center_rounded,
        ExerciseCategory.barbell => Icons.sports_gymnastics_rounded,
        ExerciseCategory.machine => Icons.settings_rounded,
        ExerciseCategory.cable => Icons.cable_rounded,
        ExerciseCategory.cardio => Icons.monitor_heart_rounded,
      };

  Color get color => switch (this) {
        ExerciseCategory.bodyweight => kNeonGreen,
        ExerciseCategory.dumbbell => kNeonCyan,
        ExerciseCategory.barbell => kNeonPink,
        ExerciseCategory.machine => kNeonViolet,
        ExerciseCategory.cable => kNeonRed,
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
  /// Se fait un côté à la fois (ex. rowing à un bras) — déclenche le
  /// sélecteur Gauche/Droite dans la séance en direct. false = mouvement
  /// bilatéral classique (les deux côtés ensemble, ou alterné dans la même
  /// série sans qu'il soit utile de distinguer).
  final bool isUnilateral;

  const Exercise({
    required this.id,
    required this.name,
    required this.category,
    required this.muscleGroup,
    this.isUnilateral = false,
  });
}

/// Groupe musculaire principal — sert de premier niveau de filtre dans le
/// sélecteur d'exercice (voir live_musculation_screen.dart), la catégorie
/// d'équipement restant le second niveau. Cardio n'a pas de "groupe" à
/// proprement parler (voir ExerciseCategoryX.isCardio) : ses exercices
/// portent muscleGroup = 'Cardio' et n'apparaissent pas dans ce filtre.
const List<String> kMuscleGroups = [
  'Pectoraux',
  'Dos',
  'Épaules',
  'Jambes',
  'Biceps',
  'Triceps',
  'Abdominaux',
];

const List<Exercise> kExerciseLibrary = [
  // ── PECTORAUX ──────────────────────────────────────────────────────────
  // Machines
  Exercise(id: 'chest_press', name: 'Développé couché machine (Chest Press)', category: ExerciseCategory.machine, muscleGroup: 'Pectoraux'),
  Exercise(id: 'machine_incline_press', name: 'Développé incliné machine', category: ExerciseCategory.machine, muscleGroup: 'Pectoraux'),
  Exercise(id: 'pec_deck', name: 'Écarté à la machine (Pec Deck)', category: ExerciseCategory.machine, muscleGroup: 'Pectoraux'),
  Exercise(id: 'machine_dips_chest', name: 'Machine à dips (faisceau inférieur)', category: ExerciseCategory.machine, muscleGroup: 'Pectoraux'),
  // Haltères
  Exercise(id: 'db_press', name: 'Développé couché haltères', category: ExerciseCategory.dumbbell, muscleGroup: 'Pectoraux'),
  Exercise(id: 'db_incline_press', name: 'Développé incliné haltères', category: ExerciseCategory.dumbbell, muscleGroup: 'Pectoraux'),
  Exercise(id: 'db_decline_press', name: 'Développé décliné haltères', category: ExerciseCategory.dumbbell, muscleGroup: 'Pectoraux'),
  Exercise(id: 'db_flye_flat', name: 'Écartés couchés haltères', category: ExerciseCategory.dumbbell, muscleGroup: 'Pectoraux'),
  Exercise(id: 'db_flye_incline', name: 'Écartés inclinés haltères', category: ExerciseCategory.dumbbell, muscleGroup: 'Pectoraux'),
  Exercise(id: 'db_pullover_chest', name: 'Pull-over', category: ExerciseCategory.dumbbell, muscleGroup: 'Pectoraux'),
  // Poulie
  Exercise(id: 'cable_flye_high', name: 'Écartés à la poulie vis-à-vis haute', category: ExerciseCategory.cable, muscleGroup: 'Pectoraux'),
  Exercise(id: 'cable_flye_low', name: 'Écartés à la poulie vis-à-vis basse', category: ExerciseCategory.cable, muscleGroup: 'Pectoraux'),
  Exercise(id: 'cable_flye_mid', name: 'Écartés à la poulie horizontale', category: ExerciseCategory.cable, muscleGroup: 'Pectoraux'),
  Exercise(id: 'cable_bench_press', name: 'Développé couché à la poulie', category: ExerciseCategory.cable, muscleGroup: 'Pectoraux'),
  // Barre
  Exercise(id: 'bb_bench', name: 'Développé couché', category: ExerciseCategory.barbell, muscleGroup: 'Pectoraux'),
  Exercise(id: 'bb_incline_bench', name: 'Développé incliné', category: ExerciseCategory.barbell, muscleGroup: 'Pectoraux'),
  Exercise(id: 'bb_decline_bench', name: 'Développé décliné', category: ExerciseCategory.barbell, muscleGroup: 'Pectoraux'),
  Exercise(id: 'bb_close_grip_bench', name: 'Développé couché prise serrée', category: ExerciseCategory.barbell, muscleGroup: 'Pectoraux'),

  // ── DOS ────────────────────────────────────────────────────────────────
  // Machines
  Exercise(id: 'lat_pulldown', name: 'Tirage vertical (Lat Pulldown)', category: ExerciseCategory.machine, muscleGroup: 'Dos'),
  Exercise(id: 'rowing_machine', name: 'Tirage horizontal (Rowing machine)', category: ExerciseCategory.machine, muscleGroup: 'Dos'),
  Exercise(id: 'tbar_row', name: 'Rowing T-Bar avec appui poitrine', category: ExerciseCategory.machine, muscleGroup: 'Dos'),
  Exercise(id: 'close_grip_pulldown', name: 'Tirage vertical prise serrée', category: ExerciseCategory.machine, muscleGroup: 'Dos'),
  Exercise(id: 'back_extension_machine', name: 'Machine à lombaires (Extensions au banc)', category: ExerciseCategory.machine, muscleGroup: 'Lombaires'),
  // Haltères
  Exercise(id: 'db_one_arm_row', name: 'Rowing à un bras (Bûcheron)', category: ExerciseCategory.dumbbell, muscleGroup: 'Dos', isUnilateral: true),
  Exercise(id: 'db_row', name: 'Rowing haltères buste penché', category: ExerciseCategory.dumbbell, muscleGroup: 'Dos'),
  Exercise(id: 'db_pullover_lat', name: 'Pull-over haltère (dos)', category: ExerciseCategory.dumbbell, muscleGroup: 'Dos'),
  // Poulie
  Exercise(id: 'cable_lat_pulldown_wide', name: 'Tirage poitrine (barre lat, prise large)', category: ExerciseCategory.cable, muscleGroup: 'Dos'),
  Exercise(id: 'cable_pulldown_neck', name: 'Tirage nuque', category: ExerciseCategory.cable, muscleGroup: 'Dos'),
  Exercise(id: 'cable_seated_row', name: 'Rowing assis à la poulie basse', category: ExerciseCategory.cable, muscleGroup: 'Dos'),
  Exercise(id: 'cable_pulldown_straight_arm', name: 'Pull-down bras tendus', category: ExerciseCategory.cable, muscleGroup: 'Dos'),
  Exercise(id: 'cable_single_arm_pulldown', name: 'Tirage vertical unilatéral', category: ExerciseCategory.cable, muscleGroup: 'Dos', isUnilateral: true),
  // Barre et Poids du corps
  Exercise(id: 'pullup', name: 'Tractions pronation (Pull-ups)', category: ExerciseCategory.bodyweight, muscleGroup: 'Dos'),
  Exercise(id: 'chinup', name: 'Tractions supination (Chin-ups)', category: ExerciseCategory.bodyweight, muscleGroup: 'Dos'),
  Exercise(id: 'bb_row_bent', name: 'Rowing barre buste penché (Yates)', category: ExerciseCategory.barbell, muscleGroup: 'Dos'),
  Exercise(id: 'bb_deadlift', name: 'Soulevé de terre', category: ExerciseCategory.barbell, muscleGroup: 'Chaîne postérieure'),
  Exercise(id: 'bb_rack_pull', name: 'Rack pulls', category: ExerciseCategory.barbell, muscleGroup: 'Dos'),

  // ── ÉPAULES (Deltoïdes) ──────────────────────────────────────────────────
  // Machines
  Exercise(id: 'machine_shoulder_press', name: 'Développé épaules machine (Shoulder Press)', category: ExerciseCategory.machine, muscleGroup: 'Épaules'),
  Exercise(id: 'machine_lateral_raise', name: 'Élévations latérales machine', category: ExerciseCategory.machine, muscleGroup: 'Épaules'),
  Exercise(id: 'reverse_pec_deck', name: 'Reverse Pec Deck (faisceau postérieur)', category: ExerciseCategory.machine, muscleGroup: 'Épaules'),
  // Haltères
  Exercise(id: 'db_shoulder', name: 'Développé militaire assis ou debout', category: ExerciseCategory.dumbbell, muscleGroup: 'Épaules'),
  Exercise(id: 'db_arnold_press', name: 'Développé Arnold', category: ExerciseCategory.dumbbell, muscleGroup: 'Épaules'),
  Exercise(id: 'db_lateral_raise', name: 'Élévations latérales', category: ExerciseCategory.dumbbell, muscleGroup: 'Épaules'),
  Exercise(id: 'db_front_raise', name: 'Élévations frontales', category: ExerciseCategory.dumbbell, muscleGroup: 'Épaules'),
  Exercise(id: 'db_rear_delt_fly', name: 'Oiseau (élévations postérieures buste penché)', category: ExerciseCategory.dumbbell, muscleGroup: 'Épaules'),
  Exercise(id: 'db_shrug', name: 'Shrugs (haussements d\'épaules)', category: ExerciseCategory.dumbbell, muscleGroup: 'Trapèzes'),
  // Poulie
  Exercise(id: 'cable_lateral_raise_uni', name: 'Élévations latérales unilatérales à la poulie basse', category: ExerciseCategory.cable, muscleGroup: 'Épaules', isUnilateral: true),
  Exercise(id: 'cable_front_raise', name: 'Élévations frontales à la poulie basse', category: ExerciseCategory.cable, muscleGroup: 'Épaules'),
  Exercise(id: 'cable_face_pull', name: 'Face pull à la poulie haute', category: ExerciseCategory.cable, muscleGroup: 'Épaules'),
  Exercise(id: 'cable_rear_delt_fly', name: 'Oiseau à la poulie vis-à-vis', category: ExerciseCategory.cable, muscleGroup: 'Épaules'),
  // Barre
  Exercise(id: 'bb_overhead_press', name: 'Développé militaire debout (Overhead Press)', category: ExerciseCategory.barbell, muscleGroup: 'Épaules'),
  Exercise(id: 'bb_upright_row', name: 'Tirage menton (Upright row)', category: ExerciseCategory.barbell, muscleGroup: 'Épaules'),
  Exercise(id: 'bb_shrug', name: 'Shrugs à la barre', category: ExerciseCategory.barbell, muscleGroup: 'Trapèzes'),

  // ── JAMBES (Quadriceps, Ischio-jambiers, Fessiers, Mollets) ─────────────
  // Machines
  Exercise(id: 'leg_press', name: 'Presse à cuisses inclinée (Leg Press)', category: ExerciseCategory.machine, muscleGroup: 'Jambes'),
  Exercise(id: 'leg_press_horizontal', name: 'Presse à cuisses horizontale', category: ExerciseCategory.machine, muscleGroup: 'Jambes'),
  Exercise(id: 'hack_squat', name: 'Hack Squat', category: ExerciseCategory.machine, muscleGroup: 'Jambes'),
  Exercise(id: 'leg_extension', name: 'Leg Extension', category: ExerciseCategory.machine, muscleGroup: 'Quadriceps'),
  Exercise(id: 'leg_curl', name: 'Leg Curl allongé', category: ExerciseCategory.machine, muscleGroup: 'Ischio-jambiers'),
  Exercise(id: 'leg_curl_seated', name: 'Leg Curl assis', category: ExerciseCategory.machine, muscleGroup: 'Ischio-jambiers'),
  Exercise(id: 'glute_kickback_machine', name: 'Machine à fessiers (Glute Kickback)', category: ExerciseCategory.machine, muscleGroup: 'Fessiers'),
  Exercise(id: 'abductor_machine', name: 'Machine Abducteurs (extérieur cuisses)', category: ExerciseCategory.machine, muscleGroup: 'Fessiers'),
  Exercise(id: 'adductor_machine', name: 'Machine Adducteurs (intérieur cuisses)', category: ExerciseCategory.machine, muscleGroup: 'Intérieur cuisses'),
  Exercise(id: 'calf_raise_standing_machine', name: 'Machine à mollets debout', category: ExerciseCategory.machine, muscleGroup: 'Mollets'),
  Exercise(id: 'calf_raise_seated_machine', name: 'Machine à mollets assis', category: ExerciseCategory.machine, muscleGroup: 'Mollets'),
  // Haltères
  Exercise(id: 'db_lunge', name: 'Fentes avant haltères', category: ExerciseCategory.dumbbell, muscleGroup: 'Jambes'),
  Exercise(id: 'db_lunge_reverse', name: 'Fentes arrière haltères', category: ExerciseCategory.dumbbell, muscleGroup: 'Jambes'),
  Exercise(id: 'db_lunge_walking', name: 'Fentes marchées haltères', category: ExerciseCategory.dumbbell, muscleGroup: 'Jambes'),
  Exercise(id: 'db_goblet_squat', name: 'Goblet Squat', category: ExerciseCategory.dumbbell, muscleGroup: 'Jambes'),
  Exercise(id: 'db_bulgarian_split_squat', name: 'Squat bulgare', category: ExerciseCategory.dumbbell, muscleGroup: 'Jambes', isUnilateral: true),
  Exercise(id: 'db_rdl', name: 'Soulevé de terre jambes tendues (RDL)', category: ExerciseCategory.dumbbell, muscleGroup: 'Ischio-jambiers'),
  Exercise(id: 'db_step_up', name: 'Montées sur banc (Step-ups)', category: ExerciseCategory.dumbbell, muscleGroup: 'Jambes'),
  Exercise(id: 'db_calf_raise_uni', name: 'Soulevé de mollets debout unilatéral', category: ExerciseCategory.dumbbell, muscleGroup: 'Mollets', isUnilateral: true),
  // Poulie
  Exercise(id: 'cable_glute_kickback', name: 'Kickback fessiers à la poulie basse', category: ExerciseCategory.cable, muscleGroup: 'Fessiers', isUnilateral: true),
  Exercise(id: 'cable_abduction', name: 'Abductions à la poulie basse', category: ExerciseCategory.cable, muscleGroup: 'Fessiers', isUnilateral: true),
  Exercise(id: 'cable_adduction', name: 'Adductions à la poulie basse', category: ExerciseCategory.cable, muscleGroup: 'Intérieur cuisses', isUnilateral: true),
  // Barre
  Exercise(id: 'bb_squat', name: 'Back squat (Squat classique)', category: ExerciseCategory.barbell, muscleGroup: 'Jambes'),
  Exercise(id: 'bb_front_squat', name: 'Front squat', category: ExerciseCategory.barbell, muscleGroup: 'Jambes'),
  Exercise(id: 'bb_lunge', name: 'Fentes à la barre', category: ExerciseCategory.barbell, muscleGroup: 'Jambes'),
  Exercise(id: 'bb_romanian_deadlift', name: 'Soulevé de terre roumain', category: ExerciseCategory.barbell, muscleGroup: 'Ischio-jambiers'),
  Exercise(id: 'bb_hip_thrust', name: 'Hip Thrust', category: ExerciseCategory.barbell, muscleGroup: 'Fessiers'),
  Exercise(id: 'bb_good_morning', name: 'Good Morning', category: ExerciseCategory.barbell, muscleGroup: 'Ischio-jambiers'),

  // ── BRAS : BICEPS ────────────────────────────────────────────────────────
  // Machines
  Exercise(id: 'preacher_curl_machine', name: 'Pupitre à biceps (Preacher Curl machine)', category: ExerciseCategory.machine, muscleGroup: 'Biceps'),
  // Haltères
  Exercise(id: 'db_curl', name: 'Curl supination (alterné ou bilatéral)', category: ExerciseCategory.dumbbell, muscleGroup: 'Biceps'),
  Exercise(id: 'db_hammer_curl', name: 'Curl marteau', category: ExerciseCategory.dumbbell, muscleGroup: 'Biceps'),
  Exercise(id: 'db_concentration_curl', name: 'Curl concentré', category: ExerciseCategory.dumbbell, muscleGroup: 'Biceps'),
  Exercise(id: 'db_preacher_curl_uni', name: 'Curl pupitre unilatéral', category: ExerciseCategory.dumbbell, muscleGroup: 'Biceps', isUnilateral: true),
  // Poulie
  Exercise(id: 'cable_curl', name: 'Curl biceps poulie basse', category: ExerciseCategory.cable, muscleGroup: 'Biceps'),
  Exercise(id: 'cable_hammer_curl', name: 'Curl marteau poulie basse', category: ExerciseCategory.cable, muscleGroup: 'Biceps'),
  // Barre et Poids du corps
  Exercise(id: 'bb_curl', name: 'Curl barre droite', category: ExerciseCategory.barbell, muscleGroup: 'Biceps'),
  Exercise(id: 'ez_curl', name: 'Curl barre EZ', category: ExerciseCategory.barbell, muscleGroup: 'Biceps'),

  // ── BRAS : TRICEPS ───────────────────────────────────────────────────────
  // Machines
  Exercise(id: 'triceps_extension_machine', name: 'Extension triceps machine', category: ExerciseCategory.machine, muscleGroup: 'Triceps'),
  Exercise(id: 'dip_machine_assisted', name: 'Machine à dips assistée', category: ExerciseCategory.machine, muscleGroup: 'Triceps'),
  // Haltères
  Exercise(id: 'db_triceps_extension_uni', name: 'Extension triceps nuque unilatéral', category: ExerciseCategory.dumbbell, muscleGroup: 'Triceps', isUnilateral: true),
  Exercise(id: 'db_kickback_triceps', name: 'Kickback triceps', category: ExerciseCategory.dumbbell, muscleGroup: 'Triceps', isUnilateral: true),
  Exercise(id: 'db_skullcrusher', name: 'Barre au front avec haltères', category: ExerciseCategory.dumbbell, muscleGroup: 'Triceps'),
  // Poulie
  Exercise(id: 'cable_triceps_pushdown', name: 'Extension triceps poulie haute (corde, barre V ou droite)', category: ExerciseCategory.cable, muscleGroup: 'Triceps'),
  Exercise(id: 'cable_triceps_pushdown_reverse', name: 'Extension triceps poulie haute prise inversée', category: ExerciseCategory.cable, muscleGroup: 'Triceps'),
  Exercise(id: 'cable_triceps_overhead', name: 'Extension triceps poulie basse au-dessus de la tête', category: ExerciseCategory.cable, muscleGroup: 'Triceps'),
  // Barre et Poids du corps
  Exercise(id: 'bb_skullcrusher', name: 'Barre au front (Triceps)', category: ExerciseCategory.barbell, muscleGroup: 'Triceps'),
  Exercise(id: 'dips', name: 'Dips aux barres parallèles', category: ExerciseCategory.bodyweight, muscleGroup: 'Triceps'),

  // ── CEINTURE ABDOMINALE ──────────────────────────────────────────────────
  // Machines
  Exercise(id: 'crunch_machine', name: 'Crunch machine', category: ExerciseCategory.machine, muscleGroup: 'Abdominaux'),
  Exercise(id: 'torso_rotation_machine', name: 'Machine à rotation du buste', category: ExerciseCategory.machine, muscleGroup: 'Obliques'),
  // Poulie
  Exercise(id: 'cable_crunch', name: 'Crunch à la poulie haute (corde)', category: ExerciseCategory.cable, muscleGroup: 'Abdominaux'),
  Exercise(id: 'cable_woodchopper', name: 'Woodchopper (torsion à la poulie)', category: ExerciseCategory.cable, muscleGroup: 'Obliques', isUnilateral: true),
  // Poids du corps
  Exercise(id: 'crunch', name: 'Crunch classique au sol', category: ExerciseCategory.bodyweight, muscleGroup: 'Abdominaux'),
  Exercise(id: 'crunch_decline', name: 'Crunch sur banc décliné', category: ExerciseCategory.bodyweight, muscleGroup: 'Abdominaux'),
  Exercise(id: 'hanging_leg_raise', name: 'Relevé de jambes suspendu à la barre', category: ExerciseCategory.bodyweight, muscleGroup: 'Abdominaux'),
  Exercise(id: 'captain_chair_leg_raise', name: 'Relevé de jambes sur chaise romaine', category: ExerciseCategory.bodyweight, muscleGroup: 'Abdominaux'),
  Exercise(id: 'plank', name: 'Gainage frontal (Planche)', category: ExerciseCategory.bodyweight, muscleGroup: 'Sangle abdominale'),
  Exercise(id: 'side_plank', name: 'Gainage latéral', category: ExerciseCategory.bodyweight, muscleGroup: 'Obliques'),
  Exercise(id: 'ab_wheel', name: 'Roulette à abdos (Ab wheel)', category: ExerciseCategory.bodyweight, muscleGroup: 'Abdominaux'),
  Exercise(id: 'russian_twist', name: 'Russian Twist', category: ExerciseCategory.bodyweight, muscleGroup: 'Obliques'),

  // ── EXTRAS (poids du corps / jambes, pas dans la liste d'origine) ───────
  Exercise(id: 'pushup', name: 'Pompes', category: ExerciseCategory.bodyweight, muscleGroup: 'Pectoraux'),
  Exercise(id: 'squat_bw', name: 'Squats au poids du corps', category: ExerciseCategory.bodyweight, muscleGroup: 'Jambes'),
  Exercise(id: 'lunge', name: 'Fentes au poids du corps', category: ExerciseCategory.bodyweight, muscleGroup: 'Jambes'),

  // ── CARDIO ───────────────────────────────────────────────────────────────
  // Au même titre que les autres catégories : utilisables dans une séance en
  // direct (ex. un bloc vélo au milieu d'une séance muscu), avec
  // durée/distance chronométrées au lieu de séries/reps (voir
  // live_musculation_screen.dart, ExerciseCategoryX.isCardio).
  Exercise(id: 'rowing_erg', name: 'Rameur', category: ExerciseCategory.cardio, muscleGroup: 'Cardio'),
  Exercise(id: 'bike', name: 'Vélo', category: ExerciseCategory.cardio, muscleGroup: 'Cardio'),
  Exercise(id: 'jump_rope', name: 'Corde à sauter', category: ExerciseCategory.cardio, muscleGroup: 'Cardio'),
  Exercise(id: 'treadmill_run', name: 'Course', category: ExerciseCategory.cardio, muscleGroup: 'Cardio'),
  Exercise(id: 'stair_climber', name: 'Escalier', category: ExerciseCategory.cardio, muscleGroup: 'Cardio'),
];
