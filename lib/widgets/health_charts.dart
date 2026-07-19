// lib/widgets/health_charts.dart
// Graphiques santé peints à la main (CustomPaint), style néon/CRT cohérent
// avec le reste de l'app. Aucune dépendance externe.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/health_snapshot.dart';
import '../services/health_score_service.dart' show TrendDir;
import '../services/vo2_estimator_service.dart' show Vo2Category;
import '../theme.dart';
import 'arcade_fx.dart';

/// Petite flèche colorée ↑/↓/→ reflétant une tendance.
/// [good] indique si la direction est favorable (vert) ou non (rose).
class TrendArrow extends StatelessWidget {
  final TrendDir dir;
  final bool good;
  final String? label;
  const TrendArrow({super.key, required this.dir, this.good = true, this.label});

  @override
  Widget build(BuildContext context) {
    final icon = switch (dir) {
      TrendDir.up => Icons.trending_up_rounded,
      TrendDir.down => Icons.trending_down_rounded,
      TrendDir.flat => Icons.trending_flat_rounded,
    };
    final color = dir == TrendDir.flat
        ? AppColors.textSecondary
        : (good ? kNeonGreen : kNeonPink);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        if (label != null) ...[
          const SizedBox(width: 3),
          Text(label!,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ],
    );
  }
}

/// Petit badge "PROVISOIRE" — pour une valeur calculée mais qui n'a pas
/// encore assez de données pour être pleinement fiable (ex. VO2 max estimé
/// avec peu de courses). Jamais un chiffre nu sans ce genre de contexte.
class ProvisionalBadge extends StatelessWidget {
  const ProvisionalBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: kNeonAmber.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kNeonAmber.withOpacity(0.5)),
      ),
      child: const Text(
        'PROVISOIRE',
        style: TextStyle(
          color: kNeonAmber,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Badge coloré affichant la catégorie fitness (Faible → Élite) d'une
/// estimation de VO2 max, comparée à des tables de référence par âge/sexe —
/// voir `Vo2EstimatorService.categoryFor`. Partagé entre la carte du hub
/// Sport et l'écran de détail santé.
class Vo2CategoryBadge extends StatelessWidget {
  final Vo2Category category;
  const Vo2CategoryBadge({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: category.color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: category.color.withOpacity(0.5)),
      ),
      child: Text(
        category.label.toUpperCase(),
        style: TextStyle(
          color: category.color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Mini-courbe sans axes, pour les cartes. Anime le tracé au premier rendu.
class Sparkline extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double height;
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.height = 34,
  });

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return SizedBox(height: height);
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => CustomPaint(
          painter: _SparklinePainter(values: values, color: color, progress: t),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double progress;
  _SparklinePainter(
      {required this.values, required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final range = (maxV - minV).abs() < 1e-6 ? 1.0 : (maxV - minV);

    Offset pointAt(int i) {
      final x = size.width * (i / (values.length - 1));
      final norm = (values[i] - minV) / range;
      final y = size.height - norm * size.height * 0.9 - size.height * 0.05;
      return Offset(x, y);
    }

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final p = pointAt(i);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }

    // Remplissage dégradé sous la courbe
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.30 * progress), color.withOpacity(0)],
        ).createShader(Offset.zero & size),
    );

    // Ligne
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withOpacity(progress)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Point terminal
    final last = pointAt(values.length - 1);
    canvas.drawCircle(last, 3 * progress, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.progress != progress || old.values != values || old.color != color;
}

/// Bande de référence médicalement établie (ex. SpO2 saine 95-100%), dessinée
/// en fond du graphique. On ne l'utilise que pour des plages consensuelles et
/// non ambiguës (jamais pour FC repos/HRV/VO2 max, trop individuelles pour
/// qu'une bande unique soit honnête) — la donnée réelle reste toujours au
/// premier plan, la bande n'est qu'un repère visuel supplémentaire.
class ChartZone {
  final double min;
  final double max;
  final Color color;
  final String label;
  const ChartZone(
      {required this.min, required this.max, required this.color, required this.label});
}

/// Courbe complète avec axes légers, ligne de baseline et étiquettes min/max.
/// Utilisée dans l'écran de détail.
class TrendChart extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double? baseline;
  final double height;
  final List<DateTime>? dates;
  final String unit;
  final int fractionDigits;
  final ChartZone? zone;
  /// Formateur de l'axe X (dates de début/fin) — par défaut "jj/mm", mais une
  /// période intra-journée (ex. le déroulé d'une course) veut plutôt "hh:mm".
  final String Function(DateTime)? xLabelFormatter;
  const TrendChart({
    super.key,
    required this.values,
    required this.color,
    this.baseline,
    this.height = 200,
    this.dates,
    this.unit = '',
    this.fractionDigits = 0,
    this.zone,
    this.xLabelFormatter,
  });

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text('Pas assez de données pour tracer une courbe.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ),
      );
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => CustomPaint(
          painter: _TrendPainter(
            values: values,
            color: color,
            baseline: baseline,
            progress: t,
            dates: dates,
            unit: unit,
            fractionDigits: fractionDigits,
            zone: zone,
            xLabelFormatter: xLabelFormatter,
          ),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double? baseline;
  final double progress;
  final List<DateTime>? dates;
  final String unit;
  final int fractionDigits;
  final ChartZone? zone;
  final String Function(DateTime)? xLabelFormatter;
  _TrendPainter({
    required this.values,
    required this.color,
    required this.baseline,
    required this.progress,
    this.dates,
    this.unit = '',
    this.fractionDigits = 0,
    this.zone,
    this.xLabelFormatter,
  });

  static String _shortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  String _xLabel(DateTime d) => (xLabelFormatter ?? _shortDate)(d);

  void _drawLabel(Canvas canvas, String text, Offset anchor,
      {required bool alignRight,
      required bool alignTop,
      bool centerVertical = false}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = alignRight ? anchor.dx - painter.width : anchor.dx;
    final dy = centerVertical
        ? anchor.dy - painter.height / 2
        : (alignTop ? anchor.dy : anchor.dy - painter.height);
    painter.paint(canvas, Offset(dx, dy));
  }

  double _labelWidth(String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  /// Graduations "rondes" (pas en 1/2/5 × 10ⁿ) façon logiciel de graphique,
  /// pour une échelle lisible plutôt que juste les deux bornes brutes.
  List<double> _niceTicks(double minV, double maxV, int target) {
    if ((maxV - minV).abs() < 1e-9) return [minV];
    final rawStep = (maxV - minV) / target;
    final mag = math.pow(10, (math.log(rawStep) / math.ln10).floor()).toDouble();
    final residual = rawStep / mag;
    final double niceStep = residual > 5
        ? 10 * mag
        : residual > 2
            ? 5 * mag
            : residual > 1
                ? 2 * mag
                : mag;
    final niceMin = (minV / niceStep).floor() * niceStep;
    final niceMax = (maxV / niceStep).ceil() * niceStep;
    final ticks = <double>[];
    for (double v = niceMin; v <= niceMax + niceStep * 0.5; v += niceStep) {
      ticks.add(v);
    }
    return ticks;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 4.0;
    const topPad = 14.0;
    // Marge basse agrandie pour laisser la place aux dates de l'axe X.
    final bottomPad = (dates != null && dates!.length >= 2) ? 28.0 : 14.0;

    double rawMin = values.reduce(math.min);
    double rawMax = values.reduce(math.max);
    if (baseline != null) {
      rawMin = math.min(rawMin, baseline!);
      rawMax = math.max(rawMax, baseline!);
    }
    // La bande de référence doit toujours être entièrement visible, même si
    // les valeurs du jour sont loin d'elle — sinon on perdrait justement le
    // repère qui permet de voir "à quel point" on s'en écarte.
    final z = zone;
    if (z != null) {
      rawMin = math.min(rawMin, z.min);
      rawMax = math.max(rawMax, z.max);
    }

    // Échelle graduée à valeurs rondes (façon logiciel de graphique) plutôt
    // que juste les deux bornes brutes — chaque ligne de grille porte son
    // propre chiffre.
    final ticks = _niceTicks(rawMin, rawMax, 4);
    final tickLabels =
        ticks.map((v) => '${v.toStringAsFixed(fractionDigits)}$unit').toList();
    final minV = ticks.first;
    final maxV = ticks.last;
    final range = (maxV - minV).abs() < 1e-6 ? 1.0 : (maxV - minV);

    // Marge droite dédiée aux graduations, dimensionnée sur le libellé le
    // plus large — les valeurs ne se superposent plus à la courbe.
    final rightPad =
        tickLabels.map(_labelWidth).reduce(math.max) + 10.0;
    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;

    double yFor(double v) =>
        topPad + chartH - ((v - minV) / range) * chartH;
    double xFor(int i) => leftPad + chartW * (i / (values.length - 1));

    // Bande de référence (dessinée avant tout le reste, en fond).
    if (z != null) {
      final zTop = yFor(z.max).clamp(topPad, topPad + chartH);
      final zBottom = yFor(z.min).clamp(topPad, topPad + chartH);
      canvas.drawRect(
        Rect.fromLTRB(leftPad, zTop, leftPad + chartW, zBottom),
        Paint()..color = z.color.withOpacity(0.12),
      );
      _drawLabel(canvas, z.label, Offset(leftPad, zTop + 1),
          alignRight: false, alignTop: true);
    }

    // Grille horizontale graduée : une ligne + un chiffre par palier rond.
    final gridPaint = Paint()
      ..color = AppColors.border.withOpacity(0.4)
      ..strokeWidth = 1;
    for (int i = 0; i < ticks.length; i++) {
      final y = yFor(ticks[i]);
      canvas.drawLine(
          Offset(leftPad, y), Offset(leftPad + chartW, y), gridPaint);
      _drawLabel(canvas, tickLabels[i], Offset(leftPad + chartW + 6, y),
          alignRight: false, alignTop: false, centerVertical: true);
    }

    // Légende axe X : dates de début/fin de la période affichée.
    final ds = dates;
    if (ds != null && ds.length >= 2) {
      final dateY = topPad + chartH + 14;
      _drawLabel(canvas, _xLabel(ds.first), Offset(leftPad, dateY),
          alignRight: false, alignTop: true);
      _drawLabel(canvas, _xLabel(ds.last), Offset(size.width - rightPad, dateY),
          alignRight: true, alignTop: true);
    }

    // Ligne de baseline (pointillés)
    if (baseline != null) {
      final by = yFor(baseline!);
      final dashPaint = Paint()
        ..color = AppColors.textSecondary.withOpacity(0.7)
        ..strokeWidth = 1.2;
      const dashW = 6.0;
      for (double x = leftPad; x < size.width - rightPad; x += dashW * 2) {
        canvas.drawLine(Offset(x, by), Offset(x + dashW, by), dashPaint);
      }
    }

    // Courbe (animée : on ne trace que jusqu'à progress)
    final count = values.length;
    final drawnCount = (count * progress).clamp(2, count).toInt();
    final path = Path();
    for (int i = 0; i < drawnCount; i++) {
      final p = Offset(xFor(i), yFor(values[i]));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }

    final fill = Path.from(path)
      ..lineTo(xFor(drawnCount - 1), topPad + chartH)
      ..lineTo(leftPad, topPad + chartH)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.25), color.withOpacity(0)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6),
    );

    // Point terminal lumineux
    if (drawnCount > 0) {
      final last = Offset(xFor(drawnCount - 1), yFor(values[drawnCount - 1]));
      canvas.drawCircle(last, 5, Paint()..color = color.withOpacity(0.25));
      canvas.drawCircle(last, 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.progress != progress ||
      old.values != values ||
      old.baseline != baseline ||
      old.color != color;
}

/// Superpose deux séries sur le même axe temporel, chacune normalisée
/// indépendamment sur sa propre échelle (0-1) — permet de croiser deux
/// métriques d'unités différentes visuellement, sans prétendre à une
/// comparaison quantitative exacte entre elles.
class OverlayTrendChart extends StatelessWidget {
  final List<double> valuesA;
  final List<double> valuesB;
  final Color colorA;
  final Color colorB;
  final double height;
  final List<DateTime>? dates;
  const OverlayTrendChart({
    super.key,
    required this.valuesA,
    required this.valuesB,
    required this.colorA,
    required this.colorB,
    this.height = 180,
    this.dates,
  });

  @override
  Widget build(BuildContext context) {
    if (valuesA.length < 2 || valuesB.length < 2) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text('Pas assez de données pour croiser ces courbes.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ),
      );
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => CustomPaint(
          painter: _OverlayTrendPainter(
            valuesA: valuesA,
            valuesB: valuesB,
            colorA: colorA,
            colorB: colorB,
            progress: t,
            dates: dates,
          ),
        ),
      ),
    );
  }
}

class _OverlayTrendPainter extends CustomPainter {
  final List<double> valuesA;
  final List<double> valuesB;
  final Color colorA;
  final Color colorB;
  final double progress;
  final List<DateTime>? dates;
  _OverlayTrendPainter({
    required this.valuesA,
    required this.valuesB,
    required this.colorA,
    required this.colorB,
    required this.progress,
    this.dates,
  });

  static String _shortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  void _drawLabel(Canvas canvas, String text, Offset anchor,
      {required bool alignRight, required bool alignTop}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = alignRight ? anchor.dx - painter.width : anchor.dx;
    final dy = alignTop ? anchor.dy : anchor.dy - painter.height;
    painter.paint(canvas, Offset(dx, dy));
  }

  List<Offset> _normalizedPoints(
      List<double> values, double chartW, double chartH, double leftPad, double topPad) {
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final range = (maxV - minV).abs() < 1e-6 ? 1.0 : (maxV - minV);
    return List.generate(values.length, (i) {
      final x = leftPad + chartW * (i / (values.length - 1));
      final norm = (values[i] - minV) / range;
      final y = topPad + chartH - norm * chartH;
      return Offset(x, y);
    });
  }

  void _drawSeries(Canvas canvas, List<Offset> pts, Color color) {
    final count = pts.length;
    final drawnCount = (count * progress).clamp(2, count).toInt();
    final path = Path();
    for (int i = 0; i < drawnCount; i++) {
      if (i == 0) {
        path.moveTo(pts[i].dx, pts[i].dy);
      } else {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    if (drawnCount > 0) {
      final last = pts[drawnCount - 1];
      canvas.drawCircle(last, 5, Paint()..color = color.withOpacity(0.25));
      canvas.drawCircle(last, 3, Paint()..color = color);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 4.0;
    const topPad = 10.0;
    final bottomPad = (dates != null && dates!.length >= 2) ? 26.0 : 10.0;
    final chartW = size.width - leftPad - 4;
    final chartH = size.height - topPad - bottomPad;

    final ptsA = _normalizedPoints(valuesA, chartW, chartH, leftPad, topPad);
    final ptsB = _normalizedPoints(valuesB, chartW, chartH, leftPad, topPad);

    // Grille horizontale légère : pas de graduation chiffrée puisque les
    // deux courbes n'ont pas la même échelle réelle, juste un repère visuel.
    final gridPaint = Paint()
      ..color = AppColors.border.withOpacity(0.3)
      ..strokeWidth = 1;
    for (int i = 0; i <= 3; i++) {
      final y = topPad + chartH * i / 3;
      canvas.drawLine(Offset(leftPad, y), Offset(leftPad + chartW, y), gridPaint);
    }

    final ds = dates;
    if (ds != null && ds.length >= 2) {
      final dateY = topPad + chartH + 14;
      _drawLabel(canvas, _shortDate(ds.first), Offset(leftPad, dateY),
          alignRight: false, alignTop: true);
      _drawLabel(canvas, _shortDate(ds.last), Offset(leftPad + chartW, dateY),
          alignRight: true, alignTop: true);
    }

    _drawSeries(canvas, ptsA, colorA);
    _drawSeries(canvas, ptsB, colorB);
  }

  @override
  bool shouldRepaint(covariant _OverlayTrendPainter old) =>
      old.progress != progress ||
      old.valuesA != valuesA ||
      old.valuesB != valuesB ||
      old.colorA != colorA ||
      old.colorB != colorB;
}

/// Hypnogramme : tracé chronologique des stades de sommeil sur la nuit.
/// 4 lanes (Éveil en haut → Profond en bas), chaque segment dessiné à sa
/// position temporelle réelle, avec des liaisons verticales entre stades.
/// Légende d'un stade de sommeil (pastille couleur + libellé + durée) —
/// utilisée sous `Hypnogram` pour détailler les minutes par stade.
class SleepLegend extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const SleepLegend(this.label, this.value, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$label $value',
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      ],
    );
  }
}

class Hypnogram extends StatelessWidget {
  final List<SleepSegment> segments;
  final double height;
  final bool showAxis;

  const Hypnogram({
    super.key,
    required this.segments,
    this.height = 130,
    this.showAxis = true,
  });

  String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text('Pas de détail des stades pour cette nuit.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ),
      );
    }
    final start = segments.map((s) => s.start).reduce((a, b) => a.isBefore(b) ? a : b);
    final end = segments.map((s) => s.end).reduce((a, b) => a.isAfter(b) ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) => CustomPaint(
              painter: _HypnogramPainter(
                segments: segments,
                start: start,
                end: end,
                progress: t,
              ),
            ),
          ),
        ),
        if (showAxis) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_hm(start),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
              Text(_hm(end),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
            ],
          ),
        ],
      ],
    );
  }
}

class _HypnogramPainter extends CustomPainter {
  final List<SleepSegment> segments;
  final DateTime start;
  final DateTime end;
  final double progress;

  _HypnogramPainter({
    required this.segments,
    required this.start,
    required this.end,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final totalMs = end.difference(start).inMilliseconds.toDouble();
    if (totalMs <= 0) return;

    const laneCount = 4; // awake, rem, light, deep
    final laneH = size.height / laneCount;
    final blockH = laneH * 0.55;

    double xFor(DateTime t) =>
        size.width * (t.difference(start).inMilliseconds / totalMs);
    double laneCenterY(int lane) => laneH * lane + laneH / 2;

    // Fond très léger de chaque lane pour la lisibilité.
    for (int lane = 0; lane < laneCount; lane++) {
      final cy = laneCenterY(lane);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, cy - blockH / 2, size.width, blockH),
          const Radius.circular(6),
        ),
        Paint()..color = AppColors.surfaceLight.withOpacity(0.35),
      );
    }

    // On ne dessine que jusqu'à progress (animation de gauche à droite).
    final drawUntilX = size.width * progress;

    // Liaisons verticales entre segments consécutifs.
    final linkPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 2;
    for (int i = 0; i < segments.length - 1; i++) {
      final a = segments[i];
      final b = segments[i + 1];
      final x = xFor(b.start);
      if (x > drawUntilX) break;
      final y1 = laneCenterY(a.stage.lane);
      final y2 = laneCenterY(b.stage.lane);
      canvas.drawLine(Offset(x, y1), Offset(x, y2), linkPaint);
    }

    // Blocs de stade.
    for (final seg in segments) {
      final x1 = xFor(seg.start);
      if (x1 > drawUntilX) break;
      var x2 = xFor(seg.end);
      x2 = math.min(x2, drawUntilX);
      final w = math.max(2.0, x2 - x1);
      final cy = laneCenterY(seg.stage.lane);
      final rect = Rect.fromLTWH(x1, cy - blockH / 2, w, blockH);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()
          ..color = seg.stage.color
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HypnogramPainter old) =>
      old.progress != progress || old.segments != segments;
}

/// Anneau de score animé (0-100) avec valeur au centre.
class HealthRing extends StatelessWidget {
  final int score;
  final Color color;
  final double size;
  final String? centerLabel;
  const HealthRing({
    super.key,
    required this.score,
    required this.color,
    this.size = 96,
    this.centerLabel,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: (score / 100).clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => CustomPaint(
          painter: _RingPainter(progress: v, color: color),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedCounter(
                  value: score.toDouble(),
                  style: TextStyle(
                    fontFamily: kArcadeFont,
                    color: color,
                    fontSize: size * 0.28,
                    fontWeight: FontWeight.w900,
                    shadows: [Shadow(color: color, blurRadius: 10)],
                  ),
                ),
                if (centerLabel != null)
                  Text(
                    centerLabel!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 6;
    const startAngle = -math.pi / 2;
    final stroke = size.width * 0.08;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AppColors.surfaceLight
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}

/// Un axe du radar (ex. Sommeil/Récup/Activité) — valeur sur 0-100.
class RadarAxis {
  final String label;
  final double value;
  final Color color;
  const RadarAxis(
      {required this.label, required this.value, required this.color});
}

/// Diagramme radar (toile d'araignée) : place chaque axe autour d'un cercle,
/// relie les valeurs en un polygone rempli — le déséquilibre entre axes se
/// voit d'un coup d'œil (un polygone tiré d'un côté), alors que les mêmes
/// valeurs en chiffres séparés ne le montrent pas. Fonctionne avec N axes,
/// mais pensé pour 3 (Sommeil/Récup/Activité).
class RadarChart extends StatelessWidget {
  final List<RadarAxis> axes;
  final double size;
  /// Polygone de référence plus pâle (ex. la semaine dernière), pour
  /// comparer deux périodes sur le même radar.
  final List<double>? compareValues;
  const RadarChart(
      {super.key, required this.axes, this.size = 220, this.compareValues});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => CustomPaint(
          painter: _RadarPainter(
              axes: axes, progress: t, compareValues: compareValues),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final List<RadarAxis> axes;
  final double progress;
  final List<double>? compareValues;
  _RadarPainter(
      {required this.axes, required this.progress, this.compareValues});

  List<Offset> _vertices(Offset center, double radius, List<double> values) {
    final n = axes.length;
    return List.generate(n, (i) {
      final angle = -math.pi / 2 + (2 * math.pi * i / n);
      final r = radius * (values[i] / 100).clamp(0.0, 1.0) * progress;
      return Offset(center.dx + r * math.cos(angle), center.dy + r * math.sin(angle));
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 6);
    final radius = math.min(size.width, size.height) / 2 - 34;
    final n = axes.length;

    final gridPaint = Paint()
      ..color = AppColors.border.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Anneaux de grille à 50% et 100%.
    for (final frac in [0.5, 1.0]) {
      final path = Path();
      for (int i = 0; i < n; i++) {
        final angle = -math.pi / 2 + (2 * math.pi * i / n);
        final p = Offset(center.dx + radius * frac * math.cos(angle),
            center.dy + radius * frac * math.sin(angle));
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    // Axes (centre → sommet).
    for (int i = 0; i < n; i++) {
      final angle = -math.pi / 2 + (2 * math.pi * i / n);
      final p = Offset(
          center.dx + radius * math.cos(angle), center.dy + radius * math.sin(angle));
      canvas.drawLine(center, p, gridPaint);
    }

    // Polygone de comparaison (référence pâle), s'il y en a un.
    final cmp = compareValues;
    if (cmp != null && cmp.length == n) {
      final pts = _vertices(center, radius, cmp);
      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(
          path,
          Paint()
            ..color = AppColors.textSecondary.withOpacity(0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }

    // Polygone de données.
    final values = axes.map((a) => a.value).toList();
    final pts = _vertices(center, radius, values);
    final dataPath = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (final p in pts.skip(1)) {
      dataPath.lineTo(p.dx, p.dy);
    }
    dataPath.close();
    canvas.drawPath(dataPath, Paint()..color = kNeonCyan.withOpacity(0.20 * progress));
    canvas.drawPath(
        dataPath,
        Paint()
          ..color = kNeonCyan.withOpacity(progress)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeJoin = StrokeJoin.round);

    // Points colorés + libellés par axe.
    for (int i = 0; i < n; i++) {
      canvas.drawCircle(pts[i], 4, Paint()..color = axes[i].color.withOpacity(progress));
      final angle = -math.pi / 2 + (2 * math.pi * i / n);
      final labelAnchor = Offset(center.dx + (radius + 20) * math.cos(angle),
          center.dy + (radius + 20) * math.sin(angle));
      final text =
          '${axes[i].label.toUpperCase()} ${axes[i].value.round()}';
      final painter = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
                color: axes[i].color,
                fontSize: 10.5,
                fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: 90);
      canvas.save();
      canvas.translate(labelAnchor.dx - painter.width / 2, labelAnchor.dy - painter.height / 2);
      painter.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.progress != progress || old.axes != axes;
}

/// Courbe à bandes de zones colorées (ex. sous tension / normale / élevée) où
/// la ligne elle-même change de couleur selon la zone du point — contrairement
/// à `TrendChart` + `ChartZone` qui garde une ligne monochrome sur fond de
/// bande. Pensée pour les métriques "état" (HRV, VFC normalisée) où ce qui
/// compte est "dans quelle zone suis-je", pas juste "la valeur a monté".
class ZoneTrendChart extends StatelessWidget {
  final List<double> values;
  final List<ChartZone> zones; // couvrant tout l'axe Y, triées min → max
  final double height;
  final List<DateTime>? dates;
  const ZoneTrendChart({
    super.key,
    required this.values,
    required this.zones,
    this.height = 170,
    this.dates,
  });

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text('Pas assez de données pour tracer une courbe.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ),
      );
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => CustomPaint(
          painter: _ZoneTrendPainter(
              values: values, zones: zones, progress: t, dates: dates),
        ),
      ),
    );
  }
}

class _ZoneTrendPainter extends CustomPainter {
  final List<double> values;
  final List<ChartZone> zones;
  final double progress;
  final List<DateTime>? dates;
  _ZoneTrendPainter(
      {required this.values,
      required this.zones,
      required this.progress,
      this.dates});

  Color _colorFor(double v) {
    for (final z in zones) {
      if (v >= z.min && v <= z.max) return z.color;
    }
    return zones.isNotEmpty ? zones.last.color : kNeonCyan;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 4.0;
    const topPad = 10.0;
    final bottomPad = (dates != null && dates!.length >= 2) ? 24.0 : 10.0;
    final chartW = size.width - leftPad - 4;
    final chartH = size.height - topPad - bottomPad;

    final minV = zones.map((z) => z.min).reduce(math.min);
    final maxV = zones.map((z) => z.max).reduce(math.max);
    final range = (maxV - minV).abs() < 1e-6 ? 1.0 : (maxV - minV);

    double yFor(double v) => topPad + chartH - ((v - minV) / range) * chartH;
    double xFor(int i) => leftPad + chartW * (i / (values.length - 1));

    // Bandes de zones en fond.
    for (final z in zones) {
      final top = yFor(z.max).clamp(topPad, topPad + chartH);
      final bottom = yFor(z.min).clamp(topPad, topPad + chartH);
      canvas.drawRect(Rect.fromLTRB(leftPad, top, leftPad + chartW, bottom),
          Paint()..color = z.color.withOpacity(0.12));
    }

    final ds = dates;
    if (ds != null && ds.length >= 2) {
      final dateY = topPad + chartH + 12;
      final fmt = (DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
      final p1 = TextPainter(
          text: TextSpan(
              text: fmt(ds.first),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
          textDirection: TextDirection.ltr)
        ..layout();
      p1.paint(canvas, Offset(leftPad, dateY));
      final p2 = TextPainter(
          text: TextSpan(
              text: fmt(ds.last),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
          textDirection: TextDirection.ltr)
        ..layout();
      p2.paint(canvas, Offset(size.width - p2.width, dateY));
    }

    final count = values.length;
    final drawnCount = (count * progress).clamp(2, count).toInt();

    // Un segment de ligne par paire de points consécutifs, coloré selon la
    // zone du point d'arrivée — la couleur change exactement là où la donnée
    // franchit une frontière de zone.
    for (int i = 0; i < drawnCount - 1; i++) {
      final p1 = Offset(xFor(i), yFor(values[i]));
      final p2 = Offset(xFor(i + 1), yFor(values[i + 1]));
      canvas.drawLine(
          p1,
          p2,
          Paint()
            ..color = _colorFor(values[i + 1])
            ..strokeWidth = 2.6
            ..strokeCap = StrokeCap.round);
    }
    for (int i = 0; i < drawnCount; i++) {
      canvas.drawCircle(
          Offset(xFor(i), yFor(values[i])), 3, Paint()..color = _colorFor(values[i]));
    }
  }

  @override
  bool shouldRepaint(covariant _ZoneTrendPainter old) =>
      old.progress != progress || old.values != values;
}

/// Un secteur d'un anneau segmenté (ex. un stade de sommeil).
class RingSegmentData {
  final double value;
  final Color color;
  final String label;
  const RingSegmentData(
      {required this.value, required this.color, required this.label});
}

/// Anneau divisé en plusieurs secteurs proportionnels (donut) — pour une
/// répartition (ex. stades de sommeil) où la part de chaque catégorie compte
/// plus que sa valeur isolée. `centerValue`/`centerLabel` optionnels pour un
/// total au centre (ex. durée totale de la nuit).
class SegmentedRing extends StatelessWidget {
  final List<RingSegmentData> segments;
  final double size;
  final String? centerValue;
  final String? centerLabel;
  const SegmentedRing({
    super.key,
    required this.segments,
    this.size = 100,
    this.centerValue,
    this.centerLabel,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => CustomPaint(
          painter: _SegmentedRingPainter(segments: segments, progress: t),
          child: (centerValue == null && centerLabel == null)
              ? null
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (centerValue != null)
                        Text(centerValue!,
                            style: TextStyle(
                                fontFamily: kArcadeFont,
                                color: AppColors.textPrimary,
                                fontSize: size * 0.16,
                                fontWeight: FontWeight.w800)),
                      if (centerLabel != null)
                        Text(centerLabel!,
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 9,
                                fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _SegmentedRingPainter extends CustomPainter {
  final List<RingSegmentData> segments;
  final double progress;
  _SegmentedRingPainter({required this.segments, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold<double>(0, (s, e) => s + e.value);
    if (total <= 0) return;
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 8;
    final stroke = size.width * 0.14;
    const startAngle = -math.pi / 2;

    var angle = startAngle;
    for (final seg in segments) {
      final sweep = 2 * math.pi * (seg.value / total) * progress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        angle,
        sweep,
        false,
        Paint()
          ..color = seg.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      angle += 2 * math.pi * (seg.value / total);
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentedRingPainter old) =>
      old.progress != progress || old.segments != segments;
}

/// Un point du nuage (ex. une course : allure × FC moyenne).
class ScatterPoint {
  final double x;
  final double y;
  final bool highlighted;
  const ScatterPoint({required this.x, required this.y, this.highlighted = false});
}

/// Nuage de points — pour une donnée qui vient d'un ensemble d'observations
/// (ex. VO2 max estimé à partir de plusieurs courses) plutôt que d'une série
/// temporelle : montre d'où vient l'estimation, pas juste son évolution.
class ScatterChart extends StatelessWidget {
  final List<ScatterPoint> points;
  final Color color;
  final double height;
  final String xLabel;
  final String yLabel;
  const ScatterChart({
    super.key,
    required this.points,
    required this.color,
    this.height = 140,
    this.xLabel = '',
    this.yLabel = '',
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text('Pas encore assez de courses pour ce graphique.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ),
      );
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => CustomPaint(
          painter: _ScatterPainter(points: points, color: color, progress: t),
        ),
      ),
    );
  }
}

class _ScatterPainter extends CustomPainter {
  final List<ScatterPoint> points;
  final Color color;
  final double progress;
  _ScatterPainter(
      {required this.points, required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 18.0;
    const bottomPad = 16.0;
    final chartW = size.width - leftPad - 8;
    final chartH = size.height - bottomPad - 8;

    final xs = points.map((p) => p.x).toList();
    final ys = points.map((p) => p.y).toList();
    final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
    final rangeX = (maxX - minX).abs() < 1e-6 ? 1.0 : (maxX - minX);
    final rangeY = (maxY - minY).abs() < 1e-6 ? 1.0 : (maxY - minY);

    final axisPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    canvas.drawLine(Offset(leftPad, 8), Offset(leftPad, 8 + chartH), axisPaint);
    canvas.drawLine(Offset(leftPad, 8 + chartH),
        Offset(leftPad + chartW, 8 + chartH), axisPaint);

    for (final p in points) {
      final x = leftPad + chartW * ((p.x - minX) / rangeX);
      final y = 8 + chartH - chartH * ((p.y - minY) / rangeY);
      final r = (p.highlighted ? 5.5 : 4.0) * progress;
      if (p.highlighted) {
        canvas.drawCircle(Offset(x, y), r + 3, Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
      }
      canvas.drawCircle(Offset(x, y), r,
          Paint()..color = color.withOpacity((p.highlighted ? 1.0 : 0.72) * progress));
    }
  }

  @override
  bool shouldRepaint(covariant _ScatterPainter old) =>
      old.progress != progress || old.points != points;
}
