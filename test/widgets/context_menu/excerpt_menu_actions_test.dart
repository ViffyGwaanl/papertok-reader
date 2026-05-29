import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/widgets/context_menu/excerpt_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('selected-text menu exposes KnowledgeCard and Seminar actions',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    await tester.pumpWidget(
      MaterialApp(
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
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Card', skipOffstage: false), findsOneWidget);
    expect(find.text('Seminar', skipOffstage: false), findsOneWidget);
  });
}
