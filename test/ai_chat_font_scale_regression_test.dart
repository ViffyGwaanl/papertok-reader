import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/ai_provider_meta.dart';
import 'package:anx_reader/providers/ai_chat.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/tool_tile_base.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Finder textFragment(String text) {
    return find.byWidgetPredicate((widget) {
      if (widget is RichText) {
        return widget.text.toPlainText().contains(text);
      }
      if (widget is Text) {
        final value = widget.data ?? widget.textSpan?.toPlainText() ?? '';
        return value.contains(text);
      }
      if (widget is SelectableText) {
        final value = widget.data ?? widget.textSpan?.toPlainText() ?? '';
        return value.contains(text);
      }
      return false;
    });
  }

  Future<void> pumpAiChat(
    WidgetTester tester, {
    required double scale,
    required List<ChatMessage> messages,
  }) async {
    final providers = [
      AiProviderMeta(
        id: 'openai',
        name: 'OpenAI',
        type: AiProviderType.openaiCompatible,
        enabled: true,
        isBuiltIn: true,
        createdAt: 1,
        updatedAt: 1,
      ),
    ];

    SharedPreferences.setMockInitialValues({
      'selectedAiService': 'openai',
      'aiChatFontScale': scale,
      'aiProvidersV1': AiProviderMeta.encodeList(providers),
      'aiConfig_openai': jsonEncode({}),
    });

    await Prefs().initPrefs();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          navigatorKey: navigatorKey,
          locale: const Locale('zh', 'CN'),
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
    container.read(aiChatProvider.notifier).restore(messages);
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> pumpToolTile(
    WidgetTester tester, {
    required double scale,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData().copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: Material(
              child: ToolTileBase(
                title: 'Demo tool',
                leadingIcon: Icons.build,
                statusColor: Colors.green,
                initiallyExpanded: true,
                contentBuilder: (context) => SelectableText(
                  'Tool output',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('AiChatStream scales message content but not input chrome', (
    tester,
  ) async {
    final assistantBlockHeights = <double>[];
    final userBlockHeights = <double>[];
    final thinkingHeaderHeights = <double>[];
    final inputHeights = <double>[];

    for (final scale in [0.8, 1.0, 1.4]) {
      await pumpAiChat(
        tester,
        scale: scale,
        messages: const [
          HumanChatMessage(content: ChatMessageContentText(text: 'User plain')),
          AIChatMessage(
            content: '<think>Thought preview</think># Heading\n\nBody line',
          ),
        ],
      );

      final l10n = L10n.of(tester.element(find.byType(AiChatStream)));
      assistantBlockHeights.add(
        tester.getSize(textFragment('Body line').first).height,
      );
      userBlockHeights.add(
        tester.getSize(textFragment('User plain').first).height,
      );
      thinkingHeaderHeights.add(
        tester.getSize(textFragment(l10n.aiSectionThinking).first).height,
      );
      inputHeights.add(
        tester.getSize(find.text(l10n.aiHintInputPlaceholder).first).height,
      );
    }

    expect(assistantBlockHeights[0], lessThan(assistantBlockHeights[1]));
    expect(assistantBlockHeights[1], lessThan(assistantBlockHeights[2]));
    expect(userBlockHeights[0], lessThan(userBlockHeights[1]));
    expect(userBlockHeights[1], lessThan(userBlockHeights[2]));
    expect(thinkingHeaderHeights[0], lessThan(thinkingHeaderHeights[1]));
    expect(thinkingHeaderHeights[1], lessThan(thinkingHeaderHeights[2]));

    expect(inputHeights[0], closeTo(inputHeights[1], 0.01));
    expect(inputHeights[1], closeTo(inputHeights[2], 0.01));
  });

  test('StyledMarkdown typography keeps headings compact and code proportional',
      () {
    final theme = ThemeData.light();
    final base = StyledMarkdownTypography.baseBodyStyle(theme);
    final scaled08 = StyledMarkdownTypography.scaledStyle(
      base,
      TextScaler.linear(0.8),
    );
    final scaled10 = StyledMarkdownTypography.scaledStyle(
      base,
      TextScaler.linear(1.0),
    );
    final scaled14 = StyledMarkdownTypography.scaledStyle(
      base,
      TextScaler.linear(1.4),
    );

    final theme10 = StyledMarkdownTypography.markdownTheme(
      brightness: Brightness.light,
      bodyStyle: scaled10,
    );
    final code10 = StyledMarkdownTypography.codeStyle(scaled10);

    expect(scaled08.fontSize, lessThan(scaled10.fontSize!));
    expect(scaled10.fontSize, lessThan(scaled14.fontSize!));
    expect(theme10.h1!.fontSize, greaterThan(scaled10.fontSize!));
    expect(theme10.h1!.fontSize, lessThan((scaled10.fontSize ?? 14) * 1.5));
    expect(theme10.h6!.fontSize, closeTo(scaled10.fontSize!, 0.001));
    expect(code10.fontSize, closeTo((scaled10.fontSize ?? 14) * 0.95, 0.001));
    expect(code10.height, closeTo(StyledMarkdownTypography.codeHeight, 0.001));
  });

  testWidgets('ToolTileBase follows the ambient message text scale',
      (tester) async {
    final outputHeights = <double>[];

    for (final scale in [0.8, 1.0, 1.4]) {
      await pumpToolTile(tester, scale: scale);
      outputHeights
          .add(tester.getSize(textFragment('Tool output').first).height);
    }

    expect(outputHeights[0], lessThan(outputHeights[1]));
    expect(outputHeights[1], lessThan(outputHeights[2]));
  });
}
