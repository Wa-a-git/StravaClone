// lib/widgets/musculation_set_fields.dart
// Contrôles de saisie d'un bloc muscu/cardio (reps, charge, durée, distance,
// côté, chip sélectionnable) — partagés entre la séance en direct
// (live_musculation_screen.dart) et la correction a posteriori d'une série
// déjà enregistrée (edit_musculation_set_sheet.dart), pour un rendu
// identique dans les deux flux.
import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';

class SelectableChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const SelectableChip({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? kNeonAmber.withOpacity(0.18) : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? kNeonAmber : AppColors.border),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? kNeonAmber : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
      ),
    );
  }
}

/// Sélecteur Gauche/Droite pour un exercice unilatéral — alterné
/// automatiquement en séance en direct, mais ajustable au cas où
/// l'alternance devine mal (ex. série ratée refaite du même côté), ou
/// corrigeable après coup.
class SideToggle extends StatelessWidget {
  final String? side;
  final ValueChanged<String?> onChanged;
  const SideToggle({super.key, required this.side, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SelectableChip(label: 'Gauche', selected: side == 'L', onTap: () => onChanged('L')),
        const SizedBox(width: 8),
        SelectableChip(label: 'Droite', selected: side == 'R', onTap: () => onChanged('R')),
      ],
    );
  }
}

class StepperRow extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  const StepperRow({super.key, required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded,
                  color: AppColors.textSecondary),
              onPressed: value > 1 ? () => onChanged(value - 1) : null,
            ),
            SizedBox(
              width: 34,
              child: Text('$value',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: kArcadeFont,
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded,
                  color: AppColors.textSecondary),
              onPressed: () => onChanged(value + 1),
            ),
          ],
        ),
      ],
    );
  }
}

class DurationStepperRow extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  const DurationStepperRow({super.key, this.label = 'Durée', required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded,
                  color: AppColors.textSecondary),
              onPressed: value > 0 ? () => onChanged(max(0, value - 15)) : null,
            ),
            SizedBox(
              width: 56,
              child: Text(fmtClock(value),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: kArcadeFont,
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded,
                  color: AppColors.textSecondary),
              onPressed: () => onChanged(value + 15),
            ),
          ],
        ),
      ],
    );
  }
}

class DistanceStepperRow extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const DistanceStepperRow({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Distance (km, optionnel)',
            style: TextStyle(color: AppColors.textSecondary)),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded,
                  color: AppColors.textSecondary),
              onPressed: value > 0 ? () => onChanged(max(0, value - 0.1)) : null,
            ),
            SizedBox(
              width: 48,
              child: Text(
                value > 0 ? value.toStringAsFixed(1) : '--',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: kArcadeFont,
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded,
                  color: AppColors.textSecondary),
              onPressed: () => onChanged(value + 0.1),
            ),
          ],
        ),
      ],
    );
  }
}

class ChargeStepperRow extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  const ChargeStepperRow({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Charge (kg)', style: TextStyle(color: AppColors.textSecondary)),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded,
                  color: AppColors.textSecondary),
              onPressed: value > 0 ? () => onChanged(max(0, value - 2.5)) : null,
            ),
            SizedBox(
              width: 48,
              child: Text(
                value > 0 ? formatCharge(value) : '--',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: kArcadeFont,
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded,
                  color: AppColors.textSecondary),
              onPressed: () => onChanged(value + 2.5),
            ),
          ],
        ),
      ],
    );
  }
}

String formatCharge(double kg) =>
    kg == kg.roundToDouble() ? kg.toInt().toString() : kg.toStringAsFixed(1);

String fmtClock(int totalSeconds) {
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
