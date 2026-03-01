import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A lightweight, chat-friendly collapsible section.
///
/// We keep this separate from [ExpansionTile] to have full control over padding,
/// density, and visual styling (Cherry-like readability, but our own style).
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

class _AiCollapsibleSectionState extends State<AiCollapsibleSection>
    with SingleTickerProviderStateMixin {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final header = Row(
      children: [
        if (widget.leading != null) ...[
          IconTheme(
            data: theme.iconTheme.copyWith(size: 16),
            child: widget.leading!,
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: theme.textTheme.labelLarge),
              if ((widget.subtitle ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    widget.subtitle!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (!_expanded && (widget.preview ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    widget.preview!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if ((widget.copyText ?? '').isNotEmpty)
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy, size: 16),
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
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    return FilledContainer(
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: header,
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: widget.child,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
