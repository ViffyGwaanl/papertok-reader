import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/ai/agent_run_event_message_part_adapter.dart';
import 'package:papertok_reader/service/ai/agent_run_graph_store.dart';
import 'package:papertok_reader/service/ai/sub_agent_runner.dart';

void main() {
  test('restores Seminar parent Director events with child role events',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('agent-event-parts-test-');
    addTearDown(() => tempDir.delete(recursive: true));

    final store = AgentRunGraphStore(rootDir: tempDir);
    await store.upsertRun(AgentRunRecord(
      runId: 'seminar-parent-director',
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: SubAgentRunStatus.completed,
      task: 'Explain the book evidence.',
      startedAt: DateTime.utc(2026, 6, 4, 18),
      finishedAt: DateTime.utc(2026, 6, 4, 18, 0, 4),
      result: 'Director synthesis summary.',
    ));
    await store.upsertEvent(AgentRunEvent(
      eventId: 'seminar-parent-director:role-critical-0:delta:0',
      runId: 'seminar-parent-director:role-critical-0',
      parentRunId: 'seminar-parent-director',
      type: AgentRunEventType.messageDelta,
      createdAt: DateTime.utc(2026, 6, 4, 18, 0, 1),
      roleId: 'critical',
      nickname: 'Critical',
      delta: 'Critical partial response.',
    ));

    final restored = AgentRunGraphStore(rootDir: tempDir);
    final parts = await seminarMessagePartsFromAgentRunGraphStore(
      restored,
      parentRunId: 'seminar-parent-director',
    );

    expect(parts.map((part) => part.id), [
      'seminar-parent-director:role-critical-0:delta:0',
      'seminar-parent-director:status:completed',
      'seminar-parent-director:result',
    ]);
    expect(parts.map((part) => part.type), [
      'role_partial',
      'director_state',
      'synthesis',
    ]);
    expect(parts[1].roleId, 'director');
    expect(parts[1].label, 'end');
    expect(parts[1].text, 'Director completed.');
    expect(parts[2].roleId, 'director');
    expect(parts[2].label, 'Director');
    expect(parts[2].text, 'Director synthesis summary.');
  });

  test('restores Seminar role partial parts from persisted child events',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('agent-event-parts-test-');
    addTearDown(() => tempDir.delete(recursive: true));

    final store = AgentRunGraphStore(rootDir: tempDir);
    await store.upsertEvent(AgentRunEvent(
      eventId: 'seminar-2:role-critical-0:status:running',
      runId: 'seminar-2:role-critical-0',
      parentRunId: 'seminar-2',
      type: AgentRunEventType.status,
      createdAt: DateTime.utc(2026, 6, 4, 16),
    ));
    await store.upsertEvent(AgentRunEvent(
      eventId: 'seminar-2:role-critical-0:delta:0',
      runId: 'seminar-2:role-critical-0',
      parentRunId: 'seminar-2',
      type: AgentRunEventType.messageDelta,
      createdAt: DateTime.utc(2026, 6, 4, 16, 0, 1),
      roleId: 'critical',
      nickname: 'Critical',
      delta: 'First recovered partial.',
    ));
    await store.upsertEvent(AgentRunEvent(
      eventId: 'seminar-2:role-synthesizer-1:delta:0',
      runId: 'seminar-2:role-synthesizer-1',
      parentRunId: 'seminar-2',
      type: AgentRunEventType.messageDelta,
      createdAt: DateTime.utc(2026, 6, 4, 16, 0, 2),
      roleId: 'synthesizer',
      nickname: 'Synthesizer',
      delta: 'Second recovered partial.',
    ));

    final restored = AgentRunGraphStore(rootDir: tempDir);
    final parts = await seminarMessagePartsFromAgentRunGraphStore(
      restored,
      parentRunId: 'seminar-2',
    );

    expect(parts.map((part) => part.id), [
      'seminar-2:role-critical-0:delta:0',
      'seminar-2:role-synthesizer-1:delta:0',
    ]);
    expect(parts.map((part) => part.roleId), ['critical', 'synthesizer']);
    expect(parts.map((part) => part.text), [
      'First recovered partial.',
      'Second recovered partial.',
    ]);
  });

  test('restores open child run records when event replay is missing',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('agent-event-parts-test-');
    addTearDown(() => tempDir.delete(recursive: true));

    final workflowDir = Directory('${tempDir.path}/.workflow');
    await workflowDir.create(recursive: true);
    final graphFile = File('${workflowDir.path}/agent_runs_v1.json');
    await graphFile.writeAsString(jsonEncode({
      'schemaVersion': 1,
      'runs': [
        {
          'runId': 'seminar-open-parent',
          'source': 'seminar',
          'profile': 'director',
          'roleId': 'director',
          'nickname': 'Director',
          'status': 'running',
          'task': 'Discuss the claim.',
          'startedAt': DateTime.utc(2026, 6, 4, 19).toIso8601String(),
        },
        {
          'runId': 'seminar-open-parent:role-critical-0',
          'parentRunId': 'seminar-open-parent',
          'source': 'seminar',
          'profile': 'critical',
          'roleId': 'critical',
          'nickname': 'Critical',
          'status': 'running',
          'task': 'Discuss the claim.',
          'startedAt': DateTime.utc(2026, 6, 4, 19, 0, 1).toIso8601String(),
        },
        {
          'runId': 'seminar-open-parent:role-supportive-1',
          'parentRunId': 'seminar-open-parent',
          'source': 'seminar',
          'profile': 'supportive',
          'roleId': 'supportive',
          'nickname': 'Supportive',
          'status': 'completed',
          'task': 'Discuss the claim.',
          'startedAt': DateTime.utc(2026, 6, 4, 19, 0, 2).toIso8601String(),
          'finishedAt': DateTime.utc(2026, 6, 4, 19, 0, 3).toIso8601String(),
          'result': 'Supportive done.',
        },
      ],
      'edges': [
        {
          'parentRunId': 'seminar-open-parent',
          'childRunId': 'seminar-open-parent:role-critical-0',
          'status': 'open',
          'createdAt': DateTime.utc(2026, 6, 4, 19, 0, 1).toIso8601String(),
          'updatedAt': DateTime.utc(2026, 6, 4, 19, 0, 1).toIso8601String(),
        },
        {
          'parentRunId': 'seminar-open-parent',
          'childRunId': 'seminar-open-parent:role-supportive-1',
          'status': 'closed',
          'createdAt': DateTime.utc(2026, 6, 4, 19, 0, 2).toIso8601String(),
          'updatedAt': DateTime.utc(2026, 6, 4, 19, 0, 3).toIso8601String(),
        },
      ],
      'events': [],
    }));

    final parts = await seminarMessagePartsFromAgentRunGraphStore(
      AgentRunGraphStore(rootDir: tempDir),
      parentRunId: 'seminar-open-parent',
    );

    expect(parts, hasLength(1));
    expect(
        parts.single.id, 'seminar-open-parent:role-critical-0:status:running');
    expect(parts.single.type, 'agent_status');
    expect(parts.single.roleId, 'critical');
    expect(parts.single.label, 'role-running');
    expect(parts.single.text, 'Critical is running.');
  });

  test('maps Seminar role message delta events to role partial message parts',
      () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:delta:0',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.messageDelta,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        roleId: 'critical',
        nickname: 'Critical',
        delta: 'Critical partial response.',
      ),
    ]);

    expect(parts, hasLength(1));
    expect(parts.single.type, 'role_partial');
    expect(parts.single.id, 'seminar-1:role-critical-0:delta:0');
    expect(parts.single.toJson()['agentRunId'], 'seminar-1:role-critical-0');
    expect(parts.single.toJson()['parentRunId'], 'seminar-1');
    expect(parts.single.roleId, 'critical');
    expect(parts.single.label, 'Critical');
    expect(parts.single.text, 'Critical partial response.');
  });

  test('maps Seminar role status allowed tools to agent status parts', () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:status:running',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.status,
        createdAt: DateTime.utc(2026, 6, 5, 16),
        status: SubAgentRunStatus.running,
        roleId: 'critical',
        nickname: 'Critical',
        allowedToolIds: const [
          'semantic_search_current_book',
          'notes_search',
        ],
      ),
    ]);

    expect(parts, hasLength(1));
    expect(parts.single.type, 'agent_status');
    expect(parts.single.allowedToolIds, [
      'semantic_search_current_book',
      'notes_search',
    ]);
    expect(parts.single.actionIds, ['wait-agent', 'close-agent']);
  });

  test('maps Seminar thinking events to thinking message parts', () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:thinking:0',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.thinking,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        roleId: 'critical',
        nickname: 'Critical',
        delta: 'Critical is comparing the available evidence.',
      ),
    ]);

    expect(parts, hasLength(1));
    expect(parts.single.type, 'thinking');
    expect(parts.single.id, 'seminar-1:role-critical-0:thinking:0');
    expect(parts.single.toJson()['agentRunId'], 'seminar-1:role-critical-0');
    expect(parts.single.toJson()['parentRunId'], 'seminar-1');
    expect(parts.single.roleId, 'critical');
    expect(parts.single.label, 'Critical');
    expect(parts.single.text, 'Critical is comparing the available evidence.');
    expect(parts.single.completedAt,
        DateTime.utc(2026, 6, 4, 16).millisecondsSinceEpoch);
  });

  test('drops generic role-start thinking when streamed thinking exists', () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:thinking:start',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.thinking,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        roleId: 'critical',
        nickname: 'Critical',
        delta: 'Critical is preparing an evidence-grounded response.',
      ),
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:thinking:stream:0',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.thinking,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 1),
        roleId: 'critical',
        nickname: 'Critical',
        delta: 'Checking note and semantic evidence.',
      ),
      AgentRunEvent(
        eventId: 'seminar-1:role-supportive-1:thinking:start',
        runId: 'seminar-1:role-supportive-1',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.thinking,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 2),
        roleId: 'supportive',
        nickname: 'Supportive',
        delta: 'Supportive is preparing an evidence-grounded response.',
      ),
    ]);

    expect(parts.map((part) => part.id), [
      'seminar-1:role-critical-0:thinking:stream:0',
      'seminar-1:role-supportive-1:thinking:start',
    ]);
    expect(parts.first.text, 'Checking note and semantic evidence.');
  });

  test('maps Seminar artifact action events to artifact action parts', () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent.fromJson({
        'eventId': 'seminar-1:artifact-action:sent-to-review',
        'runId': 'seminar-1',
        'type': 'artifact_action',
        'createdAt': DateTime.utc(2026, 6, 4, 16, 0, 1).toIso8601String(),
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
      }),
    ]);

    expect(parts, hasLength(1));
    expect(parts.single.type, 'artifact_actions');
    expect(parts.single.id, 'seminar-1:artifact-action:sent-to-review');
    expect(parts.single.toJson()['agentRunId'], 'seminar-1');
    expect(parts.single.roleId, 'director');
    expect(parts.single.status, 'completed');
    expect(
      parts.single.completedAt,
      DateTime.utc(2026, 6, 4, 16, 0, 1).millisecondsSinceEpoch,
    );
    expect(parts.single.actionIds, ['sent-to-review']);
    expect(parts.single.text, 'Exception sent to Review Inbox.');
    expect(parts.single.evidenceRefs.single.id, 'e1');
    expect(parts.single.evidenceRefs.single.sourceRef?.bookId, 7);
  });

  test('downgrades Seminar asset actions without traceable source evidence',
      () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent.fromJson({
        'eventId': 'seminar-1:artifact-action:knowledge-card-saved',
        'runId': 'seminar-1',
        'type': 'artifact_action',
        'createdAt': DateTime.utc(2026, 6, 4, 16, 0, 2).toIso8601String(),
        'status': 'completed',
        'roleId': 'director',
        'nickname': 'Director',
        'actionIds': ['knowledge-card-saved'],
        'result': 'KnowledgeCard saved.',
        'evidenceRefs': [
          {
            'id': 'e1',
            'title': 'Chapter 2',
            'snippet': 'Working memory evidence.',
          },
        ],
      }),
    ]);

    expect(parts, hasLength(1));
    expect(parts.single.type, 'artifact_actions');
    expect(parts.single.status, 'interrupted');
    expect(parts.single.actionIds, ['send-to-review']);
    expect(parts.single.actionIds, isNot(contains('knowledge-card-saved')));
    expect(parts.single.actionIds, isNot(contains('undo-knowledge-card')));
    expect(
      parts.single.text,
      contains('missing traceable source evidence'),
    );
    expect(parts.single.evidenceRefs.single.id, 'e1');
    expect(parts.single.evidenceRefs.single.sourceRef, isNull);
  });

  test('maps Seminar role status result and error events to message parts', () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:status:running',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.status,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        status: SubAgentRunStatus.running,
        roleId: 'critical',
        nickname: 'Critical',
      ),
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:result',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.result,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 1),
        roleId: 'critical',
        nickname: 'Critical',
        result: 'Critical completed response.',
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
      ),
      AgentRunEvent(
        eventId: 'seminar-1:role-verifier-1:error',
        runId: 'seminar-1:role-verifier-1',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.error,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 2),
        roleId: 'verifier',
        nickname: 'Verifier',
        error: 'Provider timeout.',
      ),
    ]);

    expect(parts.map((part) => part.type), [
      'role_turn',
      'agent_status',
    ]);
    expect(parts[0].id, 'seminar-1:role-critical-0:result');
    expect(parts[0].toJson()['agentRunId'], 'seminar-1:role-critical-0');
    expect(parts[0].toJson()['parentRunId'], 'seminar-1');
    expect(parts[0].roleId, 'critical');
    expect(parts[0].label, 'Critical');
    expect(parts[0].text, 'Critical completed response.');
    expect(parts[0].evidenceRefs.single.id, 'e1');
    expect(parts[0].evidenceRefs.single.sourceRef?.bookId, 7);
    expect(parts[1].id, 'seminar-1:role-verifier-1:error');
    expect(parts[1].toJson()['agentRunId'], 'seminar-1:role-verifier-1');
    expect(parts[1].toJson()['parentRunId'], 'seminar-1');
    expect(parts[1].roleId, 'verifier');
    expect(parts[1].label, 'role-error');
    expect(parts[1].actionIds, ['retry-agent-control']);
    expect(parts[1].text, 'Verifier failed: Provider timeout.');
  });

  test('keeps Seminar Director status events as director state parts', () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:status:completed',
        runId: 'seminar-1',
        type: AgentRunEventType.status,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        status: SubAgentRunStatus.completed,
        roleId: 'director',
        nickname: 'Director',
      ),
    ]);

    expect(parts, hasLength(1));
    expect(parts.single.type, 'director_state');
    expect(parts.single.roleId, 'director');
    expect(parts.single.label, 'end');
    expect(parts.single.text, 'Director completed.');
  });

  test('maps active Seminar Director statuses to director state', () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:status:pending',
        runId: 'seminar-1',
        type: AgentRunEventType.status,
        createdAt: DateTime.utc(2026, 6, 4, 15, 59),
        status: SubAgentRunStatus.pendingInit,
        roleId: 'director',
        nickname: 'Director',
      ),
      AgentRunEvent(
        eventId: 'seminar-1:status:running',
        runId: 'seminar-1',
        type: AgentRunEventType.status,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        status: SubAgentRunStatus.running,
        roleId: 'director',
        nickname: 'Director',
      ),
    ]);

    expect(parts, hasLength(1));
    expect(parts.single.type, 'director_state');
    expect(parts.single.roleId, 'director');
    expect(parts.single.label, 'running');
    expect(parts.single.actionIds, isEmpty);
    expect(parts.single.text, 'Director is running.');
  });

  test('maps Seminar Director failures to director failed state', () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:status:errored',
        runId: 'seminar-1',
        type: AgentRunEventType.status,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        status: SubAgentRunStatus.errored,
        roleId: 'director',
        nickname: 'Director',
      ),
      AgentRunEvent(
        eventId: 'seminar-2:error',
        runId: 'seminar-2',
        type: AgentRunEventType.error,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 1),
        roleId: 'director',
        nickname: 'Director',
        error: 'Evidence fetch failed.',
      ),
    ]);

    expect(parts, hasLength(2));
    expect(parts.map((part) => part.type), [
      'director_state',
      'director_state',
    ]);
    expect(parts.map((part) => part.label), ['failed', 'failed']);
    expect(parts.first.actionIds, isEmpty);
    expect(parts.last.actionIds, isEmpty);
    expect(parts.first.text, 'Director failed.');
    expect(parts.last.text, 'Director failed: Evidence fetch failed.');
  });

  test('maps interrupted Seminar Director status to director state', () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:status:interrupted',
        runId: 'seminar-1',
        type: AgentRunEventType.status,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        status: SubAgentRunStatus.interrupted,
        roleId: 'director',
        nickname: 'Director',
      ),
    ]);

    expect(parts, hasLength(1));
    expect(parts.single.type, 'director_state');
    expect(parts.single.roleId, 'director');
    expect(parts.single.label, 'interrupted');
    expect(parts.single.actionIds, isEmpty);
    expect(parts.single.text, 'Director was interrupted.');
  });

  test('maps terminal Seminar Director statuses to director state', () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:status:shutdown',
        runId: 'seminar-1',
        type: AgentRunEventType.status,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        status: SubAgentRunStatus.shutdown,
        roleId: 'director',
        nickname: 'Director',
      ),
      AgentRunEvent(
        eventId: 'seminar-2:status:not-found',
        runId: 'seminar-2',
        type: AgentRunEventType.status,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 1),
        status: SubAgentRunStatus.notFound,
        roleId: 'director',
        nickname: 'Director',
      ),
    ]);

    expect(parts, hasLength(2));
    expect(parts.map((part) => part.type), [
      'director_state',
      'director_state',
    ]);
    expect(parts.map((part) => part.roleId), ['director', 'director']);
    expect(parts.map((part) => part.label), ['stopped', 'not-found']);
    expect(parts.every((part) => part.actionIds.isEmpty), isTrue);
    expect(parts.map((part) => part.text), [
      'Director was shut down.',
      'Director was not found.',
    ]);
  });

  test('maps open Seminar role statuses to native agent control actions', () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:status:running',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.status,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        status: SubAgentRunStatus.running,
        roleId: 'critical',
        nickname: 'Critical',
      ),
      AgentRunEvent(
        eventId: 'seminar-1:role-supportive-1:status:waiting-input',
        runId: 'seminar-1:role-supportive-1',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.status,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 1),
        status: SubAgentRunStatus.waitingInput,
        roleId: 'supportive',
        nickname: 'Supportive',
      ),
      AgentRunEvent(
        eventId: 'seminar-1:role-verifier-2:status:interrupted',
        runId: 'seminar-1:role-verifier-2',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.status,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 2),
        status: SubAgentRunStatus.interrupted,
        roleId: 'verifier',
        nickname: 'Verifier',
      ),
      AgentRunEvent(
        eventId: 'seminar-1:role-synthesizer-3:status:completed',
        runId: 'seminar-1:role-synthesizer-3',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.status,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 3),
        status: SubAgentRunStatus.completed,
        roleId: 'synthesizer',
        nickname: 'Synthesizer',
      ),
    ]);

    expect(parts.map((part) => part.label), [
      'role-running',
      'role-waiting-input',
      'role-interrupted',
      'role-completed',
    ]);
    expect(parts.map((part) => part.toJson()['agentRunId']), [
      'seminar-1:role-critical-0',
      'seminar-1:role-supportive-1',
      'seminar-1:role-verifier-2',
      'seminar-1:role-synthesizer-3',
    ]);
    expect(parts[0].actionIds, ['wait-agent', 'close-agent']);
    expect(parts[1].actionIds, ['send-input', 'close-agent']);
    expect(parts[2].actionIds, ['resume-agent', 'close-agent']);
    expect(parts[3].actionIds, isEmpty);
  });

  test('maps failed Seminar role status to native retry control action', () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:status:errored',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.status,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        status: SubAgentRunStatus.errored,
        roleId: 'critical',
        nickname: 'Critical',
      ),
    ]);

    expect(parts.single.type, 'agent_status');
    expect(parts.single.label, 'role-error');
    expect(parts.single.actionIds, ['retry-agent-control']);
    expect(parts.single.agentRunId, 'seminar-1:role-critical-0');
  });

  test('maps failed Seminar role error event to native retry control action',
      () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:role-verifier-0:error',
        runId: 'seminar-1:role-verifier-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.error,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        roleId: 'verifier',
        nickname: 'Verifier',
        error: 'Provider timeout.',
      ),
    ]);

    expect(parts.single.type, 'agent_status');
    expect(parts.single.label, 'role-error');
    expect(parts.single.actionIds, ['retry-agent-control']);
    expect(parts.single.agentRunId, 'seminar-1:role-verifier-0');
  });

  test('keeps only the latest status part for each agent run', () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:status:running',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.status,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        status: SubAgentRunStatus.running,
        roleId: 'critical',
        nickname: 'Critical',
      ),
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:status:shutdown',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.status,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 3),
        status: SubAgentRunStatus.shutdown,
        roleId: 'critical',
        nickname: 'Critical',
      ),
    ]);

    expect(parts, hasLength(1));
    expect(parts.single.id, 'seminar-1:role-critical-0:status:shutdown');
    expect(parts.single.label, 'role-shutdown');
    expect(parts.single.actionIds, isEmpty);
  });

  test('drops stale running status when terminal event exists for same run',
      () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:status:running',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.status,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        status: SubAgentRunStatus.running,
        roleId: 'critical',
        nickname: 'Critical',
      ),
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:result',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.result,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 1),
        roleId: 'critical',
        nickname: 'Critical',
        result: 'Critical completed response.',
      ),
      AgentRunEvent(
        eventId: 'seminar-1:role-verifier-1:status:running',
        runId: 'seminar-1:role-verifier-1',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.status,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 2),
        status: SubAgentRunStatus.running,
        roleId: 'verifier',
        nickname: 'Verifier',
      ),
      AgentRunEvent(
        eventId: 'seminar-1:role-verifier-1:error',
        runId: 'seminar-1:role-verifier-1',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.error,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 3),
        roleId: 'verifier',
        nickname: 'Verifier',
        error: 'Provider timeout.',
      ),
    ]);

    expect(parts.map((part) => part.id), [
      'seminar-1:role-critical-0:result',
      'seminar-1:role-verifier-1:error',
    ]);
    expect(parts.map((part) => part.type), ['role_turn', 'agent_status']);
    expect(parts[1].label, 'role-error');
    expect(parts[1].actionIds, ['retry-agent-control']);
  });

  test('drops stale role partial when terminal event exists for same run', () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:delta:0',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.messageDelta,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        roleId: 'critical',
        nickname: 'Critical',
        delta: 'Critical partial response.',
      ),
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:error',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.error,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 1),
        roleId: 'critical',
        nickname: 'Critical',
        error: 'Provider timeout.',
      ),
    ]);

    expect(parts, hasLength(1));
    expect(parts.single.id, 'seminar-1:role-critical-0:error');
    expect(parts.single.type, 'agent_status');
    expect(parts.single.label, 'role-error');
  });

  test('drops stale terminal role event after the same child run restarts', () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:error',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.error,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        roleId: 'critical',
        nickname: 'Critical',
        error: 'Provider failed before retry.',
      ),
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:status:running',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.status,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 2),
        status: SubAgentRunStatus.running,
        roleId: 'critical',
        nickname: 'Critical',
      ),
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:delta:retry',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.messageDelta,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 3),
        roleId: 'critical',
        nickname: 'Critical',
        delta: 'Retry is generating a replacement answer.',
      ),
    ]);

    expect(parts.map((part) => part.id), [
      'seminar-1:role-critical-0:status:running',
      'seminar-1:role-critical-0:delta:retry',
    ]);
    expect(parts.map((part) => part.type), ['agent_status', 'role_partial']);
    expect(parts.any((part) => part.label == 'role-error'), isFalse);
  });

  test('maps Seminar Director waiting input event to reader composer part', () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:status:waiting-input',
        runId: 'seminar-1',
        type: AgentRunEventType.status,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        status: SubAgentRunStatus.waitingInput,
        roleId: 'director',
        nickname: 'Director',
        roleIds: const ['critical', 'supportive'],
        delta: 'Which interpretation should the reader test next?',
      ),
    ]);

    expect(parts, hasLength(1));
    expect(parts.single.type, 'reader_composer');
    expect(parts.single.id, 'seminar-1:status:waiting-input');
    expect(parts.single.toJson()['agentRunId'], 'seminar-1');
    expect(parts.single.roleId, 'director');
    expect(parts.single.label, 'ask-user');
    expect(
        parts.single.text, 'Which interpretation should the reader test next?');
    expect(
        parts.single.actionIds, ['ask-role', 'refresh-evidence', 'synthesize']);
    expect(parts.single.defaultActionId, 'ask-role');
    expect(parts.single.selectedActionId, 'ask-role');
    expect(parts.single.roleIds, ['critical', 'supportive']);
    expect(parts.single.defaultRoleId, 'critical');
    expect(parts.single.selectedRoleId, 'critical');
  });

  test('marks acknowledged Seminar control events as completed reader turns',
      () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:user-input:1',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.userInput,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        roleId: 'critical',
        nickname: 'Critical',
        delta: 'Please answer the reader objection.',
        acknowledgedAt: DateTime.utc(2026, 6, 4, 16, 0, 2),
      ),
      AgentRunEvent(
        eventId: 'seminar-1:role-verifier-1:resume-request:1',
        runId: 'seminar-1:role-verifier-1',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.resumeRequest,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 1),
        roleId: 'verifier',
        nickname: 'Verifier',
        delta: 'Resume requested.',
        acknowledgedAt: DateTime.utc(2026, 6, 4, 16, 0, 3),
      ),
    ]);

    expect(parts.map((part) => part.type), ['reader_turn', 'reader_turn']);
    expect(parts.map((part) => part.status), ['completed', 'completed']);
    expect(parts.map((part) => part.label), ['send-input', 'resume-agent']);
    expect(parts.map((part) => part.completedAt), [
      DateTime.utc(2026, 6, 4, 16, 0, 2).millisecondsSinceEpoch,
      DateTime.utc(2026, 6, 4, 16, 0, 3).millisecondsSinceEpoch,
    ]);
    expect(parts[1].text, isNull);
    expect(parts[0].toJson()['agentRunId'], 'seminar-1:role-critical-0');
    expect(parts[1].toJson()['agentRunId'], 'seminar-1:role-verifier-1');
  });

  test('marks unacknowledged Seminar control events as pending reader turns',
      () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:user-input:1',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.userInput,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        roleId: 'critical',
        nickname: 'Critical',
        delta: 'Please answer the reader objection.',
      ),
      AgentRunEvent(
        eventId: 'seminar-1:role-verifier-1:resume-request:1',
        runId: 'seminar-1:role-verifier-1',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.resumeRequest,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 1),
        roleId: 'verifier',
        nickname: 'Verifier',
        delta: 'Resume requested.',
      ),
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:retry-request:1',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.retryRequest,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 2),
        roleId: 'critical',
        nickname: 'Critical',
        delta: 'Retry requested.',
      ),
    ]);

    expect(parts.map((part) => part.type),
        ['reader_turn', 'reader_turn', 'reader_turn']);
    expect(parts.map((part) => part.status), ['pending', 'pending', 'pending']);
    expect(parts.map((part) => part.label),
        ['send-input', 'resume-agent', 'retry-agent-control']);
    expect(parts.map((part) => part.completedAt), [null, null, null]);
    expect(parts[1].text, isNull);
    expect(parts[2].text, isNull);
  });

  test('maps close requests without exposing internal default text', () {
    final closedAt = DateTime.utc(2026, 6, 8, 14, 0, 6);
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:close-request:1',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.closeRequest,
        createdAt: closedAt,
        roleId: 'critical',
        nickname: 'Critical',
        delta: 'Stop role requested.',
        acknowledgedAt: closedAt,
      ),
    ]);

    expect(parts, hasLength(1));
    expect(parts.single.type, 'reader_turn');
    expect(parts.single.label, 'close-agent');
    expect(parts.single.status, 'completed');
    expect(parts.single.text, isNull);
    expect(parts.single.completedAt, closedAt.millisecondsSinceEpoch);
  });

  test('drops stale pending control after later acknowledged control', () {
    final acknowledgedAt = DateTime.utc(2026, 6, 4, 16, 0, 4);
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:user-input:1',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.userInput,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        roleId: 'critical',
        nickname: 'Critical',
        delta: 'Please answer the older reader objection.',
      ),
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:retry-request:1',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.retryRequest,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 2),
        roleId: 'critical',
        nickname: 'Critical',
        delta: 'Retry requested.',
        acknowledgedAt: acknowledgedAt,
      ),
    ]);

    expect(parts, hasLength(1));
    expect(parts.single.type, 'reader_turn');
    expect(parts.single.label, 'retry-agent-control');
    expect(parts.single.status, 'completed');
    expect(parts.single.completedAt, acknowledgedAt.millisecondsSinceEpoch);
  });

  test('cancels unacknowledged runtime control after terminal status', () {
    final shutdownAt = DateTime.utc(2026, 6, 4, 16, 0, 4);
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:user-input:1',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.userInput,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        roleId: 'critical',
        nickname: 'Critical',
        delta: 'Please answer the reader objection.',
      ),
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:status:shutdown',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.status,
        createdAt: shutdownAt,
        status: SubAgentRunStatus.shutdown,
        roleId: 'critical',
        nickname: 'Critical',
      ),
    ]);

    expect(parts.map((part) => part.type), ['reader_turn', 'agent_status']);
    expect(parts.first.label, 'send-input');
    expect(parts.first.status, 'cancelled');
    expect(parts.first.completedAt, shutdownAt.millisecondsSinceEpoch);
    expect(parts.last.label, 'role-shutdown');
  });

  test('completes unacknowledged wait request after terminal status', () {
    final shutdownAt = DateTime.utc(2026, 6, 4, 16, 0, 4);
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:wait-request:1',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.waitRequest,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        roleId: 'critical',
        nickname: 'Critical',
        delta: 'Waiting for role to finish.',
      ),
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:status:shutdown',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.status,
        createdAt: shutdownAt,
        status: SubAgentRunStatus.shutdown,
        roleId: 'critical',
        nickname: 'Critical',
      ),
    ]);

    expect(parts.map((part) => part.type), ['reader_turn', 'agent_status']);
    expect(parts.first.label, 'wait-agent');
    expect(parts.first.status, 'completed');
    expect(parts.first.completedAt, shutdownAt.millisecondsSinceEpoch);
    expect(parts.last.label, 'role-shutdown');
  });

  test('maps Seminar wait request events to reader turn parts', () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:wait-request:1',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.waitRequest,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 2),
        roleId: 'critical',
        nickname: 'Critical',
        delta: 'Waiting for role to finish.',
      ),
      AgentRunEvent(
        eventId: 'seminar-1:role-verifier-1:wait-request:1',
        runId: 'seminar-1:role-verifier-1',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.waitRequest,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 3),
        roleId: 'verifier',
        nickname: 'Verifier',
        delta: 'Waiting for role to finish.',
        acknowledgedAt: DateTime.utc(2026, 6, 4, 16, 0, 4),
      ),
    ]);

    expect(parts.map((part) => part.type), ['reader_turn', 'reader_turn']);
    expect(parts.map((part) => part.label), ['wait-agent', 'wait-agent']);
    expect(parts.map((part) => part.status), ['pending', 'completed']);
    expect(parts[0].completedAt, isNull);
    expect(
      parts[1].completedAt,
      DateTime.utc(2026, 6, 4, 16, 0, 4).millisecondsSinceEpoch,
    );
  });

  test('maps Seminar tool wait request events to tool reader turns', () {
    final acknowledgedAt = DateTime.utc(2026, 6, 4, 16, 0, 4);
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId:
            'seminar-1:role-critical-0:wait-tool-call:seminar-1:tool:notes:1',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.waitRequest,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 2),
        roleId: 'critical',
        nickname: 'Critical',
        toolId: 'notes_search',
        query: 'agency notes',
        delta: 'Waiting for tool call to finish.',
        result: 'seminar-1:tool:notes',
        acknowledgedAt: acknowledgedAt,
      ),
    ]);

    expect(parts, hasLength(1));
    expect(parts.single.type, 'reader_turn');
    expect(parts.single.label, 'wait-tool-call');
    expect(parts.single.status, 'completed');
    expect(parts.single.roleId, 'critical');
    expect(parts.single.toolId, 'notes_search');
    expect(parts.single.query, 'agency notes');
    expect(parts.single.text, 'Waiting for tool call to finish.');
    expect(parts.single.completedAt, acknowledgedAt.millisecondsSinceEpoch);
  });

  test('maps Seminar tool cancel request events to tool reader turns', () {
    final acknowledgedAt = DateTime.utc(2026, 6, 8, 12, 0, 4);
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId:
            'seminar-1:role-critical-0:cancel-tool-call:seminar-1:role-critical-0:tool:notes:1',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.cancelRequest,
        createdAt: DateTime.utc(2026, 6, 8, 12, 0, 2),
        roleId: 'critical',
        nickname: 'Critical',
        toolId: 'notes_search',
        query: 'agency notes',
        result: 'seminar-1:role-critical-0:tool:notes',
        acknowledgedAt: acknowledgedAt,
      ),
    ]);

    expect(parts, hasLength(1));
    expect(parts.single.type, 'reader_turn');
    expect(parts.single.label, 'cancel-tool-call');
    expect(parts.single.status, 'completed');
    expect(parts.single.roleId, 'critical');
    expect(parts.single.toolId, 'notes_search');
    expect(parts.single.query, 'agency notes');
    expect(parts.single.text, isNull);
    expect(parts.single.completedAt, acknowledgedAt.millisecondsSinceEpoch);
  });

  test('completes pending Seminar tool wait after terminal tool call', () {
    final completedAt = DateTime.utc(2026, 6, 4, 16, 0, 4);
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId:
            'seminar-1:role-critical-0:wait-tool-call:seminar-1:role-critical-0:tool:notes:1',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.waitRequest,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 2),
        roleId: 'critical',
        nickname: 'Critical',
        toolId: 'notes_search',
        query: 'agency notes',
        delta: 'Waiting for tool call to finish.',
        result: 'seminar-1:role-critical-0:tool:notes',
      ),
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:tool:notes',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.toolCall,
        createdAt: completedAt,
        status: SubAgentRunStatus.completed,
        roleId: 'critical',
        nickname: 'Critical',
        toolId: 'notes_search',
        query: 'agency notes',
        result: 'Returned waited notes.',
        resultCount: 1,
      ),
    ]);

    final readerTurn = parts.singleWhere(
      (part) => part.type == 'reader_turn' && part.label == 'wait-tool-call',
    );
    final toolCall = parts.singleWhere(
      (part) => part.type == 'tool_call' && part.toolId == 'notes_search',
    );

    expect(readerTurn.status, 'completed');
    expect(readerTurn.completedAt, completedAt.millisecondsSinceEpoch);
    expect(toolCall.status, 'completed');
    expect(toolCall.text, 'Returned waited notes.');
  });

  test('maps Seminar tool call events to tool call message parts', () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:tool:semantic-search',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.toolCall,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        status: SubAgentRunStatus.running,
        toolId: 'semantic_search_current_book',
        query: 'working memory',
        result: 'Returned 2 traceable chunks.',
        resultCount: 2,
        roleIds: const ['critical', 'supportive'],
        actionIds: const ['wait-tool-call', 'cancel-tool-call'],
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
      ),
    ]);

    final toolCall = parts.singleWhere((part) => part.type == 'tool_call');
    expect(toolCall.id, 'seminar-1:tool:semantic-search');
    expect(toolCall.toolId, 'semantic_search_current_book');
    expect(toolCall.status, 'running');
    expect(toolCall.query, 'working memory');
    expect(toolCall.text, 'Returned 2 traceable chunks.');
    expect(toolCall.resultCount, 2);
    expect(toolCall.roleIds, ['critical', 'supportive']);
    expect(toolCall.actionIds, ['wait-tool-call', 'cancel-tool-call']);
    expect(toolCall.evidenceRefs.single.id, 'e1');
    expect(toolCall.evidenceRefs.single.sourceRef?.bookId, 7);
    expect(toolCall.toJson()['agentRunId'], 'seminar-1:role-critical-0');
    expect(toolCall.toJson()['parentRunId'], 'seminar-1');
  });

  test('maps terminal Seminar tool calls to completed timestamps', () {
    final completedAt = DateTime.utc(2026, 6, 4, 16, 0, 2);
    final erroredAt = DateTime.utc(2026, 6, 4, 16, 0, 3);
    final interruptedAt = DateTime.utc(2026, 6, 4, 16, 0, 4);
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:tool:notes:running',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.toolCall,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        status: SubAgentRunStatus.running,
        toolId: 'notes_search',
        query: 'agency notes',
        roleIds: const ['critical'],
      ),
      AgentRunEvent(
        eventId: 'seminar-1:tool:semantic-search:completed',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.toolCall,
        createdAt: completedAt,
        status: SubAgentRunStatus.completed,
        toolId: 'semantic_search_current_book',
        query: 'agency notes',
        result: 'Returned semantic evidence.',
        roleIds: const ['critical'],
      ),
      AgentRunEvent(
        eventId: 'seminar-1:tool:memory:errored',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.toolCall,
        createdAt: erroredAt,
        status: SubAgentRunStatus.errored,
        toolId: 'memory_search',
        query: 'agency notes',
        error: 'memory index unavailable',
        roleIds: const ['critical'],
      ),
      AgentRunEvent(
        eventId: 'seminar-1:tool:concept-graph:interrupted',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.toolCall,
        createdAt: interruptedAt,
        status: SubAgentRunStatus.interrupted,
        toolId: 'concept_graph_search',
        query: 'agency map',
        error: 'tool call was interrupted',
        roleIds: const ['critical'],
      ),
    ]);

    final byToolId = {
      for (final part in parts.where((part) => part.type == 'tool_call'))
        part.toolId: part,
    };
    expect(byToolId['notes_search']?.completedAt, isNull);
    expect(
      byToolId['notes_search']?.startedAt,
      DateTime.utc(2026, 6, 4, 16).millisecondsSinceEpoch,
    );
    expect(
      byToolId['semantic_search_current_book']?.completedAt,
      completedAt.millisecondsSinceEpoch,
    );
    expect(
      byToolId['memory_search']?.completedAt,
      erroredAt.millisecondsSinceEpoch,
    );
    expect(
      byToolId['concept_graph_search']?.completedAt,
      interruptedAt.millisecondsSinceEpoch,
    );
  });

  test('restores evidence block from graph tool call evidence refs', () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:tool:current-book:completed',
        runId: 'seminar-1:tool:current-book',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.toolCall,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        status: SubAgentRunStatus.completed,
        toolId: 'semantic_search_current_book',
        query: 'working memory',
        result: 'Returned 2 traceable chunks.',
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
          AiSeminarRunCardEvidenceSnapshot(
            id: 'e2',
            title: 'Chapter 3',
            snippet: 'Attention control evidence.',
            sourceRef: SourceRef(
              bookId: 7,
              cfi: 'epubcfi(/6/4)',
              sourceKind: SourceRefKind.currentBookRag,
              sourceTextSnippet: 'Attention control evidence.',
            ),
          ),
        ],
      ),
    ]);

    expect(parts.map((part) => part.type), ['tool_call', 'evidence']);
    final evidencePart = parts.singleWhere((part) => part.type == 'evidence');
    expect(evidencePart.id, 'seminar-1:evidence:tool-call');
    expect(evidencePart.label, 'Evidence snapshot');
    expect(evidencePart.toJson()['parentRunId'], 'seminar-1');
    expect(evidencePart.evidenceRefs.map((item) => item.id), ['e1', 'e2']);
  });

  test('splits graph tool call evidence blocks by tool id', () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:tool:current-book:completed',
        runId: 'seminar-1:tool:current-book',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.toolCall,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        status: SubAgentRunStatus.completed,
        toolId: 'semantic_search_current_book',
        query: 'working memory',
        result: 'Returned current-book evidence.',
        resultCount: 1,
        evidenceRefs: const [
          AiSeminarRunCardEvidenceSnapshot(
            id: 'current-e1',
            title: 'Chapter 2',
            snippet: 'Current-book evidence.',
          ),
        ],
      ),
      AgentRunEvent(
        eventId: 'seminar-1:tool:library:completed',
        runId: 'seminar-1:tool:library',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.toolCall,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 1),
        status: SubAgentRunStatus.completed,
        toolId: 'semantic_search_library',
        query: 'working memory',
        result: 'Returned library evidence.',
        resultCount: 1,
        evidenceRefs: const [
          AiSeminarRunCardEvidenceSnapshot(
            id: 'library-e1',
            title: 'Library result',
            snippet: 'Library evidence.',
          ),
        ],
      ),
    ]);

    final evidenceParts =
        parts.where((part) => part.type == 'evidence').toList(growable: false);

    expect(evidenceParts, hasLength(2));
    expect(
      evidenceParts.map((part) => part.toolId),
      ['semantic_search_current_book', 'semantic_search_library'],
    );
    expect(
      evidenceParts.map((part) => part.evidenceRefs.single.id),
      ['current-e1', 'library-e1'],
    );
  });

  test('drops stale running tool call when terminal tool event exists', () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:tool:current-book:running',
        runId: 'seminar-1:tool:current-book',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.toolCall,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        status: SubAgentRunStatus.running,
        toolId: 'semantic_search_current_book',
        query: 'working memory',
        roleIds: const ['critical'],
      ),
      AgentRunEvent(
        eventId: 'seminar-1:tool:current-book:completed',
        runId: 'seminar-1:tool:current-book',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.toolCall,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 2),
        status: SubAgentRunStatus.completed,
        toolId: 'semantic_search_current_book',
        query: 'working memory',
        result: 'Returned 2 traceable chunks.',
        resultCount: 2,
        roleIds: const ['critical'],
      ),
    ]);

    expect(parts, hasLength(1));
    expect(parts.single.type, 'tool_call');
    expect(parts.single.id, 'seminar-1:tool:current-book:completed');
    expect(parts.single.status, 'completed');
    expect(parts.single.text, 'Returned 2 traceable chunks.');
    expect(parts.single.resultCount, 2);
    expect(
      parts.single.startedAt,
      DateTime.utc(2026, 6, 4, 16).millisecondsSinceEpoch,
    );
    expect(
      parts.single.completedAt,
      DateTime.utc(2026, 6, 4, 16, 0, 2).millisecondsSinceEpoch,
    );
  });

  test('drops stale running tool call when interrupted tool event exists', () {
    final startedAt = DateTime.utc(2026, 6, 4, 16);
    final interruptedAt = DateTime.utc(2026, 6, 4, 16, 0, 2);
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:tool:concept-graph:running',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.toolCall,
        createdAt: startedAt,
        status: SubAgentRunStatus.running,
        toolId: 'concept_graph_search',
        query: 'agency map',
        roleIds: const ['critical'],
      ),
      AgentRunEvent(
        eventId: 'seminar-1:tool:concept-graph:interrupted',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.toolCall,
        createdAt: interruptedAt,
        status: SubAgentRunStatus.interrupted,
        toolId: 'concept_graph_search',
        query: 'agency map',
        error: 'tool call was interrupted',
        roleIds: const ['critical'],
      ),
    ]);

    expect(parts, hasLength(1));
    expect(parts.single.type, 'tool_call');
    expect(parts.single.id, 'seminar-1:tool:concept-graph:interrupted');
    expect(parts.single.status, 'interrupted');
    expect(parts.single.startedAt, startedAt.millisecondsSinceEpoch);
    expect(parts.single.completedAt, interruptedAt.millisecondsSinceEpoch);
  });

  test('keeps repeated tool calls with distinct call ids', () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:tool:call-notes-1',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.toolCall,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        status: SubAgentRunStatus.completed,
        toolId: 'notes_search',
        query: 'agency notes',
        result: 'Returned the first note match.',
        resultCount: 1,
        roleIds: const ['critical'],
      ),
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:tool:call-notes-2',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.toolCall,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 2),
        status: SubAgentRunStatus.completed,
        toolId: 'notes_search',
        query: 'agency notes',
        result: 'Returned the second note match.',
        resultCount: 1,
        roleIds: const ['critical'],
      ),
    ]);

    final toolCalls =
        parts.where((part) => part.type == 'tool_call').toList(growable: false);
    expect(toolCalls.map((part) => part.id), [
      'seminar-1:role-critical-0:tool:call-notes-1',
      'seminar-1:role-critical-0:tool:call-notes-2',
    ]);
    expect(toolCalls.map((part) => part.text), [
      'Returned the first note match.',
      'Returned the second note match.',
    ]);
  });

  test('keeps only latest event when replay includes duplicate event ids', () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:tool:call-notes',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.toolCall,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        status: SubAgentRunStatus.running,
        toolId: 'notes_search',
        query: 'agency notes',
        roleIds: const ['critical'],
      ),
      AgentRunEvent(
        eventId: 'seminar-1:role-critical-0:tool:call-notes',
        runId: 'seminar-1:role-critical-0',
        parentRunId: 'seminar-1',
        type: AgentRunEventType.toolCall,
        createdAt: DateTime.utc(2026, 6, 4, 16, 0, 2),
        status: SubAgentRunStatus.completed,
        toolId: 'notes_search',
        query: 'agency notes',
        result: 'Returned 1 note match.',
        resultCount: 1,
        roleIds: const ['critical'],
      ),
    ]);

    expect(parts, hasLength(1));
    expect(parts.single.id, 'seminar-1:role-critical-0:tool:call-notes');
    expect(parts.single.type, 'tool_call');
    expect(parts.single.status, 'completed');
    expect(parts.single.text, 'Returned 1 note match.');
  });

  test('drops non-Seminar and empty delta events without fabricating parts',
      () {
    final parts = seminarMessagePartsFromAgentRunEvents([
      AgentRunEvent(
        eventId: 'status-1',
        runId: 'run-1',
        type: AgentRunEventType.status,
        createdAt: DateTime.utc(2026, 6, 4, 16),
      ),
      AgentRunEvent(
        eventId: 'empty-delta-1',
        runId: 'run-1',
        type: AgentRunEventType.messageDelta,
        createdAt: DateTime.utc(2026, 6, 4, 16),
        roleId: 'critical',
        delta: '   ',
      ),
    ]);

    expect(parts, isEmpty);
  });
}
