import 'package:flutter/material.dart';

/// Shadow elevation system ported from swift-native AppElevation.
class AppElevation {
  AppElevation._();

  static List<BoxShadow> level1(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withOpacity(isDark ? 0.30 : 0.08),
        blurRadius: 4,
        offset: const Offset(0, 2),
      ),
    ];
  }

  static List<BoxShadow> level2(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withOpacity(isDark ? 0.35 : 0.10),
        blurRadius: 8,
        offset: const Offset(0, 4),
      ),
    ];
  }

  static List<BoxShadow> level3(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withOpacity(isDark ? 0.40 : 0.12),
        blurRadius: 16,
        offset: const Offset(0, 8),
      ),
    ];
  }

  static List<BoxShadow> level4(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withOpacity(isDark ? 0.50 : 0.15),
        blurRadius: 24,
        offset: const Offset(0, 12),
      ),
    ];
  }
}
