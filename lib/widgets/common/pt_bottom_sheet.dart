import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/claude_palette.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_motion.dart';

/// Apple/Claude-style grouped modal sheet.
///
/// Wraps content in a rounded Morandi-surface container with a grabber
/// handle, optional title/subtitle header, and a safe-area aware body.
/// Replaces raw `showModalBottomSheet` call sites across the app.
class PTBottomSheet extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const PTBottomSheet({
    super.key,
    this.title,
    this.subtitle,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.sm,
      AppSpacing.lg,
      AppSpacing.lg,
    ),
  });

  /// Present this sheet using the standard Morandi styling.
  static Future<T?> show<T>(
    BuildContext context, {
    String? title,
    String? subtitle,
    required WidgetBuilder builder,
    bool isScrollControlled = true,
    bool useRootNavigator = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useRootNavigator: useRootNavigator,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (ctx) => PTBottomSheet(
        title: title,
        subtitle: subtitle,
        child: Builder(builder: builder),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasHeader = title != null || subtitle != null;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm)
            .copyWith(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color: ClaudePalette.card(context),
          borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusLarge),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: ClaudePalette.divider(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (hasHeader) ...[
              const SizedBox(height: AppSpacing.md),
              if (title != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg),
                  child: Text(
                    title!,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: ClaudePalette.fg(context),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, 4, AppSpacing.lg, 0),
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color: ClaudePalette.secondary(context),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
            Flexible(
              child: Padding(padding: padding, child: child),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single tap-selectable row inside a PTBottomSheet picker.
class PTPickerRow<T> extends StatelessWidget {
  final T value;
  final T? groupValue;
  final String title;
  final String? subtitle;
  final IconData? leading;
  final ValueChanged<T> onChanged;

  const PTPickerRow({
    super.key,
    required this.value,
    required this.groupValue,
    required this.title,
    this.subtitle,
    this.leading,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadius),
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(value);
        },
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.easeOut,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? ClaudePalette.accentTint(context)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.cornerRadius),
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                Icon(
                  leading,
                  size: 20,
                  color: selected
                      ? ClaudePalette.accent(context)
                      : ClaudePalette.secondary(context),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
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
                            color: ClaudePalette.secondary(context),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_rounded,
                  size: 20,
                  color: ClaudePalette.accent(context),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
