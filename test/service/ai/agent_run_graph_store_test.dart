import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_agent_governance.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/ai/agent_run_graph_store.dart';
import 'package:papertok_reader/service/ai/sub_agent_runner.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('agent-run-graph-test-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('persists agent run parent child graph and edge status', () async {
    final startedAt = DateTime.utc(2026, 6, 4, 13);
    final store = AgentRunGraphStore(rootDir: tempDir);

    await store.upsertRun(AgentRunRecord(
      runId: 'seminar-parent',
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: SubAgentRunStatus.running,
      task: 'Discuss this claim with traceable book evidence.',
      startedAt: startedAt,
    ));
    await store.upsertFromSubAgentResult(
      SubAgentRunResult(
        agentRunId: 'critical-run',
        parentRunId: 'seminar-parent',
        agentType: 'research',
        task: 'Find objections.',
        status: SubAgentRunStatus.completed,
        maxSteps: 8,
        agentScene: AiAgentScene.seminar,
        allowedToolIds: const ['book_content_search'],
        startedAt: startedAt,
        finishedAt: startedAt.add(const Duration(seconds: 4)),
        result: 'Critical evidence.',
      ),
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
    );
    await store.upsertFromSubAgentResult(
      SubAgentRunResult(
        agentRunId: 'verify-run',
        parentRunId: 'critical-run',
        agentType: 'verify',
        task: 'Verify the objection.',
        status: SubAgentRunStatus.errored,
        maxSteps: 5,
        agentScene: AiAgentScene.seminar,
        allowedToolIds: const ['book_content_search'],
        startedAt: startedAt.add(const Duration(seconds: 5)),
        finishedAt: startedAt.add(const Duration(seconds: 7)),
        error: 'Verifier timeout.',
      ),
      source: 'seminar',
      profile: 'verifier',
      roleId: 'verifier',
      nickname: 'Verifier',
    );

    final children = await store.listChildren('seminar-parent');
    expect(children, hasLength(1));
    expect(children.single.run.runId, 'critical-run');
    expect(children.single.run.parentRunId, 'seminar-parent');
    expect(children.single.run.profile, 'critical');
    expect(children.single.edge.status, AgentRunEdgeStatus.closed);

    final descendants = await store.listDescendants('seminar-parent');
    expect(descendants.map((entry) => entry.run.runId), [
      'critical-run',
      'verify-run',
    ]);
    expect(descendants.last.run.error, 'Verifier timeout.');

    await store.setEdgeStatus(
      parentRunId: 'seminar-parent',
      childRunId: 'critical-run',
      status: AgentRunEdgeStatus.closed,
    );

    final restored = AgentRunGraphStore(rootDir: tempDir);
    final restoredChildren = await restored.listChildren('seminar-parent');
    expect(restoredChildren.single.edge.status, AgentRunEdgeStatus.closed);
    expect(restoredChildren.single.run.result, 'Critical evidence.');
  });

  test('terminal child run closes graph edge while active run stays open',
      () async {
    final startedAt = DateTime.utc(2026, 6, 4, 14);
    final store = AgentRunGraphStore(rootDir: tempDir);

    await store.upsertRun(AgentRunRecord(
      runId: 'seminar-parent',
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: SubAgentRunStatus.running,
      task: 'Discuss this claim.',
      startedAt: startedAt,
    ));
    await store.upsertRun(AgentRunRecord(
      runId: 'critical-run',
      parentRunId: 'seminar-parent',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.running,
      task: 'Find objections.',
      agentScene: AiAgentScene.seminar,
      allowedToolIds: const ['book_content_search'],
      startedAt: startedAt.add(const Duration(seconds: 1)),
    ));

    var children = await store.listChildren('seminar-parent');
    expect(children.single.edge.status, AgentRunEdgeStatus.open);

    await store.upsertRun(AgentRunRecord(
      runId: 'critical-run',
      parentRunId: 'seminar-parent',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.completed,
      task: 'Find objections.',
      agentScene: AiAgentScene.seminar,
      allowedToolIds: const ['book_content_search'],
      startedAt: startedAt.add(const Duration(seconds: 1)),
      finishedAt: startedAt.add(const Duration(seconds: 4)),
      result: 'Critical result.',
    ));

    children = await store.listChildren('seminar-parent');
    expect(children.single.edge.status, AgentRunEdgeStatus.closed);

    final restored = AgentRunGraphStore(rootDir: tempDir);
    final restoredChildren = await restored.listChildren('seminar-parent');
    expect(restoredChildren.single.edge.status, AgentRunEdgeStatus.closed);
  });

  test('restarting a terminal Seminar child run reopens the graph edge',
      () async {
    final startedAt = DateTime.utc(2026, 6, 5, 14);
    final failedAt = startedAt.add(const Duration(seconds: 3));
    final retryStartedAt = startedAt.add(const Duration(seconds: 8));
    final store = AgentRunGraphStore(rootDir: tempDir);
    final session = AiSeminarSessionContract(
      id: 'seminar-parent',
      question: 'Discuss this claim.',
    );

    await store.upsertFromSeminarSessionStart(
      session: session,
      startedAt: startedAt,
    );
    await store.upsertRun(AgentRunRecord(
      runId: 'seminar-parent:role-critical-0',
      parentRunId: 'seminar-parent',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.errored,
      task: 'Find objections.',
      startedAt: startedAt.add(const Duration(seconds: 1)),
      finishedAt: failedAt,
      error: 'Provider failed.',
    ));

    expect(await store.listOpenChildren('seminar-parent'), isEmpty);

    await store.upsertFromSeminarRoleStart(
      session: session,
      role: AiSeminarRole.critical,
      runId: 'seminar-parent:role-critical-0',
      startedAt: retryStartedAt,
    );

    final openChildren = await store.listOpenChildren('seminar-parent');
    expect(openChildren.map((entry) => entry.run.runId), [
      'seminar-parent:role-critical-0',
    ]);
    expect(openChildren.single.run.status, SubAgentRunStatus.running);
    expect(openChildren.single.edge.status, AgentRunEdgeStatus.open);

    final restored = AgentRunGraphStore(rootDir: tempDir);
    final restoredOpenChildren =
        await restored.listOpenChildren('seminar-parent');
    expect(restoredOpenChildren.map((entry) => entry.run.runId), [
      'seminar-parent:role-critical-0',
    ]);
    expect(restoredOpenChildren.single.edge.status, AgentRunEdgeStatus.open);
  });

  test('lists only open child runs for wait and close controls', () async {
    final startedAt = DateTime.utc(2026, 6, 4, 14, 30);
    final store = AgentRunGraphStore(rootDir: tempDir);

    await store.upsertRun(AgentRunRecord(
      runId: 'seminar-parent',
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: SubAgentRunStatus.running,
      task: 'Discuss this claim.',
      startedAt: startedAt,
    ));
    await store.upsertRun(AgentRunRecord(
      runId: 'running-child',
      parentRunId: 'seminar-parent',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.running,
      task: 'Find objections.',
      startedAt: startedAt.add(const Duration(seconds: 1)),
    ));
    await store.upsertRun(AgentRunRecord(
      runId: 'waiting-child',
      parentRunId: 'seminar-parent',
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: SubAgentRunStatus.waitingInput,
      task: 'Ask the reader.',
      startedAt: startedAt.add(const Duration(seconds: 2)),
    ));
    await store.upsertRun(AgentRunRecord(
      runId: 'interrupted-child',
      parentRunId: 'seminar-parent',
      source: 'seminar',
      profile: 'verify',
      roleId: 'verify',
      nickname: 'Verifier',
      status: SubAgentRunStatus.interrupted,
      task: 'Needs more evidence.',
      startedAt: startedAt.add(const Duration(seconds: 3)),
    ));
    await store.upsertRun(AgentRunRecord(
      runId: 'completed-child',
      parentRunId: 'seminar-parent',
      source: 'seminar',
      profile: 'synthesizer',
      roleId: 'synthesizer',
      nickname: 'Synthesizer',
      status: SubAgentRunStatus.completed,
      task: 'Summarize.',
      startedAt: startedAt.add(const Duration(seconds: 4)),
      finishedAt: startedAt.add(const Duration(seconds: 5)),
      result: 'Done.',
    ));
    await store.upsertRun(AgentRunRecord(
      runId: 'errored-child',
      parentRunId: 'seminar-parent',
      source: 'seminar',
      profile: 'verify',
      roleId: 'verify',
      nickname: 'Verifier',
      status: SubAgentRunStatus.errored,
      task: 'Verify.',
      startedAt: startedAt.add(const Duration(seconds: 6)),
      finishedAt: startedAt.add(const Duration(seconds: 7)),
      error: 'Provider failed.',
    ));

    final openChildren = await store.listOpenChildren('seminar-parent');
    expect(openChildren.map((entry) => entry.run.runId), [
      'running-child',
      'waiting-child',
      'interrupted-child',
    ]);
    expect(
      openChildren.map((entry) => entry.edge.status).toSet(),
      {AgentRunEdgeStatus.open},
    );

    final restored = AgentRunGraphStore(rootDir: tempDir);
    final restoredOpenChildren =
        await restored.listOpenChildren('seminar-parent');
    expect(restoredOpenChildren.map((entry) => entry.run.runId), [
      'running-child',
      'waiting-child',
      'interrupted-child',
    ]);
  });

  test('closes an open child run for native close-agent control', () async {
    final startedAt = DateTime.utc(2026, 6, 4, 14, 45);
    final closedAt = startedAt.add(const Duration(seconds: 9));
    final store = AgentRunGraphStore(rootDir: tempDir);

    await store.upsertRun(AgentRunRecord(
      runId: 'seminar-parent',
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: SubAgentRunStatus.running,
      task: 'Discuss this claim.',
      startedAt: startedAt,
    ));
    await store.upsertRun(AgentRunRecord(
      runId: 'critical-run',
      parentRunId: 'seminar-parent',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.running,
      task: 'Find objections.',
      startedAt: startedAt.add(const Duration(seconds: 1)),
    ));

    final closedRun = await store.closeChildRun(
      parentRunId: 'seminar-parent',
      childRunId: 'critical-run',
      now: closedAt,
    );

    expect(closedRun.status, SubAgentRunStatus.shutdown);
    expect(closedRun.finishedAt, closedAt);
    expect(await store.listOpenChildren('seminar-parent'), isEmpty);
    final children = await store.listChildren('seminar-parent');
    expect(children.single.edge.status, AgentRunEdgeStatus.closed);
    final events = await store.listEvents('critical-run');
    expect(events.map((event) => event.status), [
      SubAgentRunStatus.running,
      SubAgentRunStatus.shutdown,
    ]);
    expect(events.last.eventId, 'critical-run:status:shutdown');

    final restored = AgentRunGraphStore(rootDir: tempDir);
    expect(await restored.listOpenChildren('seminar-parent'), isEmpty);
    final restoredRun = await restored.getRun('critical-run');
    expect(restoredRun?.status, SubAgentRunStatus.shutdown);
    expect(restoredRun?.finishedAt, closedAt);
  });

  test('persists agent run events for native chat stream replay', () async {
    final startedAt = DateTime.utc(2026, 6, 4, 15);
    final store = AgentRunGraphStore(rootDir: tempDir);

    await store.upsertRun(AgentRunRecord(
      runId: 'agent-run-1',
      parentRunId: 'chat-parent',
      source: 'spawn_sub_agent',
      profile: 'research',
      roleId: 'research',
      nickname: 'Research sub-agent',
      status: SubAgentRunStatus.completed,
      task: 'Collect evidence.',
      agentScene: AiAgentScene.seminar,
      allowedToolIds: const ['semantic_search_current_book'],
      startedAt: startedAt,
      finishedAt: startedAt.add(const Duration(seconds: 3)),
      result: 'Traceable evidence summary.',
    ));

    final events = await store.listEvents('agent-run-1');
    expect(events.map((event) => event.type), [
      AgentRunEventType.status,
      AgentRunEventType.result,
    ]);
    expect(events.first.parentRunId, 'chat-parent');
    expect(events.first.status, SubAgentRunStatus.completed);
    expect(events.first.roleId, 'research');
    expect(events.first.nickname, 'Research sub-agent');
    expect(events.first.allowedToolIds, ['semantic_search_current_book']);
    expect(events.last.result, 'Traceable evidence summary.');

    final parentEvents = await store.listChildEvents('chat-parent');
    expect(parentEvents.map((event) => event.runId), [
      'agent-run-1',
      'agent-run-1',
    ]);

    final restored = AgentRunGraphStore(rootDir: tempDir);
    final restoredEvents = await restored.listEvents('agent-run-1');
    expect(restoredEvents.first.allowedToolIds, [
      'semantic_search_current_book',
    ]);
    expect(restoredEvents.last.result, 'Traceable evidence summary.');
  });

  test('persists tool call event metadata for native chat replay', () async {
    final store = AgentRunGraphStore(rootDir: tempDir);
    final createdAt = DateTime.utc(2026, 6, 4, 17);

    await store.upsertEvent(AgentRunEvent(
      eventId: 'seminar-1:tool:semantic-search',
      runId: 'seminar-1:role-critical-0',
      parentRunId: 'seminar-1',
      type: AgentRunEventType.toolCall,
      createdAt: createdAt,
      toolId: 'semantic_search_current_book',
      query: 'working memory',
      resultCount: 2,
      roleIds: const ['critical', 'supportive'],
      evidenceRefs: [
        AiSeminarRunCardEvidenceSnapshot(
          id: 'e1',
          title: 'Chapter 2',
          snippet: 'Working memory evidence.',
          sourceRef: SourceRef(
            bookId: 7,
            cfi: 'epubcfi(/6/2)',
            sourceKind: SourceRefKind.currentBookRag,
            sourceTextSnippet: 'Working memory evidence.',
          ),
        ),
      ],
    ));

    final restored = AgentRunGraphStore(rootDir: tempDir);
    final events = await restored.listChildEvents('seminar-1');
    final event = events.single;
    expect(event.type, AgentRunEventType.toolCall);
    expect(event.toolId, 'semantic_search_current_book');
    expect(event.query, 'working memory');
    expect(event.resultCount, 2);
    expect(event.roleIds, ['critical', 'supportive']);
    expect(event.evidenceRefs.single.id, 'e1');
    expect(event.evidenceRefs.single.sourceRef?.bookId, 7);
  });

  test('persists artifact action event metadata for native chat replay',
      () async {
    final store = AgentRunGraphStore(rootDir: tempDir);
    final createdAt = DateTime.utc(2026, 6, 4, 17, 30);

    await store.upsertEvent(AgentRunEvent.fromJson({
      'eventId': 'seminar-1:artifact-action:sent-to-review',
      'runId': 'seminar-1',
      'type': 'artifact_action',
      'createdAt': createdAt.toIso8601String(),
      'status': 'completed',
      'roleId': 'director',
      'nickname': 'Director',
      'actionIds': ['sent-to-review'],
      'result': 'Exception sent to Review Inbox.',
      'evidenceRefs': [
        {
          'id': 'e1',
          'title': 'Chapter 2',
          'snippet': 'Working memory evidence.',
          'sourceRef': {
            'bookId': 7,
            'cfi': 'epubcfi(/6/2)',
            'sourceKind': 'currentBookRag',
            'sourceTextSnippet': 'Working memory evidence.',
          },
        },
      ],
    }));

    final restored = AgentRunGraphStore(rootDir: tempDir);
    final event = (await restored.listEvents('seminar-1')).single;
    expect(event.type.asString, 'artifact_action');
    expect(event.toJson()['actionIds'], ['sent-to-review']);
    expect(event.status, SubAgentRunStatus.completed);
    expect(event.roleId, 'director');
    expect(event.result, 'Exception sent to Review Inbox.');
    expect(event.evidenceRefs.single.id, 'e1');
    expect(event.evidenceRefs.single.sourceRef?.bookId, 7);
  });

  test('lists and acknowledges pending child control events', () async {
    final startedAt = DateTime.utc(2026, 6, 4, 18);
    final store = AgentRunGraphStore(rootDir: tempDir);

    await store.upsertRun(AgentRunRecord(
      runId: 'seminar-parent',
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: SubAgentRunStatus.running,
      task: 'Discuss this claim.',
      startedAt: startedAt,
    ));
    await store.upsertRun(AgentRunRecord(
      runId: 'critical-run',
      parentRunId: 'seminar-parent',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.waitingInput,
      task: 'Needs reader input.',
      startedAt: startedAt.add(const Duration(seconds: 1)),
    ));
    await store.upsertEvent(AgentRunEvent(
      eventId: 'critical-run:user-input:1',
      runId: 'critical-run',
      parentRunId: 'seminar-parent',
      type: AgentRunEventType.userInput,
      createdAt: startedAt.add(const Duration(seconds: 2)),
      roleId: 'critical',
      nickname: 'Critical',
      delta: 'Use Chapter 3 as evidence.',
    ));
    await store.upsertEvent(AgentRunEvent(
      eventId: 'critical-run:resume-request:2',
      runId: 'critical-run',
      parentRunId: 'seminar-parent',
      type: AgentRunEventType.resumeRequest,
      createdAt: startedAt.add(const Duration(seconds: 3)),
      roleId: 'critical',
      nickname: 'Critical',
      delta: 'Resume requested.',
    ));
    await store.upsertEvent(AgentRunEvent(
      eventId: 'critical-run:retry-request:3',
      runId: 'critical-run',
      parentRunId: 'seminar-parent',
      type: AgentRunEventType.retryRequest,
      createdAt: startedAt.add(const Duration(seconds: 4)),
      roleId: 'critical',
      nickname: 'Critical',
      delta: 'Retry requested.',
    ));
    await store.upsertEvent(AgentRunEvent(
      eventId: 'critical-run:wait-request:4',
      runId: 'critical-run',
      parentRunId: 'seminar-parent',
      type: AgentRunEventType.waitRequest,
      createdAt: startedAt.add(const Duration(seconds: 5)),
      roleId: 'critical',
      nickname: 'Critical',
      delta: 'Waiting for role to finish.',
    ));

    final pending = await store.listPendingControlEvents(
      parentRunId: 'seminar-parent',
      childRunId: 'critical-run',
    );
    expect(pending.map((event) => event.eventId), [
      'critical-run:user-input:1',
      'critical-run:resume-request:2',
      'critical-run:retry-request:3',
    ]);

    final acknowledged = await store.acknowledgeControlEvent(
      parentRunId: 'seminar-parent',
      childRunId: 'critical-run',
      eventId: 'critical-run:user-input:1',
      now: startedAt.add(const Duration(seconds: 5)),
    );
    expect(
        acknowledged.acknowledgedAt, startedAt.add(const Duration(seconds: 5)));

    final restored = AgentRunGraphStore(rootDir: tempDir);
    final restoredPending = await restored.listPendingControlEvents(
      parentRunId: 'seminar-parent',
      childRunId: 'critical-run',
    );
    expect(restoredPending.map((event) => event.eventId), [
      'critical-run:resume-request:2',
      'critical-run:retry-request:3',
    ]);
    expect(restoredPending.map((event) => event.acknowledgedAt), [
      null,
      null,
    ]);
  });

  test('acknowledges wait requests without adding them to pending controls',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('agent-run-graph-wait-');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final store = AgentRunGraphStore(rootDir: tempDir);
    final startedAt = DateTime.utc(2026, 6, 5, 10);

    await store.upsertRun(AgentRunRecord(
      runId: 'seminar-parent',
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: SubAgentRunStatus.running,
      task: 'Discuss evidence.',
      startedAt: startedAt,
    ));
    await store.upsertRun(AgentRunRecord(
      runId: 'critical-run',
      parentRunId: 'seminar-parent',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.running,
      task: 'Discuss evidence.',
      startedAt: startedAt.add(const Duration(seconds: 1)),
    ));
    await store.upsertEvent(AgentRunEvent(
      eventId: 'critical-run:wait-request:1',
      runId: 'critical-run',
      parentRunId: 'seminar-parent',
      type: AgentRunEventType.waitRequest,
      createdAt: startedAt.add(const Duration(seconds: 2)),
      roleId: 'critical',
      nickname: 'Critical',
      delta: 'Waiting for role to finish.',
    ));

    expect(
      await store.listPendingControlEvents(
        parentRunId: 'seminar-parent',
        childRunId: 'critical-run',
      ),
      isEmpty,
    );

    final acknowledged = await store.acknowledgeControlEvent(
      parentRunId: 'seminar-parent',
      childRunId: 'critical-run',
      eventId: 'critical-run:wait-request:1',
      now: startedAt.add(const Duration(seconds: 4)),
    );

    expect(
      acknowledged.acknowledgedAt,
      startedAt.add(const Duration(seconds: 4)),
    );
    final restored = AgentRunGraphStore(rootDir: tempDir);
    final events = (await restored.listEvents('critical-run'))
        .where((event) => event.type == AgentRunEventType.waitRequest)
        .toList(growable: false);
    expect(events.single.acknowledgedAt,
        startedAt.add(const Duration(seconds: 4)));
  });
}
