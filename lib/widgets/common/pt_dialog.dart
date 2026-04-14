import 'package:flutter/material.dart';
import '../../theme/claude_palette.dart';
import '../../theme/morandi_palette.dart';
import '../../theme/app_spacing.dart';

/// Apple/Claude-style alert dialog on a Morandi surface.
///
/// Wraps `showDialog` + a custom `Dialog` so every app-level alert shares
/// the same rounded card, typography and button styling. Use this instead
/// of raw `AlertDialog` to keep the warm neutral look consistent.
class PTDialog extends StatelessWidget {
  final String? title;
  final Widget? content;
  final String? message;
  final List<Widget> actions;

  const PTDialog({
    super.key,
    this.title,
    this.content,
    this.message,
    this.actions = const [],
  });

  static Future<T?> show<T>(
    BuildContext context, {
    String? title,
    String? message,
    Widget? content,
    List<Widget> actions = const [],
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => PTDialog(
        title: title,
        message: message,
        content: content,
        actions: actions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: ClaudePalette.card(context),
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusLarge),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
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
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  message!,
                  style: TextStyle(
                    fontSize: 14,
                    color: ClaudePalette.secondary(context),
                    height: 1.35,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            if (content != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: content!,
              ),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (int i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      actions[i],
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Standard Morandi text button for dialogs. Use `destructive: true` for
/// delete/cancel confirmations (renders in the Morandi destructive hue).
class PTDialogAction extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isDefault;
  final bool destructive;

  const PTDialogAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.isDefault = false,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? MorandiPalette.destructive(context)
        : ClaudePalette.accent(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        textStyle: TextStyle(
          fontSize: 15,
          fontWeight: isDefault ? FontWeight.w600 : FontWeight.w500,
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: Text(label),
    );
  }
}
