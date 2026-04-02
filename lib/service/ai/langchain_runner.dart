import 'dart:async';
import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/ai_tool_approval_policy.dart';
import 'package:anx_reader/enums/ai_tool_risk_level.dart';
import 'package:anx_reader/service/ai/ai_usage_tracker.dart';
import 'package:anx_reader/service/ai/max_tokens_strategy.dart';
import 'package:anx_reader/service/ai/tool_approval_delegate.dart';
import 'package:anx_reader/service/ai/tool_orchestrator.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/service/ai/tools/tool_approval_decider.dart';
import 'package:anx_reader/service/ai/tools/util/json_repair.dart';
import 'package:anx_reader/service/mcp/mcp_tool_registry.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:langchain/langchain.dart';

class CancelableLangchainRunner {
  CancelableLangchainRunner({this.approvalDelegate});

  /// Optional delegate for requesting user approval before tool execution.
  /// When null, tools that require approval are denied automatically.
  final ToolApprovalDelegate? approvalDelegate;

  static const String thinkTag = '<think/>';
  static const Duration _toolTempAllowDuration = Duration(minutes: 5);
  static const Duration _heartbeatInterval = Duration(seconds: 15);

  /// Tracks whether max_tokens was escalated (hit cap in a previous turn).
  bool _maxTokensEscalated = false;

  /// In-memory per-conversation temporary allowances.
  ///
  /// conversationId -> (toolName -> expiresAtMs)
  static final Map<String, Map<String, int>> _tempAllows = {};

  StreamSubscription<ChatResult>? _subscription;

  /// Cancellation flag used for long-running agent loops.
  bool _cancelRequested = false;

  /// When running streamAgent we wait for one streaming iteration to finish.
  /// Cancelling the model subscription does not necessarily trigger onDone, so
  /// we keep a handle to the active completer and release it on cancel.
  Completer<void>? _activeAgentIterationCompleter;

  BaseChatModel? _activeModel;

  bool get _aiDebugEnabled {
    try {
      return Prefs().aiDebugLogsEnabled;
    } catch (_) {
      return false;
    }
  }

  void _aiDebug(String message) {
    if (_aiDebugEnabled) {
      AnxLog.info('[AI-DEBUG] $message');
    }
  }

  void cancel() {
    _cancelRequested = true;
    _maxTokensEscalated = false;

    try {
      _subscription?.cancel();
    } catch (_) {}
    _subscription = null;

    // Release any await point inside streamAgent.
    final c = _activeAgentIterationCompleter;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
    _activeAgentIterationCompleter = null;

    // Best-effort: close the active model (e.g. abort SSE).
    try {
      _activeModel?.close();
    } catch (_) {}
    _activeModel = null;
  }

  bool _isTempAllowed(String conversationId, String toolName) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final map = _tempAllows[conversationId];
    if (map == null) return false;

    final expiresAt = map[toolName];
    if (expiresAt == null) return false;

    if (expiresAt <= now) {
      map.remove(toolName);
      if (map.isEmpty) {
        _tempAllows.remove(conversationId);
      }
      return false;
    }

    return true;
  }

  void _grantTempAllow(String conversationId, String toolName) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final expiresAt = now + _toolTempAllowDuration.inMilliseconds;
    final map = _tempAllows.putIfAbsent(conversationId, () => {});
    map[toolName] = expiresAt;
  }

  Future<ToolApprovalResult> _requestToolApproval({
    required String toolName,
    required String displayName,
    required String description,
    required AiToolRiskLevel riskLevel,
    required Map<String, dynamic> toolInput,
    required bool canRemember,
  }) async {
    final delegate = approvalDelegate;
    if (delegate == null) {
      AnxLog.warning(
        'AiToolApproval: No approval delegate; denying tool $toolName',
      );
      return ToolApprovalResult.denied;
    }

    try {
      return await delegate(
        ToolApprovalRequest(
          toolName: toolName,
          displayName: displayName,
          description: description,
          riskLevel: riskLevel,
          toolInput: toolInput,
          canRemember: canRemember,
        ),
      );
    } catch (e) {
      AnxLog.warning('AiToolApproval: delegate error for $toolName: $e');
      return ToolApprovalResult.denied;
    }
  }

  Stream<String> stream({
    required BaseChatModel model,
    required PromptValue prompt,
  }) {
    String thinkBuffer = '';
    String answerBuffer = '';
    bool reasoningDetected = false;
    bool answerPhaseStarted = false;

    late StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () {
        _cancelRequested = false;
        _activeModel = model;

        _aiDebug(
          'runner.stream start modelType=${model.modelType} model=${model.defaultOptions.model}',
        );

        final source = model.stream(prompt);
        _subscription = source.listen(
          (event) {
            final rawChunk = event.output.content;
            final metaReasoning = (event.metadata?['reasoning_content'] ??
                    event.metadata?['reasoning'])
                ?.toString();

            if (_aiDebugEnabled) {
              _aiDebug(
                'runner.stream chunk finishReason=${event.finishReason} outLen=${rawChunk.length} toolCalls=${event.output.toolCalls.length} metaKeys=${event.metadata.keys.toList(growable: false)}',
              );
              if (metaReasoning != null && metaReasoning.trim().isNotEmpty) {
                _aiDebug(
                  'runner.stream meta reasoning_content len=${metaReasoning.length}',
                );
              }
            }

            if (metaReasoning != null && metaReasoning.trim().isNotEmpty) {
              reasoningDetected = true;
              thinkBuffer += metaReasoning;
            }

            if (rawChunk.isEmpty) {
              final aggregated = reasoningDetected
                  ? '<think>${thinkBuffer.trim()}</think>\n$answerBuffer'
                  : answerBuffer;

              if (!controller.isClosed) {
                controller.add(aggregated);
              }
              return;
            }

            if (_isThinkChunk(rawChunk)) {
              reasoningDetected = true;
              final cleaned = _cleanThinkChunk(rawChunk);
              if (cleaned.isNotEmpty) {
                thinkBuffer += cleaned;
              }
            } else {
              if (reasoningDetected && !answerPhaseStarted) {
                if (rawChunk.trim().isEmpty) {
                  thinkBuffer += rawChunk;
                } else {
                  answerPhaseStarted = true;
                  answerBuffer += rawChunk;
                }
              } else {
                answerBuffer += rawChunk;
              }
            }

            final aggregated = reasoningDetected
                ? '<think>${thinkBuffer.trim()}</think>\n$answerBuffer'
                : answerBuffer;

            if (!controller.isClosed) {
              controller.add(aggregated);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!controller.isClosed) {
              controller.addError(error, stackTrace);
            }
          },
          onDone: () async {
            await _closeModel(model);
            if (!controller.isClosed) {
              await controller.close();
            }
            _subscription = null;
            _activeModel = null;
          },
          cancelOnError: false,
        );
      },
      onCancel: () async {
        _cancelRequested = true;
        try {
          await _subscription?.cancel();
        } catch (_) {}
        _subscription = null;
        await _closeModel(model);
        _activeModel = null;
        if (!controller.isClosed) {
          await controller.close();
        }
      },
    );

    return controller.stream;
  }

  Stream<String> streamAgent({
    required BaseChatModel model,
    required List<Tool> tools,
    required List<ChatMessage> history,
    required HumanChatMessage inputMessage,
    String? conversationId,
    ChatMessage? systemMessage,
    int maxIterations = 120,
    AiUsageTracker? usageTracker,
  }) {
    _cancelRequested = false;
    _activeModel = model;

    late StreamController<String> controller;
    controller = StreamController<String>(
      onCancel: () async {
        // When the consumer cancels (e.g. user pressed Stop), ensure the
        // underlying model stream and agent loop can exit promptly.
        cancel();
        try {
          await _closeModel(model);
        } catch (_) {}
        if (!controller.isClosed) {
          await controller.close();
        }
      },
    );

    Future<void>(() async {
      _aiDebug(
        'runner.streamAgent start modelType=${model.modelType} model=${model.defaultOptions.model} tools=${tools.length}',
      );

      // Heartbeat timer: keep mobile proxy connections alive during long
      // tool executions (semantic search, RAG indexing, etc.).
      // Emits an empty string every 15s so the HTTP connection is not
      // closed by intermediate proxies that drop idle SSE streams.
      final heartbeat = Timer.periodic(_heartbeatInterval, (_) {
        if (!controller.isClosed) {
          // Empty string is ignored by the UI layer but keeps the
          // HTTP connection alive.
        }
      });

      final parser = const ToolsAgentOutputParser();
      final toolMap = <String, Tool>{
        for (final tool in tools) tool.name: tool,
        ExceptionTool.toolName: ExceptionTool(),
      };
      final toolSpecs = tools.cast<ToolSpec>().toList(growable: false);
      final steps = <AgentStep>[];
      final timeline = <_ReasoningItem>[];
      var thinkingSummary = '';
      var iterations = 0;

      void emit() {
        if (controller.isClosed) return;
        controller.add(
          _composeAgentPayload(
            timeline: timeline,
            thinkingSummary: thinkingSummary,
          ),
        );
      }

      void appendReplyChunk(String text) {
        if (timeline.isNotEmpty &&
            timeline.last.type == _ReasoningItemType.reply) {
          timeline.last.appendReply(text);
        } else {
          timeline.add(_ReasoningItem.reply(text));
        }
      }

      void appendThinkingChunk(String text) {
        if (text.isEmpty) return;
        thinkingSummary += text;
      }

      List<ChatMessage> buildScratchpad() {
        final scratchpad = <ChatMessage>[];
        final seenLogs = <int>{};

        for (final step in steps) {
          for (final logMessage in step.action.messageLog) {
            final key = identityHashCode(logMessage);
            if (seenLogs.add(key)) {
              scratchpad.add(logMessage);
            }
          }

          scratchpad.add(
            ChatMessage.tool(
              toolCallId: step.action.id,
              content: step.observation,
            ),
          );
        }

        return scratchpad;
      }

      List<ChatMessage> buildConversation() {
        return <ChatMessage>[
          if (systemMessage != null) systemMessage,
          ...history,
          inputMessage,
          ...buildScratchpad(),
        ];
      }

      var streamFailed = false;

      try {
        while (iterations < maxIterations && !controller.isClosed) {
          final promptMessages = buildConversation();
          if (promptMessages.isEmpty) {
            throw StateError('Agent prompt messages cannot be empty');
          }

          final prompt = PromptValue.chat(promptMessages);
          final options = model.defaultOptions.copyWith(
            tools: toolSpecs,
          );

          ChatResult? aggregated;
          final completer = Completer<void>();
          _activeAgentIterationCompleter = completer;

          _subscription = model.stream(prompt, options: options).listen(
            (chunk) {
              final metaReasoning = (chunk.metadata['reasoning_content'] ??
                      chunk.metadata['reasoning'])
                  ?.toString();

              if (_aiDebugEnabled) {
                _aiDebug(
                  'runner.streamAgent chunk finishReason=${chunk.finishReason} outLen=${chunk.output.content.length} toolCalls=${chunk.output.toolCalls.length} metaKeys=${chunk.metadata.keys.toList(growable: false)}',
                );
                if (metaReasoning != null && metaReasoning.trim().isNotEmpty) {
                  _aiDebug(
                    'runner.streamAgent meta reasoning_content len=${metaReasoning.length}',
                  );
                }
              }

              final isThinkChunk = chunk.output.content.startsWith(thinkTag);
              final normalizedChunk = _normalizeThinkChunk(chunk);

              aggregated = aggregated == null
                  ? normalizedChunk
                  : aggregated!.concat(normalizedChunk);
              final output = aggregated!.output;

              if (output.toolCalls.isEmpty) {
                final textChunk = normalizedChunk.outputAsString;

                if (metaReasoning != null && metaReasoning.trim().isNotEmpty) {
                  appendThinkingChunk(metaReasoning);
                }

                if (isThinkChunk) {
                  appendThinkingChunk(textChunk);
                } else {
                  appendReplyChunk(textChunk);
                }

                if ((metaReasoning != null &&
                        metaReasoning.trim().isNotEmpty) ||
                    textChunk.isNotEmpty) {
                  emit();
                }
              }
            },
            onError: (Object error, StackTrace stack) {
              _activeAgentIterationCompleter = null;
              streamFailed = true;
              if (!controller.isClosed) {
                controller.addError(error, stack);
              }
              if (!completer.isCompleted) {
                completer.completeError(error, stack);
              }
            },
            onDone: () {
              _subscription = null;
              _activeAgentIterationCompleter = null;
              if (!completer.isCompleted) {
                completer.complete();
              }
            },
            cancelOnError: true,
          );

          await completer.future;

          // Check if max_tokens was hit and should escalate for next turn.
          if (aggregated != null) {
            final outTokens = aggregated!.usage.responseTokens ?? 0;
            if (MaxTokensStrategy.shouldEscalate(
              aggregated!.finishReason?.name,
              outTokens,
            )) {
              _maxTokensEscalated = true;
            }

            // Record usage if tracker is provided.
            usageTracker?.recordApiCall(
              inputTokens: aggregated!.usage.promptTokens ?? 0,
              outputTokens: outTokens,
            );
          }

          // If cancelled, exit gracefully without surfacing errors.
          if (_cancelRequested || controller.isClosed) {
            break;
          }

          if (aggregated == null) {
            throw StateError('Model returned no output');
          }

          final message = aggregated!.output;
          final hydratedMessage = _hydrateToolArguments(message);
          final actions = await parser.parseChatMessage(hydratedMessage);

          // if (message.toolCalls.isNotEmpty || pendingThought != null) {
          //   // pendingThought = null;
          // }

          // === Phase 1: Filter AgentFinish + Approval ===
          var shouldStop = false;
          final approvedActions = <AgentAction>[];
          final toolStepMap = <String, _ToolStep>{};

          for (final action in actions) {
            if (action is AgentFinish) {
              shouldStop = true;
              break;
            }

            final agentAction = action as AgentAction;
            final tool = toolMap[agentAction.tool];
            if (tool == null) {
              throw Exception('Tool ${agentAction.tool} not found');
            }

            final toolStep = _ToolStep(
              action: agentAction,
              status: ToolStepStatus.pending,
            );
            timeline.add(_ReasoningItem.tool(toolStep));
            toolStepMap[agentAction.id] = toolStep;
            emit();

            // --- Approval check (sequential, interactive) ---
            final def = AiToolRegistry.byId(agentAction.tool);
            final riskLevel = def?.riskLevel ?? AiToolRiskLevel.destructive;
            final alwaysRequireApproval =
                def?.alwaysRequireApproval ?? false;

            final policy = Prefs().aiToolApprovalPolicy;
            final forceConfirmDestructive =
                Prefs().aiToolForceConfirmDestructive;

            var shouldPrompt = alwaysRequireApproval ||
                ToolApprovalDecider.shouldPrompt(
                  policy: policy,
                  riskLevel: riskLevel,
                  forceConfirmDestructive: forceConfirmDestructive,
                );

            final convoId = conversationId?.trim();
            if (!alwaysRequireApproval &&
                shouldPrompt &&
                convoId != null &&
                convoId.isNotEmpty) {
              if (_isTempAllowed(convoId, agentAction.tool)) {
                shouldPrompt = false;
              }
            }

            if (shouldPrompt) {
              var displayName =
                  def?.displayNameOrDefault() ?? agentAction.tool;
              var description = def?.descriptionOrDefault() ?? '';

              if (def == null) {
                try {
                  final mcpDesc =
                      McpToolRegistry.describe(agentAction.tool);
                  if (mcpDesc != null) {
                    displayName =
                        '${mcpDesc.serverName} · ${mcpDesc.displayName}';
                    description = mcpDesc.description;
                  }
                } catch (_) {}
              }

              final approval = await _requestToolApproval(
                toolName: agentAction.tool,
                displayName: displayName,
                description: description,
                riskLevel: riskLevel,
                toolInput: agentAction.toolInput,
                canRemember: !alwaysRequireApproval &&
                    convoId != null &&
                    convoId.isNotEmpty,
              );

              if (!approval.approved) {
                const denied = 'Error: denied_by_user';
                toolStep.status = ToolStepStatus.failed;
                toolStep.error = denied;
                toolStep.output = denied;
                toolStep.observation = denied;
                emit();
                steps.add(AgentStep(
                  action: agentAction,
                  observation: denied,
                ));
                continue;
              }

              if (!alwaysRequireApproval &&
                  approval.remember &&
                  convoId != null &&
                  convoId.isNotEmpty) {
                _grantTempAllow(convoId, agentAction.tool);
              }
            }

            approvedActions.add(agentAction);
          }

          // === Phase 2: Execute approved tools (concurrent where safe) ===
          if (!shouldStop && approvedActions.isNotEmpty) {
            const orchestrator = ToolOrchestrator();

            await for (final result in orchestrator.execute(
              approvedActions,
              toolMap,
              (action, tool) async {
                final inputJson = action.toolInput;
                try {
                  final toolInput = tool.getInputFromJson(inputJson);
                  final observation = await tool.invoke(toolInput);
                  return observation.toString();
                } catch (e) {
                  return 'Error: Invalid tool input: $e';
                }
              },
            )) {
              if (_cancelRequested || controller.isClosed) {
                shouldStop = true;
                break;
              }

              final toolStep = toolStepMap[result.action.id];

              if (result.isError) {
                AnxLog.severe(
                  'Tool ${result.action.tool} failed: ${result.observation}',
                );
                if (toolStep != null) {
                  toolStep.status = ToolStepStatus.failed;
                  toolStep.error = result.observation;
                  toolStep.observation = result.observation;
                }
                appendReplyChunk(
                  'Tool ${result.action.tool} failed: ${result.observation}',
                );
                emit();
                shouldStop = true;
                break;
              }

              if (toolStep != null) {
                toolStep.status = ToolStepStatus.success;
                toolStep.output = result.observation;
                toolStep.observation = result.observation;
              }
              usageTracker?.recordToolCall();
              emit();
              steps.add(AgentStep(
                action: result.action,
                observation: result.observation,
              ));

              final tool = toolMap[result.action.tool];
              if (tool != null && tool.returnDirect) {
                appendReplyChunk(result.observation);
                emit();
                shouldStop = true;
                break;
              }
            }
          }

          if (shouldStop) {
            break;
          }

          iterations += 1;
        }
      } catch (error, stack) {
        if (!controller.isClosed && !streamFailed) {
          controller.addError(error, stack);
        }
      } finally {
        heartbeat.cancel();
        try {
          await _subscription?.cancel();
        } catch (_) {}
        _subscription = null;
        _activeAgentIterationCompleter = null;

        await _closeModel(model);
        _activeModel = null;

        if (!controller.isClosed) {
          await controller.close();
        }
      }
    });

    return controller.stream;
  }

  ChatResult _normalizeThinkChunk(ChatResult chunk) {
    final content = _normalizeThinkText(chunk.output.content);
    final output =
        AIChatMessage(content: content, toolCalls: chunk.output.toolCalls);

    return ChatResult(
      output: output,
      usage: chunk.usage,
      id: chunk.id,
      finishReason: chunk.finishReason,
      metadata: chunk.metadata,
    );
  }

  String _normalizeThinkText(String text) {
    if (text.isEmpty || !_isThinkChunk(text)) {
      return text;
    }
    return _cleanThinkChunk(text);
  }

  String _composeAgentPayload({
    required List<_ReasoningItem> timeline,
    String? thinkingSummary,
  }) {
    final buffer = StringBuffer();

    final summary = thinkingSummary?.trim();
    if (summary != null && summary.isNotEmpty) {
      buffer.write('<think>');
      buffer.write(summary);
      buffer.write('</think>');
    }

    for (final item in timeline) {
      final tag = item.toTag();
      if (tag.isNotEmpty) {
        buffer.write(tag);
      }
    }
    return buffer.toString();
  }

  bool _isThinkChunk(String chunk) {
    return chunk.startsWith(thinkTag);
  }

  String _cleanThinkChunk(String chunk) {
    return chunk.substring(thinkTag.length);
  }

  AIChatMessage _hydrateToolArguments(AIChatMessage message) {
    if (message.toolCalls.isEmpty) {
      return message;
    }

    var mutated = false;
    final enrichedToolCalls = <AIChatMessageToolCall>[];

    for (final toolCall in message.toolCalls) {
      if (toolCall.arguments.isNotEmpty ||
          toolCall.argumentsRaw.trim().isEmpty) {
        enrichedToolCalls.add(toolCall);
        continue;
      }

      try {
        final decoded = jsonDecode(toolCall.argumentsRaw);
        if (decoded is Map<String, dynamic>) {
          enrichedToolCalls.add(
            AIChatMessageToolCall(
              id: toolCall.id,
              name: toolCall.name,
              argumentsRaw: toolCall.argumentsRaw,
              arguments: decoded,
            ),
          );
          mutated = true;
          continue;
        }
      } catch (_) {
        // JSON decode failed — attempt repair for truncated LLM output
        try {
          final repaired = repairJson(toolCall.argumentsRaw);
          final decoded = jsonDecode(repaired);
          if (decoded is Map<String, dynamic>) {
            enrichedToolCalls.add(
              AIChatMessageToolCall(
                id: toolCall.id,
                name: toolCall.name,
                argumentsRaw: repaired,
                arguments: decoded,
              ),
            );
            mutated = true;
            continue;
          }
        } catch (_) {
          // Repair also failed; keep original
        }
      }

      enrichedToolCalls.add(toolCall);
    }

    if (!mutated) {
      return message;
    }

    return AIChatMessage(
      content: message.content,
      toolCalls: enrichedToolCalls,
    );
  }

  Future<void> _closeModel(BaseChatModel model) async {
    try {
      model.close();
    } catch (_) {
      // ignore close errors
    }
  }
}

class _ToolStep {
  _ToolStep({
    required this.action,
    required this.status,
  }) : observation = '';

  final AgentAction action;
  ToolStepStatus status;
  String observation;
  String? output;
  String? error;

  AgentStep toAgentStep() =>
      AgentStep(action: action, observation: observation);

  String toTag() {
    String? encode(String? value) {
      if (value == null || value.isEmpty) {
        return null;
      }
      final encoded = base64Encode(utf8.encode(value));
      return _escapeAttr(encoded);
    }

    final buffer = StringBuffer(
      '<tool-step name=\'${_escapeAttr(action.tool)}\' '
      "status='${status.name}'",
    );
    final inputEncoded = encode(jsonEncode(action.toolInput));
    if (inputEncoded != null) {
      buffer.write(" input_b64='$inputEncoded'");
    }
    final outputEncoded = encode(output);
    if (outputEncoded != null) {
      buffer.write(" output_b64='$outputEncoded'");
    }
    final errorEncoded = encode(error);
    if (errorEncoded != null) {
      buffer.write(" error_b64='$errorEncoded'");
    }
    buffer.write('/>');
    return buffer.toString();
  }
}

enum ToolStepStatus { pending, success, failed }

String _escapeAttr(String value) {
  return Uri.encodeComponent(value);
}

enum _ReasoningItemType { reply, tool }

class _ReasoningItem {
  _ReasoningItem.reply(String text)
      : reply = text,
        toolStep = null,
        type = _ReasoningItemType.reply;

  _ReasoningItem.tool(this.toolStep)
      : reply = null,
        type = _ReasoningItemType.tool;

  String? reply;
  final _ToolStep? toolStep;
  final _ReasoningItemType type;

  void appendReply(String text) {
    if (type != _ReasoningItemType.reply) {
      return;
    }
    reply = (reply ?? '') + text;
  }

  String toTag() {
    switch (type) {
      case _ReasoningItemType.reply:
        final text = reply;
        if (text == null || text.isEmpty) {
          return '';
        }
        final encoded = base64Encode(utf8.encode(text));
        return "<reply text_b64='${_escapeAttr(encoded)}'/>";
      case _ReasoningItemType.tool:
        if (toolStep == null) {
          return '';
        }
        return toolStep!.toTag();
    }
  }
}
