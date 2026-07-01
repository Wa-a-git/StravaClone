// lib/widgets/record_celebration.dart
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import '../theme.dart';

/// Affiche une célébration plein écran type "NEW HIGH SCORE!" avec confettis.
/// [records] : la liste des records battus (ex. ["Plus longue distance", ...]).
Future<void> showRecordCelebration(
  BuildContext context, {
  required String title,
  required List<String> records,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.85),
    builder: (_) => _RecordCelebrationDialog(title: title, records: records),
  );
}

class _RecordCelebrationDialog extends StatefulWidget {
  final String title;
  final List<String> records;

  const _RecordCelebrationDialog({required this.title, required this.records});

  @override
  State<_RecordCelebrationDialog> createState() =>
      _RecordCelebrationDialogState();
}

class _RecordCelebrationDialogState extends State<_RecordCelebrationDialog>
    with SingleTickerProviderStateMixin {
  late final ConfettiController _confetti;
  late final AnimationController _pulse;

  static const _neon = [
    Color(0xFFF55CBD),
    Color(0xFF00FFFF),
    Color(0xFF39FF14),
    Color(0xFFF8FF00),
    Color(0xFF8A5EFF),
  ];

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 2));
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _confetti.play());
  }

  @override
  void dispose() {
    _confetti.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Confettis qui explosent depuis le haut
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            numberOfParticles: 30,
            maxBlastForce: 22,
            minBlastForce: 8,
            gravity: 0.25,
            emissionFrequency: 0.05,
            colors: _neon,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1.08).animate(
                  CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                ),
                child: const Text('🏆', style: TextStyle(fontSize: 72)),
              ),
              const SizedBox(height: 16),
              const Text(
                'NEW RECORD!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: kArcadeFont,
                  fontWeight: FontWeight.w900,
                  fontSize: 30,
                  color: Color(0xFFF8FF00),
                  letterSpacing: 2,
                  shadows: [
                    Shadow(color: Color(0xFFF8FF00), blurRadius: 18),
                    Shadow(color: Color(0xFFF55CBD), blurRadius: 30),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: kArcadeFont,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Color(0xFF00FFFF),
                  letterSpacing: 1,
                  shadows: [Shadow(color: Color(0xFF00FFFF), blurRadius: 10)],
                ),
              ),
              const SizedBox(height: 24),
              ...widget.records.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141419),
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: const Color(0xFF39FF14), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF39FF14).withOpacity(0.3),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.emoji_events_rounded,
                            color: Color(0xFF39FF14), size: 18),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            r,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF55CBD),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    shadowColor: const Color(0xFFF55CBD),
                    elevation: 12,
                  ),
                  child: const Text(
                    'CONTINUER',
                    style: TextStyle(
                      fontFamily: kArcadeFont,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
