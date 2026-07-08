import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/widgets/ai/seminar/timeline/seminar_timeline_widgets.dart';

void main() {
  testWidgets('SeminarSnapshotNativeTimeline renders parts and toggle',
      (tester) async {
    var toggleCount = 0;
    const parts = [
      AiSeminarRunCardMessagePart(type: 'role_turn', text: 'First'),
      AiSeminarRunCardMessagePart(type: 'thinking', text: 'Thinking'),
      AiSeminarRunCardMessagePart(type: 'role_turn', text: 'Second'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SeminarSnapshotNativeTimeline(
            parts: parts,
            sessionId: 'session-1',
            hiddenPartCount: 2,
            canToggleExpansion: true,
            isExpanded: false,
            zh: false,
            onToggleExpansion: () => toggleCount += 1,
            partBuilder: (part, roleTurnNumber) => Text(
              '${part.type}:${roleTurnNumber ?? 'none'}',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Seminar stream'), findsOneWidget);
    expect(find.text('role_turn:1'), findsOneWidget);
    expect(find.text('thinking:none'), findsOneWidget);
    expect(find.text('role_turn:2'), findsOneWidget);
    expect(
      find.text('2 more Seminar parts are available in tabs.'),
      findsOneWidget,
    );
    expect(find.text('Expand full Seminar stream'), findsOneWidget);

    await tester.tap(find.text('Expand full Seminar stream'));
    await tester.pump();

    expect(toggleCount, 1);
  });

  testWidgets('SeminarSnapshotNativeTimelinePart dispatches text parts',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SeminarSnapshotNativeTimelinePart(
            part: const AiSeminarRunCardMessagePart(
              type: 'review_triage',
              label: 'reason',
              text: 'Needs manual review.',
              evidenceRefs: [
                AiSeminarRunCardEvidenceSnapshot(
                  title: 'Evidence title',
                  snippet: 'Evidence snippet',
                ),
              ],
            ),
            zh: false,
            showInlineEvidence: true,
            showTraceDetails: true,
            roleTurnNumber: null,
            toolCallBuilder: (_) => const Text('tool'),
            roleTurnBuilder: (_, __) => const Text('role'),
            rolePartialBuilder: (_) => const Text('partial'),
            directorStateBuilder: (_) => const Text('director'),
            agentStatusBuilder: (_) => const Text('status'),
            readerTurnBuilder: (_) => const Text('reader'),
            readerComposerBuilder: (_) => const Text('composer'),
            thinkingContextLabelBuilder: (_) => null,
            thinkingCompletedAtLabelBuilder: (_) => null,
            roleLabelsBuilder: (_) => 'roles',
            roleLabelBuilder: (_) => 'role',
            countLabelBuilder: (_,
                    {required zhUnit,
                    required enSingular,
                    required enPlural}) =>
                'count',
            reviewTriageLabelBuilder: (_) => 'Review reason',
            reviewTriageTextBuilder: (_) => 'Needs manual review.',
            artifactChipLabelBuilder: (_) => '',
            artifactDisplayTextBuilder: (text) => text,
            artifactStatusLabelBuilder: (_) => null,
            artifactCompletedAtLabelBuilder: (_, __) => null,
            artifactDetailLabelBuilder: (_) => 'Execution result',
            evidenceTileBuilder: (_) => const Text('Evidence tile'),
            linkedEvidenceLabel: 'Linked evidence',
            missingSourceLabel: 'Missing source',
            evidenceSourceActionBuilder: (_) => const Text('Open source'),
          ),
        ),
      ),
    );

    expect(find.text('Review reason'), findsOneWidget);
    expect(find.text('Needs manual review.'), findsOneWidget);
    expect(find.text('Linked evidence'), findsOneWidget);
    expect(find.text('Evidence snippet'), findsOneWidget);
    expect(find.text('Open source'), findsOneWidget);
  });

  testWidgets('SeminarSnapshotRunSetupPartTile renders setup lines',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SeminarSnapshotRunSetupPartTile(
            part: AiSeminarRunCardMessagePart(
              type: 'seminar_run_setup',
              text: 'Question: What matters?',
              label: 'Rounds: 2',
            ),
            zh: false,
          ),
        ),
      ),
    );

    expect(find.text('Run setup'), findsOneWidget);
    expect(find.text('Question: What matters?'), findsOneWidget);
    expect(find.text('Rounds: 2'), findsOneWidget);
  });

  testWidgets('SeminarSnapshotArtifactActionsPartTile renders action details',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SeminarSnapshotArtifactActionsPartTile(
            part: const AiSeminarRunCardMessagePart(
              type: 'artifact_actions',
              status: 'completed',
              completedAt: 123,
              text: 'Saved successfully.',
              actionIds: ['save-knowledge-card'],
              evidenceRefs: [
                AiSeminarRunCardEvidenceSnapshot(
                  title: 'Evidence title',
                  snippet: 'Evidence snippet',
                ),
              ],
            ),
            zh: false,
            actionChipLabelBuilder: (_) => 'Save card',
            displayTextBuilder: (text) => text,
            statusLabelBuilder: (_) => 'Processed',
            completedAtLabelBuilder: (_, __) => 'Executed at now',
            detailLabelBuilder: (_) => 'Execution result',
            linkedEvidenceLabel: 'Linked evidence',
            missingSourceLabel: 'Missing source',
            evidenceSourceActionBuilder: (_) => const Text('Open source'),
          ),
        ),
      ),
    );

    expect(find.text('Artifact actions'), findsOneWidget);
    expect(find.text('Processed'), findsOneWidget);
    expect(find.text('Executed at now'), findsOneWidget);
    expect(find.text('Execution result'), findsOneWidget);
    expect(find.text('Saved successfully.'), findsOneWidget);
    expect(find.text('Save card'), findsOneWidget);
    expect(find.text('Evidence snippet'), findsOneWidget);
  });
}
