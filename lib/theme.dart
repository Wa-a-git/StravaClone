import 'package:flutter/material.dart';

/// Police "arcade / techno" utilisée UNIQUEMENT pour les nombres-clés et les
/// titres de section — jamais pour le corps de texte (lisibilité).
const String kArcadeFont = 'Orbitron';

/// Couleurs d'accent — tons "pierre précieuse" plutôt que néon pur : même
/// famille de teintes qu'avant (identité arcade conservée) mais assourdies
/// pour lire comme élégantes plutôt que synthwave/glow. Réservées aux
/// accents, CTA et moments forts — jamais pour du texte courant.
const Color kNeonCyan = Color(0xFF2FA9A0);
const Color kNeonPink = Color(0xFFC85A87);
const Color kNeonGreen = Color(0xFF2E9E63);
const Color kNeonViolet = Color(0xFF7C6AD6);
const Color kNeonAmber = Color(0xFFCC9640);
const Color kNeonRed = Color(0xFFC94D5C);

class AppColors {
  static const arcadePink = kNeonPink;
  static const arcadeCyan = kNeonCyan;
  static const arcadeViolet = kNeonViolet;

  // Base sombre premium — moins de violet saturé, plus neutre/profond.
  static const background = Color(0xFF0A0A10);
  static const surface = Color(0xFF15151D);
  static const surfaceAlt = Color(0xFF1B1B26);
  static const surfaceLight = Color(0xFF23232F);

  static const textPrimary = Color(0xFFF4F4F8);
  static const textSecondary = Color(0xFFA3A3B5);
  static const border = Color(0xFF2A2A38);
  static const muted = Color(0xFF6E6E82);
}

/// Échelle d'espacement — utiliser ces valeurs plutôt que des nombres ad hoc.
class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 28.0;
  static const xxxl = 36.0;
}

class AppRadius {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 18.0;
  static const xl = 24.0;
}

/// Styles de texte partagés — hiérarchie unique pour tout l'app.
class AppText {
  static const screenTitle = TextStyle(
    fontFamily: kArcadeFont,
    color: AppColors.textPrimary,
    fontSize: 18,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.6,
  );

  static const pageHeading = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 26,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
    height: 1.15,
  );

  static const eyebrow = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );

  static const sectionLabel = TextStyle(
    fontFamily: kArcadeFont,
    fontSize: 12,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.2,
  );

  static const cardValue = TextStyle(
    fontFamily: kArcadeFont,
    fontSize: 20,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
  );

  static const body = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 14,
    height: 1.4,
  );

  static const caption = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 12,
    fontWeight: FontWeight.w500,
  );
}

/// Halo lumineux discret — une seule intensité standard pour tout l'app,
/// pour éviter l'effet "chaque carte a son propre néon" qui fatigue l'œil.
/// Volontairement très léger : un repère de profondeur, pas un effet glow.
List<BoxShadow> softGlow(Color color, {double blur = 14, double opacity = 0.06}) {
  return [BoxShadow(color: color.withOpacity(opacity), blurRadius: blur)];
}

/// Léger relief de texte pour les nombres-clés — juste assez pour détacher le
/// chiffre du fond, sans effet "enseigne au néon" (pas de blur large).
List<Shadow> softTextGlow(Color color) =>
    [Shadow(color: color.withOpacity(0.35), blurRadius: 4)];
