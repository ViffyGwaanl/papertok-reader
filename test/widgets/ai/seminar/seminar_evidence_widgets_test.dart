import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/widgets/ai/seminar/evidence/seminar_evidence_widgets.dart';

void main() {
  testWidgets('SeminarSnapshotEvidenceTile renders evidence metadata',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SeminarSnapshotEvidenceTile(
            AiSeminarRunCardEvidenceSnapshot(
              id: 'current-1',
              title: 'Passage title',
              snippet: 'A focused evidence snippet.',
            ),
            zh: false,
            missingSourceLabel: 'Source missing',
            fallbackIndex: 1,
          ),
        ),
      ),
    );

    expect(find.text('Evidence 1'), findsOneWidget);
    expect(find.text('Passage title'), findsOneWidget);
    expect(find.text('A focused evidence snippet.'), findsOneWidget);
    expect(find.text('Source missing'), findsOneWidget);
  });

  testWidgets('SeminarSnapshotCompactEvidenceRows filters empty evidence',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SeminarSnapshotCompactEvidenceRows(
            evidenceRefs: const [
              AiSeminarRunCardEvidenceSnapshot(title: '', snippet: ''),
              AiSeminarRunCardEvidenceSnapshot(
                title: 'Fallback title',
                snippet: 'Compact snippet',
              ),
            ],
            linkedEvidenceLabel: 'Linked evidence',
            missingSourceLabel: 'Source missing',
            sourceActionBuilder: (_) => const Text('Open source'),
          ),
        ),
      ),
    );

    expect(find.text('Linked evidence'), findsOneWidget);
    expect(find.text('Compact snippet'), findsOneWidget);
    expect(find.text('Open source'), findsOneWidget);
    expect(find.text('Fallback title'), findsNothing);
  });

  testWidgets('SeminarEvidenceReferenceChips calls evidence callback',
      (tester) async {
    AiSeminarRunCardEvidenceSnapshot? pressed;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SeminarEvidenceReferenceChips(
            evidenceRefs: const [
              AiSeminarRunCardEvidenceSnapshot(
                id: 'current-2',
                title: 'Second',
                snippet: 'Second snippet',
              ),
            ],
            zh: false,
            onEvidencePressed: (evidence) => pressed = evidence,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Evidence 2'));
    await tester.pump();

    expect(pressed?.id, 'current-2');
  });
}
