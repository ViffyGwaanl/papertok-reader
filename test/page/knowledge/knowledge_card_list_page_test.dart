import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/page/knowledge/knowledge_card_list_page.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';

KnowledgeCard _card(String id, KnowledgeCardReviewState state) {
  return KnowledgeCard(
    id: id,
    title: 'Working memory $id',
    quote: 'The magical number seven',
    explanation: 'A short explanation.',
    sourceRefs: const <SourceRef>[],
    reviewState: state,
    createdAt: 1,
    updatedAt: 1,
  );
}

void main() {
  // Widget tests are smoke-only with an injected loader: testWidgets runs
  // under FakeAsync where real file IO never resolves. The real store IO is
  // covered by the plain test() below.
  Widget harness(KnowledgeCardsLoader loader) {
    return ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: KnowledgeCardListPage(loader: loader),
      ),
    );
  }

  testWidgets('cards render, filter works, tap opens detail with actions',
      (tester) async {
    final cards = [
      _card('a', KnowledgeCardReviewState.draft),
      _card('b', KnowledgeCardReviewState.applied),
    ];
    await tester.pumpWidget(harness((filter) => Future.value(
          cards
              .where((c) => filter == null || c.reviewState == filter)
              .toList(),
        )));
    await tester.pumpAndSettle();

    expect(find.text('Working memory a'), findsOneWidget);
    expect(find.text('Working memory b'), findsOneWidget);

    // Filter to drafts only.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Draft'));
    await tester.pumpAndSettle();
    expect(find.text('Working memory a'), findsOneWidget);
    expect(find.text('Working memory b'), findsNothing);

    await tester.tap(find.text('Working memory a'));
    await tester.pumpAndSettle();
    expect(find.text('Knowledge card details'), findsOneWidget);
    expect(find.text('Submit for review'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('empty loader shows the empty state', (tester) async {
    await tester.pumpWidget(harness((_) => Future.value(const [])));
    await tester.pumpAndSettle();
    expect(
      find.text('Cards you save from reading or AI chat will show up here.'),
      findsOneWidget,
    );
  });

  test('store roundtrip: upsert, list, filter, removeDraftCandidate',
      () async {
    final dir = await Directory.systemTemp.createTemp('kc_store_test');
    addTearDown(() => dir.delete(recursive: true));
    final store = KnowledgeCardStore(rootDir: dir);

    await store.upsert(_card('a', KnowledgeCardReviewState.draft));
    await store.upsert(_card('b', KnowledgeCardReviewState.pending));

    expect((await store.list()).length, 2);
    expect(
      (await store.list(reviewState: KnowledgeCardReviewState.draft))
          .single
          .id,
      'a',
    );

    expect(await store.removeDraftCandidate('a'), isTrue);
    expect(await store.removeDraftCandidate('missing'), isFalse);
    expect((await store.list()).single.id, 'b');
  });
}
