import 'package:flutter/material.dart';
import 'package:chinese_font_library/chinese_font_library.dart';
import 'morandi_palette.dart';
import 'app_typography.dart';
import 'app_spacing.dart';

class AppTheme {
  AppTheme._();

  /// Build light theme.
  /// [seedColor] overrides the default sage accent (user-selected accent).
  /// [eInkMode] forces a hardcoded black/white/grey palette.
  static ThemeData light({
    Color? seedColor,
    bool eInkMode = false,
  }) {
    final effectiveSeed = seedColor ?? MorandiPalette.sageLight;
    final colorScheme = eInkMode
        ? const ColorScheme(
            brightness: Brightness.light,
            primary: Color(0xFF000000),
            onPrimary: Color(0xFFFFFFFF),
            secondary: Color(0xFF000000),
            onSecondary: Color(0xFFFFFFFF),
            error: Color(0xFF000000),
            onError: Color(0xFFFFFFFF),
            surface: Color(0xFFFFFFFF),
            onSurface: Color(0xFF000000),
            surfaceContainerHighest: Color(0xFFE5E5E5),
            outline: Color(0xFF808080),
          )
        : ColorScheme.fromSeed(
            seedColor: effectiveSeed,
            brightness: Brightness.light,
            primary: effectiveSeed,
          );

    final scaffoldBg =
        eInkMode ? const Color(0xFFFFFFFF) : MorandiPalette.backgroundLight;
    final groupedBg =
        eInkMode ? const Color(0xFFF2F2F2) : MorandiPalette.elevatedLight;
    final cardBg =
        eInkMode ? const Color(0xFFFFFFFF) : MorandiPalette.cardLight;

    final base = ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scaffoldBg,
      textTheme: AppTypography.buildTextTheme(colorScheme),
      dividerColor: MorandiPalette.dividerLight,
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cornerRadius),
        ),
      ),
      sliderTheme: const SliderThemeData(
        year2023: false,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        year2023: false,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: groupedBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.cornerRadiusLarge),
          ),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: groupedBg,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: groupedBg,
      ),
    );

    return base.useSystemChineseFont(Brightness.light);
  }

  /// Build dark theme.
  /// [seedColor] overrides the default sage accent.
  /// [eInkMode] forces hardcoded b/w.
  /// [trueDarkMode] uses pure black background for OLED screens.
  static ThemeData dark({
    Color? seedColor,
    bool eInkMode = false,
    bool trueDarkMode = false,
  }) {
    final effectiveSeed = seedColor ?? MorandiPalette.sageDark;
    final colorScheme = eInkMode
        ? const ColorScheme(
            brightness: Brightness.dark,
            primary: Color(0xFFFFFFFF),
            onPrimary: Color(0xFF000000),
            secondary: Color(0xFFFFFFFF),
            onSecondary: Color(0xFF000000),
            error: Color(0xFFFFFFFF),
            onError: Color(0xFF000000),
            surface: Color(0xFF000000),
            onSurface: Color(0xFFFFFFFF),
            surfaceContainerHighest: Color(0xFF1A1A1A),
            outline: Color(0xFF808080),
          )
        : ColorScheme.fromSeed(
            seedColor: effectiveSeed,
            brightness: Brightness.dark,
            primary: effectiveSeed,
          );

    final scaffoldBg = eInkMode
        ? const Color(0xFF000000)
        : (trueDarkMode ? const Color(0xFF000000) : MorandiPalette.backgroundDark);
    final groupedBg = eInkMode
        ? const Color(0xFF0A0A0A)
        : (trueDarkMode ? const Color(0xFF000000) : MorandiPalette.elevatedDark);
    final cardBg = eInkMode
        ? const Color(0xFF0A0A0A)
        : (trueDarkMode ? const Color(0xFF0C0C18) : MorandiPalette.cardDark);

    final base = ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scaffoldBg,
      textTheme: AppTypography.buildTextTheme(colorScheme),
      dividerColor: MorandiPalette.dividerDark,
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cornerRadius),
        ),
      ),
      sliderTheme: const SliderThemeData(
        year2023: false,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        year2023: false,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: groupedBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.cornerRadiusLarge),
          ),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: groupedBg,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: groupedBg,
      ),
    );

    return base.useSystemChineseFont(Brightness.dark);
  }
}
