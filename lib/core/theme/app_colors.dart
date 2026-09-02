import 'package:flutter/material.dart';

/// Central color palette for the SoftCar passenger app.
///
/// The design language mirrors a premium ride-hailing experience:
/// a near-black "ink" primary (like Uber) combined with a vivid
/// SoftCar red accent that matches the brand logo.
class AppColors {
  AppColors._();

  // Brand ------------------------------------------------------------------
  static const Color ink = Color(0xFF0B0B0D);
  static const Color inkSoft = Color(0xFF1C1C20);
  static const Color accent = Color(0xFFE02E2E);
  static const Color accentDark = Color(0xFFB71C1C);
  static const Color accentSoft = Color(0xFFFCE7E7);

  // Surfaces ---------------------------------------------------------------
  static const Color background = Color(0xFFF6F6F6);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF141416);
  static const Color surfaceDarkElevated = Color(0xFF1E1E22);

  // Text -------------------------------------------------------------------
  static const Color textPrimary = Color(0xFF1A1A1E);
  static const Color textSecondary = Color(0xFF6B6B70);
  static const Color textTertiary = Color(0xFF9C9CA1);
  static const Color textOnDark = Color(0xFFFFFFFF);

  // Lines & dividers -------------------------------------------------------
  static const Color divider = Color(0xFFE9E9EA);
  static const Color dividerDark = Color(0xFF2A2A2E);

  // Feedback ---------------------------------------------------------------
  static const Color success = Color(0xFF18A058);
  static const Color warning = Color(0xFFF5A623);
  static const Color error = Color(0xFFE5484D);
  static const Color info = Color(0xFF3B82F6);

  // Map --------------------------------------------------------------------
  static const Color mapWater = Color(0xFFEAF3F9);
  static const Color mapRoad = Color(0xFFFFFFFF);
  static const Color mapRoadBorder = Color(0xFFE3E3E3);
  static const Color mapPark = Color(0xFFDCEEDD);
  static const Color mapRoute = Color(0xFFE02E2E);
  static const Color mapRouteDark = Color(0xFF0B0B0D);
  static const Color mapShadow = Color(0x22000000);

  // Service type accents (Uber-like palette) -------------------------------
  static const Color serviceGo = Color(0xFF0B0B0D);
  static const Color serviceComfort = Color(0xFF1F6FFF);
  static const Color servicePremium = Color(0xFF0B0B0D);
  static const Color serviceXl = Color(0xFFB23BFF);
  static const Color serviceShuttle = Color(0xFFE02E2E);

  // Shuttle seat gender colors ---------------------------------------------
  /// Reserved seat assigned to a female passenger.
  static const Color seatFemale = Color(0xFFEC4899);
  static const Color seatFemaleSoft = Color(0xFFFDE7F1);
  /// Reserved seat assigned to a male passenger.
  static const Color seatMale = Color(0xFF3B82F6);
  static const Color seatMaleSoft = Color(0xFFE3F0FF);
}
