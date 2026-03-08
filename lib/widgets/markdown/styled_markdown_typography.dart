import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

class StyledMarkdownTypography {
  const StyledMarkdownTypography._();

  static const double bodyHeight = 1.55;
  static const double codeHeight = 1.45;
  static const double codeScale = 0.95;

  static TextStyle baseBodyStyle(ThemeData theme) {
    final body = theme.textTheme.bodyMedium;
    return (body ?? const TextStyle()).copyWith(
      fontSize: body?.fontSize ?? 14,
      height: bodyHeight,
    );
  }

  static TextStyle scaledStyle(TextStyle style, TextScaler scaler) {
    return style.copyWith(
      fontSize: style.fontSize == null ? null : scaler.scale(style.fontSize!),
      letterSpacing: style.letterSpacing == null
          ? null
          : scaler.scale(style.letterSpacing!),
    );
  }

  static TextStyle codeStyle(TextStyle bodyStyle) {
    return bodyStyle.copyWith(
      fontFamily: 'JetBrainsMono',
      package: 'gpt_markdown',
      fontSize: (bodyStyle.fontSize ?? 14) * codeScale,
      height: codeHeight,
    );
  }

  static GptMarkdownThemeData markdownTheme({
    required Brightness brightness,
    required TextStyle bodyStyle,
  }) {
    TextStyle heading(double factor, FontWeight weight, double height) {
      final baseSize = bodyStyle.fontSize ?? 14;
      return bodyStyle.copyWith(
        fontSize: baseSize * factor,
        fontWeight: weight,
        height: height,
      );
    }

    return GptMarkdownThemeData(
      brightness: brightness,
      h1: heading(1.34, FontWeight.w700, 1.32),
      h2: heading(1.26, FontWeight.w700, 1.34),
      h3: heading(1.18, FontWeight.w600, 1.36),
      h4: heading(1.12, FontWeight.w600, 1.38),
      h5: heading(1.06, FontWeight.w600, 1.40),
      h6: heading(1.00, FontWeight.w600, 1.42),
    );
  }
}
