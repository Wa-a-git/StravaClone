// lib/widgets/health_charts.dart
// Graphiques santé peints à la main (CustomPaint), style néon/CRT cohérent
// avec le reste de l'app. Aucune dépendance externe.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/health_snapshot.dart';
import '../services/health_score_service.dart' show TrendDir;
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
