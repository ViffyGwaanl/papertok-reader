import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('review_item_store_');
  });

  tearDown(() async {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  SourceRef traceableRef() => SourceRef(
        bookId: 1,
        href: 'Text/ch.xhtml',
        cfi: 'epubcfi(/6/4)',
        sourceTextSnippet: 'The source passage.',
        sourceKind: SourceRefKind.highlight,
      );

  ReviewItem item({
    String id = 'review-1',
    ReviewItemStatus status = ReviewItemStatus.pending,
    List<SourceRef>? sourceRefs,
    int createdAt = 100,
    ReviewItemSourceType sourceType = ReviewItemSourceType.knowledgeCard,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) {
    return ReviewItem(
      id: id,
      sourceType: sourceType,
      sourceId: 'source-$id',
      title: 'Title $id',
      body: 'Body $id',
      status: status,
      sourceRefs: sourceRefs ?? [traceableRef()],
      createdAt: createdAt,
      updatedAt: createdAt,
      payload: payload,
    );
  }

  test('first write creates versioned review item inbox file', () async {
    final store = ReviewItemStore(rootDir: tempRoot);

    await store.upsert(item());

    final inboxFile = File(
      p.join(tempRoot.path, '.workflow', 'review_items_v1.json'),
    );
    expect(inboxFile.existsSync(), isTrue);
    final decoded =
        jsonDecode(inboxFile.readAsStringSync()) as Map<String, dynamic>;
    expect(decoded['version'], 1);
    final items = decoded['items'] as List;
    expect(items, hasLength(1));
    expect((items.single as Map)['id'], 'review-1');
  });

  test('raw upsert cannot bypass review decisions', () async {
    final store = ReviewItemStore(rootDir: tempRoot);

    expect(
      () =>
          store.upsert(item(id: 'approved', status: ReviewItemStatus.approved)),
      throwsArgumentError,
    );
    expect(
      () => store.upsert(item(id: 'applied', status: ReviewItemStatus.applied)),
      throwsArgumentError,
    );

    expect(await store.list(), isEmpty);
  });

  test('lists items newest first and filters by status and source type',
      () async {
    final store = ReviewItemStore(rootDir: tempRoot);

    await store.upsert(item(id: 'older', createdAt: 10));
    await store.upsert(
      item(
        id: 'newer',
        createdAt: 20,
        sourceType: ReviewItemSourceType.seminarSynthesis,
      ),
    );
    await store.upsert(item(id: 'dismissed', createdAt: 30));
    await store.dismiss('dismissed', now: 40);

    expect((await store.list()).map((i) => i.id), [
      'dismissed',
      'newer',
      'older',
    ]);
    expect(
      (await store.list(status: ReviewItemStatus.pending)).map((i) => i.id),
      ['newer', 'older'],
    );
    expect(
      (await store.list(sourceType: ReviewItemSourceType.seminarSynthesis))
          .map((i) => i.id),
      ['newer'],
    );
  });

  test('approve and apply record traceable user decisions', () async {
    final store = ReviewItemStore(rootDir: tempRoot);
    await store.upsert(item(id: 'card'));

    final approved = await store.approve(
      'card',
      now: 200,
      decisionSource: 'user_approve',
    );
    final applied = await store.apply(
      'card',
      now: 300,
      decisionSource: 'user_apply',
    );

    expect(approved.status, ReviewItemStatus.approved);
    expect(approved.decidedAt, 200);
    expect(approved.decisionSource, 'user_approve');
    expect(applied.status, ReviewItemStatus.applied);
    expect(applied.appliedAt, 300);
    expect(applied.decisionSource, 'user_apply');

    final restored = await store.getById('card');
    expect(restored!.status, ReviewItemStatus.applied);
    expect(restored.appliedAt, 300);
  });

  test('generic store apply rejects sources without apply adapters', () async {
    final store = ReviewItemStore(rootDir: tempRoot);
    await store.upsert(
      item(
        id: 'seminar',
        sourceType: ReviewItemSourceType.seminarSynthesis,
      ),
    );
    await store.approve('seminar', now: 200);

    expect(
      () => store.apply('seminar', now: 300),
      throwsUnsupportedError,
    );

    final restored = await store.getById('seminar');
    expect(restored!.status, ReviewItemStatus.approved);
    expect(restored.appliedAt, isNull);
  });

  test(
      'generic store apply rejects memory candidates without controller adapter',
      () async {
    final store = ReviewItemStore(rootDir: tempRoot);
    final item = ReviewItem(
      id: 'memory-candidate:mem-raw',
      sourceType: ReviewItemSourceType.memoryCandidate,
      sourceId: 'mem-raw',
      title: 'Raw memory apply',
      body: 'Raw store apply must not bypass MemoryWorkflowService.',
      status: ReviewItemStatus.pending,
      sourceRefs: [traceableRef()],
      createdAt: 100,
      updatedAt: 100,
    );
    await store.upsert(item);
    await store.approve(item.id, now: 200);

    expect(
      () => store.apply(item.id, now: 300),
      throwsUnsupportedError,
    );
    final unchanged = await store.getById(item.id);
    expect(unchanged!.status, ReviewItemStatus.approved);
    expect(unchanged.appliedAt, isNull);
  });

  test('generic store apply rejects sync conflict even with canApply gate',
      () async {
    final store = ReviewItemStore(rootDir: tempRoot);
    await store.upsert(
      item(
        id: 'sync-conflict:unsafe',
        sourceType: ReviewItemSourceType.syncConflict,
        payload: const {'canApply': true},
      ),
    );
    await store.approve('sync-conflict:unsafe', now: 200);

    expect(
      () => store.apply('sync-conflict:unsafe', now: 300),
      throwsUnsupportedError,
    );

    final restored = await store.getById('sync-conflict:unsafe');
    expect(restored!.status, ReviewItemStatus.approved);
    expect(restored.appliedAt, isNull);
  });

  test('generic store apply rejects review history imports', () async {
    final store = ReviewItemStore(rootDir: tempRoot);
    await store.upsert(
      item(
        id: 'review-history-import:remote',
        sourceType: ReviewItemSourceType.reviewHistoryImport,
      ),
    );
    await store.approve('review-history-import:remote', now: 200);

    expect(
      () => store.apply('review-history-import:remote', now: 300),
      throwsUnsupportedError,
    );

    final restored = await store.getById('review-history-import:remote');
    expect(restored!.status, ReviewItemStatus.approved);
    expect(restored.appliedAt, isNull);
  });

  test('submit moves a draft review item into pending without applying it',
      () async {
    final store = ReviewItemStore(rootDir: tempRoot);
    await store.upsert(item(id: 'draft', status: ReviewItemStatus.draft));

    final submitted = await store.submit('draft', now: 180);

    expect(submitted.status, ReviewItemStatus.pending);
    expect(submitted.updatedAt, 180);
    expect(submitted.decidedAt, isNull);
    expect(submitted.appliedAt, isNull);
    expect(submitted.decisionSource, isNull);
  });

  test('dismiss records a terminal review decision', () async {
    final store = ReviewItemStore(rootDir: tempRoot);
    await store.upsert(item(id: 'seminar'));

    final dismissed = await store.dismiss(
      'seminar',
      now: 220,
      decisionSource: 'user_dismiss',
    );

    expect(dismissed.status, ReviewItemStatus.dismissed);
    expect(dismissed.decidedAt, 220);
    expect(dismissed.decisionSource, 'user_dismiss');
    expect(
      () => dismissed.transitionTo(ReviewItemStatus.approved, now: 230),
      throwsStateError,
    );
  });

  test('legacy applied item without traceable source is downgraded on read',
      () async {
    final file = File(
      p.join(tempRoot.path, '.workflow', 'review_items_v1.json'),
    );
    file.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({
        'version': 1,
        'items': [
          {
            'id': 'orphan',
            'sourceType': 'knowledge-card',
            'sourceId': 'kc-1',
            'title': 'Orphan',
            'body': 'No source',
            'status': 'applied',
            'sourceRefs': [],
            'createdAt': 100,
            'updatedAt': 100,
            'appliedAt': 120,
          }
        ],
      }),
    );

    final store = ReviewItemStore(rootDir: tempRoot);
    final restored = await store.getById('orphan');

    expect(restored!.status, ReviewItemStatus.approved);
    expect(restored.appliedAt, isNull);
    expect(restored.canApply, false);
  });

  test('malformed inbox file degrades to an empty review list', () async {
    final file = File(
      p.join(tempRoot.path, '.workflow', 'review_items_v1.json'),
    );
    file.createSync(recursive: true);
    file.writeAsStringSync('{bad json');

    final store = ReviewItemStore(rootDir: tempRoot);

    expect(await store.list(), isEmpty);
  });
}
