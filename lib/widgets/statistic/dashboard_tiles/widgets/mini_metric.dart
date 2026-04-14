import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:flutter/material.dart';

class DashboardMiniMetric extends StatelessWidget {
  const DashboardMiniMetric({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    this.trailingBadge,
  });

  final int value;
  final String label;
  final IconData icon;

  /// Optional small accent-colored badge text (e.g. "0.8%").
  final String? trailingBadge;

  @override
  Widget build(BuildContext context) {
    // Extract leading non-digit label (e.g. "天") and number from localized strings.
    final rawLabel = label;
    final numericPart = rawLabel.replaceAll(RegExp(r'[^0-9]'), '');
    final unitPart = rawLabel.replaceAll(RegExp(r'[0-9\s]'), '').trim();
    final hasEmbeddedNumber = numericPart.isNotEmpty;
    final displayNumber = hasEmbeddedNumber ? numericPart : value.toString();
    final displayUnit = hasEmbeddedNumber ? unitPart : rawLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: ClaudePalette.secondary(context)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                displayUnit.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.4,
                  color: ClaudePalette.secondary(context),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              displayNumber,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: ClaudePalette.fg(context),
                height: 1.05,
                letterSpacing: -0.3,
              ),
            ),
            if (trailingBadge != null) ...[
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  trailingBadge!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: ClaudePalette.accent(context),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
