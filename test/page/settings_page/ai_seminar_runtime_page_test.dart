import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/page/settings_page/ai_seminar_runtime.dart';
import 'package:papertok_reader/providers/ai_seminar_runtime.dart';
import 'package:papertok_reader/service/ai/ai_seminar_runtime_service.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
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

  AiSeminarRuntimeService service() {
    final bundle = AiSeminarEvidenceBundle(
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
    return AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle,
      streamRole: (invocation, _) async* {
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
              if (invocation.role == AiSeminarRole.synthesizer)
                const AiSeminarWhiteboardEntry(
                  id: 'review-1',
                  kind: AiSeminarWhiteboardKind.reviewSuggestion,
                  text: 'What should be reviewed later?',
                  evidenceRefIds: ['e1'],
                ),
            ],
          ),
        );
      },
      now: () => 1000,
    );
  }

  testWidgets(
      'shows structured seminar roles evidence whiteboard and synthesis',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiSeminarRuntimePage(initialQuestion: 'What is the claim?'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(find.byType(TextField), 'What is the claim?');
    await tester.tap(find.text('Start Seminar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Seminar Mode'), findsWidgets);
    expect(find.text('Evidence'), findsOneWidget);
    expect(find.text('The source passage.'), findsOneWidget);
    expect(find.text('critical response'), findsOneWidget);
    expect(find.text('supportive response'), findsOneWidget);
    expect(find.text('synthesizer response'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Shared whiteboard'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Shared whiteboard'), findsOneWidget);
    expect(find.text('Candidate card'), findsOneWidget);
    expect(find.text('Synthesis'), findsOneWidget);
    expect(find.text('Send to Review'), findsOneWidget);
  });

  testWidgets(
      'tapping Send to Review writes seminar card and flashcard candidates without applying',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final reviewStore = _MemoryReviewItemStore();
    final cardStore = _MemoryKnowledgeCardStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
          aiSeminarReviewItemStoreProvider.overrideWithValue(reviewStore),
          aiSeminarKnowledgeCardStoreProvider.overrideWithValue(cardStore),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiSeminarRuntimePage(initialQuestion: 'What is the claim?'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(find.byType(TextField), 'What is the claim?');
    await tester.tap(find.text('Start Seminar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    await tester.scrollUntilVisible(
      find.text('Send to Review'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Send to Review'), findsOneWidget);
    await tester.tap(find.text('Send to Review'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final pendingItems =
        await reviewStore.list(status: ReviewItemStatus.pending);
    final appliedItems =
        await reviewStore.list(status: ReviewItemStatus.applied);
    final seminarCards =
        await cardStore.list(origin: KnowledgeCardOrigin.seminar);
    final sourceTypes = pendingItems.map((item) => item.sourceType).toSet();

    expect(
      sourceTypes,
      containsAll({
        ReviewItemSourceType.seminarSynthesis,
        ReviewItemSourceType.knowledgeCard,
        ReviewItemSourceType.flashcardCandidate,
      }),
    );
    final synthesisItem = pendingItems.singleWhere(
      (item) => item.sourceType == ReviewItemSourceType.seminarSynthesis,
    );
    expect(synthesisItem.payload['summary'], 'synthesizer response');
    expect(synthesisItem.payload['candidateReviewQuestions'], isNotEmpty);
    expect(synthesisItem.sourceRefs.single.hasEvidence, true);

    expect(seminarCards, hasLength(1));
    expect(seminarCards.single.reviewState, KnowledgeCardReviewState.pending);
    expect(seminarCards.single.isUserAsset, false);
    expect(seminarCards.single.conceptRefs, ['Seminar concept']);

    final flashcard = pendingItems.singleWhere(
      (item) => item.sourceType == ReviewItemSourceType.flashcardCandidate,
    );
    expect(flashcard.status, ReviewItemStatus.pending);
    expect(flashcard.sourceId, contains(':question-1'));
    expect(appliedItems, isEmpty);
    expect(find.textContaining('Sent synthesis and 1 card(s) to Review.'),
        findsOneWidget);
  });
}

class _MemoryReviewItemStore extends ReviewItemStore {
  final _items = <String, ReviewItem>{};

  @override
  Future<List<ReviewItem>> list({
    ReviewItemStatus? status,
    ReviewItemSourceType? sourceType,
  }) async {
    return _items.values.where((item) {
      if (status != null && item.status != status) return false;
      if (sourceType != null && item.sourceType != sourceType) return false;
      return true;
    }).toList(growable: false);
  }

  @override
  Future<ReviewItem?> getById(String id) async => _items[id];

  @override
  Future<ReviewItem> upsert(ReviewItem item) async {
    if (item.status != ReviewItemStatus.draft &&
        item.status != ReviewItemStatus.pending) {
      throw ArgumentError(
        'Only draft/pending review items can be staged.',
      );
    }
    _items[item.id] = item;
    return item;
  }
}

class _MemoryKnowledgeCardStore extends KnowledgeCardStore {
  final _cards = <KnowledgeCard>[];

  @override
  Future<List<KnowledgeCard>> list({
    KnowledgeCardReviewState? reviewState,
    KnowledgeCardOrigin? origin,
  }) async {
    return _cards.where((card) {
      if (reviewState != null && card.reviewState != reviewState) {
        return false;
      }
      if (origin != null && card.origin != origin) return false;
      return true;
    }).toList(growable: false);
  }

  @override
  Future<KnowledgeCard?> getById(String id) async {
    for (final card in _cards) {
      if (card.id == id) return card;
    }
    return null;
  }

  @override
  Future<KnowledgeCardStoreUpsertResult> upsertCandidate(
    KnowledgeCard candidate,
  ) async {
    for (final card in _cards) {
      if (card.id == candidate.id ||
          KnowledgeCardDedupe.isLikelyDuplicate(card, candidate)) {
        return KnowledgeCardStoreUpsertResult(
          card: card,
          inserted: false,
          duplicateOfId: card.id,
        );
      }
    }
    final staged = candidate.copyWith(
      reviewState: candidate.reviewState == KnowledgeCardReviewState.draft
          ? KnowledgeCardReviewState.draft
          : KnowledgeCardReviewState.pending,
      ownership: AiOutputOwnership.aiGeneratedDraft,
    );
    _cards.add(staged);
    return KnowledgeCardStoreUpsertResult(card: staged, inserted: true);
  }
}
