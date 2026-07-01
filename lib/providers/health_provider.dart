import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/health_connect_service.dart';

final healthConnectServiceProvider = Provider((ref) => HealthConnectService());

class HealthDataState {
  final int steps;
  final double calories;
  final double avgHeartRate;
  final bool isLoading;
  final bool hasPermission;

  HealthDataState({
    this.steps = 0,
    this.calories = 0.0,
    this.avgHeartRate = 0.0,
    this.isLoading = false,
    this.hasPermission = false,
  });

  HealthDataState copyWith({
    int? steps,
    double? calories,
    double? avgHeartRate,
    bool? isLoading,
    bool? hasPermission,
  }) {
    return HealthDataState(
      steps: steps ?? this.steps,
      calories: calories ?? this.calories,
      avgHeartRate: avgHeartRate ?? this.avgHeartRate,
      isLoading: isLoading ?? this.isLoading,
      hasPermission: hasPermission ?? this.hasPermission,
    );
  }
}

class HealthDataNotifier extends StateNotifier<HealthDataState> {
  final HealthConnectService _service;

  HealthDataNotifier(this._service) : super(HealthDataState());

  Future<void> fetchDailyData() async {
    state = state.copyWith(isLoading: true);
    
    final hasPermission = await _service.requestPermissions();
    if (!hasPermission) {
      state = state.copyWith(isLoading: false, hasPermission: false);
      return;
    }

    final steps = await _service.getDailySteps();
    final calories = await _service.getDailyActiveCalories();
    final heartRate = await _service.getAverageHeartRate();

    state = state.copyWith(
      steps: steps,
      calories: calories,
      avgHeartRate: heartRate,
      isLoading: false,
      hasPermission: true,
    );
  }
}

final healthDataProvider = StateNotifierProvider<HealthDataNotifier, HealthDataState>((ref) {
  final service = ref.watch(healthConnectServiceProvider);
  return HealthDataNotifier(service);
});
