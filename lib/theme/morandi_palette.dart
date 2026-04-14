import 'package:flutter/material.dart';

/// Claude design palette — warm cream + warm dark, terracotta accent.
/// This class is named `MorandiPalette` for backwards compatibility but the
/// hex values are the Claude app tokens:
///   light: bg #F9F9F7  fg #2D2D2B
///   dark:  bg #2D2D2B  fg #F9F9F7
///   accent #CC7D5E (Claude terracotta)
/// Adaptive helpers below resolve light/dark per BuildContext.
class MorandiPalette {
  MorandiPalette._();

  // === Surfaces ===
  // Light: F9F9F7 base, FFFFFF cards, F3F2EE grouped/elevated.
  static const Color backgroundLight = Color(0xFFF9F9F7);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color elevatedLight = Color(0xFFF3F2EE);
  // Dark: 2D2D2B base, 363633 cards, 333331 elevated. Warm near-black.
  static const Color backgroundDark = Color(0xFF2D2D2B);
  static const Color cardDark = Color(0xFF363633);
  static const Color elevatedDark = Color(0xFF333331);

  // === Text ===
  static const Color primaryTextLight = Color(0xFF2D2D2B);
  static const Color primaryTextDark = Color(0xFFF9F9F7);
  static const Color secondaryTextLight = Color(0xFF6E6E6A);
  static const Color secondaryTextDark = Color(0xFFB8B6AE);
  static const Color tertiaryTextLight = Color(0xFF9A9994);
  static const Color tertiaryTextDark = Color(0xFF8A8881);

  // === Accent palette ===
  // sage helper now resolves to Claude terracotta so existing call sites
  // (which use MorandiPalette.sage(context) as the brand accent) inherit
  // the new color without touching every caller.
  static const Color sageLight = Color(0xFFCC7D5E);
  static const Color sageDark = Color(0xFFD68E70);
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
  static const Color dividerLight = Color(0xFFE8E5DF);
  static const Color dividerDark = Color(0xFF45443F);
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
  static Color destructive(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? destructiveDark
          : destructiveLight;
  static Color dustyRose(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? dustyRoseDark
          : dustyRoseLight;
  static Color clay(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? clayDark : clayLight;
  static Color taupe(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? taupeDark : taupeLight;
  static Color stone(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? stoneDark : stoneLight;
  static Color warmGray(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? warmGrayDark
          : warmGrayLight;
  static Color moss(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? mossDark : mossLight;
  static Color powder(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? powderDark
          : powderLight;
  static Color lavender(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? lavenderDark
          : lavenderLight;
  static Color mauve(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? mauveDark : mauveLight;
  static Color sand(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? sandDark : sandLight;
  static Color mist(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? mistDark : mistLight;
}
