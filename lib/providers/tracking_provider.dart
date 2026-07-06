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
  final String runName;
  final int pauseDurationSeconds;
  final List<Map<String, dynamic>> laps; // Ajout de la mémoire des boucles
  final List<double> elevations; // altitude (m) parallèle à routePoints
  final List<int> pointSeconds; // secondes écoulées, parallèle à routePoints

  const TrackingState({
    this.status = TrackingStatus.idle,
    this.elapsedSeconds = 0,
    this.totalDistance = 0.0,
    this.routePoints = const [],
    this.locationPermissionGranted = false,
    this.currentPosition,
    this.runName = '',
    this.pauseDurationSeconds = 0,
    this.laps = const [],
    this.elevations = const [],
    this.pointSeconds = const [],
  });

  TrackingState copyWith({
    TrackingStatus? status,
    int? elapsedSeconds,
    double? totalDistance,
    List<LatLng>? routePoints,
    bool? locationPermissionGranted,
    LatLng? currentPosition,
    String? runName,
    int? pauseDurationSeconds,
    List<Map<String, dynamic>>? laps,
    List<double>? elevations,
    List<int>? pointSeconds,
  }) {
    return TrackingState(
      status: status ?? this.status,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      totalDistance: totalDistance ?? this.totalDistance,
      routePoints: routePoints ?? this.routePoints,
      locationPermissionGranted:
      locationPermissionGranted ?? this.locationPermissionGranted,
      currentPosition: currentPosition ?? this.currentPosition,
      runName: runName ?? this.runName,
      pauseDurationSeconds:
      pauseDurationSeconds ?? this.pauseDurationSeconds,
      laps: laps ?? this.laps,
      elevations: elevations ?? this.elevations,
      pointSeconds: pointSeconds ?? this.pointSeconds,
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

  int get currentLapDuration {
    int previousTime = laps.fold(0, (sum, lap) => sum + (lap['duration'] as int));
    return elapsedSeconds - previousTime;
  }

  double get currentLapDistance {
    double previousDist = laps.fold(0.0, (sum, lap) => sum + (lap['distance'] as double));
    return totalDistance - previousDist;
  }

  String get formattedCurrentLapTime {
    final duration = currentLapDuration;
    final m = duration ~/ 60;
    final s = duration % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get formattedCurrentLapDistance {
    final dist = currentLapDistance;
    if (dist < 1000) return '${dist.toStringAsFixed(0)} m';
    return '${(dist / 1000).toStringAsFixed(2)} km';
  }
}

// ── Notifier ─────────────────────────────────────────────────────────────────

class TrackingNotifier extends StateNotifier<TrackingState> {
  TrackingNotifier() : super(const TrackingState());

  Timer? _timer;
  StreamSubscription<Position>? _positionSubscription;
  Position? _lastPosition;
  DateTime? _pauseStartTime;
  DateTime? _lastMovementTime;

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

  void updateRunName(String name) {
    state = state.copyWith(runName: name);
  }

  // ── Controls ──────────────────────────────────────────────────────────────

  Future<void> start() async {
    if (state.status != TrackingStatus.idle) return;

    state = state.copyWith(
      status: TrackingStatus.tracking,
      routePoints: [],
      totalDistance: 0.0,
      elapsedSeconds: 0,
      laps: [], // Réinitialisation des boucles au démarrage
      pauseDurationSeconds: 0,
      elevations: [],
      pointSeconds: [],
    );
    _lastPosition = null;
    _pauseStartTime = null;
    _lastMovementTime = DateTime.now();

    _startTimer();
    await _startGPS();
  }

  void pause() {
    if (state.status != TrackingStatus.tracking) return;
    _pauseStartTime = DateTime.now();
    state = state.copyWith(status: TrackingStatus.paused);
    _timer?.cancel();
    _positionSubscription?.pause();
  }

  void resume() {
    if (state.status != TrackingStatus.paused) return;
    if (_pauseStartTime != null) {
      final pauseSeconds = DateTime.now()
          .difference(_pauseStartTime!)
          .inSeconds;
      state = state.copyWith(
        pauseDurationSeconds: state.pauseDurationSeconds + pauseSeconds,
      );
      _pauseStartTime = null;
    }
    _lastMovementTime = DateTime.now(); // Evite un faux auto-pause à la reprise
    state = state.copyWith(status: TrackingStatus.tracking);
    _startTimer();
    _positionSubscription?.resume();
  }

  // Ajout de la fonction pour enregistrer un bloc (Lap)
  void recordLap() {
    if (state.status != TrackingStatus.tracking) return;

    int previousLapsTime = 0;
    double previousLapsDistance = 0.0;

    for (var lap in state.laps) {
      previousLapsTime += lap['duration'] as int;
      previousLapsDistance += lap['distance'] as double;
    }

    final currentLapDuration = state.elapsedSeconds - previousLapsTime;
    final currentLapDistance = state.totalDistance - previousLapsDistance;

    final newLap = {
      'lapNumber': state.laps.length + 1,
      'duration': currentLapDuration,
      'distance': currentLapDistance,
      'totalTimeAtLap': state.elapsedSeconds,
    };

    state = state.copyWith(laps: [...state.laps, newLap]);
  }

  Future<Activity?> stop() async {
    if (state.status == TrackingStatus.idle) return null;

    if (state.status == TrackingStatus.paused && _pauseStartTime != null) {
      final pauseSeconds = DateTime.now().difference(_pauseStartTime!).inSeconds;
      state = state.copyWith(
        pauseDurationSeconds: state.pauseDurationSeconds + pauseSeconds,
      );
      _pauseStartTime = null;
    }

    _timer?.cancel();
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    final savedPoints = state.routePoints;
    final savedDistance = state.totalDistance;
    final savedDuration = state.elapsedSeconds;
    final savedRunName = state.runName.isNotEmpty ? state.runName : null;
    final savedPauseDuration = state.pauseDurationSeconds;
    final savedLapCount = state.laps.length;
      final savedLaps = List<Map<String, dynamic>>.from(state.laps);
    final savedElevations = List<double>.from(state.elevations);
    final savedPointSeconds = List<int>.from(state.pointSeconds);

    state = state.copyWith(
      status: TrackingStatus.idle,
      routePoints: [],
      totalDistance: 0.0,
      elapsedSeconds: 0,
      laps: [],
      pauseDurationSeconds: 0,
      runName: '',
      elevations: [],
      pointSeconds: [],
    );

    if (savedPoints.isEmpty) return null;

    final route = savedPoints.map((p) => [p.latitude, p.longitude]).toList();

    final activity = Activity(
      // Reconstitue l'heure de DÉBUT (pas l'instant présent, qui est la fin
      // de la course) — sinon toute requête Health Connect ancrée sur cette
      // date interroge la fenêtre d'APRÈS la course (récupération) au lieu
      // de la course elle-même (bug trouvé en vérifiant le graphe FC).
      date: DateTime.now()
          .subtract(Duration(seconds: savedDuration + savedPauseDuration)),
      distance: savedDistance,
      duration: savedDuration,
      route: route,
      name: savedRunName,
      pauseDurationSeconds: savedPauseDuration,
      lapCount: savedLapCount,
        laps: savedLaps, // <-- On passe maintenant les données des boucles au modèle !
      elevations: savedElevations.isNotEmpty ? savedElevations : null,
      pointSeconds: savedPointSeconds.isNotEmpty ? savedPointSeconds : null,
    );

    await HiveService.saveActivity(activity);
    return activity;
  }

  /// Arrête le suivi et réinitialise l'état SANS rien enregistrer.
  void discard() {
    _timer?.cancel();
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _lastPosition = null;
    _pauseStartTime = null;
    state = state.copyWith(
      status: TrackingStatus.idle,
      routePoints: [],
      totalDistance: 0.0,
      elapsedSeconds: 0,
      laps: [],
      pauseDurationSeconds: 0,
      runName: '',
      elevations: [],
      pointSeconds: [],
    );
  }

  // ── Private ──────────────────────────────────────────────────────────────

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.status == TrackingStatus.tracking) {
        bool isMoving = true;
        if (_lastMovementTime != null && DateTime.now().difference(_lastMovementTime!).inSeconds > 4) {
          isMoving = false; // Auto-pause : aucun déplacement détecté depuis 4 secondes
        }
        
        if (isMoving) {
          state = state.copyWith(elapsedSeconds: state.elapsedSeconds + 1);
        } else {
          state = state.copyWith(pauseDurationSeconds: state.pauseDurationSeconds + 1);
        }
      }
    });
  }

  Future<void> _startGPS() async {
    _positionSubscription = LocationService.getPositionStream().listen(
      (Position position) => _handleNewPosition(position, forced: false),
      onError: (_) {},
    );
  }

  // Force une mise à jour immédiate de la position (bouton de recentrage)
  Future<void> forceUpdateLocation() async {
    if (state.status != TrackingStatus.tracking) return;
    try {
      final pos = await LocationService.getCurrentPosition();
      if (pos != null) {
        _handleNewPosition(pos, forced: true);
      }
    } catch (_) {}
  }

  void _handleNewPosition(Position position, {bool forced = false}) {
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

      // Filtre anti-dérive allégé pour Android : on capte un maximum de points
      if (!forced) {
        // Tolérance augmentée à 25m et seuil très bas de 0.5m pour la haute précision
        if (position.accuracy > 25.0 || addedDistance < 0.5) {
          state = state.copyWith(currentPosition: newPoint);
          return;
        }
      }
    }

    _lastPosition = position;
    _lastMovementTime = DateTime.now();

    state = state.copyWith(
      routePoints: [...state.routePoints, newPoint],
      totalDistance: state.totalDistance + addedDistance,
      currentPosition: newPoint,
      elevations: [...state.elevations, position.altitude],
      pointSeconds: [...state.pointSeconds, state.elapsedSeconds],
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