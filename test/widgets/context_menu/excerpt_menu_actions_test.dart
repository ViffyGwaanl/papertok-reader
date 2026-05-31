import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/providers/concept_graph_explorer.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/knowledge/selection_knowledge_card_producer.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';
import 'package:papertok_reader/utils/get_path/get_base_path.dart';
import 'package:papertok_reader/widgets/context_menu/excerpt_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'selected-text menu exposes KnowledgeCard, Seminar, and Graph actions',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider
              .overrideWithValue(_EmptyConceptGraphStore()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Center(
              child: ExcerptMenu(
                annoCfi: 'epubcfi(/6/4)',
                annoContent: 'Evidence-backed learning needs jump links.',
                onClose: () {},
                footnote: false,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black12),
                ),
                onTranslate: () async {},
                toggleReaderNoteMenu: ({bool? show}) {},
                openReaderNoteMenu: (_) async {},
                onNoteCreated: (_) {},
                axis: Axis.horizontal,
                reverse: false,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Card', skipOffstage: false), findsOneWidget);
    expect(find.text('Seminar', skipOffstage: false), findsOneWidget);
    expect(find.text('Graph', skipOffstage: false), findsOneWidget);
  });

  testWidgets('selected-text Card action creates a review candidate from menu',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    final calls = <_KnowledgeCardCall>[];
    final feedback = <String>[];
    var closed = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider
              .overrideWithValue(_EmptyConceptGraphStore()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Center(
              child: ExcerptMenu(
                annoCfi: 'epubcfi(/6/4)',
                annoContent: 'Evidence-backed learning needs jump links.',
                onClose: () => closed = true,
                footnote: false,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black12),
                ),
                onTranslate: () async {},
                toggleReaderNoteMenu: ({bool? show}) {},
                openReaderNoteMenu: (_) async {},
                onNoteCreated: (_) {},
                axis: Axis.horizontal,
                reverse: false,
                knowledgeCardReaderContext:
                    const ExcerptKnowledgeCardReaderContext(
                  bookId: 42,
                  bookTitle: 'Evidence Book',
                  chapterTitle: 'Chapter 1',
                ),
                knowledgeCardCreator: ({
                  required bookId,
                  required cfi,
                  required selectedText,
                  chapterTitle,
                  bookTitle,
                }) async {
                  calls.add(
                    _KnowledgeCardCall(
                      bookId: bookId,
                      cfi: cfi,
                      selectedText: selectedText,
                      chapterTitle: chapterTitle,
                      bookTitle: bookTitle,
                    ),
                  );
                  return SelectionKnowledgeCardProducerResult(
                    card: KnowledgeCard(
                      id: 'selection-test',
                      title: 'Evidence-backed learning',
                      quote: selectedText,
                      explanation: 'Saved from reader selection.',
                      sourceRefs: [
                        SourceRef(
                          bookId: bookId,
                          cfi: cfi,
                          sourceTextSnippet: selectedText,
                          sourceKind: SourceRefKind.reader,
                        ),
                      ],
                      reviewState: KnowledgeCardReviewState.pending,
                      origin: KnowledgeCardOrigin.selection,
                    ),
                    inserted: true,
                    addedToReviewInbox: true,
                  );
                },
                knowledgeCardFeedback: feedback.add,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.text('Card', skipOffstage: false));
    await _pumpMenuActionFrames(tester);

    expect(calls, hasLength(1));
    expect(calls.single.bookId, 42);
    expect(calls.single.cfi, 'epubcfi(/6/4)');
    expect(
      calls.single.selectedText,
      'Evidence-backed learning needs jump links.',
    );
    expect(calls.single.bookTitle, 'Evidence Book');
    expect(calls.single.chapterTitle, 'Chapter 1');
    expect(feedback, ['Added to Review inbox']);
    expect(closed, true);
  });

  testWidgets(
      'selected-text Card action uses fallback reader context and default producer',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final originalDocumentPath = documentPath;
    final tempRoot =
        Directory.systemTemp.createTempSync('excerpt_menu_fallback_');
    documentPath = tempRoot.path;
    debugExcerptKnowledgeCardReaderContextResolverOverride =
        () => const ExcerptKnowledgeCardReaderContext(
              bookId: 77,
              bookTitle: 'Fallback Book',
              chapterTitle: 'Fallback Chapter',
            );
    addTearDown(() {
      debugExcerptKnowledgeCardReaderContextResolverOverride = null;
      documentPath = originalDocumentPath;
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });
    final feedback = <String>[];
    var closeCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider
              .overrideWithValue(_EmptyConceptGraphStore()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Center(
              child: ExcerptMenu(
                annoCfi: 'epubcfi(/6/8)',
                annoContent: 'Fallback selection becomes reviewable evidence.',
                onClose: () => closeCount += 1,
                footnote: false,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black12),
                ),
                onTranslate: () async {},
                toggleReaderNoteMenu: ({bool? show}) {},
                openReaderNoteMenu: (_) async {},
                onNoteCreated: (_) {},
                axis: Axis.horizontal,
                reverse: false,
                knowledgeCardFeedback: feedback.add,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.runAsync(() async {
      await tester.tap(find.text('Card', skipOffstage: false));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    final knowledgeRoot =
        Directory('${tempRoot.path}${Platform.pathSeparator}memory');
    final cards = await tester.runAsync(
          () => KnowledgeCardStore(rootDir: knowledgeRoot).list(
            reviewState: KnowledgeCardReviewState.pending,
            origin: KnowledgeCardOrigin.selection,
          ),
        ) ??
        const <KnowledgeCard>[];
    final reviewItems = await tester.runAsync(
          () => ReviewItemStore(rootDir: knowledgeRoot).list(
            status: ReviewItemStatus.pending,
            sourceType: ReviewItemSourceType.knowledgeCard,
          ),
        ) ??
        const <ReviewItem>[];

    expect(cards, hasLength(1));
    expect(
        cards.single.quote, 'Fallback selection becomes reviewable evidence.');
    expect(cards.single.sourceRefs.single.bookId, 77);
    expect(cards.single.sourceRefs.single.cfi, 'epubcfi(/6/8)');
    expect(cards.single.sourceRefs.single.sourceTitle, 'Fallback Book');
    expect(cards.single.sourceRefs.single.locationLabel, 'Fallback Chapter');
    expect(cards.single.sourceRefs.single.canJumpBack, true);
    expect(reviewItems, hasLength(1));
    expect(reviewItems.single.sourceId, cards.single.id);
    expect(feedback, ['Added to Review inbox']);
    expect(closeCount, 1);

    await tester.runAsync(() async {
      await tester.tap(find.text('Card', skipOffstage: false));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(
      await tester.runAsync(
            () => KnowledgeCardStore(rootDir: knowledgeRoot).list(
              reviewState: KnowledgeCardReviewState.pending,
              origin: KnowledgeCardOrigin.selection,
            ),
          ) ??
          const <KnowledgeCard>[],
      hasLength(1),
    );
    expect(
      await tester.runAsync(
            () => ReviewItemStore(rootDir: knowledgeRoot).list(
              status: ReviewItemStatus.pending,
              sourceType: ReviewItemSourceType.knowledgeCard,
            ),
          ) ??
          const <ReviewItem>[],
      hasLength(1),
    );
  });

  testWidgets('selected-text Graph action opens selection-scoped explorer',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider
              .overrideWithValue(_EmptyConceptGraphStore()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Center(
              child: ExcerptMenu(
                annoCfi: 'epubcfi(/6/4)',
                annoContent: 'Evidence-backed learning needs jump links.',
                onClose: () {},
                footnote: false,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black12),
                ),
                onTranslate: () async {},
                toggleReaderNoteMenu: ({bool? show}) {},
                openReaderNoteMenu: (_) async {},
                onNoteCreated: (_) {},
                axis: Axis.horizontal,
                reverse: false,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(-260, 0),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Graph', skipOffstage: false));
    await tester.pumpAndSettle();

    expect(find.text('Concept graph'), findsOneWidget);
    expect(find.text('No related concepts yet'), findsOneWidget);
    expect(find.text('Create draft candidate'), findsOneWidget);
  });

  testWidgets('selected-text Seminar action opens structured runtime page',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider
              .overrideWithValue(_EmptyConceptGraphStore()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Center(
              child: ExcerptMenu(
                annoCfi: 'epubcfi(/6/4)',
                annoContent: 'Evidence-backed learning needs jump links.',
                onClose: () {},
                footnote: false,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black12),
                ),
                onTranslate: () async {},
                toggleReaderNoteMenu: ({bool? show}) {},
                openReaderNoteMenu: (_) async {},
                onNoteCreated: (_) {},
                axis: Axis.horizontal,
                reverse: false,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.text('Seminar', skipOffstage: false));
    await tester.pumpAndSettle();

    expect(find.text('Seminar Mode'), findsOneWidget);
    expect(find.textContaining('Evidence-backed learning needs jump links.'),
        findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Start Seminar'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Start Seminar'), findsOneWidget);
  });

  testWidgets('selected-text AI action opens chat draft with reader SourceRef',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    final launches = <_AiDraftLaunch>[];
    var closeCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider
              .overrideWithValue(_EmptyConceptGraphStore()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Center(
              child: ExcerptMenu(
                annoCfi: 'epubcfi(/6/4)',
                annoContent: 'Evidence-backed learning needs jump links.',
                onClose: () => closeCount += 1,
                footnote: false,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black12),
                ),
                onTranslate: () async {},
                toggleReaderNoteMenu: ({bool? show}) {},
                openReaderNoteMenu: (_) async {},
                onNoteCreated: (_) {},
                axis: Axis.horizontal,
                reverse: false,
                knowledgeCardReaderContext:
                    const ExcerptKnowledgeCardReaderContext(
                  bookId: 42,
                  bookTitle: 'Evidence Book',
                  chapterTitle: 'Chapter 1',
                ),
                aiChatDraftOpener: ({
                  required content,
                  sourceRef,
                }) async {
                  launches.add(
                    _AiDraftLaunch(
                      content: content,
                      sourceRef: sourceRef,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(-360, 0),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('AI', skipOffstage: false));
    await _pumpMenuActionFrames(tester);

    expect(closeCount, 1);
    expect(launches, hasLength(1));
    expect(
        launches.single.content, 'Evidence-backed learning needs jump links.');
    final sourceRef = launches.single.sourceRef;
    expect(sourceRef, isNotNull);
    expect(sourceRef!.bookId, 42);
    expect(sourceRef.cfi, 'epubcfi(/6/4)');
    expect(sourceRef.sourceTextSnippet,
        'Evidence-backed learning needs jump links.');
    expect(sourceRef.sourceKind, SourceRefKind.reader);
    expect(sourceRef.sourceTitle, 'Evidence Book');
    expect(sourceRef.locationLabel, 'Chapter 1');
    expect(sourceRef.canJumpBack, true);
    expect(sourceRef.jumpLink, startsWith('paperreader://reader/open?'));
  });

  testWidgets('selected-text AI action does not fake grounding without anchor',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    final launches = <_AiDraftLaunch>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conceptGraphStoreProvider
              .overrideWithValue(_EmptyConceptGraphStore()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Center(
              child: ExcerptMenu(
                annoCfi: '   ',
                annoContent: 'Ungrounded selection still opens a draft.',
                onClose: () {},
                footnote: false,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black12),
                ),
                onTranslate: () async {},
                toggleReaderNoteMenu: ({bool? show}) {},
                openReaderNoteMenu: (_) async {},
                onNoteCreated: (_) {},
                axis: Axis.horizontal,
                reverse: false,
                knowledgeCardReaderContext:
                    const ExcerptKnowledgeCardReaderContext(
                  bookId: 42,
                  bookTitle: 'Evidence Book',
                  chapterTitle: 'Chapter 1',
                ),
                aiChatDraftOpener: ({
                  required content,
                  sourceRef,
                }) async {
                  launches.add(
                    _AiDraftLaunch(
                      content: content,
                      sourceRef: sourceRef,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(-360, 0),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('AI', skipOffstage: false));
    await _pumpMenuActionFrames(tester);

    expect(launches, hasLength(1));
    expect(
        launches.single.content, 'Ungrounded selection still opens a draft.');
    expect(launches.single.sourceRef, isNull);
  });
}

Future<void> _pumpMenuActionFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}

class _KnowledgeCardCall {
  const _KnowledgeCardCall({
    required this.bookId,
    required this.cfi,
    required this.selectedText,
    required this.chapterTitle,
    required this.bookTitle,
  });

  final int bookId;
  final String cfi;
  final String selectedText;
  final String? chapterTitle;
  final String? bookTitle;
}

class _AiDraftLaunch {
  const _AiDraftLaunch({
    required this.content,
    required this.sourceRef,
  });

  final String content;
  final SourceRef? sourceRef;
}

class _EmptyConceptGraphStore extends ConceptGraphStore {
  @override
  Future<List<ConceptNode>> listNodes() async => const [];

  @override
  Future<ConceptGraphIntegrityReport> inspectIntegrity() async {
    return const ConceptGraphIntegrityReport(
      orphanNodeIds: [],
      brokenEdgeIds: [],
    );
  }
}
