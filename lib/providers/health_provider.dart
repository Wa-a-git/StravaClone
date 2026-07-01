import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/health_snapshot.dart';
import '../services/health_connect_service.dart';
import '../services/health_score_service.dart';

final healthConnectServiceProvider = Provider((ref) => HealthConnectService());

class HealthDataState {
  final HealthSnapshot snapshot;
  final HealthScores? scores;
  final bool isLoading;
  final bool hasPermission;

  HealthDataState({
    this.snapshot = const HealthSnapshot(),
    this.scores,
    this.isLoading = false,
    this.hasPermission = false,
  });

  HealthDataState copyWith({
    HealthSnapshot? snapshot,
    HealthScores? scores,
    bool? isLoading,
    bool? hasPermission,
  }) {
    return HealthDataState(
      snapshot: snapshot ?? this.snapshot,
      scores: scores ?? this.scores,
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

    final snapshot = await _service.getTodaySnapshot();
    final scores = HealthScoreService.computeAll(snapshot);

    state = state.copyWith(
      snapshot: snapshot,
      scores: scores,
      isLoading: false,
      hasPermission: true,
    );
  }
}

final healthDataProvider = StateNotifierProvider<HealthDataNotifier, HealthDataState>((ref) {
  final service = ref.watch(healthConnectServiceProvider);
  return HealthDataNotifier(service);
});
