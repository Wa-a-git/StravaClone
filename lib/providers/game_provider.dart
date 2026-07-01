// lib/providers/game_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/game_service.dart';
import 'activity_provider.dart';

/// XP bonus issu des quêtes réclamées (persisté dans Hive, exposé en réactif).
final questBonusProvider =
    StateProvider<int>((ref) => GameStore.questBonusXp);

/// Profil joueur dérivé en temps réel de l'historique + des quêtes réclamées.
final playerProfileProvider = Provider<PlayerProfile>((ref) {
  final activities = ref.watch(activityListProvider);
  final bonus = ref.watch(questBonusProvider);
  return GameService.profileFor(activities, bonusXp: bonus);
});
