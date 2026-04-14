import 'package:flutter/material.dart';
import 'package:chinese_font_library/chinese_font_library.dart';
import 'morandi_palette.dart';
import 'claude_palette.dart';
import 'app_typography.dart';
import 'app_spacing.dart';

class AppTheme {
  AppTheme._();

  /// Build light theme.
  /// [seedColor] overrides the default Claude terracotta accent.
  /// [eInkMode] forces a hardcoded black/white/grey palette.
  static ThemeData light({
    Color? seedColor,
    bool eInkMode = false,
  }) {
    final effectiveSeed = seedColor ?? ClaudePalette.accentLight;
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
    final dividerColor = eInkMode
        ? const Color(0xFFE5E5E5)
        : MorandiPalette.dividerLight;

    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBg: scaffoldBg,
      cardBg: cardBg,
      groupedBg: groupedBg,
      dividerColor: dividerColor,
      brightness: Brightness.light,
    );
  }

  /// Build dark theme.
  /// [seedColor] overrides the default Claude terracotta accent.
  /// [eInkMode] forces hardcoded b/w.
  /// [trueDarkMode] uses pure black background for OLED screens.
  static ThemeData dark({
    Color? seedColor,
    bool eInkMode = false,
    bool trueDarkMode = false,
  }) {
    final effectiveSeed = seedColor ?? ClaudePalette.accentDark;
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
    final dividerColor = eInkMode
        ? const Color(0xFF2A2A2A)
        : MorandiPalette.dividerDark;

    return _buildTheme(
      colorScheme: colorScheme,
      scaffoldBg: scaffoldBg,
      cardBg: cardBg,
      groupedBg: groupedBg,
      dividerColor: dividerColor,
      brightness: Brightness.dark,
    );
  }

  /// Single source of truth for component themes. Both light and dark pass
  /// resolved surfaces + ColorScheme through here so every control (app bar,
  /// bottom nav, tab bar, segmented button, buttons, inputs, switches,
  /// sliders, etc.) inherits the Claude terracotta accent automatically.
  static ThemeData _buildTheme({
    required ColorScheme colorScheme,
    required Color scaffoldBg,
    required Color cardBg,
    required Color groupedBg,
    required Color dividerColor,
    required Brightness brightness,
  }) {
    final accent = colorScheme.primary;
    final onSurface = colorScheme.onSurface;
    final onSurfaceVariant = colorScheme.onSurfaceVariant;

    final base = ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scaffoldBg,
      textTheme: AppTypography.buildTextTheme(colorScheme),
      dividerColor: dividerColor,
      dividerTheme: DividerThemeData(
        color: dividerColor,
        thickness: 0.5,
        space: 0.5,
      ),

      // === AppBar ===
      // Flat warm surface, no blue tint, accent icons.
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        iconTheme: IconThemeData(color: onSurface),
        actionsIconTheme: IconThemeData(color: onSurface),
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
      ),

      // === Bottom navigation (legacy BottomNavigationBar) ===
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: cardBg,
        selectedItemColor: accent,
        unselectedItemColor: onSurfaceVariant,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: true,
        showUnselectedLabels: true,
      ),

      // === M3 NavigationBar ===
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardBg,
        indicatorColor: accent.withValues(alpha: 0.15),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final color = states.contains(WidgetState.selected)
              ? accent
              : onSurfaceVariant;
          return TextStyle(color: color, fontSize: 12);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final color = states.contains(WidgetState.selected)
              ? accent
              : onSurfaceVariant;
          return IconThemeData(color: color, size: 22);
        }),
      ),

      // === TabBar ===
      tabBarTheme: TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: onSurfaceVariant,
        indicatorColor: accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),

      // === SegmentedButton (iOS-style 自动/竖排/横排 etc.) ===
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return accent.withValues(alpha: 0.15);
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return accent;
            return onSurfaceVariant;
          }),
          iconColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return accent;
            return onSurfaceVariant;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            return BorderSide(
              color: states.contains(WidgetState.selected)
                  ? accent.withValues(alpha: 0.35)
                  : dividerColor,
              width: 0.8,
            );
          }),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.cornerRadius),
            ),
          ),
        ),
      ),

      // === Buttons ===
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: colorScheme.onPrimary,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: dividerColor),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: onSurface),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
      ),

      // === Inputs ===
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: groupedBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cornerRadius),
          borderSide: BorderSide(color: dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cornerRadius),
          borderSide: BorderSide(color: dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cornerRadius),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),

      // === Cards ===
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cornerRadius),
        ),
      ),

      // === Controls (already accented, kept here for single source) ===
      sliderTheme: SliderThemeData(
        year2023: false,
        activeTrackColor: accent,
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: 0.12),
        inactiveTrackColor: dividerColor,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        year2023: false,
        color: accent,
        linearTrackColor: dividerColor,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return null;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return null;
        }),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return null;
        }),
      ),

      // === Containers / surfaces ===
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: groupedBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.cornerRadiusLarge),
          ),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: groupedBg,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardBg,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: cardBg,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cornerRadius),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: onSurface,
        textColor: onSurface,
        selectedColor: accent,
        selectedTileColor: accent.withValues(alpha: 0.1),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: groupedBg,
        selectedColor: accent.withValues(alpha: 0.15),
        labelStyle: TextStyle(color: onSurface),
        side: BorderSide(color: dividerColor),
      ),
    );

    return base.useSystemChineseFont(brightness);
  }
}
