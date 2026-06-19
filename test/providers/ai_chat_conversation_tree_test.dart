import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/models/ai_provider_meta.dart';
import 'package:papertok_reader/providers/ai_chat.dart';
import 'package:papertok_reader/service/ai/ai_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    Prefs().aiTitleGenerationEnabled = false;
    _configureAiProvider();
  });

  test('conversationTree exposes the current branching tree read-only',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(aiChatProvider.future);

    final notifier = container.read(aiChatProvider.notifier);
    notifier.restore(
      [
        ChatMessage.humanText('Question'),
        ChatMessage.ai('First answer'),
        ChatMessage.ai('Second answer'),
      ],
      sessionId: 'tree-session',
    );

    final tree = notifier.conversationTree;
    final assistantNodes = tree.nodes.values
        .where((node) => node.toChatMessage() is AIChatMessage)
        .toList(growable: false);

    expect(tree.activePathMessages().map((m) => m.contentAsString), [
      'Question',
      'Second answer',
    ]);
    expect(assistantNodes, hasLength(2));
  });

  test('activatePathToNode switches the active path to a sibling branch',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(aiChatProvider.future);

    final notifier = container.read(aiChatProvider.notifier);
    notifier.restore(
      [
        ChatMessage.humanText('Question'),
        ChatMessage.ai('First answer'),
        ChatMessage.ai('Second answer'),
      ],
      sessionId: 'tree-session',
    );
    final firstAnswerNodeId = _nodeIdForText(
      notifier.conversationTree,
      'First answer',
    );

    final didSwitch = notifier.activatePathToNode(firstAnswerNodeId);

    expect(didSwitch, isTrue);
    expect(
        container.read(aiChatProvider).value!.map((m) => m.contentAsString), [
      'Question',
      'First answer',
    ]);
    expect(
      notifier.conversationTree.activePathNodeIds().last,
      firstAnswerNodeId,
    );
  });

  test('activatePathToNode persists conversationV2 after switching path',
      () async {
    final tempDir = Directory.systemTemp.createTempSync('ai-chat-tree-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(aiChatProvider.future);

    final notifier = container.read(aiChatProvider.notifier);
    notifier.restore(
      [
        ChatMessage.humanText('Question'),
        ChatMessage.ai('First answer'),
        ChatMessage.ai('Second answer'),
      ],
      sessionId: 'tree-session',
    );
    final firstAnswerNodeId = _nodeIdForText(
      notifier.conversationTree,
      'First answer',
    );

    expect(notifier.activatePathToNode(firstAnswerNodeId), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));
    final persistedTree =
        AiConversationTree.fromJson(history.single.conversationV2!);
    expect(persistedTree.activePathNodeIds().last, firstAnswerNodeId);
    expect(persistedTree.activePathMessages().map((m) => m.contentAsString), [
      'Question',
      'First answer',
    ]);
  });
}

String _nodeIdForText(AiConversationTree tree, String text) {
  for (final entry in tree.nodes.entries) {
    if (entry.value.toChatMessage()?.contentAsString == text) {
      return entry.key;
    }
  }
  fail('No node found for "$text"');
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
  );
  Prefs().selectedAiService = providerId;
  Prefs().aiProvidersV1 = [provider];
  Prefs().saveAiConfig(providerId, {
    'apiKey': 'test-key',
    'baseUrl': 'http://127.0.0.1.invalid/v1',
    'model': 'test-model',
  });
}

void _mockPathProvider(String? cachePath) {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    channel,
    cachePath == null
        ? null
        : (call) async {
            if (call.method == 'getApplicationCacheDirectory') {
              return cachePath;
            }
            return cachePath;
          },
  );
}
