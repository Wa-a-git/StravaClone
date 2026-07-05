import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/daily_health_record.dart';
import '../models/health_snapshot.dart';
import '../services/export_service.dart';
import '../services/google_health_api_service.dart';
import '../services/health_connect_service.dart';
import '../services/health_score_service.dart';
import '../services/health_store.dart';
import '../services/health_game_service.dart';

final healthConnectServiceProvider = Provider((ref) => HealthConnectService());

class HealthDataState {
  final HealthSnapshot snapshot;
  final HealthScores? scores;
  final List<DailyHealthRecord> history;
  final List<HealthInsight> insights;
  final int stepsStreak;
  final int sleepStreak;
  final int healthXpToday;
  final bool isLoading;
  final bool hasPermission;

  HealthDataState({
    this.snapshot = const HealthSnapshot(),
    this.scores,
    this.history = const [],
    this.insights = const [],
    this.stepsStreak = 0,
    this.sleepStreak = 0,
    this.healthXpToday = 0,
    this.isLoading = false,
    this.hasPermission = false,
  });

  HealthDataState copyWith({
    HealthSnapshot? snapshot,
    HealthScores? scores,
    List<DailyHealthRecord>? history,
    List<HealthInsight>? insights,
    int? stepsStreak,
    int? sleepStreak,
    int? healthXpToday,
    bool? isLoading,
    bool? hasPermission,
  }) {
    return HealthDataState(
      snapshot: snapshot ?? this.snapshot,
      scores: scores ?? this.scores,
      history: history ?? this.history,
      insights: insights ?? this.insights,
      stepsStreak: stepsStreak ?? this.stepsStreak,
      sleepStreak: sleepStreak ?? this.sleepStreak,
      healthXpToday: healthXpToday ?? this.healthXpToday,
      isLoading: isLoading ?? this.isLoading,
      hasPermission: hasPermission ?? this.hasPermission,
    );
  }
}

class HealthDataNotifier extends StateNotifier<HealthDataState> {
  final HealthConnectService _service;

  HealthDataNotifier(this._service) : super(HealthDataState()) {
    // Si l'historique existe déjà (perms accordées lors d'une session
    // précédente), on charge silencieusement au démarrage.
    if (HealthStore.dayCount > 0) {
      fetchDailyData();
    }
  }

  Future<void> fetchDailyData() async {
    state = state.copyWith(isLoading: true);

    final hasPermission = await _service.requestPermissions();
    if (!hasPermission) {
      state = state.copyWith(isLoading: false, hasPermission: false);
      return;
    }

    // Remplit l'historique (première fois) + resynchronise aujourd'hui.
    await _service.backfillHistory(days: 30);

    // Après backfill, le jour courant est garanti stocké : on le lit.
    final now = DateTime.now();
    var record = HealthStore.recordFor(now);
    var snapshot = record?.toSnapshot() ?? await _service.getTodaySnapshot();

    // VO2 max : source séparée (Google Health API, cloud), best-effort — ne
    // bloque jamais le reste du dashboard si non connecté ou en erreur.
    final vo2Max = await _fetchVo2Max();
    if (vo2Max != null && vo2Max > 0) {
      snapshot = snapshot.copyWith(vo2Max: vo2Max);
      if (record != null) {
        record = record.copyWith(vo2Max: vo2Max);
        await HealthStore.upsertDay(record);
      }
    }

    final scores = record != null
        ? HealthScores(
            sleepScore: record.sleepScore,
            recoveryScore: record.recoveryScore,
            activityScore: record.activityScore,
            bioScore: record.bioScore,
            tier: HealthScoreService.tierFor(record.bioScore),
          )
        : HealthScoreService.computeAll(snapshot);

    // Récompense l'XP santé du jour (idempotent) dans le pool commun.
    final xp = await HealthGameService.awardDailyXp(now, scores, snapshot);

    // Export vault (mycelium) best-effort, fire-and-forget : n'attend pas le
    // réseau pour afficher le dashboard.
    if (record != null) {
      unawaited(ExportService.saveHealthDayAsMarkdown(record));
    }

    _recompute(snapshot, scores, xp);
  }

  /// VO2 max le plus récent via Google Health API, si connecté. Null si non
  /// connecté ou en erreur — jamais d'exception propagée (métrique premium
  /// optionnelle, ne doit jamais casser le reste du dashboard).
  Future<double?> _fetchVo2Max() async {
    try {
      final api = GoogleHealthApiService();
      if (!await api.isConnected()) return null;
      return await api.getLatestVo2Max();
    } catch (_) {
      return null;
    }
  }

  /// Recalcule uniquement les insights (après un feedback pouce haut/bas),
  /// sans refaire d'appel réseau.
  void refreshInsights() {
    if (state.scores == null) return;
    _recompute(state.snapshot, state.scores!, state.healthXpToday);
  }

  void _recompute(HealthSnapshot snapshot, HealthScores scores, int xpToday) {
    final history = HealthStore.lastNDays(30);
    final todayRec = HealthStore.recordFor(DateTime.now());

    final stepsStreak =
        HealthStore.streak((r) => r.steps >= HealthGameService.stepsGoal);
    final sleepStreak = HealthStore.streak(
        (r) => r.totalSleepMin >= HealthGameService.sleepGoalHours * 60);

    final insights = todayRec == null
        ? <HealthInsight>[]
        : HealthScoreService.insights(
            today: todayRec,
            rhrBaseline: HealthStore.baseline(HealthMetric.restingHeartRate),
            hrvBaseline: HealthStore.baseline(HealthMetric.hrv),
            sleepBaselineHours:
                HealthStore.baseline(HealthMetric.sleepHours),
            stepsStreak: stepsStreak,
            sleepStreak: sleepStreak,
          ).where((i) => !HealthFeedbackStore.isDismissed(i.id)).toList();

    state = state.copyWith(
      snapshot: snapshot,
      scores: scores,
      history: history,
      insights: insights,
      stepsStreak: stepsStreak,
      sleepStreak: sleepStreak,
      healthXpToday: xpToday,
      isLoading: false,
      hasPermission: true,
    );
  }
}

final healthDataProvider =
    StateNotifierProvider<HealthDataNotifier, HealthDataState>((ref) {
  final service = ref.watch(healthConnectServiceProvider);
  return HealthDataNotifier(service);
});
