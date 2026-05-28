import 'package:papertok_reader/models/ai_agent_governance.dart';
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
  SpawnSubAgentTool(this._toolContext)
      : super(
          name: 'spawn_sub_agent',
          description:
              'Spawn a focused sub-agent to perform a specific sub-task '
              'independently. The sub-agent runs with its own context and '
              'restricted tools, returning its findings as text. '
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

  @override
  SpawnSubAgentInput parseInput(Map<String, dynamic> json) =>
      SpawnSubAgentInput.fromJson(json);

  @override
  Future<Map<String, dynamic>> run(SpawnSubAgentInput input) async {
    final result = await SubAgentRunner.run(
      task: input.task,
      agentType: input.agentType,
      toolContext: _toolContext,
      maxSteps: input.maxSteps,
      permissionMatrix: _toolContext.toolPermissionMatrix ??
          AiToolPermissionMatrix.defaultMatrix,
      agentScene: _toolContext.agentScene,
    );

    return {
      'agentType': input.agentType,
      'task': input.task,
      'result': result,
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
