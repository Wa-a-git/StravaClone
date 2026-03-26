// lib/screens/tracking_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/tracking_provider.dart';
import '../providers/activity_provider.dart';

class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key});

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  final MapController _mapController = MapController();

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
    final confirmed = await _showStopConfirmDialog();
    if (!confirmed) return;

    HapticFeedback.heavyImpact();
    final activity = await ref.read(trackingProvider.notifier).stop();
    if (!mounted) return;

    ref.read(activityListProvider.notifier).refresh();

    if (activity != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${activity.distanceKm} km saved in ${activity.durationFormatted}'),
          backgroundColor: const Color(0xFF30D158),
          behavior: SnackBarBehavior.floating,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
    Navigator.pop(context);
  }

  Future<bool> _showStopConfirmDialog() async {
    return await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius:
        BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E5EA),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.stop_rounded,
                  color: Colors.red, size: 30),
            ),
            const SizedBox(height: 16),
            const Text(
              'Stop Activity?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1C1C1E),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your run will be saved to your history.',
              style: TextStyle(
                fontSize: 15,
                color: Color(0xFF8E8E93),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Stop & Save',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Keep Going',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8E8E93),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ) ??
        false;
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Location Required',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
            'Please enable location permission to use GPS tracking.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<TrackingState>(trackingProvider, (previous, next) {
      if (next.status == TrackingStatus.tracking &&
          next.currentPosition != null &&
          next.routePoints.length >
              (previous?.routePoints.length ?? 0)) {
        _moveCameraTo(next.currentPosition!);
      }
    });

    final trackState = ref.watch(trackingProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Record'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () async {
            if (trackState.status != TrackingStatus.idle) {
              final leave = await _showStopConfirmDialog();
              if (!leave) return;
              await ref.read(trackingProvider.notifier).stop();
              ref.read(activityListProvider.notifier).refresh();
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
            color: Colors.white,
            child: Column(
              children: [
                // Drag handle
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E5EA),
                    borderRadius: BorderRadius.circular(2),
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
                          color: const Color(0xFFE5E5EA)),
                      Expanded(
                        child: _StatDisplay(
                          label: 'DISTANCE',
                          value: trackState.formattedDistance,
                        ),
                      ),
                      Container(
                          width: 0.5,
                          height: 48,
                          color: const Color(0xFFE5E5EA)),
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

                const Divider(height: 0.5),

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
        color: const Color(0xFFFF9500),
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
          urlTemplate:
          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.strava_clone',
          subdomains: const ['a', 'b', 'c'],
        ),
        if (routePoints.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: routePoints,
                strokeWidth: 5.0,
                color: const Color(0xFFFC4C02),
              ),
            ],
          ),
        if (routePoints.isNotEmpty)
          MarkerLayer(
            markers: [
              Marker(
                point: routePoints.first,
                width: 32,
                height: 32,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF30D158),
                    shape: BoxShape.circle,
                    border:
                    Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black26, blurRadius: 4)
                    ],
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 16),
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
                      color: const Color(0xFFFC4C02),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white, width: 2.5),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black26, blurRadius: 6)
                      ],
                    ),
                  ),
                ),
            ],
          ),
        const RichAttributionWidget(
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }

  Widget _buildControls(TrackingStatus status) {
    switch (status) {
      case TrackingStatus.idle:
      // Big circular START button
        return Center(
          child: GestureDetector(
            onTap: _handleStart,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFFC4C02),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFC4C02).withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
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
            // Pause button — outlined circle
            GestureDetector(
              onTap: _handlePause,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: const Color(0xFFFF9500), width: 2),
                ),
                child: const Icon(
                  Icons.pause_rounded,
                  color: Color(0xFFFF9500),
                  size: 30,
                ),
              ),
            ),
            const SizedBox(width: 32),
            // Stop button — filled red circle
            GestureDetector(
              onTap: _handleStop,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
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
                  color: const Color(0xFF30D158),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color:
                      const Color(0xFF30D158).withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
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
                  color: Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
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

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
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
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
                color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))
          ],
        ),
        child: Icon(icon, color: const Color(0xFFFC4C02), size: 20),
      ),
    );
  }
}

// ── Status pill ───────────────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _StatusPill(
      {required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6)
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Recording badge (animated) ────────────────────────────────────────────────

class _RecordingBadge extends StatefulWidget {
  const _RecordingBadge();

  @override
  State<_RecordingBadge> createState() => _RecordingBadgeState();
}

class _RecordingBadgeState extends State<_RecordingBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fade;

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
        padding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFFC4C02),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 6)
          ],
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
                color: Colors.white,
                fontWeight: FontWeight.w700,
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
            color: Color(0xFF8E8E93),
            fontWeight: FontWeight.w500,
            letterSpacing: 0.8,
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
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1C1C1E),
                    letterSpacing: -1,
                  ),
                ),
                if (unit.isNotEmpty)
                  TextSpan(
                    text: unit,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF8E8E93),
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