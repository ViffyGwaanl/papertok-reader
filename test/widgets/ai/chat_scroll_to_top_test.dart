import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/widgets/ai/chat_scroll_to_top.dart';

void main() {
  testWidgets('double-tap scrolls the attached list back to top',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: ChatScrollToTopTitle(
              controller: controller,
              child: const Text('title'),
            ),
          ),
          body: ListView.builder(
            controller: controller,
            itemCount: 100,
            itemBuilder: (_, i) => SizedBox(height: 50, child: Text('$i')),
          ),
        ),
      ),
    );

    controller.jumpTo(2000);
    await tester.pump();
    expect(controller.offset, 2000);

    await tester.tap(find.text('title'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('title'));
    await tester.pumpAndSettle();

    expect(controller.offset, 0);
  });

  testWidgets('double-tap with no attached clients does not throw',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ChatScrollToTopTitle(
          controller: controller,
          child: const Text('title'),
        ),
      ),
    );

    await tester.tap(find.text('title'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('title'));
    await tester.pump(const Duration(milliseconds: 400));
    // No exception = pass.
  });
}
