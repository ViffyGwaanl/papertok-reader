import 'package:flutter/material.dart';

/// Claude design tokens — the canonical brand colors used by the Claude app.
///
/// This is the named entry point for new code. The legacy `MorandiPalette`
/// class still exists and now resolves to the same hex values, so any code
/// that still imports it keeps working.
class ClaudePalette {
  ClaudePalette._();

  // === Brand accent ===
  /// Claude terracotta. The single brand accent, used for active controls,
  /// primary buttons, selection highlights, and the send button.
  static const Color accentLight = Color(0xFFCC7D5E);
  static const Color accentDark = Color(0xFFD68E70);

  // === Surfaces ===
  static const Color bgLight = Color(0xFFF9F9F7); // warm cream
  static const Color bgDark = Color(0xFF2D2D2B); // warm near-black
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFF363633);
  static const Color elevatedLight = Color(0xFFF3F2EE);
  static const Color elevatedDark = Color(0xFF333331);

  // === Foreground / text ===
  static const Color fgLight = Color(0xFF2D2D2B);
  static const Color fgDark = Color(0xFFF9F9F7);
  static const Color secondaryLight = Color(0xFF6E6E6A);
  static const Color secondaryDark = Color(0xFFB8B6AE);
  static const Color tertiaryLight = Color(0xFF9A9994);
  static const Color tertiaryDark = Color(0xFF8A8881);

  // === Semantic ===
  static const Color dividerLight = Color(0xFFE8E5DF);
  static const Color dividerDark = Color(0xFF45443F);
  // Subtle terracotta tint used for selected rows / user message bubble bg.
  static const Color accentTintLight = Color(0x1ACC7D5E); // ~10% terracotta
  static const Color accentTintDark = Color(0x26D68E70); // ~15% terracotta

  // === Adaptive helpers ===
  static bool _isDark(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark;

  static Color accent(BuildContext ctx) =>
      _isDark(ctx) ? accentDark : accentLight;
  static Color accentTint(BuildContext ctx) =>
      _isDark(ctx) ? accentTintDark : accentTintLight;
  static Color bg(BuildContext ctx) => _isDark(ctx) ? bgDark : bgLight;
  static Color card(BuildContext ctx) => _isDark(ctx) ? cardDark : cardLight;
  static Color elevated(BuildContext ctx) =>
      _isDark(ctx) ? elevatedDark : elevatedLight;
  static Color fg(BuildContext ctx) => _isDark(ctx) ? fgDark : fgLight;
  static Color secondary(BuildContext ctx) =>
      _isDark(ctx) ? secondaryDark : secondaryLight;
  static Color tertiary(BuildContext ctx) =>
      _isDark(ctx) ? tertiaryDark : tertiaryLight;
  static Color divider(BuildContext ctx) =>
      _isDark(ctx) ? dividerDark : dividerLight;
}
