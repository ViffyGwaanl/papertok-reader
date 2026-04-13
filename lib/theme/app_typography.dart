import 'package:flutter/material.dart';

/// Typography scale ported from swift-native AppTypography.swift.
/// Sizes in logical pixels (Flutter default).
class AppTypography {
  AppTypography._();

  static const double largeTitleSize = 34;
  static const double titleSize = 28;
  static const double title2Size = 22;
  static const double title3Size = 20;
  static const double headlineSize = 17;
  static const double bodySize = 17;
  static const double calloutSize = 16;
  static const double subheadlineSize = 15;
  static const double footnoteSize = 13;
  static const double captionSize = 12;
  static const double caption2Size = 11;

  // Returns a TextTheme based on the current ColorScheme.
  static TextTheme buildTextTheme(ColorScheme colors) {
    final base = TextStyle(color: colors.onSurface);
    return TextTheme(
      displayLarge: base.copyWith(fontSize: largeTitleSize, fontWeight: FontWeight.w600),
      displayMedium: base.copyWith(fontSize: titleSize, fontWeight: FontWeight.w600),
      displaySmall: base.copyWith(fontSize: title2Size, fontWeight: FontWeight.w600),
      headlineLarge: base.copyWith(fontSize: title2Size, fontWeight: FontWeight.w600),
      headlineMedium: base.copyWith(fontSize: title3Size, fontWeight: FontWeight.w600),
      headlineSmall: base.copyWith(fontSize: headlineSize, fontWeight: FontWeight.w600),
      titleLarge: base.copyWith(fontSize: title3Size, fontWeight: FontWeight.w600),
      titleMedium: base.copyWith(fontSize: headlineSize, fontWeight: FontWeight.w600),
      titleSmall: base.copyWith(fontSize: subheadlineSize, fontWeight: FontWeight.w600),
      bodyLarge: base.copyWith(fontSize: bodySize, fontWeight: FontWeight.w400),
      bodyMedium: base.copyWith(fontSize: calloutSize, fontWeight: FontWeight.w400),
      bodySmall: base.copyWith(fontSize: subheadlineSize, fontWeight: FontWeight.w400, color: colors.onSurface.withOpacity(0.7)),
      labelLarge: base.copyWith(fontSize: footnoteSize, fontWeight: FontWeight.w600),
      labelMedium: base.copyWith(fontSize: captionSize, fontWeight: FontWeight.w500),
      labelSmall: base.copyWith(fontSize: caption2Size, fontWeight: FontWeight.w500),
    );
  }
}
