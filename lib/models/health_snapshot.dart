import 'package:flutter/material.dart';
import '../theme.dart';

/// Un stade de sommeil détecté par la montre.
enum SleepStage { deep, light, rem, awake }

extension SleepStageX on SleepStage {
  String get label => switch (this) {
        SleepStage.deep => 'Profond',
        SleepStage.light => 'Léger',
        SleepStage.rem => 'Paradoxal',
        SleepStage.awake => 'Éveil',
      };

  /// Couleurs alignées sur la légende historique du panneau sommeil.
  Color get color => switch (this) {
        SleepStage.deep => kNeonViolet,
        SleepStage.light => const Color(0xFF6E8BFF), // bleu doux (sommeil léger)
        SleepStage.rem => kNeonCyan,
        SleepStage.awake => AppColors.muted,
      };

  /// Rang vertical pour l'hypnogramme (0 = éveil en haut, 3 = profond en bas),
  /// comme les tracés de sommeil grand public.
  int get lane => switch (this) {
        SleepStage.awake => 0,
        SleepStage.rem => 1,
        SleepStage.light => 2,
        SleepStage.deep => 3,
      };
}

/// Un segment continu passé dans un stade donné (pour l'hypnogramme).
class SleepSegment {
  final SleepStage stage;
  final DateTime start;
  final DateTime end;

  const SleepSegment({
    required this.stage,
    required this.start,
    required this.end,
  });

  double get minutes => end.difference(start).inSeconds / 60.0;

  Map<String, dynamic> toMap() => {
        's': stage.index,
        'f': start.millisecondsSinceEpoch,
        't': end.millisecondsSinceEpoch,
      };

  factory SleepSegment.fromMap(Map<dynamic, dynamic> m) => SleepSegment(
        stage: SleepStage.values[(m['s'] as num?)?.toInt() ?? 0],
        start: DateTime.fromMillisecondsSinceEpoch((m['f'] as num?)?.toInt() ?? 0),
        end: DateTime.fromMillisecondsSinceEpoch((m['t'] as num?)?.toInt() ?? 0),
      );
}

class SleepBreakdown {
  final double deepMin;
  final double lightMin;
  final double remMin;
  final double awakeMin;
  final double asleepMin;

  /// Chronologie détaillée des stades (peut être vide si l'appareil ne la
  /// fournit pas). Sert à tracer l'hypnogramme.
  final List<SleepSegment> segments;

  const SleepBreakdown({
    this.deepMin = 0,
    this.lightMin = 0,
    this.remMin = 0,
    this.awakeMin = 0,
    this.asleepMin = 0,
    this.segments = const [],
  });

  double get totalInBedMin => deepMin + lightMin + remMin + awakeMin;
  double get totalAsleepMin => deepMin + lightMin + remMin;

  double get efficiency =>
      totalInBedMin <= 0 ? 0 : (totalAsleepMin / totalInBedMin) * 100;

  /// Heure de coucher (début du 1er segment) si disponible.
  DateTime? get bedtime =>
      segments.isEmpty ? null : segments.map((s) => s.start).reduce((a, b) => a.isBefore(b) ? a : b);

  /// Heure de lever (fin du dernier segment) si disponible.
  DateTime? get wakeTime =>
      segments.isEmpty ? null : segments.map((s) => s.end).reduce((a, b) => a.isAfter(b) ? a : b);
}

class HealthSnapshot {
  final int steps;
  final double activeCalories;
  final double totalCalories;
  final double avgHeartRate;
  final double restingHeartRate;
  final double restingHeartRateBaseline;
  final double spo2;
  final double respiratoryRate;
  final double hrv;
  final double hrvBaseline;
  final int flightsClimbed;
  final double distanceKm;
  final SleepBreakdown sleep;

  const HealthSnapshot({
    this.steps = 0,
    this.activeCalories = 0,
    this.totalCalories = 0,
    this.avgHeartRate = 0,
    this.restingHeartRate = 0,
    this.restingHeartRateBaseline = 0,
    this.spo2 = 0,
    this.respiratoryRate = 0,
    this.hrv = 0,
    this.hrvBaseline = 0,
    this.flightsClimbed = 0,
    this.distanceKm = 0,
    this.sleep = const SleepBreakdown(),
  });
}
