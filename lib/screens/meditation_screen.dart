// lib/screens/meditation_screen.dart
// Pleine conscience : chrono démarrer/arrêter, historique des séances, FC
// pendant la séance (Health Connect, même fenêtre temporelle que les courses
// dans detail_screen.dart), série de jours consécutifs.
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/meditation_session.dart';
import '../services/health_connect_service.dart';
import '../services/meditation_store.dart';
import '../theme.dart';
import '../widgets/ui_kit.dart';

class MeditationScreen extends StatefulWidget {
  const MeditationScreen({super.key});

  @override
  State<MeditationScreen> createState() => _MeditationScreenState();
}

class _MeditationScreenState extends State<MeditationScreen> {
  Timer? _ticker;
  DateTime? _startTime;
  int _elapsedSeconds = 0;
  bool _saving = false;

  bool get _running => _startTime != null;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _start() {
    setState(() {
      _startTime = DateTime.now();
      _elapsedSeconds = 0;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds++);
    });
  }

  Future<void> _stop() async {
    final start = _startTime;
    if (start == null) return;
    _ticker?.cancel();
    _ticker = null;
    final end = DateTime.now();
    final durationSeconds = end.difference(start).inSeconds;

    // Séance trop courte pour être une vraie séance (tap accidentel) : on
    // annule sans enregistrer, sans bloquer l'utilisateur avec une erreur.
    if (durationSeconds < 10) {
      setState(() {
        _startTime = null;
        _elapsedSeconds = 0;
      });
      return;
    }

    setState(() => _saving = true);
    final vitals = await HealthConnectService().getActivityVitals(start, end);
    await MeditationStore.addEntry(MeditationSession(
      date: start,
      durationSeconds: durationSeconds,
      avgHr: vitals.avgHr,
      minHr: vitals.minHr,
      maxHr: vitals.maxHr,
    ));
    if (!mounted) return;
    setState(() {
      _startTime = null;
      _elapsedSeconds = 0;
      _saving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final history = MeditationStore.all();
    final streak = MeditationStore.streak();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text(
          'MÉDITATION',
          style: TextStyle(
            fontFamily: kArcadeFont,
            color: kNeonCyan,
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppPanel(
            accent: kNeonCyan,
            hero: true,
            child: Column(
              children: [
                if (streak > 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.local_fire_department_rounded,
                          color: kNeonAmber, size: 16),
                      const SizedBox(width: 4),
                      Text('$streak j de suite',
                          style: const TextStyle(
                              fontFamily: kArcadeFont,
                              color: kNeonAmber,
                              fontSize: 12,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                Text(
                  _fmtClock(_elapsedSeconds),
                  style: const TextStyle(
                    fontFamily: kArcadeFont,
                    color: Colors.white,
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                GlowButton(
                  label: _running ? 'ARRÊTER' : 'DÉMARRER',
                  icon: _running
                      ? Icons.stop_rounded
                      : Icons.self_improvement_rounded,
                  color: _running ? kNeonPink : kNeonCyan,
                  foreground: Colors.white,
                  busy: _saving,
                  onPressed: _saving ? null : (_running ? _stop : _start),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const PanelTitle('HISTORIQUE', color: kNeonCyan),
          const SizedBox(height: AppSpacing.md),
          if (history.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Aucune séance enregistrée pour l\'instant.',
                  style: AppText.caption),
            )
          else
            for (final entry in history)
              _SessionTile(
                sessionKey: entry.key,
                session: entry.value,
                onDeleted: () => setState(() {}),
              ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final String sessionKey;
  final MeditationSession session;
  final VoidCallback onDeleted;

  const _SessionTile({
    required this.sessionKey,
    required this.session,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.self_improvement_rounded, color: kNeonCyan, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_fmtDate(session.date), style: AppText.body),
                Text(
                  session.hasHr
                      ? 'FC moy. ${session.avgHr.round()} bpm (${session.minHr.round()}-${session.maxHr.round()})'
                      : 'FC non disponible',
                  style: AppText.caption,
                ),
              ],
            ),
          ),
          Text(_fmtClock(session.durationSeconds),
              style: const TextStyle(
                  fontFamily: kArcadeFont,
                  color: kNeonCyan,
                  fontSize: 13,
                  fontWeight: FontWeight.w800)),
          IconButton(
            icon: const Icon(Icons.close_rounded,
                color: AppColors.textSecondary, size: 18),
            onPressed: () async {
              await MeditationStore.deleteEntry(sessionKey);
              onDeleted();
            },
          ),
        ],
      ),
    );
  }
}

String _fmtClock(int totalSeconds) {
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String _fmtDate(DateTime d) {
  const months = [
    'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
    'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'
  ];
  final h = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${months[d.month - 1]} · $h:$min';
}
