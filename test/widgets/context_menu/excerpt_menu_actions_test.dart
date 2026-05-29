import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/providers/concept_graph_explorer.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';
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
