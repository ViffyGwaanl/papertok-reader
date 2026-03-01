import 'package:anx_reader/widgets/common/container/outlined_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A chat-friendly collapsible section.
///
/// Design goal: magazine-style appendix / margin note.
/// Keep it calm and readable; avoid looking like a default ExpansionTile.
class AiCollapsibleSection extends StatefulWidget {
  const AiCollapsibleSection({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.preview,
    this.copyText,
    this.initiallyExpanded = false,
    required this.child,
  });

  final String title;

  /// Short meta text shown next to the title (e.g. count).
  final String? subtitle;

  final Widget? leading;

  /// Optional one-line preview shown when collapsed.
  final String? preview;

  /// If provided, shows a copy button in the header.
  final String? copyText;

  final bool initiallyExpanded;
  final Widget child;

  @override
  State<AiCollapsibleSection> createState() => _AiCollapsibleSectionState();
}

class _AiCollapsibleSectionState extends State<AiCollapsibleSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
    });
  }

  Widget _buildTitleBadge(ThemeData theme) {
    final bg = theme.colorScheme.surface;
    final fg = theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.leading != null) ...[
            IconTheme(
              data: theme.iconTheme.copyWith(size: 14, color: fg),
              child: widget.leading!,
            ),
            const SizedBox(width: 6),
          ],
          Text(
            widget.title,
            style: theme.textTheme.labelLarge?.copyWith(
              letterSpacing: 0.2,
              color: fg,
            ),
          ),
          if ((widget.subtitle ?? '').trim().isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              widget.subtitle!.trim(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: fg,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final paperBg = Color.alphaBlend(
      theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.85),
      theme.colorScheme.surface,
    );

    final stripeColor = theme.colorScheme.tertiary.withValues(alpha: 0.55);

    return OutlinedContainer(
      radius: 16,
      outlineColor: theme.colorScheme.outlineVariant,
      color: paperBg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Margin-note stripe.
          Container(
            width: 3,
            height: _expanded ? 42 : 28,
            margin: const EdgeInsets.only(top: 2, right: 10),
            decoration: BoxDecoration(
              color: stripeColor,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _toggle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          _buildTitleBadge(theme),
                          const Spacer(),
                          if ((widget.copyText ?? '').isNotEmpty)
                            IconButton(
                              tooltip: 'Copy',
                              icon: Icon(
                                Icons.copy,
                                size: 16,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              onPressed: () => Clipboard.setData(
                                ClipboardData(text: widget.copyText!),
                              ),
                            ),
                          AnimatedRotation(
                            turns: _expanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeOut,
                            child: Icon(
                              Icons.expand_more,
                              size: 20,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!_expanded && (widget.preview ?? '').trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      widget.preview!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.3,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: _expanded
                      ? Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Divider(
                                height: 18,
                                color: theme.colorScheme.outlineVariant,
                              ),
                              widget.child,
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
