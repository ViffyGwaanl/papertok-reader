import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/ai_provider_meta.dart';
import 'package:papertok_reader/page/settings_page/ai_seminar_config.dart';
import 'package:papertok_reader/page/settings_page/custom_skills.dart';
import 'package:papertok_reader/service/ai/skills/custom_skill_store.dart';
import 'package:papertok_reader/widgets/ai/ai_chat_stream.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Choose style custom skill row opens custom skill settings',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const providerId = 'openai';
      final providers = [
        AiProviderMeta(
          id: providerId,
          name: 'OpenAI',
          type: AiProviderType.openaiCompatible,
          enabled: true,
          isBuiltIn: true,
          createdAt: 1,
          updatedAt: 1,
        ),
      ];

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
      });
      await Prefs().initPrefs();
      await CustomSkillStore().importJson('''
{
  "schemaVersion": 1,
  "id": "local_terms",
  "name": "Local Terms",
  "description": "Explain local concepts.",
  "systemPromptAppend": "Prefer local term definitions.",
  "allowedToolIds": ["current_chapter_content"],
  "scenes": ["reading"],
  "enabled": true
}
''');

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: AiChatStream(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose style'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();

      expect(find.text('Local Terms'), findsOneWidget);
      expect(find.textContaining('Custom'), findsAtLeastNWidgets(1));

      await tester.tap(find.textContaining('Custom').last);
      await tester.pumpAndSettle();

      expect(find.byType(CustomSkillsPage), findsOneWidget);
      expect(find.text('Local Terms'), findsOneWidget);
      expect(Prefs().activeAiSkillId, 'paper_analyzer');
    },
  );

  testWidgets(
    'Choose style built-in skill row opens prompt settings without selecting it',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const providerId = 'openai';
      final providers = [
        AiProviderMeta(
          id: providerId,
          name: 'OpenAI',
          type: AiProviderType.openaiCompatible,
          enabled: true,
          isBuiltIn: true,
          createdAt: 1,
          updatedAt: 1,
        ),
      ];

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'reading_companion',
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: AiChatStream(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose style'));
      await tester.pumpAndSettle();

      expect(find.text('Paper Analyzer'), findsOneWidget);
      expect(find.text('Skill settings'), findsAtLeastNWidgets(1));

      await tester.tap(find.text('Skill settings').first);
      await tester.pumpAndSettle();

      expect(find.text('Paper Analyzer settings'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).maxLength,
        Prefs.aiSkillCustomPromptMaxChars,
      );
      await tester.enterText(
        find.byType(TextField).last,
        'Always include a methods-versus-evidence checklist.',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(Prefs().activeAiSkillId, 'reading_companion');
      expect(
        Prefs().prefs.getString('aiSkillPromptProfilesV1'),
        contains('methods-versus-evidence checklist'),
      );
    },
  );

  testWidgets(
    'Choose style Seminar row opens Seminar settings without selecting it',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const providerId = 'openai';
      final providers = [
        AiProviderMeta(
          id: providerId,
          name: 'OpenAI',
          type: AiProviderType.openaiCompatible,
          enabled: true,
          isBuiltIn: true,
          createdAt: 1,
          updatedAt: 1,
        ),
      ];

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'reading_companion',
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: AiChatStream(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose style'));
      await tester.pumpAndSettle();

      expect(find.text('Seminar Mode'), findsOneWidget);
      expect(find.text('Seminar settings'), findsOneWidget);

      await tester.tap(find.text('Seminar settings'));
      await tester.pumpAndSettle();

      expect(find.byType(AiSeminarConfigPage), findsOneWidget);
      expect(find.text('Role prompt profiles'), findsOneWidget);
      expect(Prefs().activeAiSkillId, 'reading_companion');
    },
  );
}
