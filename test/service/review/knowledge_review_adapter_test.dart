import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/book_note.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/memory/memory_candidate.dart';
import 'package:papertok_reader/service/memory/memory_source_kind.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';

void main() {
  SourceRef ref() => SourceRef(
        bookId: 1,
        cfi: '/6/2[chapter]!/4/1:0',
        sourceTitle: 'Chapter 1',
        sourceTextSnippet: 'Evidence text',
        sourceKind: SourceRefKind.reader,
      );

  KnowledgeCard card({List<SourceRef>? sourceRefs}) => KnowledgeCard(
        id: 'card-1',
        title: 'Hybrid retrieval',
        quote: 'BM25 and vectors cover different failure modes.',
        explanation: 'Use lexical and dense retrieval together.',
        sourceRefs: sourceRefs ?? [ref()],
        origin: KnowledgeCardOrigin.seminar,
        createdAt: 100,
      );

  group('KnowledgeCardReviewAdapter', () {
    test('projects AI draft card into pending review item', () {
      final item = KnowledgeCardReviewAdapter.fromKnowledgeCard(card());

      expect(item.id, 'knowledge-card:card-1');
      expect(item.sourceType, ReviewItemSourceType.knowledgeCard);
      expect(item.status, ReviewItemStatus.pending);
      expect(item.hasTraceableSource, isTrue);
      expect(item.payload['card'], containsPair('origin', 'seminar'));
    });

    test('does not apply a card that has no traceable source', () {
      final sourceLess = card(sourceRefs: const []);
      final item = KnowledgeCardReviewAdapter.fromKnowledgeCard(
        sourceLess,
        status: ReviewItemStatus.approved,
      );

      final approved = KnowledgeCardReviewAdapter.applyReviewDecision(
        sourceLess,
        item,
      );
      expect(approved.canApply, isFalse);
      expect(
        () => item.transitionTo(ReviewItemStatus.applied, now: 200),
        throwsStateError,
      );
    });

    test('dismissed cards keep AI draft ownership', () {
      final pending = KnowledgeCardReviewAdapter.fromKnowledgeCard(card());
      final dismissed = pending.transitionTo(
        ReviewItemStatus.dismissed,
        now: 200,
        decisionSource: 'user_dismiss',
      );

      final dismissedCard = KnowledgeCardReviewAdapter.applyReviewDecision(
        card(),
        dismissed,
      );

      expect(dismissedCard.reviewState, KnowledgeCardReviewState.dismissed);
      expect(dismissedCard.ownership, AiOutputOwnership.aiGeneratedDraft);
      expect(dismissedCard.isUserAsset, false);
    });

    test('approved traceable card can become a spaced review item', () {
      final approved = card().copyWith(
        reviewState: KnowledgeCardReviewState.approved,
      );

      final spaced = KnowledgeCardReviewAdapter.toSpacedReviewItem(
        approved,
        id: 'review-1',
        dueAt: 200,
      );

      expect(spaced.cardId, 'card-1');
      expect(spaced.prompt, 'Hybrid retrieval');
      expect(spaced.answer, contains('lexical'));
      expect(spaced.dueAt, 200);
      expect(spaced.sourceRefs.single.hasEvidence, isTrue);
    });
  });

  group('MemoryCandidateReviewAdapter', () {
    test('projects existing memory candidate status and source ref', () {
      const candidate = MemoryCandidate(
        id: 'mem-1',
        summary: 'Remember RAG rule',
        text: 'Default to current book before library.',
        targetDoc: MemoryDocTarget.daily,
        sourceType: 'session_digest',
        createdAtMs: 100,
        status: MemoryCandidateStatus.pending,
        bookId: 7,
        cfi: '/6/2!/4/1:0',
        chapter: 'Search',
        sourceKind: MemorySourceKind.chat,
      );

      final item = MemoryCandidateReviewAdapter.fromMemoryCandidate(candidate);

      expect(item.id, 'memory-candidate:mem-1');
      expect(item.status, ReviewItemStatus.pending);
      expect(item.sourceRefs.single.sourceKind, SourceRefKind.memory);
      expect(item.sourceRefs.single.jumpLink, startsWith('paperreader://'));
      expect(item.payload['targetDoc'], 'daily');
    });

    test('conversation-only memory candidate keeps evidence with reason', () {
      const candidate = MemoryCandidate(
        id: 'mem-chat',
        summary: 'Remember chat preference',
        text: 'Prefer concise Chinese answers.',
        targetDoc: MemoryDocTarget.daily,
        sourceType: 'manual_save',
        createdAtMs: 120,
        status: MemoryCandidateStatus.pending,
        sourcePointer: 'conversation-1#node-2',
        sourceKind: MemorySourceKind.chat,
      );

      final item = MemoryCandidateReviewAdapter.fromMemoryCandidate(candidate);

      expect(item.sourceRefs.single.sourceKind, SourceRefKind.memory);
      expect(item.sourceRefs.single.sourceTextSnippet,
          'Prefer concise Chinese answers.');
      expect(item.sourceRefs.single.sourceHash, isNotEmpty);
      expect(item.sourceRefs.single.hasUnavailableReason, isTrue);
      expect(item.sourceRefs.single.hasEvidence, isTrue);
    });
  });

  group('BookNoteSourceRefAdapter', () {
    test('turns highlights into traceable source refs', () {
      final note = BookNote(
        id: 9,
        bookId: 3,
        content: 'A useful highlighted paragraph',
        cfi: '/6/4!/4/5:2',
        chapter: 'Evidence',
        type: 'highlight',
        color: 'ffff00',
        updateTime: DateTime.fromMillisecondsSinceEpoch(300),
      );

      final sourceRef = BookNoteSourceRefAdapter.fromBookNote(
        note,
        sourceTitle: 'PaperTok Notes',
      );

      expect(sourceRef.sourceKind, SourceRefKind.highlight);
      expect(sourceRef.bookId, 3);
      expect(sourceRef.sourceTextSnippet, 'A useful highlighted paragraph');
      expect(sourceRef.jumpLink, startsWith('paperreader://reader/open?'));
      expect(sourceRef.hasEvidence, isTrue);
      expect(sourceRef.canJumpBack, isTrue);
    });

    test('marks old notes without cfi as unavailable instead of jumpable', () {
      final note = BookNote(
        id: 10,
        bookId: 3,
        content: 'A migrated reader note without location',
        cfi: '',
        chapter: 'Migrated notes',
        type: 'note',
        color: 'ffff00',
        updateTime: DateTime.fromMillisecondsSinceEpoch(400),
      );

      final sourceRef = BookNoteSourceRefAdapter.fromBookNote(
        note,
        sourceTitle: 'PaperTok Notes',
      );

      expect(sourceRef.sourceKind, SourceRefKind.note);
      expect(sourceRef.canJumpBack, isFalse);
      expect(sourceRef.jumpLink, isNull);
      expect(sourceRef.hasUnavailableReason, isTrue);
      expect(sourceRef.unavailableReason,
          contains('book-note-source-not-jumpable'));
      expect(sourceRef.hasEvidence, isTrue);
    });

    test('does not build reader intent for notes with invalid book anchors',
        () {
      final note = BookNote(
        id: 11,
        bookId: 0,
        content: 'A migrated note with stale cfi',
        cfi: 'epubcfi(/6/8)',
        chapter: 'Migrated notes',
        type: 'highlight',
        color: 'ffff00',
        updateTime: DateTime.fromMillisecondsSinceEpoch(500),
      );

      final sourceRef = BookNoteSourceRefAdapter.fromBookNote(note);
      final intent = BookNoteSourceRefAdapter.readerIntentForBookNote(note);

      expect(sourceRef.canJumpBack, isFalse);
      expect(sourceRef.hasUnavailableReason, isTrue);
      expect(intent, isNull);
    });
  });

  group('FlashcardReviewAdapter', () {
    test('requires approval and evidence before creating spaced review item',
        () {
      final pending = FlashcardReviewAdapter.fromFlashcardCandidate(
        id: 'flash-1',
        prompt: 'What should RAG evidence include?',
        answer: 'A SourceRef and jump link.',
        sourceRefs: [ref()],
        now: 100,
      );

      expect(pending.status, ReviewItemStatus.pending);
      expect(
        () => FlashcardReviewAdapter.toSpacedReviewItem(
          pending,
          id: 'spaced-1',
        ),
        throwsStateError,
      );

      final approved = pending.transitionTo(
        ReviewItemStatus.approved,
        now: 200,
        decisionSource: 'user_approve',
      );
      final spaced = FlashcardReviewAdapter.toSpacedReviewItem(
        approved,
        id: 'spaced-1',
      );

      expect(spaced.cardId, 'flash-1');
      expect(spaced.prompt, 'What should RAG evidence include?');
      expect(spaced.sourceRefs.single.hasEvidence, isTrue);
    });
  });

  group('Seminar flashcard handoff', () {
    test('projects candidate review questions into flashcard review items', () {
      final synthesis = AiSeminarSynthesis(
        summary: 'Use SourceRef-backed evidence.',
        supportiveView: 'The evidence is actionable.',
        criticalView: 'The evidence can be stale.',
        evidenceRefIds: const ['e1'],
        evidence: [
          AiSeminarEvidence(
            id: 'e1',
            scope: AiSeminarEvidenceScope.currentBook,
            text: 'Evidence text',
            sourceRef: ref(),
          ),
        ],
        candidateReviewQuestions: const [
          'What does every RAG answer need?',
          'What should stay out of formal knowledge?',
        ],
        readyForReview: true,
      );

      final flashcards = SeminarSynthesisReviewAdapter.flashcardsFromSynthesis(
        seminarId: 's1',
        synthesis: synthesis,
        now: 100,
      );

      expect(flashcards, hasLength(2));
      expect(flashcards.first.id, 'flashcard:seminar:s1:question-1');
      expect(
          flashcards.first.sourceType, ReviewItemSourceType.flashcardCandidate);
      expect(flashcards.first.status, ReviewItemStatus.pending);
      expect(flashcards.first.title, 'What does every RAG answer need?');
      expect(flashcards.first.body, 'Use SourceRef-backed evidence.');
      expect(flashcards.first.hasTraceableSource, true);
    });
  });

  group('ConceptGraphReviewAdapter', () {
    ConceptEdge relation({
      String id = 'edge-1',
      List<SourceRef>? evidenceRefs,
    }) {
      return ConceptEdge(
        id: id,
        sourceNodeId: 'n1',
        targetNodeId: 'n2',
        type: ConceptEdgeType.supports,
        label: 'n1 supports n2',
        evidenceRefs: evidenceRefs ?? [ref()],
        confidence: 0.72,
      );
    }

    test('projects graph relation into pending review item', () {
      final item = ConceptGraphReviewAdapter.fromRelation(relation());

      expect(item.id, 'concept-graph-relation:edge-1');
      expect(item.sourceType, ReviewItemSourceType.conceptGraphRelation);
      expect(item.status, ReviewItemStatus.pending);
      expect(item.sourceRefs.single.hasEvidence, isTrue);
      expect(item.payload['edge'], containsPair('type', 'supports'));
    });

    test('only applied graph relation becomes formal ownership', () {
      final pending = ConceptGraphReviewAdapter.fromRelation(relation());
      final approved = pending.transitionTo(
        ReviewItemStatus.approved,
        now: 200,
        decisionSource: 'user_approve',
      );
      final applied = approved.transitionTo(
        ReviewItemStatus.applied,
        now: 300,
        decisionSource: 'user_apply',
      );

      final approvedEdge = ConceptGraphReviewAdapter.applyReviewDecision(
        relation(),
        approved,
      );
      final appliedEdge = ConceptGraphReviewAdapter.applyReviewDecision(
        relation(),
        applied,
      );

      expect(approvedEdge.ownership, AiOutputOwnership.aiGeneratedDraft);
      expect(approvedEdge.isFormal, false);
      expect(appliedEdge.ownership, AiOutputOwnership.aiGeneratedApproved);
      expect(appliedEdge.isFormal, true);
    });

    test('untraceable graph relation cannot be projected as applied', () {
      final edge = relation(evidenceRefs: const []);
      final item = ConceptGraphReviewAdapter.fromRelation(
        edge,
        status: ReviewItemStatus.applied,
      );

      expect(item.status, ReviewItemStatus.approved);
      final restored = ConceptGraphReviewAdapter.applyReviewDecision(
        edge,
        item,
      );
      expect(restored.ownership, AiOutputOwnership.aiGeneratedDraft);
      expect(restored.isFormal, false);
    });
  });
}
