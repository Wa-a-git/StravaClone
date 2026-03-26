// lib/screens/detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/activity.dart';

class DetailScreen extends StatefulWidget {
  final Activity activity;
  const DetailScreen({super.key, required this.activity});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  Activity get _activity => widget.activity;

  List<LatLng> get _routePoints =>
      _activity.route.map((pt) => LatLng(pt[0], pt[1])).toList();

  LatLng get _mapCenter {
    final points = _routePoints;
    if (points.isEmpty) return const LatLng(15.0, 121.0);
    final midIndex = points.length ~/ 2;
    return points[midIndex];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: CustomScrollView(
        slivers: [
          // ── App bar ──────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            leading: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFF2F2F7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 16,
                  color: Color(0xFF1C1C1E),
                ),
              ),
            ),
            title: Column(
              children: [
                const Text(
                  'Running',
                  style: TextStyle(
                    color: Color(0xFF1C1C1E),
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  _formatDateShort(_activity.date),
                  style: const TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),

          SliverToBoxAdapter(
            child: Column(
              children: [
                _buildMap(),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _buildStatsGrid(),
                      const SizedBox(height: 16),
                      if (_routePoints.isNotEmpty) _buildRouteCard(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final points = _routePoints;

    return Container(
      height: 300,
      child: points.isEmpty
          ? Container(
        color: const Color(0xFFE5E5EA),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map_outlined,
                  size: 40, color: Color(0xFF8E8E93)),
              SizedBox(height: 8),
              Text(
                'No route data',
                style: TextStyle(
                  color: Color(0xFF8E8E93),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      )
          : FlutterMap(
        options: MapOptions(
          initialCenter: _mapCenter,
          initialZoom: 15,
          initialCameraFit: points.length > 1
              ? CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.all(48),
          )
              : null,
        ),
        children: [
          TileLayer(
            urlTemplate:
            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.strava_clone',
            subdomains: const ['a', 'b', 'c'],
          ),
          if (points.length >= 2)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: points,
                  strokeWidth: 5.0,
                  color: const Color(0xFFFC4C02),
                ),
              ],
            ),
          MarkerLayer(
            markers: [
              Marker(
                point: points.first,
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
              if (points.length > 1)
                Marker(
                  point: points.last,
                  width: 32,
                  height: 32,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border:
                      Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black26, blurRadius: 4)
                      ],
                    ),
                    child: const Icon(Icons.flag_rounded,
                        color: Colors.white, size: 16),
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
      ),
    );
  }

  Widget _buildStatsGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _DetailStatCard(
                label: 'Distance',
                value: _activity.distanceKm,
                unit: 'km',
                iconColor: const Color(0xFFFC4C02),
                icon: Icons.route_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DetailStatCard(
                label: 'Duration',
                value: _activity.durationFormatted,
                unit: '',
                iconColor: const Color(0xFF0A84FF),
                icon: Icons.timer_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _DetailStatCard(
                label: 'Avg Pace',
                value: _activity.avgPace,
                unit: '/km',
                iconColor: const Color(0xFF30D158),
                icon: Icons.speed_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DetailStatCard(
                label: 'GPS Points',
                value: _activity.route.length.toString(),
                unit: 'pts',
                iconColor: const Color(0xFFBF5AF2),
                icon: Icons.location_on_rounded,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRouteCard() {
    final points = _routePoints;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Route',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1C1C1E),
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 14),
          _RoutePointRow(
            label: 'Start',
            lat: points.first.latitude,
            lng: points.first.longitude,
            color: const Color(0xFF30D158),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
            child: Container(
              width: 1.5,
              height: 18,
              color: const Color(0xFFE5E5EA),
            ),
          ),
          _RoutePointRow(
            label: 'Finish',
            lat: points.last.latitude,
            lng: points.last.longitude,
            color: Colors.red,
          ),
        ],
      ),
    );
  }

  String _formatDateShort(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = date.hour > 12
        ? date.hour - 12
        : (date.hour == 0 ? 12 : date.hour);
    final amPm = date.hour >= 12 ? 'PM' : 'AM';
    final minute = date.minute.toString().padLeft(2, '0');
    return '${months[date.month - 1]} ${date.day}, ${date.year} · $hour:$minute $amPm';
  }
}

// ── Detail stat card ──────────────────────────────────────────────────────────

class _DetailStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color iconColor;
  final IconData icon;

  const _DetailStatCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.iconColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8E8E93),
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: value,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1C1C1E),
                            letterSpacing: -0.5,
                          ),
                        ),
                        if (unit.isNotEmpty)
                          TextSpan(
                            text: ' $unit',
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
            ),
          ),
        ],
      ),
    );
  }
}

// ── Route point row ───────────────────────────────────────────────────────────

class _RoutePointRow extends StatelessWidget {
  final String label;
  final double lat;
  final double lng;
  final Color color;

  const _RoutePointRow({
    required this.label,
    required this.lat,
    required this.lng,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            label == 'Start'
                ? Icons.play_arrow_rounded
                : Icons.flag_rounded,
            color: color,
            size: 13,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            Text(
              '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF8E8E93),
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ],
    );
  }
}