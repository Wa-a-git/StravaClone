// lib/widgets/mascot_sprites.dart
// Source unique des sprites du personnage (Qiyana) : humeurs disponibles,
// dossier/préfixe/nombre de frames par humeur, et logique de choix d'humeur
// à partir des données santé — utilisée par le HUD du Feed et par la
// galerie dédiée (onglet Mascotte) pour rester cohérentes entre elles.
import '../services/health_score_service.dart';

enum MascotMood { running, meditating, tired, celebrating, proud, happyTired, neutral }

/// Dossier + préfixe de fichier + nombre de frames par humeur. "tired" ne
/// boucle que sur les 3 premières frames (bâillement) — les frames 5-8
/// (elle s'endort) servent d'illustration statique dans l'écran Sommeil.
const Map<MascotMood, (String, String, int)> kMascotSprites = {
  MascotMood.running: ('character', 'run', 6),
  MascotMood.meditating: ('character/meditation', 'med', 6),
  MascotMood.tired: ('character/tired', 'tired', 3),
  MascotMood.celebrating: ('character/celebrate', 'cele', 8),
  MascotMood.proud: ('character/proud', 'proud', 8),
  MascotMood.happyTired: ('character/happy_tired', 'ht', 8),
  MascotMood.neutral: ('character/neutral', 'neutral', 8),
};

String mascotSpriteAsset(MascotMood mood, int frame) {
  final (dir, prefix, _) = kMascotSprites[mood]!;
  return 'assets/$dir/${prefix}_$frame.png';
}

/// Priorité, du plus ponctuel/rare au plus permanent : célébration (course
/// ET musculation faites aujourd'hui) > fierté (série de jours consécutifs)
/// > contente-fatiguée (au moins un entraînement fait aujourd'hui) > fatigue
/// (alerte sommeil, à ne pas masquer) > méditation (récupération élevée) >
/// course par défaut.
MascotMood pickMascotMood({
  required HealthScores? scores,
  required bool todayMusculationDone,
  required int runStreak,
  required double todayRunKm,
}) {
  if (todayRunKm > 0 && todayMusculationDone) return MascotMood.celebrating;
  if (runStreak >= 3) return MascotMood.proud;
  if (todayRunKm > 0 || todayMusculationDone) return MascotMood.happyTired;
  if (scores != null && scores.sleepScore > 0 && scores.sleepScore < 50) {
    return MascotMood.tired;
  }
  if (scores != null && scores.recoveryScore >= 80) return MascotMood.meditating;
  return MascotMood.running;
}
