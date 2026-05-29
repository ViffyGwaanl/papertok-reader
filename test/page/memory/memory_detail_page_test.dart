import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/page/memory/memory_detail_page.dart';
import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:papertok_reader/service/memory/memory_candidate.dart';
import 'package:papertok_reader/service/memory/memory_source_kind.dart';
import 'package:path/path.dart' as p;

void main() {
  testWidgets('shows source evidence and opens reader source for memory entry',
      (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('memory_detail_test_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final store = MarkdownMemoryStore(rootDir: tempDir);
    final path = p.join(tempDir.path, '2026-05-29.md');
    File(path).writeAsStringSync('Remember retrieval evidence.');
    final candidate = _candidate(
      text: 'Remember retrieval evidence.',
      targetDoc: MemoryDocTarget.daily,
      bookId: 7,
      cfi: 'epubcfi(/6/8)',
      chapter: 'Chapter 2',
      sourceKind: MemorySourceKind.reading,
    );
    final opened = <Uri>[];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MemoryDetailPage(
            entry: MemoryEntryRef(
              title: '2026-05-29',
              path: path,
              preview: 'Remember retrieval evidence.',
              modified: null,
            ),
            store: store,
            allKnownTags: const [],
            sourceOpener: (_, uri) async => opened.add(uri),
            appliedCandidateLoader: () async => [candidate],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    await tester.pump();

    expect(find.text('Evidence'), findsOneWidget);
    expect(find.text('1 traceable'), findsOneWidget);
    expect(find.text('Remember retrieval evidence.'), findsWidgets);
    expect(find.text('Chapter 2'), findsOneWidget);
    expect(find.text('Open source'), findsOneWidget);

    await tester.tap(find.text('Open source'));
    await tester.pump();

    expect(opened, hasLength(1));
    expect(opened.single.scheme, 'paperreader');
    expect(opened.single.host, 'reader');
    expect(opened.single.queryParameters['bookId'], '7');
    expect(opened.single.queryParameters['cfi'], 'epubcfi(/6/8)');
  });

  testWidgets('unavailable memory source explains reason without opening',
      (tester) async {
    final tempDir =
        Directory.systemTemp.createTempSync('memory_detail_unavailable_test_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final store = MarkdownMemoryStore(rootDir: tempDir);
    final path = p.join(tempDir.path, 'MEMORY.md');
    File(path).writeAsStringSync('# Preferences\n\nPrefer concise answers.');
    final candidate = _candidate(
      text: 'Prefer concise answers.',
      targetDoc: MemoryDocTarget.longTerm,
      sourceKind: MemorySourceKind.chat,
    );
    final opened = <Uri>[];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MemoryDetailPage(
            entry: MemoryEntryRef(
              title: 'Preferences',
              path: path,
              preview: 'Prefer concise answers.',
              body: 'Prefer concise answers.',
              modified: null,
            ),
            store: store,
            allKnownTags: const [],
            sourceOpener: (_, uri) async => opened.add(uri),
            appliedCandidateLoader: () async => [candidate],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    await tester.pump();

    expect(find.text('1 unavailable'), findsOneWidget);
    await tester.tap(find.text('Open source'));
    await tester.pump();

    expect(opened, isEmpty);
    expect(find.text('memory-source-not-jumpable'), findsWidgets);
  });

  testWidgets('long-term section detail does not expose file-level tag editor',
      (tester) async {
    final tempDir =
        Directory.systemTemp.createTempSync('memory_detail_section_test_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final store = MarkdownMemoryStore(rootDir: tempDir);
    final path = p.join(tempDir.path, 'MEMORY.md');
    File(path).writeAsStringSync('# Alpha\n\nsection body');

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MemoryDetailPage(
            entry: MemoryEntryRef(
              title: 'Alpha',
              path: path,
              preview: 'section body',
              body: 'section body',
              supportsBulkActions: false,
              modified: null,
            ),
            store: store,
            allKnownTags: const ['project'],
            appliedCandidateLoader: () async => const <MemoryCandidate>[],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    await tester.pump();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('section body'), findsOneWidget);
  });
}

MemoryCandidate _candidate({
  required String text,
  required MemoryDocTarget targetDoc,
  int? bookId,
  String? cfi,
  String? chapter,
  MemorySourceKind sourceKind = MemorySourceKind.chat,
}) {
  return MemoryCandidate(
    id: 'memory-${text.hashCode}',
    summary: text,
    text: text,
    targetDoc: targetDoc,
    appliedTargetDoc: targetDoc,
    sourceType: 'test',
    createdAtMs: 1000,
    status: MemoryCandidateStatus.applied,
    appliedAtMs: 1200,
    displayText: text,
    bookId: bookId,
    cfi: cfi,
    chapter: chapter,
    sourceKind: sourceKind,
  );
}
