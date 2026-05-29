import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';

void main() {
  SourceRef traceableRef() => SourceRef(
        bookId: 1,
        href: 'Text/ch.xhtml',
        sourceTextSnippet: 'The source passage.',
        sourceKind: SourceRefKind.currentBookRag,
      );

  AiSeminarSynthesis synthesis({
    bool traceable = true,
    bool readyForReview = true,
    List<AiSeminarWhiteboardEntry> candidateCards = const [
      AiSeminarWhiteboardEntry(
        id: 'card1',
        kind: AiSeminarWhiteboardKind.candidateCard,
        text: 'Hidden premise card',
        evidenceRefIds: ['e1'],
      ),
    ],
  }) =>
      AiSeminarSynthesis(
        summary: 'Balanced summary',
        supportiveView: 'Supportive view',
        criticalView: 'Critical view',
        candidateCards: candidateCards,
        candidateReviewQuestions: const ['What assumption matters most?'],
        evidenceRefIds: const ['e1'],
        evidence: [
          AiSeminarEvidence(
            id: 'e1',
            scope: AiSeminarEvidenceScope.currentBook,
            text: 'The source passage.',
            sourceRef: traceable
                ? traceableRef()
                : SourceRef(
                    sourceTextSnippet: 'Detached text.',
                    sourceKind: SourceRefKind.external,
                  ),
          ),
        ],
        readyForReview: readyForReview,
      );

  test('projects traceable seminar synthesis into pending review item', () {
    final item = SeminarSynthesisReviewAdapter.fromSynthesis(
      seminarId: 's1',
      synthesis: synthesis(),
      now: 100,
    );

    expect(item.sourceType, ReviewItemSourceType.seminarSynthesis);
    expect(item.status, ReviewItemStatus.pending);
    expect(item.sourceRefs.single.hasEvidence, true);
    expect(item.payload['summary'], 'Balanced summary');
    expect(item.payload['candidateReviewQuestions'], isNotEmpty);
  });

  test('keeps untraceable seminar synthesis as draft review item', () {
    final item = SeminarSynthesisReviewAdapter.fromSynthesis(
      seminarId: 's2',
      synthesis: synthesis(traceable: false),
      now: 100,
    );

    expect(item.status, ReviewItemStatus.draft);
    expect(item.canApply, false);
    expect(item.sourceRefs, isEmpty);
  });

  test('creates pending KnowledgeCard candidates without user-asset writes',
      () {
    final cards = SeminarSynthesisReviewAdapter.knowledgeCardsFromSynthesis(
      seminarId: 's1',
      synthesis: synthesis(),
      now: 100,
    );

    expect(cards, hasLength(1));
    expect(cards.single.origin, KnowledgeCardOrigin.seminar);
    expect(cards.single.reviewState, KnowledgeCardReviewState.pending);
    expect(cards.single.ownership, AiOutputOwnership.aiGeneratedDraft);
    expect(cards.single.isUserAsset, false);
    expect(cards.single.sourceRefs.single.hasEvidence, true);
  });

  test('carries seminar candidate concepts into KnowledgeCard candidates', () {
    final cards = SeminarSynthesisReviewAdapter.knowledgeCardsFromSynthesis(
      seminarId: 's1',
      synthesis: synthesis(
        candidateCards: const [
          AiSeminarWhiteboardEntry(
            id: 'card1',
            kind: AiSeminarWhiteboardKind.candidateCard,
            text: 'Hidden premise card',
            evidenceRefIds: ['e1'],
            conceptRefs: ['Hidden premise', 'Argument structure'],
          ),
        ],
      ),
      now: 100,
    );

    expect(cards.single.conceptRefs, [
      'Hidden premise',
      'Argument structure',
    ]);
    expect(cards.single.origin, KnowledgeCardOrigin.seminar);
    expect(cards.single.isUserAsset, false);
  });

  test('keeps explicitly not-ready synthesis in draft and creates no cards',
      () {
    final notReady = synthesis(readyForReview: false);

    final item = SeminarSynthesisReviewAdapter.fromSynthesis(
      seminarId: 's3',
      synthesis: notReady,
      now: 100,
    );
    final cards = SeminarSynthesisReviewAdapter.knowledgeCardsFromSynthesis(
      seminarId: 's3',
      synthesis: notReady,
      now: 100,
    );

    expect(item.status, ReviewItemStatus.draft);
    expect(item.sourceRefs, isEmpty);
    expect(cards, isEmpty);
  });

  test('dedupes blank and duplicate candidate card ids during handoff', () {
    final cards = SeminarSynthesisReviewAdapter.knowledgeCardsFromSynthesis(
      seminarId: 's4',
      synthesis: synthesis(
        candidateCards: const [
          AiSeminarWhiteboardEntry(
            id: '',
            kind: AiSeminarWhiteboardKind.candidateCard,
            text: 'Blank id card',
            evidenceRefIds: ['e1'],
          ),
          AiSeminarWhiteboardEntry(
            id: 'dup',
            kind: AiSeminarWhiteboardKind.candidateCard,
            text: 'First duplicate card',
            evidenceRefIds: ['e1'],
          ),
          AiSeminarWhiteboardEntry(
            id: 'dup',
            kind: AiSeminarWhiteboardKind.candidateCard,
            text: 'Second duplicate card',
            evidenceRefIds: ['e1'],
          ),
        ],
      ),
      now: 100,
    );

    expect(cards.map((card) => card.id).toSet(), hasLength(cards.length));
    expect(cards.map((card) => card.id), [
      'seminar:s4:card-1',
      'seminar:s4:dup',
      'seminar:s4:dup-2',
    ]);
  });
}
