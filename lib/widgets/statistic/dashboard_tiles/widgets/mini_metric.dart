import 'package:anx_reader/theme/claude_palette.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: ClaudePalette.secondary(context)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: ClaudePalette.secondary(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value.toString(),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: ClaudePalette.fg(context),
                height: 1.1,
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
