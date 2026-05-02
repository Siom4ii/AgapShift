import 'package:flutter/material.dart';

/// Brand palette aligned with AgapShift UI mocks.
abstract final class AgapColors {
  static const Color primary = Color(0xFF005C39);
  static const Color primaryBright = Color(0xFF008060);
  static const Color mintSurface = Color(0xFFE8F5EF);
  static const Color mintSoft = Color(0xFFB8E0D2);
  static const Color water = Color(0xFFB8D4E8);
  static const Color pageBackground = Color(0xFFF8F9FB);
  static const Color accentOrange = Color(0xFFF59E0B);
  static const Color borderSubtle = Color(0xFFE0E0E0);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color urgentBadge = Color(0xFFE8E0F5);
  static const Color urgentText = Color(0xFF5B21B6);

  /// Wordmark / logo artwork (royal blue + worker green from brand).
  static const Color brandWordmarkBlue = Color(0xFF1E4E9E);
  /// Padlock hero on login — soft sky behind the mark (matches logo tile).
  static const Color loginHeroSky = Color(0xFFB8D9F0);
  static const Color loginHeroSkyLight = Color(0xFFDCEAF7);
  static const Color loginBackdropTop = Color(0xFFE8F1FA);
  static const Color loginBackdropBottom = Color(0xFFF8FBFF);
  static const Color loginFieldFill = Color(0xFFF2F6FB);
  static const Color brandWordmarkGreen = Color(0xFF43A047);
  static const Color brandBoltYellow = Color(0xFFFFD700);
  static const Color brandNavySuit = Color(0xFF0D1B2A);

  /// Business app UI (dashboard mocks): vibrant emerald + mint surfaces.
  static const Color businessGreen = Color(0xFF00A859);
  static const Color businessGreenDeep = Color(0xFF007C47);
  static const Color businessGreenLight = Color(0xFF4ADE80);
  static const Color businessMint = Color(0xFFE8F8F0);
}
