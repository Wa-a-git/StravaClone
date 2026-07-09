// lib/providers/game_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/game_service.dart';
import '../services/musculation_store.dart';
import 'activity_provider.dart';

/// XP bonus issu des quêtes réclamées (persisté dans Hive, exposé en réactif).
final questBonusProvider =
    StateProvider<int>((ref) => GameStore.questBonusXp);

/// Compteur incrémenté à chaque ajout/suppression d'un exercice de
/// musculation — MusculationStore (Hive) n'a pas de flux réactif propre,
/// donc c'est ce compteur qui force `playerProfileProvider` à relire le
/// volume cumulé après une modification (voir musculation_screen.dart).
final musculationRevisionProvider = StateProvider<int>((ref) => 0);

/// Profil joueur dérivé en temps réel de l'historique + des quêtes réclamées.
/// La stat Force fusionne le dénivelé de course et le volume de musculation
/// (séries × reps × charge, tout l'historique) — pas de provider réactif
/// dédié pour la muscu (pas de flux Riverpod sur MusculationStore), donc
/// relu directement depuis Hive à chaque recalcul, comme le reste du profil.
final playerProfileProvider = Provider<PlayerProfile>((ref) {
  final activities = ref.watch(activityListProvider);
  final bonus = ref.watch(questBonusProvider);
  ref.watch(musculationRevisionProvider);
  final musculationVolumeKg =
      MusculationStore.all().fold<double>(0, (s, e) => s + e.volumeKg);
  return GameService.profileFor(activities,
      bonusXp: bonus, musculationVolumeKg: musculationVolumeKg);
});
