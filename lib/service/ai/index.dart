import 'dart:async';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/ai_provider_meta.dart';
import 'package:anx_reader/service/ai/langchain_ai_config.dart';
import 'package:anx_reader/service/ai/langchain_registry.dart';
import 'package:anx_reader/service/ai/langchain_runner.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/service/ai/api_key_rotation.dart';
import 'package:riverpod/riverpod.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:langchain_core/prompts.dart';

enum AiRequestScope { chat, translate }

final CancelableLangchainRunner _chatRunner = CancelableLangchainRunner();
final CancelableLangchainRunner _translationRunner =
    CancelableLangchainRunner();

CancelableLangchainRunner _runnerForScope(AiRequestScope scope) {
  return switch (scope) {
    AiRequestScope.chat => _chatRunner,
    AiRequestScope.translate => _translationRunner,
  };
}

Stream<String> aiGenerateStream(
  List<ChatMessage> messages, {
  AiRequestScope scope = AiRequestScope.chat,
  String? identifier,
  Map<String, String>? config,
  bool regenerate = false,
  bool useAgent = false,
  Ref? ref,
}) {
  if (useAgent) {
    assert(ref != null, 'ref must be provided when useAgent is true');
  }
  LangchainAiRegistry registry = LangchainAiRegistry(ref);

  return _generateStream(
    messages: messages,
    identifier: identifier,
    overrideConfig: config,
    regenerate: regenerate,
    useAgent: useAgent,
    registry: registry,
    runner: _runnerForScope(scope),
  );
}

void cancelActiveAiRequest() {
  _chatRunner.cancel();
}

void cancelActiveTranslationRequest() {
  _translationRunner.cancel();
}

Stream<String> _generateStream({
  required List<ChatMessage> messages,
  required CancelableLangchainRunner runner,
  String? identifier,
  Map<String, String>? overrideConfig,
  required bool regenerate,
  required bool useAgent,
  required LangchainAiRegistry registry,
}) async* {
  AnxLog.info('aiGenerateStream called identifier: $identifier');
  final sanitizedMessages = _sanitizeMessagesForPrompt(messages);
  final selectedProviderId = identifier ?? Prefs().selectedAiService;

  // Provider Center integration:
  // - `selectedAiService` stores a provider id (built-in id or custom uuid).
  // - LangChain registry resolves by *provider kind* (openai/claude/gemini).
  //   We map from provider meta.type to a stable built-in identifier.
  final meta = Prefs().getAiProviderMeta(selectedProviderId);
  final registryIdentifier = meta == null
      ? selectedProviderId
      : switch (meta.type) {
          AiProviderType.anthropic => 'claude',
          AiProviderType.gemini => 'gemini',
          AiProviderType.openaiResponses => 'openai-responses',
          AiProviderType.openaiCompatible => 'openai',
        };

  final savedConfig = Prefs().getAiConfig(selectedProviderId);
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

  var config = LangchainAiConfig.fromPrefs(registryIdentifier, savedConfig);
  if (overrideConfig != null && overrideConfig.isNotEmpty) {
    final override =
        LangchainAiConfig.fromPrefs(registryIdentifier, overrideConfig);
    config = mergeConfigs(config, override);
  }

  // Multi API keys support (round-robin per request):
  // Users can input multiple keys in the API key field separated by comma/semicolon/newline,
  // or a JSON array string.
  final rawMergedConfig = <String, String>{}
    ..addAll(savedConfig)
    ..addAll(overrideConfig ?? const {});

  final apiKeys = parseApiKeysFromConfig(rawMergedConfig);

  AnxLog.info(
    'aiGenerateStream: $selectedProviderId($registryIdentifier), model: ${config.model}, baseUrl: ${config.baseUrl}',
  );

  bool shouldRetry(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('401') ||
        message.contains('unauthorized') ||
        message.contains('invalid api key')) {
      return true;
    }
    if (message.contains('429') || message.contains('rate limit')) {
      return true;
    }
    if (message.contains('503') || message.contains('bad gateway')) {
      return true;
    }
    return false;
  }

  // Multi-key failover:
  // - Round-robin starting point is tracked per provider id.
  // - If a request fails immediately (no streamed output yet) with an auth/rate
  //   limit error, we retry with the next key.
  final keys = apiKeys;
  final startIndex = apiKeyRoundRobin.startIndex(selectedProviderId);
  final attempts = keys.isEmpty ? 1 : keys.length;

  for (var attempt = 0; attempt < attempts; attempt++) {
    final attemptKey = keys.isEmpty
        ? config.apiKey
        : keys[(startIndex + attempt) % keys.length];
    final attemptConfig = config.copyWith(apiKey: attemptKey);

    if (keys.length > 1) {
      AnxLog.info(
        'aiGenerateStream: apiKey rotation provider=$selectedProviderId keys=${keys.length} attempt=${attempt + 1}/$attempts',
      );
    }

    final pipeline = registry.resolve(attemptConfig, useAgent: useAgent);
    final model = pipeline.model;

    Stream<String> stream;
    if (useAgent) {
      final inputMessage = _latestUserMessage(sanitizedMessages);
      if (inputMessage == null) {
        yield 'No user input provided';
        try {
          model.close();
        } catch (_) {}
        return;
      }

      final tools = pipeline.tools;
      if (tools.isEmpty) {
        yield 'Agent mode not supported for this provider.';
        try {
          model.close();
        } catch (_) {}
        return;
      }

      final historyMessages = sanitizedMessages
          .sublist(0, sanitizedMessages.length - 1)
          .toList(growable: false);

      stream = runner.streamAgent(
        model: model,
        tools: tools,
        history: historyMessages,
        input: inputMessage,
        systemMessage: pipeline.systemMessage,
      );
    } else {
      final prompt = PromptValue.chat(sanitizedMessages);
      stream = runner.stream(model: model, prompt: prompt);
    }

    var buffer = '';

    try {
      await for (final chunk in stream) {
        buffer = chunk;
        yield buffer;
      }

      // Success: advance round-robin index for next request.
      if (keys.length > 1) {
        apiKeyRoundRobin.advance(selectedProviderId, startIndex + attempt + 1);
      }
      return;
    } catch (error, stack) {
      // Retry only if:
      // - multi-key enabled
      // - no partial output yet
      // - error looks like auth/rate-limit
      final canRetry = keys.length > 1 && buffer.isEmpty && shouldRetry(error);
      if (canRetry && attempt < attempts - 1) {
        AnxLog.info(
          'aiGenerateStream: retry with next apiKey provider=$selectedProviderId attempt=${attempt + 1}/$attempts error=${_mapError(error)}',
        );
        continue;
      }

      final mapped = _mapError(error);
      AnxLog.severe('AI error: $mapped\n$stack');
      yield mapped;
      return;
    } finally {
      try {
        model.close();
      } catch (_) {}
    }
  }
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

List<ChatMessage> _sanitizeMessagesForPrompt(List<ChatMessage> messages) {
  return messages.map((message) {
    if (message is AIChatMessage) {
      final plainText = reasoningContentToPlainText(message.content);
      if (plainText == message.content) {
        return message;
      }
      return AIChatMessage(
        content: plainText,
        toolCalls: message.toolCalls,
      );
    }
    return message;
  }).toList(growable: false);
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
