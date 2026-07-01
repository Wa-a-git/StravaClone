// lib/providers/activity_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/activity.dart';
import '../services/hive_service.dart';

// ── State ────────────────────────────────────────────────────────────────────

class ActivityListNotifier extends StateNotifier<List<Activity>> {
  ActivityListNotifier() : super([]) {
    _load();
  }

  void _load() {
    state = HiveService.getAllActivities();
  }

  /// Reload from Hive (call after tracking saves a new activity).
  void refresh() => _load();

  Future<void> deleteActivity(Activity activity) async {
    await HiveService.deleteActivity(activity.key);
    _load();
  }

  /// Renomme une course (corrige une faute de frappe par ex.).
  Future<void> renameActivity(Activity activity, String newName) async {
    final trimmed = newName.trim();
    activity.name = trimmed.isEmpty ? null : trimmed;
    await activity.save(); // HiveObject.save() persiste la modification
    _load();
  }

  Future<void> clearAll() async {
    await HiveService.clearAll();
    _load();
  }

  int get count => state.length;
}

// ── Provider ──────────────────────────────────────────────────────────────────

final activityListProvider =
StateNotifierProvider<ActivityListNotifier, List<Activity>>(
      (ref) => ActivityListNotifier(),
);