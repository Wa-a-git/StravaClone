import 'package:health/health.dart';

class HealthConnectService {
  final Health _health = Health();
  
  HealthConnectService() {
    _health.configure();
  }
  
  // Define the types of data we want to fetch
  final List<HealthDataType> _types = [
    HealthDataType.STEPS,
    HealthDataType.HEART_RATE,
    HealthDataType.SLEEP_SESSION,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.RESTING_HEART_RATE,
  ];

  // Request permissions for Health Connect
  Future<bool> requestPermissions() async {
    bool hasPermissions = await _health.hasPermissions(_types) ?? false;
    if (!hasPermissions) {
      try {
        hasPermissions = await _health.requestAuthorization(_types);
      } catch (e) {
        print("Exception in requestAuthorization: $e");
        hasPermissions = false;
      }
    }
    return hasPermissions;
  }

  // Get total steps for today
  Future<int> getDailySteps() async {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    
    try {
      int? steps = await _health.getTotalStepsInInterval(midnight, now);
      return steps ?? 0;
    } catch (e) {
      print("Error fetching steps: $e");
      return 0;
    }
  }

  // Get active calories burned today
  Future<double> getDailyActiveCalories() async {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    
    try {
      List<HealthDataPoint> healthData = await _health.getHealthDataFromTypes(
        types: [HealthDataType.ACTIVE_ENERGY_BURNED], 
        startTime: midnight, 
        endTime: now
      );
      
      double totalCalories = 0.0;
      for (var data in healthData) {
        if (data.value is NumericHealthValue) {
          totalCalories += (data.value as NumericHealthValue).numericValue.toDouble();
        }
      }
      return totalCalories;
    } catch (e) {
      print("Error fetching calories: $e");
      return 0.0;
    }
  }

  // Get average heart rate for today
  Future<double> getAverageHeartRate() async {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    
    try {
      List<HealthDataPoint> healthData = await _health.getHealthDataFromTypes(
        types: [HealthDataType.HEART_RATE], 
        startTime: midnight, 
        endTime: now
      );
      
      if (healthData.isEmpty) return 0.0;

      double total = 0.0;
      for (var data in healthData) {
        if (data.value is NumericHealthValue) {
          total += (data.value as NumericHealthValue).numericValue.toDouble();
        }
      }
      return total / healthData.length;
    } catch (e) {
      print("Error fetching heart rate: $e");
      return 0.0;
    }
  }
}
