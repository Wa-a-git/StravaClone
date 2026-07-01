// lib/widgets/ui_kit.dart
// Composants partagés du design system — à utiliser à la place de Container
// "faits main" pour garder une hiérarchie et un espacement cohérents partout.
import 'package:flutter/material.dart';
import '../theme.dart';

/// Carte standard de l'app. Bordure neutre par défaut ; l'accent ne sert
/// qu'à teinter légèrement la bordure et à donner un repère de couleur,
/// jamais à faire un halo agressif (réservé aux [AppPanel.hero]).
class AppPanel extends StatelessWidget {
  final Widget child;
  final Color? accent;
  final bool hero;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const AppPanel({
    super.key,
    required this.child,
    this.accent,
    this.hero = false,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = accent != null
        ? accent!.withOpacity(hero ? 0.5 : 0.25)
        : AppColors.border;

    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: borderColor, width: hero ? 1.2 : 1),
        boxShadow: hero && accent != null ? softGlow(accent!, blur: 24, opacity: 0.14) : null,
      ),
      child: child,
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: content,
    );
  }
}

/// Titre de section utilisé en tête de panneau (police arcade, discret).
class PanelTitle extends StatelessWidget {
  final String text;
  final Color color;
  final Widget? trailing;

  const PanelTitle(this.text, {super.key, this.color = kNeonCyan, this.trailing});

  @override
  Widget build(BuildContext context) {
    final title = Text(
      text,
      style: AppText.sectionLabel.copyWith(color: color),
    );
    if (trailing == null) return title;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [title, trailing!],
    );
  }
}

/// En-tête de page (hors AppBar) — utilisé sous le SliverAppBar de chaque écran.
class PageHeading extends StatelessWidget {
  final String eyebrow;
  final String title;

  const PageHeading({super.key, required this.eyebrow, required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(eyebrow, style: AppText.eyebrow),
        const SizedBox(height: AppSpacing.xs),
        Text(title, style: AppText.pageHeading),
      ],
    );
  }
}

/// Sélecteur segmenté générique (remplace les multiples "period selectors"
/// dupliqués à travers l'app).
class SegmentedTabs<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  const SegmentedTabs({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: values.map((v) {
          final isActive = v == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(v),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.surfaceLight : null,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: isActive ? Border.all(color: kNeonPink.withOpacity(0.5)) : null,
                ),
                child: Text(
                  labelOf(v),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Bouton principal plein-largeur (arcade, réservé aux CTA importants).
class GlowButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final VoidCallback? onPressed;
  final bool busy;
  final Color? foreground;

  const GlowButton({
    super.key,
    required this.label,
    required this.color,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? Colors.black;
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton.icon(
        onPressed: busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: fg,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        ),
        icon: busy
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: fg),
              )
            : (icon != null ? Icon(icon, size: 18) : const SizedBox.shrink()),
        label: Text(
          label,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: fg),
        ),
      ),
    );
  }
}

/// Barre de progression fine, réutilisée pour XP / quêtes / sommeil.
class AppProgressBar extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  final double height;

  const AppProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Stack(
        children: [
          Container(height: height, color: AppColors.surfaceLight),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => FractionallySizedBox(
              widthFactor: v,
              child: Container(height: height, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Feuille modale standard (bottom sheet) — remplace les multiples
/// showModalBottomSheet configurés à la main dans chaque écran.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required Widget child,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: isScrollControlled,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    ),
  );
}

/// État vide générique (liste vide, données manquantes...).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.accent = kNeonPink,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: accent),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppText.caption,
            ),
          ],
        ),
      ),
    );
  }
}
