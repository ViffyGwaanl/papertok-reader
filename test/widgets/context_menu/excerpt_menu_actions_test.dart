import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/providers/concept_graph_explorer.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';
import 'package:papertok_reader/service/knowledge/selection_knowledge_card_producer.dart';
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
    await tester.pumpAndSettle();

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
    expect(find.text('Start Seminar'), findsOneWidget);
    expect(find.textContaining('Evidence-backed learning needs jump links.'),
        findsOneWidget);
  });
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
