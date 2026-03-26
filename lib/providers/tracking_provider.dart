// lib/providers/tracking_provider.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../services/location_service.dart';
import '../services/hive_service.dart';
import '../models/activity.dart';

// ── Tracking state enum ──────────────────────────────────────────────────────

enum TrackingStatus { idle, tracking, paused }

// ── Immutable state class ────────────────────────────────────────────────────

class TrackingState {
  final TrackingStatus status;
  final int elapsedSeconds;
  final double totalDistance; // metres
  final List<LatLng> routePoints;
  final bool locationPermissionGranted;
  final LatLng? currentPosition;

  const TrackingState({
    this.status = TrackingStatus.idle,
    this.elapsedSeconds = 0,
    this.totalDistance = 0.0,
    this.routePoints = const [],
    this.locationPermissionGranted = false,
    this.currentPosition,
  });

  TrackingState copyWith({
    TrackingStatus? status,
    int? elapsedSeconds,
    double? totalDistance,
    List<LatLng>? routePoints,
    bool? locationPermissionGranted,
    LatLng? currentPosition,
  }) {
    return TrackingState(
      status: status ?? this.status,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      totalDistance: totalDistance ?? this.totalDistance,
      routePoints: routePoints ?? this.routePoints,
      locationPermissionGranted:
      locationPermissionGranted ?? this.locationPermissionGranted,
      currentPosition: currentPosition ?? this.currentPosition,
    );
  }

  // ── Derived getters ──────────────────────────────────────────────────────

  String get formattedTime {
    final h = elapsedSeconds ~/ 3600;
    final m = (elapsedSeconds % 3600) ~/ 60;
    final s = elapsedSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get formattedDistance {
    if (totalDistance < 1000) {
      return '${totalDistance.toStringAsFixed(0)} m';
    }
    return '${(totalDistance / 1000).toStringAsFixed(2)} km';
  }

  String get formattedPace {
    if (totalDistance <= 0 || elapsedSeconds <= 0) return '--:--';
    final paceSeconds = (elapsedSeconds / (totalDistance / 1000)).round();
    final m = paceSeconds ~/ 60;
    final s = paceSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

// ── Notifier ─────────────────────────────────────────────────────────────────

class TrackingNotifier extends StateNotifier<TrackingState> {
  TrackingNotifier() : super(const TrackingState());

  Timer? _timer;
  StreamSubscription<Position>? _positionSubscription;
  Position? _lastPosition;

  // ── Permission & initial location ─────────────────────────────────────────

  Future<bool> requestPermissionAndInit() async {
    final granted = await LocationService.requestPermission();
    if (!granted) {
      state = state.copyWith(locationPermissionGranted: false);
      return false;
    }
    state = state.copyWith(locationPermissionGranted: true);

    final pos = await LocationService.getCurrentPosition();
    if (pos != null) {
      state = state.copyWith(
        currentPosition: LatLng(pos.latitude, pos.longitude),
      );
    }
    return true;
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  Future<void> start() async {
    if (state.status != TrackingStatus.idle) return;

    state = state.copyWith(
      status: TrackingStatus.tracking,
      routePoints: [],
      totalDistance: 0.0,
      elapsedSeconds: 0,
    );
    _lastPosition = null;

    _startTimer();
    await _startGPS();
  }

  void pause() {
    if (state.status != TrackingStatus.tracking) return;
    state = state.copyWith(status: TrackingStatus.paused);
    _timer?.cancel();
    _positionSubscription?.pause();
  }

  void resume() {
    if (state.status != TrackingStatus.paused) return;
    state = state.copyWith(status: TrackingStatus.tracking);
    _startTimer();
    _positionSubscription?.resume();
  }

  Future<Activity?> stop() async {
    if (state.status == TrackingStatus.idle) return null;

    _timer?.cancel();
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    final savedPoints = state.routePoints;
    final savedDistance = state.totalDistance;
    final savedDuration = state.elapsedSeconds;

    state = state.copyWith(
      status: TrackingStatus.idle,
      routePoints: [],
      totalDistance: 0.0,
      elapsedSeconds: 0,
    );

    if (savedPoints.isEmpty) return null;

    final route = savedPoints.map((p) => [p.latitude, p.longitude]).toList();
    final activity = Activity(
      date: DateTime.now(),
      distance: savedDistance,
      duration: savedDuration,
      route: route,
    );

    await HiveService.saveActivity(activity);
    return activity;
  }

  // ── Private ──────────────────────────────────────────────────────────────

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.status == TrackingStatus.tracking) {
        state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
      }
    });
  }

  Future<void> _startGPS() async {
    _positionSubscription = LocationService.getPositionStream().listen(
          (Position position) {
        if (state.status != TrackingStatus.tracking) return;

        final newPoint = LatLng(position.latitude, position.longitude);
        double addedDistance = 0.0;

        if (_lastPosition != null) {
          addedDistance = LocationService.distanceBetween(
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            position.latitude,
            position.longitude,
          );
        }

        _lastPosition = position;

        state = state.copyWith(
          routePoints: [...state.routePoints, newPoint],
          totalDistance: state.totalDistance + addedDistance,
          currentPosition: newPoint,
        );
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final trackingProvider =
StateNotifierProvider<TrackingNotifier, TrackingState>(
      (ref) => TrackingNotifier(),
);