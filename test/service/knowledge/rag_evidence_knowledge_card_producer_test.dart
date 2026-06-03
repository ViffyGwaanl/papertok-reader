import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/knowledge/rag_evidence_knowledge_card_producer.dart';
import 'package:papertok_reader/service/rag/semantic_search_library.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';

void main() {
  late Directory tempRoot;
  late KnowledgeCardStore cardStore;
  late ReviewItemStore reviewStore;
  late RagEvidenceKnowledgeCardProducer producer;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('rag-card-producer-');
    cardStore = KnowledgeCardStore(rootDir: tempRoot);
    reviewStore = ReviewItemStore(rootDir: tempRoot);
    producer = RagEvidenceKnowledgeCardProducer(
      cardStore: cardStore,
      reviewStore: reviewStore,
    );
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('derived library RAG result defaults to draft without Review', () async {
    final result = await producer.createFromLibrarySearchResult(
      derivedResult(
        derivedSummary:
            'GraphRAG community: Key themes: Attention, Memory. Evidence.',
      ),
      now: 100,
    );

    expect(result.inserted, true);
    expect(result.addedToReviewInbox, false);
    expect(result.reviewItem, isNull);
    expect(result.card.origin, KnowledgeCardOrigin.ragEvidence);
    expect(result.card.reviewState, KnowledgeCardReviewState.draft);
    expect(result.card.ownership, AiOutputOwnership.aiGeneratedDraft);
    expect(result.card.title, contains('attention memory'));
    expect(result.card.explanation, contains('GraphRAG community'));
    expect(result.card.quote, contains('Book chunk evidence'));
    expect(result.card.quote, isNot(contains('GraphRAG community')));
    expect(result.card.sourceRefs.single.canJumpBack, true);
    expect(result.card.sourceRefs.single.hasDerivedChunkHint, true);

    expect(await reviewStore.list(), isEmpty);
  });

  test('derived library RAG result can be explicitly sent to Review', () async {
    final result = await producer.createFromLibrarySearchResult(
      derivedResult(
        derivedSummary:
            'GraphRAG community: Key themes: Attention, Memory. Evidence.',
      ),
      createReviewItem: true,
      now: 100,
    );

    expect(result.inserted, true);
    expect(result.addedToReviewInbox, true);
    expect(result.card.reviewState, KnowledgeCardReviewState.pending);

    final reviewItems = await reviewStore.list(
      status: ReviewItemStatus.pending,
      sourceType: ReviewItemSourceType.knowledgeCard,
    );
    expect(reviewItems, hasLength(1));
    expect(reviewItems.single.sourceId, result.card.id);
    expect(reviewItems.single.sourceRefs.single.canJumpBack, true);
  });

  test('plain traceable library RAG result defaults to draft without Review',
      () async {
    final result = await producer.createFromLibrarySearchResult(
      derivedResult(derivedLayer: null, derivedSummary: null),
      now: 100,
    );

    expect(result.card.origin, KnowledgeCardOrigin.ragEvidence);
    expect(result.card.explanation, contains('RAG evidence saved'));
    expect(result.card.reviewState, KnowledgeCardReviewState.draft);
    expect(result.addedToReviewInbox, false);
    expect(await reviewStore.list(), isEmpty);
  });

  test('traceable RAG result can be saved as draft without Review', () async {
    final result = await producer.createFromLibrarySearchResult(
      derivedResult(),
      createReviewItem: false,
      now: 100,
    );

    expect(result.inserted, true);
    expect(result.addedToReviewInbox, false);
    expect(result.reviewItem, isNull);
    expect(result.card.origin, KnowledgeCardOrigin.ragEvidence);
    expect(result.card.reviewState, KnowledgeCardReviewState.draft);
    expect(result.card.sourceRefs.single.canJumpBack, true);
    expect(await reviewStore.list(), isEmpty);
  });

  test('draft RAG card fallback explanation does not mention Review', () async {
    final result = await producer.createFromLibrarySearchResult(
      derivedResult(derivedLayer: null, derivedSummary: null),
      createReviewItem: false,
      now: 100,
    );

    expect(result.card.reviewState, KnowledgeCardReviewState.draft);
    expect(result.card.explanation, contains('RAG evidence saved as draft'));
    expect(result.card.explanation, isNot(contains('review')));
    expect(await reviewStore.list(), isEmpty);
  });

  test('duplicate RAG result does not create duplicate cards', () async {
    final first = await producer.createFromLibrarySearchResult(
      derivedResult(),
      now: 100,
    );
    final second = await producer.createFromLibrarySearchResult(
      derivedResult(),
      now: 200,
    );

    expect(first.inserted, true);
    expect(second.inserted, false);
    expect(second.duplicateOfId, first.card.id);

    final cards = await cardStore.list(origin: KnowledgeCardOrigin.ragEvidence);
    expect(cards, hasLength(1));
  });

  test('untraceable RAG result is rejected before writing stores', () async {
    await expectLater(
      producer.createFromLibrarySearchResult(
        AiSemanticSearchLibraryResult(
          ok: true,
          query: 'attention memory',
          evidence: [
            AiSemanticSearchLibraryEvidence(
              bookId: 7,
              bookTitle: 'Graph Notes',
              href: 'Text/rag.xhtml',
              anchor: 'Chunk 77',
              snippet: 'Book chunk evidence without SourceRef.',
              jumpLink: '',
              score: 0.91,
            ),
          ],
        ),
        now: 100,
      ),
      throwsArgumentError,
    );

    expect(await cardStore.list(), isEmpty);
    expect(await reviewStore.list(), isEmpty);
  });

  test('traceable RAG result without chunk snippet is rejected', () async {
    await expectLater(
      producer.createFromLibrarySearchResult(
        AiSemanticSearchLibraryResult(
          ok: true,
          query: 'attention memory',
          evidence: [
            AiSemanticSearchLibraryEvidence(
              chunkId: 77,
              bookId: 7,
              bookTitle: 'Graph Notes',
              href: 'Text/rag.xhtml',
              anchor: 'Chunk 77',
              snippet: '   ',
              jumpLink:
                  'paperreader://reader/open?bookId=7&href=Text/rag.xhtml',
              score: 0.91,
              sourceRef: SourceRef(
                bookId: 7,
                href: 'Text/rag.xhtml',
                chunkId: 77,
                jumpLink:
                    'paperreader://reader/open?bookId=7&href=Text/rag.xhtml',
                sourceTitle: 'Graph Notes',
                locationLabel: 'Chunk 77',
                sourceKind: SourceRefKind.libraryRag,
                createdAt: 90,
              ),
              derivedLayer: 'graph',
              derivedSummary: 'Derived summary without formal chunk text.',
            ),
          ],
        ),
        now: 100,
      ),
      throwsArgumentError,
    );

    expect(await cardStore.list(), isEmpty);
    expect(await reviewStore.list(), isEmpty);
  });

  test('derived summary is clipped before card and review payload persistence',
      () async {
    final longSummary = List.filled(900, 'summary').join(' ');

    final result = await producer.createFromLibrarySearchResult(
      derivedResult(derivedSummary: longSummary),
      createReviewItem: true,
      now: 100,
    );

    expect(result.card.explanation.length, lessThanOrEqualTo(1200));
    final cardPayload =
        result.reviewItem!.payload['card'] as Map<String, dynamic>;
    expect(
      (cardPayload['explanation'] as String).length,
      lessThanOrEqualTo(1200),
    );
  });
}

AiSemanticSearchLibraryResult derivedResult({
  String? derivedLayer = 'graph',
  String? derivedSummary =
      'GraphRAG community: Key themes: Attention, Memory. Evidence.',
}) {
  return AiSemanticSearchLibraryResult(
    ok: true,
    query: 'attention memory',
    evidence: [
      AiSemanticSearchLibraryEvidence(
        chunkId: 77,
        bookId: 7,
        bookTitle: 'Graph Notes',
        href: 'Text/rag.xhtml',
        anchor: 'Chunk 77',
        snippet: 'Book chunk evidence for attention and memory.',
        jumpLink: 'paperreader://reader/open?bookId=7&href=Text/rag.xhtml',
        score: 0.91,
        sourceRef: SourceRef(
          bookId: 7,
          href: 'Text/rag.xhtml',
          chunkId: 77,
          jumpLink: 'paperreader://reader/open?bookId=7&href=Text/rag.xhtml',
          sourceTitle: 'Graph Notes',
          locationLabel: 'Chunk 77',
          sourceTextSnippet: 'Book chunk evidence for attention and memory.',
          sourceKind: SourceRefKind.libraryRag,
          createdAt: 90,
        ),
        derivedLayer: derivedLayer,
        derivedSummary: derivedSummary,
      ),
    ],
  );
}
