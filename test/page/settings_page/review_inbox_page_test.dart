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

  testWidgets('Open source emits reader URI through injected opener',
      (tester) async {
    final opened = <Uri>[];

    await _pumpPage(
      tester,
      controller,
      sourceOpener: (_, uri) async => opened.add(uri),
    );

    await tester.tap(find.text('Open source'));
    await tester.pump();

    expect(opened, hasLength(1));
    expect(opened.single.scheme, 'paperreader');
    expect(opened.single.host, 'reader');
    expect(opened.single.path, '/open');
    expect(opened.single.queryParameters['bookId'], '9');
    expect(opened.single.queryParameters['cfi'], 'epubcfi(/6/12)');
    expect(opened.single.queryParameters['href'], 'Text/chapter.xhtml');
  });

  testWidgets('Open source explains unavailable provenance without opening',
      (tester) async {
    final opened = <Uri>[];
    final conflictController = _FakeReviewInboxController([
      ReviewItem(
        id: 'sync-conflict:missing-source',
        sourceType: ReviewItemSourceType.syncConflict,
        sourceId: 'missing-source',
        title: 'Sync conflict: missing-source',
        body: 'Conflict reason: source-missing',
        status: ReviewItemStatus.pending,
        sourceRefs: [
          SourceRef(
            sourceKind: SourceRefKind.unknown,
            unavailableReason: 'sync-conflict-no-source',
          ),
        ],
      ),
    ]);

    await _pumpPage(
      tester,
      conflictController,
      sourceOpener: (_, uri) async => opened.add(uri),
    );

    expect(find.text('Sync conflict: missing-source'), findsOneWidget);
    expect(find.text('sync-conflict-no-source'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -360));
    await tester.pump();

    await tester.tap(find.text('Open source'));
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('sync-conflict-no-source'), findsWidgets);
    expect(opened, isEmpty);
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

  testWidgets('safe sync conflict exposes approve and apply actions',
      (tester) async {
    final safeSource = SourceRef(
      bookId: 9,
      href: 'Text/chapter.xhtml',
      cfi: 'epubcfi(/6/12)',
      sourceTitle: 'Widget Book',
      locationLabel: 'Chapter 2',
      sourceTextSnippet: 'A visible evidence quote.',
      sourceKind: SourceRefKind.highlight,
    );
    final pendingController = _FakeReviewInboxController([
      ReviewItem(
        id: 'sync-conflict:kc-safe',
        sourceType: ReviewItemSourceType.syncConflict,
        sourceId: 'kc-safe',
        title: 'Sync conflict: kc-safe',
        body: 'Conflict reason: content-conflict',
        status: ReviewItemStatus.pending,
        sourceRefs: [safeSource],
        payload: const {'canApply': true},
      ),
    ]);

    await _pumpPage(tester, pendingController);

    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);
    expect(find.text('Apply'), findsNothing);

    final approvedController = _FakeReviewInboxController([
      ReviewItem(
        id: 'sync-conflict:kc-safe',
        sourceType: ReviewItemSourceType.syncConflict,
        sourceId: 'kc-safe',
        title: 'Sync conflict: kc-safe',
        body: 'Conflict reason: content-conflict',
        status: ReviewItemStatus.approved,
        sourceRefs: [safeSource],
        payload: const {'canApply': true},
      ),
    ]);

    await _pumpPage(tester, approvedController);
    await tester.tap(find.text('Approved').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Apply'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
  });

  testWidgets('approved safe sync conflicts expose batch apply action',
      (tester) async {
    final safeSource = SourceRef(
      bookId: 9,
      href: 'Text/chapter.xhtml',
      cfi: 'epubcfi(/6/12)',
      sourceTitle: 'Widget Book',
      locationLabel: 'Chapter 2',
      sourceTextSnippet: 'A visible evidence quote.',
      sourceKind: SourceRefKind.highlight,
    );
    final batchController = _FakeReviewInboxController([
      ReviewItem(
        id: 'sync-conflict:kc-safe-a',
        sourceType: ReviewItemSourceType.syncConflict,
        sourceId: 'kc-safe-a',
        title: 'Sync conflict: kc-safe-a',
        body: 'Conflict reason: content-conflict',
        status: ReviewItemStatus.approved,
        sourceRefs: [safeSource],
        payload: const {'canApply': true},
      ),
      ReviewItem(
        id: 'sync-conflict:kc-preview-only',
        sourceType: ReviewItemSourceType.syncConflict,
        sourceId: 'kc-preview-only',
        title: 'Sync conflict: kc-preview-only',
        body: 'Conflict reason: preview-only',
        status: ReviewItemStatus.approved,
        sourceRefs: [safeSource],
        payload: const {'canApply': false, 'remotePreviewOnly': true},
      ),
      ReviewItem(
        id: 'sync-conflict:kc-unavailable-only',
        sourceType: ReviewItemSourceType.syncConflict,
        sourceId: 'kc-unavailable-only',
        title: 'Sync conflict: kc-unavailable-only',
        body: 'Conflict reason: source-missing',
        status: ReviewItemStatus.approved,
        sourceRefs: [
          SourceRef(
            sourceKind: SourceRefKind.unknown,
            unavailableReason: 'sync-conflict-no-source',
          ),
        ],
        payload: const {'canApply': true},
      ),
      ReviewItem(
        id: 'memory-candidate:mem-approved',
        sourceType: ReviewItemSourceType.memoryCandidate,
        sourceId: 'mem-approved',
        title: 'Approved memory',
        body: 'Memory should not be part of sync conflict batch apply.',
        status: ReviewItemStatus.approved,
        sourceRefs: [safeSource],
        payload: const {'targetDoc': 'daily'},
      ),
    ]);

    await _pumpPage(tester, batchController);
    await tester.tap(find.text('Approved').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byType(DropdownButton<ReviewItemSourceType?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sync conflict').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Apply Sync conflict'), findsOneWidget);
    await tester.tap(find.text('Apply Sync conflict'));
    await tester.pump();

    expect(batchController.batchApplyRuns, 1);
    expect(batchController.appliedIds, ['sync-conflict:kc-safe-a']);
  });

  testWidgets('approved flashcard candidate can be applied from inbox',
      (tester) async {
    final flashcardController = _FakeReviewInboxController([
      ReviewItem(
        id: 'flashcard:seminar-review',
        sourceType: ReviewItemSourceType.flashcardCandidate,
        sourceId: 'seminar-review',
        title: 'Flashcard: evidence check',
        body: 'Q: What should be remembered?\nA: The source-backed claim.',
        status: ReviewItemStatus.approved,
        sourceRefs: [
          SourceRef(
            bookId: 11,
            href: 'Text/seminar.xhtml',
            cfi: 'epubcfi(/6/20)',
            sourceTitle: 'Seminar Book',
            locationLabel: 'Chapter 3',
            sourceTextSnippet: 'A traceable seminar flashcard source.',
            sourceKind: SourceRefKind.reader,
          ),
        ],
      ),
    ]);

    await _pumpPage(tester, flashcardController);
    await tester.tap(find.text('Approved').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Flashcard: evidence check'), findsOneWidget);
    expect(find.text('Flashcard'), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget);

    await tester.tap(find.text('Apply'));
    await tester.pump();

    expect(flashcardController.appliedIds, ['flashcard:seminar-review']);
  });

  testWidgets('approved memory candidate can be applied from inbox',
      (tester) async {
    final memoryController = _FakeReviewInboxController([
      ReviewItem(
        id: 'memory-candidate:mem-review',
        sourceType: ReviewItemSourceType.memoryCandidate,
        sourceId: 'mem-review',
        title: 'Remember current-book priority',
        body: 'Default to current book before library search.',
        status: ReviewItemStatus.approved,
        sourceRefs: [
          SourceRef(
            bookId: 12,
            href: 'Text/memory.xhtml',
            cfi: 'epubcfi(/6/24)',
            sourceTitle: 'Memory Book',
            locationLabel: 'Chapter 4',
            sourceTextSnippet: 'Current book first, library second.',
            sourceKind: SourceRefKind.memory,
          ),
        ],
        payload: const {'targetDoc': 'daily'},
      ),
    ]);

    await _pumpPage(tester, memoryController);
    await tester.tap(find.text('Approved').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Remember current-book priority'), findsOneWidget);
    expect(find.text('Memory'), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget);

    await tester.tap(find.text('Apply'));
    await tester.pump();

    expect(memoryController.appliedIds, ['memory-candidate:mem-review']);
  });
}

class _FakeReviewInboxController extends ReviewInboxController {
  _FakeReviewInboxController(this._items);

  final List<ReviewItem> _items;
  final appliedIds = <String>[];
  var batchApplyRuns = 0;

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

  @override
  Future<ReviewItem> apply(String id, {int? now}) async {
    appliedIds.add(id);
    return _items.firstWhere((item) => item.id == id).copyWith(
          status: ReviewItemStatus.applied,
        );
  }

  @override
  Future<ReviewInboxBatchApplyResult> applyApprovedSyncConflicts() async {
    batchApplyRuns += 1;
    final applied = <ReviewItem>[];
    for (var index = 0; index < _items.length; index++) {
      final item = _items[index];
      if (!ReviewInboxController.canBatchApplySyncConflict(item)) {
        continue;
      }
      appliedIds.add(item.id);
      final appliedItem = item.copyWith(status: ReviewItemStatus.applied);
      _items[index] = appliedItem;
      applied.add(appliedItem);
    }
    return ReviewInboxBatchApplyResult(applied: applied);
  }
}

Future<void> _pumpPage(WidgetTester tester, ReviewInboxController controller,
    {Future<void> Function(WidgetRef ref, Uri uri)? sourceOpener}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        reviewInboxControllerProvider.overrideWithValue(controller),
      ],
      child: MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: ReviewInboxPage(sourceOpener: sourceOpener),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}
