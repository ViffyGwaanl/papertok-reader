import 'package:flutter/material.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_elevation.dart';
import '../../theme/claude_palette.dart';

/// PaperTok card container — Morandi-themed elevated surface.
class PTCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final int elevation;
  final VoidCallback? onTap;

  const PTCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.elevation = 1,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final shadows = elevation == 1
        ? AppElevation.level1(context)
        : elevation == 2
            ? AppElevation.level2(context)
            : elevation == 3
                ? AppElevation.level3(context)
                : AppElevation.level4(context);

    final container = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: ClaudePalette.card(context),
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadius),
        boxShadow: shadows,
      ),
      child: child,
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.cornerRadius),
          child: container,
        ),
      );
    }
    return container;
  }
}
