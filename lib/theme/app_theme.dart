import 'package:flutter/material.dart';
import 'morandi_palette.dart';
import 'app_typography.dart';
import 'app_spacing.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: MorandiPalette.sageLight,
      brightness: Brightness.light,
      surface: MorandiPalette.cardLight,
      onSurface: MorandiPalette.primaryTextLight,
      primary: MorandiPalette.sageLight,
      error: MorandiPalette.errorLight,
    );
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: MorandiPalette.backgroundLight,
      textTheme: AppTypography.buildTextTheme(colorScheme),
      dividerColor: MorandiPalette.dividerLight,
      cardTheme: CardThemeData(
        elevation: 0,
        color: MorandiPalette.cardLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cornerRadius),
        ),
      ),
    );
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: MorandiPalette.sageDark,
      brightness: Brightness.dark,
      surface: MorandiPalette.cardDark,
      onSurface: MorandiPalette.primaryTextDark,
      primary: MorandiPalette.sageDark,
      error: MorandiPalette.errorDark,
    );
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: MorandiPalette.backgroundDark,
      textTheme: AppTypography.buildTextTheme(colorScheme),
      dividerColor: MorandiPalette.dividerDark,
      cardTheme: CardThemeData(
        elevation: 0,
        color: MorandiPalette.cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cornerRadius),
        ),
      ),
    );
  }
}
