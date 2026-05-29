import 'package:papertok_reader/page/memory/widgets/memory_row.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders title and preview', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MemoryRow(
          entry: const MemoryEntryRef(
            title: 'Test title',
            path: '/tmp/x.md',
            preview: 'preview body',
            modified: null,
          ),
          onTap: () {},
        ),
      ),
    ));
    expect(find.text('Test title'), findsOneWidget);
    expect(find.text('preview body'), findsOneWidget);
  });

  testWidgets('tap triggers onTap callback', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MemoryRow(
          entry: const MemoryEntryRef(
            title: 'T',
            path: '/tmp/x.md',
            preview: 'p',
            modified: null,
          ),
          onTap: () => tapped++,
        ),
      ),
    ));
    await tester.tap(find.byType(MemoryRow));
    expect(tapped, 1);
  });

  testWidgets('renders source audit chips when source refs are present',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: MemoryRow(
          entry: const MemoryEntryRef(
            title: 'T',
            path: '/tmp/x.md',
            preview: 'p',
            modified: null,
          ),
          sourceRefs: [
            SourceRef(
              bookId: 7,
              cfi: 'epubcfi(/6/8)',
              jumpLink:
                  'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
              sourceKind: SourceRefKind.memory,
              sourceTextSnippet: 'Traceable memory evidence.',
            ),
          ],
          onTap: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1 traceable'), findsOneWidget);
  });
}
