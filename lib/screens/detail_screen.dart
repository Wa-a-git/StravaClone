// lib/screens/detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import '../models/activity.dart';
import '../services/efficiency_trend.dart';
import '../services/export_service.dart';
import '../services/health_connect_service.dart';
import '../services/health_score_service.dart' show TrendDir;
import '../services/hr_efficiency_store.dart';
import '../theme.dart';
import '../widgets/health_charts.dart';

class DetailScreen extends StatefulWidget {
  final Activity activity;
  const DetailScreen({super.key, required this.activity});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  Activity get _activity => widget.activity;

  // Données montre (FC + calories) lues depuis Health Connect pour la fenêtre
  // temporelle de la course. Chargées après le premier rendu.
  ActivityVitals? _vitals;
  bool _loadingVitals = true;

  @override
  void initState() {
    super.initState();
    _loadVitals();
  }

  Future<void> _loadVitals() async {
    setState(() => _loadingVitals = true);
    final start = _activity.date;
    final end = start.add(Duration(
        seconds: _activity.duration + _activity.pauseDurationSeconds));
    final vitals =
        await HealthConnectService().getActivityVitals(start, end);
    if (mounted) {
      setState(() {
        _vitals = vitals;
        _loadingVitals = false;
      });
    }
  }

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
      backgroundColor: const Color(0xFF09090B),
      body: CustomScrollView(
        slivers: [
          // ── App bar ──────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xFF09090B),
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF141419),
                  shape: BoxShape.circle,
                  border: Border.all(color: kNeonCyan, width: 1.2),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 16,
                  color: kNeonCyan,
                ),
              ),
            ),
            actions: [
              IconButton(
                onPressed: _exportMarkdown,
                icon: const Icon(Icons.download_rounded, color: kNeonCyan),
                tooltip: 'Exporter en Markdown',
              ),
            ],
            title: Column(
              children: [
                Text(
                  _activity.title,
                  style: const TextStyle(
                    fontFamily: kArcadeFont,
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    shadows: [Shadow(color: kNeonPink, blurRadius: 8)],
                  ),
                ),
                Text(
                  _formatDateShort(_activity.date),
                  style: const TextStyle(
                    color: Color(0xFFAAAAAA),
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
                      _buildWatchCard(),
                      if (_activity.speedSeries.length >= 2) ...[
                        const SizedBox(height: 16),
                        _buildSpeedCard(),
                      ],
                      if (_routePoints.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildRouteCard(),
                      ],
                      // Affichage conditionnel des boucles
                      if ((_activity.laps != null) && (_activity.laps!.isNotEmpty)) ...[
                        const SizedBox(height: 16),
                        _buildLapsList(),
                      ],
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

  Future<void> _exportMarkdown() async {
    String? dirPath = ExportService.getSavedExportDirectory();
    if (dirPath == null) {
      if (await Permission.manageExternalStorage.request().isGranted || await Permission.storage.request().isGranted) {
        final selectedDir = await FilePicker.getDirectoryPath(dialogTitle: 'Choisir le dossier lié à Drive');
        if (selectedDir != null) {
          await ExportService.saveExportDirectory(selectedDir);
          dirPath = selectedDir;
        }
      }
    }

    String? path;
    if (dirPath != null) {
      path = await ExportService.saveActivityAsMarkdown(_activity);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          path != null
              ? 'Export .md créé dans $path'
              : 'Impossible d’exporter le fichier Markdown.',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Widget _buildMap() {
    final points = _routePoints;

    return SizedBox(
      height: 300,
      child: points.isEmpty
          ? Container(
        color: const Color(0xFF141419),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map_outlined,
                  size: 40, color: Color(0xFF555555)),
              SizedBox(height: 8),
              Text(
                'Aucune trace GPS',
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
            'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
            userAgentPackageName: 'com.example.strava_clone',
            subdomains: const ['a', 'b', 'c', 'd'],
          ),
          if (points.length >= 2)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: points,
                  strokeWidth: 5.0,
                  color: kNeonPink,
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
                    color: kNeonGreen,
                    shape: BoxShape.circle,
                    border:
                    Border.all(color: Colors.black, width: 2),
                    boxShadow: [
                      BoxShadow(
                          color: kNeonGreen.withOpacity(0.8),
                          blurRadius: 10)
                    ],
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.black, size: 16),
                ),
              ),
              if (points.length > 1)
                Marker(
                  point: points.last,
                  width: 32,
                  height: 32,
                  child: Container(
                    decoration: BoxDecoration(
                      color: kNeonRed,
                      shape: BoxShape.circle,
                      border:
                      Border.all(color: Colors.black, width: 2),
                      boxShadow: [
                        BoxShadow(
                            color: kNeonRed.withOpacity(0.8),
                            blurRadius: 10)
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
              TextSourceAttribution('CartoDB Dark Matter'),
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
                iconColor: kNeonPink,
                icon: Icons.route_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DetailStatCard(
                label: 'Durée',
                value: _activity.durationFormatted,
                unit: '',
                iconColor: kNeonCyan,
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
                label: 'Allure moy.',
                value: _activity.avgPace,
                unit: '/km',
                iconColor: kNeonGreen,
                icon: Icons.speed_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DetailStatCard(
                label: 'Pause',
                value: _activity.pauseFormatted,
                unit: '',
                iconColor: kNeonAmber,
                icon: Icons.pause_rounded,
              ),
            ),
          ],
        ),
        if (_activity.hasElevation) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DetailStatCard(
                  label: 'Dénivelé +',
                  value: _activity.elevationGainValue.round().toString(),
                  unit: 'm',
                  iconColor: kNeonGreen,
                  icon: Icons.trending_up_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DetailStatCard(
                  label: 'Dénivelé -',
                  value: _activity.elevationLossValue.round().toString(),
                  unit: 'm',
                  iconColor: kNeonRed,
                  icon: Icons.trending_down_rounded,
                ),
              ),
            ],
          ),
        ],
        if (_activity.lapCount > 0) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DetailStatCard(
                  label: 'Boucles',
                  value: _activity.lapCount.toString(),
                  unit: '',
                  iconColor: const Color(0xFFFF9500),
                  icon: Icons.loop_rounded,
                ),
              ),
            ],
          ),
        ],
        if (_activity.inclinePercent != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DetailStatCard(
                  label: 'Inclinaison',
                  value: _activity.inclinePercent!.toStringAsFixed(1),
                  unit: '%',
                  iconColor: kNeonAmber,
                  icon: Icons.stairs_rounded,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildWatchCard() {
    final v = _vitals;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF141419),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kNeonCyan.withOpacity(0.4), width: 1.2),
        boxShadow: [BoxShadow(color: kNeonCyan.withOpacity(0.10), blurRadius: 12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.watch_rounded, color: kNeonCyan, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Données montre',
                style: TextStyle(
                  fontFamily: kArcadeFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: kNeonCyan,
                  letterSpacing: 0.5,
                  shadows: [Shadow(color: kNeonCyan, blurRadius: 6)],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_loadingVitals)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: kNeonCyan),
                ),
              ),
            )
          else if (v == null || !v.hasData) ...[
            const Text(
              'Aucune donnée de la montre sur ce créneau.\nSi tu as lancé la course depuis l\'app (pas depuis la montre), '
              'la Charge 6 doit d\'abord synchroniser vers Health Connect — '
              'ça peut prendre quelques minutes après la fin de la course.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadVitals,
              style: OutlinedButton.styleFrom(
                foregroundColor: kNeonCyan,
                side: BorderSide(color: kNeonCyan.withOpacity(0.5)),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Réessayer'),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: _WatchStat(
                    label: 'FC moy.',
                    value: v.hasHr ? v.avgHr.round().toString() : '--',
                    unit: 'bpm',
                    color: kNeonPink,
                  ),
                ),
                Expanded(
                  child: _WatchStat(
                    label: 'FC max',
                    value: v.hasHr ? v.maxHr.round().toString() : '--',
                    unit: 'bpm',
                    color: kNeonRed,
                  ),
                ),
                Expanded(
                  child: _WatchStat(
                    label: 'FC min',
                    value: v.hasHr ? v.minHr.round().toString() : '--',
                    unit: 'bpm',
                    color: kNeonCyan,
                  ),
                ),
                Expanded(
                  child: _WatchStat(
                    label: 'Cal. actives',
                    value: v.activeCalories > 0
                        ? v.activeCalories.round().toString()
                        : '--',
                    unit: 'kcal',
                    color: kNeonAmber,
                  ),
                ),
              ],
            ),
            if (v.hasHr && v.hrSamples.length >= 2) ...[
              const SizedBox(height: 18),
              const Text('Fréquence cardiaque pendant la course',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              const SizedBox(height: 8),
              TrendChart(
                values: v.hrSamples,
                dates: [for (final s in v.hrSeries) s.$1],
                color: kNeonPink,
                unit: ' bpm',
                height: 140,
                xLabelFormatter: (d) =>
                    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
              ),
              if (_buildEfficiencyComparisonLine(v) case final line?) ...[
                const SizedBox(height: 10),
                line,
              ],
            ],
          ],
        ],
      ),
    );
  }

  static const int _efficiencyHistoryWindow = 10;
  static const int _efficiencyMinHistory = 5;

  /// Compare la FC pour l'allure de cette course à la moyenne des courses
  /// précédentes (voir `EfficiencyTrend`) — `null` tant que l'historique est
  /// trop court pour qu'une comparaison soit défendable.
  Widget? _buildEfficiencyComparisonLine(ActivityVitals v) {
    if (_activity.avgSpeedKmhValue <= 0) return null;
    final currentRatio = v.avgHr / _activity.avgSpeedKmhValue;
    final currentMs = _activity.date.millisecondsSinceEpoch;
    final previous = HrEfficiencyStore.all()
        .where((p) => p.date.millisecondsSinceEpoch != currentMs)
        .toList();
    if (previous.length < _efficiencyMinHistory) return null;
    final window = previous.length > _efficiencyHistoryWindow
        ? previous.sublist(previous.length - _efficiencyHistoryWindow)
        : previous;
    final baseline = EfficiencyTrend.average(window.map((p) => p.ratio).toList());
    final trend = EfficiencyTrend.compare(currentRatio, baseline);
    if (trend.dir == TrendDir.flat) return null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrendArrow(dir: trend.dir, good: trend.good),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            trend.good
                ? 'FC pour cette allure plus basse que d\'habitude (${trend.label} bpm/km/h) — bon signe.'
                : 'FC pour cette allure plus haute que d\'habitude (${trend.label} bpm/km/h).',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 11.5, height: 1.3),
          ),
        ),
      ],
    );
  }

  Widget _buildLapsList() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF141419),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kNeonCyan, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Détail des boucles',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: kNeonCyan,
              letterSpacing: -0.4,
              shadows: [Shadow(color: kNeonCyan, blurRadius: 6)],
            ),
          ),
          const SizedBox(height: 14),
          ...List.generate(_activity.laps!.length, (index) {
            final lap = _activity.laps![index];
            final lapDistance = (lap['distance'] as num?)?.toDouble() ?? 0.0;
            final lapDuration = (lap['duration'] as num?)?.toInt() ?? 0;
            
            final m = lapDuration ~/ 60;
            final s = lapDuration % 60;
            final timeStr = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
            
            String paceStr = '--:--';
            if (lapDistance > 0 && lapDuration > 0) {
              final paceSeconds = (lapDuration / (lapDistance / 1000)).round();
              paceStr = '${(paceSeconds ~/ 60).toString().padLeft(2, '0')}:${(paceSeconds % 60).toString().padLeft(2, '0')} /km';
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Boucle ${index + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: kNeonPink,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$timeStr  •  ${(lapDistance / 1000).toStringAsFixed(2)} km',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
                      ),
                      Text(
                        'Allure : $paceStr',
                        style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 12),
                      )
                    ],
                  )
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Vitesse au fil de la course, dérivée du tracé GPS (voir
  /// `Activity.speedSeries`) — absente pour les activités enregistrées
  /// avant l'ajout de l'horodatage par point.
  Widget _buildSpeedCard() {
    final series = _activity.speedSeries;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF141419),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kNeonGreen.withOpacity(0.4), width: 1.2),
        boxShadow: [BoxShadow(color: kNeonGreen.withOpacity(0.10), blurRadius: 12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.speed_rounded, color: kNeonGreen, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Vitesse pendant la course',
                style: TextStyle(
                  fontFamily: kArcadeFont,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: kNeonGreen,
                  letterSpacing: 0.5,
                  shadows: [Shadow(color: kNeonGreen, blurRadius: 6)],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TrendChart(
            values: [for (final p in series) p.$2],
            dates: [
              for (final p in series) _activity.date.add(Duration(seconds: p.$1))
            ],
            color: kNeonGreen,
            unit: ' km/h',
            fractionDigits: 1,
            height: 140,
            xLabelFormatter: (d) {
              final elapsed = d.difference(_activity.date).inSeconds;
              final m = elapsed ~/ 60;
              final s = elapsed % 60;
              return '$m:${s.toString().padLeft(2, '0')}';
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRouteCard() {
    final points = _routePoints;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF141419),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kNeonCyan, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Parcours',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: kNeonCyan,
              letterSpacing: -0.4,
              shadows: [Shadow(color: kNeonCyan, blurRadius: 6)],
            ),
          ),
          const SizedBox(height: 14),
          _RoutePointRow(
            label: 'Start',
            lat: points.first.latitude,
            lng: points.first.longitude,
            color: kNeonGreen,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
            child: Container(
              width: 1.5,
              height: 18,
              color: const Color(0xFF333333),
            ),
          ),
          _RoutePointRow(
            label: 'Finish',
            lat: points.last.latitude,
            lng: points.last.longitude,
            color: kNeonRed,
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
        color: const Color(0xFF141419),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: iconColor.withOpacity(0.4), width: 1),
        boxShadow: [
          BoxShadow(color: iconColor.withOpacity(0.12), blurRadius: 10),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
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
                    color: Color(0xFFAAAAAA),
                    fontWeight: FontWeight.w500,
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
                            fontFamily: kArcadeFont,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0,
                          ),
                        ),
                        if (unit.isNotEmpty)
                          TextSpan(
                            text: ' $unit',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: iconColor,
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

// ── Watch stat (petite valeur santé de la course) ────────────────────────────

class _WatchStat extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _WatchStat({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          alignment: Alignment.centerLeft,
          fit: BoxFit.scaleDown,
          child: RichText(
            text: TextSpan(children: [
              TextSpan(
                text: value,
                style: TextStyle(
                  fontFamily: kArcadeFont,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              TextSpan(
                text: ' $unit',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
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