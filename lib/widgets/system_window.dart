// lib/widgets/system_window.dart
// Popup néon réutilisable (level-up, palier, quête accomplie) — thème arcade.
import 'package:flutter/material.dart';
import '../theme.dart';

/// Affiche une notification néon plein écran avec animation d'apparition.
Future<void> showSystemWindow(
  BuildContext context, {
  required String heading,
  required List<String> lines,
  Color accent = kNeonCyan,
  String buttonLabel = 'CONTINUER',
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'notif',
    barrierColor: Colors.black.withOpacity(0.82),
    transitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, __, ___) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return Opacity(
        opacity: anim.value.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.85 + 0.15 * curved.value,
          child: _NeonWindow(
            heading: heading,
            lines: lines,
            accent: accent,
            buttonLabel: buttonLabel,
          ),
        ),
      );
    },
  );
}

class _NeonWindow extends StatelessWidget {
  final String heading;
  final List<String> lines;
  final Color accent;
  final String buttonLabel;

  const _NeonWindow({
    required this.heading,
    required this.lines,
    required this.accent,
    required this.buttonLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
          decoration: BoxDecoration(
            color: const Color(0xFF141419),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent, width: 1.5),
            boxShadow: [
              BoxShadow(color: accent.withOpacity(0.45), blurRadius: 26),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                heading,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: kArcadeFont,
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  shadows: [Shadow(color: accent, blurRadius: 18)],
                ),
              ),
              const SizedBox(height: 16),
              ...lines.map(
                (l) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFCCCCCC),
                      fontSize: 14,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 10,
                    shadowColor: accent,
                  ),
                  child: Text(
                    buttonLabel,
                    style: const TextStyle(
                      fontFamily: kArcadeFont,
                      color: Colors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
