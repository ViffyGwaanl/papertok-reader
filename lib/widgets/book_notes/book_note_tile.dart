import 'package:papertok_reader/constants/note_annotations.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/book_note.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/utils/time_to_human.dart';
import 'package:papertok_reader/widgets/common/container/filled_container.dart';
import 'package:papertok_reader/widgets/knowledge/source_ref_evidence_list.dart';
import 'package:flutter/material.dart';

class BookNoteTile extends StatelessWidget {
  const BookNoteTile({
    super.key,
    required this.note,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.backgroundColor,
    this.margin = const EdgeInsets.only(bottom: 8),
    this.sourceTitle,
    this.showSourceAudit = true,
  });

  final BookNote note;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final Color? backgroundColor;
  final EdgeInsetsGeometry margin;
  final String? sourceTitle;
  final bool showSourceAudit;

  Icon _buildIcon(Color color) {
    final match = notesType.where((option) => option.type == note.type);
    if (match.isNotEmpty) {
      return Icon(match.first.icon, color: color);
    }
    return Icon(Icons.bookmark, color: color);
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = Color(int.tryParse('0xaa${note.color}') ?? 0xaa555555);
    final infoStyle = TextStyle(
      fontSize: 14,
      color: ClaudePalette.secondary(context),
    );
    final sourceRef = showSourceAudit
        ? BookNoteSourceRefAdapter.fromBookNote(
            note,
            sourceTitle: sourceTitle,
          )
        : null;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTap: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: FilledContainer(
        color: backgroundColor,
        padding: const EdgeInsets.all(8.0),
        margin: margin,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 10, right: 10, top: 10),
              child: _buildIcon(iconColor),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.content,
                    style: const TextStyle(
                      fontSize: 16,
                    ),
                  ),
                  if (note.readerNote != null && note.readerNote!.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 4),
                        IntrinsicHeight(
                          child: Row(
                            children: [
                              const VerticalDivider(
                                thickness: 3,
                              ),
                              Expanded(
                                child: Text(
                                  note.readerNote!,
                                  style: infoStyle.copyWith(
                                    color: ClaudePalette.tertiary(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  if (sourceRef != null && sourceRef.hasEvidence) ...[
                    const SizedBox(height: 8),
                    _BookNoteSourceAudit(sourceRef: sourceRef),
                    const SizedBox(height: 8),
                  ],
                  Divider(
                    indent: 4,
                    height: 3,
                    color: ClaudePalette.divider(context),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          note.chapter,
                          style: infoStyle,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        timeToHuman(note.createTime),
                        style: infoStyle,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _BookNoteSourceAudit extends StatelessWidget {
  const _BookNoteSourceAudit({required this.sourceRef});

  final SourceRef sourceRef;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final audit = PaperReaderSourceJumpAudit.fromSourceRefs([sourceRef]);
    final labels = <String>[
      if (audit.jumpableCount > 0)
        l10n.reviewInboxTraceableSources(audit.jumpableCount),
      if (audit.unavailableCount > 0)
        l10n.reviewInboxUnavailableSources(audit.unavailableCount),
      if (audit.unresolvedIndexes.isNotEmpty)
        l10n.reviewInboxUnresolvedSources(audit.unresolvedIndexes.length),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (labels.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final label in labels) _SourceAuditChip(label: label),
            ],
          ),
          const SizedBox(height: 8),
        ],
        SourceRefEvidenceList(sourceRefs: [sourceRef], maxItems: 1),
      ],
    );
  }
}

class _SourceAuditChip extends StatelessWidget {
  const _SourceAuditChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ClaudePalette.accentTint(context),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: ClaudePalette.secondary(context),
              ),
        ),
      ),
    );
  }
}
