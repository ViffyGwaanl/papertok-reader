import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/models/ai_agent_governance.dart';
import 'package:papertok_reader/service/ai/agent_tool_call_event.dart';
import 'package:papertok_reader/service/ai/langchain_ai_config.dart';
import 'package:papertok_reader/service/ai/langchain_registry.dart';
import 'package:papertok_reader/service/ai/langchain_runner.dart';
import 'package:papertok_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:papertok_reader/utils/log/common.dart';
import 'package:langchain_core/chat_models.dart';

typedef SubAgentRunExecutor = Future<String> Function(SubAgentRunPlan plan);

enum SubAgentRunStatus {
  pendingInit('pendingInit'),
  running('running'),
  waitingInput('waiting_input'),
  interrupted('interrupted'),
  completed('completed'),
  errored('errored'),
  shutdown('shutdown'),
  notFound('notFound');

  const SubAgentRunStatus(this.asString);

  final String asString;
}

@immutable
class SubAgentRunPlan {
  const SubAgentRunPlan({
    required this.agentRunId,
    required this.agentType,
    required this.task,
    required this.status,
    required this.maxSteps,
    required this.agentScene,
    required this.allowedToolIds,
    required this.startedAt,
    this.parentRunId,
    this.toolCallObserver,
  });

  final String agentRunId;
  final String? parentRunId;
  final String agentType;
  final String task;
  final SubAgentRunStatus status;
  final int maxSteps;
  final AiAgentScene agentScene;
  final List<String> allowedToolIds;
  final DateTime startedAt;
  final AgentToolCallObserver? toolCallObserver;

  Map<String, dynamic> toJson() => {
        'agentRunId': agentRunId,
        if (parentRunId != null) 'parentRunId': parentRunId,
        'agentType': agentType,
        'task': task,
        'status': status.asString,
        'maxSteps': maxSteps,
        'agentScene': agentScene.asString,
        'allowedToolIds': allowedToolIds,
        'startedAt': startedAt.toIso8601String(),
      };
}

@immutable
class SubAgentRunResult {
  const SubAgentRunResult({
    required this.agentRunId,
    required this.agentType,
    required this.task,
    required this.status,
    required this.maxSteps,
    required this.agentScene,
    required this.allowedToolIds,
    required this.startedAt,
    this.parentRunId,
    this.finishedAt,
    this.result,
    this.error,
  });

  final String agentRunId;
  final String? parentRunId;
  final String agentType;
  final String task;
  final SubAgentRunStatus status;
  final int maxSteps;
  final AiAgentScene agentScene;
  final List<String> allowedToolIds;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String? result;
  final String? error;

  Map<String, dynamic> toJson() => {
        'agentRunId': agentRunId,
        if (parentRunId != null) 'parentRunId': parentRunId,
        'agentType': agentType,
        'task': task,
        'status': status.asString,
        'maxSteps': maxSteps,
        'agentScene': agentScene.asString,
        'allowedToolIds': allowedToolIds,
        'startedAt': startedAt.toIso8601String(),
        if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
        if (result != null) 'result': result,
        if (error != null) 'error': error,
      };
}

/// Runs a lightweight sub-agent with isolated context and restricted tools.
///
/// Sub-agents cannot spawn further sub-agents (prevents infinite recursion)
/// and have no UI approval delegate (auto-approve read-only tools).
class SubAgentRunner {
  const SubAgentRunner._();

  /// Tool IDs available to each agent type.
  static const _agentToolSets = <String, List<String>>{
    'research': [
      'web_search',
      'fetch_url',
      'book_content_search',
      'semantic_search_current_book',
      'semantic_search_library',
      'current_reading_metadata',
    ],
    'summarize': [
      'current_chapter_content',
      'chapter_content_by_href',
      'current_book_toc',
      'current_reading_metadata',
      'current_book_fulltext',
    ],
    'verify': [
      'book_content_search',
      'semantic_search_current_book',
      'semantic_search_library',
      'chapter_content_by_href',
      'notes_search',
      'fetch_url',
    ],
  };

  /// Runs a sub-agent with the given [task] and returns its final output text.
  ///
  /// [agentType]: one of 'research', 'summarize', 'verify'.
  /// [maxSteps]: maximum tool-use iterations (1-15, default 8).
  /// [toolContext]: shared tool context from the parent agent.
  static Future<String> run({
    required String task,
    required String agentType,
    required AiToolContext toolContext,
    int maxSteps = 8,
    SubAgentGovernancePolicy governancePolicy =
        const SubAgentGovernancePolicy(),
    AiToolPermissionMatrix permissionMatrix =
        AiToolPermissionMatrix.defaultMatrix,
    AiAgentScene agentScene = AiAgentScene.reading,
  }) async {
    final tracked = await runTracked(
      task: task,
      agentType: agentType,
      toolContext: toolContext,
      maxSteps: maxSteps,
      governancePolicy: governancePolicy,
      permissionMatrix: permissionMatrix,
      agentScene: agentScene,
    );

    final result = tracked.result?.trim();
    if (result != null && result.isNotEmpty) return result;
    if (tracked.error != null) return 'Sub-agent error: ${tracked.error}';
    return 'Sub-agent produced no output.';
  }

  static Future<SubAgentRunResult> runTracked({
    required String task,
    required String agentType,
    AiToolContext? toolContext,
    int maxSteps = 8,
    SubAgentGovernancePolicy governancePolicy =
        const SubAgentGovernancePolicy(),
    AiToolPermissionMatrix permissionMatrix =
        AiToolPermissionMatrix.defaultMatrix,
    AiAgentScene agentScene = AiAgentScene.reading,
    String? agentRunId,
    String? parentRunId,
    DateTime Function()? clock,
    SubAgentRunExecutor? executor,
    AgentToolCallObserver? toolCallObserver,
  }) async {
    final effectiveClock = clock ?? DateTime.now;
    final startedAt = effectiveClock();
    final type = _normalizedAgentType(agentType);
    final effectiveMaxSteps = maxSteps.clamp(1, 15).toInt();
    final toolIds = allowedToolIdsForAgent(
      agentType: type,
      governancePolicy: governancePolicy,
      permissionMatrix: permissionMatrix,
      agentScene: agentScene,
    );
    final runId = _normalizedRunId(agentRunId) ??
        _agentRunIdFor(agentType: type, startedAt: startedAt);
    final normalizedParentRunId = _normalizedRunId(parentRunId);
    final effectiveToolCallObserver = toolCallObserver == null
        ? null
        : (AgentToolCallEvent event) => toolCallObserver(event.copyWith(
              agentRunId: runId,
              parentRunId: normalizedParentRunId,
              roleId: type,
            ));
    final plan = SubAgentRunPlan(
      agentRunId: runId,
      parentRunId: normalizedParentRunId,
      agentType: type,
      task: task,
      status: SubAgentRunStatus.running,
      maxSteps: effectiveMaxSteps,
      agentScene: agentScene,
      allowedToolIds: toolIds,
      startedAt: startedAt,
      toolCallObserver: effectiveToolCallObserver,
    );

    AnxLog.info('SubAgent: starting run=$runId type=$type '
        'task="${_truncate(task, 80)}" maxSteps=$effectiveMaxSteps '
        'tools=${toolIds.length}');

    try {
      final output = executor != null
          ? await executor(plan)
          : await _executeRun(
              plan: plan,
              toolContext: toolContext ??
                  (throw StateError(
                    'AiToolContext is required for live sub-agent runs.',
                  )),
              permissionMatrix: permissionMatrix,
              toolCallObserver: effectiveToolCallObserver,
            );
      final result = output.trim();
      AnxLog.info('SubAgent: completed run=$runId type=$type '
          'resultLen=${result.length}');
      return SubAgentRunResult(
        agentRunId: runId,
        parentRunId: normalizedParentRunId,
        agentType: type,
        task: task,
        status: SubAgentRunStatus.completed,
        maxSteps: effectiveMaxSteps,
        agentScene: agentScene,
        allowedToolIds: toolIds,
        startedAt: startedAt,
        finishedAt: effectiveClock(),
        result: result.isEmpty ? 'Sub-agent produced no output.' : result,
      );
    } catch (e) {
      AnxLog.warning('SubAgent: execution error run=$runId type=$type: $e');
      return SubAgentRunResult(
        agentRunId: runId,
        parentRunId: normalizedParentRunId,
        agentType: type,
        task: task,
        status: SubAgentRunStatus.errored,
        maxSteps: effectiveMaxSteps,
        agentScene: agentScene,
        allowedToolIds: toolIds,
        startedAt: startedAt,
        finishedAt: effectiveClock(),
        error: e.toString(),
      );
    }
  }

  static Future<String> _executeRun({
    required SubAgentRunPlan plan,
    required AiToolContext toolContext,
    required AiToolPermissionMatrix permissionMatrix,
    AgentToolCallObserver? toolCallObserver,
  }) async {
    // Build model from current config (same provider as parent).
    final serviceId = Prefs().selectedAiService;
    final config = Prefs().getAiConfig(serviceId);
    final providerMeta = Prefs().getAiProviderMeta(serviceId);
    final registryId =
        LangchainAiConfig.registryIdentifierForProvider(providerMeta);
    final langConfig = LangchainAiConfig.fromPrefs(registryId, config);

    final registry = LangchainAiRegistry(toolContext.ref);
    final pipeline = registry.resolve(langConfig);

    // Build restricted tool set (no spawn_sub_agent to prevent recursion).
    final tools = AiToolRegistry.buildTools(toolContext, plan.allowedToolIds);

    // Create isolated runner with no approval delegate.
    final runner = CancelableLangchainRunner();

    final systemPrompt = ChatMessage.system(
      'You are a focused sub-agent of type "${plan.agentType}". '
      'Your sole task: ${plan.task}\n\n'
      'Rules:\n'
      '- Complete the task efficiently using available tools.\n'
      '- Return a clear, structured answer.\n'
      '- Do NOT ask the user questions — gather info via tools.\n'
      '- Do NOT create/modify user data (highlights, notes, etc.).\n',
    );

    // Accumulate all stream output.
    final buffer = StringBuffer();
    final stream = runner.streamAgent(
      model: pipeline.model,
      tools: tools,
      history: const [],
      inputMessage: ChatMessage.humanText(plan.task) as HumanChatMessage,
      systemMessage: systemPrompt,
      maxIterations: plan.maxSteps,
      toolPermissionMatrix: permissionMatrix,
      toolCallObserver: toolCallObserver,
    );

    try {
      await for (final chunk in stream) {
        buffer.clear();
        buffer.write(chunk);
      }
    } catch (e) {
      AnxLog.warning('SubAgent: execution error: $e');
      if (buffer.isEmpty) {
        return 'Sub-agent error: $e';
      }
    }

    final result = buffer.toString().trim();
    return result.isEmpty ? 'Sub-agent produced no output.' : result;
  }

  static List<String> allowedToolIdsForAgent({
    required String agentType,
    SubAgentGovernancePolicy governancePolicy =
        const SubAgentGovernancePolicy(),
    AiToolPermissionMatrix permissionMatrix =
        AiToolPermissionMatrix.defaultMatrix,
    AiAgentScene agentScene = AiAgentScene.reading,
  }) {
    final type = _normalizedAgentType(agentType);
    return _agentToolSets[type]!
        .where(governancePolicy.canUseToolInsideSubAgent)
        .where((toolId) =>
            permissionMatrix.isAllowed(scene: agentScene, toolId: toolId))
        .where((toolId) {
      final rule = permissionMatrix.ruleFor(toolId);
      return rule != null && rule.readOnly && !rule.requiresApproval;
    }).toList(growable: false);
  }

  static String _normalizedAgentType(String agentType) =>
      _agentToolSets.containsKey(agentType) ? agentType : 'research';

  static String? _normalizedRunId(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String _agentRunIdFor({
    required String agentType,
    required DateTime startedAt,
  }) =>
      'subagent-$agentType-${startedAt.microsecondsSinceEpoch}';

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}...';
}
