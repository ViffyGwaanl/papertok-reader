import 'dart:convert';

import 'package:papertok_reader/models/ai_agent_governance.dart';
import 'package:papertok_reader/service/ai/agent_run_graph_store.dart';
import 'package:papertok_reader/service/ai/agent_tool_call_event.dart';
import 'package:papertok_reader/service/ai/sub_agent_runner.dart';
import 'package:papertok_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:papertok_reader/service/ai/tools/input/spawn_sub_agent_input.dart';

import 'base_tool.dart';

/// Tool that spawns a lightweight sub-agent to handle focused tasks.
///
/// Sub-agents run in isolated contexts with restricted tool sets and cannot
/// spawn further sub-agents (preventing infinite recursion).
class SpawnSubAgentTool
    extends RepositoryTool<SpawnSubAgentInput, Map<String, dynamic>> {
  SpawnSubAgentTool(
    this._toolContext, {
    AgentRunGraphStore? graphStore,
    SubAgentRunExecutor? executor,
    String? agentRunId,
    DateTime Function()? clock,
  })  : _graphStore = graphStore ?? AgentRunGraphStore(),
        _executor = executor,
        _agentRunId = agentRunId,
        _clock = clock,
        super(
          name: 'spawn_sub_agent',
          description:
              'Spawn a focused sub-agent to perform a specific sub-task '
              'independently. The sub-agent runs with its own context and '
              'restricted tools, returning a traceable run id, status, '
              'allowed tools, and its findings as text. '
              'Use this to delegate research, summarization, or verification '
              'tasks while you continue reasoning about the main problem. '
              'Agent types: "research" (web search, book search), '
              '"summarize" (chapter content, TOC), '
              '"verify" (search, notes, cross-reference).',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'task': {
                'type': 'string',
                'description':
                    'Required. Clear description of what the sub-agent '
                        'should accomplish.',
              },
              'agentType': {
                'type': 'string',
                'description':
                    'Required. Type of sub-agent: "research", "summarize", '
                        'or "verify".',
                'enum': ['research', 'summarize', 'verify'],
              },
              'maxSteps': {
                'type': 'integer',
                'description':
                    'Optional. Maximum tool-use iterations (1-15). Default 8.',
              },
            },
            'required': ['task', 'agentType'],
          },
          timeout: const Duration(minutes: 3),
        );

  final AiToolContext _toolContext;
  final AgentRunGraphStore _graphStore;
  final SubAgentRunExecutor? _executor;
  final String? _agentRunId;
  final DateTime Function()? _clock;

  @override
  SpawnSubAgentInput parseInput(Map<String, dynamic> json) =>
      SpawnSubAgentInput.fromJson(json);

  @override
  Future<Map<String, dynamic>> run(SpawnSubAgentInput input) async {
    final result = await SubAgentRunner.runTracked(
      task: input.task,
      agentType: input.agentType,
      toolContext: _toolContext,
      maxSteps: input.maxSteps,
      permissionMatrix: _toolContext.toolPermissionMatrix ??
          AiToolPermissionMatrix.defaultMatrix,
      agentScene: _toolContext.agentScene,
      parentRunId: _toolContext.conversationId,
      agentRunId: _agentRunId,
      clock: _clock,
      executor: _executor,
      toolCallObserver: (event) => _recordToolCallEvent(input, event),
    );

    await _graphStore.upsertFromSubAgentResult(
      result,
      source: 'spawn_sub_agent',
      profile: result.agentType,
      roleId: result.agentType,
      nickname: _agentNickname(result.agentType),
    );

    return result.toJson();
  }

  Future<void> _recordToolCallEvent(
    SpawnSubAgentInput input,
    AgentToolCallEvent event,
  ) async {
    final runId = (event.agentRunId ?? _agentRunId ?? '').trim();
    final parentRunId =
        (event.parentRunId ?? _toolContext.conversationId)?.trim();
    if (runId.isEmpty) return;
    final roleId = (event.roleId ?? input.agentType).trim();
    await _graphStore.upsertEvent(AgentRunEvent(
      eventId: '$runId:tool:${agentToolCallEventIdSegment(event)}',
      runId: runId,
      parentRunId:
          parentRunId == null || parentRunId.isEmpty ? null : parentRunId,
      type: AgentRunEventType.toolCall,
      createdAt: _clock?.call() ?? DateTime.now(),
      status: _subAgentStatusForToolCall(event.status),
      roleId: roleId,
      nickname: _agentNickname(roleId),
      toolId: event.toolId,
      query: _queryFromToolInput(event.input),
      result: event.output,
      error: event.error,
      resultCount: event.resultCount ?? 0,
      roleIds: [roleId],
    ));
  }

  static SubAgentRunStatus _subAgentStatusForToolCall(
    AgentToolCallEventStatus status,
  ) {
    return switch (status) {
      AgentToolCallEventStatus.running => SubAgentRunStatus.running,
      AgentToolCallEventStatus.completed => SubAgentRunStatus.completed,
      AgentToolCallEventStatus.errored => SubAgentRunStatus.errored,
    };
  }

  static String? _queryFromToolInput(Map<String, dynamic> input) {
    const preferredKeys = ['query', 'q', 'keyword', 'text'];
    for (final key in preferredKeys) {
      final value = input[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    if (input.isEmpty) return null;
    return jsonEncode(input);
  }

  static String _agentNickname(String agentType) {
    return switch (agentType) {
      'research' => 'Research sub-agent',
      'summarize' => 'Summarize sub-agent',
      'verify' => 'Verify sub-agent',
      _ => 'Sub-agent',
    };
  }
}

AiToolDefinition createSpawnSubAgentToolDefinition() {
  return AiToolDefinition(
    id: 'spawn_sub_agent',
    displayNameBuilder: (_) => 'Spawn Sub-Agent',
    descriptionBuilder: (_) =>
        'Delegate focused sub-tasks to an independent lightweight agent',
    build: (context) => SpawnSubAgentTool(context).tool,
  );
}
