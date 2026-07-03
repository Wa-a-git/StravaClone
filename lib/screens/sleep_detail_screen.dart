// lib/screens/sleep_detail_screen.dart
// Détail approfondi d'une nuit de sommeil : hypnogramme chronologique,
// répartition des stades, score, et navigation nuit par nuit (← →).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/daily_health_record.dart';
import '../models/health_snapshot.dart';
import '../services/health_score_service.dart';
import '../services/health_store.dart';
import '../theme.dart';
import '../widgets/health_charts.dart';
import '../widgets/ui_kit.dart';

class SleepDetailScreen extends StatefulWidget {
  /// Jour de départ (la nuit rattachée à ce jour civil). Par défaut aujourd'hui.
  final DateTime? initialDay;
  const SleepDetailScreen({super.key, this.initialDay});

  @override
  State<SleepDetailScreen> createState() => _SleepDetailScreenState();
}

class _SleepDetailScreenState extends State<SleepDetailScreen> {
  late List<DailyHealthRecord> _nights;
  late int _index;

  @override
  void initState() {
    super.initState();
    // Toutes les nuits avec du sommeil, de la plus récente à la plus ancienne.
    _nights = HealthStore.all().where((r) => r.totalSleepMin > 0).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final target = widget.initialDay ?? DateTime.now();
    final key = DailyHealthRecord.keyFor(target);
    final found = _nights.indexWhere((r) => r.key == key);
    _index = found >= 0 ? found : 0;
  }

  DailyHealthRecord? get _current =>
      _nights.isEmpty ? null : _nights[_index];

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= _nights.length) return;
    HapticFeedback.selectionClick();
    setState(() => _index = next);
  }

  String _fmtDuration(double minutes) {
    final h = minutes ~/ 60;
    final m = (minutes % 60).round();
    return '${h}h${m.toString().padLeft(2, '0')}';
  }

  String _fmtNightLabel(DateTime d) {
    const days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    const months = [
      'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
      'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'
    ];
    final today = DateTime.now();
    final isToday = DailyHealthRecord.keyFor(d) == DailyHealthRecord.keyFor(today);
    if (isToday) return 'Cette nuit';
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final rec = _current;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text(
          'SOMMEIL',
          style: TextStyle(
            fontFamily: kArcadeFont,
            color: kNeonViolet,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
      ),
      body: rec == null
          ? const EmptyState(
              icon: Icons.bedtime_rounded,
              title: 'Aucune nuit enregistrée',
              subtitle: 'Porte ta montre la nuit pour voir ton sommeil détaillé ici.',
              accent: kNeonViolet,
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _nightNav(rec),
                const SizedBox(height: AppSpacing.lg),
                _heroCard(rec),
                const SizedBox(height: AppSpacing.lg),
                _hypnogramCard(rec),
                const SizedBox(height: AppSpacing.lg),
                _stagesCard(rec.sleep),
                const SizedBox(height: AppSpacing.lg),
                _trendCard(),
              ],
            ),
    );
  }

  Widget _nightNav(DailyHealthRecord rec) {
    // _nights est trié du plus récent au plus ancien : index+1 = nuit + ancienne.
    final canGoOlder = _index < _nights.length - 1;
    final canGoNewer = _index > 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _navButton(Icons.chevron_left_rounded, canGoOlder, () => _go(1)),
        Text(
          _fmtNightLabel(rec.date),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        _navButton(Icons.chevron_right_rounded, canGoNewer, () => _go(-1)),
      ],
    );
  }

  Widget _navButton(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon,
            color: enabled ? kNeonViolet : AppColors.muted, size: 26),
      ),
    );
  }

  Widget _heroCard(DailyHealthRecord rec) {
    final sleep = rec.sleep;
    final score = rec.sleepScore;
    final bedtime = sleep.bedtime;
    final wake = sleep.wakeTime;
    String range = '';
    if (bedtime != null && wake != null) {
      String hm(DateTime d) =>
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      range = '${hm(bedtime)} – ${hm(wake)}';
    }
    return AppPanel(
      accent: kNeonViolet,
      hero: true,
      child: Row(
        children: [
          HealthRing(score: score, color: kNeonViolet, size: 96, centerLabel: 'SCORE'),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fmtDuration(sleep.totalAsleepMin),
                  style: const TextStyle(
                    fontFamily: kArcadeFont,
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (range.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(range, style: AppText.caption),
                ],
                const SizedBox(height: 8),
                Text(
                  'Efficacité ${sleep.efficiency.toStringAsFixed(0)}%',
                  style: const TextStyle(color: kNeonCyan, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hypnogramCard(DailyHealthRecord rec) {
    return AppPanel(
      accent: kNeonViolet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelTitle('CYCLES DE LA NUIT', color: kNeonViolet),
          const SizedBox(height: 14),
          Hypnogram(segments: rec.sleepSegments, height: 150),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final stage in [SleepStage.awake, SleepStage.rem, SleepStage.light, SleepStage.deep])
                _legendDot(stage.label, stage.color),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: AppText.caption),
      ],
    );
  }

  Widget _stagesCard(SleepBreakdown sleep) {
    final total = sleep.totalInBedMin <= 0 ? 1 : sleep.totalInBedMin;
    Widget row(SleepStage stage, double minutes) {
      final pct = (minutes / total * 100);
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: stage.color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(stage.label, style: AppText.body),
                const Spacer(),
                Text(_fmtDuration(minutes),
                    style: const TextStyle(
                        fontFamily: kArcadeFont,
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Text('${pct.toStringAsFixed(0)}%',
                      textAlign: TextAlign.right,
                      style: AppText.caption),
                ),
              ],
            ),
            const SizedBox(height: 6),
            AppProgressBar(value: minutes / total, color: stage.color, height: 6),
          ],
        ),
      );
    }

    return AppPanel(
      accent: kNeonViolet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelTitle('RÉPARTITION DES STADES', color: kNeonViolet),
          const SizedBox(height: 14),
          row(SleepStage.deep, sleep.deepMin),
          row(SleepStage.rem, sleep.remMin),
          row(SleepStage.light, sleep.lightMin),
          row(SleepStage.awake, sleep.awakeMin),
        ],
      ),
    );
  }

  Widget _trendCard() {
    final series = HealthStore.series(HealthMetric.sleepHours, 14)
        .map((e) => e.value)
        .where((v) => v > 0)
        .toList();
    return AppPanel(
      accent: kNeonCyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelTitle('DURÉE — 14 DERNIERS JOURS', color: kNeonCyan),
          const SizedBox(height: 14),
          if (series.length >= 2)
            TrendChart(
              values: series,
              color: kNeonCyan,
              baseline: HealthStore.baseline(HealthMetric.sleepHours, window: 14),
              height: 160,
            )
          else
            const SizedBox(
              height: 80,
              child: Center(
                child: Text('La tendance se construit nuit après nuit.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }
}
