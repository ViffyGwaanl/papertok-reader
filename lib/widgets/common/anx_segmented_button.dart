import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/claude_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Defines a single segment item used by [AnxSegmentedButton].
class SegmentButtonItem<T> {
  const SegmentButtonItem({
    required this.value,
    required this.label,
    this.icon,
    this.labelStyle,
    this.maxLines,
    this.overflow,
  });

  final T value;
  final String label;
  final Widget? icon;
  final TextStyle? labelStyle;
  final int? maxLines;
  final TextOverflow? overflow;
}

/// A custom segmented picker rendered with Claude design tokens.
///
/// This intentionally does NOT delegate to Material's [SegmentedButton]
/// so it is immune to custom seed-color overrides (some users pick a
/// blue theme color which leaks into M3 `SegmentedButton`). The
/// selected tile always uses [ClaudePalette.accentTint] + accent.
class AnxSegmentedButton<T> extends StatelessWidget {
  const AnxSegmentedButton({
    super.key,
    required this.segments,
    required this.selected,
    this.onSelectionChanged,
    this.multiSelectionEnabled = false,
    this.emptySelectionAllowed = false,
    this.showSelectedIcon = true,
    this.enabled = true,
    this.style,
  });

  final List<SegmentButtonItem<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>>? onSelectionChanged;
  final bool multiSelectionEnabled;
  final bool emptySelectionAllowed;
  final bool showSelectedIcon;
  // Accepted for backwards compatibility but no longer wired to Material.
  final ButtonStyle? style;
  final bool enabled;

  void _handleTap(T value) {
    if (!enabled) return;
    HapticFeedback.selectionClick();
    final cb = onSelectionChanged;
    if (cb == null) return;

    final Set<T> next;
    if (multiSelectionEnabled) {
      next = Set<T>.from(selected);
      if (next.contains(value)) {
        if (next.length > 1 || emptySelectionAllowed) {
          next.remove(value);
        }
      } else {
        next.add(value);
      }
    } else {
      if (selected.contains(value)) {
        if (emptySelectionAllowed) {
          next = <T>{};
        } else {
          next = {value};
        }
      } else {
        next = {value};
      }
    }
    cb(next);
  }

  @override
  Widget build(BuildContext context) {
    final accent = ClaudePalette.accent(context);
    final accentTint = ClaudePalette.accentTint(context);
    final secondary = ClaudePalette.secondary(context);
    final divider = ClaudePalette.divider(context);
    final elevated = ClaudePalette.elevated(context);

    const double radius = AppSpacing.cornerRadius;

    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Container(
        decoration: BoxDecoration(
          color: elevated,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: divider, width: 0.5),
        ),
        padding: const EdgeInsets.all(3),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: segments.map((segment) {
                final isSelected = selected.contains(segment.value);
                final fg = isSelected ? accent : secondary;
                return Expanded(
                  child: _SegmentTile(
                    onTap: () => _handleTap(segment.value),
                    background:
                        isSelected ? accentTint : Colors.transparent,
                    radius: radius - 3,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (segment.icon != null) ...[
                            IconTheme.merge(
                              data: IconThemeData(color: fg, size: 16),
                              child: DefaultTextStyle.merge(
                                style: TextStyle(
                                  color: fg,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                child: segment.icon!,
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              segment.label,
                              softWrap: false,
                              maxLines: segment.maxLines ?? 1,
                              overflow:
                                  segment.overflow ?? TextOverflow.fade,
                              style: (segment.labelStyle ??
                                      const TextStyle())
                                  .copyWith(
                                color: fg,
                                fontSize: segment.labelStyle?.fontSize ?? 13,
                                fontWeight: segment.labelStyle?.fontWeight ??
                                    (isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w500),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}

class _SegmentTile extends StatelessWidget {
  const _SegmentTile({
    required this.onTap,
    required this.background,
    required this.radius,
    required this.child,
  });

  final VoidCallback onTap;
  final Color background;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }
}
