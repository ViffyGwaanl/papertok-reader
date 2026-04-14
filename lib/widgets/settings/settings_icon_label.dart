import 'package:anx_reader/theme/claude_palette.dart';
import 'package:flutter/material.dart';

/// Claude-style settings icon + title row.
///
/// Renders a monochrome glyph in the foreground color followed by a title
/// (and optional subtitle). The legacy 29x29 colored tint square has been
/// removed in favor of Claude's flat monochrome design.
class SettingsIconLabel extends StatelessWidget {
  final String title;
  final IconData icon;

  /// Deprecated: kept for backwards compatibility with callers that still pass
  /// a tint color. The value is ignored — Claude rows are monochrome.
  final Color? tint;
  final String? subtitle;

  const SettingsIconLabel({
    super.key,
    required this.title,
    required this.icon,
    this.tint,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 22, color: ClaudePalette.fg(context)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 16,
                  color: ClaudePalette.fg(context),
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: ClaudePalette.tertiary(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// Deprecated: Claude monochrome design. Kept for backwards compatibility.
/// Warm Morandi tint palette for Settings icons. No longer used for rendering
/// — rows are now monochrome — but the constants remain so existing imports
/// continue to compile.
class SettingsIconTints {
  SettingsIconTints._();
  // AI / Assistant
  static const Color sparkles = Color(0xFFC0A890); // clay
  static const Color tools    = Color(0xFFB0A498); // taupe
  static const Color prompt   = Color(0xFFC4A4A0); // dusty rose
  static const Color network  = Color(0xFFA0B8C8); // powder
  // Reading
  static const Color reading  = Color(0xFFC4A4A0); // dusty rose
  static const Color kairos   = Color(0xFFC0A890); // clay
  static const Color translate = Color(0xFFA0B8C8); // powder
  // Data
  static const Color sync     = Color(0xFF8FA68A); // sage
  static const Color storage  = Color(0xFFA8A098); // warm gray
  // Customization
  static const Color appearance = Color(0xFF98A890); // moss
  static const Color homeNav  = Color(0xFF8FA68A); // sage
  // Other
  static const Color about    = Color(0xFFA8A098); // warm gray
  static const Color tts      = Color(0xFFB8A8C8); // muted lavender
  static const Color advanced = Color(0xFFB0A498); // taupe
  static const Color memory   = Color(0xFF98A890); // moss
}
