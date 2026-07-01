// lib/services/game_result_store.dart
// Stockage simple des résultats de mini-jeux (boîte Hive non typée).
import 'package:hive_flutter/hive_flutter.dart';

class GameResultStore {
  static Box get _box => Hive.box('game_results');

  /// Enregistre un résultat. [data] doit contenir au minimum :
  /// 'type' (String), 'date' (int ms). + les stats du jeu.
  static Future<void> add(Map<String, dynamic> data) async {
    await _box.add(data);
  }

  /// Tous les résultats, du plus récent au plus ancien.
  static List<Map<String, dynamic>> all() {
    final list = _box.values
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    list.sort((a, b) => (b['date'] as int).compareTo(a['date'] as int));
    return list;
  }

  static Future<void> clear() async => _box.clear();
}
