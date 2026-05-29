import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/providers/ai_seminar_runtime.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/ai/ai_seminar_runtime_service.dart';
import 'package:papertok_reader/service/review/review_inbox_controller.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';

void main() {
  SourceRef traceableRef() => SourceRef(
        bookId: 7,
        href: 'Text/ch.xhtml',
        cfi: 'epubcfi(/6/8)',
        jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
        sourceTextSnippet: 'The source passage.',
        sourceKind: SourceRefKind.currentBookRag,
      );

  AiSeminarEvidenceBundle bundle() => AiSeminarEvidenceBundle(
        query: 'What is the claim?',
        evidence: [
          AiSeminarEvidence(
            id: 'e1',
            scope: AiSeminarEvidenceScope.currentBook,
            text: 'The source passage.',
            sourceRef: traceableRef(),
          ),
        ],
      );

  AiSeminarRuntimeService service({bool failFirst = false}) {
    var calls = 0;
    return AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        calls += 1;
        if (failFirst && calls == 1) {
          throw StateError('model unavailable');
        }
        yield AiSeminarRoleStreamChunk(
          partialText: '${invocation.role.asString} partial',
        );
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
            whiteboardEntries: [
              if (invocation.role == AiSeminarRole.synthesizer)
                const AiSeminarWhiteboardEntry(
                  id: 'card-1',
                  kind: AiSeminarWhiteboardKind.candidateCard,
                  text: 'Candidate card',
                  evidenceRefIds: ['e1'],
                  conceptRefs: ['Seminar concept'],
                ),
            ],
          ),
        );
      },
      now: () => 1000,
    );
  }

  test('start captures evidence role turns whiteboard and synthesis', () async {
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(aiSeminarRuntimeProvider.notifier).start(
          AiSeminarSessionContract(id: 's1', question: 'Explain this.'),
        );
    final state = container.read(aiSeminarRuntimeProvider);

    expect(state.status, AiSeminarRunStatus.completed);
    expect(state.evidenceBundle!.evidence.single.id, 'e1');
    expect(state.turns.map((turn) => turn.role), [
      AiSeminarRole.critical,
      AiSeminarRole.supportive,
      AiSeminarRole.synthesizer,
    ]);
    expect(state.whiteboardEntries.single.id, 'card-1');
    expect(state.synthesis!.summary, 'synthesizer response');
    expect(state.canRetry, false);
  });

  test('retry clears failed partial state and reruns the same session',
      () async {
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(
          service(failFirst: true),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(aiSeminarRuntimeProvider.notifier);

    await notifier.start(
      AiSeminarSessionContract(id: 's2', question: 'Retry this.'),
    );
    expect(container.read(aiSeminarRuntimeProvider).status,
        AiSeminarRunStatus.failed);

    await notifier.retry();
    final state = container.read(aiSeminarRuntimeProvider);

    expect(state.status, AiSeminarRunStatus.completed);
    expect(state.partialRoleText, isNull);
    expect(state.activeRole, isNull);
    expect(state.turns, hasLength(3));
  });

  test('state serializes enough runtime data for restoration', () async {
    final state = AiSeminarRuntimeState.initial().copyWith(
      session: AiSeminarSessionContract(id: 's3', question: 'Restore?'),
      status: AiSeminarRunStatus.running,
      evidenceBundle: bundle(),
      activeRole: AiSeminarRole.critical,
      partialRoleText: 'critical partial',
    );

    final restored = AiSeminarRuntimeState.fromJson(state.toJson());

    expect(restored.session!.id, 's3');
    expect(restored.status, AiSeminarRunStatus.running);
    expect(restored.evidenceBundle!.evidence.single.id, 'e1');
    expect(restored.activeRole, AiSeminarRole.critical);
    expect(restored.partialRoleText, 'critical partial');
  });

  test('sendToReview hands off synthesis and candidate cards', () async {
    final tempRoot = await Directory.systemTemp.createTemp();
    addTearDown(() => tempRoot.deleteSync(recursive: true));
    final reviewStore = ReviewItemStore(rootDir: tempRoot);
    final cardStore = KnowledgeCardStore(rootDir: tempRoot);
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
        aiSeminarReviewItemStoreProvider.overrideWithValue(reviewStore),
        aiSeminarKnowledgeCardStoreProvider.overrideWithValue(cardStore),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(aiSeminarRuntimeProvider.notifier);
    await notifier.start(
      AiSeminarSessionContract(id: 's4', question: 'Send this to Review.'),
    );

    final result = await notifier.sendToReview(now: 200);
    final pendingItems =
        await reviewStore.list(status: ReviewItemStatus.pending);
    final seminarCards =
        await cardStore.list(origin: KnowledgeCardOrigin.seminar);

    expect(result.reviewItemId, 'seminar-synthesis:s4');
    expect(result.knowledgeCardIds, ['seminar:s4:card-1']);
    expect(
      pendingItems.map((item) => item.sourceType).toSet(),
      containsAll({
        ReviewItemSourceType.seminarSynthesis,
        ReviewItemSourceType.knowledgeCard,
      }),
    );
    expect(seminarCards.single.reviewState, KnowledgeCardReviewState.pending);
    expect(seminarCards.single.isUserAsset, false);
    expect(seminarCards.single.conceptRefs, ['Seminar concept']);
  });

  test('seminar candidate concepts seed graph candidates after Review apply',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp();
    addTearDown(() => tempRoot.deleteSync(recursive: true));
    final reviewStore = ReviewItemStore(rootDir: tempRoot);
    final cardStore = KnowledgeCardStore(rootDir: tempRoot);
    final graphStore = ConceptGraphStore(rootDir: tempRoot);
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
        aiSeminarReviewItemStoreProvider.overrideWithValue(reviewStore),
        aiSeminarKnowledgeCardStoreProvider.overrideWithValue(cardStore),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(aiSeminarRuntimeProvider.notifier);

    await notifier.start(
      AiSeminarSessionContract(id: 's6', question: 'Seed graph.'),
    );
    await notifier.sendToReview(now: 400);
    final cardItem = (await reviewStore.list(
      status: ReviewItemStatus.pending,
      sourceType: ReviewItemSourceType.knowledgeCard,
    ))
        .single;
    final controller = ReviewInboxController(
      rootDir: tempRoot,
      reviewStore: reviewStore,
      knowledgeCardStore: cardStore,
      conceptGraphStore: graphStore,
      now: () => 401,
    );

    await controller.approve(cardItem.id);
    await controller.apply(cardItem.id);

    final conceptNodes = (await graphStore.listNodes())
        .where((node) => node.type == ConceptNodeType.concept)
        .toList(growable: false);
    final relationItems = await reviewStore.list(
      status: ReviewItemStatus.pending,
      sourceType: ReviewItemSourceType.conceptGraphRelation,
    );

    expect(conceptNodes.map((node) => node.label), contains('Seminar concept'));
    expect(relationItems, isNotEmpty);
  });

  test('sendToReview retry repairs candidate card review item', () async {
    final tempRoot = await Directory.systemTemp.createTemp();
    addTearDown(() => tempRoot.deleteSync(recursive: true));
    final reviewStore = _FailsFirstKnowledgeCardReviewStore(rootDir: tempRoot);
    final cardStore = KnowledgeCardStore(rootDir: tempRoot);
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
        aiSeminarReviewItemStoreProvider.overrideWithValue(reviewStore),
        aiSeminarKnowledgeCardStoreProvider.overrideWithValue(cardStore),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(aiSeminarRuntimeProvider.notifier);

    await notifier.start(
      AiSeminarSessionContract(id: 's5', question: 'Repair ReviewItem.'),
    );

    await expectLater(
      notifier.sendToReview(now: 300),
      throwsA(isA<StateError>()),
    );
    expect(await cardStore.list(origin: KnowledgeCardOrigin.seminar),
        hasLength(1));

    final result = await notifier.sendToReview(now: 301);
    final pendingItems =
        await reviewStore.list(status: ReviewItemStatus.pending);

    expect(result.knowledgeCardIds, isEmpty);
    expect(
      pendingItems.where(
        (item) => item.sourceType == ReviewItemSourceType.knowledgeCard,
      ),
      hasLength(1),
    );
  });
}

class _FailsFirstKnowledgeCardReviewStore extends ReviewItemStore {
  _FailsFirstKnowledgeCardReviewStore({required super.rootDir});

  var _remainingFailures = 1;

  @override
  Future<ReviewItem> upsert(ReviewItem item) {
    if (item.sourceType == ReviewItemSourceType.knowledgeCard &&
        _remainingFailures > 0) {
      _remainingFailures -= 1;
      return Future<ReviewItem>.error(StateError('simulated review write'));
    }
    return super.upsert(item);
  }
}
