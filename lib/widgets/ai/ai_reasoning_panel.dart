import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:flutter/material.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/widgets/ai/tool_step_tile.dart';

class ReasoningPanel extends StatelessWidget {
  const ReasoningPanel({
    super.key,
    required this.timeline,
    required this.expanded,
    required this.onToggle,
    this.streaming = false,
    this.margin = const EdgeInsets.only(bottom: 8.0),
  });

  final List<ParsedReasoningEntry> timeline;
  final bool expanded;
  final bool streaming;
  final VoidCallback onToggle;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      streaming
                          ? L10n.of(context).aiReasoningThinking
                          : L10n.of(context).aiReasoningTitle,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _ReasoningTimeline(timeline: timeline),
            ),
        ],
      ),
    );
  }
}

class _ReasoningTimeline extends StatelessWidget {
  const _ReasoningTimeline({required this.timeline});

  final List<ParsedReasoningEntry> timeline;

  @override
  Widget build(BuildContext context) {
    if (timeline.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final children = <Widget>[];
    for (var i = 0; i < timeline.length; i++) {
      final entry = timeline[i];
      if (entry.isThink && entry.text != null && entry.text!.isNotEmpty) {
        children.add(
          SelectableText(
            entry.text!,
            style: theme.textTheme.bodyMedium,
          ),
        );
      } else if (entry.isToolStep && entry.toolStep != null) {
        children.add(ToolStepTile(step: entry.toolStep!));
      }

      if (i != timeline.length - 1) {
        children.add(const SizedBox(height: 12));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
