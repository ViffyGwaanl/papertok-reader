import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/widgets/ai/seminar/disagreement/seminar_disagreement_widgets.dart';

void main() {
  testWidgets('SeminarSnapshotDisagreementDetails renders roles and evidence',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SeminarSnapshotDisagreementDetails(
            details: const [
              AiSeminarRunCardDisagreementDetail(
                text: 'Unresolved tension.',
                agentRunId: 'seminar-role-critical',
                parentRunId: 'seminar-chat-history',
                roleIds: ['critical', 'supportive'],
                evidenceRefs: [
                  AiSeminarRunCardEvidenceSnapshot(
                    id: 'current-1',
                    title: 'Evidence title',
                    snippet: 'Evidence snippet',
                  ),
                ],
              ),
            ],
            zh: false,
            roleLabelsBuilder: _roleLabels,
            evidenceTileBuilder: (_) => const Text('Evidence tile'),
          ),
        ),
      ),
    );

    expect(find.text('Unresolved tension.'), findsOneWidget);
    expect(find.text('Linked roles'), findsOneWidget);
    expect(find.text('Critical, Supportive'), findsOneWidget);
    expect(find.text('Linked evidence'), findsOneWidget);
    expect(find.text('Evidence tile'), findsOneWidget);
    expect(find.text('Agent trace'), findsOneWidget);
  });

  testWidgets('SeminarSnapshotContradictionScanTiles renders overview and gaps',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SeminarSnapshotContradictionScanTiles(
              parts: const [
                AiSeminarRunCardMessagePart(
                  type: 'contradiction_scan',
                  label: 'evidence-gap',
                  text: 'Need supporting quote.',
                  roleIds: ['critical'],
                ),
                AiSeminarRunCardMessagePart(
                  type: 'contradiction_scan',
                  label: 'evidence-gap',
                  text: 'Need dated source.',
                ),
                AiSeminarRunCardMessagePart(
                  type: 'contradiction_scan',
                  label: 'supported',
                  text: 'There is supporting evidence.',
                  roleIds: ['supportive'],
                  evidenceRefs: [
                    AiSeminarRunCardEvidenceSnapshot(
                      id: 'current-2',
                      title: 'Evidence title',
                      snippet: 'Evidence snippet',
                    ),
                  ],
                ),
              ],
              zh: false,
              roleLabelsBuilder: _roleLabels,
              countLabelBuilder: _countLabel,
              evidenceTileBuilder: (_) => const Text('Evidence tile'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Contradiction scan overview'), findsOneWidget);
    expect(find.text('3 scans'), findsOneWidget);
    expect(find.text('2 evidence gaps'), findsNWidgets(2));
    expect(find.text('1 evidence-backed scan'), findsOneWidget);
    expect(find.text('Evidence gap summary'), findsOneWidget);
    expect(find.text('Need supporting quote.'), findsNWidgets(2));
    expect(find.text('Need dated source.'), findsNWidgets(2));
    expect(find.text('Contradiction scan'), findsNWidgets(3));
    expect(find.text('Scan result'), findsNWidgets(2));
    expect(find.text('Evidence gap'), findsNWidgets(2));
    expect(find.text('Traceable evidence missing'), findsNWidgets(2));
    expect(find.text('Critical'), findsOneWidget);
    expect(find.text('Supportive'), findsOneWidget);
    expect(find.text('Evidence tile'), findsOneWidget);
  });

  testWidgets(
      'SeminarSnapshotDisagreementRebuttalTiles renders rebuttal detail',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SeminarSnapshotDisagreementRebuttalTiles(
            parts: const [
              AiSeminarRunCardMessagePart(
                type: 'disagreement_rebuttal',
                agentRunId: 'seminar-role-critical',
                parentRunId: 'seminar-chat-history',
                roleId: 'critical',
                label: 'Whether the source applies.',
                text: 'Counterpoint from the role.',
                evidenceRefs: [
                  AiSeminarRunCardEvidenceSnapshot(
                    id: 'current-3',
                    title: 'Evidence title',
                    snippet: 'Evidence snippet',
                  ),
                ],
              ),
            ],
            zh: false,
            roleLabelBuilder: _roleLabel,
            evidenceTileBuilder: (_) => const Text('Evidence tile'),
          ),
        ),
      ),
    );

    expect(find.text('Disagreement rebuttal turn'), findsOneWidget);
    expect(find.text('Role'), findsOneWidget);
    expect(find.text('Critical'), findsOneWidget);
    expect(find.text('Target disagreement'), findsOneWidget);
    expect(find.text('Whether the source applies.'), findsOneWidget);
    expect(find.text('Counterpoint from the role.'), findsOneWidget);
    expect(find.text('Linked evidence'), findsOneWidget);
    expect(find.text('Evidence tile'), findsOneWidget);
    expect(find.text('Agent trace'), findsOneWidget);
  });
}

String _roleLabels(List<String> roleIds) => roleIds.map(_roleLabel).join(', ');

String _roleLabel(String roleId) => switch (roleId) {
      'critical' => 'Critical',
      'supportive' => 'Supportive',
      _ => roleId,
    };

String _countLabel(
  int count, {
  required String zhUnit,
  required String enSingular,
  required String enPlural,
}) {
  return count == 1 ? '1 $enSingular' : '$count $enPlural';
}
