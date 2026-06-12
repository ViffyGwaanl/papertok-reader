import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/page/settings_page/ai_seminar_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  testWidgets('seminar settings persist default max rounds', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('zh', 'CN'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiSeminarConfigPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final maxRoundsField =
        find.byKey(const ValueKey('seminar-default-max-rounds'));
    expect(maxRoundsField, findsOneWidget);

    await tester.enterText(maxRoundsField, '10');
    await tester.pump();

    expect(Prefs().aiSeminarDefaultMaxRounds, 10);
  });
}
