// lib/widgets/arcade_fx.dart
// Effets visuels "arcade / borne rétro" réutilisables.
import 'package:flutter/material.dart';

/// Compteur animé qui défile de 0 (ou de l'ancienne valeur) jusqu'à [value],
/// comme un score d'arcade qui grimpe.
class AnimatedCounter extends StatelessWidget {
  final double value;
  final int fractionDigits;
  final String suffix;
  final TextStyle? style;
  final Duration duration;

  const AnimatedCounter({
    super.key,
    required this.value,
    this.fractionDigits = 0,
    this.suffix = '',
    this.style,
    this.duration = const Duration(milliseconds: 900),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text(
        '${v.toStringAsFixed(fractionDigits)}$suffix',
        style: style,
      ),
    );
  }
}

/// Superpose de fines lignes horizontales (scanlines) + un léger vignettage
/// pour donner l'aspect d'un vieil écran cathodique (CRT).
class ScanlineOverlay extends StatelessWidget {
  final Widget child;
  final double opacity;
  final bool vignette;

  const ScanlineOverlay({
    super.key,
    required this.child,
    this.opacity = 0.05,
    this.vignette = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _ScanlinePainter(opacity: opacity, vignette: vignette),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  final double opacity;
  final bool vignette;

  _ScanlinePainter({required this.opacity, required this.vignette});

  @override
  void paint(Canvas canvas, Size size) {
    // Lignes horizontales tous les 3 px
    final linePaint = Paint()
      ..color = Colors.black.withOpacity(opacity)
      ..strokeWidth = 1.0;
    for (double y = 0; y < size.height; y += 3.0) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    // Léger vignettage sombre sur les bords
    if (vignette) {
      final rect = Offset.zero & size;
      final vignettePaint = Paint()
        ..shader = RadialGradient(
          radius: 0.9,
          colors: [
            Colors.transparent,
            Colors.black.withOpacity(0.22),
          ],
          stops: const [0.65, 1.0],
        ).createShader(rect);
      canvas.drawRect(rect, vignettePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanlinePainter oldDelegate) =>
      oldDelegate.opacity != opacity || oldDelegate.vignette != vignette;
}
