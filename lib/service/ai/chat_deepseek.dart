import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:langchain_core/chat_models.dart';
import 'package:langchain_core/language_models.dart';
import 'package:langchain_core/prompts.dart';
import 'package:langchain_core/tools.dart';
import 'package:langchain_openai/langchain_openai.dart';
import 'package:openai_dart/openai_dart.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/utils/ai_reasoning_parser.dart';
import 'package:papertok_reader/utils/log/common.dart';
import 'package:uuid/uuid.dart';

/// Chat model targeting DeepSeek's `/chat/completions` endpoint with proper
/// handling of the `reasoning_content` field that DeepSeek's thinking-mode
/// API requires on assistant messages (V3.1+ deepseek-chat / deepseek-reasoner).
///
/// Differences from [ChatOpenAI] (which the rest of the OpenAI-compatible
/// providers share):
///
/// * On the **request** side, assistant messages whose content contains
///   `<think>…</think>` (produced by Paper Reader's agent runner) are split:
///   the thinking text is sent as `reasoning_content`, while `content` only
///   carries the visible reply + tool-step plaintext. Without this split,
///   DeepSeek returns 400: "The reasoning_content in the thinking mode must
///   be passed back to the API."
/// * On the **response** side, streamed `reasoning_content` deltas are
///   surfaced via `metadata['reasoning_content']` so the existing runner can
///   render them as the `<think>` panel.
///
/// Everything else (tool calling, temperature/top_p, etc.) follows the
/// OpenAI Chat Completions protocol.
class ChatDeepSeek extends BaseChatModel<ChatOpenAIOptions> {
  ChatDeepSeek({
    required String apiKey,
    String? baseUrl,
    Map<String, String>? headers,
    super.defaultOptions = const ChatOpenAIOptions(model: 'deepseek-chat'),
    http.Client? client,
  })  : _apiKey = apiKey,
        _baseUrl = (baseUrl == null || baseUrl.trim().isEmpty)
            ? 'https://api.deepseek.com/v1'
            : _normalizeBaseUrl(baseUrl),
        _headers = headers,
        _httpClient = client ?? http.Client(),
        _ownsClient = client == null;

  final String _apiKey;
  final String _baseUrl;
  final Map<String, String>? _headers;
  final http.Client _httpClient;
  final bool _ownsClient;
  final _uuid = const Uuid();

  bool _closed = false;

  /// Accumulates `reasoning_content` deltas across chunks of the CURRENT
  /// streaming response. Reset at the start of each `stream()` call.
  String _currentReasoningBuffer = '';

  /// Captured reasoning-content sessions from earlier iterations within the
  /// same agent loop. Each entry pairs the tool-call ids that DeepSeek
  /// produced with the chain-of-thought that led to them.
  ///
  /// DeepSeek's V3.1+ thinking-mode API requires `reasoning_content` to be
  /// replayed on the assistant message of a tool-call turn (see project notes
  /// in the class docstring). Since the langchain runner stores the model's
  /// reasoning in a local `thinkingSummary` rather than on the AIChatMessage
  /// content, we capture it here and re-attach it when the next iteration
  /// rebuilds the prompt with scratchpad messages.
  final List<_ReasoningSession> _reasoningSessions = [];

  bool get _aiDebugEnabled {
    try {
      return Prefs().aiDebugLogsEnabled;
    } catch (_) {
      return false;
    }
  }

  void _aiDebug(String message) {
    if (_aiDebugEnabled) {
      AnxLog.info('[AI-DEBUG][deepseek] $message');
    }
  }

  @override
  String get modelType => 'deepseek-chat';

  static String _normalizeBaseUrl(String url) {
    var trimmed = url.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  Uri get _endpoint => Uri.parse('$_baseUrl/chat/completions');

  @override
  Future<List<int>> tokenize(
    PromptValue promptValue, {
    ChatOpenAIOptions? options,
  }) async {
    return utf8.encode(promptValue.toString());
  }

  @override
  Future<ChatResult> invoke(
    PromptValue input, {
    ChatOpenAIOptions? options,
  }) async {
    ChatResult? aggregated;
    await for (final chunk in stream(input, options: options)) {
      aggregated = aggregated == null ? chunk : aggregated.concat(chunk);
    }
    if (aggregated == null) {
      throw StateError('DeepSeek returned no output');
    }
    return aggregated;
  }

  @override
  Stream<ChatResult> stream(
    PromptValue input,
    {ChatOpenAIOptions? options}) async* {
    final effective = options ?? defaultOptions;

    final messages = input.toChatMessages();

    // If the request is a fresh agent loop (no ToolChatMessage / scratchpad
    // tool outputs in the prompt), drop any captured reasoning sessions —
    // they belonged to a previous turn and aren't relevant any more.
    final hasToolOutputs = messages.any((m) => m is ToolChatMessage);
    if (!hasToolOutputs) {
      _reasoningSessions.clear();
    }
    _currentReasoningBuffer = '';

    final body = _buildRequestBody(messages, effective);

    final request = http.Request('POST', _endpoint)
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'Authorization': 'Bearer $_apiKey',
        if (_headers != null) ..._headers,
      })
      ..body = jsonEncode(body);

    _aiDebug(
      'request endpoint=$_endpoint model=${body['model']} messages=${(body['messages'] as List).length} tools=${(body['tools'] as List?)?.length ?? 0}',
    );

    final streamed = await _httpClient.send(request);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final errorBody = await streamed.stream.bytesToString();
      throw StateError(
        'DeepSeek HTTP ${streamed.statusCode}: $errorBody',
      );
    }

    final responseId = _uuid.v4();
    final decoder = _SseDecoder();
    final toolCallChunks = <int, _StreamingToolCall>{};

    await for (final bytes in streamed.stream) {
      if (_closed) break;
      for (final event in decoder.addBytes(bytes)) {
        final data = event.data;
        if (data == null) continue;

        // OpenAI-style stream sends a `[DONE]` sentinel to mark end.
        if (event.isDone) {
          return;
        }

        try {
          final response = CreateChatCompletionStreamResponse.fromJson(data);
          yield _mapStreamResponse(response, responseId, toolCallChunks);
        } catch (e) {
          _aiDebug('failed to parse SSE chunk: $e');
        }
      }
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _reasoningSessions.clear();
    _currentReasoningBuffer = '';
    if (_ownsClient) {
      try {
        _httpClient.close();
      } catch (_) {}
    }
  }

  Map<String, dynamic> _buildRequestBody(
    List<ChatMessage> messages,
    ChatOpenAIOptions options,
  ) {
    final model = options.model ?? defaultOptions.model ?? 'deepseek-chat';
    final mappedMessages = messages
        .map(_mapMessage)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);

    final tools = (options.tools ?? defaultOptions.tools ?? const <ToolSpec>[])
        .map(_mapTool)
        .toList(growable: false);

    final toolChoice = options.toolChoice ?? defaultOptions.toolChoice;
    final temperature = options.temperature ?? defaultOptions.temperature;
    final topP = options.topP ?? defaultOptions.topP;
    final maxTokens = options.maxTokens ?? defaultOptions.maxTokens;
    final frequencyPenalty =
        options.frequencyPenalty ?? defaultOptions.frequencyPenalty;
    final presencePenalty =
        options.presencePenalty ?? defaultOptions.presencePenalty;
    final stop = options.stop ?? defaultOptions.stop;
    final seed = options.seed ?? defaultOptions.seed;

    return <String, dynamic>{
      'model': model,
      'messages': mappedMessages,
      'stream': true,
      'stream_options': {'include_usage': true},
      if (tools.isNotEmpty) 'tools': tools,
      if (toolChoice != null) 'tool_choice': _mapToolChoice(toolChoice),
      if (temperature != null) 'temperature': temperature,
      if (topP != null) 'top_p': topP,
      if (maxTokens != null) 'max_tokens': maxTokens,
      if (frequencyPenalty != null) 'frequency_penalty': frequencyPenalty,
      if (presencePenalty != null) 'presence_penalty': presencePenalty,
      if (stop != null && stop.isNotEmpty) 'stop': stop,
      if (seed != null) 'seed': seed,
    };
  }

  Map<String, dynamic>? _mapMessage(ChatMessage msg) {
    if (msg is SystemChatMessage) {
      return {
        'role': 'system',
        'content': msg.content,
      };
    }

    if (msg is HumanChatMessage) {
      return {
        'role': 'user',
        'content': _mapHumanContent(msg.content),
      };
    }

    if (msg is AIChatMessage) {
      final hasToolCalls = msg.toolCalls.isNotEmpty;
      final fields = extractDeepSeekAssistantFields(msg.content);

      // DeepSeek's V3.1+ thinking-mode rule (per docs):
      //   - assistant messages WITH tool_calls MUST carry reasoning_content
      //     so the model can pick up its own chain-of-thought after the
      //     tool result comes back;
      //   - assistant messages WITHOUT tool_calls MUST NOT carry
      //     reasoning_content — sending it can trigger the inverse 400
      //     error and pollutes context.
      String? reasoningContent;
      if (hasToolCalls) {
        // Prefer reasoning embedded directly in `<think>` (defensive — the
        // runner doesn't currently do this for scratchpad messages).
        reasoningContent = fields.reasoningContent;
        // Otherwise look up the side-channel session we captured during the
        // streaming response that emitted these tool calls.
        if (reasoningContent == null || reasoningContent.isEmpty) {
          final ids = msg.toolCalls.map((t) => t.id).toSet();
          for (final session in _reasoningSessions) {
            if (session.toolCallIds.intersection(ids).isNotEmpty) {
              reasoningContent = session.content;
              break;
            }
          }
        }
      }

      final mapped = <String, dynamic>{
        'role': 'assistant',
        if (fields.content.isNotEmpty) 'content': fields.content,
        if (reasoningContent != null && reasoningContent.isNotEmpty)
          'reasoning_content': reasoningContent,
        if (hasToolCalls)
          'tool_calls': msg.toolCalls
              .map(
                (t) => {
                  'id': t.id,
                  'type': 'function',
                  'function': {
                    'name': t.name,
                    'arguments': t.argumentsRaw.isNotEmpty
                        ? t.argumentsRaw
                        : jsonEncode(t.arguments),
                  },
                },
              )
              .toList(growable: false),
      };
      // OpenAI/DeepSeek require either content or tool_calls to be present;
      // include an empty string when both happen to be missing (rare, but
      // possible for streamed deltas that produced nothing visible).
      if (!mapped.containsKey('content') && !mapped.containsKey('tool_calls')) {
        mapped['content'] = '';
      }
      return mapped;
    }

    if (msg is ToolChatMessage) {
      return {
        'role': 'tool',
        'tool_call_id': msg.toolCallId,
        'content': msg.content,
      };
    }

    return null;
  }

  Object _mapHumanContent(ChatMessageContent content) {
    if (content is ChatMessageContentText) {
      return content.text;
    }
    if (content is ChatMessageContentImage) {
      return [_mapImagePart(content)];
    }
    if (content is ChatMessageContentMultiModal) {
      final parts = <Map<String, dynamic>>[];
      for (final part in content.parts) {
        if (part is ChatMessageContentText) {
          parts.add({'type': 'text', 'text': part.text});
        } else if (part is ChatMessageContentImage) {
          parts.add(_mapImagePart(part));
        }
      }
      return parts;
    }
    return content.toString();
  }

  Map<String, dynamic> _mapImagePart(ChatMessageContentImage img) {
    final data = img.data.trim();
    final isUrl = data.startsWith('http://') || data.startsWith('https://');
    final url = isUrl
        ? data
        : 'data:${img.mimeType ?? 'image/jpeg'};base64,$data';
    return {
      'type': 'image_url',
      'image_url': {
        'url': url,
        'detail': img.detail.name,
      },
    };
  }

  Map<String, dynamic> _mapTool(ToolSpec tool) {
    return {
      'type': 'function',
      'function': {
        'name': tool.name,
        'description': tool.description,
        'parameters': tool.inputJsonSchema,
      },
    };
  }

  Object _mapToolChoice(ChatToolChoice choice) {
    return switch (choice) {
      ChatToolChoiceNone() => 'none',
      ChatToolChoiceAuto() => 'auto',
      ChatToolChoiceRequired() => 'required',
      ChatToolChoiceForced(:final name) => {
          'type': 'function',
          'function': {'name': name},
        },
    };
  }

  ChatResult _mapStreamResponse(
    CreateChatCompletionStreamResponse response,
    String responseId,
    Map<int, _StreamingToolCall> chunks,
  ) {
    final choice = response.choices?.firstOrNull;
    final delta = choice?.delta;

    final reasoning = delta?.reasoningContent;
    final content = delta?.content ?? '';

    // Buffer reasoning_content so we can replay it on the next iteration's
    // assistant message if this response ends up emitting tool_calls.
    if (reasoning != null && reasoning.isNotEmpty) {
      _currentReasoningBuffer += reasoning;
    }

    final emittedToolCalls = <AIChatMessageToolCall>[];
    final rawToolCalls = delta?.toolCalls;
    if (rawToolCalls != null) {
      for (final chunk in rawToolCalls) {
        // Streamed function-call chunks identify themselves by `index` (0, 1,
        // …) in the OpenAI/DeepSeek protocol. Fall back to a synthetic key
        // derived from the existing chunk count if the field is missing.
        final idx = chunk.index ?? chunks.length;
        final acc = chunks.putIfAbsent(idx, () => _StreamingToolCall());
        if ((chunk.id ?? '').isNotEmpty) acc.id = chunk.id!;
        final fn = chunk.function;
        if (fn != null) {
          if ((fn.name ?? '').isNotEmpty) acc.name = fn.name!;
          if ((fn.arguments ?? '').isNotEmpty) acc.argumentsRaw += fn.arguments!;
        }
      }
    }

    // When the choice finishes (or this is the final usage chunk), emit the
    // accumulated tool calls so the agent loop can dispatch them.
    final finishReason = _mapFinishReason(choice?.finishReason);
    if (finishReason == FinishReason.toolCalls && chunks.isNotEmpty) {
      final sorted = chunks.entries.toList(growable: false)
        ..sort((a, b) => a.key.compareTo(b.key));
      for (final entry in sorted) {
        final c = entry.value;
        if (c.id.isEmpty || c.name.isEmpty) continue;
        Map<String, dynamic> args = const {};
        try {
          final decoded = jsonDecode(c.argumentsRaw);
          if (decoded is Map<String, dynamic>) {
            args = decoded;
          } else if (decoded is Map) {
            args = decoded.cast<String, dynamic>();
          }
        } catch (_) {}
        emittedToolCalls.add(
          AIChatMessageToolCall(
            id: c.id,
            name: c.name,
            argumentsRaw: c.argumentsRaw,
            arguments: args,
          ),
        );
      }
      chunks.clear();

      // Capture the reasoning that led to these tool calls so the next
      // iteration's `_mapMessage` can replay it on the same assistant
      // message — DeepSeek requires reasoning_content alongside tool_calls.
      if (_currentReasoningBuffer.isNotEmpty && emittedToolCalls.isNotEmpty) {
        _reasoningSessions.add(
          _ReasoningSession(
            toolCallIds: emittedToolCalls.map((t) => t.id).toSet(),
            content: _currentReasoningBuffer,
          ),
        );
        _currentReasoningBuffer = '';
      }
    } else if (finishReason == FinishReason.stop ||
        finishReason == FinishReason.length) {
      // Final reply (no tool call) — discard accumulated reasoning so a
      // future fresh-turn check doesn't carry stale state.
      _currentReasoningBuffer = '';
    }

    return ChatResult(
      id: response.id ?? responseId,
      output: AIChatMessage(
        content: content,
        toolCalls: emittedToolCalls,
      ),
      finishReason: finishReason,
      metadata: {
        if (response.model != null) 'model': response.model!,
        if (response.systemFingerprint != null)
          'system_fingerprint': response.systemFingerprint!,
        if (reasoning != null && reasoning.isNotEmpty)
          'reasoning_content': reasoning,
      },
      usage: _mapUsage(response.usage),
      streaming: true,
    );
  }

  LanguageModelUsage _mapUsage(CompletionUsage? usage) {
    return LanguageModelUsage(
      promptTokens: usage?.promptTokens,
      responseTokens: usage?.completionTokens,
      totalTokens: usage?.totalTokens,
    );
  }

  FinishReason _mapFinishReason(ChatCompletionFinishReason? reason) {
    return switch (reason) {
      ChatCompletionFinishReason.stop => FinishReason.stop,
      ChatCompletionFinishReason.length => FinishReason.length,
      ChatCompletionFinishReason.toolCalls => FinishReason.toolCalls,
      ChatCompletionFinishReason.contentFilter => FinishReason.contentFilter,
      ChatCompletionFinishReason.functionCall => FinishReason.toolCalls,
      null => FinishReason.unspecified,
    };
  }
}

class _StreamingToolCall {
  String id = '';
  String name = '';
  String argumentsRaw = '';
}

class _ReasoningSession {
  _ReasoningSession({required this.toolCallIds, required this.content});
  final Set<String> toolCallIds;
  final String content;
}

class _SseEvent {
  const _SseEvent({this.data, this.isDone = false});
  final Map<String, dynamic>? data;
  final bool isDone;
}

/// Minimal SSE decoder for OpenAI-style `data: {...}\n\n` streams.
class _SseDecoder {
  final _buffer = StringBuffer();

  Iterable<_SseEvent> addBytes(List<int> bytes) {
    _buffer.write(utf8.decode(bytes, allowMalformed: true));
    final text = _buffer.toString().replaceAll('\r\n', '\n');

    final parts = text.split('\n\n');
    if (parts.length <= 1) {
      return const [];
    }

    _buffer
      ..clear()
      ..write(parts.removeLast());

    final events = <_SseEvent>[];
    for (final part in parts) {
      final lines = part.split('\n');
      final dataLines = <String>[];
      for (final line in lines) {
        if (line.startsWith('data:')) {
          dataLines.add(line.substring('data:'.length).trim());
        }
      }
      if (dataLines.isEmpty) continue;
      final raw = dataLines.join('\n');
      if (raw == '[DONE]') {
        events.add(const _SseEvent(isDone: true));
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          events.add(_SseEvent(data: decoded));
        } else if (decoded is Map) {
          events.add(_SseEvent(data: decoded.cast<String, dynamic>()));
        }
      } catch (_) {
        // Ignore malformed event payloads.
      }
    }
    return events;
  }
}
