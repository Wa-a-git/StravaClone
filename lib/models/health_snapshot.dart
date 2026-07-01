class SleepBreakdown {
  final double deepMin;
  final double lightMin;
  final double remMin;
  final double awakeMin;
  final double asleepMin;

  const SleepBreakdown({
    this.deepMin = 0,
    this.lightMin = 0,
    this.remMin = 0,
    this.awakeMin = 0,
    this.asleepMin = 0,
  });

  double get totalInBedMin => deepMin + lightMin + remMin + awakeMin;
  double get totalAsleepMin => deepMin + lightMin + remMin;

  double get efficiency =>
      totalInBedMin <= 0 ? 0 : (totalAsleepMin / totalInBedMin) * 100;
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
