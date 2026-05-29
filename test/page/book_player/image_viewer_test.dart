import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/main.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/page/book_player/image_viewer.dart';
import 'package:papertok_reader/service/knowledge/image_analysis_knowledge_card_producer.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';
import 'package:papertok_reader/utils/toast/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('image analysis sheet exposes KnowledgeCard action',
      (tester) async {
    var cardText = '';

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            height: 420,
            child: AiImageAnalysisSheet(
              stream: Stream<String>.value(
                'The image explains a traceable evidence chain.',
              ),
              onContinueAsk: (_) async {},
              onCreateKnowledgeCard: (text) async {
                cardText = text;
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('AI Image Analysis'), findsOneWidget);
    expect(find.text('Card'), findsOneWidget);

    await tester.tap(find.text('Card'));
    await tester.pump();

    expect(cardText, contains('traceable evidence chain'));
  });

  testWidgets('ImageViewer analysis Card action writes review stores',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'aiImageAnalysisProviderIdV1': 'test-provider',
    });
    await Prefs().initPrefs();

    final cardStore = _MemoryKnowledgeCardStore();
    final reviewStore = _MemoryReviewItemStore();
    final producer = ImageAnalysisKnowledgeCardProducer(
      cardStore: cardStore,
      reviewStore: reviewStore,
    );
    final prompts = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 420,
            child: ImageViewer(
              image: _testImageDataUrl(),
              bookId: 7,
              bookName: 'Image Evidence Book',
              cfi: 'epubcfi(/6/8)',
              chapterHref: 'Text/chapter.xhtml',
              chapterTitle: 'Chapter 3',
              contextText: 'A figure about source-grounded retrieval.',
              alt: 'retrieval diagram',
              title: 'Grounding figure',
              analysisStreamFactory: ({
                required base64,
                required mimeType,
                required prompt,
              }) {
                prompts.add(prompt);
                return Stream<String>.value(
                  'The image explains a source-grounded retrieval path.',
                );
              },
              knowledgeCardCreator: ({
                required bookId,
                required analysisText,
                cfi,
                href,
                imageTitle,
                imageAlt,
                contextText,
                chapterTitle,
                bookTitle,
                now,
              }) async {
                final result = await producer.createFromImageAnalysis(
                  bookId: bookId,
                  cfi: cfi,
                  href: href,
                  analysisText: analysisText,
                  imageTitle: imageTitle,
                  imageAlt: imageAlt,
                  contextText: contextText,
                  chapterTitle: chapterTitle,
                  bookTitle: bookTitle,
                  now: 100,
                );
                return result;
              },
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    AnxToast.init(tester.element(find.byType(ImageViewer)));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.auto_awesome));
    await _pumpUntilFound(tester, find.text('Card'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(prompts.single, contains('source-grounded retrieval'));
    expect(find.text('AI Image Analysis'), findsOneWidget);
    expect(find.text('Card'), findsOneWidget);

    await tester.tap(find.text('Card'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final cards =
        await cardStore.list(origin: KnowledgeCardOrigin.imageAnalysis);
    final reviewItems =
        await reviewStore.list(sourceType: ReviewItemSourceType.knowledgeCard);

    expect(cards, hasLength(1));
    expect(cards.single.reviewState, KnowledgeCardReviewState.pending);
    expect(cards.single.sourceRefs.single.bookId, 7);
    expect(cards.single.sourceRefs.single.cfi, 'epubcfi(/6/8)');
    expect(cards.single.sourceRefs.single.href, 'Text/chapter.xhtml');
    expect(
      cards.single.sourceRefs.single.jumpLink,
      contains('paperreader://reader/open'),
    );
    expect(cards.single.sourceRefs.single.jumpLink, contains('bookId=7'));
    expect(
      cards.single.sourceRefs.single.jumpLink,
      contains('Text%2Fchapter.xhtml'),
    );
    expect(
      cards.single.sourceRefs.single.jumpLink,
      contains('epubcfi%28%2F6%2F8%29'),
    );
    expect(cards.single.sourceRefs.single.sourceHash, startsWith('sha256:'));
    expect(cards.single.sourceRefs.single.createdAt, 100);
    expect(cards.single.sourceRefs.single.canJumpBack, true);
    expect(cards.single.quote, contains('source-grounded retrieval'));
    expect(reviewItems, hasLength(1));
    expect(reviewItems.single.status, ReviewItemStatus.pending);
    expect(reviewItems.single.sourceId, cards.single.id);
    final reviewPayload = reviewItems.single.payload.toString();
    expect(reviewPayload, isNot(contains('data:image')));
    expect(reviewPayload, isNot(contains('base64')));

    await tester.pump(const Duration(milliseconds: 2100));
  });
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxAttempts = 20,
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await _pumpForRealAsync(tester);
  }
}

Future<void> _pumpForRealAsync(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
}

String _testImageDataUrl() {
  final image = img.Image(width: 2, height: 2);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgb(x, y, 220, 30, 30);
    }
  }
  return 'data:image/png;base64,${base64Encode(img.encodePng(image))}';
}

class _MemoryKnowledgeCardStore extends KnowledgeCardStore {
  final _cards = <KnowledgeCard>[];

  @override
  Future<List<KnowledgeCard>> list({
    KnowledgeCardReviewState? reviewState,
    KnowledgeCardOrigin? origin,
  }) async {
    return _cards.where((card) {
      if (reviewState != null && card.reviewState != reviewState) return false;
      if (origin != null && card.origin != origin) return false;
      return true;
    }).toList();
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
    }).toList();
  }

  @override
  Future<ReviewItem> upsert(ReviewItem item) async {
    _items[item.id] = item;
    return item;
  }
}
