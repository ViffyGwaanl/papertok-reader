import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/app/app_globals.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/book_note.dart';
import 'package:papertok_reader/widgets/book_notes/book_note_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('BookNoteTile shows traceable source evidence for old highlights',
      (tester) async {
    await _initPrefs();
    await tester.pumpWidget(
      _wrap(
        BookNoteTile(
          note: _note(
            content: 'Traceable highlight text.',
            cfi: 'epubcfi(/6/8)',
            type: 'highlight',
          ),
          sourceTitle: 'Audit Book',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Evidence'), findsOneWidget);
    expect(find.text('1 traceable'), findsOneWidget);
    expect(find.text('Traceable highlight text.'), findsWidgets);
    expect(find.text('Audit Book · Evidence chapter'), findsOneWidget);
  });

  testWidgets(
      'BookNoteTile shows unavailable source state for notes without cfi',
      (tester) async {
    await _initPrefs();
    await tester.pumpWidget(
      _wrap(
        BookNoteTile(
          note: _note(
            content: 'Migrated note text.',
            cfi: '',
            type: 'note',
          ),
          sourceTitle: 'Audit Book',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Evidence'), findsOneWidget);
    expect(find.text('1 unavailable'), findsOneWidget);
    expect(find.text('Migrated note text.'), findsWidgets);
    expect(
      find.textContaining('book-note-source-not-jumpable'),
      findsOneWidget,
    );
  });
}

Future<void> _initPrefs() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await Prefs().initPrefs();
}

Widget _wrap(Widget child) {
  return MaterialApp(
    navigatorKey: navigatorKey,
    locale: const Locale('en'),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(body: child),
  );
}

BookNote _note({
  required String content,
  required String cfi,
  required String type,
}) {
  return BookNote(
    id: 1,
    bookId: 7,
    content: content,
    cfi: cfi,
    chapter: 'Evidence chapter',
    type: type,
    color: 'ffcc00',
    createTime: DateTime.fromMillisecondsSinceEpoch(1000),
    updateTime: DateTime.fromMillisecondsSinceEpoch(1000),
  );
}
