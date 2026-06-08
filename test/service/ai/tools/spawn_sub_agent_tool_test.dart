import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_agent_governance.dart';
import 'package:papertok_reader/service/ai/agent_run_graph_store.dart';
import 'package:papertok_reader/service/ai/agent_tool_call_event.dart';
import 'package:papertok_reader/service/ai/sub_agent_runner.dart';
import 'package:papertok_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:papertok_reader/service/ai/tools/input/spawn_sub_agent_input.dart';
import 'package:papertok_reader/service/ai/tools/spawn_sub_agent_tool.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('spawn-sub-agent-test-');
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('spawn sub-agent writes a traceable graph edge', () async {
    final startedAt = DateTime.utc(2026, 6, 4, 14);
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'chat-parent-run',
      source: 'ai_chat',
      profile: 'parent',
      roleId: 'parent',
      nickname: 'AI Chat',
      status: SubAgentRunStatus.running,
      task: 'Parent chat turn.',
      startedAt: startedAt,
    ));
    final toolContext = AiToolContext(
      ref: container.read(_refProvider),
      conversationId: 'chat-parent-run',
      agentSceneOverride: AiAgentScene.seminar,
    );
    final tool = SpawnSubAgentTool(
      toolContext,
      graphStore: graphStore,
      agentRunId: 'spawned-run-1',
      clock: () => startedAt,
      executor: (plan) async {
        expect(plan.parentRunId, 'chat-parent-run');
        expect(plan.agentRunId, 'spawned-run-1');
        return 'Sub-agent evidence summary.';
      },
    );

    final result = await tool.run(const SpawnSubAgentInput(
      task: 'Collect evidence.',
      agentType: 'research',
      maxSteps: 4,
    ));

    expect(result['agentRunId'], 'spawned-run-1');
    expect(result['parentRunId'], 'chat-parent-run');
    expect(result['status'], 'completed');

    final children = await graphStore.listChildren('chat-parent-run');
    expect(children, hasLength(1));
    expect(children.single.run.runId, 'spawned-run-1');
    expect(children.single.run.source, 'spawn_sub_agent');
    expect(children.single.run.profile, 'research');
    expect(children.single.run.roleId, 'research');
    expect(children.single.run.nickname, 'Research sub-agent');
    expect(children.single.run.result, 'Sub-agent evidence summary.');
    expect(children.single.edge.status, AgentRunEdgeStatus.closed);
  });

  test('spawn sub-agent writes child tool call events to graph', () async {
    final startedAt = DateTime.utc(2026, 6, 5, 15);
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'chat-parent-run',
      source: 'ai_chat',
      profile: 'parent',
      roleId: 'parent',
      nickname: 'AI Chat',
      status: SubAgentRunStatus.running,
      task: 'Parent chat turn.',
      startedAt: startedAt,
    ));
    final toolContext = AiToolContext(
      ref: container.read(_refProvider),
      conversationId: 'chat-parent-run',
      agentSceneOverride: AiAgentScene.seminar,
    );
    final tool = SpawnSubAgentTool(
      toolContext,
      graphStore: graphStore,
      agentRunId: 'spawned-run-tools',
      clock: () => startedAt,
      executor: (plan) async {
        await plan.toolCallObserver?.call(const AgentToolCallEvent(
          callId: 'call-search-1',
          toolId: 'semantic_search_current_book',
          input: {'query': 'agency'},
          status: AgentToolCallEventStatus.running,
        ));
        await plan.toolCallObserver?.call(const AgentToolCallEvent(
          callId: 'call-search-1',
          toolId: 'semantic_search_current_book',
          input: {'query': 'agency'},
          status: AgentToolCallEventStatus.completed,
          output: 'Found 2 current-book matches.',
          resultCount: 2,
          durationMs: 12,
        ));
        return 'Sub-agent evidence summary.';
      },
    );

    await tool.run(const SpawnSubAgentInput(
      task: 'Search the current book.',
      agentType: 'research',
      maxSteps: 4,
    ));

    final events = await graphStore.listEvents('spawned-run-tools');
    final toolCall = events.singleWhere(
      (event) => event.type == AgentRunEventType.toolCall,
    );
    expect(toolCall.eventId, 'spawned-run-tools:tool:call-search-1');
    expect(toolCall.runId, 'spawned-run-tools');
    expect(toolCall.parentRunId, 'chat-parent-run');
    expect(toolCall.status, SubAgentRunStatus.completed);
    expect(toolCall.toolId, 'semantic_search_current_book');
    expect(toolCall.query, 'agency');
    expect(toolCall.result, 'Found 2 current-book matches.');
    expect(toolCall.resultCount, 2);
    expect(toolCall.roleIds, ['research']);
  });

  test('spawn sub-agent keeps distinct tool calls without provider call ids',
      () async {
    final startedAt = DateTime.utc(2026, 6, 5, 16);
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'chat-parent-run',
      source: 'ai_chat',
      profile: 'parent',
      roleId: 'parent',
      nickname: 'AI Chat',
      status: SubAgentRunStatus.running,
      task: 'Parent chat turn.',
      startedAt: startedAt,
    ));
    final toolContext = AiToolContext(
      ref: container.read(_refProvider),
      conversationId: 'chat-parent-run',
      agentSceneOverride: AiAgentScene.seminar,
    );
    final tool = SpawnSubAgentTool(
      toolContext,
      graphStore: graphStore,
      agentRunId: 'spawned-run-empty-call-id',
      clock: () => startedAt,
      executor: (plan) async {
        await plan.toolCallObserver?.call(const AgentToolCallEvent(
          callId: '',
          toolId: 'semantic_search_current_book',
          input: {'query': 'first claim'},
          status: AgentToolCallEventStatus.completed,
          output: 'Found first current-book match.',
          resultCount: 1,
        ));
        await plan.toolCallObserver?.call(const AgentToolCallEvent(
          callId: '',
          toolId: 'semantic_search_current_book',
          input: {'query': 'second claim'},
          status: AgentToolCallEventStatus.completed,
          output: 'Found second current-book match.',
          resultCount: 1,
        ));
        return 'Sub-agent evidence summary.';
      },
    );

    await tool.run(const SpawnSubAgentInput(
      task: 'Search the current book twice.',
      agentType: 'research',
      maxSteps: 4,
    ));

    final toolEvents = (await graphStore.listEvents(
      'spawned-run-empty-call-id',
    ))
        .where((event) => event.type == AgentRunEventType.toolCall)
        .toList(growable: false);
    expect(toolEvents, hasLength(2));
    expect(toolEvents.map((event) => event.query), [
      'first claim',
      'second claim',
    ]);
    expect(toolEvents.map((event) => event.eventId).toSet(), hasLength(2));
  });
}
