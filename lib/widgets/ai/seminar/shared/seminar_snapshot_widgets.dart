import 'package:flutter/material.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/ai/seminar/seminar_expandable_text.dart';

class SeminarSnapshotHeading extends StatelessWidget {
  const SeminarSnapshotHeading(this.icon, this.label, {super.key});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: ClaudePalette.secondary(context)),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: ClaudePalette.secondary(context),
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }
}

class SeminarSnapshotMissingSourceChip extends StatelessWidget {
  const SeminarSnapshotMissingSourceChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SeminarSnapshotTinyChip(label);
  }
}

class SeminarSnapshotLabeledTinyChip extends StatelessWidget {
  const SeminarSnapshotLabeledTinyChip({
    required this.label,
    required this.value,
    super.key,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SeminarSnapshotLabelText(label),
        SeminarSnapshotTinyChip(value),
      ],
    );
  }
}

class SeminarSnapshotLabelText extends StatelessWidget {
  const SeminarSnapshotLabelText(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: ClaudePalette.secondary(context),
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class SeminarSnapshotDetailLabel extends StatelessWidget {
  const SeminarSnapshotDetailLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: ClaudePalette.secondary(context),
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class SeminarSnapshotTinyChip extends StatelessWidget {
  const SeminarSnapshotTinyChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context)
            .colorScheme
            .secondaryContainer
            .withValues(alpha: 0.62),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: ClaudePalette.fg(context),
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class SeminarSnapshotExpandableText extends StatelessWidget {
  const SeminarSnapshotExpandableText(
    this.text, {
    this.collapsedMaxLines = 3,
    this.style,
    super.key,
  });

  final String text;
  final int collapsedMaxLines;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final zh =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';
    return SeminarExpandableText(
      text: text,
      collapsedMaxLines: collapsedMaxLines,
      expandLabel: zh ? '展开全文' : 'Expand',
      collapseLabel: zh ? '收起' : 'Collapse',
      evidenceLabelBuilder: (number) => zh ? '证据$number' : 'Evidence $number',
      style: style,
    );
  }
}

class SeminarMetaChipData {
  const SeminarMetaChipData({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;
}

class SeminarMetaChips extends StatelessWidget {
  const SeminarMetaChips({
    required this.chips,
    super.key,
  });

  final List<SeminarMetaChipData> chips;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final chip in chips)
          SeminarMetaChip(
            icon: chip.icon,
            label: chip.label,
          ),
      ],
    );
  }
}

class SeminarMetaChip extends StatelessWidget {
  const SeminarMetaChip({
    required this.icon,
    required this.label,
    super.key,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: ClaudePalette.accentTint(context),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: ClaudePalette.accent(context),
          ),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.52,
            ),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: ClaudePalette.fg(context),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
