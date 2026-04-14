import 'package:anx_reader/theme/claude_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Claude-style grouped settings section: optional header + Card containing
/// monochrome rows separated by hairline dividers.
class SettingsSectionCard extends StatelessWidget {
  final String? title;
  final String? footer;
  final List<Widget> tiles;
  final EdgeInsetsGeometry margin;

  const SettingsSectionCard({
    super.key,
    this.title,
    this.footer,
    required this.tiles,
    this.margin = const EdgeInsets.fromLTRB(16, 16, 16, 0),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Text(
                title!.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 0.6,
                  color: ClaudePalette.secondary(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: ClaudePalette.card(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: _interleaveDividers(context),
            ),
          ),
          if (footer != null) ...[
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8, right: 16),
              child: Text(
                footer!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: ClaudePalette.secondary(context),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _interleaveDividers(BuildContext context) {
    final result = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      result.add(tiles[i]);
      if (i < tiles.length - 1) {
        result.add(Padding(
          padding: const EdgeInsets.only(left: 50),
          child: Divider(
            height: 1,
            thickness: 0.5,
            color: ClaudePalette.divider(context),
          ),
        ));
      }
    }
    return result;
  }
}

/// A Claude-style navigation row: monochrome glyph, title, optional subtitle,
/// chevron. The legacy 29x29 colored tint square has been removed.
class SettingsNavRow extends StatelessWidget {
  final IconData icon;

  /// Deprecated: kept for backwards compatibility. Ignored visually — Claude
  /// rows are monochrome.
  final Color? tint;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const SettingsNavRow({
    super.key,
    required this.icon,
    this.tint,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 22, color: ClaudePalette.fg(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      color: ClaudePalette.fg(context),
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: TextStyle(
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
            Icon(
              Icons.chevron_right,
              size: 22,
              color: ClaudePalette.tertiary(context),
            ),
          ],
        ),
      ),
    );
  }
}
