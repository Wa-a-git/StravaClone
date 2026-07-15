// lib/models/activity.dart
import 'dart:math';
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

  /// Secondes écoulées depuis le début de l'activité, parallèle à `route` —
  /// permet de reconstruire une vitesse instantanée après coup (`route` seul
  /// ne dit pas QUAND chaque point a été capté). Absent sur les activités
  /// enregistrées avant l'ajout de ce champ.
  @HiveField(10)
  List<int>? pointSeconds;

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
    this.pointSeconds,
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

  /// Libellé du type de séance affiché dans les listes/cartes — même
  /// mapping que `ExportService._sportLabel` pour rester cohérent avec les
  /// fiches vault.
  String get sportLabel => switch (workoutType) {
        'interval' => 'Fractionné',
        'pace_zone' => 'Zone d\'allure',
        'treadmill' => 'Tapis',
        'run_manual' => 'Course (manuel)',
        'other_cardio' => 'Cardio',
        _ => 'Running',
      };

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

  /// Vitesse (km/h) au fil de la course, dérivée de `route` + `pointSeconds`
  /// (distance/temps entre points consécutifs), lissée par une moyenne
  /// glissante pour absorber le bruit GPS. Liste vide si `pointSeconds` est
  /// absent (activité enregistrée avant l'ajout de ce champ, ou avec moins
  /// de 2 points).
  List<(int second, double speedKmh)> get speedSeries {
    final ps = pointSeconds;
    if (ps == null || ps.length < 2 || route.length != ps.length) {
      return const [];
    }

    final raw = <(int, double)>[];
    for (int i = 1; i < route.length; i++) {
      final dt = ps[i] - ps[i - 1];
      if (dt <= 0) continue;
      final meters = _haversineMeters(
          route[i - 1][0], route[i - 1][1], route[i][0], route[i][1]);
      final kmh = (meters / dt) * 3.6;
      if (kmh > 40) continue; // saut GPS aberrant (signal perdu puis retrouvé)
      raw.add((ps[i], kmh));
    }
    if (raw.isEmpty) return const [];

    // Moyenne glissante (fenêtre de 5) pour lisser le bruit point à point —
    // sans ça, le graphe serait une succession de pics illisibles.
    const window = 5;
    final smoothed = <(int, double)>[];
    for (int i = 0; i < raw.length; i++) {
      final lo = (i - window ~/ 2).clamp(0, raw.length - 1);
      final hi = (i + window ~/ 2).clamp(0, raw.length - 1);
      final slice = raw.sublist(lo, hi + 1);
      final avg = slice.map((e) => e.$2).reduce((a, b) => a + b) / slice.length;
      smoothed.add((raw[i].$1, avg));
    }
    return smoothed;
  }

  static double _haversineMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0; // rayon terrestre, mètres
    double deg2rad(double d) => d * (pi / 180);
    final dLat = deg2rad(lat2 - lat1);
    final dLng = deg2rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(deg2rad(lat1)) * cos(deg2rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }
}