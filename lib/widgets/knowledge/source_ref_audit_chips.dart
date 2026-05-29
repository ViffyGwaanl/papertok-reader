import 'package:flutter/material.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:papertok_reader/theme/claude_palette.dart';

class SourceRefAuditChips extends StatelessWidget {
  const SourceRefAuditChips({
    super.key,
    required this.sourceRefs,
  });

  final List<SourceRef> sourceRefs;

  @override
  Widget build(BuildContext context) {
    if (sourceRefs.isEmpty) return const SizedBox.shrink();

    final l10n = L10n.of(context);
    final audit = PaperReaderSourceJumpAudit.fromSourceRefs(sourceRefs);
    final chips = <Widget>[
      if (audit.jumpableCount > 0)
        _SourceRefAuditChip(
          label: l10n.reviewInboxTraceableSources(audit.jumpableCount),
        ),
      if (audit.unavailableCount > 0)
        _SourceRefAuditChip(
          label: l10n.reviewInboxUnavailableSources(audit.unavailableCount),
        ),
      if (audit.unresolvedIndexes.isNotEmpty)
        _SourceRefAuditChip(
          label: l10n.reviewInboxUnresolvedSources(
            audit.unresolvedIndexes.length,
          ),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips,
    );
  }
}

class _SourceRefAuditChip extends StatelessWidget {
  const _SourceRefAuditChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: ClaudePalette.elevated(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ClaudePalette.divider(context)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: ClaudePalette.secondary(context),
        ),
      ),
    );
  }
}
