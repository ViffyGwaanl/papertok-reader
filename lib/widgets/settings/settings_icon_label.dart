import 'package:flutter/material.dart';

/// Apple Settings-style icon + title row.
/// Renders a 29x29 tinted rounded square with a white icon, then a title (and optional subtitle).
class SettingsIconLabel extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color tint;
  final String? subtitle;

  const SettingsIconLabel({
    super.key,
    required this.title,
    required this.icon,
    required this.tint,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 29,
          height: 29,
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(7),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: Colors.white, size: 16),
        ),
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
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
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

/// Warm Morandi tint palette for Settings icons. Intentionally narrow —
/// desaturated earthy neutrals keep the settings feel calm and Claude-like
/// instead of iOS rainbow.
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
