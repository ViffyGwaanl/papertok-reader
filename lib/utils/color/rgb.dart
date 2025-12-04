import 'package:flutter/material.dart';

/// Ensure value is RGB (strips any alpha component).
int sanitizeRgb(int value) => value & 0x00FFFFFF;

/// Convert RGB int to Color with full alpha.
Color colorFromRgb(int rgb) => Color(0xFF000000 | sanitizeRgb(rgb));

/// Extract RGB component from a Color.
int rgbFromColor(Color color) => color.toARGB32() & 0x00FFFFFF;
