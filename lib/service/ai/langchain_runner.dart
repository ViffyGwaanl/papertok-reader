import 'dart:async';
import 'dart:convert';

import 'package:anx_reader/utils/log/common.dart';
import 'package:langchain/langchain.dart';

class CancelableLangchainRunner {
  static const String thinkTag = '<think/>';
  StreamSubscription<ChatResult>? _subscription;

  void cancel() {
    _subscription?.cancel();
    _subscription = null;
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
        final source = model.stream(prompt);
        _subscription = source.listen(
          (event) {
            final rawChunk = event.output.content;
            if (rawChunk.isEmpty) {
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
          },
          cancelOnError: false,
        );
      },
      onCancel: () async {
        await _subscription?.cancel();
        _subscription = null;
        await _closeModel(model);
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
    required String input,
    ChatMessage? systemMessage,
    int maxIterations = 120,
  }) {
    final controller = StreamController<String>();

    Future<void>(() async {
      final parser = const ToolsAgentOutputParser();
      final toolMap = <String, Tool>{
        for (final tool in tools) tool.name: tool,
        ExceptionTool.toolName: ExceptionTool(),
      };
      final toolSpecs = tools.cast<ToolSpec>().toList(growable: false);
      final steps = <AgentStep>[];
      final timeline = <_ReasoningItem>[];

      var finalAnswer = '';
      // String? pendingThought;
      var iterations = 0;

      void emit() {
        if (controller.isClosed) return;
        controller.add(
          _composeAgentPayload(
            timeline: timeline,
            answer: finalAnswer,
          ),
        );
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
          ChatMessage.humanText(input),
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
          final options = model.defaultOptions.copyWith(tools: toolSpecs);

          ChatResult? aggregated;

          final completer = Completer<void>();
          _subscription = model.stream(prompt, options: options).listen(
            (chunk) {
              final normalizedChunk = _normalizeThinkChunk(chunk);

              aggregated = aggregated == null
                  ? normalizedChunk
                  : aggregated!.concat(normalizedChunk);
              final output = aggregated!.output;

              if (output.toolCalls.isNotEmpty ||
                  _isThinkChunk(chunk.outputAsString)) {
                final thought = normalizedChunk.outputAsString;
                if (thought.isNotEmpty) {
                  timeline.add(_ReasoningItem.think(thought));
                  emit();
                }
              } else {
                finalAnswer += chunk.outputAsString;
                emit();
              }
            },
            onError: (Object error, StackTrace stack) {
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
              if (!completer.isCompleted) {
                completer.complete();
              }
            },
            cancelOnError: true,
          );

          await completer.future;

          if (aggregated == null) {
            throw StateError('Model returned no output');
          }

          final message = aggregated!.output;
          final actions = await parser.parseChatMessage(message);

          // if (message.toolCalls.isNotEmpty || pendingThought != null) {
          //   // pendingThought = null;
          // }

          var shouldStop = false;
          for (final action in actions) {
            if (action is AgentFinish) {
              final resolved = action.returnValues;
              finalAnswer = resolved.values.first?.toString() ?? '';
              emit();
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
            emit();

            try {
              final inputJson = agentAction.toolInput;
              final toolInput = tool.getInputFromJson(inputJson);
              final observation = await tool.invoke(toolInput);
              final observationText = observation.toString();
              toolStep.status = ToolStepStatus.success;
              toolStep.output = observationText;
              toolStep.observation = observationText;
              emit();

              steps.add(
                AgentStep(
                  action: agentAction,
                  observation: observationText,
                ),
              );
            } catch (error) {
              AnxLog.severe(
                  'Tool ${agentAction.tool} execution failed: $error');
              final message = error.toString();
              toolStep.status = ToolStepStatus.failed;
              toolStep.error = message;
              toolStep.observation = message;
              finalAnswer = 'Tool ${agentAction.tool} failed: $message';
              emit();
              shouldStop = true;
              break;
            }

            if (tool.returnDirect) {
              finalAnswer = toolStep.output ?? '';
              emit();
              shouldStop = true;
              break;
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
        await _subscription?.cancel();
        _subscription = null;
        await _closeModel(model);
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
    required String answer,
  }) {
    final buffer = StringBuffer();
    buffer.write('<think>');
    for (final item in timeline) {
      buffer.write(item.toTag());
    }
    buffer.writeln('</think>');

    if (answer.trim().isNotEmpty) {
      buffer.writeln(answer.trim());
    }

    return buffer.toString().trim();
  }

  bool _isThinkChunk(String chunk) {
    return chunk.startsWith(thinkTag);
  }

  String _cleanThinkChunk(String chunk) {
    return chunk.substring(thinkTag.length);
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

class _ReasoningItem {
  _ReasoningItem.think(this.thought)
      : toolStep = null,
        isThink = true;

  _ReasoningItem.tool(this.toolStep)
      : thought = null,
        isThink = false;

  final String? thought;
  final _ToolStep? toolStep;
  final bool isThink;

  String toTag() {
    if (isThink && thought != null) {
      return "<think-block text='${_escapeAttr(thought!)}'/>";
    }
    if (toolStep != null) {
      return toolStep!.toTag();
    }
    return '';
  }
}
