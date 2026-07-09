import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/daily_health_record.dart';
import '../models/vo2_estimate.dart';
import '../services/health_store.dart';
import '../services/vo2_estimate_store.dart';
import '../services/vo2_estimator_service.dart';
import '../theme.dart';
import '../widgets/health_charts.dart';

class HealthMetricDetailScreen extends StatefulWidget {
  final HealthMetric metric;
  final Color accent;
  const HealthMetricDetailScreen({
    super.key,
    required this.metric,
    required this.accent,
  });

  @override
  State<HealthMetricDetailScreen> createState() =>
      _HealthMetricDetailScreenState();
}

class _HealthMetricDetailScreenState extends State<HealthMetricDetailScreen> {
  int _range = 7;

  @override
  Widget build(BuildContext context) {
    final meta = _metaFor(widget.metric);
    // VO2 max : source locale (régression FC/allure), pas Health Connect —
    // HealthStore n'a jamais de série pour cette métrique dans notre cas.
    final isVo2Max = widget.metric == HealthMetric.vo2Max;
    final vo2Estimates = isVo2Max ? Vo2EstimateStore.all() : const <Vo2Estimate>[];
    final cutoff = DateTime.now().subtract(Duration(days: _range));
    final series = isVo2Max
        ? [
            for (final e in vo2Estimates)
              if (e.date.isAfter(cutoff)) MapEntry(e.date, e.value)
          ]
        : HealthStore.series(widget.metric, _range)
            .where((e) => e.value > 0)
            .toList();
    final values = series.map((e) => e.value).toList();
    final dates = series.map((e) => e.key).toList();
    final baseline = isVo2Max
        ? (values.length > 1
            ? values.sublist(0, values.length - 1).reduce((a, b) => a + b) /
                (values.length - 1)
            : 0.0)
        : HealthStore.baseline(widget.metric, window: _range);

    final hasData = values.isNotEmpty;
    final current = hasData ? values.last : 0.0;
    final minV = hasData ? values.reduce(math.min) : 0.0;
    final maxV = hasData ? values.reduce(math.max) : 0.0;
    final avgV =
        hasData ? values.reduce((a, b) => a + b) / values.length : 0.0;
    final vo2Confidence = isVo2Max && vo2Estimates.isNotEmpty
        ? Vo2EstimatorService.confidenceFor(vo2Estimates.last)
        : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(
          meta.title.toUpperCase(),
          style: TextStyle(
            fontFamily: kArcadeFont,
            color: widget.accent,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            shadows: [Shadow(color: widget.accent, blurRadius: 10)],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Valeur courante
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                hasData ? meta.format(current) : '--',
                style: TextStyle(
                  fontFamily: kArcadeFont,
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  shadows: [Shadow(color: widget.accent, blurRadius: 12)],
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(meta.unit,
                    style: TextStyle(
                        color: widget.accent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
              if (vo2Confidence?.isProvisional == true) ...[
                const SizedBox(width: 8),
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: ProvisionalBadge(),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            vo2Confidence?.caption ?? 'valeur du jour',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 20),

          // Sélecteur de plage
          _RangeSelector(
            range: _range,
            accent: widget.accent,
            onChanged: (r) => setState(() => _range = r),
          ),
          const SizedBox(height: 16),

          // Graphique
          _Panel(
            accent: widget.accent,
            child: values.length >= 2
                ? TrendChart(
                    values: values,
                    color: widget.accent,
                    baseline: baseline > 0 ? baseline : null,
                    height: 200,
                    dates: dates,
                    unit: meta.unit,
                    fractionDigits: meta.fractionDigits,
                    zone: meta.zone,
                  )
                : _SparseState(
                    value: hasData ? meta.format(current) : null,
                    unit: meta.unit,
                    accent: widget.accent,
                    days: values.length,
                    customMessage: isVo2Max && hasData
                        ? 'Ce chiffre est déjà basé sur tes courses des 90 '
                            'derniers jours. Cette courbe suit son évolution '
                            'jour après jour — elle s\'enrichira à chaque '
                            'nouvelle journée où l\'app recalcule l\'estimation.'
                        : null,
                  ),
          ),
          const SizedBox(height: 16),

          // Stats min / moy / max
          Row(
            children: [
              Expanded(
                  child: _StatBox(
                      'MIN', hasData ? meta.format(minV) : '--', widget.accent)),
              const SizedBox(width: 10),
              Expanded(
                  child: _StatBox(
                      'MOY', hasData ? meta.format(avgV) : '--', widget.accent)),
              const SizedBox(width: 10),
              Expanded(
                  child: _StatBox(
                      'MAX', hasData ? meta.format(maxV) : '--', widget.accent)),
            ],
          ),
          const SizedBox(height: 16),

          // Transparence du calcul
          _Panel(
            accent: widget.accent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meta.explainTitle,
                  style: TextStyle(
                    fontFamily: kArcadeFont,
                    color: widget.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 10),
                Text(meta.explain,
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Affichage quand on n'a pas encore assez de jours pour une courbe.
class _SparseState extends StatelessWidget {
  final String? value;
  final String unit;
  final Color accent;
  final int days;
  /// Remplace le message par défaut ("X jour(s) enregistré(s), reviens
  /// demain") — utilisé pour le VO2 max, où le chiffre affiché est déjà
  /// basé sur un vrai historique de courses même si la courbe (jour après
  /// jour) n'a pas encore plusieurs points ; le message générique donnerait
  /// l'impression trompeuse qu'il n'y a presque aucune donnée.
  final String? customMessage;
  const _SparseState(
      {required this.value,
      required this.unit,
      required this.accent,
      required this.days,
      this.customMessage});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (value != null) ...[
            Icon(Icons.show_chart_rounded,
                color: accent.withOpacity(0.5), size: 32),
            const SizedBox(height: 10),
            if (customMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  customMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12, height: 1.4),
                ),
              )
            else ...[
              Text(
                days <= 1
                    ? '1 jour enregistré'
                    : '$days jours enregistrés',
                style: TextStyle(
                    fontFamily: kArcadeFont,
                    color: accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              const Text(
                'La courbe se construit chaque jour.\nReviens demain pour voir la tendance.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ] else
            const Text('Aucune donnée pour cette métrique.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _RangeSelector extends StatelessWidget {
  final int range;
  final Color accent;
  final ValueChanged<int> onChanged;
  const _RangeSelector(
      {required this.range, required this.accent, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(int r, String label) {
      final active = r == range;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(r),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active ? accent.withOpacity(0.18) : AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: active ? accent : AppColors.border, width: 1.2),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: kArcadeFont,
                color: active ? accent : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(7, '7 J'),
        chip(30, '30 J'),
        chip(90, '90 J'),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  const _StatBox(this.label, this.value, this.accent);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontFamily: kArcadeFont,
                  color: accent,
                  fontSize: 16,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  final Color accent;
  const _Panel({required this.child, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.4), width: 1.2),
      ),
      child: child,
    );
  }
}

// ── Métadonnées d'affichage par métrique ──────────────────────────────────────
class _MetricMeta {
  final String title;
  final String unit;
  final int fractionDigits;
  final String explainTitle;
  final String explain;
  final ChartZone? zone;
  const _MetricMeta({
    required this.title,
    required this.unit,
    required this.fractionDigits,
    required this.explainTitle,
    required this.explain,
    this.zone,
  });

  String format(double v) => v.toStringAsFixed(fractionDigits);
}

_MetricMeta _metaFor(HealthMetric m) {
  switch (m) {
    case HealthMetric.bioScore:
      return const _MetricMeta(
          title: 'Bio-Score',
          unit: '/100',
          fractionDigits: 0,
          explainTitle: 'COMMENT C\'EST CALCULÉ',
          explain:
              'Le Bio-Score combine 35% sommeil, 35% récupération et 30% activité. '
              'C\'est notre indicateur maison de forme globale du jour — aucune donnée '
              'propriétaire Fitbit requise.');
    case HealthMetric.sleepScore:
      return const _MetricMeta(
          title: 'Score Sommeil',
          unit: '/100',
          fractionDigits: 0,
          explainTitle: 'COMMENT C\'EST CALCULÉ',
          explain:
              'Basé sur la durée (cible 8 h), la répartition des phases (idéal ~20% '
              'profond, ~25% paradoxal) et l\'efficacité (temps endormi / temps au lit).');
    case HealthMetric.recoveryScore:
      return const _MetricMeta(
          title: 'Score Récupération',
          unit: '/100',
          fractionDigits: 0,
          explainTitle: 'COMMENT C\'EST CALCULÉ',
          explain:
              'Compare ta FC au repos et ta variabilité cardiaque (HRV) du jour à ta '
              'moyenne des 7 derniers jours. FC repos basse + HRV haute = bonne récup.');
    case HealthMetric.activityScore:
      return const _MetricMeta(
          title: 'Score Activité',
          unit: '/100',
          fractionDigits: 0,
          explainTitle: 'COMMENT C\'EST CALCULÉ',
          explain:
              'Pondère les pas (objectif 10k), les calories actives (500 kcal) et les '
              'étages montés (10). Reflète ton niveau de mouvement du jour.');
    case HealthMetric.steps:
      return const _MetricMeta(
          title: 'Pas',
          unit: 'pas',
          fractionDigits: 0,
          explainTitle: 'À PROPOS',
          explain: 'Nombre de pas cumulés sur la journée, lu depuis Health Connect. '
              'Objectif quotidien : 10 000 pas (rapporte de l\'XP santé).');
    case HealthMetric.activeCalories:
      return const _MetricMeta(
          title: 'Calories actives',
          unit: 'kcal',
          fractionDigits: 0,
          explainTitle: 'À PROPOS',
          explain: 'Énergie dépensée par l\'activité physique (hors métabolisme de '
              'base). Objectif quotidien : 500 kcal.');
    case HealthMetric.restingHeartRate:
      return const _MetricMeta(
          title: 'FC au repos',
          unit: 'bpm',
          fractionDigits: 0,
          explainTitle: 'À PROPOS',
          explain: 'Fréquence cardiaque au repos. Plus elle est basse et stable, '
              'meilleure est généralement ta condition et ta récupération.');
    case HealthMetric.hrv:
      return const _MetricMeta(
          title: 'Variabilité cardiaque',
          unit: 'ms',
          fractionDigits: 0,
          explainTitle: 'À PROPOS',
          explain: 'La HRV (RMSSD) mesure la variation entre battements. Une HRV plus '
              'élevée que ta moyenne indique un système nerveux bien récupéré.');
    case HealthMetric.spo2:
      return const _MetricMeta(
          title: 'Saturation O2',
          unit: '%',
          fractionDigits: 0,
          explainTitle: 'À PROPOS',
          explain: 'Taux d\'oxygène dans le sang mesuré pendant le sommeil. '
              'Une valeur saine se situe généralement entre 95 et 100%.',
          zone: ChartZone(
              min: 95, max: 100, color: kNeonGreen, label: 'Plage saine 95-100%'));
    case HealthMetric.respiratoryRate:
      return const _MetricMeta(
          title: 'Fréquence respiratoire',
          unit: 'rpm',
          fractionDigits: 1,
          explainTitle: 'À PROPOS',
          explain: 'Respirations par minute pendant le sommeil. Une valeur stable '
              'nuit après nuit est un bon signe ; une hausse peut signaler de la fatigue.',
          zone: ChartZone(
              min: 12,
              max: 20,
              color: kNeonGreen,
              label: 'Plage saine 12-20 rpm au repos'));
    case HealthMetric.sleepHours:
      return const _MetricMeta(
          title: 'Durée de sommeil',
          unit: 'h',
          fractionDigits: 1,
          explainTitle: 'À PROPOS',
          explain: 'Total de sommeil (profond + léger + paradoxal). Cible : 7-8 h '
              'pour une récupération optimale.');
    case HealthMetric.distanceKm:
      return const _MetricMeta(
          title: 'Distance',
          unit: 'km',
          fractionDigits: 2,
          explainTitle: 'À PROPOS',
          explain: 'Distance totale parcourue sur la journée (marche + course), '
              'lue depuis Health Connect.');
    case HealthMetric.flightsClimbed:
      return const _MetricMeta(
          title: 'Étages montés',
          unit: 'étages',
          fractionDigits: 0,
          explainTitle: 'À PROPOS',
          explain: 'Nombre d\'étages gravis dans la journée. Contribue au score '
              'd\'activité et sollicite le système cardio.');
    case HealthMetric.vo2Max:
      return const _MetricMeta(
          title: 'VO2 max',
          unit: 'ml/kg/min',
          fractionDigits: 1,
          explainTitle: 'À PROPOS',
          explain: 'Volume maximal d\'oxygène que ton corps peut utiliser à '
              'l\'effort — un des meilleurs indicateurs de ta condition '
              'cardiovasculaire. Estimé localement par régression FC/allure '
              'sur tes courses avec FC (pas une mesure directe de la montre) '
              '— voir Sport pour le détail du calcul.');
    case HealthMetric.weightKg:
      return const _MetricMeta(
          title: 'Poids',
          unit: 'kg',
          fractionDigits: 1,
          explainTitle: 'À PROPOS',
          explain: 'Dernier relevé connu, lu depuis Health Connect (balance '
              'connectée). Se met à jour seulement les jours où tu te pèses — '
              'les autres jours reprennent la dernière valeur connue.');
  }
}
