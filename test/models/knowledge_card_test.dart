import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/source_ref.dart';

void main() {
  test('AI generated card defaults to draft and is not a user asset', () {
    final card = KnowledgeCard(
      id: 'card1',
      title: 'Hidden premise',
      quote: 'The premise is implied.',
      explanation: 'The author depends on an unstated assumption.',
      sourceRefs: [
        SourceRef(
          bookId: 1,
          href: 'Text/ch.xhtml',
          sourceTextSnippet: 'The premise is implied.',
          sourceKind: SourceRefKind.currentBookRag,
        ),
      ],
      origin: KnowledgeCardOrigin.seminar,
    );

    expect(card.reviewState, KnowledgeCardReviewState.draft);
    expect(card.ownership, AiOutputOwnership.aiGeneratedDraft);
    expect(card.hasTraceableSource, true);
    expect(card.canApply, false);
    expect(card.isUserAsset, false);
  });

  test('approved traceable card can be applied after review', () {
    final card = KnowledgeCard(
      id: 'card1',
      title: 'Concept',
      quote: 'Quote',
      explanation: 'Explanation',
      reviewState: KnowledgeCardReviewState.approved,
      ownership: AiOutputOwnership.aiGeneratedApproved,
      sourceRefs: [
        SourceRef(
          bookId: 2,
          cfi: 'epubcfi(/6/2)',
          sourceKind: SourceRefKind.reader,
        ),
      ],
    );

    expect(card.canApply, true);
    final applied = card.copyWith(
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
    );
    expect(applied.isUserAsset, true);

    final restored = KnowledgeCard.fromJson(applied.toJson());
    expect(restored.sourceRefs.single.cfi, 'epubcfi(/6/2)');
    expect(restored.reviewState, KnowledgeCardReviewState.applied);
  });

  test('source hash alone does not make a card traceable', () {
    final card = KnowledgeCard(
      id: 'card1',
      title: 'Detached claim',
      quote: 'Quote',
      explanation: 'Explanation',
      reviewState: KnowledgeCardReviewState.approved,
      ownership: AiOutputOwnership.aiGeneratedApproved,
      sourceRefs: [
        SourceRef(
          sourceTextSnippet: 'Only a detached snippet',
          sourceKind: SourceRefKind.external,
        ),
      ],
    );

    expect(card.sourceRefs.single.sourceHash, isNotNull);
    expect(card.hasTraceableSource, isFalse);
    expect(card.canApply, isFalse);
    final applied =
        card.copyWith(reviewState: KnowledgeCardReviewState.applied);
    expect(applied.isUserAsset, isFalse);
    expect(applied.reviewState, KnowledgeCardReviewState.approved);
  });

  test('applied card without traceable evidence is downgraded on restore', () {
    final restored = KnowledgeCard.fromJson({
      'id': 'card2',
      'title': 'Detached claim',
      'quote': 'Quote',
      'explanation': 'Explanation',
      'reviewState': 'applied',
      'ownership': AiOutputOwnership.aiGeneratedApproved.asString,
      'sourceRefs': [
        SourceRef(
          sourceTextSnippet: 'Only a detached snippet',
          sourceKind: SourceRefKind.external,
        ).toSafeJson(),
      ],
    });

    expect(restored.sourceRefs.single.sourceHash, isNotNull);
    expect(restored.hasTraceableSource, isFalse);
    expect(restored.reviewState, KnowledgeCardReviewState.approved);
    expect(restored.isUserAsset, isFalse);
  });

  test('applied card with draft ownership is downgraded', () {
    final card = KnowledgeCard(
      id: 'card3',
      title: 'Traceable but still draft-owned',
      quote: 'Quote',
      explanation: 'Explanation',
      reviewState: KnowledgeCardReviewState.applied,
      sourceRefs: [
        SourceRef(
          bookId: 1,
          href: 'Text/ch.xhtml',
          sourceKind: SourceRefKind.currentBookRag,
        ),
      ],
    );

    expect(card.hasTraceableSource, isTrue);
    expect(card.reviewState, KnowledgeCardReviewState.approved);
    expect(card.isUserAsset, isFalse);
  });

  test('dedupe catches same source hash and normalized quote', () {
    final a = KnowledgeCard(
      id: 'a',
      title: 'A',
      quote: '  The Same   Quote ',
      explanation: 'A',
      sourceRefs: [
        SourceRef(
          bookId: 1,
          href: 'Text/ch.xhtml',
          sourceTextSnippet: 'The same quote',
          sourceKind: SourceRefKind.currentBookRag,
        ),
      ],
    );
    final b = KnowledgeCard(
      id: 'b',
      title: 'B',
      quote: 'the same quote',
      explanation: 'B',
      sourceRefs: [
        SourceRef(
          bookId: 1,
          href: 'Text/ch.xhtml',
          sourceTextSnippet: 'The same quote',
          sourceKind: SourceRefKind.currentBookRag,
        ),
      ],
    );

    expect(KnowledgeCardDedupe.isLikelyDuplicate(a, b), true);
  });

  test('same book anchor dedupes without relying on ai_index chunk id', () {
    final a = KnowledgeCard(
      id: 'a',
      title: 'A',
      quote: 'quote a',
      explanation: 'A',
      sourceRefs: [
        SourceRef(
          bookId: 1,
          href: 'Text/ch.xhtml',
          chunkId: 10,
          sourceKind: SourceRefKind.libraryRag,
        ),
      ],
    );
    final b = KnowledgeCard(
      id: 'b',
      title: 'B',
      quote: 'quote b',
      explanation: 'B',
      sourceRefs: [
        SourceRef(
          bookId: 1,
          href: 'Text/ch.xhtml',
          chunkId: 20,
          sourceKind: SourceRefKind.libraryRag,
        ),
      ],
    );

    expect(KnowledgeCardDedupe.isLikelyDuplicate(a, b), true);
  });
}
