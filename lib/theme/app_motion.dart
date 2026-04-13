import 'package:flutter/material.dart';

/// Animation timings and curves ported from swift-native.
/// Use these for ALL transitions to ensure consistency.
class AppMotion {
  AppMotion._();

  // === Durations ===
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 350);

  // === Curves ===
  static const Curve easeOut = Curves.easeOut;
  static const Curve easeInOut = Curves.easeInOut;
  static const Curve spring = Curves.easeOutBack;
  static const Curve smoothSpring = Cubic(0.25, 0.46, 0.45, 0.94);
}
