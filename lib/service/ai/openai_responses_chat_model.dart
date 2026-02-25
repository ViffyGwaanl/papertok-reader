import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:langchain_core/chat_models.dart';
import 'package:langchain_core/language_models.dart';
import 'package:langchain_core/prompts.dart';
import 'package:langchain_core/tools.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:langchain_openai/langchain_openai.dart';

/// A minimal OpenAI Responses API chat model wrapper.
///
/// Design goals:
/// - Works with LangChain agent loop (tool calling).
/// - Streams answer text deltas.
/// - Emits provider-supplied thinking signals via `metadata['reasoning_content']`.
///
/// Policy note:
/// - Thinking is provider-only: if the provider returns no reasoning/thinking
///   content, we show none.
/// - thinkingMode=off only affects request side (we don't request reasoning),
///   but if the provider still returns reasoning metadata, we display it.
class ChatOpenAIResponses extends BaseChatModel<ChatOpenAIOptions> {
  ChatOpenAIResponses({
    required this.baseUrl,
    required this.apiKey,
    this.headers,
    this.usePreviousResponseId = true,
    required super.defaultOptions,
    http.Client? client,
  }) : _client = client;

  final String baseUrl;
  final String apiKey;
  final Map<String, String>? headers;

  /// Whether to use server-side conversation state via `previous_response_id`
  /// for tool-output continuation.
  ///
  /// Some third-party "Responses-compatible" gateways do not support this
  /// parameter.
  final bool usePreviousResponseId;

  http.Client? _client;
  StreamSubscription<List<int>>? _activeSubscription;

  /// Last server-side response id (e.g. `resp_...`).
  ///
  /// Used for tool-call continuations via `previous_response_id` to avoid
  /// manually replaying provider reasoning items.
  String? _lastServerResponseId;

  /// Accumulated reasoning items from previous Responses calls within the same
  /// agent loop.
  ///
  /// OpenAI docs note that for reasoning models, reasoning items returned along
  /// with tool calls must be passed back when you submit tool outputs.
  ///
  /// We keep these items in-memory and replay them into subsequent requests in
  /// the same run.
  final List<Map<String, dynamic>> _replayReasoningItems = [];

  bool get _aiDebugEnabled {
    try {
      return Prefs().aiDebugLogsEnabled;
    } catch (_) {
      return false;
    }
  }

  void _aiDebug(String message) {
    if (_aiDebugEnabled) {
      AnxLog.info('[AI-DEBUG][openai-responses] $message');
    }
  }

  @override
  String get modelType => 'openai-responses';

  Uri _endpoint() {
    var trimmed = baseUrl.trim();
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }

    // baseUrl is expected to be something like https://api.openai.com/v1
    // We always call /responses.
    return Uri.parse('$trimmed/responses');
  }

  http.Client _ensureClient() => _client ??= http.Client();

  @override
  void close() {
    try {
      _activeSubscription?.cancel();
    } catch (_) {}
    _activeSubscription = null;

    try {
      _client?.close();
    } catch (_) {}
    _client = null;
  }

  @override
  Future<List<int>> tokenize(
    PromptValue promptValue, {
    ChatOpenAIOptions? options,
  }) async {
    // Best-effort fallback. We don't rely on exact tokenization for our usage.
    final text = promptValue.toString();
    return utf8.encode(text);
  }

  @override
  Future<ChatResult> invoke(
    PromptValue input, {
    ChatOpenAIOptions? options,
  }) async {
    // Aggregate the streamed chunks.
    final effective = options ?? defaultOptions;
    ChatResult? aggregated;
    await for (final chunk in stream(input, options: effective)) {
      aggregated = aggregated == null ? chunk : aggregated!.concat(chunk);
    }
    if (aggregated == null) {
      throw StateError('OpenAI Responses returned no output');
    }
    return aggregated!;
  }

  @override
  Stream<ChatResult> stream(
    PromptValue input, {
    ChatOpenAIOptions? options,
  }) {
    final effective = options ?? defaultOptions;
    final controller = StreamController<ChatResult>();

    Future<void>(() async {
      final requestBody = _buildRequestBody(input.toChatMessages(), effective);

      if (_aiDebugEnabled) {
        final inputItems = requestBody['input'];
        final inputTypes = inputItems is List
            ? inputItems
                .map((e) => e is Map ? e['type']?.toString() : null)
                .whereType<String>()
                .toList(growable: false)
            : const <String>[];
        _aiDebug(
          'request model=${requestBody['model']} tool_count=${(requestBody['tools'] as List?)?.length ?? 0} tool_choice=${requestBody['tool_choice']} reasoning=${requestBody['reasoning']} inputTypes=$inputTypes',
        );
      }

      final request = http.Request('POST', _endpoint())
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
          if (headers != null) ...headers!,
        })
        ..body = jsonEncode(requestBody);

      final client = _ensureClient();

      try {
        final response = await client.send(request);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final errorBody = await response.stream.bytesToString();
          throw StateError(
            'OpenAI Responses HTTP ${response.statusCode}: $errorBody',
          );
        }

        final decoder = _SseDecoder();
        final localResponseId = _randomId();

        String? accumulatedThinking;
        final pendingCallsByItemId = <String, _PendingFunctionCall>{};
        final seenReasoningItemIds = <String>{};

        String? serverResponseId;
        void maybeCaptureResponseId(Map<String, dynamic> data) {
          try {
            final resp = data['response'];
            if (resp is Map) {
              final id = resp['id']?.toString();
              if (id != null && id.trim().isNotEmpty) {
                serverResponseId = id.trim();
              }
            }
          } catch (_) {
            // ignore
          }
        }

        void emitTextDelta(String delta) {
          if (delta.isEmpty || controller.isClosed) return;
          controller.add(
            ChatResult(
              id: serverResponseId ?? localResponseId,
              output: AIChatMessage(content: delta),
              finishReason: FinishReason.unspecified,
              metadata: const {},
              usage: LanguageModelUsage(),
              streaming: true,
            ),
          );
        }

        void emitThinkingDelta(String text) {
          if (text.trim().isEmpty || controller.isClosed) return;
          accumulatedThinking = (accumulatedThinking ?? '') + text;

          // Emit an empty chunk with metadata so the runner can pick it up.
          controller.add(
            ChatResult(
              id: serverResponseId ?? localResponseId,
              output: AIChatMessage(content: ''),
              finishReason: FinishReason.unspecified,
              metadata: {
                'reasoning_content': text,
              },
              usage: LanguageModelUsage(),
              streaming: true,
            ),
          );
        }

        void captureReasoningItem(Map<String, dynamic> item) {
          // Compatibility mode: some third-party Responses gateways reject
          // `reasoning` items entirely. When we cannot rely on
          // `previous_response_id`, avoid persisting/replaying provider reasoning
          // items; we still surface reasoning deltas to the UI via metadata.
          if (!usePreviousResponseId) {
            return;
          }

          final id = item['id']?.toString();
          if (id != null && id.isNotEmpty && !seenReasoningItemIds.add(id)) {
            return;
          }
          _replayReasoningItems.add(item);
        }

        void emitToolCallsAndFinish(List<_PendingFunctionCall> calls) {
          if (controller.isClosed) return;

          final toolCalls = <AIChatMessageToolCall>[];
          for (final c in calls) {
            final callId = c.callId;
            final name = c.name;
            final argsRaw = c.arguments;
            if (callId.isEmpty || name.isEmpty) continue;

            Map<String, dynamic> parsed = const {};
            try {
              final decoded = jsonDecode(argsRaw);
              if (decoded is Map<String, dynamic>) {
                parsed = decoded;
              } else if (decoded is Map) {
                parsed = decoded.cast<String, dynamic>();
              }
            } catch (_) {}

            toolCalls.add(
              AIChatMessageToolCall(
                id: callId,
                name: name,
                argumentsRaw: argsRaw,
                arguments: parsed,
              ),
            );
          }

          controller.add(
            ChatResult(
              id: serverResponseId ?? localResponseId,
              output: AIChatMessage(content: '', toolCalls: toolCalls),
              finishReason: FinishReason.toolCalls,
              metadata: {
                if (accumulatedThinking != null &&
                    accumulatedThinking!.trim().isNotEmpty)
                  'reasoning_content': accumulatedThinking!,
              },
              usage: LanguageModelUsage(),
              streaming: true,
            ),
          );
        }

        _activeSubscription = response.stream.listen(
          (bytes) {
            for (final event in decoder.addBytes(bytes)) {
              final type = event.type;
              final data = event.data;
              if (type == null || data == null) continue;

              maybeCaptureResponseId(data);

              if (type == 'response.output_text.delta') {
                final delta = data['delta']?.toString() ?? '';
                if (_aiDebugEnabled) {
                  _aiDebug(
                      'event response.output_text.delta len=${delta.length}');
                }
                if (delta.isNotEmpty) emitTextDelta(delta);
                continue;
              }

              // Streaming function calls.
              if (type == 'response.output_item.added' ||
                  type == 'response.output_item.done') {
                final itemRaw = data['item'];
                if (itemRaw is Map) {
                  final item = itemRaw.cast<String, dynamic>();
                  final itemType = item['type']?.toString();

                  if (itemType == 'reasoning') {
                    captureReasoningItem(item);
                    final summary = item['summary'];
                    if (summary is List) {
                      for (final s in summary) {
                        if (s is Map &&
                            s['type']?.toString() == 'summary_text') {
                          final text = s['text']?.toString() ?? '';
                          if (text.isNotEmpty) emitThinkingDelta(text);
                        }
                      }
                    }
                    continue;
                  }

                  if (itemType == 'function_call') {
                    final itemId = item['id']?.toString() ?? '';
                    final callId = item['call_id']?.toString() ?? '';
                    final name = item['name']?.toString() ?? '';
                    final args = item['arguments']?.toString() ?? '';
                    final outputIndex = (data['output_index'] is int)
                        ? data['output_index'] as int
                        : int.tryParse(data['output_index']?.toString() ?? '');

                    if (itemId.isNotEmpty) {
                      final pending = pendingCallsByItemId[itemId] ??
                          _PendingFunctionCall(
                            itemId: itemId,
                            outputIndex: outputIndex,
                            callId: callId,
                            name: name,
                          );
                      pending.callId =
                          pending.callId.isNotEmpty ? pending.callId : callId;
                      pending.name =
                          pending.name.isNotEmpty ? pending.name : name;
                      if (args.isNotEmpty) {
                        pending.arguments = args;
                      }
                      if (outputIndex != null) {
                        pending.outputIndex = outputIndex;
                      }

                      if (type == 'response.output_item.done') {
                        pending.done = true;
                      }

                      pendingCallsByItemId[itemId] = pending;
                    }

                    continue;
                  }

                  if (itemType == 'message') {
                    // Some models may include provider thinking as `reasoning_text`
                    // parts within the message.
                    final content = item['content'];
                    if (content is List) {
                      for (final part in content) {
                        if (part is Map &&
                            part['type']?.toString() == 'reasoning_text') {
                          final text = part['text']?.toString() ?? '';
                          if (text.isNotEmpty) emitThinkingDelta(text);
                        }
                      }
                    }
                  }
                }
              }

              if (type == 'response.function_call_arguments.delta') {
                final itemId = data['item_id']?.toString() ?? '';
                final delta = data['delta']?.toString() ?? '';
                if (_aiDebugEnabled) {
                  _aiDebug(
                    'event response.function_call_arguments.delta item_id=$itemId len=${delta.length}',
                  );
                }
                if (itemId.isEmpty || delta.isEmpty) continue;

                final pending = pendingCallsByItemId[itemId];
                if (pending != null) {
                  pending.arguments += delta;
                }
                continue;
              }

              if (type == 'response.function_call_arguments.done') {
                final itemId = data['item_id']?.toString() ?? '';
                final args = data['arguments']?.toString() ?? '';
                if (_aiDebugEnabled) {
                  _aiDebug(
                    'event response.function_call_arguments.done item_id=$itemId len=${args.length}',
                  );
                }
                if (itemId.isEmpty || args.isEmpty) continue;

                final pending = pendingCallsByItemId[itemId];
                if (pending != null) {
                  pending.arguments = args;
                }
                continue;
              }

              if (type == 'response.completed') {
                // Completed response may also carry reasoning.summary.
                final responseObj = data['response'];
                if (responseObj is Map) {
                  final reasoning = responseObj['reasoning'];
                  if (reasoning is Map) {
                    final summary = reasoning['summary'];
                    if (summary is String && summary.trim().isNotEmpty) {
                      emitThinkingDelta(summary);
                    }
                  }
                }

                final calls = pendingCallsByItemId.values
                    .where((c) => c.callId.isNotEmpty && c.name.isNotEmpty)
                    .toList(growable: false)
                  ..sort((a, b) {
                    final ai = a.outputIndex ?? 999999;
                    final bi = b.outputIndex ?? 999999;
                    return ai.compareTo(bi);
                  });

                if (calls.isNotEmpty) {
                  emitToolCallsAndFinish(calls);
                }

                // Persist the last server response id for tool-call continuation.
                if (serverResponseId != null && serverResponseId!.isNotEmpty) {
                  _lastServerResponseId = serverResponseId;
                }

                if (!controller.isClosed) {
                  unawaited(controller.close());
                }
                return;
              }

              if (type == 'response.failed' || type == 'error') {
                if (!controller.isClosed) {
                  unawaited(controller.close());
                }
                return;
              }
            }
          },
          onError: (Object error, StackTrace stack) {
            if (!controller.isClosed) {
              controller.addError(error, stack);
            }
          },
          onDone: () {
            if (!controller.isClosed) {
              controller.close();
            }
          },
          cancelOnError: true,
        );
      } catch (e, st) {
        if (!controller.isClosed) {
          controller.addError(e, st);
          await controller.close();
        }
      }
    });

    controller.onCancel = () async {
      try {
        await _activeSubscription?.cancel();
      } catch (_) {}
      _activeSubscription = null;
    };

    return controller.stream;
  }

  Map<String, dynamic> _buildRequestBody(
    List<ChatMessage> messages,
    ChatOpenAIOptions options,
  ) {
    final model = options.model ?? defaultOptions.model;

    // If we're starting a fresh run (no tool outputs in the scratchpad), clear
    // replay items and previous-response tracking.
    final hasToolOutputs = messages.any((m) => m is ToolChatMessage);
    if (!hasToolOutputs) {
      _replayReasoningItems.clear();
      _lastServerResponseId = null;
    }

    // Prefer mapping the first system message into `instructions`.
    String? instructions;

    // Tool-call continuation path:
    // If we have a server-side response id, use `previous_response_id` and only
    // submit tool outputs. This avoids manual replay of provider reasoning items
    // (which is brittle and may violate item adjacency constraints).
    if (usePreviousResponseId &&
        hasToolOutputs &&
        _lastServerResponseId != null &&
        _lastServerResponseId!.trim().isNotEmpty) {
      final outputs = <Map<String, dynamic>>[];
      for (final msg in messages) {
        if (msg is ToolChatMessage) {
          final item = _mapChatMessageToResponseInput(msg);
          if (item is Map<String, dynamic>) {
            outputs.add(item);
          }
        }
      }

      final tools = (options.tools ?? const <ToolSpec>[])
          .map(
            (tool) => {
              'type': 'function',
              'name': tool.name,
              'description': tool.description,
              'parameters': tool.inputJsonSchema,
              'strict': tool.strict,
            },
          )
          .toList(growable: false);

      final reasoning = _buildReasoningBlock(options.reasoningEffort);

      return {
        'model': model,
        'previous_response_id': _lastServerResponseId,
        'input': outputs,
        'stream': true,
        if (tools.isNotEmpty) 'tools': tools,
        'tool_choice': _mapToolChoice(options.toolChoice) ?? 'auto',
        if (reasoning != null) 'reasoning': reasoning,
        if (options.temperature != null) 'temperature': options.temperature,
        if (options.topP != null) 'top_p': options.topP,
        if (options.maxTokens != null) 'max_output_tokens': options.maxTokens,
        'parallel_tool_calls': true,
      };
    }

    final inputItems = <Map<String, dynamic>>[];

    for (final msg in messages) {
      if (instructions == null && msg is SystemChatMessage) {
        final text = msg.contentAsString.trim();
        if (text.isNotEmpty) {
          instructions = text;
          continue;
        }
      }

      final item = _mapChatMessageToResponseInput(msg);
      if (item == null) continue;
      if (item is List<Map<String, dynamic>>) {
        inputItems.addAll(item);
      } else {
        inputItems.add(item);
      }
    }

    // Fallback (no previous_response_id available): keep best-effort reasoning
    // replay for tool-call loops. This may be required for some reasoning
    // models, but can be rejected by strict servers.
    var replayInserted = false;
    if (usePreviousResponseId &&
        hasToolOutputs &&
        _replayReasoningItems.isNotEmpty) {
      for (var i = 0; i < inputItems.length; i++) {
        if (inputItems[i]['type']?.toString() == 'function_call') {
          inputItems.insertAll(i, _replayReasoningItems);
          replayInserted = true;
          break;
        }
      }

      if (!replayInserted) {
        _aiDebug('skipping reasoning replay: no function_call found');
      }
    }

    final tools = (options.tools ?? const <ToolSpec>[])
        .map(
          (tool) => {
            'type': 'function',
            'name': tool.name,
            'description': tool.description,
            'parameters': tool.inputJsonSchema,
            'strict': tool.strict,
          },
        )
        .toList(growable: false);

    final reasoning = _buildReasoningBlock(options.reasoningEffort);

    return {
      'model': model,
      if (instructions != null) 'instructions': instructions,
      'input': inputItems,
      'stream': true,
      if (tools.isNotEmpty) 'tools': tools,
      'tool_choice': _mapToolChoice(options.toolChoice) ?? 'auto',
      if (reasoning != null) 'reasoning': reasoning,
      if (options.temperature != null) 'temperature': options.temperature,
      if (options.topP != null) 'top_p': options.topP,
      if (options.maxTokens != null) 'max_output_tokens': options.maxTokens,
      'parallel_tool_calls': true,
    };
  }

  Object? _mapToolChoice(ChatToolChoice? choice) {
    if (choice == null) {
      return null;
    }

    return switch (choice) {
      ChatToolChoiceNone() => 'none',
      ChatToolChoiceAuto() => 'auto',
      ChatToolChoiceRequired() => 'required',
      ChatToolChoiceForced(:final name) => {
          'type': 'function',
          'name': name,
        },
    };
  }

  Map<String, dynamic>? _buildReasoningBlock(
      ChatOpenAIReasoningEffort? effort) {
    if (effort == null) {
      return null;
    }

    // Compatibility mode: some third-party "Responses-compatible" gateways
    // reject the `reasoning` request parameter. Keep this opt-in to the strict
    // OpenAI Responses behavior.
    if (!usePreviousResponseId) {
      return null;
    }

    // Request provider-supplied reasoning summary.
    return {
      'effort': switch (effort) {
        ChatOpenAIReasoningEffort.minimal => 'low',
        ChatOpenAIReasoningEffort.low => 'low',
        ChatOpenAIReasoningEffort.medium => 'medium',
        ChatOpenAIReasoningEffort.high => 'high',
      },
      'summary': 'auto',
    };
  }

  dynamic _mapChatMessageToResponseInput(ChatMessage msg) {
    // Tool output.
    if (msg is ToolChatMessage) {
      return {
        'type': 'function_call_output',
        'call_id': msg.toolCallId,
        'output': msg.content,
      };
    }

    // Assistant tool calls.
    if (msg is AIChatMessage && msg.toolCalls.isNotEmpty) {
      return msg.toolCalls
          .map(
            (t) => {
              'type': 'function_call',
              'call_id': t.id,
              'name': t.name,
              'arguments': t.argumentsRaw,
            },
          )
          .toList(growable: false);
    }

    final role = switch (msg) {
      SystemChatMessage() => 'system',
      HumanChatMessage() => 'user',
      AIChatMessage() => 'assistant',
      CustomChatMessage() => (msg as CustomChatMessage).role,
      _ => 'user',
    };

    final text = msg.contentAsString;
    if (text.trim().isEmpty) {
      return null;
    }

    return {
      'type': 'message',
      'role': role,
      'content': [
        {
          'type': 'input_text',
          'text': text,
        }
      ],
    };
  }

  String _randomId() {
    final ms = DateTime.now().millisecondsSinceEpoch;
    return 'resp_$ms';
  }
}

class _PendingFunctionCall {
  _PendingFunctionCall({
    required this.itemId,
    this.outputIndex,
    required this.callId,
    required this.name,
    this.arguments = '',
    this.done = false,
  });

  final String itemId;
  int? outputIndex;
  String callId;
  String name;
  String arguments;
  bool done;
}

class _SseEvent {
  const _SseEvent({this.type, this.data});

  final String? type;
  final Map<String, dynamic>? data;
}

/// Very small SSE decoder for OpenAI streaming.
///
/// It expects event blocks in the form:
///
/// ```
/// event: xxx\n
/// data: {...}\n
/// \n
/// ```
class _SseDecoder {
  final _buffer = StringBuffer();

  Iterable<_SseEvent> addBytes(List<int> bytes) {
    _buffer.write(utf8.decode(bytes, allowMalformed: true));
    final text = _buffer.toString().replaceAll('\r\n', '\n');

    final parts = text.split('\n\n');
    if (parts.length <= 1) {
      return const [];
    }

    // Keep last partial part.
    _buffer
      ..clear()
      ..write(parts.removeLast());

    final events = <_SseEvent>[];
    for (final part in parts) {
      final lines = part.split('\n');
      String? event;
      final dataLines = <String>[];

      for (final line in lines) {
        if (line.startsWith('event:')) {
          event = line.substring('event:'.length).trim();
        } else if (line.startsWith('data:')) {
          dataLines.add(line.substring('data:'.length).trim());
        }
      }

      if (dataLines.isEmpty) {
        continue;
      }

      final rawData = dataLines.join('\n');
      if (rawData == '[DONE]') {
        events.add(const _SseEvent(type: 'done', data: null));
        continue;
      }

      try {
        final decoded = jsonDecode(rawData);
        if (decoded is Map<String, dynamic>) {
          events.add(
            _SseEvent(
              type: decoded['type']?.toString() ?? event,
              data: decoded,
            ),
          );
        } else if (decoded is Map) {
          final map = decoded.cast<String, dynamic>();
          events.add(
            _SseEvent(
              type: map['type']?.toString() ?? event,
              data: map,
            ),
          );
        }
      } catch (_) {
        // ignore invalid json blocks
      }
    }

    return events;
  }
}
