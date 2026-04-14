// test/page/memory/tag_editor_test.dart
import 'package:papertok_reader/page/memory/widgets/tag_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders initial tags as selected chips', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TagEditor(
          initial: const ['alpha', 'beta'],
          suggestions: const ['alpha', 'beta', 'gamma'],
          onChanged: (_) {},
        ),
      ),
    ));
    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);
    // Gamma is a suggestion and should also render as a chip (unselected).
    expect(find.text('gamma'), findsOneWidget);
  });

  testWidgets('text field add fires onChanged', (tester) async {
    final updates = <List<String>>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TagEditor(
          initial: const ['alpha'],
          suggestions: const <String>[],
          onChanged: updates.add,
        ),
      ),
    ));
    await tester.enterText(find.byType(TextField), 'beta');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(updates.isNotEmpty, isTrue);
    expect(updates.last, containsAll(<String>['alpha', 'beta']));
  });

  testWidgets('tapping a selected chip removes it', (tester) async {
    final updates = <List<String>>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TagEditor(
          initial: const ['remove-me', 'keep'],
          suggestions: const <String>[],
          onChanged: updates.add,
        ),
      ),
    ));
    await tester.tap(find.text('remove-me'));
    await tester.pump();
    expect(updates.last, equals(<String>['keep']));
  });

  testWidgets('tapping a suggestion chip adds it', (tester) async {
    final updates = <List<String>>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TagEditor(
          initial: const <String>[],
          suggestions: const ['alpha', 'beta'],
          onChanged: updates.add,
        ),
      ),
    ));
    await tester.tap(find.text('alpha'));
    await tester.pump();
    expect(updates.last, equals(<String>['alpha']));
  });

  testWidgets('duplicate add is a no-op', (tester) async {
    final updates = <List<String>>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TagEditor(
          initial: const ['alpha'],
          suggestions: const <String>[],
          onChanged: updates.add,
        ),
      ),
    ));
    await tester.enterText(find.byType(TextField), 'alpha');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    // onChanged NOT called for a duplicate.
    expect(updates, isEmpty);
  });
}
