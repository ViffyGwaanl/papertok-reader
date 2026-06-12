import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/widgets/ai/seminar/seminar_expandable_text.dart';

void main() {
  testWidgets('SeminarExpandableText expands into selectable scrollable text',
      (tester) async {
    const longText = 'First long paragraph that should start collapsed.\n\n'
        'Second long paragraph that must be readable after expansion.\n\n'
        'Third paragraph keeps enough content to require scrolling.';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SeminarExpandableText(
            text: longText,
            collapsedMaxLines: 1,
            expandedMaxHeight: 72,
            expandLabel: 'Expand',
            collapseLabel: 'Collapse',
          ),
        ),
      ),
    );

    expect(find.byType(SelectableText), findsNothing);
    expect(find.text('Expand'), findsOneWidget);

    await tester.tap(find.text('Expand'));
    await tester.pumpAndSettle();

    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('Collapse'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.text(longText),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Collapse'));
    await tester.pumpAndSettle();

    expect(find.byType(SelectableText), findsNothing);
    expect(find.text('Expand'), findsOneWidget);
  });

  testWidgets(
      'SeminarExpandableText hides internal evidence ids and literal newlines',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SeminarExpandableText(
            text: r'First line\nSecond line (current-1)',
            expandLabel: 'Expand',
            collapseLabel: 'Collapse',
          ),
        ),
      ),
    );

    expect(find.textContaining(r'\n'), findsNothing);
    expect(find.textContaining('current-1'), findsNothing);
    expect(find.textContaining('First line\nSecond line Evidence 1'),
        findsOneWidget);
  });
}
