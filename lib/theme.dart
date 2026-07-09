import 'package:flutter/material.dart';

/// Police "arcade / techno" utilisée UNIQUEMENT pour les nombres-clés et les
/// titres de section — jamais pour le corps de texte (lisibilité). Référencée
/// par 94 usages dans 20 écrans : ne pas changer sans repasser sur chacun,
/// voir `kArcadePixelFont` ci-dessous pour le remplacement pixel ciblé.
const String kArcadeFont = 'Orbitron';

/// Police pixel 8-bit (thème rétro-arcade) — disponible mais volontairement
/// PAS branchée sur `kArcadeFont` : ses glyphes sont bien plus larges
/// qu'Orbitron, donc sûre uniquement sur des libellés courts vérifiés au cas
/// par cas (un score, "43,8", "NIVEAU 14"...), jamais sur un titre d'écran ou
/// un libellé de section qui peut être long ("SUPERPOSITION & ACTIONNABLE").
/// À adopter progressivement, écran par écran, en vérifiant chaque fois à
/// l'affichage réel — jamais en remplaçant `kArcadeFont` globalement.
const String kArcadePixelFont = 'Press Start 2P';

/// Couleurs d'accent — palette rétro-arcade saturée (rose électrique, jaune
/// doré, cyan, violet néon) sur fond violet-noir profond, à la place des
/// tons "pierre précieuse" assourdis précédents. Réservées aux accents, CTA
/// et moments forts — jamais pour du texte courant.
const Color kNeonCyan = Color(0xFF29F1E0);
const Color kNeonPink = Color(0xFFFF3EA5);
const Color kNeonGreen = Color(0xFF3DDC84);
const Color kNeonViolet = Color(0xFFA34BFF);
const Color kNeonAmber = Color(0xFFFFD23F);
const Color kNeonRed = Color(0xFFFF4D6D);

class AppColors {
  static const arcadePink = kNeonPink;
  static const arcadeCyan = kNeonCyan;
  static const arcadeViolet = kNeonViolet;

  // Base violet-noir profond façon borne d'arcade, plus tons neutres.
  static const background = Color(0xFF120A1E);
  static const surface = Color(0xFF1E1030);
  static const surfaceAlt = Color(0xFF26123E);
  static const surfaceLight = Color(0xFF33184F);

  static const textPrimary = Color(0xFFFFF6FC);
  static const textSecondary = Color(0xFFC9A8E8);
  static const border = Color(0xFF4A2A73);
  static const muted = Color(0xFF8A6BB0);
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
