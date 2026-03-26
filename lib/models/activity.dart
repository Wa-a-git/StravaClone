// lib/models/activity.dart
import 'package:hive/hive.dart';

part 'activity.g.dart';

@HiveType(typeId: 0)
class Activity extends HiveObject {
  @HiveField(0)
  late DateTime date;

  @HiveField(1)
  late double distance; // in meters

  @HiveField(2)
  late int duration; // in seconds

  @HiveField(3)
  late List<List<double>> route; // [[lat, lng], ...]

  Activity({
    required this.date,
    required this.distance,
    required this.duration,
    required this.route,
  });

  /// Distance in kilometers (formatted string)
  String get distanceKm => (distance / 1000).toStringAsFixed(2);

  /// Duration formatted as HH:MM:SS or MM:SS
  String get durationFormatted {
    final h = duration ~/ 3600;
    final m = (duration % 3600) ~/ 60;
    final s = duration % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Average pace in min/km (MM:SS)
  String get avgPace {
    if (distance <= 0) return '--:--';
    final paceSeconds = (duration / (distance / 1000)).round();
    final m = paceSeconds ~/ 60;
    final s = paceSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}