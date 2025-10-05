import 'dart:async';
import 'dart:convert';

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
    required AgentExecutor executor,
    required String input,
  }) {
    final controller = StreamController<String>();

    Future<void>(() async {
      final steps = <_ToolStep>[];
      final timeline = <_ReasoningItem>[];
      var finalAnswer = '';

      final toolMap = <String, Tool>{
        for (final tool in executor.agent.tools) tool.name: tool,
        ExceptionTool.toolName: ExceptionTool(),
      };

      final maxIterations = executor.maxIterations;
      final maxExecutionTime = executor.maxExecutionTime;
      final stopwatch = Stopwatch()..start();
      final inputs = {'input': input};

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

      Map<String, dynamic> resolveReturnValues(Map<String, dynamic> values) {
        if (executor.agent.returnValues.isEmpty) {
          return values;
        }
        final key = executor.agent.returnValues.first;
        final value = values[key];
        return {key: value};
      }

      Future<void> finishWith(AgentFinish finish) async {
        final resolved = resolveReturnValues(finish.returnValues);
        finalAnswer = resolved.values.first?.toString() ?? '';
        emit();
      }

      try {
        while (true) {
          if (maxIterations != null && iterations >= maxIterations) {
            final stopped = executor.agent.returnStoppedResponse(
              executor.earlyStoppingMethod,
              steps.map((s) => s.toAgentStep()).toList(growable: false),
            );
            await finishWith(stopped);
            break;
          }

          if (maxExecutionTime != null &&
              stopwatch.elapsed >= maxExecutionTime) {
            final stopped = executor.agent.returnStoppedResponse(
              executor.earlyStoppingMethod,
              steps.map((s) => s.toAgentStep()).toList(growable: false),
            );
            await finishWith(stopped);
            break;
          }

          List<BaseAgentAction> actions;
          try {
            actions = await executor.agent.plan(
              AgentPlanInput(
                inputs,
                steps.map((s) => s.toAgentStep()).toList(growable: false),
              ),
            );
          } on OutputParserException catch (e) {
            if (executor.handleParsingErrors == null) rethrow;
            actions = [
              AgentAction(
                id: 'error',
                tool: ExceptionTool.toolName,
                toolInput: executor.handleParsingErrors!(e),
                log: e.toString(),
              ),
            ];
          }

          var finished = false;
          for (final action in actions) {
            if (action is AgentFinish) {
              await finishWith(action);
              finished = true;
              break;
            }

            final agentAction = action as AgentAction;
            final sanitizedLog = _sanitizeAgentLog(agentAction.log);
            if (sanitizedLog.isNotEmpty) {
              timeline.add(
                _ReasoningItem.think(sanitizedLog),
              );
              emit();
            }

            final tool = toolMap[agentAction.tool];
            if (tool == null) {
              throw Exception('Tool ${agentAction.tool} not found');
            }

            final toolStep = _ToolStep(
              action: agentAction,
              status: ToolStepStatus.pending,
            );
            steps.add(toolStep);
            timeline.add(_ReasoningItem.tool(toolStep));
            emit();

            try {
              final toolInput = tool.getInputFromJson(agentAction.toolInput);
              final observation = await tool.invoke(toolInput);
              toolStep.status = ToolStepStatus.success;
              toolStep.output = observation.toString();
              toolStep.observation = observation.toString();
              emit();
            } catch (error) {
              final message = error.toString();
              toolStep.status = ToolStepStatus.failed;
              toolStep.error = message;
              toolStep.observation = message;
              finalAnswer = "Tool ${agentAction.tool} failed: $message";
              emit();
              finished = true;
              break;
            }

            emit();

            if (tool.returnDirect) {
              final finish = AgentFinish(
                returnValues: {
                  executor.agent.returnValues.first: toolStep.output ?? '',
                },
              );
              await finishWith(finish);
              finished = true;
              break;
            }
          }

          if (finished) {
            break;
          }

          iterations += 1;
        }
      } catch (e, stack) {
        if (!controller.isClosed) {
          controller.addError(e, stack);
        }
      } finally {
        if (!controller.isClosed) {
          await controller.close();
        }
      }
    });

    return controller.stream;
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
    final buffer = StringBuffer(
      '<tool-step name=\'${_escapeAttr(action.tool)}\' '
      "status='${status.name}'",
    );
    buffer.write(" input='${_escapeAttr(jsonEncode(action.toolInput))}'");
    if (output != null && output!.isNotEmpty) {
      buffer.write(" output='${_escapeAttr(output!)}'");
    }
    if (error != null && error!.isNotEmpty) {
      buffer.write(" error='${_escapeAttr(error!)}'");
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

String _sanitizeAgentLog(String log) {
  final lines = log
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !_shouldDropLogLine(line))
      .toList(growable: false);

  return lines.join('\n').trim();
}

bool _shouldDropLogLine(String line) {
  final normalized = line.toLowerCase();
  return normalized.contains('invoking:') ||
      normalized.contains('responded:') ||
      normalized.contains('observation:') ||
      normalized.contains('tool call:') ||
      normalized.contains('tool input:') ||
      normalized.contains('tool output:');
}
