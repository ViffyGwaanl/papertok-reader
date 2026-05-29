import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/page/settings_page/spaced_review.dart';
import 'package:papertok_reader/providers/spaced_review.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/review/spaced_review_store.dart';

void main() {
  testWidgets('shows due review items and records ratings', (tester) async {
    final store = _FakeSpacedReviewStore([
      SpacedReviewItem(
        id: 'spaced-review:knowledge-card:kc-1',
        cardId: 'kc-1',
        prompt: 'Attention bottleneck',
        answer: 'A durable card should be reviewed later.',
        dueAt: 1000,
        sourceRefs: [
          SourceRef(
            bookId: 7,
            cfi: 'epubcfi(/6/8)',
            jumpLink:
                'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
            sourceTitle: 'Review Book',
            locationLabel: 'Chapter 4',
            sourceTextSnippet: 'Traceable evidence.',
            sourceKind: SourceRefKind.highlight,
          ),
          SourceRef(
            unavailableReason: 'The source book was deleted.',
            sourceKind: SourceRefKind.reader,
          ),
        ],
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          spacedReviewStoreProvider.overrideWithValue(store),
          spacedReviewKnowledgeCardStoreProvider.overrideWithValue(
            _FakeKnowledgeCardStore(),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: SpacedReviewPage(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Spaced review'), findsWidgets);
    expect(find.text('Attention bottleneck'), findsOneWidget);
    expect(find.text('1 traceable'), findsOneWidget);
    expect(find.text('1 unavailable'), findsOneWidget);
    expect(find.text('Evidence'), findsOneWidget);
    expect(find.text('Traceable evidence.'), findsOneWidget);
    expect(find.text('Review Book · Chapter 4'), findsOneWidget);
    expect(find.text('The source book was deleted.'), findsOneWidget);
    expect(find.text('Open source'), findsOneWidget);

    await tester.tap(find.text('Good'));
    await tester.pump();

    expect(store.recordedRatings, ['good']);
  });
}

class _FakeKnowledgeCardStore extends KnowledgeCardStore {
  _FakeKnowledgeCardStore()
      : super(rootDir: Directory.systemTemp.createTempSync());

  @override
  Future<List<KnowledgeCard>> list({
    KnowledgeCardReviewState? reviewState,
    KnowledgeCardOrigin? origin,
  }) async {
    return const <KnowledgeCard>[];
  }
}

class _FakeSpacedReviewStore extends SpacedReviewStore {
  _FakeSpacedReviewStore(this._items)
      : super(rootDir: Directory.systemTemp.createTempSync());

  final List<SpacedReviewItem> _items;
  final List<String> recordedRatings = [];

  @override
  Future<List<SpacedReviewItem>> list({
    bool dueOnly = false,
    int? now,
  }) async {
    return _items;
  }

  @override
  Future<SpacedReviewItem> recordReview(
    String id, {
    required SpacedReviewRating rating,
    int? now,
    String? note,
  }) async {
    recordedRatings.add(rating.asString);
    return _items.singleWhere((item) => item.id == id).recordReview(
          reviewedAt: now ?? 1000,
          rating: rating.asString,
          nextDueAt: (now ?? 1000) + Duration.millisecondsPerDay * 3,
          nextIntervalDays: 3,
          note: note,
        );
  }
}
