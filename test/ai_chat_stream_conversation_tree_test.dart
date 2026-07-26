import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:ai_provider_kit/ai_provider_kit.dart';
import 'package:papertok_reader/providers/ai_chat.dart';
import 'package:papertok_reader/widgets/ai/ai_chat_stream.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('AiChatStream opens tree overlay and switches branches',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _configureAiProvider();
    await Prefs().initPrefs();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const AiChatStream(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AiChatStream)),
    );
    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore([
      ChatMessage.humanText('Question'),
      ChatMessage.ai('First answer'),
      ChatMessage.ai('Second answer'),
    ]);
    await tester.pumpAndSettle();

    expect(find.textContaining('Second answer'), findsOneWidget);
    expect(find.textContaining('First answer'), findsNothing);

    await tester.tap(find.byTooltip('Open conversation tree'));
    await tester.pumpAndSettle();

    expect(find.text('Conversation tree'), findsOneWidget);
    expect(find.text('First answer'), findsOneWidget);

    await tester.tap(find.text('First answer'));
    await tester.pumpAndSettle();

    expect(find.text('Conversation tree'), findsNothing);
    expect(find.textContaining('First answer'), findsOneWidget);
    expect(find.textContaining('Second answer'), findsNothing);
  });
}

void _configureAiProvider() {
  const providerId = 'openai';
  final provider = AiProviderMeta(
    id: providerId,
    name: 'OpenAI',
    type: AiProviderType.openaiCompatible,
    enabled: true,
    isBuiltIn: true,
    createdAt: 1,
    updatedAt: 1,
    logoKey: 'assets/images/openai.png',
  );
  SharedPreferences.setMockInitialValues({
    'selectedAiService': providerId,
    'aiProvidersV1': AiProviderMeta.encodeList([provider]),
    'aiConfig_$providerId': jsonEncode({
      'url': 'https://example.com/v1/chat/completions',
      'api_key': 'TEST_KEY',
      'model': 'test-model',
    }),
  });
}
