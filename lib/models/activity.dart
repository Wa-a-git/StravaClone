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

  @HiveField(4)
  String? name;

  @HiveField(5)
  late int pauseDurationSeconds;

  @HiveField(6)
  late int lapCount;

  @HiveField(7)
  List<dynamic>? laps;

  @HiveField(8)
  List<double>? elevations; // altitude (m) parallèle aux points de route

  /// Type de séance : `null` = course libre (comportement historique),
  /// `'interval'` = fractionné, `'pace_zone'` = zone d'allure. Sert à choisir
  /// comment exploiter les données (ex. paires FC/allure par lap pour
  /// l'estimation VO2 max) et à afficher le bon libellé dans le vault.
  @HiveField(9)
  String? workoutType;

  Activity({
    required this.date,
    required this.distance,
    required this.duration,
    required this.route,
    this.name,
    this.pauseDurationSeconds = 0,
    this.lapCount = 0,
    this.laps,
    this.elevations,
    this.workoutType,
  });

  /// Distance in kilometers (formatted string)
  String get distanceKm => (distance / 1000).toStringAsFixed(2);

  /// Distance in kilometers as a number
  double get distanceKmValue => distance / 1000;

  /// Average speed in km/h
  double get avgSpeedKmhValue {
    if (duration <= 0) return 0.0;
    return distanceKmValue / (duration / 3600);
  }

  String get avgSpeedKmh => avgSpeedKmhValue > 0
      ? avgSpeedKmhValue.toStringAsFixed(1)
      : '--';

  String get title => name?.isNotEmpty == true ? name! : 'Running';

  /// True si la course possède des données d'altitude exploitables.
  bool get hasElevation => elevations != null && elevations!.length >= 2;

  /// Dénivelé positif total en mètres.
  /// Filtre anti-bruit GPS : on ignore les variations < 3 m (hystérésis).
  double get elevationGainValue {
    final e = elevations;
    if (e == null || e.length < 2) return 0.0;
    double gain = 0.0;
    double lastStable = e.first;
    for (final alt in e) {
      final diff = alt - lastStable;
      if (diff.abs() >= 3.0) {
        if (diff > 0) gain += diff;
        lastStable = alt;
      }
    }
    return gain;
  }

  /// Dénivelé négatif total en mètres (valeur positive).
  double get elevationLossValue {
    final e = elevations;
    if (e == null || e.length < 2) return 0.0;
    double loss = 0.0;
    double lastStable = e.first;
    for (final alt in e) {
      final diff = alt - lastStable;
      if (diff.abs() >= 3.0) {
        if (diff < 0) loss += -diff;
        lastStable = alt;
      }
    }
    return loss;
  }

  String get elevationGain => hasElevation ? '${elevationGainValue.round()}' : '--';

  String get pauseFormatted {
    final h = pauseDurationSeconds ~/ 3600;
    final m = (pauseDurationSeconds % 3600) ~/ 60;
    final s = pauseDurationSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

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