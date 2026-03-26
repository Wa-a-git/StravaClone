// lib/services/tracking_service.dart
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'location_service.dart';
import 'hive_service.dart';
import '../models/activity.dart';
import 'package:flutter/material.dart';

enum TrackingState { idle, tracking, paused }

class TrackingService {
  // ── State ──────────────────────────────────────────────────────────────────
  TrackingState _state = TrackingState.idle;
  TrackingState get state => _state;

  // ── Timer ──────────────────────────────────────────────────────────────────
  Timer? _timer;
  int _elapsedSeconds = 0;
  int get elapsedSeconds => _elapsedSeconds;

  // ── Route data ─────────────────────────────────────────────────────────────
  final List<LatLng> _routePoints = [];
  List<LatLng> get routePoints => List.unmodifiable(_routePoints);

  double _totalDistance = 0.0; // meters
  double get totalDistance => _totalDistance;

  Position? _lastPosition;

  // ── GPS stream ─────────────────────────────────────────────────────────────
  StreamSubscription<Position>? _positionSubscription;

  // ── Callbacks (notify UI) ──────────────────────────────────────────────────
  VoidCallback? onTick;         // called every second
  VoidCallback? onLocationUpdate; // called when new GPS point arrives

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Start a brand-new activity
  Future<void> start() async {
    if (_state != TrackingState.idle) return;

    // Reset everything
    _routePoints.clear();
    _totalDistance = 0.0;
    _elapsedSeconds = 0;
    _lastPosition = null;

    _state = TrackingState.tracking;
    _startTimer();
    await _startGPS();
  }

  /// Pause tracking (keep timer and route intact)
  void pause() {
    if (_state != TrackingState.tracking) return;
    _state = TrackingState.paused;
    _timer?.cancel();
    _positionSubscription?.pause();
  }

  /// Resume after pause
  void resume() {
    if (_state != TrackingState.paused) return;
    _state = TrackingState.tracking;
    _startTimer();
    _positionSubscription?.resume();
  }

  /// Stop tracking, save activity to Hive, and reset
  Future<Activity?> stop() async {
    if (_state == TrackingState.idle) return null;

    _timer?.cancel();
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _state = TrackingState.idle;

    if (_routePoints.isEmpty) return null;

    // Build route list for Hive storage
    final route = _routePoints
        .map((p) => [p.latitude, p.longitude])
        .toList();

    final activity = Activity(
      date: DateTime.now(),
      distance: _totalDistance,
      duration: _elapsedSeconds,
      route: route,
    );

    await HiveService.saveActivity(activity);
    return activity;
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsedSeconds++;
      onTick?.call();
    });
  }

  Future<void> _startGPS() async {
    _positionSubscription = LocationService.getPositionStream().listen(
          (Position position) {
        if (_state != TrackingState.tracking) return;

        final newPoint = LatLng(position.latitude, position.longitude);

        // Calculate distance from last known position
        if (_lastPosition != null) {
          _totalDistance += LocationService.distanceBetween(
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            position.latitude,
            position.longitude,
          );
        }

        _routePoints.add(newPoint);
        _lastPosition = position;
        onLocationUpdate?.call();
      },
      onError: (error) {
        // GPS error — silently continue, UI will show last known data
      },
    );
  }

  // ── Utility ────────────────────────────────────────────────────────────────

  String get formattedTime {
    final h = _elapsedSeconds ~/ 3600;
    final m = (_elapsedSeconds % 3600) ~/ 60;
    final s = _elapsedSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get formattedDistance {
    if (_totalDistance < 1000) {
      return '${_totalDistance.toStringAsFixed(0)} m';
    }
    return '${(_totalDistance / 1000).toStringAsFixed(2)} km';
  }

  void dispose() {
    _timer?.cancel();
    _positionSubscription?.cancel();
  }
}