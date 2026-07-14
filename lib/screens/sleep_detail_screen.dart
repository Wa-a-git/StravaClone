// lib/screens/sleep_detail_screen.dart
// Détail approfondi d'une nuit de sommeil : hypnogramme chronologique,
// répartition des stades, score, physio de la nuit (avec comparaison aux 7
// nuits précédentes) et navigation nuit par nuit (← →). Les tendances sur
// plusieurs nuits (durée, HRV, dette de sommeil...) ne sont volontairement
// pas ici — cet écran ne parle que de LA nuit affichée, voir le lien en bas
// vers l'onglet Santé pour tout ce qui est agrégé.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/daily_health_record.dart';
import '../models/health_snapshot.dart';
import '../services/health_score_service.dart';
import '../services/health_store.dart';
import '../theme.dart';
import '../widgets/health_charts.dart';
import '../widgets/ui_kit.dart';
import 'shell_screen.dart';

class SleepDetailScreen extends ConsumerStatefulWidget {
  /// Jour de départ (la nuit rattachée à ce jour civil). Par défaut aujourd'hui.
  final DateTime? initialDay;
  const SleepDetailScreen({super.key, this.initialDay});

  @override
  ConsumerState<SleepDetailScreen> createState() => _SleepDetailScreenState();
}

class _SleepDetailScreenState extends ConsumerState<SleepDetailScreen> {
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
    final baseline = rec == null ? const <DailyHealthRecord>[] : _baselineRecords();
    final insight = rec == null ? null : _nightInsight(rec, baseline);
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
                _physioCard(rec, baseline),
                if (insight != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _insightCard(insight),
                ],
                const SizedBox(height: AppSpacing.lg),
                _hypnogramCard(rec),
                const SizedBox(height: AppSpacing.lg),
                _stagesCard(rec.sleep),
                const SizedBox(height: AppSpacing.lg),
                _trendLinkCard(),
              ],
            ),
    );
  }

  /// Les nuits juste avant celle affichée (jusqu'à 7) — sert de référence
  /// pour les badges de comparaison de la carte physio. Recalculé à chaque
  /// navigation ← → puisque "avant" dépend de la nuit consultée, pas
  /// forcément d'aujourd'hui.
  List<DailyHealthRecord> _baselineRecords() {
    final from = _index + 1;
    if (from >= _nights.length) return const [];
    final to = (from + 7).clamp(0, _nights.length);
    return _nights.sublist(from, to);
  }

  double _avgOf(
      List<DailyHealthRecord> records, double Function(DailyHealthRecord) f) {
    final vals = records.map(f).where((v) => v > 0).toList();
    if (vals.isEmpty) return 0;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  double _restorativeRatio(DailyHealthRecord r) {
    final total = r.sleep.totalAsleepMin;
    if (total <= 0) return 0;
    return (r.sleep.deepMin + r.sleep.remMin) / total * 100;
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

  // ── Physio de cette nuit : FC moyenne, SpO2, respiration, ratio
  // réparateur — chacune avec un badge de comparaison aux 7 nuits
  // précédentes (repère ponctuel, pas un graphique). ────────────────────────
  Widget _physioCard(DailyHealthRecord rec, List<DailyHealthRecord> baseline) {
    final hrBaseline = _avgOf(baseline, (r) => r.avgHeartRate);
    final spo2Baseline = _avgOf(baseline, (r) => r.spo2);
    final respBaseline = _avgOf(baseline, (r) => r.respiratoryRate);
    final ratioBaseline = _avgOf(baseline, _restorativeRatio);
    final ratio = _restorativeRatio(rec);

    return AppPanel(
      accent: kNeonViolet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelTitle('PHYSIO DE CETTE NUIT', color: kNeonViolet),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _physioTile(
                  icon: Icons.favorite_rounded,
                  color: kNeonPink,
                  label: 'FC moyenne',
                  value: rec.avgHeartRate > 0 ? rec.avgHeartRate.round().toString() : '--',
                  unit: 'bpm',
                  delta: rec.avgHeartRate > 0
                      ? _deltaBadge(rec.avgHeartRate, hrBaseline, lowerIsBetter: true)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _physioTile(
                  icon: Icons.water_drop_rounded,
                  color: kNeonCyan,
                  label: 'SpO2',
                  value: rec.spo2 > 0 ? rec.spo2.round().toString() : '--',
                  unit: '%',
                  delta: rec.spo2 > 0
                      ? _deltaBadge(rec.spo2, spo2Baseline, lowerIsBetter: false, flatThreshold: 1)
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _physioTile(
                  icon: Icons.air_rounded,
                  color: kNeonViolet,
                  label: 'Respiration',
                  value: rec.respiratoryRate > 0
                      ? rec.respiratoryRate.toStringAsFixed(1)
                      : '--',
                  unit: 'rpm',
                  delta: rec.respiratoryRate > 0
                      ? _deltaBadge(rec.respiratoryRate, respBaseline,
                          lowerIsBetter: true, flatThreshold: 0.5)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _physioTile(
                  icon: Icons.check_circle_rounded,
                  color: kNeonGreen,
                  label: 'Sommeil réparateur',
                  value: ratio > 0 ? ratio.round().toString() : '--',
                  unit: '%',
                  delta: ratio > 0
                      ? _deltaBadge(ratio, ratioBaseline, lowerIsBetter: false, flatThreshold: 2)
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Sommeil réparateur = (profond + paradoxal) / temps total — c\'est ce '
            'ratio qui pèse le plus dans le score de sommeil.',
            style: TextStyle(color: AppColors.muted, fontSize: 10.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _physioTile({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required String unit,
    required Widget? delta,
  }) {
    final noData = value == '--';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: noData ? AppColors.muted : color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: TextStyle(
                      fontFamily: kArcadeFont,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: noData ? AppColors.muted : Colors.white)),
              const SizedBox(width: 4),
              Text(unit, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
            ],
          ),
          if (delta != null) ...[
            const SizedBox(height: 6),
            delta,
          ],
        ],
      ),
    );
  }

  /// Badge de comparaison à la moyenne des nuits précédentes — direction de
  /// la flèche selon le signe réel de l'écart, couleur selon si cet écart
  /// est favorable pour CETTE métrique (ex. FC en baisse = bon, SpO2 en
  /// hausse = bon). Neutre si pas encore assez d'historique ou écart minime.
  Widget _deltaBadge(
    double current,
    double baseline, {
    required bool lowerIsBetter,
    double flatThreshold = 1,
  }) {
    if (baseline <= 0) {
      return const Text('pas encore de référence',
          style: TextStyle(color: AppColors.muted, fontSize: 9.5));
    }
    final delta = current - baseline;
    if (delta.abs() < flatThreshold) {
      return const _DeltaChip(label: '= vs 7 nuits', color: AppColors.muted, icon: null);
    }
    final good = lowerIsBetter ? delta < 0 : delta > 0;
    final sign = delta > 0 ? '+' : '';
    final label =
        '$sign${delta.abs() < 10 ? delta.toStringAsFixed(1) : delta.round()} vs 7 nuits';
    return _DeltaChip(
      label: label,
      color: good ? kNeonGreen : kNeonPink,
      icon: delta > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
    );
  }

  /// Recommandation basée sur CETTE nuit précisément (pas les insights
  /// génériques déjà affichés dans Santé) — quelques règles simples, pas
  /// besoin de plus pour commencer.
  HealthInsight? _nightInsight(DailyHealthRecord rec, List<DailyHealthRecord> baseline) {
    if (rec.totalSleepMin > 0 && rec.totalSleepMin < 360) {
      return const HealthInsight(
        'night_short',
        'Nuit courte (moins de 6h) — essaie de te coucher plus tôt ce soir.',
        kNeonPink,
        Icons.bedtime_rounded,
      );
    }
    if (rec.sleep.awakeMin > 45) {
      return const HealthInsight(
        'night_awake',
        'Beaucoup de réveils cette nuit — regarde si un facteur extérieur '
            '(bruit, lumière, chaleur) peut expliquer ça.',
        kNeonAmber,
        Icons.visibility_rounded,
      );
    }
    final hrBaseline = _avgOf(baseline, (r) => r.avgHeartRate);
    final ratioBaseline = _avgOf(baseline, _restorativeRatio);
    final hrDelta =
        rec.avgHeartRate > 0 && hrBaseline > 0 ? rec.avgHeartRate - hrBaseline : 0.0;
    final ratioDelta = ratioBaseline > 0 ? _restorativeRatio(rec) - ratioBaseline : 0.0;
    if (hrBaseline > 0 && hrDelta > 4) {
      return HealthInsight(
        'night_hr_high',
        'FC nocturne plus haute que d\'habitude (+${hrDelta.round()} bpm) — '
            'stress, alcool ou repas tardif peuvent jouer.',
        kNeonPink,
        Icons.favorite_rounded,
      );
    }
    if (hrDelta < -2 && ratioDelta > 3) {
      return const HealthInsight(
        'night_good',
        'Bonne nuit de récupération — FC nocturne en baisse et sommeil '
            'réparateur en hausse. Garde cette routine de coucher.',
        kNeonGreen,
        Icons.bolt_rounded,
      );
    }
    return null;
  }

  Widget _insightCard(HealthInsight insight) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: insight.color, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: insight.color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(insight.icon, size: 15, color: insight.color),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(insight.text,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 12.5, height: 1.4)),
          ),
        ],
      ),
    );
  }

  // ── Lien vers les tendances (Santé) — remplace l'ancienne carte "14
  // derniers jours" : ce n'était pas de la donnée "cette nuit", et Santé
  // affiche déjà le score de sommeil sur 30 jours + la superposition
  // personnalisable (HRV × sommeil, etc.). ──────────────────────────────────
  Widget _trendLinkCard() {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).popUntil((route) => route.isFirst);
        ref.read(shellIndexProvider.notifier).state = 1;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, style: BorderStyle.solid),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: kNeonCyan.withOpacity(0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.show_chart_rounded, size: 16, color: kNeonCyan),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tendances & croisements',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                  SizedBox(height: 2),
                  Text('Sommeil sur plusieurs jours, HRV, dette de sommeil → Santé',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 10.5)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: kNeonCyan, size: 20),
          ],
        ),
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const _DeltaChip({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
          ],
          Text(label,
              style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
