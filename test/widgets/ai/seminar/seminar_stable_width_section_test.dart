import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/widgets/ai/seminar/seminar_stable_width_section.dart';

void main() {
  testWidgets('stable width section expands narrow seminar stages',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 320,
            child: SeminarFullWidthSection(
              child: SizedBox(width: 80, height: 24),
            ),
          ),
        ),
      ),
    );

    final sectionBox = tester.renderObject<RenderBox>(
      find.byType(SeminarFullWidthSection),
    );
    expect(sectionBox.size.width, 320);
  });
}
