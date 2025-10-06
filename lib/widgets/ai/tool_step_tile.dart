import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:anx_reader/widgets/common/container/outlined_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ToolStepTile extends StatefulWidget {
  const ToolStepTile({
    super.key,
    required this.step,
  });

  final ParsedToolStep step;

  @override
  State<ToolStepTile> createState() => _ToolStepTileState();
}

class _ToolStepTileState extends State<ToolStepTile> {
  bool _expanded = false;

  Color _statusColor(String status, ThemeData theme) {
    switch (status) {
      case 'success':
        return Colors.green;
      case 'failed':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(widget.step.status, theme);

    return OutlinedContainer(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      radius: 14,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.build, size: 12),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.step.name,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 6),
              if (widget.step.input != null)
                _ExpandableField(
                  label: 'Input',
                  value: widget.step.input!,
                ),
              if (widget.step.output != null)
                _ExpandableField(
                  label: 'Output',
                  value: widget.step.output!,
                ),
              if (widget.step.error != null)
                _ExpandableField(
                  label: 'Error',
                  value: widget.step.error!,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExpandableField extends StatelessWidget {
  const _ExpandableField({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.labelMedium)),
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy, size: 12),
              onPressed: () => Clipboard.setData(ClipboardData(text: value)),
            ),
          ],
        ),
        FilledContainer(
          color: theme.colorScheme.surfaceVariant,
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          radius: 6,
          child: SelectableText(
            value,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
