// lib/screens/interval_game_screen.dart
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
import '../services/game_result_store.dart';
import '../services/game_service.dart';
import '../services/hive_service.dart';
import '../services/live_pace.dart';
import '../services/location_service.dart';
import '../services/vo2_estimator_service.dart';
import '../widgets/system_window.dart';
import '../theme.dart';

enum _Kind { warmup, work, rest }

class _Phase {
  final _Kind kind;
  final int seconds;
  final int repIndex;
  const _Phase(this.kind, this.seconds, this.repIndex);
}

/// Préréglage à appliquer à l'ouverture (ex. depuis la suggestion
/// "Lance un 4×4" du hub Sport) — évite de repasser par les boutons +/-.
typedef IntervalPreset = ({int work, int rest, int reps, int warmup});

class IntervalGameScreen extends ConsumerStatefulWidget {
  final IntervalPreset? initialPreset;
  const IntervalGameScreen({super.key, this.initialPreset});

  @override
  ConsumerState<IntervalGameScreen> createState() => _IntervalGameScreenState();
}

class _IntervalGameScreenState extends ConsumerState<IntervalGameScreen> {
  // Réglages
  int _warmup = 60;
  int _work = 30;
  int _rest = 30;
  int _reps = 8;

  // Runtime
  bool _running = false;
  final LivePace _pace = LivePace();
  final AudioCoach _coach = AudioCoach();
  StreamSubscription<Position>? _sub;
  Timer? _timer;

  List<_Phase> _phases = [];
  int _idx = 0;
  int _remaining = 0;
  int _elapsed = 0;
  double _speedKmh = 0;

  double _curWorkStartDist = 0;
  double _workDistanceTotal = 0;
  int _workSecondsTotal = 0;
  int _repsCompleted = 0;

  // Trace GPS + repères par répétition, pour exporter une vraie Activity en
  // fin de séance (voir _finish) — condition nécessaire pour que le
  // fractionné alimente l'estimation VO2 max (paires FC/allure par lap).
  final List<List<double>> _route = [];
  final List<Map<String, dynamic>> _laps = [];
  final List<int> _pointSeconds = [];

  @override
  void initState() {
    super.initState();
    final p = widget.initialPreset;
    if (p != null) {
      _work = p.work;
      _rest = p.rest;
      _reps = p.reps;
      _warmup = p.warmup;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    _coach.stop();
    WakelockPlus.disable();
    super.dispose();
  }

  void _applyPreset(int w, int r, int reps, {int warmup = 60}) {
    setState(() {
      _work = w;
      _rest = r;
      _reps = reps;
      _warmup = warmup;
    });
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

    _phases = [];
    if (_warmup > 0) _phases.add(_Phase(_Kind.warmup, _warmup, 0));
    for (int i = 1; i <= _reps; i++) {
      _phases.add(_Phase(_Kind.work, _work, i));
      if (i < _reps && _rest > 0) _phases.add(_Phase(_Kind.rest, _rest, i));
    }

    setState(() {
      _running = true;
      _idx = 0;
      _elapsed = 0;
      _workDistanceTotal = 0;
      _workSecondsTotal = 0;
      _repsCompleted = 0;
    });
    _route.clear();
    _laps.clear();
    _pointSeconds.clear();
    HapticFeedback.mediumImpact();

    _sub = LocationService.getPositionStream().listen((p) {
      _speedKmh = _pace.addPosition(p);
      _route.add([p.latitude, p.longitude]);
      _pointSeconds.add(_elapsed);
    });
    _enterPhase();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _enterPhase() {
    final p = _phases[_idx];
    _remaining = p.seconds;
    switch (p.kind) {
      case _Kind.warmup:
        _coach.say('Échauffement. $_warmup secondes.', interrupt: true);
        break;
      case _Kind.work:
        _curWorkStartDist = _pace.totalDistance;
        final isLast = !_phases.skip(_idx + 1).any((x) => x.kind == _Kind.work);
        _coach.say(
            isLast
                ? 'Dernière répétition. Effort !'
                : 'Effort ! Répétition ${p.repIndex}',
            interrupt: true);
        break;
      case _Kind.rest:
        _coach.say('Récupération', interrupt: true);
        break;
    }
    HapticFeedback.heavyImpact();
    setState(() {});
  }

  void _advance() {
    final leaving = _phases[_idx];
    if (leaving.kind == _Kind.work) {
      final repDist = _pace.totalDistance - _curWorkStartDist;
      _workDistanceTotal += repDist;
      _workSecondsTotal += leaving.seconds;
      _repsCompleted++;
      // Un lap par répétition d'effort : c'est ce qui permet à l'estimateur
      // VO2 max de découper la FC par intervalle plutôt que sur la moyenne
      // de toute la séance (qui mélangerait effort et récup).
      _laps.add({
        'lapNumber': _repsCompleted,
        'duration': leaving.seconds,
        'distance': repDist,
        'totalTimeAtLap': _elapsed,
      });
    }
    _idx++;
    if (_idx >= _phases.length) {
      _finish();
      return;
    }
    _enterPhase();
  }

  void _tick() {
    if (_remaining <= 0) {
      _advance();
      return;
    }
    final p = _phases[_idx];
    // Décompte 3-2-1 avant un effort
    if ((p.kind == _Kind.warmup || p.kind == _Kind.rest) && _remaining <= 3) {
      _coach.say('$_remaining', interrupt: true);
    }
    setState(() {
      _remaining--;
      _elapsed++;
    });
  }

  Future<void> _finish({bool aborted = false}) async {
    _timer?.cancel();
    await _sub?.cancel();
    WakelockPlus.disable();
    _running = false;

    final avgPaceSec = _workDistanceTotal > 50
        ? (_workSecondsTotal / (_workDistanceTotal / 1000)).round()
        : 0;
    final xp = _repsCompleted * 25 + (_workDistanceTotal / 1000 * 15).round();

    await _coach.say(aborted ? 'Séance arrêtée.' : 'Terminé, bravo !');
    await GameResultStore.add({
      'type': 'hiit',
      'date': DateTime.now().millisecondsSinceEpoch,
      'work': _work,
      'rest': _rest,
      'reps': _reps,
      'repsCompleted': _repsCompleted,
      'workDistance': _workDistanceTotal,
      'avgPaceSec': avgPaceSec,
      'duration': _elapsed,
      'xp': xp,
    });
    await GameStore.addBonusXp(xp);
    ref.read(questBonusProvider.notifier).state = GameStore.questBonusXp;

    // Enregistre une vraie Activity (GPS + laps par répétition) si la séance
    // a produit quelque chose d'exploitable — sinon (arrêt immédiat) inutile
    // d'ajouter une entrée vide à l'historique. C'est ce qui permet à cette
    // séance de compter pour l'estimation VO2 max et d'apparaître dans le
    // suivi Sport comme une vraie sortie.
    if (_repsCompleted > 0 && _pace.totalDistance > 0) {
      final activity = Activity(
        date: DateTime.now().subtract(Duration(seconds: _elapsed)),
        distance: _pace.totalDistance,
        duration: _elapsed,
        route: _route,
        name: 'Fractionné $_reps× ($_work s / $_rest s)',
        lapCount: _repsCompleted,
        laps: _laps,
        workoutType: 'interval',
        pointSeconds: _pointSeconds,
      );
      await HiveService.saveActivity(activity);
      ref.read(activityListProvider.notifier).refresh();
      unawaited(Vo2EstimatorService.recomputeAndStore(
          ref.read(activityListProvider)));
    }

    if (!mounted) return;
    await showSystemWindow(
      context,
      heading: aborted ? 'SÉANCE ARRÊTÉE' : 'SÉANCE TERMINÉE',
      lines: [
        'Répétitions : $_repsCompleted / $_reps',
        'Distance effort : ${(_workDistanceTotal / 1000).toStringAsFixed(2)} km',
        'Allure effort : ${formatPace(avgPaceSec == 0 ? null : avgPaceSec)} /km',
        '+$xp XP',
      ],
      accent: kNeonPink,
    );
    if (mounted) Navigator.pop(context);
  }

  // ── UI ───────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('FRACTIONNÉ',
            style: TextStyle(
                fontFamily: kArcadeFont,
                color: kNeonPink,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                shadows: [Shadow(color: kNeonPink, blurRadius: 12)])),
      ),
      body: _running ? _buildRunning() : _buildSetup(),
    );
  }

  Widget _buildSetup() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          const Text('Préréglages',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _preset('30/30 ×8', 30, 30, 8),
              _preset('45/15 ×10', 45, 15, 10),
              _preset('1min/1min ×6', 60, 60, 6),
              _preset('2min/2min ×5', 120, 120, 5),
              _preset('4min/3min ×4', 240, 180, 4, warmup: 300),
            ],
          ),
          const SizedBox(height: 24),
          _row('Échauffement', '$_warmup s',
              () => setState(() => _warmup = (_warmup - 15).clamp(0, 600)),
              () => setState(() => _warmup = (_warmup + 15).clamp(0, 600))),
          _row('Effort', '$_work s',
              () => setState(() => _work = (_work - 5).clamp(5, 600)),
              () => setState(() => _work = (_work + 5).clamp(5, 600))),
          _row('Récupération', '$_rest s',
              () => setState(() => _rest = (_rest - 5).clamp(0, 600)),
              () => setState(() => _rest = (_rest + 5).clamp(0, 600))),
          _row('Répétitions', '$_reps',
              () => setState(() => _reps = (_reps - 1).clamp(1, 30)),
              () => setState(() => _reps = (_reps + 1).clamp(1, 30))),
          const SizedBox(height: 20),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _start,
              style: ElevatedButton.styleFrom(
                backgroundColor: kNeonPink,
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

  Widget _preset(String label, int w, int r, int reps, {int warmup = 60}) {
    final active = _work == w && _rest == r && _reps == reps;
    return GestureDetector(
      onTap: () => _applyPreset(w, r, reps, warmup: warmup),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? kNeonPink.withOpacity(0.2) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: active ? kNeonPink : AppColors.border, width: 1.3),
        ),
        child: Text(label,
            style: TextStyle(
                fontFamily: kArcadeFont,
                color: active ? kNeonPink : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _row(String label, String value, VoidCallback minus, VoidCallback plus) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style:
                    const TextStyle(color: Colors.white, fontSize: 15)),
          ),
          _btn(Icons.remove_rounded, minus),
          SizedBox(
            width: 72,
            child: Text(value,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: kArcadeFont,
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900)),
          ),
          _btn(Icons.add_rounded, plus),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: kNeonPink.withOpacity(0.15),
          shape: BoxShape.circle,
          border: Border.all(color: kNeonPink, width: 1.3),
        ),
        child: Icon(icon, color: kNeonPink, size: 20),
      ),
    );
  }

  Widget _buildRunning() {
    final p = _phases[_idx];
    final Color color;
    final String label;
    switch (p.kind) {
      case _Kind.warmup:
        color = AppColors.textSecondary;
        label = 'ÉCHAUFFEMENT';
        break;
      case _Kind.work:
        color = kNeonPink;
        label = 'EFFORT';
        break;
      case _Kind.rest:
        color = kNeonCyan;
        label = 'RÉCUPÉRATION';
        break;
    }
    final paceSec = _pace.paceSecPerKm;

    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            color: color.withOpacity(0.10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: TextStyle(
                        fontFamily: kArcadeFont,
                        color: color,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        shadows: [Shadow(color: color, blurRadius: 14)])),
                const SizedBox(height: 8),
                Text('$_remaining',
                    style: TextStyle(
                        fontFamily: kArcadeFont,
                        color: Colors.white,
                        fontSize: 96,
                        fontWeight: FontWeight.w900,
                        shadows: [Shadow(color: color, blurRadius: 28)])),
                const Text('secondes',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 14)),
                const SizedBox(height: 12),
                if (p.kind != _Kind.warmup)
                  Text('Répétition ${p.repIndex} / $_reps',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 14)),
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
                  _LiveStat(label: 'ALLURE', value: '${formatPace(paceSec)}/km'),
                  _LiveStat(
                      label: 'VITESSE',
                      value: '${_speedKmh.toStringAsFixed(1)} km/h'),
                  _LiveStat(label: 'TEMPS', value: _fmtTime(_elapsed)),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => _finish(aborted: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kNeonRed,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('ARRÊTER',
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
                fontSize: 16,
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
