import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/page/settings_page/review_inbox.dart';
import 'package:papertok_reader/providers/review_inbox.dart';
import 'package:papertok_reader/service/review/review_inbox_controller.dart';

void main() {
  late ReviewInboxController controller;

  setUp(() async {
    controller = _FakeReviewInboxController([
      ReviewItem(
        id: 'knowledge-card:kc-widget',
        sourceType: ReviewItemSourceType.knowledgeCard,
        sourceId: 'kc-widget',
        title: 'Widget review card',
        body: 'The page should show pending review items.',
        status: ReviewItemStatus.pending,
        sourceRefs: [
          SourceRef(
            bookId: 9,
            href: 'Text/chapter.xhtml',
            cfi: 'epubcfi(/6/12)',
            sourceTitle: 'Widget Book',
            locationLabel: 'Chapter 2',
            sourceTextSnippet: 'A visible evidence quote.',
            sourceKind: SourceRefKind.highlight,
          ),
        ],
      ),
    ]);
  });

  testWidgets('shows pending review items with source and actions',
      (tester) async {
    await _pumpPage(tester, controller);

    expect(find.text('Review inbox'), findsWidgets);
    expect(find.text('Widget review card'), findsOneWidget);
    expect(find.text('Knowledge card'), findsOneWidget);
    expect(find.text('Pending'), findsWidgets);
    expect(find.text('Evidence'), findsOneWidget);
    expect(find.text('A visible evidence quote.'), findsOneWidget);
    expect(find.text('Widget Book · Chapter 2'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);
  });

  testWidgets('evidence preview fits a narrow review list surface',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final narrowController = _FakeReviewInboxController([
      ReviewItem(
        id: 'knowledge-card:kc-narrow',
        sourceType: ReviewItemSourceType.knowledgeCard,
        sourceId: 'kc-narrow',
        title: 'Very long review card title that should wrap inside the card',
        body: 'The body also needs to fit before the evidence preview.',
        status: ReviewItemStatus.pending,
        sourceRefs: [
          SourceRef(
            bookId: 10,
            href: 'Text/narrow.xhtml',
            cfi: 'epubcfi(/6/18)',
            sourceTitle: 'Long Source Title For A Small Phone Width',
            locationLabel: 'A deeply nested chapter location label',
            sourceTextSnippet: List.filled(30, 'Narrow evidence').join(' '),
            sourceKind: SourceRefKind.highlight,
          ),
        ],
      ),
    ]);

    await _pumpPage(tester, narrowController);

    expect(find.text('Evidence'), findsOneWidget);
    expect(find.textContaining('Narrow evidence'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sync conflict review item exposes dismiss but not approve',
      (tester) async {
    final conflictController = _FakeReviewInboxController([
      ReviewItem(
        id: 'sync-conflict:kc-conflict',
        sourceType: ReviewItemSourceType.syncConflict,
        sourceId: 'kc-conflict',
        title: 'Sync conflict: kc-conflict',
        body: 'Conflict reason: content-conflict',
        status: ReviewItemStatus.pending,
        sourceRefs: [
          SourceRef(
            sourceKind: SourceRefKind.unknown,
            unavailableReason: 'sync-conflict-no-source',
          ),
        ],
      ),
    ]);

    await _pumpPage(tester, conflictController);

    expect(find.text('Sync conflict: kc-conflict'), findsOneWidget);
    expect(find.text('Sync conflict'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Apply'), findsNothing);
    expect(find.text('sync-conflict-no-source'), findsOneWidget);
  });
}

class _FakeReviewInboxController extends ReviewInboxController {
  _FakeReviewInboxController(this._items);

  final List<ReviewItem> _items;

  @override
  Future<List<ReviewItem>> list({
    ReviewItemStatus? status,
    ReviewItemSourceType? sourceType,
  }) async {
    return _items.where((item) {
      if (status != null && item.status != status) return false;
      if (sourceType != null && item.sourceType != sourceType) return false;
      return true;
    }).toList(growable: false);
  }
}

Future<void> _pumpPage(
  WidgetTester tester,
  ReviewInboxController controller,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        reviewInboxControllerProvider.overrideWithValue(controller),
      ],
      child: MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: const ReviewInboxPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}
