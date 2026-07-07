// lib/screens/pace_zone_game_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/activity.dart';
import '../providers/activity_provider.dart';
import '../providers/game_provider.dart';
import '../services/audio_coach.dart';
import '../services/export_service.dart';
import '../services/game_result_store.dart';
import '../services/game_service.dart';
import '../services/hive_service.dart';
import '../services/live_pace.dart';
import '../services/location_service.dart';
import '../services/vo2_estimator_service.dart';
import '../widgets/system_window.dart';
import '../theme.dart';

enum _ZoneStatus { idle, tooSlow, inZone, tooFast }

class PaceZoneGameScreen extends ConsumerStatefulWidget {
  const PaceZoneGameScreen({super.key});

  @override
  ConsumerState<PaceZoneGameScreen> createState() => _PaceZoneGameScreenState();
}

class _PaceZoneGameScreenState extends ConsumerState<PaceZoneGameScreen> {
  // Réglages
  int _targetSec = 360; // 6:00 /km
  int _tolerance = 15; // ± secondes

  // Runtime
  bool _running = false;
  final LivePace _pace = LivePace();
  final AudioCoach _coach = AudioCoach();
  StreamSubscription<Position>? _sub;
  Timer? _timer;

  int _elapsed = 0;
  int _inZoneSeconds = 0;
  _ZoneStatus _status = _ZoneStatus.idle;

  // Trace GPS, pour exporter une vraie Activity en fin de séance (voir _stop)
  // — condition nécessaire pour que la séance alimente l'estimation VO2 max.
  final List<List<double>> _route = [];
  final List<int> _pointSeconds = [];

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    _coach.stop();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _start() async {
    final granted = await LocationService.requestPermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Permission GPS requise pour ce jeu')));
      }
      return;
    }
    await _coach.init();
    WakelockPlus.enable();
    setState(() {
      _running = true;
      _elapsed = 0;
      _inZoneSeconds = 0;
      _status = _ZoneStatus.idle;
    });
    _route.clear();
    _pointSeconds.clear();
    HapticFeedback.mediumImpact();
    _coach.say('C\'est parti. Allure cible ${formatPace(_targetSec)}.');

    _sub = LocationService.getPositionStream().listen((p) {
      _pace.addPosition(p);
      _route.add([p.latitude, p.longitude]);
      _pointSeconds.add(_elapsed);
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    _elapsed++;
    final paceSec = _pace.paceSecPerKm;
    _ZoneStatus s;
    if (paceSec == null) {
      s = _ZoneStatus.idle;
    } else if (paceSec > _targetSec + _tolerance) {
      s = _ZoneStatus.tooSlow;
    } else if (paceSec < _targetSec - _tolerance) {
      s = _ZoneStatus.tooFast;
    } else {
      s = _ZoneStatus.inZone;
    }
    if (s == _ZoneStatus.inZone) _inZoneSeconds++;

    // Annonce vocale au changement d'état (avec cooldown)
    if (s != _status && s != _ZoneStatus.idle) {
      switch (s) {
        case _ZoneStatus.tooSlow:
          _coach.say('Accélère', cooldown: const Duration(seconds: 6));
          break;
        case _ZoneStatus.tooFast:
          _coach.say('Ralentis', cooldown: const Duration(seconds: 6));
          break;
        case _ZoneStatus.inZone:
          _coach.say('Allure parfaite', cooldown: const Duration(seconds: 8));
          break;
        case _ZoneStatus.idle:
          break;
      }
    }
    setState(() => _status = s);
  }

  Future<void> _stop() async {
    _timer?.cancel();
    await _sub?.cancel();
    WakelockPlus.disable();
    _running = false;

    final distance = _pace.totalDistance;
    final duration = _elapsed;
    final pct = duration > 0 ? (_inZoneSeconds / duration * 100).round() : 0;
    final avgPaceSec =
        distance > 50 ? (duration / (distance / 1000)).round() : 0;
    final xp = 20 + (_inZoneSeconds / 60 * 12).round();

    await _coach.say('Terminé. ${pct} pour cent dans la zone.');
    await GameResultStore.add({
      'type': 'pace',
      'date': DateTime.now().millisecondsSinceEpoch,
      'targetSec': _targetSec,
      'tolerance': _tolerance,
      'distance': distance,
      'duration': duration,
      'pctInZone': pct,
      'avgPaceSec': avgPaceSec,
      'xp': xp,
    });
    await GameStore.addBonusXp(xp);
    ref.read(questBonusProvider.notifier).state = GameStore.questBonusXp;

    // Enregistre une vraie Activity (GPS) si la séance a produit quelque
    // chose d'exploitable — même logique que le fractionné : ça permet à
    // cette séance de compter pour l'estimation VO2 max et d'apparaître dans
    // le suivi Sport comme une vraie sortie.
    if (distance > 0) {
      final activity = Activity(
        date: DateTime.now().subtract(Duration(seconds: duration)),
        distance: distance,
        duration: duration,
        route: _route,
        name: 'Zone d\'allure ${formatPace(_targetSec)}/km',
        workoutType: 'pace_zone',
        pointSeconds: _pointSeconds,
      );
      await HiveService.saveActivity(activity);
      ref.read(activityListProvider.notifier).refresh();
      unawaited(Vo2EstimatorService.recomputeAndStore(
          ref.read(activityListProvider)));
      unawaited(ExportService.exportActivityToConfiguredDirectory(activity));
    }

    if (!mounted) return;
    await showSystemWindow(
      context,
      heading: 'ZONE TERMINÉE',
      lines: [
        '$pct % du temps dans la zone',
        'Distance : ${(distance / 1000).toStringAsFixed(2)} km',
        'Allure moy. : ${formatPace(avgPaceSec == 0 ? null : avgPaceSec)} /km',
        '+$xp XP',
      ],
      accent: kNeonGreen,
    );
    if (mounted) Navigator.pop(context);
  }

  Color get _statusColor {
    switch (_status) {
      case _ZoneStatus.inZone:
        return kNeonGreen;
      case _ZoneStatus.tooSlow:
        return const Color(0xFFFF7A1A);
      case _ZoneStatus.tooFast:
        return kNeonCyan;
      case _ZoneStatus.idle:
        return AppColors.textSecondary;
    }
  }

  String get _statusLabel {
    switch (_status) {
      case _ZoneStatus.inZone:
        return 'DANS LA ZONE';
      case _ZoneStatus.tooSlow:
        return 'TROP LENT → ACCÉLÈRE';
      case _ZoneStatus.tooFast:
        return 'TROP RAPIDE → RALENTIS';
      case _ZoneStatus.idle:
        return 'EN ATTENTE…';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('ZONE D\'ALLURE',
            style: TextStyle(
                fontFamily: kArcadeFont,
                color: kNeonGreen,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                shadows: [Shadow(color: kNeonGreen, blurRadius: 12)])),
      ),
      body: _running ? _buildRunning() : _buildSetup(),
    );
  }

  // ── Setup ──────────────────────────────────────────────────────────────────
  Widget _buildSetup() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          const Text('Allure cible',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 8),
          _Stepper(
            value: '${formatPace(_targetSec)} /km',
            onMinus: () => setState(
                () => _targetSec = (_targetSec + 5).clamp(150, 600)),
            onPlus: () => setState(
                () => _targetSec = (_targetSec - 5).clamp(150, 600)),
          ),
          const SizedBox(height: 24),
          const Text('Tolérance',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 8),
          _Stepper(
            value: '± $_tolerance s',
            onMinus: () =>
                setState(() => _tolerance = (_tolerance - 5).clamp(5, 60)),
            onPlus: () =>
                setState(() => _tolerance = (_tolerance + 5).clamp(5, 60)),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: const Text(
              'Maintiens ton allure dans la zone. La voix t\'indique d\'accélérer ou de ralentir. Pose le téléphone ou garde-le sur toi : le son suffit.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _start,
              style: ElevatedButton.styleFrom(
                backgroundColor: kNeonGreen,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('DÉMARRER',
                  style: TextStyle(
                      fontFamily: kArcadeFont,
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Running ────────────────────────────────────────────────────────────────
  Widget _buildRunning() {
    final paceSec = _pace.paceSecPerKm;
    final pct = _elapsed > 0 ? (_inZoneSeconds / _elapsed * 100).round() : 0;
    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            color: _statusColor.withOpacity(0.08),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_statusLabel,
                    style: TextStyle(
                        fontFamily: kArcadeFont,
                        color: _statusColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                        shadows: [Shadow(color: _statusColor, blurRadius: 12)])),
                const SizedBox(height: 16),
                Text(formatPace(paceSec),
                    style: TextStyle(
                        fontFamily: kArcadeFont,
                        color: Colors.white,
                        fontSize: 72,
                        fontWeight: FontWeight.w900,
                        shadows: [Shadow(color: _statusColor, blurRadius: 24)])),
                const Text('min / km',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                const SizedBox(height: 8),
                Text('Cible ${formatPace(_targetSec)}  •  ± $_tolerance s',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, 20 + MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(color: AppColors.surface),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _LiveStat(label: 'TEMPS', value: _fmtTime(_elapsed)),
                  _LiveStat(
                      label: 'DISTANCE',
                      value: '${(_pace.totalDistance / 1000).toStringAsFixed(2)} km'),
                  _LiveStat(label: 'EN ZONE', value: '$pct %'),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _stop,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kNeonRed,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('TERMINER',
                      style: TextStyle(
                          fontFamily: kArcadeFont,
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _fmtTime(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }
}

class _Stepper extends StatelessWidget {
  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  const _Stepper(
      {required this.value, required this.onMinus, required this.onPlus});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _circleBtn(Icons.remove_rounded, onMinus),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: kArcadeFont,
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900)),
          ),
          _circleBtn(Icons.add_rounded, onPlus),
        ],
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: kNeonGreen.withOpacity(0.15),
            shape: BoxShape.circle,
            border: Border.all(color: kNeonGreen, width: 1.5),
          ),
          child: Icon(icon, color: kNeonGreen),
        ),
      ),
    );
  }
}

class _LiveStat extends StatelessWidget {
  final String label;
  final String value;
  const _LiveStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontFamily: kArcadeFont,
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                letterSpacing: 1)),
      ],
    );
  }
}
