import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/widgets/ai/seminar/snapshot/seminar_snapshot_tabs.dart';

void main() {
  test('seminarSnapshotAvailableSubviews keeps expected ordering', () {
    final subviews = seminarSnapshotAvailableSubviews(
      toolCalls: const [
        AiSeminarRunCardToolCallSnapshot(
          toolId: 'semantic_search_current_book',
          query: 'query',
          resultCount: 1,
        ),
      ],
      evidence: const [
        AiSeminarRunCardEvidenceSnapshot(title: 'T', snippet: 'S'),
      ],
      roles: const [
        AiSeminarRunCardRoleSummary(
          roleId: 'critical',
          label: 'Critical',
          summary: 'S',
        ),
      ],
      hasLiveRole: false,
      synthesis: 'Summary',
      hasStatus: true,
      hasThinking: true,
      hasControls: true,
      hasReviewTriage: true,
      hasArtifactActions: true,
      disagreements: const ['Disagreement'],
      hasContradictionScans: false,
      hasDisagreementRebuttals: false,
      openQuestions: const ['Question'],
    );

    expect(
      subviews,
      const [
        SeminarRunSnapshotSubview.overview,
        SeminarRunSnapshotSubview.status,
        SeminarRunSnapshotSubview.thinking,
        SeminarRunSnapshotSubview.controls,
        SeminarRunSnapshotSubview.tools,
        SeminarRunSnapshotSubview.evidence,
        SeminarRunSnapshotSubview.roles,
        SeminarRunSnapshotSubview.disagreements,
        SeminarRunSnapshotSubview.whiteboard,
        SeminarRunSnapshotSubview.summary,
        SeminarRunSnapshotSubview.artifacts,
        SeminarRunSnapshotSubview.review,
      ],
    );
  });

  test('seminarSnapshotSelectedSubview falls back to overview', () {
    expect(
      seminarSnapshotSelectedSubview(
        'session-1',
        const [SeminarRunSnapshotSubview.overview],
        const {'session-1': SeminarRunSnapshotSubview.roles},
      ),
      SeminarRunSnapshotSubview.overview,
    );
  });

  testWidgets('SeminarSnapshotSubviewTabs renders labels and selection',
      (tester) async {
    var selected = SeminarRunSnapshotSubview.overview;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SeminarSnapshotSubviewTabs(
            sessionId: 'session-1',
            subviews: const [
              SeminarRunSnapshotSubview.overview,
              SeminarRunSnapshotSubview.roles,
            ],
            selected: SeminarRunSnapshotSubview.overview,
            zh: false,
            onSelected: (subview) => selected = subview,
          ),
        ),
      ),
    );

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Roles'), findsOneWidget);

    await tester.tap(find.text('Roles'));
    await tester.pump();

    expect(selected, SeminarRunSnapshotSubview.roles);
  });
}
