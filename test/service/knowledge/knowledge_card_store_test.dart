import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/knowledge_sync.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('knowledge_card_store_');
  });

  tearDown(() async {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  SourceRef traceableRef({
    int bookId = 1,
    String href = 'Text/ch.xhtml',
    String cfi = 'epubcfi(/6/4)',
    String snippet = 'The source passage.',
  }) =>
      SourceRef(
        bookId: bookId,
        href: href,
        cfi: cfi,
        sourceTextSnippet: snippet,
        sourceKind: SourceRefKind.highlight,
      );

  KnowledgeCard card({
    String id = 'card-1',
    String title = 'Hidden premise',
    String quote = 'The source passage.',
    String explanation = 'The author depends on an unstated assumption.',
    String? userNote,
    KnowledgeCardReviewState reviewState = KnowledgeCardReviewState.pending,
    AiOutputOwnership ownership = AiOutputOwnership.aiGeneratedDraft,
    List<SourceRef>? sourceRefs,
    int createdAt = 100,
  }) {
    return KnowledgeCard(
      id: id,
      title: title,
      quote: quote,
      explanation: explanation,
      userNote: userNote,
      reviewState: reviewState,
      ownership: ownership,
      sourceRefs: sourceRefs ?? [traceableRef(snippet: quote)],
      origin: KnowledgeCardOrigin.seminar,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  test('first candidate write creates versioned knowledge card file', () async {
    final store = KnowledgeCardStore(rootDir: tempRoot);

    final result = await store.upsertCandidate(card());

    expect(result.inserted, true);
    expect(result.duplicateOfId, isNull);
    final cardsFile = File(
      p.join(tempRoot.path, '.knowledge', 'knowledge_cards_v1.json'),
    );
    expect(cardsFile.existsSync(), isTrue);
    final decoded =
        jsonDecode(cardsFile.readAsStringSync()) as Map<String, dynamic>;
    expect(decoded['version'], 1);
    final cards = decoded['cards'] as List;
    expect(cards, hasLength(1));
    final stored = cards.single as Map;
    expect(stored['id'], 'card-1');
    expect(stored['entityType'], 'ai-draft');
    expect((stored['payload'] as Map)['id'], 'card-1');
  });

  test(
      'duplicate candidate returns existing card without overwriting user note',
      () async {
    final store = KnowledgeCardStore(rootDir: tempRoot);
    await store.upsertCandidate(
      card(
        id: 'original',
        userNote: 'Keep this user note.',
        createdAt: 100,
      ),
    );

    final result = await store.upsertCandidate(
      card(
        id: 'duplicate',
        title: 'Generated again',
        quote: '  the source   passage. ',
        explanation: 'Different generated explanation.',
        createdAt: 200,
      ),
    );

    expect(result.inserted, false);
    expect(result.duplicateOfId, 'original');
    expect(result.card.id, 'original');
    expect(result.card.userNote, 'Keep this user note.');
    final cards = await store.list();
    expect(cards, hasLength(1));
    expect(cards.single.id, 'original');
  });

  test('same-id candidate conflict does not overwrite existing user content',
      () async {
    final store = KnowledgeCardStore(rootDir: tempRoot);
    await store.upsertCandidate(
      card(
        id: 'same-id',
        quote: 'Original quote',
        userNote: 'Keep this user note.',
        createdAt: 100,
      ),
    );

    final result = await store.upsertCandidate(
      card(
        id: 'same-id',
        title: 'Regenerated title',
        quote: 'Different quote that misses heuristic dedupe.',
        explanation: 'Different generated explanation.',
        createdAt: 200,
        sourceRefs: [traceableRef(cfi: 'epubcfi(/6/8)', snippet: 'Different')],
      ),
    );

    expect(result.inserted, false);
    expect(result.duplicateOfId, 'same-id');
    final restored = await store.getById('same-id');
    expect(restored!.title, 'Hidden premise');
    expect(restored.quote, 'Original quote');
    expect(restored.userNote, 'Keep this user note.');
  });

  test('candidate writes cannot bypass review by arriving as applied',
      () async {
    final store = KnowledgeCardStore(rootDir: tempRoot);
    final appliedCandidate = card(
      id: 'pre-applied',
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
    );

    final result = await store.upsertCandidate(appliedCandidate);

    expect(result.inserted, true);
    expect(result.card.reviewState, KnowledgeCardReviewState.pending);
    expect(result.card.ownership, AiOutputOwnership.aiGeneratedDraft);
    expect(result.card.isUserAsset, false);
    final cardsFile = File(
      p.join(tempRoot.path, '.knowledge', 'knowledge_cards_v1.json'),
    );
    final decoded =
        jsonDecode(cardsFile.readAsStringSync()) as Map<String, dynamic>;
    final stored = (decoded['cards'] as List).single as Map;
    expect(stored['entityType'], 'ai-draft');
    expect((stored['payload'] as Map)['reviewState'], 'pending');
    expect((stored['payload'] as Map)['ownership'], 'AI-generated-draft');
  });

  test('raw upsert cannot persist applied user assets', () async {
    final store = KnowledgeCardStore(rootDir: tempRoot);

    expect(
      () => store.upsert(
        card(
          id: 'direct-applied',
          reviewState: KnowledgeCardReviewState.applied,
          ownership: AiOutputOwnership.aiGeneratedApproved,
        ),
      ),
      throwsArgumentError,
    );

    expect(await store.list(), isEmpty);
  });

  test('applies ReviewItem decisions to the stored card without writing memory',
      () async {
    final store = KnowledgeCardStore(rootDir: tempRoot);
    await store.upsertCandidate(card(id: 'kc-review'));
    final pending = KnowledgeCardReviewAdapter.fromKnowledgeCard(
      card(id: 'kc-review'),
    );
    final approved = pending.transitionTo(
      ReviewItemStatus.approved,
      now: 200,
      decisionSource: 'user_approve',
    );
    final appliedReview = approved.transitionTo(
      ReviewItemStatus.applied,
      now: 300,
      decisionSource: 'user_apply',
    );

    final approvedCard = await store.applyReviewDecision(approved, now: 200);
    final appliedCard =
        await store.applyReviewDecision(appliedReview, now: 300);

    expect(approvedCard.reviewState, KnowledgeCardReviewState.approved);
    expect(approvedCard.ownership, AiOutputOwnership.aiGeneratedApproved);
    expect(appliedCard.reviewState, KnowledgeCardReviewState.applied);
    expect(appliedCard.isUserAsset, true);
    expect(appliedCard.sourceRefs.single.hasEvidence, true);
    final restored = await store.getById('kc-review');
    expect(restored!.reviewState, KnowledgeCardReviewState.applied);
    final cardsFile = File(
      p.join(tempRoot.path, '.knowledge', 'knowledge_cards_v1.json'),
    );
    final decoded =
        jsonDecode(cardsFile.readAsStringSync()) as Map<String, dynamic>;
    final stored = (decoded['cards'] as List).single as Map;
    expect(stored['entityType'], 'knowledge-card');
  });

  test('rejects review decisions for missing or mismatched card sources',
      () async {
    final store = KnowledgeCardStore(rootDir: tempRoot);
    await store.upsertCandidate(card(id: 'kc-existing'));

    final wrongType = ReviewItem(
      id: 'seminar-synthesis:s1',
      sourceType: ReviewItemSourceType.seminarSynthesis,
      sourceId: 's1',
      title: 'Seminar',
      body: 'Body',
      status: ReviewItemStatus.approved,
      sourceRefs: [traceableRef()],
    );
    final missingCard = ReviewItem(
      id: 'knowledge-card:missing',
      sourceType: ReviewItemSourceType.knowledgeCard,
      sourceId: 'missing',
      title: 'Missing',
      body: 'Body',
      status: ReviewItemStatus.approved,
      sourceRefs: [traceableRef()],
    );

    expect(
      () => store.applyReviewDecision(wrongType, now: 200),
      throwsArgumentError,
    );
    expect(
      () => store.applyReviewDecision(missingCard, now: 200),
      throwsStateError,
    );
  });

  test('legacy applied card without traceable source is downgraded on read',
      () async {
    final file = File(
      p.join(tempRoot.path, '.knowledge', 'knowledge_cards_v1.json'),
    );
    file.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({
        'version': 1,
        'cards': [
          {
            'id': 'orphan',
            'title': 'Orphan',
            'quote': 'Detached quote',
            'explanation': 'No traceable source.',
            'reviewState': 'applied',
            'ownership': AiOutputOwnership.aiGeneratedApproved.asString,
            'sourceRefs': [],
          }
        ],
      }),
    );

    final store = KnowledgeCardStore(rootDir: tempRoot);
    final restored = await store.getById('orphan');

    expect(restored!.reviewState, KnowledgeCardReviewState.approved);
    expect(restored.isUserAsset, false);
  });

  test('sync envelopes preserve pending conflict metadata on read', () async {
    final conflictCard = card(
      id: 'kc-conflict',
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
    );
    final envelope = KnowledgeSyncEnvelope(
      id: conflictCard.id,
      entityType: KnowledgeSyncEntityType.knowledgeCard,
      schemaVersion: 1,
      updatedAt: 200,
      conflictStatus: KnowledgeSyncConflictStatus.pendingReview,
      conflictReason: 'content-conflict',
      sourceRefs: conflictCard.sourceRefs,
      payload: conflictCard.toJson(),
    );
    final file = File(
      p.join(tempRoot.path, '.knowledge', 'knowledge_cards_v1.json'),
    );
    file.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({
        'version': 1,
        'cards': [envelope.toJson()],
      }),
    );

    final store = KnowledgeCardStore(rootDir: tempRoot);
    final cards = await store.list();
    final envelopes = await store.listSyncEnvelopes();

    expect(cards.single.isUserAsset, true);
    expect(envelopes.single.requiresConflictReview, true);
    expect(envelopes.single.conflictReason, 'content-conflict');
  });

  test('malformed card file degrades to an empty card list', () async {
    final file = File(
      p.join(tempRoot.path, '.knowledge', 'knowledge_cards_v1.json'),
    );
    file.createSync(recursive: true);
    file.writeAsStringSync('{bad json');

    final store = KnowledgeCardStore(rootDir: tempRoot);

    expect(await store.list(), isEmpty);
  });
}
