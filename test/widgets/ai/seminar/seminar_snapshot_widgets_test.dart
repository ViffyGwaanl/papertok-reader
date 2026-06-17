import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/widgets/ai/seminar/shared/seminar_snapshot_widgets.dart';

void main() {
  testWidgets('Seminar snapshot shared widgets render labels and chips',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: const [
              SeminarSnapshotHeading(Icons.fact_check_outlined, 'Evidence'),
              SeminarSnapshotMissingSourceChip('Source missing'),
              SeminarSnapshotLabeledTinyChip(
                label: 'Role',
                value: 'Critical',
              ),
              SeminarSnapshotDetailLabel('Detail'),
              SeminarSnapshotTinyChip('Ready'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Evidence'), findsOneWidget);
    expect(find.text('Source missing'), findsOneWidget);
    expect(find.text('Role'), findsOneWidget);
    expect(find.text('Critical'), findsOneWidget);
    expect(find.text('Detail'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('Seminar meta chips render all provided chip data',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SeminarMetaChips(
            chips: [
              SeminarMetaChipData(
                icon: Icons.flag_outlined,
                label: 'Running',
              ),
              SeminarMetaChipData(
                icon: Icons.groups_2_outlined,
                label: '4 roles',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Running'), findsOneWidget);
    expect(find.text('4 roles'), findsOneWidget);
  });

  testWidgets('Seminar snapshot expandable text wires controls and evidence',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SeminarSnapshotExpandableText(
            r'First line\nSecond line (current-1)',
            collapsedMaxLines: 1,
          ),
        ),
      ),
    );

    expect(find.text('Expand'), findsOneWidget);
    expect(find.textContaining('Evidence 1'), findsOneWidget);

    await tester.tap(find.text('Expand'));
    await tester.pumpAndSettle();

    expect(find.text('Collapse'), findsOneWidget);
  });
}
