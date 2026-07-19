// lib/screens/live_musculation_screen.dart
// Séance en direct (muscu ET cardio — même logique, un exercice cardio se
// choisit comme un autre au milieu d'une séance) : chrono de séance, bascule
// simple En exercice / Pause, saisie des données PENDANT le repos qui suit
// (reps+charge, ou durée+distance pour le cardio — jamais avant, puisqu'on ne
// les connaît qu'une fois le bloc fait), et données montre (FC) rattachées à
// la séance entière une fois terminée (comme les courses/méditation : jamais
// de polling en direct, une seule lecture Health Connect sur toute la
// fenêtre à la fin).
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../data/exercise_library.dart';
import '../models/musculation_log.dart';
import '../models/musculation_session.dart';
import '../providers/game_provider.dart' show musculationRevisionProvider;
import '../services/audio_coach.dart';
import '../services/export_service.dart';
import '../services/health_connect_service.dart';
import '../services/musculation_session_store.dart';
import '../services/musculation_store.dart';
import '../theme.dart';
import '../widgets/ui_kit.dart';

enum _Phase { working, resting }

class LiveMusculationScreen extends ConsumerStatefulWidget {
  const LiveMusculationScreen({super.key});

  @override
  ConsumerState<LiveMusculationScreen> createState() =>
      _LiveMusculationScreenState();
}

class _LiveMusculationScreenState extends ConsumerState<LiveMusculationScreen> {
  late final DateTime _sessionStart = DateTime.now();
  int get _sessionId => _sessionStart.millisecondsSinceEpoch;

  Timer? _ticker;
  int _sessionElapsed = 0;

  _Phase _phase = _Phase.working;
  int _workElapsed = 0;
  int _restElapsed = 0;
  int? _restTarget;
  bool _restAlertFired = false;

  Exercise? _exercise;
  int _reps = 10;
  double _charge = 0;
  int _duration = 0;
  double _distance = 0;
  bool _isInterval = false;

  final AudioCoach _coach = AudioCoach();
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _coach.init();
    _ticker = Timer.periodic(const Duration(seconds: 1), _onTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickExercise());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _coach.stop();
    WakelockPlus.disable();
    super.dispose();
  }

  void _onTick(Timer t) {
    if (!mounted) return;
    setState(() {
      _sessionElapsed++;
      if (_phase == _Phase.working) {
        _workElapsed++;
      } else {
        _restElapsed++;
        if (_restTarget != null &&
            !_restAlertFired &&
            _restElapsed >= _restTarget!) {
          _restAlertFired = true;
          HapticFeedback.heavyImpact();
          _coach.say('Objectif de repos atteint', interrupt: true);
        }
      }
    });
  }

  List<MusculationLogEntry> get _sessionSets =>
      MusculationStore.entriesForSession(_sessionId).map((e) => e.value).toList();

  void _applyPrefill(Exercise ex) {
    final ownSets = _sessionSets.where((s) => s.exerciseId == ex.id).toList();
    final source = ownSets.isNotEmpty
        ? ownSets.last
        : MusculationStore.all().lastWhereOrNull((s) => s.exerciseId == ex.id);
    setState(() {
      if (ex.category.isCardio) {
        _duration = source?.durationSeconds ?? 0;
        _distance = source?.distanceKm ?? 0;
        _isInterval = source?.isInterval ?? false;
      } else {
        _reps = source?.reps ?? 10;
        _charge = source?.chargeKg ?? 0;
      }
    });
  }

  Future<void> _pickExercise() async {
    final ex = await showAppSheet<Exercise>(
        context: context, child: const _ExercisePickerSheet());
    if (ex == null) return;
    // Changer d'exercice repart toujours d'un état "en exercice" propre — si
    // on était en plein repos (saisie pas encore confirmée), ce changement
    // d'avis annule implicitement cette saisie en cours.
    setState(() {
      _exercise = ex;
      _phase = _Phase.working;
      _workElapsed = 0;
    });
    _applyPrefill(ex);
  }

  void _endSet() {
    final ex = _exercise;
    if (ex == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _phase = _Phase.resting;
      _restElapsed = 0;
      _restAlertFired = false;
      // Cardio : la durée de l'effort qu'on vient de faire est mesurée, pas
      // devinée — préremplie ici, encore ajustable pendant le repos.
      if (ex.category.isCardio) _duration = _workElapsed;
    });
  }

  Future<void> _confirmSetAndRest() async {
    final ex = _exercise;
    if (ex == null) return;
    final cardio = ex.category.isCardio;
    await MusculationStore.addEntry(MusculationLogEntry(
      date: DateTime.now(),
      exerciseId: ex.id,
      exerciseName: ex.name,
      category: ex.category,
      sets: 1,
      reps: cardio ? 0 : _reps,
      chargeKg: cardio ? 0 : _charge,
      sessionId: _sessionId,
      restSeconds: _restElapsed,
      durationSeconds: cardio ? _duration : 0,
      distanceKm: cardio ? _distance : 0,
      isInterval: cardio ? _isInterval : false,
    ));
    ref.read(musculationRevisionProvider.notifier).state++;
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _phase = _Phase.working;
      _workElapsed = 0;
    });
  }

  void _discardSet() {
    setState(() {
      _phase = _Phase.working;
      _workElapsed = 0;
    });
  }

  Future<void> _finishSession() async {
    if (_finishing) return;
    final sets = _sessionSets;
    if (sets.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() => _finishing = true);
    _ticker?.cancel();
    final end = DateTime.now();
    final vitals = await HealthConnectService().getActivityVitals(_sessionStart, end);
    await MusculationSessionStore.addEntry(MusculationSession(
      date: _sessionStart,
      endDate: end,
      avgHr: vitals.avgHr,
      minHr: vitals.minHr,
      maxHr: vitals.maxHr,
      activeCalories: vitals.activeCalories,
    ));
    // Best-effort, comme le reste des exports — n'empêche jamais la
    // sauvegarde locale si le vault est injoignable.
    unawaited(ExportService.saveMusculationDayAsMarkdown(
        DateTime.now(),
        MusculationStore.todayEntries().map((e) => e.value).toList()));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _SessionRecapDialog(
        durationSeconds: end.difference(_sessionStart).inSeconds,
        sets: sets,
        vitals: vitals,
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _confirmClose() async {
    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Terminer la séance ?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          _sessionSets.isEmpty
              ? 'Aucun bloc enregistré pour l\'instant.'
              : '${_sessionSets.length} bloc(s) enregistré(s) seront gardés.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continuer la séance'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kNeonPink),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Terminer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (choice == true) await _finishSession();
  }

  @override
  Widget build(BuildContext context) {
    final phaseColor = _phase == _Phase.working ? kNeonGreen : kNeonAmber;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
          onPressed: _confirmClose,
        ),
        title: Text(
          'SÉANCE · ${_fmtClock(_sessionElapsed)}',
          style: const TextStyle(
            fontFamily: kArcadeFont,
            color: kNeonPink,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _finishing ? null : _confirmClose,
            child: const Text('TERMINER',
                style: TextStyle(color: kNeonPink, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GestureDetector(
            onTap: _pickExercise,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                    color: (_exercise?.category.color ?? AppColors.border)
                        .withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  Icon(_exercise?.category.icon ?? Icons.fitness_center_rounded,
                      color: _exercise?.category.color ?? AppColors.textSecondary,
                      size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _exercise?.name ?? 'Choisir un exercice',
                      style: TextStyle(
                        color: _exercise != null
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.swap_horiz_rounded,
                      color: AppColors.textSecondary, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppPanel(
            accent: phaseColor,
            hero: true,
            child: _phase == _Phase.working
                ? _WorkingPanel(
                    onEndSet: _exercise != null ? _endSet : null,
                    isCardio: _exercise?.category.isCardio ?? false,
                    workElapsed: _workElapsed,
                  )
                : _RestingPanel(
                    isCardio: _exercise!.category.isCardio,
                    restElapsed: _restElapsed,
                    restTarget: _restTarget,
                    onTargetChanged: (v) => setState(() {
                      _restTarget = v;
                      _restAlertFired = false;
                    }),
                    reps: _reps,
                    charge: _charge,
                    onRepsChanged: (v) => setState(() => _reps = v),
                    onChargeChanged: (v) => setState(() => _charge = v),
                    duration: _duration,
                    distance: _distance,
                    isInterval: _isInterval,
                    onDurationChanged: (v) => setState(() => _duration = v),
                    onDistanceChanged: (v) => setState(() => _distance = v),
                    onIntervalChanged: (v) => setState(() => _isInterval = v),
                    onConfirm: _confirmSetAndRest,
                    onDiscard: _discardSet,
                  ),
          ),
          const SizedBox(height: AppSpacing.xl),
          PanelTitle('BLOCS DE CETTE SÉANCE (${_sessionSets.length})',
              color: kNeonCyan),
          const SizedBox(height: AppSpacing.md),
          if (_sessionSets.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Aucun bloc enregistré pour l\'instant.',
                  style: AppText.caption),
            )
          else
            for (final s in _sessionSets.reversed) _SessionSetTile(entry: s),
        ],
      ),
    );
  }
}

class _WorkingPanel extends StatelessWidget {
  final VoidCallback? onEndSet;
  final bool isCardio;
  final int workElapsed;
  const _WorkingPanel(
      {required this.onEndSet, required this.isCardio, required this.workElapsed});

  @override
  Widget build(BuildContext context) {
    final active = onEndSet != null;
    return Column(
      children: [
        Text(isCardio ? 'EN EFFORT' : 'EN EXERCICE',
            style: const TextStyle(
                fontFamily: kArcadeFont,
                color: kNeonGreen,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1)),
        const SizedBox(height: AppSpacing.md),
        if (isCardio) ...[
          Text(
            _fmtClock(workElapsed),
            style: TextStyle(
                fontFamily: kArcadeFont,
                color: Colors.white.withOpacity(active ? 1 : 0.3),
                fontSize: 36,
                fontWeight: FontWeight.w900),
          ),
        ] else ...[
          Icon(Icons.fitness_center_rounded,
              color: kNeonGreen.withOpacity(active ? 1 : 0.3), size: 40),
          const SizedBox(height: 4),
          Text(_fmtClock(workElapsed),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        ],
        const SizedBox(height: AppSpacing.lg),
        GlowButton(
          label: isCardio ? 'TERMINER L\'EFFORT' : 'TERMINER LA SÉRIE',
          icon: Icons.check_rounded,
          color: kNeonGreen,
          foreground: Colors.black,
          onPressed: onEndSet,
        ),
        if (!active) ...[
          const SizedBox(height: AppSpacing.sm),
          const Text('Choisis un exercice pour commencer.',
              style: AppText.caption, textAlign: TextAlign.center),
        ],
      ],
    );
  }
}

class _RestingPanel extends StatelessWidget {
  final bool isCardio;
  final int restElapsed;
  final int? restTarget;
  final ValueChanged<int?> onTargetChanged;
  final int reps;
  final double charge;
  final ValueChanged<int> onRepsChanged;
  final ValueChanged<double> onChargeChanged;
  final int duration;
  final double distance;
  final bool isInterval;
  final ValueChanged<int> onDurationChanged;
  final ValueChanged<double> onDistanceChanged;
  final ValueChanged<bool> onIntervalChanged;
  final VoidCallback onConfirm;
  final VoidCallback onDiscard;

  const _RestingPanel({
    required this.isCardio,
    required this.restElapsed,
    required this.restTarget,
    required this.onTargetChanged,
    required this.reps,
    required this.charge,
    required this.onRepsChanged,
    required this.onChargeChanged,
    required this.duration,
    required this.distance,
    required this.isInterval,
    required this.onDurationChanged,
    required this.onDistanceChanged,
    required this.onIntervalChanged,
    required this.onConfirm,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final reached = restTarget != null && restElapsed >= restTarget!;
    return Column(
      children: [
        const Text('REPOS',
            style: TextStyle(
                fontFamily: kArcadeFont,
                color: kNeonAmber,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1)),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _fmtClock(restElapsed),
          style: TextStyle(
            fontFamily: kArcadeFont,
            color: reached ? kNeonGreen : Colors.white,
            fontSize: 36,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            _TargetChip(
                label: 'Libre', selected: restTarget == null, onTap: () => onTargetChanged(null)),
            for (final t in [60, 90, 120])
              _TargetChip(
                  label: '${t}s',
                  selected: restTarget == t,
                  onTap: () => onTargetChanged(restTarget == t ? null : t)),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
              isCardio ? 'EFFORT QUE TU VIENS DE FAIRE' : 'SÉRIE QUE TU VIENS DE FAIRE',
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8)),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (isCardio) ...[
          _DurationStepperRow(value: duration, onChanged: onDurationChanged),
          const SizedBox(height: 10),
          _DistanceStepperRow(value: distance, onChanged: onDistanceChanged),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: _TargetChip(
                label: 'Fractionné',
                selected: isInterval,
                onTap: () => onIntervalChanged(!isInterval)),
          ),
        ] else ...[
          _StepperRow(label: 'Répétitions', value: reps, onChanged: onRepsChanged),
          const SizedBox(height: 10),
          _ChargeStepperRow(value: charge, onChanged: onChargeChanged),
        ],
        const SizedBox(height: AppSpacing.lg),
        GlowButton(
          label: isCardio ? 'BLOC SUIVANT' : 'SÉRIE SUIVANTE',
          icon: Icons.arrow_forward_rounded,
          color: kNeonCyan,
          foreground: Colors.black,
          onPressed: onConfirm,
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: onDiscard,
          child: Text(isCardio ? 'Annuler ce bloc' : 'Annuler cette série',
              style: const TextStyle(color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}

class _TargetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TargetChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? kNeonAmber.withOpacity(0.18) : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? kNeonAmber : AppColors.border),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? kNeonAmber : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
      ),
    );
  }
}

class _SessionSetTile extends StatelessWidget {
  final MusculationLogEntry entry;
  const _SessionSetTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: entry.category.color.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(entry.category.icon, color: entry.category.color, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(entry.exerciseName, style: AppText.body),
          ),
          Text(_setSummary(entry),
              style: TextStyle(
                  fontFamily: kArcadeFont,
                  color: entry.category.color,
                  fontSize: 13,
                  fontWeight: FontWeight.w800)),
          if (entry.isInterval) ...[
            const SizedBox(width: 6),
            const Icon(Icons.bolt_rounded, color: kNeonAmber, size: 14),
          ],
          if (entry.restSeconds > 0) ...[
            const SizedBox(width: 10),
            Icon(Icons.timer_outlined, color: AppColors.textSecondary, size: 13),
            const SizedBox(width: 3),
            Text(_fmtClock(entry.restSeconds),
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _SessionRecapDialog extends StatelessWidget {
  final int durationSeconds;
  final List<MusculationLogEntry> sets;
  final ActivityVitals vitals;

  const _SessionRecapDialog(
      {required this.durationSeconds, required this.sets, required this.vitals});

  @override
  Widget build(BuildContext context) {
    final strengthSets = sets.where((e) => !e.category.isCardio).toList();
    final cardioSets = sets.where((e) => e.category.isCardio).toList();
    final totalVolume = strengthSets.fold<double>(0, (s, e) => s + e.volumeKg);
    final totalCardioDuration =
        cardioSets.fold<int>(0, (s, e) => s + e.durationSeconds);
    final totalCardioDistance =
        cardioSets.fold<double>(0, (s, e) => s + e.distanceKm);
    final avgRest = sets.where((e) => e.restSeconds > 0).isEmpty
        ? 0
        : sets.where((e) => e.restSeconds > 0).map((e) => e.restSeconds).reduce((a, b) => a + b) ~/
            sets.where((e) => e.restSeconds > 0).length;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Séance terminée',
          style: TextStyle(
              fontFamily: kArcadeFont, color: kNeonGreen, fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RecapRow('Durée', _fmtClock(durationSeconds)),
          _RecapRow('Blocs', '${sets.length}'),
          if (strengthSets.isNotEmpty)
            _RecapRow('Volume total', '${totalVolume.toStringAsFixed(0)} kg'),
          if (cardioSets.isNotEmpty)
            _RecapRow('Cardio',
                '${_fmtClock(totalCardioDuration)}${totalCardioDistance > 0 ? ' · ${totalCardioDistance.toStringAsFixed(1)} km' : ''}'),
          if (avgRest > 0) _RecapRow('Repos moyen', _fmtClock(avgRest)),
          if (vitals.hasHr)
            _RecapRow('FC moy. (min-max)',
                '${vitals.avgHr.round()} (${vitals.minHr.round()}-${vitals.maxHr.round()}) bpm'),
        ],
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kNeonGreen),
          onPressed: () => Navigator.pop(context),
          child: const Text('OK', style: TextStyle(color: Colors.black)),
        ),
      ],
    );
  }
}

class _RecapRow extends StatelessWidget {
  final String label;
  final String value;
  const _RecapRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Text(value,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ── Sélecteur d'exercice : recherche + filtre catégorie, renvoie l'exercice
// choisi (Navigator.pop(ctx, exercise)) — contrairement à _QuickLogSheet
// (musculation_screen.dart), ne demande pas séries/reps ici, juste le choix
// de l'exercice, puisque la saisie a lieu plus tard pendant le repos. ───────
class _ExercisePickerSheet extends StatefulWidget {
  const _ExercisePickerSheet();

  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  ExerciseCategory? _filter;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final query = _search.trim().toLowerCase();
    final exercises = kExerciseLibrary.where((e) {
      if (_filter != null && e.category != _filter) return false;
      if (query.isNotEmpty && !e.name.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).toList();

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Choisir un exercice',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5)),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            onChanged: (v) => setState(() => _search = v),
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Rechercher un exercice…',
              prefixIcon: Icon(Icons.search_rounded, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChip(
                  label: 'Tout',
                  color: AppColors.textSecondary,
                  selected: _filter == null,
                  onTap: () => setState(() => _filter = null),
                ),
                for (final c in ExerciseCategory.values) ...[
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: c.label,
                    color: c.color,
                    selected: _filter == c,
                    onTap: () => setState(() => _filter = c),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: exercises.isEmpty
                ? const Center(
                    child: Text('Aucun exercice trouvé.', style: AppText.caption))
                : ListView.builder(
                    itemCount: exercises.length,
                    itemBuilder: (context, i) {
                      final e = exercises[i];
                      return GestureDetector(
                        onTap: () => Navigator.pop(context, e),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: e.category.color.withOpacity(0.14),
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                ),
                                child: Icon(e.category.icon,
                                    color: e.category.color, size: 17),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(e.name, style: AppText.body),
                                    Text(e.muscleGroup, style: AppText.caption),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip(
      {required this.label, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.16) : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color.withOpacity(0.6) : AppColors.border),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  const _StepperRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded,
                  color: AppColors.textSecondary),
              onPressed: value > 1 ? () => onChanged(value - 1) : null,
            ),
            SizedBox(
              width: 34,
              child: Text('$value',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: kArcadeFont,
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded,
                  color: AppColors.textSecondary),
              onPressed: () => onChanged(value + 1),
            ),
          ],
        ),
      ],
    );
  }
}

class _DurationStepperRow extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _DurationStepperRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Durée', style: TextStyle(color: AppColors.textSecondary)),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded,
                  color: AppColors.textSecondary),
              onPressed: value > 0 ? () => onChanged(max(0, value - 15)) : null,
            ),
            SizedBox(
              width: 56,
              child: Text(_fmtClock(value),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: kArcadeFont,
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded,
                  color: AppColors.textSecondary),
              onPressed: () => onChanged(value + 15),
            ),
          ],
        ),
      ],
    );
  }
}

class _DistanceStepperRow extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _DistanceStepperRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Distance (km, optionnel)',
            style: TextStyle(color: AppColors.textSecondary)),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded,
                  color: AppColors.textSecondary),
              onPressed: value > 0 ? () => onChanged(max(0, value - 0.1)) : null,
            ),
            SizedBox(
              width: 48,
              child: Text(
                value > 0 ? value.toStringAsFixed(1) : '--',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: kArcadeFont,
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded,
                  color: AppColors.textSecondary),
              onPressed: () => onChanged(value + 0.1),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChargeStepperRow extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const _ChargeStepperRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Charge (kg)', style: TextStyle(color: AppColors.textSecondary)),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded,
                  color: AppColors.textSecondary),
              onPressed: value > 0 ? () => onChanged(max(0, value - 2.5)) : null,
            ),
            SizedBox(
              width: 48,
              child: Text(
                value > 0 ? _formatCharge(value) : '--',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: kArcadeFont,
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded,
                  color: AppColors.textSecondary),
              onPressed: () => onChanged(value + 2.5),
            ),
          ],
        ),
      ],
    );
  }
}

extension _LastWhereOrNull<T> on List<T> {
  T? lastWhereOrNull(bool Function(T) test) {
    for (var i = length - 1; i >= 0; i--) {
      if (test(this[i])) return this[i];
    }
    return null;
  }
}

String _formatCharge(double kg) =>
    kg == kg.roundToDouble() ? kg.toInt().toString() : kg.toStringAsFixed(1);

/// Résumé compact d'un bloc loggé — durée/distance pour le cardio,
/// reps × charge sinon.
String _setSummary(MusculationLogEntry e) {
  if (e.category.isCardio) {
    final parts = <String>[_fmtClock(e.durationSeconds)];
    if (e.distanceKm > 0) parts.add('${e.distanceKm.toStringAsFixed(1)} km');
    return parts.join(' · ');
  }
  return e.chargeKg > 0
      ? '${e.reps} × ${_formatCharge(e.chargeKg)} kg'
      : '${e.reps} reps';
}

String _fmtClock(int totalSeconds) {
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
