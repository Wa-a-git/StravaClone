// lib/widgets/health_charts.dart
// Graphiques santé peints à la main (CustomPaint), style néon/CRT cohérent
// avec le reste de l'app. Aucune dépendance externe.
import 'dart:math' as math;
import 'package:flutter/material.dart';
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

/// Courbe complète avec axes légers, ligne de baseline et étiquettes min/max.
/// Utilisée dans l'écran de détail.
class TrendChart extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double? baseline;
  final double height;
  const TrendChart({
    super.key,
    required this.values,
    required this.color,
    this.baseline,
    this.height = 200,
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
  _TrendPainter({
    required this.values,
    required this.color,
    required this.baseline,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 4.0;
    const rightPad = 4.0;
    const topPad = 14.0;
    const bottomPad = 14.0;
    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;

    double minV = values.reduce(math.min);
    double maxV = values.reduce(math.max);
    if (baseline != null) {
      minV = math.min(minV, baseline!);
      maxV = math.max(maxV, baseline!);
    }
    final range = (maxV - minV).abs() < 1e-6 ? 1.0 : (maxV - minV);

    double yFor(double v) =>
        topPad + chartH - ((v - minV) / range) * chartH;
    double xFor(int i) => leftPad + chartW * (i / (values.length - 1));

    // Grille horizontale légère (4 lignes)
    final gridPaint = Paint()
      ..color = AppColors.border.withOpacity(0.4)
      ..strokeWidth = 1;
    for (int g = 0; g <= 3; g++) {
      final y = topPad + chartH * (g / 3);
      canvas.drawLine(Offset(leftPad, y), Offset(size.width - rightPad, y),
          gridPaint);
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
