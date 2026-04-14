import 'package:papertok_reader/page/memory/widgets/memory_row.dart';
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
}
