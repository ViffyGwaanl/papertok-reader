import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/widgets/ai/seminar/whiteboard/seminar_whiteboard_widgets.dart';

void main() {
  testWidgets('SeminarSnapshotWhiteboardSection renders grouped notes',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SeminarSnapshotWhiteboardSection(
            disagreements: ['Disagreement note'],
            openQuestions: ['Open question'],
            zh: false,
          ),
        ),
      ),
    );

    expect(find.text('Shared whiteboard'), findsOneWidget);
    expect(find.text('Disagreements'), findsOneWidget);
    expect(find.text('Disagreement note'), findsOneWidget);
    expect(find.text('Open questions'), findsOneWidget);
    expect(find.text('Open question'), findsOneWidget);
  });

  testWidgets('SeminarSnapshotReviewPreview renders triage candidates',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SeminarSnapshotReviewPreview(
              synthesis: 'Synthesis summary.',
              evidenceCount: 2,
              activeSynthesis: null,
              reviewTriageParts: const [
                AiSeminarRunCardMessagePart(
                  type: 'review_triage',
                  label: 'reason',
                  text: 'Needs review.',
                ),
                AiSeminarRunCardMessagePart(
                  type: 'review_triage',
                  label: 'ai-suggestion',
                  text: 'Check manually.',
                ),
                AiSeminarRunCardMessagePart(
                  type: 'review_triage',
                  label: 'risk',
                  text: 'medium',
                ),
                AiSeminarRunCardMessagePart(
                  type: 'review_triage',
                  label: 'suggested-action',
                  text: 'send-to-review',
                ),
                AiSeminarRunCardMessagePart(
                  type: 'review_triage',
                  label: 'knowledge-card',
                  text: 'Candidate card.',
                  evidenceRefs: [
                    AiSeminarRunCardEvidenceSnapshot(
                      id: 'current-1',
                      title: 'Evidence title',
                      snippet: 'Evidence snippet',
                    ),
                  ],
                ),
                AiSeminarRunCardMessagePart(
                  type: 'review_triage',
                  label: 'spaced-review',
                  text: 'Question?',
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
              triageItemsBuilder: _triageItems,
              reasonTextsBuilder: (_) => const [],
              candidateCardItemsBuilder: (_) => const [],
              reviewQuestionItemsBuilder: (_) => const [],
              riskLevelBuilder: (_) => 'low',
              riskLabelBuilder: _riskLabel,
              suggestedActionBuilder: (_) => 'send-to-review',
              suggestedActionLabelBuilder: _suggestedActionLabel,
              triageSuggestionTextBuilder: (_) => null,
              evidenceTileBuilder: (_) => const Text('Evidence tile'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Exception triage preview'), findsOneWidget);
    expect(find.text('Synthesis'), findsOneWidget);
    expect(find.text('Synthesis summary.'), findsOneWidget);
    expect(find.text('Traceable evidence: 2 sources'), findsOneWidget);
    expect(find.text('Review reasons'), findsOneWidget);
    expect(find.text('Needs review.'), findsOneWidget);
    expect(find.text('AI triage suggestion'), findsOneWidget);
    expect(find.text('Check manually.'), findsOneWidget);
    expect(find.text('AI risk level'), findsOneWidget);
    expect(find.text('Medium risk'), findsOneWidget);
    expect(find.text('Suggested action'), findsOneWidget);
    expect(find.text('Send to exception center'), findsOneWidget);
    expect(find.text('Exception Review payload'), findsOneWidget);
    expect(find.text('Synthesis: 1 item'), findsOneWidget);
    expect(find.text('KnowledgeCard candidates: 1 item'), findsOneWidget);
    expect(find.text('KnowledgeCard candidate details'), findsOneWidget);
    expect(find.text('Candidate card.'), findsOneWidget);
    expect(find.text('Spaced Review candidates: 1 item'), findsOneWidget);
    expect(find.text('Spaced Review candidate details'), findsOneWidget);
    expect(find.text('Question?'), findsOneWidget);
    expect(find.text('Evidence tile'), findsNWidgets(2));
  });
}

List<SeminarReviewPreviewItem> _triageItems(
  List<AiSeminarRunCardMessagePart> parts, {
  required String label,
}) {
  return parts
      .where((part) => part.label?.trim() == label)
      .map(
        (part) => SeminarReviewPreviewItem(
          text: part.text?.trim() ?? '',
          evidenceRefs: part.evidenceRefs,
        ),
      )
      .where((item) => !item.isEmpty)
      .toList(growable: false);
}

String _riskLabel(String? risk) => switch (risk?.trim()) {
      'medium' => 'Medium risk',
      'low' => 'Low risk',
      _ => risk?.trim() ?? '',
    };

String _suggestedActionLabel(String? action) => switch (action?.trim()) {
      'send-to-review' => 'Send to exception center',
      _ => action?.trim() ?? '',
    };
