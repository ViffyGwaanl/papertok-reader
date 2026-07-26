import 'dart:async';
import 'dart:io';

import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/main.dart';
import 'package:ai_provider_kit/ai_provider_kit.dart';
import 'package:papertok_reader/service/ai/langchain_ai_config.dart';
import 'package:papertok_reader/service/ai/langchain_registry.dart';
import 'package:papertok_reader/service/ai/ai_usage_tracker.dart';
import 'package:papertok_reader/service/ai/annotation_ledger.dart';
import 'package:papertok_reader/service/ai/conversation_compressor.dart';
import 'package:papertok_reader/service/ai/langchain_runner.dart';
import 'package:papertok_reader/utils/ai_reasoning_parser.dart';
import 'package:papertok_reader/utils/log/common.dart';
import 'package:papertok_reader/service/mcp/mcp_client_service.dart';
import 'package:papertok_reader/widgets/ai/tool_approval_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:langchain_core/prompts.dart';

enum AiRequestScope { chat, translate, imageAnalysis }

final CancelableLangchainRunner _chatRunner = CancelableLangchainRunner(
  approvalDelegate: buildToolApprovalDialogDelegate(),
);
final CancelableLangchainRunner _translationRunner =
    CancelableLangchainRunner();
final CancelableLangchainRunner _imageAnalysisRunner =
    CancelableLangchainRunner();

/// Session-level usage trackers (keyed by conversationId).
final Map<String, AiUsageTracker> _sessionTrackers = {};

/// Session-level annotation ledgers (keyed by conversationId).
/// Persists across turns so AI can see annotations it created earlier.
final Map<String, AnnotationLedger> _sessionLedgers = {};

/// Session-level compression failure counts.
final Map<String, int> _compressionFailures = {};

const _compressor = ConversationCompressor();

AiUsageTracker _trackerForSession(String? id) =>
    _sessionTrackers.putIfAbsent(id ?? '', () => AiUsageTracker());

/// Returns the usage tracker for a conversation (for UI display).
AiUsageTracker? getUsageTracker(String? conversationId) =>
    _sessionTrackers[conversationId ?? ''];

/// Returns the usage tracker for a conversation, creating it if necessary.
AiUsageTracker ensureAiUsageTracker(String? conversationId) =>
    _trackerForSession(conversationId);

CancelableLangchainRunner _runnerForScope(AiRequestScope scope) {
  return switch (scope) {
    AiRequestScope.chat => _chatRunner,
    AiRequestScope.translate => _translationRunner,
    AiRequestScope.imageAnalysis => _imageAnalysisRunner,
  };
}

Stream<String> aiGenerateStream(
  List<ChatMessage> messages, {
  AiRequestScope scope = AiRequestScope.chat,
  String? identifier,
  Map<String, String>? config,
  bool regenerate = false,
  bool useAgent = false,
  String? conversationId,
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
    conversationId: conversationId,
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

void cancelActiveImageAnalysisRequest() {
  _imageAnalysisRunner.cancel();
}

Stream<String> _generateStream({
  required List<ChatMessage> messages,
  required CancelableLangchainRunner runner,
  String? identifier,
  Map<String, String>? overrideConfig,
  required bool regenerate,
  required bool useAgent,
  String? conversationId,
  required LangchainAiRegistry registry,
}) async* {
  AnxLog.info('aiGenerateStream called identifier: $identifier');
  final selectedProviderId = identifier ?? Prefs().selectedAiService;

  // Provider Center integration:
  // - `selectedAiService` stores a provider id (built-in id or custom uuid).
  // - LangChain registry resolves by *provider kind* (openai/claude/gemini).
  //   We map from provider meta.type to a stable built-in identifier.
  final meta = Prefs().getAiProviderMeta(selectedProviderId);
  var registryIdentifier = meta == null
      ? selectedProviderId
      : switch (meta.type) {
          AiProviderType.anthropic => 'claude',
          AiProviderType.gemini => 'gemini',
          AiProviderType.openaiResponses => 'openai-responses',
          AiProviderType.openaiCompatible => 'openai',
        };

  // DeepSeek detection: the meta-type switch collapses every OpenAI-compatible
  // provider to 'openai', including DeepSeek. That hides the dedicated
  // ChatDeepSeek model that handles V3.1+ thinking-mode `reasoning_content`
  // correctly. Promote to 'deepseek' when we can tell:
  //   - the selected provider id is the built-in 'deepseek'
  //   - the configured base URL points at api.deepseek.com
  //   - the configured model name starts with deepseek-* (covers NewAPI /
  //     OpenRouter gateways and any other relay that exposes DeepSeek models)
  if (registryIdentifier == 'openai') {
    final cfg = Prefs().getAiConfig(selectedProviderId);
    final mergedRaw = <String, String>{...cfg, ...(overrideConfig ?? const {})};
    final url = (mergedRaw['url'] ?? '').toLowerCase();
    final model = (mergedRaw['model'] ?? '').toLowerCase();
    if (selectedProviderId == 'deepseek' ||
        url.contains('deepseek.com') ||
        model.startsWith('deepseek-') ||
        model == 'deepseek-chat' ||
        model == 'deepseek-reasoner') {
      AnxLog.info(
        'aiGenerateStream: promoting "$selectedProviderId" to deepseek '
        '(url=$url model=$model)',
      );
      registryIdentifier = 'deepseek';
    }
  }

  final sanitizedMessages = _sanitizeMessagesForPrompt(
    messages,
    registryIdentifier: registryIdentifier,
  );

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

  Future<void> maybeAutoRefreshMcpTools() async {
    if (!useAgent) return;
    if (!Prefs().mcpAutoRefreshToolsV1) return;

    final enabledServers =
        Prefs().mcpServersV1.where((s) => s.enabled).toList(growable: false);
    if (enabledServers.isEmpty) return;

    // Refresh only when cache is missing (default safe behavior).
    final missingCache = enabledServers
        .where((s) => Prefs().getMcpToolsCacheV1(s.id) == null)
        .toList(growable: false);
    if (missingCache.isEmpty) return;

    AnxLog.info(
      'MCP: auto refreshing tools for ${missingCache.length} server(s) (cache missing)',
    );

    final futures = missingCache.map((server) async {
      try {
        final tools = await McpClientService.instance
            .listTools(server)
            .timeout(const Duration(seconds: 6));
        Prefs().saveMcpToolsCacheV1(server.id, tools);
        AnxLog.info(
          'MCP: tools refreshed serverId=${server.id} tools=${tools.length}',
        );
      } catch (e) {
        AnxLog.warning(
          'MCP: auto refresh tools failed serverId=${server.id} endpoint=${server.endpoint} error=$e',
        );
      }
    }).toList(growable: false);

    // Best-effort: don't block the chat forever.
    try {
      await Future.wait(futures).timeout(const Duration(seconds: 8));
    } catch (_) {
      // ignore
    }
  }

  await maybeAutoRefreshMcpTools();

  // Multi API keys support (round-robin per request) + failure stats.
  //
  // We prefer the managed list stored in `api_keys` (JSON array of objects).
  // For backward compatibility we also accept delimiter-separated strings and
  // `api_key`.
  final rawMergedConfig = <String, String>{}
    ..addAll(savedConfig)
    ..addAll(overrideConfig ?? const {});

  final managedEntries = decodeAiApiKeyEntries(rawMergedConfig);
  final hasManagedList = (savedConfig['api_keys'] ?? '').trim().isNotEmpty;
  final nowMs = DateTime.now().millisecondsSinceEpoch;

  // Policy + attempt order come from ai_provider_kit; semantics (thresholds,
  // per-class cooldowns, all-cooling fallback, round-robin offset) are the
  // ones this loop used to hand-roll — kept in lockstep with the embeddings
  // call site.
  final policy = AiKeyRotationPolicy.fromRawConfig(rawMergedConfig);

  AnxLog.info(
    'aiGenerateStream: $selectedProviderId($registryIdentifier), model: ${config.model}, baseUrl: ${config.baseUrl}',
  );

  void persistManagedKeys(
    List<AiApiKeyEntry> entries, {
    required String activeKey,
  }) {
    if (!hasManagedList) return;
    final cfg = Prefs().getAiConfig(selectedProviderId);
    cfg['api_keys'] = encodeAiApiKeyEntries(entries);
    cfg['api_key'] = activeKey;
    Prefs().saveAiConfig(selectedProviderId, cfg);
  }

  final startIndex = apiKeyRoundRobin.startIndex(selectedProviderId);
  final keyAttempts = planAiKeyAttempts(
    entries: managedEntries,
    fallbackApiKey: config.apiKey,
    startIndex: startIndex,
    nowMs: nowMs,
  );
  // With nothing configured, still fire one bare attempt — the provider's own
  // auth error is more useful to the user than a local refusal.
  final attempts = keyAttempts.isEmpty ? 1 : keyAttempts.length;

  for (var attempt = 0; attempt < attempts; attempt++) {
    final keyAttempt = keyAttempts.isEmpty ? null : keyAttempts[attempt];
    final attemptEntry = keyAttempt?.entry;
    final attemptKey = keyAttempt?.apiKey ?? config.apiKey;

    final attemptConfig = config.copyWith(apiKey: attemptKey);

    if (keyAttempts.length > 1) {
      AnxLog.info(
        'aiGenerateStream: apiKey rotation provider=$selectedProviderId keys=${keyAttempts.length} attempt=${attempt + 1}/$attempts',
      );
    }

    final sessionLedger = useAgent
        ? _sessionLedgers.putIfAbsent(
            conversationId ?? '', () => AnnotationLedger())
        : null;
    final pipeline = registry.resolve(
      attemptConfig,
      useAgent: useAgent,
      annotationLedger: sessionLedger,
    );
    final model = pipeline.model;

    Stream<String> stream;
    if (useAgent) {
      final inputMessage = _latestUserChatMessage(sanitizedMessages);
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

      final inputIndex = sanitizedMessages.lastIndexWhere(
        (m) => m is HumanChatMessage,
      );
      final historyMessages = inputIndex > 0
          ? sanitizedMessages.sublist(0, inputIndex).toList(growable: false)
          : const <ChatMessage>[];

      // Conversation compression: if context usage > 85%, summarise old
      // messages via LLM before sending. Falls back to truncation after
      // 3 consecutive failures.
      var compressedHistory = historyMessages;
      if (historyMessages.length >
          ConversationCompressor.keepRecentMessages + 2) {
        final convoId = conversationId ?? '';
        final failures = _compressionFailures[convoId] ?? 0;
        final estimated = historyMessages.fold<int>(
          0,
          (sum, m) => sum + (m.contentAsString.length ~/ 4) + 24,
        );

        // Derive context window from model config; fall back to 128K.
        final contextWindow = config.maxTokens ?? 128000;

        if (_compressor.shouldCompress(
          estimatedTokens: estimated,
          contextWindowSize: contextWindow,
          consecutiveFailures: failures,
        )) {
          try {
            final result = await _compressor.compress(
              messages: historyMessages,
              model: model,
            );
            if (result.compressed) {
              compressedHistory = result.messages;
              _compressionFailures[convoId] = 0;
            } else {
              _compressionFailures[convoId] = failures + 1;
            }
          } catch (e) {
            AnxLog.warning('ConversationCompressor failed: $e');
            _compressionFailures[convoId] = failures + 1;
          }
        }
      }

      final tracker = _trackerForSession(conversationId);

      stream = runner.streamAgent(
        model: model,
        tools: tools,
        history: compressedHistory,
        inputMessage: inputMessage,
        conversationId: conversationId,
        systemMessage: pipeline.systemMessage,
        usageTracker: tracker,
        toolPermissionMatrix: pipeline.permissionMatrix,
      );
    } else {
      final prompt = PromptValue.chat(sanitizedMessages);
      final tracker =
          conversationId == null ? null : _trackerForSession(conversationId);
      stream = runner.stream(
        model: model,
        prompt: prompt,
        usageTracker: tracker,
      );
    }

    var buffer = '';

    try {
      await for (final chunk in stream) {
        buffer = chunk;
        yield buffer;
      }

      // Success: advance round-robin index for next request and persist stats.
      if (keyAttempts.length > 1) {
        apiKeyRoundRobin.advance(selectedProviderId, startIndex + attempt + 1);
      }

      if (attemptEntry != null && hasManagedList) {
        final updated = applyAiKeySuccess(attemptEntry, nowMs: nowMs);
        persistManagedKeys(
          upsertAiKeyEntry(managedEntries, updated),
          activeKey: attemptKey,
        );
      }

      return;
    } catch (error, stack) {
      final mapped = _mapError(error);

      // Update failure stats only when:
      // - managed list is enabled
      // - the request failed before producing any streamed output
      // - the error looks retryable (auth / rate limit / gateway)
      final failure = classifyAiFailureText(error);
      if (attemptEntry != null && hasManagedList && buffer.isEmpty) {
        final updated = applyAiKeyFailure(
          attemptEntry,
          nowMs: nowMs,
          policy: policy,
          failure: failure,
        );
        persistManagedKeys(
          upsertAiKeyEntry(managedEntries, updated),
          activeKey: attemptKey,
        );
      }

      // Retry only if:
      // - multi-key enabled
      // - no partial output yet
      // - error looks retryable
      final canRetry = keyAttempts.length > 1 &&
          buffer.isEmpty &&
          isAiKeyCooldownWorthy(failure);
      if (canRetry && attempt < attempts - 1) {
        AnxLog.info(
          'aiGenerateStream: retry with next apiKey provider=$selectedProviderId attempt=${attempt + 1}/$attempts error=$mapped',
        );
        continue;
      }

      AnxLog.severe('AI error: $mapped\n$stack');
      yield mergeStreamErrorWithPartial(buffer, mapped);
      return;
    } finally {
      try {
        model.close();
      } catch (_) {}
    }
  }
}

String mergeStreamErrorWithPartial(String partial, String error) {
  final normalizedError = error.trim();
  final normalizedPartial = partial.trimRight();
  if (normalizedPartial.isEmpty) {
    return normalizedError;
  }
  if (normalizedError.isEmpty) {
    return normalizedPartial;
  }
  return '$normalizedPartial\n\n$normalizedError';
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

List<ChatMessage> _sanitizeMessagesForPrompt(
  List<ChatMessage> messages, {
  required String registryIdentifier,
}) {
  // DeepSeek's thinking-mode API expects the chain-of-thought to be passed
  // back in a dedicated `reasoning_content` field on the assistant message.
  // ChatDeepSeek extracts `<think>…</think>` directly from the raw assistant
  // payload, so we must NOT flatten the structured content here for DeepSeek
  // — otherwise the model would see thinking text crammed into `content` and
  // reject the request with "must be passed back".
  if (registryIdentifier == 'deepseek') {
    return messages;
  }

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

HumanChatMessage? _latestUserChatMessage(List<ChatMessage> messages) {
  for (var i = messages.length - 1; i >= 0; i--) {
    final message = messages[i];
    if (message is HumanChatMessage) {
      return message;
    }
  }
  return null;
}
