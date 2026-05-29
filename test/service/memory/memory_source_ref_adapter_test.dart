import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:papertok_reader/service/memory/memory_candidate.dart';
import 'package:papertok_reader/service/memory/memory_source_kind.dart';
import 'package:papertok_reader/service/memory/memory_source_ref_adapter.dart';
import 'package:path/path.dart' as p;

void main() {
  test('projects matching applied memory candidates into source refs', () {
    final entry = MemoryEntryRef(
      title: '2026-05-29',
      path: p.join(Directory.systemTemp.path, '2026-05-29.md'),
      preview: 'Remember retrieval evidence.',
      modified: null,
    );
    final sourceRefs = MemoryEntrySourceRefAdapter.sourceRefsForEntry(
      entry: entry,
      body: 'Remember retrieval evidence.',
      candidates: [
        _candidate(
          text: 'Remember retrieval evidence.',
          targetDoc: MemoryDocTarget.daily,
          bookId: 7,
          cfi: 'epubcfi(/6/8)',
          chapter: 'Chapter 2',
          sourceKind: MemorySourceKind.reading,
        ),
        _candidate(
          text: 'Unrelated long-term memory.',
          targetDoc: MemoryDocTarget.longTerm,
        ),
      ],
    );

    expect(sourceRefs, hasLength(1));
    expect(sourceRefs.single.sourceKind, SourceRefKind.memory);
    expect(sourceRefs.single.canJumpBack, isTrue);
    expect(sourceRefs.single.sourceTextSnippet, 'Remember retrieval evidence.');
    expect(sourceRefs.single.sourceTitle, 'Chapter 2');
  });

  test('ignores unapplied or body-mismatched memory candidates', () {
    final entry = MemoryEntryRef(
      title: '2026-05-29',
      path: p.join(Directory.systemTemp.path, '2026-05-29.md'),
      preview: 'Remember retrieval evidence.',
      modified: null,
    );
    final sourceRefs = MemoryEntrySourceRefAdapter.sourceRefsForEntry(
      entry: entry,
      body: 'Remember retrieval evidence.',
      candidates: [
        _candidate(
          text: 'Remember retrieval evidence.',
          targetDoc: MemoryDocTarget.daily,
          status: MemoryCandidateStatus.pending,
          bookId: 7,
          cfi: 'epubcfi(/6/8)',
        ),
        _candidate(
          text: 'Different applied memory.',
          targetDoc: MemoryDocTarget.daily,
          bookId: 8,
          cfi: 'epubcfi(/6/10)',
        ),
      ],
    );

    expect(sourceRefs, isEmpty);
  });

  test('does not assign source refs by summary-only matches', () {
    final entry = MemoryEntryRef(
      title: 'Alpha',
      path: p.join(Directory.systemTemp.path, 'MEMORY.md'),
      preview: 'Short label appears here.',
      body: 'Short label appears here.',
      modified: null,
    );
    final sourceRefs = MemoryEntrySourceRefAdapter.sourceRefsForEntry(
      entry: entry,
      body: entry.body,
      candidates: [
        _candidate(
          summary: 'Short label appears here.',
          text: 'Actual applied memory lives under another H1 section.',
          targetDoc: MemoryDocTarget.longTerm,
          bookId: 7,
          cfi: 'epubcfi(/6/8)',
        ),
      ],
    );

    expect(sourceRefs, isEmpty);
  });

  test('keeps conversation-only applied memory as unavailable evidence', () {
    final entry = MemoryEntryRef(
      title: 'Long term',
      path: p.join(Directory.systemTemp.path, 'MEMORY.md'),
      preview: 'Prefer concise Chinese answers.',
      modified: null,
    );
    final sourceRefs = MemoryEntrySourceRefAdapter.sourceRefsForEntry(
      entry: entry,
      body: '# Long term\nPrefer concise Chinese answers.',
      candidates: [
        _candidate(
          text: 'Prefer concise Chinese answers.',
          targetDoc: MemoryDocTarget.longTerm,
          sourcePointer: 'conversation-1#node-2',
          sourceKind: MemorySourceKind.chat,
        ),
      ],
    );

    expect(sourceRefs, hasLength(1));
    expect(sourceRefs.single.canJumpBack, isFalse);
    expect(sourceRefs.single.hasUnavailableReason, isTrue);
    expect(sourceRefs.single.unavailableReason,
        contains('memory-source-not-jumpable'));
    expect(sourceRefs.single.hasEvidence, isTrue);
  });
}

MemoryCandidate _candidate({
  String? summary,
  required String text,
  required MemoryDocTarget targetDoc,
  int? bookId,
  String? cfi,
  String? chapter,
  String? sourcePointer,
  MemorySourceKind sourceKind = MemorySourceKind.chat,
  MemoryCandidateStatus status = MemoryCandidateStatus.applied,
}) {
  return MemoryCandidate(
    id: 'memory-${text.hashCode}',
    summary: summary ?? text,
    text: text,
    targetDoc: targetDoc,
    appliedTargetDoc: targetDoc,
    sourceType: 'test',
    createdAtMs: 1000,
    status: status,
    appliedAtMs: status == MemoryCandidateStatus.applied ? 1200 : null,
    displayText: text,
    sourcePointer: sourcePointer,
    bookId: bookId,
    cfi: cfi,
    chapter: chapter,
    sourceKind: sourceKind,
  );
}
