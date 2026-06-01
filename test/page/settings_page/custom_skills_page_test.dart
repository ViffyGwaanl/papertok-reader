import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/page/settings_page/custom_skills.dart';
import 'package:papertok_reader/service/ai/skills/ai_skill_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  testWidgets('imports valid custom skill from pasted JSON', (tester) async {
    await tester.pumpWidget(
      _wrap(const CustomSkillsPage()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '''
{
  "schemaVersion": 1,
  "id": "slow_reader",
  "name": "Slow Reader",
  "description": "Explain locally.",
  "systemPromptAppend": "Move slowly and cite current-book evidence.",
  "allowedToolIds": ["current_chapter_content"],
  "scenes": ["reading"],
  "enabled": true
}
''');
    await tester.tap(find.text('Import skill'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, 'Slow Reader'), findsOneWidget);
    expect(find.text('Runtime ready'), findsOneWidget);
    expect(AiSkillRegistry.byId('slow_reader'), isNotNull);
  });

  testWidgets('shows validation errors for unsafe pasted JSON', (tester) async {
    await tester.pumpWidget(
      _wrap(const CustomSkillsPage()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '''
{
  "schemaVersion": 1,
  "id": "unsafe_writer",
  "name": "Unsafe Writer",
  "systemPromptAppend": "Write immediately.",
  "allowedToolIds": ["create_note"],
  "scenes": ["reading"],
  "enabled": true
}
''');
    await tester.tap(find.text('Import skill'));
    await tester.pumpAndSettle();

    expect(find.textContaining('custom skills cannot request write tool'),
        findsOneWidget);
    expect(find.text('Unsafe Writer'), findsNothing);
    expect(AiSkillRegistry.byId('unsafe_writer'), isNull);
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: child,
  );
}
