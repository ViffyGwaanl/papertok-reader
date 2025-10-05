import 'dart:async';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/service/ai/ai_cache.dart';
import 'package:anx_reader/service/ai/langchain_ai_config.dart';
import 'package:anx_reader/service/ai/langchain_registry.dart';
import 'package:anx_reader/service/ai/langchain_runner.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:langchain/langchain.dart'
    show AgentExecutor, ConversationBufferMemory, ToolsAgent;
import 'package:langchain_core/chat_models.dart';
import 'package:langchain_core/prompts.dart';

final LangchainAiRegistry _registry = LangchainAiRegistry();
final CancelableLangchainRunner _runner = CancelableLangchainRunner();

Stream<String> aiGenerateStream(
  List<ChatMessage> messages, {
  String? identifier,
  Map<String, String>? config,
  bool regenerate = false,
  bool useAgent = false,
}) {
  return _generateStream(
    messages: messages,
    identifier: identifier,
    overrideConfig: config,
    regenerate: regenerate,
    useAgent: useAgent,
  );
}

void cancelActiveAiRequest() {
  _runner.cancel();
}

Stream<String> _generateStream({
  required List<ChatMessage> messages,
  String? identifier,
  Map<String, String>? overrideConfig,
  required bool regenerate,
  required bool useAgent,
}) async* {
  AnxLog.info('aiGenerateStream called identifier: $identifier');
  final selectedIdentifier = identifier ?? Prefs().selectedAiService;
  final savedConfig = Prefs().getAiConfig(selectedIdentifier);
  if (savedConfig.isEmpty &&
      (overrideConfig == null || overrideConfig.isEmpty)) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      yield L10n.of(context).aiServiceNotConfigured;
    } else {
      yield 'AI service not configured';
    }
    return;
  }

  var config = LangchainAiConfig.fromPrefs(selectedIdentifier, savedConfig);
  if (overrideConfig != null && overrideConfig.isNotEmpty) {
    final override =
        LangchainAiConfig.fromPrefs(selectedIdentifier, overrideConfig);
    config = mergeConfigs(config, override);
  }

  final hash = _hashMessages(messages);
  final cacheEntry = await AiCache.getAiCache(hash);

  if (!useAgent &&
      cacheEntry != null &&
      cacheEntry.data.isNotEmpty &&
      !regenerate) {
    yield cacheEntry.decoratedText();
    return;
  }

  AnxLog.info(
      'aiGenerateStream: $selectedIdentifier, model: ${config.model}, baseUrl: ${config.baseUrl}');

  final pipeline = _registry.resolve(config, useAgent: useAgent);
  final model = pipeline.model;

  Stream<String> stream;
  if (useAgent) {
    final inputMessage = _latestUserMessage(messages);
    if (inputMessage == null) {
      yield 'No user input provided';
      return;
    }

    final tools = pipeline.tools;
    if (tools.isEmpty) {
      yield 'Agent mode not supported for this provider.';
      return;
    }

    final memory = ConversationBufferMemory(returnMessages: true);
    final historyMessages = messages.sublist(0, messages.length - 1);
    for (final message in historyMessages) {
      await memory.chatHistory.addChatMessage(message);
    }

    final agent = ToolsAgent.fromLLMAndTools(
      llm: model,
      tools: tools,
      memory: memory,
    );
    final executor = AgentExecutor(
      agent: agent,
      maxIterations: 120,
      returnIntermediateSteps: true,
    );
    stream = _runner.streamAgent(
      executor: executor,
      input: inputMessage,
    );
  } else {
    final prompt = PromptValue.chat(messages);
    stream = _runner.stream(model: model, prompt: prompt);
  }

  var buffer = cacheEntry?.data ?? '';

  try {
    await for (final chunk in stream) {
      buffer = chunk;
      yield buffer;
    }

    if (!useAgent && buffer.isNotEmpty) {
      final conversation = [...messages, ChatMessage.ai(buffer)];
      await AiCache.setAiCache(hash, buffer, selectedIdentifier, conversation);
    }
  } catch (error, stack) {
    final mapped = _mapError(error);
    AnxLog.severe('AI error: $mapped\n$stack');
    yield mapped;
  } finally {
    try {
      model.close();
    } catch (_) {}
  }
}

int _hashMessages(List<ChatMessage> messages) {
  final digest =
      messages.map((m) => '${_roleOf(m)}: ${m.contentAsString}').join('\n');
  return digest.hashCode;
}

String _roleOf(ChatMessage message) {
  return switch (message) {
    SystemChatMessage _ => 'system',
    HumanChatMessage _ => 'user',
    AIChatMessage _ => 'assistant',
    ToolChatMessage _ => 'tool',
    CustomChatMessage custom => custom.role,
  };
}

String _mapError(Object error) {
  final base = 'Error: ';

  if (error is TimeoutException) {
    return '${base}Request timed out';
  }

  if (error is SocketException) {
    return '${base}Network error: ${error.message}';
  }

  final message = error.toString().toLowerCase();

  if (message.contains('401') ||
      message.contains('unauthorized') ||
      message.contains('invalid api key')) {
    return '${base}Authentication failed. Please verify API key.';
  }

  if (message.contains('429') || message.contains('rate limit')) {
    return '${base}Rate limit reached. Try again later.';
  }

  if (message.contains('timeout')) {
    return '${base}Request timed out';
  }

  if (message.contains('network') ||
      message.contains('socket') ||
      message.contains('failed host lookup')) {
    return '${base}Network error: ${error.toString()}';
  }

  return '$base${error.toString()}';
}

String? _latestUserMessage(List<ChatMessage> messages) {
  for (var i = messages.length - 1; i >= 0; i--) {
    final message = messages[i];
    if (message is HumanChatMessage) {
      return message.contentAsString;
    }
  }
  return null;
}
