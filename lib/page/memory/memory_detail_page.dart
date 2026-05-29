import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/page/memory/widgets/tag_editor.dart';
import 'package:papertok_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:papertok_reader/service/deeplink/paperreader_source_opener.dart';
import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:papertok_reader/service/memory/memory_candidate.dart';
import 'package:papertok_reader/service/memory/memory_candidate_store.dart';
import 'package:papertok_reader/service/memory/memory_source_ref_adapter.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/knowledge/source_ref_audit_chips.dart';
import 'package:papertok_reader/widgets/knowledge/source_ref_evidence_list.dart';
import 'package:papertok_reader/widgets/markdown/styled_markdown.dart';
import 'package:flutter/material.dart';

typedef MemoryAppliedCandidateLoader = Future<List<MemoryCandidate>> Function();

/// Detail view for a single Memory entry (either a MEMORY.md section or
/// a daily note). Renders the markdown body via `StyledMarkdown`, shows
/// an inline `TagEditor` at the top that reads/writes YAML front-matter
/// tags on the underlying file.
class MemoryDetailPage extends ConsumerStatefulWidget {
  final MemoryEntryRef entry;
  final MarkdownMemoryStore store;
  final List<String> allKnownTags;
  final PaperReaderSourceOpener? sourceOpener;
  final MemoryAppliedCandidateLoader? appliedCandidateLoader;

  const MemoryDetailPage({
    super.key,
    required this.entry,
    required this.store,
    required this.allKnownTags,
    this.sourceOpener,
    this.appliedCandidateLoader,
  });

  @override
  ConsumerState<MemoryDetailPage> createState() => _MemoryDetailPageState();
}

class _MemoryDetailPageState extends ConsumerState<MemoryDetailPage> {
  late Future<_DetailState> _loader;

  @override
  void initState() {
    super.initState();
    _loader = _load();
  }

  Future<_DetailState> _load() async {
    final file = File(widget.entry.path);
    final raw = file.existsSync() ? file.readAsStringSync() : '';
    final entryBody =
        widget.entry.body.trim().isEmpty ? raw : widget.entry.body;
    final body = _stripFrontMatter(entryBody);
    final tags = _readEntryTags(raw);
    final candidates = await (widget.appliedCandidateLoader?.call() ??
        MemoryCandidateStore(
          rootDir: widget.store.rootDir,
        ).list(status: MemoryCandidateStatus.applied));
    final sourceRefs = MemoryEntrySourceRefAdapter.sourceRefsForEntry(
      entry: widget.entry,
      body: body,
      candidates: candidates,
    );
    return _DetailState(body: body, tags: tags, sourceRefs: sourceRefs);
  }

  String _stripFrontMatter(String content) {
    if (!content.startsWith('---\n')) return content;
    final endIdx = content.indexOf('\n---\n', 4);
    if (endIdx == -1) return content;
    return content.substring(endIdx + 5);
  }

  List<String> _readEntryTags(String content) {
    if (!content.startsWith('---\n')) return const <String>[];
    final endIdx = content.indexOf('\n---\n', 4);
    if (endIdx == -1) return const <String>[];
    final frontMatter = content.substring(4, endIdx);
    final tagMatch =
        RegExp(r'^tags:\s*\[(.*)\]\s*$', multiLine: true).firstMatch(
      frontMatter,
    );
    if (tagMatch == null) return const <String>[];
    return tagMatch
        .group(1)!
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.entry.title)),
      body: FutureBuilder<_DetailState>(
        future: _loader,
        builder: (context, snap) {
          if (!snap.hasData) {
            return Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ClaudePalette.tertiary(context),
                ),
              ),
            );
          }
          final data = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              if (widget.entry.supportsBulkActions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TagEditor(
                    initial: data.tags,
                    suggestions: widget.allKnownTags,
                    onChanged: (updated) async {
                      await widget.store.writeEntryTags(
                        widget.entry.path,
                        updated,
                      );
                    },
                  ),
                ),
              Divider(
                color: ClaudePalette.divider(context),
                thickness: 0.5,
                height: 24,
              ),
              if (data.sourceRefs.isNotEmpty) ...[
                _MemorySourceSection(
                  sourceRefs: data.sourceRefs,
                  sourceOpener: widget.sourceOpener ?? openPaperReaderSource,
                ),
                const SizedBox(height: 18),
              ],
              StyledMarkdown(data: data.body),
            ],
          );
        },
      ),
    );
  }
}

class _DetailState {
  final String body;
  final List<String> tags;
  final List<SourceRef> sourceRefs;

  const _DetailState({
    required this.body,
    required this.tags,
    required this.sourceRefs,
  });
}

class _MemorySourceSection extends ConsumerWidget {
  const _MemorySourceSection({
    required this.sourceRefs,
    required this.sourceOpener,
  });

  final List<SourceRef> sourceRefs;
  final PaperReaderSourceOpener sourceOpener;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final intent = _firstReaderIntent(sourceRefs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SourceRefAuditChips(sourceRefs: sourceRefs),
        const SizedBox(height: 10),
        SourceRefEvidenceList(sourceRefs: sourceRefs),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.open_in_new),
            label: Text(l10n.reviewInboxOpenSourceAction),
            onPressed: intent == null
                ? () => showPaperReaderSourceUnavailable(
                      context,
                      sourceRefs,
                      l10n.conceptGraphNoEvidence,
                    )
                : () async => sourceOpener(ref, intent.toUri()),
          ),
        ),
      ],
    );
  }

  PaperReaderReaderIntent? _firstReaderIntent(List<SourceRef> sourceRefs) {
    for (final sourceRef in sourceRefs) {
      final intent = PaperReaderReaderIntent.fromSourceRef(sourceRef);
      if (intent != null) return intent;
    }
    return null;
  }
}
