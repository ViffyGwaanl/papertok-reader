import 'package:flutter/material.dart';

/// Morandi color palette - muted, soothing earth tones.
/// Each token has a light and dark variant for adaptive theming.
/// Ported from swift-native MorandiPalette.swift.
class MorandiPalette {
  MorandiPalette._();

  // === Surfaces ===
  static const Color backgroundLight = Color(0xFFFAF8F5);
  static const Color backgroundDark = Color(0xFF1A1A2E);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFF2C2C3F);
  static const Color elevatedLight = Color(0xFFF2EEE8);
  static const Color elevatedDark = Color(0xFF252538);

  // === Text ===
  static const Color primaryTextLight = Color(0xFF343434);
  static const Color primaryTextDark = Color(0xFFF0EDE5);
  static const Color secondaryTextLight = Color(0xFF8A8A8E);
  static const Color secondaryTextDark = Color(0xFFA8A8B8);
  static const Color tertiaryTextLight = Color(0xFFB0B0B4);
  static const Color tertiaryTextDark = Color(0xFF70707E);

  // === Accent palette ===
  static const Color sageLight = Color(0xFF8FA68A);
  static const Color sageDark = Color(0xFFA8C2A2);
  static const Color dustyRoseLight = Color(0xFFC4A4A0);
  static const Color dustyRoseDark = Color(0xFFD4B8AE);
  static const Color warmGrayLight = Color(0xFFA8A098);
  static const Color warmGrayDark = Color(0xFF9A9690);
  static const Color stoneLight = Color(0xFFB8B0A8);
  static const Color stoneDark = Color(0xFFA0988F);
  static const Color clayLight = Color(0xFFC0A890);
  static const Color clayDark = Color(0xFFDDB992);
  static const Color lavenderLight = Color(0xFFB8A8C8);
  static const Color lavenderDark = Color(0xFFB3ACCA);
  static const Color powderLight = Color(0xFFA0B8C8);
  static const Color powderDark = Color(0xFFBAC9D7);
  static const Color sandLight = Color(0xFFD0C4B0);
  static const Color sandDark = Color(0xFF4A4A5A);
  static const Color mauveLight = Color(0xFFC8A0B0);
  static const Color mauveDark = Color(0xFFD0ACBA);
  static const Color mossLight = Color(0xFF98A890);
  static const Color mossDark = Color(0xFF98A586);
  static const Color taupeLight = Color(0xFFB0A498);
  static const Color taupeDark = Color(0xFF9A8F82);
  static const Color mistLight = Color(0xFFC8D0D0);
  static const Color mistDark = Color(0xFF6C7A82);

  // === Semantic ===
  static const Color dividerLight = Color(0xFFE8E4E0);
  static const Color dividerDark = Color(0xFF3A3A52);
  static const Color successLight = Color(0xFF7FA88A);
  static const Color successDark = Color(0xFF96C2A2);
  static const Color warningLight = Color(0xFFD4A574);
  static const Color warningDark = Color(0xFFE0BC8F);
  static const Color errorLight = Color(0xFFC47A7A);
  static const Color errorDark = Color(0xFFD89898);
  static const Color infoLight = Color(0xFF7A9CB8);
  static const Color infoDark = Color(0xFF94B0C9);
  static const Color destructiveLight = Color(0xFFC87070);
  static const Color destructiveDark = Color(0xFFD89090);

  // === Highlight (annotations) ===
  static const Color highlightYellowLight = Color(0xFFE8D890);
  static const Color highlightYellowDark = Color(0xFFB3A657);
  static const Color highlightPinkLight = Color(0xFFF5B8C0);
  static const Color highlightPinkDark = Color(0xFFB37782);
  static const Color highlightRedLight = Color(0xFFD09898);
  static const Color highlightRedDark = Color(0xFFB37272);
  static const Color highlightBlueLight = Color(0xFF90B0D0);
  static const Color highlightBlueDark = Color(0xFF6B8BA8);
  static const Color highlightGreenLight = Color(0xFF98C8A0);
  static const Color highlightGreenDark = Color(0xFF7A9C72);
  static const Color highlightPurpleLight = Color(0xFFB898C8);
  static const Color highlightPurpleDark = Color(0xFF8970A3);

  // === Adaptive helpers (use within build context) ===
  static Color background(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? backgroundDark : backgroundLight;
  static Color card(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? cardDark : cardLight;
  static Color elevated(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? elevatedDark : elevatedLight;
  static Color primaryText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? primaryTextDark : primaryTextLight;
  static Color secondaryText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? secondaryTextDark : secondaryTextLight;
  static Color tertiaryText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? tertiaryTextDark : tertiaryTextLight;
  static Color sage(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? sageDark : sageLight;
  static Color divider(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dividerDark : dividerLight;
  static Color success(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? successDark : successLight;
  static Color warning(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? warningDark : warningLight;
  static Color error(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? errorDark : errorLight;
  static Color info(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? infoDark : infoLight;
}
