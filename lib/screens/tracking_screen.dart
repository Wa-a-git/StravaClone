// lib/screens/tracking_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/tracking_provider.dart';
import '../providers/activity_provider.dart';
import '../providers/game_provider.dart';
import '../models/activity.dart';
import '../services/export_service.dart';
import '../services/game_service.dart';
import '../widgets/record_celebration.dart';
import '../widgets/system_window.dart';
import '../theme.dart';

enum _StopChoice { save, discard, keepGoing }

class TrackingScreen extends ConsumerStatefulWidget {
  /// Objectif de distance affiché pendant la course (ex. la routine "5 km
  /// quotidien"). Purement informatif — n'arrête pas le suivi, ne change rien
  /// à TrackingProvider/TrackingState.
  final double? targetKm;
  const TrackingScreen({super.key, this.targetKm});

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _nameController = TextEditingController();

  static const _defaultCenter = LatLng(15.0, 121.0);
  static const _defaultZoom = 15.5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final granted = await ref
          .read(trackingProvider.notifier)
          .requestPermissionAndInit();
      if (!granted && mounted) _showPermissionDeniedDialog();
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _moveCameraTo(LatLng point) {
    _mapController.move(point, _mapController.camera.zoom);
  }

  Future<void> _handleStart() async {
    final state = ref.read(trackingProvider);
    if (!state.locationPermissionGranted) {
      _showPermissionDeniedDialog();
      return;
    }
    HapticFeedback.mediumImpact();
    await ref.read(trackingProvider.notifier).start();
    _nameController.clear();
  }

  void _handleLap() {
    HapticFeedback.heavyImpact();
    ref.read(trackingProvider.notifier).recordLap();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Nouveau bloc démarré !', style: TextStyle(color: kNeonCyan, fontWeight: FontWeight.bold, shadows: [Shadow(color: kNeonCyan, blurRadius: 8)])),
        backgroundColor: const Color(0xFF141419),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: kNeonCyan, width: 1)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _handlePause() {
    HapticFeedback.lightImpact();
    ref.read(trackingProvider.notifier).pause();
  }

  void _handleResume() {
    HapticFeedback.mediumImpact();
    ref.read(trackingProvider.notifier).resume();
  }

  Future<void> _handleStop() async {
    final choice = await _showStopConfirmDialog();
    if (choice == _StopChoice.keepGoing) return;

    HapticFeedback.heavyImpact();

    // L'utilisateur a choisi de ne PAS enregistrer la course
    if (choice == _StopChoice.discard) {
      ref.read(trackingProvider.notifier).discard();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Course supprimée — rien n’a été enregistré',
              style: TextStyle(color: kNeonRed, fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF141419),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: kNeonRed, width: 1)),
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.pop(context);
      return;
    }

    final activity = await ref.read(trackingProvider.notifier).stop();
    if (!mounted) return;

    ref.read(activityListProvider.notifier).refresh();

    if (activity != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${activity.distanceKm} km saved in ${activity.durationFormatted}',
              style: const TextStyle(color: kNeonPink, fontWeight: FontWeight.bold, shadows: [Shadow(color: kNeonPink, blurRadius: 6)])),
          backgroundColor: const Color(0xFF141419),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: kNeonPink, width: 1)),
          duration: const Duration(seconds: 3),
        ),
      );

      // 🏆 Célébration si un record est battu
      await _maybeCelebrateRecords(activity);
      if (!mounted) return;

      // ⬆️ Notification "Système" si montée de niveau
      await _maybeLevelUp(activity);
      if (!mounted) return;

      final exportedPath =
          await ExportService.exportActivityToConfiguredDirectory(activity);

      if (exportedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export .md saved to: $exportedPath', style: const TextStyle(color: kNeonCyan)),
            backgroundColor: const Color(0xFF141419),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: kNeonCyan, width: 1)),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
    if (mounted) Navigator.pop(context);
  }

  /// Compare la course à l'historique et célèbre les records battus.
  Future<void> _maybeCelebrateRecords(Activity activity) async {
    // Trop courte (test / faux départ) → pas de célébration
    if (activity.distanceKmValue < 0.2) return;

    final all = ref.read(activityListProvider);
    final others = all.where((a) => a.key != activity.key).toList();

    final records = <String>[];

    if (others.isEmpty) {
      records.add('Première course enregistrée !');
    } else {
      // Plus longue distance
      final maxDistOther =
          others.map((a) => a.distanceKmValue).fold<double>(0, max);
      if (activity.distanceKmValue > maxDistOther) {
        records.add('Plus longue distance : ${activity.distanceKm} km');
      }

      // Meilleure allure (sec/km le plus bas), distance significative
      if (activity.distanceKmValue >= 0.5) {
        final myPace = activity.duration / activity.distanceKmValue;
        final bestOtherPace = others
            .where((a) => a.distanceKmValue >= 0.5)
            .map((a) => a.duration / a.distanceKmValue)
            .fold<double>(double.infinity, min);
        if (myPace < bestOtherPace) {
          records.add('Meilleure allure : ${activity.avgPace} /km');
        }
      }

      // Plus gros dénivelé positif
      if (activity.hasElevation && activity.elevationGainValue > 0) {
        final maxElevOther =
            others.map((a) => a.elevationGainValue).fold<double>(0, max);
        if (activity.elevationGainValue > maxElevOther) {
          records.add('Plus gros dénivelé : ${activity.elevationGain} m');
        }
      }
    }

    if (records.isNotEmpty && mounted) {
      HapticFeedback.heavyImpact();
      await showRecordCelebration(
        context,
        title: activity.title,
        records: records,
      );
    }
  }

  /// Compare le niveau avant/après la sauvegarde et notifie une montée de niveau.
  Future<void> _maybeLevelUp(Activity activity) async {
    final all = ref.read(activityListProvider);
    final others = all.where((a) => a.key != activity.key).toList();
    final bonus = ref.read(questBonusProvider);

    final before = GameService.profileFor(others, bonusXp: bonus);
    final after = GameService.profileFor(all, bonusXp: bonus);

    if (after.level <= before.level) return;

    final lines = <String>['Tu atteins le niveau ${after.level} !'];
    final tierUp = after.tier.minLevel != before.tier.minLevel;
    if (tierUp) {
      lines.add('Nouveau palier : ${after.tier.name}');
    }

    if (!mounted) return;
    HapticFeedback.heavyImpact();
    await showSystemWindow(
      context,
      heading: tierUp ? 'NOUVEAU PALIER' : 'LEVEL UP',
      lines: lines,
      accent: tierUp ? after.tier.color : kNeonCyan,
    );
  }

  Future<_StopChoice> _showStopConfirmDialog() async {
    _nameController.clear();
    return await showModalBottomSheet<_StopChoice>(
      context: context,
      backgroundColor: const Color(0xFF141419), // Fond sombre néon
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
        BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF333333),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: kNeonPink.withOpacity(0.15),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: kNeonPink.withOpacity(0.3), blurRadius: 15)
                  ],
                ),
                child: const Icon(Icons.stop_rounded,
                    color: kNeonPink, size: 30),
              ),
              const SizedBox(height: 16),
              const Text(
                'Stop Activity?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  shadows: [Shadow(color: kNeonPink, blurRadius: 8)],
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Enregistre ta course, ou supprime-la sans la garder.',
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFFAAAAAA),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Nom de la course...',
                  hintStyle: const TextStyle(color: Color(0xFF555555)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1E1E24),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    ref.read(trackingProvider.notifier).updateRunName(_nameController.text.trim());
                    Navigator.pop(ctx, _StopChoice.save);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kNeonPink,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    shadowColor: kNeonPink,
                    elevation: 10,
                  ),
                  child: const Text(
                    'Stop & Save',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, _StopChoice.discard),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: kNeonRed, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Supprimer (ne pas enregistrer)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: kNeonRed,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, _StopChoice.keepGoing),
                  child: const Text(
                    'Keep Going',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: kNeonCyan,
                      shadows: [Shadow(color: kNeonCyan, blurRadius: 6)],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ) ??
        _StopChoice.keepGoing;
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141419),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: kNeonPink, width: 1)),
        title: const Text(
          'Location Required',
          style: TextStyle(fontWeight: FontWeight.w700, color: kNeonPink, shadows: [Shadow(color: kNeonPink, blurRadius: 8)]),
        ),
        content: const Text(
            'Please enable location permission to use GPS tracking.',
            style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFFAAAAAA))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(backgroundColor: kNeonCyan, foregroundColor: Colors.black),
            child: const Text('Open Settings', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<TrackingState>(trackingProvider, (previous, next) {
      if (next.status == TrackingStatus.tracking && next.currentPosition != null) {
        bool positionChanged = previous?.currentPosition?.latitude != next.currentPosition!.latitude ||
                               previous?.currentPosition?.longitude != next.currentPosition!.longitude;
        // Centre la caméra si la position a réellement changé
        if (positionChanged) {
          _moveCameraTo(next.currentPosition!);
        }
      }
    });

    final trackState = ref.watch(trackingProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09090B),
        title: const Text('RECORD', style: TextStyle(
          fontFamily: kArcadeFont,
          fontSize: 18,
          color: kNeonPink,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
          shadows: [Shadow(color: kNeonPink, blurRadius: 12)]
        )),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: kNeonCyan),
          onPressed: () async {
            if (trackState.status != TrackingStatus.idle) {
              final choice = await _showStopConfirmDialog();
              if (choice == _StopChoice.keepGoing) return;
              if (choice == _StopChoice.discard) {
                ref.read(trackingProvider.notifier).discard();
              } else {
                await ref.read(trackingProvider.notifier).stop();
                ref.read(activityListProvider.notifier).refresh();
              }
            }
            if (mounted) Navigator.pop(context);
          },
        ),
      ),
      body: Column(
        children: [
          // ── Map area ────────────────────────────────────────────────────
          Expanded(
            flex: 6,
            child: Stack(
              children: [
                _buildMap(trackState),

                // Status badge
                Positioned(
                  top: 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _buildStatusBadge(trackState.status),
                  ),
                ),

                // Re-centre button
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: _MapButton(
                    icon: Icons.my_location_rounded,
                    onTap: () {
                      // Force la mise à jour GPS pour plus de précision
                      ref.read(trackingProvider.notifier).forceUpdateLocation();
                      HapticFeedback.lightImpact();

                      final pos =
                          trackState.currentPosition ?? _defaultCenter;
                      _moveCameraTo(pos);
                    },
                  ),
                ),
              ],
            ),
          ),

          // ── Controls panel ───────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF141419),
              border: const Border(top: BorderSide(color: kNeonPink, width: 2)),
              boxShadow: [
                BoxShadow(
                  color: kNeonPink.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Drag handle
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF333333),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Repère d'objectif (ex. routine "5 km quotidien") — purement
                // informatif, ne coupe jamais la course.
                if (widget.targetKm != null)
                  _TargetKmBanner(
                    targetKm: widget.targetKm!,
                    currentKm: trackState.totalDistance / 1000,
                  ),
                // Indicateur de boucle en cours
                if (trackState.laps.isNotEmpty && trackState.status != TrackingStatus.idle)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    color: kNeonCyan.withOpacity(0.1),
                    child: Text(
                      'BOUCLE ${trackState.laps.length + 1} EN COURS  •  Temps : ${trackState.formattedCurrentLapTime}  •  Dist : ${trackState.formattedCurrentLapDistance}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: kNeonCyan, fontWeight: FontWeight.w700, fontSize: 12, shadows: [Shadow(color: kNeonCyan, blurRadius: 5)]),
                    ),
                  ),
                // Stats row
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _StatDisplay(
                          label: 'TIME',
                          value: trackState.formattedTime,
                        ),
                      ),
                      Container(
                          width: 0.5,
                          height: 48,
                          color: const Color(0xFF333333)),
                      Expanded(
                        child: _StatDisplay(
                          label: 'DISTANCE',
                          value: trackState.formattedDistance,
                        ),
                      ),
                      Container(
                          width: 0.5,
                          height: 48,
                          color: const Color(0xFF333333)),
                      Expanded(
                        child: _StatDisplay(
                          label: 'PACE',
                          value: trackState.formattedPace,
                          unit: '/km',
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 0.5, color: Color(0xFF333333)),

                // Buttons
                Padding(
                  padding: EdgeInsets.only(
                    left: 32,
                    right: 32,
                    top: 20,
                    bottom:
                    24 + MediaQuery.of(context).padding.bottom,
                  ),
                  child: _buildControls(trackState.status),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(TrackingStatus status) {
    if (status == TrackingStatus.tracking) {
      return const _RecordingBadge();
    } else if (status == TrackingStatus.paused) {
      return _StatusPill(
        label: 'PAUSED',
        color: kNeonAmber, // Néon Jaune
        icon: Icons.pause_rounded,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildMap(TrackingState trackState) {
    final center = trackState.currentPosition ?? _defaultCenter;
    final routePoints = trackState.routePoints;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: _defaultZoom,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', // Carte Sombre (Dark Matter)
          userAgentPackageName: 'com.example.strava_clone',
          subdomains: const ['a', 'b', 'c', 'd'],
        ),
        if (routePoints.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: routePoints.toList(), // .toList() force la carte à se rafraîchir en direct !
                strokeWidth: 5.0,
                color: kNeonPink, // Trace Rose Néon
              ),
            ],
          ),
          MarkerLayer(
            markers: [
              if (routePoints.isNotEmpty)
              Marker(
                point: routePoints.first,
                width: 32,
                height: 32,
                child: Container(
                  decoration: BoxDecoration(
                    color: kNeonGreen, // Néon Vert Start
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 2),
                    boxShadow: [
                      BoxShadow(color: kNeonGreen.withOpacity(0.8), blurRadius: 10)
                    ],
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 16),
                ),
              ),
              if (trackState.status != TrackingStatus.idle &&
                  trackState.currentPosition != null)
                Marker(
                  point: trackState.currentPosition!,
                  width: 20,
                  height: 20,
                  child: Container(
                    decoration: BoxDecoration(
                      color: kNeonPink,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 2.5),
                      boxShadow: [
                        BoxShadow(color: kNeonPink.withOpacity(0.8), blurRadius: 12)
                      ],
                    ),
                  ),
                ),
            ],
          ),
        const RichAttributionWidget(
          attributions: [
            TextSourceAttribution('CartoDB Dark Matter'),
          ],
        ),
      ],
    );
  }

  Widget _buildControls(TrackingStatus status) {
    switch (status) {
      case TrackingStatus.idle:
        return Center(
          child: GestureDetector(
            onTap: _handleStart,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: kNeonPink, // Néon Rose
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: kNeonPink.withOpacity(0.6),
                    blurRadius: 25,
                    offset: const Offset(0, 0),
                  ),
                ],
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 44,
              ),
            ),
          ),
        );

      case TrackingStatus.tracking:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Bouton Lap (Bleu)
            GestureDetector(
              onTap: _handleLap,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: kNeonCyan, // Néon Cyan
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: kNeonCyan.withOpacity(0.5),
                      blurRadius: 15,
                      offset: const Offset(0, 0),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.flag_rounded,
                  color: Colors.black,
                  size: 30,
                ),
              ),
            ),
            const SizedBox(width: 32),
            // Bouton Pause (Blanc/Orange)
            GestureDetector(
              onTap: _handlePause,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFF141419),
                  shape: BoxShape.circle,
                  border: Border.all(color: kNeonAmber, width: 2), // Néon Jaune
                  boxShadow: [
                    BoxShadow(
                      color: kNeonAmber.withOpacity(0.3),
                      blurRadius: 10,
                    )
                  ]
                ),
                child: const Icon(
                  Icons.pause_rounded,
                  color: kNeonAmber,
                  size: 30,
                ),
              ),
            ),
          ],
        );

      case TrackingStatus.paused:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Resume button
            GestureDetector(
              onTap: _handleResume,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: kNeonGreen, // Néon Vert
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: kNeonGreen.withOpacity(0.5),
                      blurRadius: 15,
                      offset: const Offset(0, 0),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.black,
                  size: 30,
                ),
              ),
            ),
            const SizedBox(width: 32),
            // Stop button
            GestureDetector(
              onTap: _handleStop,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: kNeonRed, // Néon Rouge
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: kNeonRed.withOpacity(0.5),
                      blurRadius: 15,
                      offset: const Offset(0, 0),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.stop_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),
          ],
        );
    }
  }
}

// ── Map overlay button ────────────────────────────────────────────────────────

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MapButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF141419),
          shape: BoxShape.circle,
          border: Border.all(color: kNeonCyan, width: 1.5),
          boxShadow: [
            BoxShadow(color: kNeonCyan.withOpacity(0.4), blurRadius: 10)
          ],
        ),
        child: Icon(icon, color: kNeonCyan, size: 20),
      ),
    );
  }
}

// ── Status pill ───────────────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _StatusPill({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: color.withOpacity(0.6), blurRadius: 12)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.black, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Recording badge (animated) ───────────────────────────────────────────────

class _RecordingBadge extends StatefulWidget {
  const _RecordingBadge();

  @override
  State<_RecordingBadge> createState() => _RecordingBadgeState();
}

class _RecordingBadgeState extends State<_RecordingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _fade = Tween<double>(begin: 1.0, end: 0.4).animate(_controller);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: kNeonPink,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: kNeonPink.withOpacity(0.6), blurRadius: 12)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: _fade.value,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 7),
            const Text(
              'RECORDING',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

// ── Repère d'objectif de distance (ex. routine "5 km quotidien") ─────────────
class _TargetKmBanner extends StatelessWidget {
  final double targetKm;
  final double currentKm;
  const _TargetKmBanner({required this.targetKm, required this.currentKm});

  @override
  Widget build(BuildContext context) {
    final ratio = targetKm <= 0 ? 0.0 : (currentKm / targetKm).clamp(0.0, 1.0);
    final reached = currentKm >= targetKm;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'OBJECTIF ${targetKm.toStringAsFixed(0)} KM',
                style: const TextStyle(
                  color: kNeonPink,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                reached
                    ? 'Objectif atteint !'
                    : '${(targetKm - currentKm).toStringAsFixed(2)} km restants',
                style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(
              children: [
                Container(height: 5, color: const Color(0xFF2A2A30)),
                FractionallySizedBox(
                  widthFactor: ratio,
                  child: Container(
                      height: 5,
                      color: reached
                          ? kNeonGreen
                          : kNeonPink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stat display ──────────────────────────────────────────────────────────────

class _StatDisplay extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _StatDisplay({
    required this.label,
    required this.value,
    this.unit = '',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: kNeonCyan, // Labels en Cyan
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            shadows: [Shadow(color: kNeonCyan, blurRadius: 5)],
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    fontFamily: kArcadeFont,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    shadows: [Shadow(color: kNeonPink, blurRadius: 10)], // Valeurs blanches avec aura Rose
                    letterSpacing: 0,
                  ),
                ),
                if (unit.isNotEmpty)
                  TextSpan(
                    text: unit,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: kNeonCyan,
                      shadows: [Shadow(color: kNeonCyan, blurRadius: 5)],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}