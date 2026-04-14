import 'dart:io';

import 'package:anx_reader/service/memory/markdown_memory_store.dart';
import 'package:anx_reader/service/memory/memory_candidate.dart';
import 'package:anx_reader/service/memory/memory_candidate_store.dart';
import 'package:anx_reader/service/memory/memory_source_kind.dart';
import 'package:anx_reader/service/memory/memory_workflow_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempRoot;
  late MemoryWorkflowService workflow;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('mws_ctx_');
    final markdown = MarkdownMemoryStore(rootDir: tempRoot);
    final candidates = MemoryCandidateStore(rootDir: tempRoot);
    workflow = MemoryWorkflowService(
      store: markdown,
      candidateStore: candidates,
    );
  });

  tearDown(() async {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('addToReviewInbox with reading context populates v2 fields', () async {
    final candidate = await workflow.addToReviewInbox(
      text: 'remember this insight',
      targetDoc: MemoryDocTarget.daily,
      sourceType: 'reading_session',
      bookId: 42,
      cfi: 'epubcfi(/6/4!/4/2)',
      chapter: 'Chapter 1',
      sourceKind: MemorySourceKind.reading,
    );
    expect(candidate.bookId, 42);
    expect(candidate.cfi, 'epubcfi(/6/4!/4/2)');
    expect(candidate.chapter, 'Chapter 1');
    expect(candidate.sourceKind, MemorySourceKind.reading);
  });

  test('addToReviewInbox without reading context defaults to chat sourceKind',
      () async {
    final candidate = await workflow.addToReviewInbox(
      text: 'pure chat note',
      targetDoc: MemoryDocTarget.daily,
      sourceType: 'session_digest',
    );
    expect(candidate.bookId, isNull);
    expect(candidate.cfi, isNull);
    expect(candidate.chapter, isNull);
    expect(candidate.sourceKind, MemorySourceKind.chat);
  });

  test('saveToDaily with reading context populates v2 fields', () async {
    final candidate = await workflow.saveToDaily(
      text: 'applied immediately',
      sourceType: 'reading_session',
      bookId: 7,
      cfi: 'epubcfi(/2/4)',
      chapter: 'Intro',
      sourceKind: MemorySourceKind.reading,
    );
    expect(candidate.bookId, 7);
    expect(candidate.cfi, 'epubcfi(/2/4)');
    expect(candidate.chapter, 'Intro');
    expect(candidate.sourceKind, MemorySourceKind.reading);
  });
}
