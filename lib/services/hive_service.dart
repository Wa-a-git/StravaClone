// lib/services/hive_service.dart
import 'package:hive_flutter/hive_flutter.dart';
import '../models/activity.dart';

class HiveService {
  static const String _boxName = 'activities';
  static Box<Activity>? _box;

  /// Initialize Hive and open the activities box.
  /// Must be called before using any other method.
  static Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(ActivityAdapter());
    _box = await Hive.openBox<Activity>(_boxName);
    await Hive.openBox('settings'); // Boîte pour mémoriser le dossier d'export
    await Hive.openBox('game_results'); // Résultats des mini-jeux
  }

  /// Returns the open box (throws if not initialized).
  static Box<Activity> get box {
    if (_box == null || !_box!.isOpen) {
      throw StateError(
        'HiveService not initialized. Call HiveService.init() first.',
      );
    }
    return _box!;
  }

  /// Persist a new activity.
  static Future<void> saveActivity(Activity activity) async {
    await box.add(activity);
  }

  /// All activities sorted newest-first.
  static List<Activity> getAllActivities() {
    final list = box.values.toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  /// Delete a single activity by its Hive key.
  static Future<void> deleteActivity(dynamic key) async {
    await box.delete(key);
  }

  /// Wipe every activity.
  static Future<void> clearAll() async {
    await box.clear();
  }

  /// How many activities are stored.
  static int get activityCount => box.length;
}