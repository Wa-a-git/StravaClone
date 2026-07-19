// lib/screens/edit_musculation_set_sheet.dart
// Correction d'une série/bloc déjà enregistré — mêmes contrôles que la saisie
// en direct (live_musculation_screen.dart), pour un geste familier que ce
// soit juste après l'avoir loggé (séance en cours) ou après coup (détail
// d'une séance passée). Ne persiste rien elle-même : renvoie l'entrée
// modifiée (ou null si annulé), à l'appelant de choisir comment la stocker.
import 'package:flutter/material.dart';
import '../data/exercise_library.dart';
import '../models/musculation_log.dart';
import '../theme.dart';
import '../widgets/musculation_set_fields.dart';
import '../widgets/ui_kit.dart';

Future<MusculationLogEntry?> showEditMusculationSetSheet(
    BuildContext context, MusculationLogEntry entry) {
  return showAppSheet<MusculationLogEntry>(
    context: context,
    child: _EditSetSheet(entry: entry),
  );
}

class _EditSetSheet extends StatefulWidget {
  final MusculationLogEntry entry;
  const _EditSetSheet({required this.entry});

  @override
  State<_EditSetSheet> createState() => _EditSetSheetState();
}

class _EditSetSheetState extends State<_EditSetSheet> {
  late int _reps = widget.entry.reps;
  late double _charge = widget.entry.chargeKg;
  late int _duration = widget.entry.durationSeconds;
  late double _distance = widget.entry.distanceKm;
  late bool _isInterval = widget.entry.isInterval;
  late int _restSeconds = widget.entry.restSeconds;
  late String? _side = widget.entry.side;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final cardio = entry.category.isCardio;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(entry.category.icon, color: entry.category.color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(entry.exerciseName,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (cardio) ...[
          DurationStepperRow(
              value: _duration, onChanged: (v) => setState(() => _duration = v)),
          const SizedBox(height: 10),
          DistanceStepperRow(
              value: _distance, onChanged: (v) => setState(() => _distance = v)),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableChip(
                label: 'Fractionné',
                selected: _isInterval,
                onTap: () => setState(() => _isInterval = !_isInterval)),
          ),
        ] else ...[
          if (_side != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: SideToggle(side: _side, onChanged: (v) => setState(() => _side = v)),
            ),
            const SizedBox(height: 10),
          ],
          StepperRow(
              label: 'Répétitions', value: _reps, onChanged: (v) => setState(() => _reps = v)),
          const SizedBox(height: 10),
          ChargeStepperRow(value: _charge, onChanged: (v) => setState(() => _charge = v)),
        ],
        const SizedBox(height: 10),
        DurationStepperRow(
            label: 'Repos',
            value: _restSeconds,
            onChanged: (v) => setState(() => _restSeconds = v)),
        const SizedBox(height: AppSpacing.xl),
        GlowButton(
          label: 'ENREGISTRER',
          icon: Icons.check_rounded,
          color: kNeonCyan,
          foreground: Colors.black,
          onPressed: () => Navigator.pop(
            context,
            entry.copyWith(
              reps: _reps,
              chargeKg: _charge,
              durationSeconds: _duration,
              distanceKm: _distance,
              isInterval: _isInterval,
              restSeconds: _restSeconds,
              side: _side,
            ),
          ),
        ),
      ],
    );
  }
}
