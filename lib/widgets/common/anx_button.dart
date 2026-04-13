import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_spacing.dart';
import '../../theme/morandi_palette.dart';

enum AnxButtonType { filled, outlined, text }

class AnxButton extends StatelessWidget {
  const AnxButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.disabled = false,
    this.isLoading = false,
    this.type = AnxButtonType.filled,
    this.style,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.clipBehavior = Clip.none,
  })  : icon = null,
        label = null;

  const AnxButton.icon({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.disabled = false,
    this.isLoading = false,
    this.type = AnxButtonType.filled,
    this.style,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.clipBehavior = Clip.none,
  }) : child = null;

  const AnxButton.text({
    super.key,
    required this.onPressed,
    required this.child,
    this.disabled = false,
    this.isLoading = false,
    this.style,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.clipBehavior = Clip.none,
  })  : icon = null,
        label = null,
        type = AnxButtonType.text;

  const AnxButton.outlined({
    super.key,
    required this.onPressed,
    required this.child,
    this.disabled = false,
    this.isLoading = false,
    this.style,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.clipBehavior = Clip.none,
  })  : icon = null,
        label = null,
        type = AnxButtonType.outlined;

  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onHover;
  final ValueChanged<bool>? onFocusChange;
  final ButtonStyle? style;
  final FocusNode? focusNode;
  final bool autofocus;
  final Clip clipBehavior;
  final Widget? child;
  final Widget? icon;
  final Widget? label;
  final bool disabled;
  final bool isLoading;
  final AnxButtonType type;

  /// Build a token-driven default style merged beneath any user-provided [style].
  ButtonStyle _effectiveStyle(BuildContext context) {
    final sage = MorandiPalette.sage(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusSmall),
    );
    final padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    );

    ButtonStyle base;
    switch (type) {
      case AnxButtonType.filled:
        base = FilledButton.styleFrom(
          backgroundColor: sage,
          foregroundColor: Colors.white,
          padding: padding,
          shape: shape,
        );
        break;
      case AnxButtonType.outlined:
        base = OutlinedButton.styleFrom(
          foregroundColor: sage,
          side: BorderSide(color: sage),
          padding: padding,
          shape: shape,
        );
        break;
      case AnxButtonType.text:
        base = TextButton.styleFrom(
          foregroundColor: sage,
          padding: padding,
          shape: shape,
        );
        break;
    }
    return style == null ? base : base.merge(style!);
  }

  Widget _spinner(BuildContext context, {double size = 20}) {
    final color = type == AnxButtonType.filled
        ? Colors.white
        : MorandiPalette.sage(context);
    return SizedBox(
      key: const ValueKey('anx-button-spinner'),
      width: size,
      height: size,
      child: CircularProgressIndicator(strokeWidth: 2, color: color),
    );
  }

  Widget _fadeSwap({required Widget child}) {
    return AnimatedSwitcher(
      duration: AppMotion.fast,
      switchInCurve: AppMotion.easeInOut,
      switchOutCurve: AppMotion.easeInOut,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ButtonStyle effectiveStyle = _effectiveStyle(context);
    final VoidCallback? effectiveOnPressed =
        (disabled || isLoading) ? null : onPressed;
    final VoidCallback? effectiveOnLongPress =
        (disabled || isLoading) ? null : onLongPress;

    Widget buttonContent;

    if (isLoading) {
      buttonContent = _spinner(context, size: 24);
    } else {
      buttonContent = KeyedSubtree(
        key: const ValueKey('anx-button-content'),
        child: child ?? const SizedBox(),
      );
    }

    // Helper to build the specific button widget
    Widget buildButton({required Widget child}) {
      switch (type) {
        case AnxButtonType.filled:
          return FilledButton(
            onPressed: effectiveOnPressed,
            onLongPress: effectiveOnLongPress,
            onHover: onHover,
            onFocusChange: onFocusChange,
            style: effectiveStyle,
            focusNode: focusNode,
            autofocus: autofocus,
            clipBehavior: clipBehavior,
            child: child,
          );
        case AnxButtonType.outlined:
          return OutlinedButton(
            onPressed: effectiveOnPressed,
            onLongPress: effectiveOnLongPress,
            onHover: onHover,
            onFocusChange: onFocusChange,
            style: effectiveStyle,
            focusNode: focusNode,
            autofocus: autofocus,
            clipBehavior: clipBehavior,
            child: child,
          );
        case AnxButtonType.text:
          return TextButton(
            onPressed: effectiveOnPressed,
            onLongPress: effectiveOnLongPress,
            onHover: onHover,
            onFocusChange: onFocusChange,
            style: effectiveStyle,
            focusNode: focusNode,
            autofocus: autofocus,
            clipBehavior: clipBehavior,
            child: child,
          );
      }
    }

    // Handle Icon constructors
    if (icon != null && label != null) {
      Widget iconToUse = _fadeSwap(
        child: isLoading
            ? _spinner(context, size: 16)
            : KeyedSubtree(
                key: const ValueKey('anx-button-icon'),
                child: icon!,
              ),
      );

      switch (type) {
        case AnxButtonType.filled:
          return FilledButton.icon(
            onPressed: effectiveOnPressed,
            onLongPress: effectiveOnLongPress,
            onHover: onHover,
            onFocusChange: onFocusChange,
            style: effectiveStyle,
            focusNode: focusNode,
            autofocus: autofocus,
            clipBehavior: clipBehavior,
            icon: iconToUse,
            label: label!,
          );
        case AnxButtonType.outlined:
          return OutlinedButton.icon(
            onPressed: effectiveOnPressed,
            onLongPress: effectiveOnLongPress,
            onHover: onHover,
            onFocusChange: onFocusChange,
            style: effectiveStyle,
            focusNode: focusNode,
            autofocus: autofocus,
            clipBehavior: clipBehavior,
            icon: iconToUse,
            label: label!,
          );
        case AnxButtonType.text:
          return TextButton.icon(
            onPressed: effectiveOnPressed,
            onLongPress: effectiveOnLongPress,
            onHover: onHover,
            onFocusChange: onFocusChange,
            style: effectiveStyle,
            focusNode: focusNode,
            autofocus: autofocus,
            clipBehavior: clipBehavior,
            icon: iconToUse,
            label: label!,
          );
      }
    }

    // Non-icon constructors: wrap content in an AnimatedSwitcher so the
    // transition between loading spinner and child content fades smoothly.
    return buildButton(child: _fadeSwap(child: buttonContent));
  }
}
