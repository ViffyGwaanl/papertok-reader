import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_agent_governance.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/ai/index.dart';
import 'package:papertok_reader/service/ai/agent_run_event_message_part_adapter.dart';
import 'package:papertok_reader/service/ai/agent_run_graph_store.dart';
import 'package:papertok_reader/service/ai/agent_tool_call_event.dart';
import 'package:papertok_reader/service/ai/ai_seminar_orchestration_service.dart';
import 'package:papertok_reader/service/ai/ai_seminar_runtime_service.dart';
import 'package:papertok_reader/service/ai/sub_agent_runner.dart';

void main() {
  SourceRef traceableRef() => SourceRef(
        bookId: 7,
        href: 'Text/ch.xhtml',
        cfi: 'epubcfi(/6/8)',
        jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
        sourceTextSnippet: 'The source passage.',
        sourceKind: SourceRefKind.currentBookRag,
      );

  AiSeminarEvidenceBundle bundle() => AiSeminarEvidenceBundle(
        query: 'What is the claim?',
        evidence: [
          AiSeminarEvidence(
            id: 'e1',
            scope: AiSeminarEvidenceScope.currentBook,
            text: 'The source passage.',
            sourceRef: traceableRef(),
          ),
        ],
      );

  AiSeminarEvidenceBundle mixedScopeBundle() => AiSeminarEvidenceBundle(
        query: 'Compare the claims.',
        evidence: [
          AiSeminarEvidence(
            id: 'current-evidence',
            scope: AiSeminarEvidenceScope.currentBook,
            text: 'The source passage.',
            sourceRef: traceableRef(),
          ),
          AiSeminarEvidence(
            id: 'library-evidence',
            scope: AiSeminarEvidenceScope.library,
            text: 'The library passage.',
            sourceRef: SourceRef(
              bookId: 8,
              href: 'Text/other.xhtml',
              jumpLink: 'paperreader://reader/open?bookId=8',
              sourceTextSnippet: 'The library passage.',
              sourceKind: SourceRefKind.libraryRag,
            ),
          ),
        ],
      );

  test('streams evidence roles whiteboard and synthesis events', () async {
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          partialText: '${invocation.role.asString} partial',
        );
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
            whiteboardEntries: [
              if (invocation.role == AiSeminarRole.critical)
                const AiSeminarWhiteboardEntry(
                  id: 'w1',
                  kind: AiSeminarWhiteboardKind.disagreement,
                  text: 'The claim needs narrower evidence.',
                  evidenceRefIds: ['e1'],
                ),
            ],
          ),
        );
      },
      now: () => 1000,
    );

    final events = await service
        .run(AiSeminarSessionContract(id: 's1', question: 'What is it?'))
        .toList();

    expect(
        events.map((event) => event.type),
        containsAllInOrder([
          AiSeminarRuntimeEventType.sessionStarted,
          AiSeminarRuntimeEventType.evidenceReady,
          AiSeminarRuntimeEventType.roleStarted,
          AiSeminarRuntimeEventType.roleDelta,
          AiSeminarRuntimeEventType.roleCompleted,
          AiSeminarRuntimeEventType.whiteboardUpdated,
          AiSeminarRuntimeEventType.synthesisReady,
        ]));
    final completed = events.last;
    expect(completed.run!.status, AiSeminarRunStatus.completed);
    expect(completed.run!.readyForReview, true);
    expect(completed.synthesis!.criticalView, 'critical response');
    expect(completed.whiteboardEntries.single.id, 'w1');
  });

  test('writes completed Seminar role turns to agent graph', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-role-graph-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
            startedAt: 1000,
            completedAt: 1100,
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1000,
    );

    await service
        .run(
          AiSeminarSessionContract(
            id: 'seminar-parent-run',
            question: 'What is it?',
            roleProfiles: [
              AiSeminarRoleProfile(
                role: AiSeminarRole.supportive,
                enabled: false,
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.synthesizer,
                enabled: false,
              ),
            ],
          ),
        )
        .toList();

    final children = await graphStore.listChildren('seminar-parent-run');
    expect(children.map((entry) => entry.run.runId), [
      'seminar-parent-run:role-critical-0',
      'seminar-parent-run:role-synthesizer-1',
    ]);

    final critical = children.first.run;
    expect(critical.source, 'seminar');
    expect(critical.roleId, 'critical');
    expect(critical.profile, 'critical');
    expect(critical.nickname, 'Critical');
    expect(critical.task, 'What is it?');
    expect(critical.result, 'critical response');
    expect(
      critical.startedAt,
      DateTime.fromMillisecondsSinceEpoch(1000),
    );
    expect(
      critical.finishedAt,
      DateTime.fromMillisecondsSinceEpoch(1100),
    );
    expect(children.first.edge.status, AgentRunEdgeStatus.closed);

    final synthesizer = children.last.run;
    expect(synthesizer.roleId, 'synthesizer');
    expect(synthesizer.nickname, 'Synthesizer');
    expect(synthesizer.result, 'synthesizer response');

    final criticalEvents = await graphStore.listEvents(
      'seminar-parent-run:role-critical-0',
    );
    expect(criticalEvents.map((event) => event.type), [
      AgentRunEventType.status,
      AgentRunEventType.thinking,
      AgentRunEventType.status,
      AgentRunEventType.result,
    ]);
    expect(criticalEvents.first.parentRunId, 'seminar-parent-run');
    expect(criticalEvents.first.status, SubAgentRunStatus.running);
    expect(criticalEvents[1].delta,
        'Critical is preparing an evidence-grounded seminar response.');
    expect(criticalEvents[2].status, SubAgentRunStatus.completed);
    expect(criticalEvents.first.roleId, 'critical');
    expect(criticalEvents.last.result, 'critical response');
    expect(criticalEvents.last.evidenceRefs.single.id, 'e1');
    expect(criticalEvents.last.evidenceRefs.single.sourceRef?.bookId, 7);
  });

  test('writes Seminar parent director run lifecycle to agent graph', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-parent-lifecycle-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    var nowMs = 1000;
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
            startedAt: nowMs,
            completedAt: nowMs + 50,
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => nowMs += 100,
    );

    await service
        .run(
          AiSeminarSessionContract(
            id: 'seminar-parent-lifecycle',
            question: 'What is it?',
            maxRounds: 2,
            roleProfiles: [
              AiSeminarRoleProfile(
                role: AiSeminarRole.supportive,
                enabled: false,
              ),
            ],
          ),
        )
        .toList();

    final parent = await graphStore.getRun('seminar-parent-lifecycle');
    expect(parent, isNotNull);
    expect(parent!.source, 'seminar');
    expect(parent.parentRunId, isNull);
    expect(parent.profile, 'director');
    expect(parent.roleId, 'director');
    expect(parent.nickname, 'Director');
    expect(parent.status, SubAgentRunStatus.completed);
    expect(parent.task, 'What is it?');
    expect(parent.maxSteps, 2);
    expect(parent.agentScene, AiAgentScene.seminar);
    expect(parent.result, 'synthesizer response');

    final parentEvents = await graphStore.listEvents(
      'seminar-parent-lifecycle',
    );
    expect(parentEvents.map((event) => event.type), [
      AgentRunEventType.status,
      AgentRunEventType.thinking,
      AgentRunEventType.thinking,
      AgentRunEventType.status,
      AgentRunEventType.result,
    ]);
    expect(parentEvents.first.status, SubAgentRunStatus.running);
    expect(parentEvents[1].eventId,
        'seminar-parent-lifecycle:thinking:evidence_collection');
    expect(
        parentEvents[2].eventId, 'seminar-parent-lifecycle:thinking:synthesis');
    expect(parentEvents[3].status, SubAgentRunStatus.completed);
    expect(parentEvents.last.result, 'synthesizer response');
    expect(parentEvents.last.evidenceRefs.single.id, 'e1');
    expect(parentEvents.last.evidenceRefs.single.sourceRef?.bookId, 7);

    final toolEvents = await graphStore
        .listEvents('seminar-parent-lifecycle:tool:current-book');
    expect(toolEvents, hasLength(1));
    expect(toolEvents.single.type, AgentRunEventType.toolCall);
    expect(toolEvents.single.status, SubAgentRunStatus.completed);
    expect(toolEvents.single.result, 'Returned 1 traceable evidence chunk.');
    expect(toolEvents.single.resultCount, 1);
  });

  test('writes Director evidence collection thinking event to agent graph',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-director-evidence-thinking-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) => throw StateError('index unavailable'),
      streamRole: (_, __) => const Stream<AiSeminarRoleStreamChunk>.empty(),
      agentRunGraphStore: graphStore,
      now: () => 1000,
    );
    final session = AiSeminarSessionContract(
      id: 'seminar-director-evidence-thinking',
      question: 'Where does the book define attention?',
    );

    await service.run(session).toList();

    final parentEvents = await graphStore.listEvents(session.id);
    final thinkingEvent = parentEvents.singleWhere(
      (event) => event.eventId == '${session.id}:thinking:evidence_collection',
    );
    expect(thinkingEvent.type, AgentRunEventType.thinking);
    expect(thinkingEvent.roleId, 'director');
    expect(thinkingEvent.nickname, 'Director');
    expect(
      thinkingEvent.delta,
      'Director is collecting traceable evidence for the seminar.',
    );
  });

  test('writes Director synthesis thinking event to agent graph', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-director-synthesis-thinking-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1000,
    );
    final session = AiSeminarSessionContract(
      id: 'seminar-director-synthesis-thinking',
      question: 'What should be retained?',
      roleProfiles: [
        AiSeminarRoleProfile(
          role: AiSeminarRole.supportive,
          enabled: false,
        ),
      ],
    );

    await service.run(session).toList();

    final parentEvents = await graphStore.listEvents(session.id);
    final thinkingEvent = parentEvents.singleWhere(
      (event) => event.eventId == '${session.id}:thinking:synthesis',
    );
    expect(thinkingEvent.type, AgentRunEventType.thinking);
    expect(thinkingEvent.roleId, 'director');
    expect(thinkingEvent.nickname, 'Director');
    expect(
      thinkingEvent.delta,
      'Director is synthesizing the seminar into traceable conclusions.',
    );
  });

  test('writes Seminar role thinking event before role stream', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-role-thinking-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1000,
    );
    const sessionId = 'seminar-role-thinking';

    await service
        .run(
          AiSeminarSessionContract(
            id: sessionId,
            question: 'What should the critical role inspect?',
            roleProfiles: [
              AiSeminarRoleProfile(
                role: AiSeminarRole.supportive,
                enabled: false,
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.synthesizer,
                enabled: false,
              ),
            ],
          ),
        )
        .toList();

    final roleRunId = '$sessionId:role-critical-0';
    final roleEvents = await graphStore.listEvents(roleRunId);
    final thinkingEvent = roleEvents.singleWhere(
      (event) => event.eventId == '$roleRunId:thinking:start',
    );
    expect(thinkingEvent.type, AgentRunEventType.thinking);
    expect(thinkingEvent.parentRunId, sessionId);
    expect(thinkingEvent.roleId, AiSeminarRole.critical.asString);
    expect(thinkingEvent.nickname, seminarRoleNickname(AiSeminarRole.critical));
    expect(
      thinkingEvent.delta,
      'Critical is preparing an evidence-grounded seminar response.',
    );
  });

  test('writes failed Seminar parent director run when evidence fetch fails',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-parent-fetch-failed-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    var nowMs = 1000;
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) => throw StateError('index unavailable'),
      streamRole: (_, __) => const Stream<AiSeminarRoleStreamChunk>.empty(),
      agentRunGraphStore: graphStore,
      now: () => nowMs += 100,
    );

    final events = await service
        .run(AiSeminarSessionContract(
          id: 'seminar-parent-fetch-failed',
          question: 'What failed?',
        ))
        .toList();

    expect(events.last.type, AiSeminarRuntimeEventType.failed);
    expect(events.last.message, contains('index unavailable'));

    final parent = await graphStore.getRun('seminar-parent-fetch-failed');
    expect(parent, isNotNull);
    expect(parent!.status, SubAgentRunStatus.errored);
    expect(parent.error, contains('index unavailable'));
    final parentEvents = await graphStore.listEvents(
      'seminar-parent-fetch-failed',
    );
    expect(
        parentEvents
            .map((event) => event.status)
            .whereType<SubAgentRunStatus>(),
        [
          SubAgentRunStatus.running,
          SubAgentRunStatus.errored,
        ]);
    expect(parentEvents.last.error, contains('index unavailable'));

    final toolEvents = await graphStore.listChildEvents(
      'seminar-parent-fetch-failed',
    );
    final toolCall = toolEvents.singleWhere(
      (event) => event.type == AgentRunEventType.toolCall,
    );
    expect(toolCall.toolId, 'semantic_search_current_book');
    expect(toolCall.status, SubAgentRunStatus.errored);
    expect(toolCall.query, 'What failed?');
    expect(toolCall.roleIds, ['critical', 'supportive', 'synthesizer']);
    expect(toolCall.error, contains('index unavailable'));
  });

  test('writes interrupted Seminar parent director run for evidence gaps',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-parent-needs-evidence-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    var nowMs = 1000;
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => const AiSeminarEvidenceBundle(
        query: 'missing source evidence',
        evidence: <AiSeminarEvidence>[],
      ),
      streamRole: (_, __) => const Stream<AiSeminarRoleStreamChunk>.empty(),
      agentRunGraphStore: graphStore,
      now: () => nowMs += 100,
    );

    final events = await service
        .run(AiSeminarSessionContract(
          id: 'seminar-parent-needs-evidence',
          question: 'Needs evidence?',
        ))
        .toList();

    expect(events.last.type, AiSeminarRuntimeEventType.needsEvidence);
    expect(events.last.message, contains('traceable current-source evidence'));

    final parent = await graphStore.getRun('seminar-parent-needs-evidence');
    expect(parent, isNotNull);
    expect(parent!.status, SubAgentRunStatus.interrupted);
    final parentEvents = await graphStore.listEvents(
      'seminar-parent-needs-evidence',
    );
    expect(
        parentEvents
            .map((event) => event.status)
            .whereType<SubAgentRunStatus>(),
        [
          SubAgentRunStatus.running,
          SubAgentRunStatus.interrupted,
        ]);
    const childRunId = 's2:role-critical-0';
    final child = await graphStore.getRun(childRunId);
    expect(child, isNotNull);
    expect(child!.status, SubAgentRunStatus.shutdown);
    expect(child.finishedAt, isNotNull);
    expect(child.error, contains('cancelled'));
    final childEvents = await graphStore.listEvents(childRunId);
    expect(
      childEvents.map((event) => event.status).whereType<SubAgentRunStatus>(),
      [
        SubAgentRunStatus.running,
        SubAgentRunStatus.shutdown,
      ],
    );
    final openChildren = await graphStore.listOpenChildren('s2');
    expect(openChildren, isEmpty);
  });

  test('closes role child run when role cites missing evidence', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-role-missing-evidence-child-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    var nowMs = 1000;
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['missing-evidence'],
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => nowMs += 100,
    );

    final events = await service
        .run(AiSeminarSessionContract(
          id: 'seminar-role-missing-evidence-child',
          question: 'Needs role evidence?',
        ))
        .toList();

    expect(events.last.type, AiSeminarRuntimeEventType.needsEvidence);
    expect(
      events.last.message,
      contains('cited missing or untraceable evidence'),
    );

    const childRunId = 'seminar-role-missing-evidence-child:role-critical-0';
    final child = await graphStore.getRun(childRunId);
    expect(child, isNotNull);
    expect(child!.status, SubAgentRunStatus.interrupted);
    expect(child.finishedAt, isNotNull);
    expect(child.error, contains('cited missing or untraceable evidence'));

    final childEvents = await graphStore.listEvents(childRunId);
    expect(
      childEvents.map((event) => event.status).whereType<SubAgentRunStatus>(),
      [
        SubAgentRunStatus.running,
        SubAgentRunStatus.interrupted,
      ],
    );
    final openChildren = await graphStore
        .listOpenChildren('seminar-role-missing-evidence-child');
    expect(openChildren.map((entry) => entry.run.runId), [childRunId]);
    expect(openChildren.single.run.status, SubAgentRunStatus.interrupted);
  });

  test('marks role child run errored when role stream fails', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-role-stream-error-child-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    var nowMs = 1000;
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (_, __) async* {
        throw StateError('provider timeout');
      },
      agentRunGraphStore: graphStore,
      now: () => nowMs += 100,
    );

    final events = await service
        .run(AiSeminarSessionContract(
          id: 'seminar-role-stream-error-child',
          question: 'What failed?',
        ))
        .toList();

    expect(events.last.type, AiSeminarRuntimeEventType.failed);
    expect(events.last.message, contains('provider timeout'));

    const childRunId = 'seminar-role-stream-error-child:role-critical-0';
    final child = await graphStore.getRun(childRunId);
    expect(child, isNotNull);
    expect(child!.status, SubAgentRunStatus.errored);
    expect(child.finishedAt, isNotNull);
    expect(child.error, contains('provider timeout'));

    final childEvents = await graphStore.listEvents(childRunId);
    expect(
      childEvents.map((event) => event.status).whereType<SubAgentRunStatus>(),
      [
        SubAgentRunStatus.running,
        SubAgentRunStatus.errored,
      ],
    );
    final openChildren =
        await graphStore.listOpenChildren('seminar-role-stream-error-child');
    expect(openChildren, isEmpty);
  });

  test('marks role child run errored when role produces no turn', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-role-no-turn-child-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    var nowMs = 1000;
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (_, __) => const Stream<AiSeminarRoleStreamChunk>.empty(),
      agentRunGraphStore: graphStore,
      now: () => nowMs += 100,
    );

    final events = await service
        .run(AiSeminarSessionContract(
          id: 'seminar-role-no-turn-child',
          question: 'What produced no turn?',
        ))
        .toList();

    expect(events.last.type, AiSeminarRuntimeEventType.failed);
    expect(events.last.message, contains('produced no turn'));

    const childRunId = 'seminar-role-no-turn-child:role-critical-0';
    final child = await graphStore.getRun(childRunId);
    expect(child, isNotNull);
    expect(child!.status, SubAgentRunStatus.errored);
    expect(child.finishedAt, isNotNull);
    expect(child.error, contains('produced no turn'));
    final openChildren =
        await graphStore.listOpenChildren('seminar-role-no-turn-child');
    expect(openChildren, isEmpty);
  });

  test('marks role child run errored when role returns failed turn', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-role-failed-turn-child-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    var nowMs = 1000;
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-failed-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '',
            evidenceRefIds: const ['e1'],
            error: 'provider returned malformed role JSON',
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => nowMs += 100,
    );

    final events = await service
        .run(AiSeminarSessionContract(
          id: 'seminar-role-failed-turn-child',
          question: 'What failed as a turn?',
        ))
        .toList();

    expect(events.last.type, AiSeminarRuntimeEventType.failed);
    expect(events.last.message, contains('malformed role JSON'));

    const childRunId = 'seminar-role-failed-turn-child:role-critical-0';
    final child = await graphStore.getRun(childRunId);
    expect(child, isNotNull);
    expect(child!.status, SubAgentRunStatus.errored);
    expect(child.finishedAt, isNotNull);
    expect(child.error, contains('malformed role JSON'));
    final openChildren =
        await graphStore.listOpenChildren('seminar-role-failed-turn-child');
    expect(openChildren, isEmpty);
  });

  test('marks role child run errored when executor returns wrong role',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-role-wrong-role-child-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    var nowMs = 1000;
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-wrong-role-${invocation.role.asString}',
            role: AiSeminarRole.supportive,
            prompt: invocation.prompt,
            responseText: 'supportive response',
            evidenceRefIds: const ['e1'],
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => nowMs += 100,
    );

    final events = await service
        .run(AiSeminarSessionContract(
          id: 'seminar-role-wrong-role-child',
          question: 'What returned the wrong role?',
        ))
        .toList();

    expect(events.last.type, AiSeminarRuntimeEventType.failed);
    expect(events.last.message, contains('supportive for critical'));

    const childRunId = 'seminar-role-wrong-role-child:role-critical-0';
    final child = await graphStore.getRun(childRunId);
    expect(child, isNotNull);
    expect(child!.status, SubAgentRunStatus.errored);
    expect(child.finishedAt, isNotNull);
    expect(child.error, contains('supportive for critical'));
    final openChildren =
        await graphStore.listOpenChildren('seminar-role-wrong-role-child');
    expect(openChildren, isEmpty);
  });

  test('writes live Seminar role partial deltas to agent events', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-role-delta-event-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          partialText: '${invocation.role.asString} partial',
        );
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
            startedAt: 1000,
            completedAt: 1100,
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1000,
    );

    await service
        .run(
          AiSeminarSessionContract(
            id: 'seminar-live-run',
            question: 'What is it?',
            bookId: 7,
            roleProfiles: [
              AiSeminarRoleProfile(
                role: AiSeminarRole.critical,
                allowedToolIds: const [
                  'semantic_search_current_book',
                  'notes_search',
                ],
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.supportive,
                enabled: false,
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.synthesizer,
                enabled: false,
              ),
            ],
          ),
        )
        .toList();

    final criticalEvents = await graphStore.listEvents(
      'seminar-live-run:role-critical-0',
    );
    expect(criticalEvents.map((event) => event.type), [
      AgentRunEventType.status,
      AgentRunEventType.toolCall,
      AgentRunEventType.thinking,
      AgentRunEventType.messageDelta,
      AgentRunEventType.status,
      AgentRunEventType.result,
    ]);
    expect(criticalEvents.first.status, SubAgentRunStatus.running);
    expect(criticalEvents.first.allowedToolIds, [
      'semantic_search_current_book',
      'notes_search',
    ]);
    final roleToolCall = criticalEvents.singleWhere(
      (event) => event.type == AgentRunEventType.toolCall,
    );
    expect(
      roleToolCall.eventId,
      'seminar-live-run:role-critical-0:tool:semantic_search_current_book',
    );
    expect(roleToolCall.runId, 'seminar-live-run:role-critical-0');
    expect(roleToolCall.parentRunId, 'seminar-live-run');
    expect(roleToolCall.status, SubAgentRunStatus.completed);
    expect(roleToolCall.toolId, 'semantic_search_current_book');
    expect(roleToolCall.query, 'What is the claim?');
    expect(roleToolCall.resultCount, 1);
    expect(roleToolCall.roleIds, ['critical']);
    expect(roleToolCall.evidenceRefs.single.id, 'e1');
    expect(
      criticalEvents
          .where((event) => event.type == AgentRunEventType.toolCall)
          .map((event) => event.toolId),
      ['semantic_search_current_book'],
    );
    expect(criticalEvents[2].delta,
        'Critical is preparing an evidence-grounded seminar response.');
    expect(criticalEvents[3].delta, 'critical partial');
    expect(criticalEvents[4].status, SubAgentRunStatus.completed);
    expect(criticalEvents[4].allowedToolIds, [
      'semantic_search_current_book',
      'notes_search',
    ]);
    expect(criticalEvents.last.result, 'critical response');
  });

  test('writes streamed Seminar role thinking summaries to agent events',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-role-stream-thinking-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        yield const AiSeminarRoleStreamChunk(
          thinkingText: 'Checking note and semantic evidence.',
        );
        yield AiSeminarRoleStreamChunk(
          partialText: '${invocation.role.asString} partial',
        );
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
            startedAt: 1000,
            completedAt: 1100,
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1000,
    );

    await service
        .run(
          AiSeminarSessionContract(
            id: 'seminar-stream-thinking',
            question: 'What is it?',
            bookId: 7,
            roleProfiles: [
              AiSeminarRoleProfile(
                role: AiSeminarRole.critical,
                allowedToolIds: const ['semantic_search_current_book'],
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.supportive,
                enabled: false,
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.synthesizer,
                enabled: false,
              ),
            ],
          ),
        )
        .toList();

    final criticalEvents = await graphStore.listEvents(
      'seminar-stream-thinking:role-critical-0',
    );
    final thinkingEvents = criticalEvents
        .where((event) => event.type == AgentRunEventType.thinking)
        .toList();
    expect(thinkingEvents.map((event) => event.eventId), [
      'seminar-stream-thinking:role-critical-0:thinking:start',
      'seminar-stream-thinking:role-critical-0:thinking:stream:0',
    ]);
    expect(
      thinkingEvents.last.delta,
      'Checking note and semantic evidence.',
    );
    expect(
      criticalEvents.indexOf(thinkingEvents.last),
      lessThan(criticalEvents.indexWhere(
        (event) => event.type == AgentRunEventType.messageDelta,
      )),
    );
  });

  test('records streamed Seminar role tool events on the same child run',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-role-tool-event-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        await invocation.toolCallObserver?.call(const AgentToolCallEvent(
          callId: 'call-notes-1',
          toolId: 'notes_search',
          input: {'query': 'agency notes'},
          status: AgentToolCallEventStatus.running,
        ));
        await invocation.toolCallObserver?.call(const AgentToolCallEvent(
          callId: 'call-notes-1',
          toolId: 'notes_search',
          input: {'query': 'agency notes'},
          status: AgentToolCallEventStatus.completed,
          output: 'Returned 1 note match.',
          resultCount: 1,
        ));
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
            startedAt: 1000,
            completedAt: 1100,
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1000,
    );

    await service
        .run(
          AiSeminarSessionContract(
            id: 'seminar-role-tool-event',
            question: 'What is it?',
            bookId: 7,
            roleProfiles: [
              AiSeminarRoleProfile(
                role: AiSeminarRole.critical,
                allowedToolIds: const [
                  'semantic_search_current_book',
                  'notes_search',
                ],
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.supportive,
                enabled: false,
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.synthesizer,
                enabled: false,
              ),
            ],
          ),
        )
        .toList();

    final toolEvents = (await graphStore.listEvents(
      'seminar-role-tool-event:role-critical-0',
    ))
        .where((event) => event.type == AgentRunEventType.toolCall)
        .toList(growable: false);

    final notesToolCall = toolEvents.singleWhere(
      (event) => event.toolId == 'notes_search',
    );
    expect(
      notesToolCall.eventId,
      'seminar-role-tool-event:role-critical-0:tool:call-notes-1',
    );
    expect(notesToolCall.runId, 'seminar-role-tool-event:role-critical-0');
    expect(notesToolCall.parentRunId, 'seminar-role-tool-event');
    expect(notesToolCall.status, SubAgentRunStatus.completed);
    expect(notesToolCall.query, 'agency notes');
    expect(notesToolCall.result, 'Returned 1 note match.');
    expect(notesToolCall.resultCount, 1);
    expect(notesToolCall.roleIds, ['critical']);
  });

  test('preserves distinct Seminar role tool calls without provider call ids',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-role-tool-empty-call-id-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        await invocation.toolCallObserver?.call(const AgentToolCallEvent(
          callId: '',
          toolId: 'semantic_search_current_book',
          input: {'query': 'first claim'},
          status: AgentToolCallEventStatus.completed,
          output: 'Returned first current-book match.',
          resultCount: 1,
        ));
        await invocation.toolCallObserver?.call(const AgentToolCallEvent(
          callId: '',
          toolId: 'semantic_search_current_book',
          input: {'query': 'second claim'},
          status: AgentToolCallEventStatus.completed,
          output: 'Returned second current-book match.',
          resultCount: 1,
        ));
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
            startedAt: 1000,
            completedAt: 1100,
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1000,
    );

    await service
        .run(
          AiSeminarSessionContract(
            id: 'seminar-role-empty-call-id',
            question: 'What is it?',
            bookId: 7,
            roleProfiles: [
              AiSeminarRoleProfile(
                role: AiSeminarRole.critical,
                allowedToolIds: const ['semantic_search_current_book'],
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.supportive,
                enabled: false,
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.synthesizer,
                enabled: false,
              ),
            ],
          ),
        )
        .toList();

    final toolEvents = (await graphStore.listEvents(
      'seminar-role-empty-call-id:role-critical-0',
    ))
        .where((event) =>
            event.type == AgentRunEventType.toolCall &&
            (event.query == 'first claim' || event.query == 'second claim'))
        .toList(growable: false);

    expect(toolEvents, hasLength(2));
    expect(toolEvents.map((event) => event.query), [
      'first claim',
      'second claim',
    ]);
    expect(toolEvents.map((event) => event.eventId).toSet(), hasLength(2));
  });

  test('filters Seminar role tool events outside the role allowlist', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-role-tool-allowlist-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        await invocation.toolCallObserver?.call(const AgentToolCallEvent(
          callId: 'call-allowed-search',
          toolId: 'semantic_search_current_book',
          input: {'query': 'allowed evidence'},
          status: AgentToolCallEventStatus.completed,
          output: 'Returned allowed evidence.',
          resultCount: 1,
        ));
        await invocation.toolCallObserver?.call(const AgentToolCallEvent(
          callId: 'call-write-memory',
          toolId: 'memory_append',
          input: {'text': 'unapproved write'},
          status: AgentToolCallEventStatus.completed,
          output: 'Wrote memory.',
          resultCount: 1,
        ));
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
            startedAt: 1000,
            completedAt: 1100,
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1000,
    );

    await service
        .run(
          AiSeminarSessionContract(
            id: 'seminar-role-tool-allowlist',
            question: 'What is it?',
            bookId: 7,
            roleProfiles: [
              AiSeminarRoleProfile(
                role: AiSeminarRole.critical,
                allowedToolIds: const ['semantic_search_current_book'],
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.supportive,
                enabled: false,
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.synthesizer,
                enabled: false,
              ),
            ],
          ),
        )
        .toList();

    final toolEvents = (await graphStore.listEvents(
      'seminar-role-tool-allowlist:role-critical-0',
    ))
        .where((event) => event.type == AgentRunEventType.toolCall)
        .toList(growable: false);

    expect(
      toolEvents.map((event) => event.toolId),
      contains('semantic_search_current_book'),
    );
    expect(
      toolEvents.any((event) => event.toolId == 'memory_append'),
      isFalse,
    );
  });

  test('filters library fallback tool events in reading Seminar sessions',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-role-reading-tool-scene-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        await invocation.toolCallObserver?.call(const AgentToolCallEvent(
          callId: 'call-library-search',
          toolId: 'semantic_search_library',
          input: {'query': 'library-wide evidence'},
          status: AgentToolCallEventStatus.completed,
          output: 'Returned library result.',
          resultCount: 1,
        ));
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
            startedAt: 1000,
            completedAt: 1100,
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1000,
    );

    await service
        .run(
          AiSeminarSessionContract(
            id: 'seminar-role-reading-tool-scene',
            question: 'What is it?',
            bookId: 7,
            roleProfiles: [
              AiSeminarRoleProfile(
                role: AiSeminarRole.critical,
                allowedToolIds: const [
                  'semantic_search_current_book',
                  'semantic_search_library',
                ],
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.supportive,
                enabled: false,
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.synthesizer,
                enabled: false,
              ),
            ],
          ),
        )
        .toList();

    final toolEvents = (await graphStore.listEvents(
      'seminar-role-reading-tool-scene:role-critical-0',
    ))
        .where((event) => event.type == AgentRunEventType.toolCall)
        .toList(growable: false);

    expect(
      toolEvents.any((event) => event.toolId == 'semantic_search_library'),
      isFalse,
    );
  });

  test('streams live Seminar role tool call events before role delta',
      () async {
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        await invocation.toolCallObserver?.call(const AgentToolCallEvent(
          callId: 'call-notes-live',
          toolId: 'notes_search',
          input: {'query': 'agency notes'},
          status: AgentToolCallEventStatus.completed,
          output: 'Returned 1 note match.',
          resultCount: 1,
        ));
        yield const AiSeminarRoleStreamChunk(
          partialText: 'critical after notes tool',
        );
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
            startedAt: 1000,
            completedAt: 1100,
          ),
        );
      },
      now: () => 1000,
    );

    final events = await service
        .run(
          AiSeminarSessionContract(
            id: 'seminar-live-tool-event',
            question: 'What is it?',
            roleProfiles: [
              AiSeminarRoleProfile(
                role: AiSeminarRole.critical,
                allowedToolIds: const ['notes_search'],
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.supportive,
                enabled: false,
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.synthesizer,
                enabled: false,
              ),
            ],
          ),
        )
        .toList();

    final toolEventIndex = events.indexWhere(
      (event) => event.type == AiSeminarRuntimeEventType.roleToolCall,
    );
    final roleDeltaIndex = events.indexWhere(
      (event) => event.type == AiSeminarRuntimeEventType.roleDelta,
    );

    expect(toolEventIndex, isNonNegative);
    expect(roleDeltaIndex, isNonNegative);
    expect(toolEventIndex, lessThan(roleDeltaIndex));

    final toolEvent = events[toolEventIndex];
    expect(toolEvent.activeRole, AiSeminarRole.critical);
    expect(toolEvent.agentRunEvent?.eventId,
        'seminar-live-tool-event:role-critical-0:tool:call-notes-live');
    expect(toolEvent.agentRunEvent?.runId,
        'seminar-live-tool-event:role-critical-0');
    expect(toolEvent.agentRunEvent?.parentRunId, 'seminar-live-tool-event');
    expect(toolEvent.agentRunEvent?.toolId, 'notes_search');
    expect(toolEvent.agentRunEvent?.status, SubAgentRunStatus.completed);
    expect(toolEvent.agentRunEvent?.query, 'agency notes');
    expect(toolEvent.agentRunEvent?.result, 'Returned 1 note match.');
    expect(toolEvent.agentRunEvent?.resultCount, 1);
    expect(toolEvent.agentRunEvent?.roleIds, ['critical']);
  });

  test('streams running Seminar role tool calls while role stream is blocked',
      () async {
    final releaseTool = Completer<void>();
    final toolObserverEntered = Completer<void>();
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        await invocation.toolCallObserver?.call(const AgentToolCallEvent(
          callId: 'call-notes-blocked',
          toolId: 'notes_search',
          input: {'query': 'blocked notes'},
          status: AgentToolCallEventStatus.running,
        ));
        if (!toolObserverEntered.isCompleted) {
          toolObserverEntered.complete();
        }
        await releaseTool.future;
        await invocation.toolCallObserver?.call(const AgentToolCallEvent(
          callId: 'call-notes-blocked',
          toolId: 'notes_search',
          input: {'query': 'blocked notes'},
          status: AgentToolCallEventStatus.completed,
          output: 'Returned blocked note.',
          resultCount: 1,
        ));
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
            startedAt: 1000,
            completedAt: 1100,
          ),
        );
      },
      now: () => 1000,
    );

    final runningToolEvent = Completer<AiSeminarRuntimeEvent>();
    final done = Completer<void>();
    late final StreamSubscription<AiSeminarRuntimeEvent> subscription;
    subscription = service
        .run(
      AiSeminarSessionContract(
        id: 'seminar-blocked-tool-event',
        question: 'What is blocked?',
        roleProfiles: [
          AiSeminarRoleProfile(
            role: AiSeminarRole.critical,
            allowedToolIds: const ['notes_search'],
          ),
          AiSeminarRoleProfile(
            role: AiSeminarRole.supportive,
            enabled: false,
          ),
          AiSeminarRoleProfile(
            role: AiSeminarRole.synthesizer,
            enabled: false,
          ),
        ],
      ),
    )
        .listen(
      (event) {
        if (event.type == AiSeminarRuntimeEventType.roleToolCall &&
            event.agentRunEvent?.status == SubAgentRunStatus.running &&
            !runningToolEvent.isCompleted) {
          runningToolEvent.complete(event);
        }
      },
      onDone: done.complete,
      onError: done.completeError,
    );
    addTearDown(() async {
      if (!releaseTool.isCompleted) releaseTool.complete();
      await subscription.cancel();
    });

    await toolObserverEntered.future;
    final toolEvent = await runningToolEvent.future.timeout(
      const Duration(milliseconds: 200),
    );
    expect(toolEvent.activeRole, AiSeminarRole.critical);
    expect(toolEvent.agentRunEvent?.eventId,
        'seminar-blocked-tool-event:role-critical-0:tool:call-notes-blocked');
    expect(toolEvent.agentRunEvent?.runId,
        'seminar-blocked-tool-event:role-critical-0');
    expect(toolEvent.agentRunEvent?.parentRunId, 'seminar-blocked-tool-event');
    expect(toolEvent.agentRunEvent?.toolId, 'notes_search');
    expect(toolEvent.agentRunEvent?.query, 'blocked notes');

    releaseTool.complete();
    await done.future.timeout(const Duration(seconds: 2));
  });

  test('runs pending send-input control event as user directed role', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-control-inbox-consume-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final session = AiSeminarSessionContract(
      id: 'seminar-control-consume',
      question: 'What should continue?',
      roleProfiles: [
        AiSeminarRoleProfile(
          role: AiSeminarRole.supportive,
          enabled: false,
        ),
        AiSeminarRoleProfile(
          role: AiSeminarRole.synthesizer,
          enabled: false,
        ),
      ],
    );
    final childRunId = '${session.id}:role-critical-0';
    await graphStore.upsertFromSeminarSessionStart(
      session: session,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await graphStore.upsertFromSeminarRoleStart(
      session: session,
      role: AiSeminarRole.critical,
      runId: childRunId,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1100),
    );
    await graphStore.upsertRun(AgentRunRecord.fromSeminarRoleStart(
      session: session,
      role: AiSeminarRole.critical,
      runId: childRunId,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1100),
    ).copyWith(status: SubAgentRunStatus.waitingInput));
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: '$childRunId:user-input:1200',
      runId: childRunId,
      parentRunId: session.id,
      type: AgentRunEventType.userInput,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1200),
      roleId: AiSeminarRole.critical.asString,
      nickname: seminarRoleNickname(AiSeminarRole.critical),
      delta: 'Please answer the reader objection.',
    ));

    AiSeminarRoleInvocation? capturedInvocation;
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) => fail('pending control should reuse evidence'),
      streamRole: (invocation, _) async* {
        capturedInvocation = invocation;
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-control-critical',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: 'critical resumed response',
            evidenceRefIds: const ['e1'],
            startedAt: 1300,
            completedAt: 1400,
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1500,
    );

    final events = await service.runPendingAgentControl(
      session,
      childRunId: childRunId,
      evidenceBundle: bundle(),
      priorTurns: const <AiSeminarRoleTurn>[],
    ).toList();

    expect(
      events.map((event) => event.type),
      containsAllInOrder([
        AiSeminarRuntimeEventType.roleStarted,
        AiSeminarRuntimeEventType.roleCompleted,
      ]),
    );
    expect(capturedInvocation?.role, AiSeminarRole.critical);
    expect(
      capturedInvocation?.prompt,
      contains('Please answer the reader objection.'),
    );
    final pendingControls = await graphStore.listPendingControlEvents(
      parentRunId: session.id,
      childRunId: childRunId,
    );
    expect(pendingControls, isEmpty);
    final controlEvent = (await graphStore.listEvents(childRunId))
        .singleWhere((event) => event.eventId == '$childRunId:user-input:1200');
    expect(controlEvent.acknowledgedAt, isNotNull);
    expect(
        controlEvent.acknowledgedAt, DateTime.fromMillisecondsSinceEpoch(1500));
    final followUpEvents = await graphStore.listEvents(childRunId);
    final thinkingEvent = followUpEvents.singleWhere(
      (event) => event.eventId == '$childRunId:thinking:start',
    );
    expect(thinkingEvent.parentRunId, session.id);
    expect(thinkingEvent.roleId, AiSeminarRole.critical.asString);
    expect(
      thinkingEvent.delta,
      'Critical is preparing an evidence-grounded seminar response.',
    );
  });

  test('keeps pending child control unacknowledged when evidence is invalid',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-control-invalid-evidence-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final session = AiSeminarSessionContract(
      id: 'seminar-control-invalid-evidence',
      question: 'What should wait for evidence?',
      roleProfiles: [
        AiSeminarRoleProfile(
          role: AiSeminarRole.supportive,
          enabled: false,
        ),
        AiSeminarRoleProfile(
          role: AiSeminarRole.synthesizer,
          enabled: false,
        ),
      ],
    );
    final childRunId = '${session.id}:role-critical-0';
    await graphStore.upsertFromSeminarSessionStart(
      session: session,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await graphStore.upsertRun(AgentRunRecord.fromSeminarRoleStart(
      session: session,
      role: AiSeminarRole.critical,
      runId: childRunId,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1100),
    ).copyWith(status: SubAgentRunStatus.waitingInput));
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: '$childRunId:user-input:1200',
      runId: childRunId,
      parentRunId: session.id,
      type: AgentRunEventType.userInput,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1200),
      roleId: AiSeminarRole.critical.asString,
      nickname: seminarRoleNickname(AiSeminarRole.critical),
      delta: 'Please continue after better evidence.',
    ));

    final invalidEvidenceBundle = AiSeminarEvidenceBundle(
      query: 'Missing anchored evidence',
      evidence: [
        AiSeminarEvidence(
          id: 'hash-only',
          scope: AiSeminarEvidenceScope.currentBook,
          text: 'Hash-only text without a retrievable source.',
          sourceRef: SourceRef(
            sourceKind: SourceRefKind.currentBookRag,
            sourceTextSnippet: 'Hash-only text without a retrievable source.',
          ),
        ),
      ],
    );
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) => fail('pending control should reuse evidence'),
      streamRole: (_, __) => fail('invalid evidence must not run a role'),
      agentRunGraphStore: graphStore,
      now: () => 1500,
    );

    final events = await service.runPendingAgentControl(
      session,
      childRunId: childRunId,
      evidenceBundle: invalidEvidenceBundle,
      priorTurns: const <AiSeminarRoleTurn>[],
    ).toList();

    expect(events.map((event) => event.type), [
      AiSeminarRuntimeEventType.needsEvidence,
    ]);
    final pendingControls = await graphStore.listPendingControlEvents(
      parentRunId: session.id,
      childRunId: childRunId,
    );
    expect(pendingControls.map((event) => event.eventId), [
      '$childRunId:user-input:1200',
    ]);
    final controlEvent = (await graphStore.listEvents(childRunId))
        .singleWhere((event) => event.eventId == '$childRunId:user-input:1200');
    expect(controlEvent.acknowledgedAt, isNull);
    final child = await graphStore.getRun(childRunId);
    expect(child, isNotNull);
    expect(child!.status, SubAgentRunStatus.interrupted);
    expect(child.finishedAt, isNotNull);
    expect(child.error, contains('traceable current-source evidence'));
    final openChildren = await graphStore.listOpenChildren(session.id);
    expect(openChildren.map((entry) => entry.run.runId), [childRunId]);
    expect(openChildren.single.run.status, SubAgentRunStatus.interrupted);
  });

  test('interrupts pending control child run when prior turns are invalid',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-control-invalid-prior-turns-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final session = AiSeminarSessionContract(
      id: 'seminar-control-invalid-prior-turns',
      question: 'What should wait for better prior turns?',
      roleProfiles: [
        AiSeminarRoleProfile(
          role: AiSeminarRole.supportive,
          enabled: false,
        ),
        AiSeminarRoleProfile(
          role: AiSeminarRole.synthesizer,
          enabled: false,
        ),
      ],
    );
    final childRunId = '${session.id}:role-critical-0';
    await graphStore.upsertFromSeminarSessionStart(
      session: session,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await graphStore.upsertRun(AgentRunRecord.fromSeminarRoleStart(
      session: session,
      role: AiSeminarRole.critical,
      runId: childRunId,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1100),
    ).copyWith(status: SubAgentRunStatus.waitingInput));
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: '$childRunId:user-input:1200',
      runId: childRunId,
      parentRunId: session.id,
      type: AgentRunEventType.userInput,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1200),
      roleId: AiSeminarRole.critical.asString,
      nickname: seminarRoleNickname(AiSeminarRole.critical),
      delta: 'Please continue after invalid prior turns.',
    ));

    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) => fail('pending control should reuse evidence'),
      streamRole: (_, __) => fail('invalid prior turns must not run a role'),
      agentRunGraphStore: graphStore,
      now: () => 1500,
    );

    final events = await service.runPendingAgentControl(
      session,
      childRunId: childRunId,
      evidenceBundle: bundle(),
      priorTurns: const [
        AiSeminarRoleTurn(
          id: 'turn-invalid-prior',
          role: AiSeminarRole.critical,
          prompt: 'invalid prior',
          responseText: 'invalid prior response',
          evidenceRefIds: ['missing-evidence'],
        ),
      ],
    ).toList();

    expect(events.map((event) => event.type), [
      AiSeminarRuntimeEventType.needsEvidence,
    ]);
    final controlEvent = (await graphStore.listEvents(childRunId))
        .singleWhere((event) => event.eventId == '$childRunId:user-input:1200');
    expect(controlEvent.acknowledgedAt, isNull);
    final child = await graphStore.getRun(childRunId);
    expect(child, isNotNull);
    expect(child!.status, SubAgentRunStatus.interrupted);
    expect(child.finishedAt, isNotNull);
    expect(child.error, contains('prior turns need traceable evidence'));
    final openChildren = await graphStore.listOpenChildren(session.id);
    expect(openChildren.map((entry) => entry.run.runId), [childRunId]);
    expect(openChildren.single.run.status, SubAgentRunStatus.interrupted);
  });

  test('interrupts pending control child run when role cites missing evidence',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-control-missing-role-evidence-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final session = AiSeminarSessionContract(
      id: 'seminar-control-missing-role-evidence',
      question: 'What should wait for cited evidence?',
      roleProfiles: [
        AiSeminarRoleProfile(
          role: AiSeminarRole.supportive,
          enabled: false,
        ),
        AiSeminarRoleProfile(
          role: AiSeminarRole.synthesizer,
          enabled: false,
        ),
      ],
    );
    final childRunId = '${session.id}:role-critical-0';
    await graphStore.upsertFromSeminarSessionStart(
      session: session,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await graphStore.upsertRun(AgentRunRecord.fromSeminarRoleStart(
      session: session,
      role: AiSeminarRole.critical,
      runId: childRunId,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1100),
    ).copyWith(status: SubAgentRunStatus.waitingInput));
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: '$childRunId:user-input:1200',
      runId: childRunId,
      parentRunId: session.id,
      type: AgentRunEventType.userInput,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1200),
      roleId: AiSeminarRole.critical.asString,
      nickname: seminarRoleNickname(AiSeminarRole.critical),
      delta: 'Please continue with the known evidence.',
    ));

    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) => fail('pending control should reuse evidence'),
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-control-critical-missing-evidence',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: 'critical response with a bad citation',
            evidenceRefIds: const ['missing-evidence'],
            startedAt: 1300,
            completedAt: 1400,
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1500,
    );

    final events = await service.runPendingAgentControl(
      session,
      childRunId: childRunId,
      evidenceBundle: bundle(),
      priorTurns: const <AiSeminarRoleTurn>[],
    ).toList();

    expect(events.map((event) => event.type), [
      AiSeminarRuntimeEventType.roleStarted,
      AiSeminarRuntimeEventType.needsEvidence,
    ]);
    final controlEvent = (await graphStore.listEvents(childRunId))
        .singleWhere((event) => event.eventId == '$childRunId:user-input:1200');
    expect(controlEvent.acknowledgedAt, isNull);
    final child = await graphStore.getRun(childRunId);
    expect(child, isNotNull);
    expect(child!.status, SubAgentRunStatus.interrupted);
    expect(child.error, contains('cited missing or untraceable evidence'));
  });

  test('marks pending control child run errored when role stream fails',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-control-stream-error-child-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final session = AiSeminarSessionContract(
      id: 'seminar-control-stream-error-child',
      question: 'What should fail visibly?',
      roleProfiles: [
        AiSeminarRoleProfile(
          role: AiSeminarRole.supportive,
          enabled: false,
        ),
        AiSeminarRoleProfile(
          role: AiSeminarRole.synthesizer,
          enabled: false,
        ),
      ],
    );
    final childRunId = '${session.id}:role-critical-0';
    await graphStore.upsertFromSeminarSessionStart(
      session: session,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await graphStore.upsertRun(AgentRunRecord.fromSeminarRoleStart(
      session: session,
      role: AiSeminarRole.critical,
      runId: childRunId,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1100),
    ).copyWith(status: SubAgentRunStatus.waitingInput));
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: '$childRunId:user-input:1200',
      runId: childRunId,
      parentRunId: session.id,
      type: AgentRunEventType.userInput,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1200),
      roleId: AiSeminarRole.critical.asString,
      nickname: seminarRoleNickname(AiSeminarRole.critical),
      delta: 'Please continue, but provider fails.',
    ));

    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) => fail('pending control should reuse evidence'),
      streamRole: (_, __) async* {
        throw StateError('provider timeout');
      },
      agentRunGraphStore: graphStore,
      now: () => 1500,
    );

    final events = await service.runPendingAgentControl(
      session,
      childRunId: childRunId,
      evidenceBundle: bundle(),
      priorTurns: const <AiSeminarRoleTurn>[],
    ).toList();

    expect(events.map((event) => event.type), [
      AiSeminarRuntimeEventType.roleStarted,
      AiSeminarRuntimeEventType.failed,
    ]);
    final controlEvent = (await graphStore.listEvents(childRunId))
        .singleWhere((event) => event.eventId == '$childRunId:user-input:1200');
    expect(controlEvent.acknowledgedAt, isNull);
    final child = await graphStore.getRun(childRunId);
    expect(child, isNotNull);
    expect(child!.status, SubAgentRunStatus.errored);
    expect(child.finishedAt, isNotNull);
    expect(child.error, contains('provider timeout'));
    final openChildren = await graphStore.listOpenChildren(session.id);
    expect(openChildren, isEmpty);
  });

  test('marks pending control child run errored when role produces no turn',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-control-no-turn-child-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final session = AiSeminarSessionContract(
      id: 'seminar-control-no-turn-child',
      question: 'What should fail without a turn?',
      roleProfiles: [
        AiSeminarRoleProfile(
          role: AiSeminarRole.supportive,
          enabled: false,
        ),
        AiSeminarRoleProfile(
          role: AiSeminarRole.synthesizer,
          enabled: false,
        ),
      ],
    );
    final childRunId = '${session.id}:role-critical-0';
    await graphStore.upsertFromSeminarSessionStart(
      session: session,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await graphStore.upsertRun(AgentRunRecord.fromSeminarRoleStart(
      session: session,
      role: AiSeminarRole.critical,
      runId: childRunId,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1100),
    ).copyWith(status: SubAgentRunStatus.waitingInput));
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: '$childRunId:user-input:1200',
      runId: childRunId,
      parentRunId: session.id,
      type: AgentRunEventType.userInput,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1200),
      roleId: AiSeminarRole.critical.asString,
      nickname: seminarRoleNickname(AiSeminarRole.critical),
      delta: 'Please continue, but no turn is produced.',
    ));

    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) => fail('pending control should reuse evidence'),
      streamRole: (_, __) => const Stream<AiSeminarRoleStreamChunk>.empty(),
      agentRunGraphStore: graphStore,
      now: () => 1500,
    );

    final events = await service.runPendingAgentControl(
      session,
      childRunId: childRunId,
      evidenceBundle: bundle(),
      priorTurns: const <AiSeminarRoleTurn>[],
    ).toList();

    expect(events.map((event) => event.type), [
      AiSeminarRuntimeEventType.roleStarted,
      AiSeminarRuntimeEventType.failed,
    ]);
    final controlEvent = (await graphStore.listEvents(childRunId))
        .singleWhere((event) => event.eventId == '$childRunId:user-input:1200');
    expect(controlEvent.acknowledgedAt, isNull);
    final child = await graphStore.getRun(childRunId);
    expect(child, isNotNull);
    expect(child!.status, SubAgentRunStatus.errored);
    expect(child.finishedAt, isNotNull);
    expect(child.error, contains('produced no turn'));
    final openChildren = await graphStore.listOpenChildren(session.id);
    expect(openChildren, isEmpty);
  });

  test('marks pending control child run errored when role returns failed turn',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-control-failed-turn-child-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final session = AiSeminarSessionContract(
      id: 'seminar-control-failed-turn-child',
      question: 'What should fail as a turn?',
      roleProfiles: [
        AiSeminarRoleProfile(
          role: AiSeminarRole.supportive,
          enabled: false,
        ),
        AiSeminarRoleProfile(
          role: AiSeminarRole.synthesizer,
          enabled: false,
        ),
      ],
    );
    final childRunId = '${session.id}:role-critical-0';
    await graphStore.upsertFromSeminarSessionStart(
      session: session,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await graphStore.upsertRun(AgentRunRecord.fromSeminarRoleStart(
      session: session,
      role: AiSeminarRole.critical,
      runId: childRunId,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1100),
    ).copyWith(status: SubAgentRunStatus.waitingInput));
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: '$childRunId:user-input:1200',
      runId: childRunId,
      parentRunId: session.id,
      type: AgentRunEventType.userInput,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1200),
      roleId: AiSeminarRole.critical.asString,
      nickname: seminarRoleNickname(AiSeminarRole.critical),
      delta: 'Please continue, but return a failed turn.',
    ));

    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) => fail('pending control should reuse evidence'),
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-control-failed-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '',
            evidenceRefIds: const ['e1'],
            error: 'provider returned malformed role JSON',
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1500,
    );

    final events = await service.runPendingAgentControl(
      session,
      childRunId: childRunId,
      evidenceBundle: bundle(),
      priorTurns: const <AiSeminarRoleTurn>[],
    ).toList();

    expect(events.map((event) => event.type), [
      AiSeminarRuntimeEventType.roleStarted,
      AiSeminarRuntimeEventType.failed,
    ]);
    final controlEvent = (await graphStore.listEvents(childRunId))
        .singleWhere((event) => event.eventId == '$childRunId:user-input:1200');
    expect(controlEvent.acknowledgedAt, isNull);
    final child = await graphStore.getRun(childRunId);
    expect(child, isNotNull);
    expect(child!.status, SubAgentRunStatus.errored);
    expect(child.finishedAt, isNotNull);
    expect(child.error, contains('malformed role JSON'));
    final openChildren = await graphStore.listOpenChildren(session.id);
    expect(openChildren, isEmpty);
  });

  test(
      'marks pending control child run errored when executor returns wrong role',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-control-wrong-role-child-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final session = AiSeminarSessionContract(
      id: 'seminar-control-wrong-role-child',
      question: 'What should fail as the wrong role?',
      roleProfiles: [
        AiSeminarRoleProfile(
          role: AiSeminarRole.supportive,
          enabled: false,
        ),
        AiSeminarRoleProfile(
          role: AiSeminarRole.synthesizer,
          enabled: false,
        ),
      ],
    );
    final childRunId = '${session.id}:role-critical-0';
    await graphStore.upsertFromSeminarSessionStart(
      session: session,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await graphStore.upsertRun(AgentRunRecord.fromSeminarRoleStart(
      session: session,
      role: AiSeminarRole.critical,
      runId: childRunId,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1100),
    ).copyWith(status: SubAgentRunStatus.waitingInput));
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: '$childRunId:user-input:1200',
      runId: childRunId,
      parentRunId: session.id,
      type: AgentRunEventType.userInput,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1200),
      roleId: AiSeminarRole.critical.asString,
      nickname: seminarRoleNickname(AiSeminarRole.critical),
      delta: 'Please continue, but return the wrong role.',
    ));

    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) => fail('pending control should reuse evidence'),
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-control-wrong-role-${invocation.role.asString}',
            role: AiSeminarRole.supportive,
            prompt: invocation.prompt,
            responseText: 'supportive response',
            evidenceRefIds: const ['e1'],
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1500,
    );

    final events = await service.runPendingAgentControl(
      session,
      childRunId: childRunId,
      evidenceBundle: bundle(),
      priorTurns: const <AiSeminarRoleTurn>[],
    ).toList();

    expect(events.map((event) => event.type), [
      AiSeminarRuntimeEventType.roleStarted,
      AiSeminarRuntimeEventType.failed,
    ]);
    expect(events.last.message, contains('supportive for critical'));
    final controlEvent = (await graphStore.listEvents(childRunId))
        .singleWhere((event) => event.eventId == '$childRunId:user-input:1200');
    expect(controlEvent.acknowledgedAt, isNull);
    final child = await graphStore.getRun(childRunId);
    expect(child, isNotNull);
    expect(child!.status, SubAgentRunStatus.errored);
    expect(child.finishedAt, isNotNull);
    expect(child.error, contains('supportive for critical'));
    final openChildren = await graphStore.listOpenChildren(session.id);
    expect(openChildren, isEmpty);
  });

  test(
      'marks pending control child run errored when role output budget is exceeded',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-control-role-budget-child-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final session = AiSeminarSessionContract(
      id: 'seminar-control-role-budget-child',
      question: 'What should fail by budget?',
      budgetPolicy: const AiSeminarBudgetPolicy(
        maxRoleOutputTokens: 1,
      ),
      roleProfiles: [
        AiSeminarRoleProfile(
          role: AiSeminarRole.supportive,
          enabled: false,
        ),
        AiSeminarRoleProfile(
          role: AiSeminarRole.synthesizer,
          enabled: false,
        ),
      ],
    );
    final childRunId = '${session.id}:role-critical-0';
    await graphStore.upsertFromSeminarSessionStart(
      session: session,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await graphStore.upsertRun(AgentRunRecord.fromSeminarRoleStart(
      session: session,
      role: AiSeminarRole.critical,
      runId: childRunId,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1100),
    ).copyWith(status: SubAgentRunStatus.waitingInput));
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: '$childRunId:user-input:1200',
      runId: childRunId,
      parentRunId: session.id,
      type: AgentRunEventType.userInput,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1200),
      roleId: AiSeminarRole.critical.asString,
      nickname: seminarRoleNickname(AiSeminarRole.critical),
      delta: 'Please continue, but hit the role output budget.',
    ));

    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) => fail('pending control should reuse evidence'),
      streamRole: (_, __) async* {
        yield const AiSeminarRoleStreamChunk(
          partialText:
              'This partial response is intentionally long enough to exceed one local token.',
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1500,
    );

    final events = await service.runPendingAgentControl(
      session,
      childRunId: childRunId,
      evidenceBundle: bundle(),
      priorTurns: const <AiSeminarRoleTurn>[],
    ).toList();

    expect(events.map((event) => event.type), [
      AiSeminarRuntimeEventType.roleStarted,
      AiSeminarRuntimeEventType.failed,
    ]);
    expect(events.last.message, contains('role output token budget'));
    final controlEvent = (await graphStore.listEvents(childRunId))
        .singleWhere((event) => event.eventId == '$childRunId:user-input:1200');
    expect(controlEvent.acknowledgedAt, isNull);
    final child = await graphStore.getRun(childRunId);
    expect(child, isNotNull);
    expect(child!.status, SubAgentRunStatus.errored);
    expect(child.finishedAt, isNotNull);
    expect(child.error, contains('role output token budget'));
    final openChildren = await graphStore.listOpenChildren(session.id);
    expect(openChildren, isEmpty);
  });

  test('writes child terminal status when pending control is cancelled',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-control-cancelled-child-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final session = AiSeminarSessionContract(
      id: 'seminar-control-cancelled-child',
      question: 'What should be cancelled?',
      roleProfiles: [
        AiSeminarRoleProfile(
          role: AiSeminarRole.supportive,
          enabled: false,
        ),
        AiSeminarRoleProfile(
          role: AiSeminarRole.synthesizer,
          enabled: false,
        ),
      ],
    );
    final childRunId = '${session.id}:role-critical-0';
    await graphStore.upsertFromSeminarSessionStart(
      session: session,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await graphStore.upsertRun(AgentRunRecord.fromSeminarRoleStart(
      session: session,
      role: AiSeminarRole.critical,
      runId: childRunId,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1100),
    ).copyWith(status: SubAgentRunStatus.waitingInput));
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: '$childRunId:user-input:1200',
      runId: childRunId,
      parentRunId: session.id,
      type: AgentRunEventType.userInput,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1200),
      roleId: AiSeminarRole.critical.asString,
      nickname: seminarRoleNickname(AiSeminarRole.critical),
      delta: 'Please continue until cancelled.',
    ));

    final token = AiSeminarCancellationToken();
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) => fail('pending control should reuse evidence'),
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          partialText: '${invocation.role.asString} partial before cancel',
        );
        token.cancel();
      },
      agentRunGraphStore: graphStore,
      now: () => 1500,
    );

    final events = await service
        .runPendingAgentControl(
          session,
          childRunId: childRunId,
          evidenceBundle: bundle(),
          priorTurns: const <AiSeminarRoleTurn>[],
          cancelToken: token,
        )
        .toList();

    expect(events.last.type, AiSeminarRuntimeEventType.cancelled);
    final child = await graphStore.getRun(childRunId);
    expect(child?.status, SubAgentRunStatus.shutdown);
    final childEvents = await graphStore.listEvents(childRunId);
    expect(
      childEvents.any(
        (event) =>
            event.type == AgentRunEventType.status &&
            event.status == SubAgentRunStatus.shutdown,
      ),
      isTrue,
    );
    final parts = seminarMessagePartsFromAgentRunEvents(childEvents);
    final readerTurn = parts.singleWhere((part) => part.type == 'reader_turn');
    expect(readerTurn.label, 'send-input');
    expect(readerTurn.status, 'cancelled');
  });

  test('runs pending retry control event on the failed child run id', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-retry-control-consume-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final session = AiSeminarSessionContract(
      id: 'seminar-retry-control',
      question: 'What should be retried?',
      roleProfiles: [
        AiSeminarRoleProfile(
          role: AiSeminarRole.supportive,
          enabled: false,
        ),
        AiSeminarRoleProfile(
          role: AiSeminarRole.synthesizer,
          enabled: false,
        ),
      ],
    );
    final childRunId = '${session.id}:role-critical-0';
    await graphStore.upsertFromSeminarSessionStart(
      session: session,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await graphStore.upsertRun(AgentRunRecord.fromSeminarRoleStart(
      session: session,
      role: AiSeminarRole.critical,
      runId: childRunId,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1100),
    ).copyWith(
      status: SubAgentRunStatus.errored,
      finishedAt: DateTime.fromMillisecondsSinceEpoch(1190),
      error: 'provider timeout',
    ));
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: '$childRunId:retry-request:1200',
      runId: childRunId,
      parentRunId: session.id,
      type: AgentRunEventType.retryRequest,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1200),
      roleId: AiSeminarRole.critical.asString,
      nickname: seminarRoleNickname(AiSeminarRole.critical),
      delta: 'Retry requested.',
    ));

    AiSeminarRoleInvocation? capturedInvocation;
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) => fail('pending retry should reuse evidence'),
      streamRole: (invocation, _) async* {
        capturedInvocation = invocation;
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-retry-critical',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: 'critical retried response',
            evidenceRefIds: const ['e1'],
            startedAt: 1300,
            completedAt: 1400,
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1500,
    );

    await service.runPendingAgentControl(
      session,
      childRunId: childRunId,
      evidenceBundle: bundle(),
      priorTurns: const <AiSeminarRoleTurn>[],
    ).toList();

    expect(capturedInvocation?.role, AiSeminarRole.critical);
    expect(capturedInvocation?.prompt, contains('Retry requested.'));
    final pendingControls = await graphStore.listPendingControlEvents(
      parentRunId: session.id,
      childRunId: childRunId,
    );
    expect(pendingControls, isEmpty);
    final retryEvent = (await graphStore.listEvents(childRunId)).singleWhere(
      (event) => event.eventId == '$childRunId:retry-request:1200',
    );
    expect(retryEvent.acknowledgedAt, isNotNull);
    expect(
      (await graphStore.getRun(childRunId))?.status,
      SubAgentRunStatus.completed,
    );
  });

  test('retry control ignores the failed prior turn for the same child',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-retry-failed-prior-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final session = AiSeminarSessionContract(
      id: 'seminar-retry-failed-prior',
      question: 'What should be regenerated?',
      roleProfiles: [
        AiSeminarRoleProfile(
          role: AiSeminarRole.supportive,
          enabled: false,
        ),
        AiSeminarRoleProfile(
          role: AiSeminarRole.synthesizer,
          enabled: false,
        ),
      ],
    );
    final childRunId = '${session.id}:role-critical-0';
    await graphStore.upsertFromSeminarSessionStart(
      session: session,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await graphStore.upsertRun(AgentRunRecord.fromSeminarRoleStart(
      session: session,
      role: AiSeminarRole.critical,
      runId: childRunId,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1100),
    ).copyWith(
      status: SubAgentRunStatus.errored,
      finishedAt: DateTime.fromMillisecondsSinceEpoch(1190),
      error: 'provider timeout',
    ));
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: '$childRunId:retry-request:1200',
      runId: childRunId,
      parentRunId: session.id,
      type: AgentRunEventType.retryRequest,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1200),
      roleId: AiSeminarRole.critical.asString,
      nickname: seminarRoleNickname(AiSeminarRole.critical),
      delta: 'Retry requested.',
    ));

    AiSeminarRoleInvocation? capturedInvocation;
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) => fail('pending retry should reuse evidence'),
      streamRole: (invocation, _) async* {
        capturedInvocation = invocation;
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-retry-critical-recovered',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: 'critical recovered response',
            evidenceRefIds: const ['e1'],
            startedAt: 1300,
            completedAt: 1400,
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1500,
    );

    final events = await service.runPendingAgentControl(
      session,
      childRunId: childRunId,
      evidenceBundle: bundle(),
      priorTurns: const [
        AiSeminarRoleTurn(
          id: 'turn-failed-critical',
          role: AiSeminarRole.critical,
          prompt: 'failed prompt',
          responseText: '',
          evidenceRefIds: ['e1'],
          error: 'provider timeout',
        ),
      ],
    ).toList();

    expect(
      events.map((event) => event.type),
      containsAllInOrder([
        AiSeminarRuntimeEventType.roleStarted,
        AiSeminarRuntimeEventType.roleCompleted,
      ]),
    );
    expect(capturedInvocation?.role, AiSeminarRole.critical);
    expect(capturedInvocation?.priorTurns, isEmpty);
    final retryEvent = (await graphStore.listEvents(childRunId)).singleWhere(
      (event) => event.eventId == '$childRunId:retry-request:1200',
    );
    expect(retryEvent.acknowledgedAt, isNotNull);
    expect(
      (await graphStore.getRun(childRunId))?.status,
      SubAgentRunStatus.completed,
    );
  });

  test('errored child consumes retry before stale user input', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-retry-priority-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final session = AiSeminarSessionContract(
      id: 'seminar-retry-priority',
      question: 'Which control should run?',
      roleProfiles: [
        AiSeminarRoleProfile(
          role: AiSeminarRole.supportive,
          enabled: false,
        ),
        AiSeminarRoleProfile(
          role: AiSeminarRole.synthesizer,
          enabled: false,
        ),
      ],
    );
    final childRunId = '${session.id}:role-critical-0';
    await graphStore.upsertFromSeminarSessionStart(
      session: session,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await graphStore.upsertRun(AgentRunRecord.fromSeminarRoleStart(
      session: session,
      role: AiSeminarRole.critical,
      runId: childRunId,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1100),
    ).copyWith(
      status: SubAgentRunStatus.errored,
      finishedAt: DateTime.fromMillisecondsSinceEpoch(1190),
      error: 'provider timeout',
    ));
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: '$childRunId:user-input:1200',
      runId: childRunId,
      parentRunId: session.id,
      type: AgentRunEventType.userInput,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1200),
      roleId: AiSeminarRole.critical.asString,
      nickname: seminarRoleNickname(AiSeminarRole.critical),
      delta: 'Old reader input should not win retry.',
    ));
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: '$childRunId:retry-request:1300',
      runId: childRunId,
      parentRunId: session.id,
      type: AgentRunEventType.retryRequest,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1300),
      roleId: AiSeminarRole.critical.asString,
      nickname: seminarRoleNickname(AiSeminarRole.critical),
      delta: 'Retry requested.',
    ));

    AiSeminarRoleInvocation? capturedInvocation;
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) => fail('pending retry should reuse evidence'),
      streamRole: (invocation, _) async* {
        capturedInvocation = invocation;
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-retry-priority-critical',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: 'critical retry priority response',
            evidenceRefIds: const ['e1'],
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1500,
    );

    await service.runPendingAgentControl(
      session,
      childRunId: childRunId,
      evidenceBundle: bundle(),
      priorTurns: const <AiSeminarRoleTurn>[],
    ).toList();

    expect(capturedInvocation?.prompt, contains('Retry requested.'));
    expect(
      capturedInvocation?.prompt,
      isNot(contains('Old reader input should not win retry.')),
    );
    final events = await graphStore.listEvents(childRunId);
    final oldInput = events.singleWhere(
      (event) => event.eventId == '$childRunId:user-input:1200',
    );
    final retry = events.singleWhere(
      (event) => event.eventId == '$childRunId:retry-request:1300',
    );
    expect(oldInput.acknowledgedAt, isNull);
    expect(retry.acknowledgedAt, isNotNull);
  });

  test('runs pending child control on the controlled child run id', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-control-run-id-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final session = AiSeminarSessionContract(
      id: 'seminar-control-run-id',
      question: 'What should continue?',
      roleProfiles: [
        AiSeminarRoleProfile(
          role: AiSeminarRole.synthesizer,
          enabled: false,
        ),
      ],
    );
    final childRunId = '${session.id}:role-critical-0';
    await graphStore.upsertFromSeminarSessionStart(
      session: session,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await graphStore.upsertRun(AgentRunRecord.fromSeminarRoleStart(
      session: session,
      role: AiSeminarRole.critical,
      runId: childRunId,
      startedAt: DateTime.fromMillisecondsSinceEpoch(1100),
    ).copyWith(status: SubAgentRunStatus.waitingInput));
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: '$childRunId:user-input:1200',
      runId: childRunId,
      parentRunId: session.id,
      type: AgentRunEventType.userInput,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1200),
      roleId: AiSeminarRole.critical.asString,
      nickname: seminarRoleNickname(AiSeminarRole.critical),
      delta: 'Please continue this interrupted branch.',
    ));

    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) => fail('pending control should reuse evidence'),
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-control-critical',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: 'critical controlled response',
            evidenceRefIds: const ['e1'],
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1500,
    );

    await service.runPendingAgentControl(
      session,
      childRunId: childRunId,
      evidenceBundle: bundle(),
      priorTurns: const [
        AiSeminarRoleTurn(
          id: 'turn-prior-supportive',
          role: AiSeminarRole.supportive,
          prompt: 'prior prompt',
          responseText: 'prior response',
          evidenceRefIds: ['e1'],
        ),
      ],
    ).toList();

    final controlledEvents = await graphStore.listEvents(childRunId);
    expect(
      controlledEvents.map((event) => event.eventId),
      containsAll([
        '$childRunId:thinking:start',
        '$childRunId:status:completed',
        '$childRunId:result',
      ]),
    );
    expect((await graphStore.getRun(childRunId))?.status,
        SubAgentRunStatus.completed);
    expect(await graphStore.getRun('${session.id}:role-critical-1'), isNull);
  });

  test('writes evidence tool call events to agent graph', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-tool-call-event-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => mixedScopeBundle(),
      streamRole: (invocation, _) async* {
        final evidenceIds = invocation.evidenceBundle.evidence
            .map((item) => item.id)
            .toList(growable: false);
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: evidenceIds,
            startedAt: 1000,
            completedAt: 1100,
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1000,
    );

    await service
        .run(
          AiSeminarSessionContract(
            id: 'seminar-tool-run',
            question: 'Compare the claims.',
            roleProfiles: [
              AiSeminarRoleProfile(
                role: AiSeminarRole.critical,
                evidenceScopes: const [AiSeminarEvidenceScope.currentBook],
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.supportive,
                evidenceScopes: const [AiSeminarEvidenceScope.library],
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.synthesizer,
                evidenceScopes: const [AiSeminarEvidenceScope.currentBook],
              ),
            ],
          ),
        )
        .toList();

    final events = await graphStore.listChildEvents('seminar-tool-run');
    final toolCalls = events
        .where((event) => event.type == AgentRunEventType.toolCall)
        .toList(growable: false);
    expect(toolCalls.map((event) => event.toolId), [
      'semantic_search_current_book',
      'semantic_search_library',
    ]);

    final currentBookCall = toolCalls[0];
    expect(currentBookCall.query, 'Compare the claims.');
    expect(currentBookCall.resultCount, 1);
    expect(currentBookCall.roleIds, ['critical', 'synthesizer']);
    expect(currentBookCall.evidenceRefs.single.id, 'current-evidence');
    expect(currentBookCall.evidenceRefs.single.sourceRef?.bookId, 7);

    final libraryCall = toolCalls[1];
    expect(libraryCall.query, 'Compare the claims.');
    expect(libraryCall.resultCount, 1);
    expect(libraryCall.roleIds, ['supportive']);
    expect(libraryCall.evidenceRefs.single.id, 'library-evidence');
    expect(libraryCall.evidenceRefs.single.sourceRef?.bookId, 8);
  });

  test('writes all evidence refs to evidence tool call graph events', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-tool-call-all-evidence-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final evidenceBundle = AiSeminarEvidenceBundle(
      query: 'Compare all claims.',
      evidence: [
        for (var i = 1; i <= 3; i++)
          AiSeminarEvidence(
            id: 'current-evidence-$i',
            scope: AiSeminarEvidenceScope.currentBook,
            text: 'Current evidence passage $i.',
            sourceRef: traceableRef(),
          ),
      ],
    );
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => evidenceBundle,
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: invocation.evidenceBundle.evidence
                .map((item) => item.id)
                .toList(growable: false),
            startedAt: 1000,
            completedAt: 1100,
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1000,
    );

    await service
        .run(
          AiSeminarSessionContract(
            id: 'seminar-tool-all-evidence-run',
            question: 'Compare all claims.',
            scopes: const [AiSeminarEvidenceScope.currentBook],
          ),
        )
        .toList();

    final currentBookEvents = await graphStore.listEvents(
      'seminar-tool-all-evidence-run:tool:current-book',
    );
    expect(currentBookEvents, hasLength(1));
    final currentBookCall = currentBookEvents.single;
    expect(currentBookCall.type, AgentRunEventType.toolCall);
    expect(currentBookCall.resultCount, 3);
    expect(
      currentBookCall.evidenceRefs.map((item) => item.id),
      ['current-evidence-1', 'current-evidence-2', 'current-evidence-3'],
    );
  });

  test('completes enabled evidence tool calls with zero results', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-tool-call-zero-result-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
            startedAt: 1000,
            completedAt: 1100,
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1000,
    );

    await service
        .run(
          AiSeminarSessionContract(
            id: 'seminar-tool-zero-result-run',
            question: 'Compare the claims.',
            scopes: const [
              AiSeminarEvidenceScope.currentBook,
              AiSeminarEvidenceScope.library,
            ],
            roleProfiles: [
              AiSeminarRoleProfile(
                role: AiSeminarRole.critical,
                evidenceScopes: const [AiSeminarEvidenceScope.currentBook],
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.supportive,
                evidenceScopes: const [AiSeminarEvidenceScope.library],
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.synthesizer,
                evidenceScopes: const [AiSeminarEvidenceScope.currentBook],
              ),
            ],
          ),
        )
        .toList();

    final libraryEvents = await graphStore.listEvents(
      'seminar-tool-zero-result-run:tool:library',
    );
    expect(libraryEvents, hasLength(1));
    final libraryCall = libraryEvents.single;
    expect(libraryCall.type, AgentRunEventType.toolCall);
    expect(libraryCall.status, SubAgentRunStatus.completed);
    expect(libraryCall.toolId, 'semantic_search_library');
    expect(libraryCall.result, 'Returned 0 traceable evidence chunks.');
    expect(libraryCall.resultCount, 0);
    expect(libraryCall.roleIds, ['supportive']);
    expect(libraryCall.evidenceRefs, isEmpty);
  });

  test('maps current chapter tool calls to current book evidence', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-tool-call-current-chapter-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
            startedAt: 1000,
            completedAt: 1100,
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1000,
    );

    await service
        .run(
          AiSeminarSessionContract(
            id: 'seminar-tool-current-chapter-run',
            question: 'Find this chapter evidence.',
            scopes: const [AiSeminarEvidenceScope.currentChapter],
            roleProfiles: [
              AiSeminarRoleProfile(
                role: AiSeminarRole.critical,
                evidenceScopes: const [AiSeminarEvidenceScope.currentChapter],
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.supportive,
                enabled: false,
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.synthesizer,
                evidenceScopes: const [AiSeminarEvidenceScope.currentChapter],
              ),
            ],
          ),
        )
        .toList();

    final currentChapterEvents = await graphStore.listEvents(
      'seminar-tool-current-chapter-run:tool:current-chapter',
    );
    expect(currentChapterEvents, hasLength(1));
    final currentChapterCall = currentChapterEvents.single;
    expect(currentChapterCall.type, AgentRunEventType.toolCall);
    expect(currentChapterCall.status, SubAgentRunStatus.completed);
    expect(currentChapterCall.toolId, 'semantic_search_current_book');
    expect(currentChapterCall.resultCount, 1);
    expect(currentChapterCall.result, 'Returned 1 traceable evidence chunk.');
    expect(currentChapterCall.roleIds, ['critical', 'synthesizer']);
    expect(currentChapterCall.evidenceRefs.single.id, 'e1');
  });

  test('writes all role evidence refs to role tool call graph events',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-role-tool-all-evidence-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final evidenceBundle = AiSeminarEvidenceBundle(
      query: 'Compare role claims.',
      evidence: [
        for (var i = 1; i <= 3; i++)
          AiSeminarEvidence(
            id: 'role-evidence-$i',
            scope: AiSeminarEvidenceScope.currentBook,
            text: 'Role evidence passage $i.',
            sourceRef: traceableRef(),
          ),
      ],
    );
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => evidenceBundle,
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: invocation.evidenceBundle.evidence
                .map((item) => item.id)
                .toList(growable: false),
            startedAt: 1000,
            completedAt: 1100,
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1000,
    );

    await service
        .run(
          AiSeminarSessionContract(
            id: 'seminar-role-tool-all-evidence-run',
            question: 'Compare role claims.',
            bookId: 7,
            scopes: const [AiSeminarEvidenceScope.currentBook],
            roleProfiles: [
              AiSeminarRoleProfile(
                role: AiSeminarRole.critical,
                allowedToolIds: const ['semantic_search_current_book'],
                evidenceScopes: const [AiSeminarEvidenceScope.currentBook],
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.supportive,
                enabled: false,
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.synthesizer,
                enabled: false,
              ),
            ],
          ),
        )
        .toList();

    final roleEvents = await graphStore.listEvents(
      'seminar-role-tool-all-evidence-run:role-critical-0',
    );
    final roleToolCall = roleEvents.singleWhere(
      (event) =>
          event.type == AgentRunEventType.toolCall &&
          event.toolId == 'semantic_search_current_book',
    );
    expect(roleToolCall.resultCount, 3);
    expect(
      roleToolCall.evidenceRefs.map((item) => item.id),
      ['role-evidence-1', 'role-evidence-2', 'role-evidence-3'],
    );
  });

  test('filters streamed role evidence by profile scope', () async {
    final seenEvidenceIds = <AiSeminarRole, List<String>>{};
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => mixedScopeBundle(),
      streamRole: (invocation, _) async* {
        final ids = invocation.evidenceBundle.evidence
            .map((evidence) => evidence.id)
            .toList(growable: false);
        seenEvidenceIds[invocation.role] = ids;
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: ids,
          ),
        );
      },
      now: () => 1000,
    );

    final events = await service
        .run(
          AiSeminarSessionContract(
            id: 's-role-scoped-runtime',
            question: 'Compare the claims.',
            bookId: 7,
            roleProfiles: [
              AiSeminarRoleProfile(
                role: AiSeminarRole.critical,
                evidenceScopes: const [AiSeminarEvidenceScope.currentBook],
              ),
              AiSeminarRoleProfile(
                role: AiSeminarRole.supportive,
                evidenceScopes: const [AiSeminarEvidenceScope.library],
              ),
            ],
          ),
        )
        .toList();

    expect(events.last.run!.status, AiSeminarRunStatus.completed);
    expect(seenEvidenceIds[AiSeminarRole.critical], ['current-evidence']);
    expect(seenEvidenceIds[AiSeminarRole.supportive], ['library-evidence']);
    expect(
      seenEvidenceIds[AiSeminarRole.synthesizer],
      ['current-evidence', 'library-evidence'],
    );
  });

  test('attaches local estimated token usage to completed role turns',
      () async {
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
          ),
        );
      },
      now: () => 1000,
    );

    final events = await service
        .run(AiSeminarSessionContract(id: 's-usage', question: 'Usage?'))
        .toList();
    final completedTurn = events
        .where((event) => event.type == AiSeminarRuntimeEventType.roleCompleted)
        .first
        .turn!;

    expect(completedTurn.tokenUsage, isNotNull);
    expect(completedTurn.tokenUsage!.inputTokens, greaterThan(0));
    expect(completedTurn.tokenUsage!.outputTokens, greaterThan(0));
    expect(
      completedTurn.tokenUsage!.totalTokens,
      completedTurn.tokenUsage!.inputTokens +
          completedTurn.tokenUsage!.outputTokens,
    );
    expect(completedTurn.tokenUsage!.isEstimated, true);
    expect(
        completedTurn.tokenUsage!.estimationMethod, 'local-char-estimate-v1');
  });

  test('resumes from completed role checkpoint without rerunning it', () async {
    final invokedRoles = <AiSeminarRole>[];
    final priorTurnRoles = <AiSeminarRole, List<AiSeminarRole>>{};
    final completedCriticalTurn = AiSeminarRoleTurn(
      id: 'turn-critical',
      role: AiSeminarRole.critical,
      prompt: 'critical prompt',
      responseText: 'critical response',
      evidenceRefIds: const ['e1'],
    );
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async {
        fail('resume should use persisted evidence instead of refetching');
      },
      streamRole: (invocation, _) async* {
        invokedRoles.add(invocation.role);
        priorTurnRoles[invocation.role] =
            invocation.priorTurns.map((turn) => turn.role).toList();
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
          ),
        );
      },
      now: () => 1000,
    );

    final events = await service
        .run(
          AiSeminarSessionContract(id: 's-resume', question: 'Resume?'),
          checkpoint: AiSeminarRuntimeCheckpoint(
            evidenceBundle: bundle(),
            completedTurns: [completedCriticalTurn],
            startedAt: 900,
          ),
        )
        .toList();

    expect(invokedRoles, [
      AiSeminarRole.supportive,
      AiSeminarRole.synthesizer,
    ]);
    expect(priorTurnRoles[AiSeminarRole.supportive], [
      AiSeminarRole.critical,
    ]);
    expect(priorTurnRoles[AiSeminarRole.synthesizer], [
      AiSeminarRole.critical,
      AiSeminarRole.supportive,
    ]);
    expect(
      events.where(
        (event) =>
            event.type == AiSeminarRuntimeEventType.roleStarted &&
            event.activeRole == AiSeminarRole.critical,
      ),
      isEmpty,
    );
    expect(events.first.turns.single.role, AiSeminarRole.critical);
    expect(events.last.type, AiSeminarRuntimeEventType.synthesisReady);
    expect(events.last.run!.startedAt, 900);
    expect(events.last.run!.turns.map((turn) => turn.role), [
      AiSeminarRole.critical,
      AiSeminarRole.supportive,
      AiSeminarRole.synthesizer,
    ]);
    final restoredCritical = events.last.run!.turns.first;
    expect(restoredCritical.tokenUsage, isNotNull);
    expect(
      restoredCritical.tokenUsage!.estimationMethod,
      'local-char-estimate-v1',
    );
    expect(events.last.run!.tokenUsage!.totalTokens, greaterThan(0));
  });

  test('rejects unsafe checkpoint before invoking roles', () async {
    var invoked = false;
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async {
        fail('resume should use persisted evidence instead of refetching');
      },
      streamRole: (_, __) async* {
        invoked = true;
      },
      now: () => 1000,
    );

    final events = await service
        .run(
          AiSeminarSessionContract(id: 's-invalid-resume', question: 'Resume?'),
          checkpoint: AiSeminarRuntimeCheckpoint(
            evidenceBundle: bundle(),
            completedTurns: const [
              AiSeminarRoleTurn(
                id: 'turn-supportive',
                role: AiSeminarRole.supportive,
                prompt: 'supportive prompt',
                responseText: 'supportive response',
                evidenceRefIds: ['e1'],
              ),
            ],
            startedAt: 900,
          ),
        )
        .toList();

    expect(invoked, false);
    expect(events.last.type, AiSeminarRuntimeEventType.failed);
    expect(
      events.last.message,
      'AI Seminar checkpoint is invalid and cannot be resumed safely.',
    );
    expect(events.last.run!.turns, isEmpty);
  });

  test('rejects checkpoint turns that cite evidence outside role scope',
      () async {
    var invoked = false;
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async {
        fail('resume should use persisted evidence instead of refetching');
      },
      streamRole: (_, __) async* {
        invoked = true;
      },
      now: () => 1000,
    );

    final events = await service
        .run(
          AiSeminarSessionContract(
            id: 's-invalid-role-scope-resume',
            question: 'Resume?',
            bookId: 7,
            roleProfiles: [
              AiSeminarRoleProfile(
                role: AiSeminarRole.critical,
                evidenceScopes: const [AiSeminarEvidenceScope.currentBook],
              ),
            ],
          ),
          checkpoint: AiSeminarRuntimeCheckpoint(
            evidenceBundle: mixedScopeBundle(),
            completedTurns: const [
              AiSeminarRoleTurn(
                id: 'turn-critical',
                role: AiSeminarRole.critical,
                prompt: 'critical prompt',
                responseText: 'critical response',
                evidenceRefIds: ['library-evidence'],
              ),
            ],
            startedAt: 900,
          ),
        )
        .toList();

    expect(invoked, false);
    expect(events.last.type, AiSeminarRuntimeEventType.failed);
    expect(
      events.last.message,
      'AI Seminar checkpoint is invalid and cannot be resumed safely.',
    );
    expect(events.last.run!.turns, isEmpty);
  });

  test('stops before synthesis when role output budget is exceeded', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-role-completed-budget-child-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText:
                'This role answer is intentionally long enough to exceed one local token.',
            evidenceRefIds: const ['e1'],
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1000,
    );

    final events = await service
        .run(
          AiSeminarSessionContract(
            id: 'seminar-role-completed-budget-child',
            question: 'Budget?',
            budgetPolicy: const AiSeminarBudgetPolicy(
              maxRoleOutputTokens: 1,
            ),
          ),
        )
        .toList();

    expect(events.last.type, AiSeminarRuntimeEventType.failed);
    expect(events.last.message, contains('role output token budget'));
    expect(events.last.run!.turns, hasLength(1));
    expect(
        events.last.run!.turns.single.tokenUsage!.outputTokens, greaterThan(1));
    expect(
      events.any(
          (event) => event.type == AiSeminarRuntimeEventType.synthesisReady),
      isFalse,
    );
    const childRunId = 'seminar-role-completed-budget-child:role-critical-0';
    final child = await graphStore.getRun(childRunId);
    expect(child, isNotNull);
    expect(child!.status, SubAgentRunStatus.errored);
    expect(child.finishedAt, isNotNull);
    expect(child.error, contains('role output token budget'));
    final openChildren = await graphStore
        .listOpenChildren('seminar-role-completed-budget-child');
    expect(openChildren, isEmpty);
  });

  test('cancels active role stream when local role output budget is exceeded',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-role-partial-budget-child-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    late AiSeminarCancellationToken token;
    var emittedAfterBudget = false;
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, cancelToken) async* {
        token = cancelToken;
        yield const AiSeminarRoleStreamChunk(
          partialText:
              'This partial response is intentionally long enough to exceed one local token.',
        );
        emittedAfterBudget = !cancelToken.isCancelled;
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => 1000,
    );

    final events = await service
        .run(
          AiSeminarSessionContract(
            id: 'seminar-role-partial-budget-child',
            question: 'Budget?',
            budgetPolicy: const AiSeminarBudgetPolicy(
              maxRoleOutputTokens: 1,
            ),
          ),
        )
        .toList();

    expect(token.isCancelled, true);
    expect(emittedAfterBudget, false);
    expect(events.last.type, AiSeminarRuntimeEventType.failed);
    expect(events.last.message, contains('role output token budget'));
    expect(events.last.run!.turns, isEmpty);
    expect(
      events.any(
          (event) => event.type == AiSeminarRuntimeEventType.roleCompleted),
      isFalse,
    );
    const childRunId = 'seminar-role-partial-budget-child:role-critical-0';
    final child = await graphStore.getRun(childRunId);
    expect(child, isNotNull);
    expect(child!.status, SubAgentRunStatus.errored);
    expect(child.finishedAt, isNotNull);
    expect(child.error, contains('role output token budget'));
    final openChildren =
        await graphStore.listOpenChildren('seminar-role-partial-budget-child');
    expect(openChildren, isEmpty);
  });

  test('stops before synthesis when run token budget is exceeded', () async {
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
          ),
        );
      },
      now: () => 1000,
    );

    final events = await service
        .run(
          AiSeminarSessionContract(
            id: 's-run-budget',
            question: 'Budget?',
            budgetPolicy: const AiSeminarBudgetPolicy(maxRunTokens: 1),
          ),
        )
        .toList();

    expect(events.last.type, AiSeminarRuntimeEventType.failed);
    expect(events.last.message, contains('run token budget'));
    expect(events.last.run!.tokenUsage!.totalTokens, greaterThan(1));
    expect(
      events.any(
          (event) => event.type == AiSeminarRuntimeEventType.synthesisReady),
      isFalse,
    );
  });

  test('budget gate uses local estimate when provider usage is present',
      () async {
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: 'ok',
            evidenceRefIds: const ['e1'],
            tokenUsage: const AiSeminarTokenUsage(
              inputTokens: 1000,
              outputTokens: 1000,
              isEstimated: false,
              estimationMethod: 'provider-usage-tracker-v1',
              source: 'provider-reported',
            ),
          ),
        );
      },
      now: () => 1000,
    );

    final events = await service
        .run(
          AiSeminarSessionContract(
            id: 's-provider-usage-budget',
            question: 'Budget?',
            budgetPolicy: const AiSeminarBudgetPolicy(
              maxRoleOutputTokens: 10,
              maxRunTokens: 10000,
            ),
          ),
        )
        .toList();

    expect(events.last.type, AiSeminarRuntimeEventType.synthesisReady);
    expect(events.last.run!.tokenUsage!.source, 'provider-reported');
  });

  test('stops before synthesis when run cost cap is exceeded', () async {
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: 'costly response',
            evidenceRefIds: const ['e1'],
            tokenUsage: const AiSeminarTokenUsage(
              inputTokens: 1000,
              outputTokens: 1000,
              isEstimated: false,
              estimationMethod: 'provider-usage-tracker-v1',
              source: 'provider-reported',
            ),
          ),
        );
      },
      now: () => 1000,
    );

    final events = await service
        .run(
          AiSeminarSessionContract(
            id: 's-cost-cap',
            question: 'Budget?',
            budgetPolicy: const AiSeminarBudgetPolicy(
              maxRunCostUsd: 0.001,
              inputCostPerMillionTokens: 1,
              outputCostPerMillionTokens: 1,
              costPriceSource: 'test-pricing-v1',
            ),
          ),
        )
        .toList();

    expect(events.last.type, AiSeminarRuntimeEventType.failed);
    expect(events.last.message, contains('run cost cap'));
    expect(events.last.run!.turns, hasLength(1));
    expect(events.last.run!.estimatedCostUsd, greaterThan(0.001));
    expect(
      events.any(
          (event) => event.type == AiSeminarRuntimeEventType.synthesisReady),
      isFalse,
    );
  });

  test('records billing snapshot without claiming invoice reconciliation',
      () async {
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: 'priced response',
            evidenceRefIds: const ['e1'],
            tokenUsage: const AiSeminarTokenUsage(
              inputTokens: 1000,
              outputTokens: 1000,
              isEstimated: false,
              estimationMethod: 'provider-usage-tracker-v1',
              source: AiSeminarTokenUsage.sourceProviderReported,
            ),
          ),
        );
      },
      now: () => 1000,
    );

    final events = await service
        .run(
          AiSeminarSessionContract(
            id: 's-billing-snapshot',
            question: 'Billing?',
            budgetPolicy: const AiSeminarBudgetPolicy(
              maxRunCostUsd: 1,
              inputCostPerMillionTokens: 2,
              outputCostPerMillionTokens: 8,
              costPriceSource: 'test-pricing-v1',
            ),
          ),
        )
        .toList();
    final billing = events.last.run!.billingSnapshot!;

    expect(events.last.type, AiSeminarRuntimeEventType.synthesisReady);
    expect(billing.usageSnapshot.source,
        AiSeminarTokenUsage.sourceProviderReported);
    expect(billing.pricingSource, 'test-pricing-v1');
    expect(billing.pricingCapturedAt, 1000);
    expect(billing.estimatedCostUsd, greaterThan(0));
    expect(
      billing.invoiceStatus,
      AiSeminarInvoiceReconciliationStatus.notConnected,
    );
    expect(billing.invoiceReason, contains('not connected'));
    expect(billing.isProviderInvoice, false);
  });

  test('does not count executor-supplied token usage on failed role turns',
      () async {
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: 'partial failure',
            evidenceRefIds: const ['e1'],
            error: 'model stopped',
            tokenUsage: const AiSeminarTokenUsage(
              inputTokens: 999,
              outputTokens: 999,
              isEstimated: true,
              estimationMethod: 'executor-supplied',
            ),
          ),
        );
      },
      now: () => 1000,
    );

    final events = await service
        .run(AiSeminarSessionContract(id: 's-failed-usage', question: 'Usage?'))
        .toList();
    final failed = events.last;

    expect(failed.type, AiSeminarRuntimeEventType.failed);
    expect(failed.run!.tokenUsage, isNull);
    expect(failed.run!.turns.single.tokenUsage, isNull);
  });

  test('cancel token stops before synthesis and emits cancelled event',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'seminar-parent-cancel-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final graphStore = AgentRunGraphStore(rootDir: tempDir);
    late AiSeminarCancellationToken token;
    var nowMs = 1000;
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, cancelToken) async* {
        token = cancelToken;
        yield AiSeminarRoleStreamChunk(
          partialText: '${invocation.role.asString} partial',
        );
        token.cancel();
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
          ),
        );
      },
      agentRunGraphStore: graphStore,
      now: () => nowMs += 100,
    );

    final events = await service
        .run(AiSeminarSessionContract(id: 's2', question: 'Cancel?'))
        .toList();

    expect(events.last.type, AiSeminarRuntimeEventType.cancelled);
    expect(events.last.run!.status, AiSeminarRunStatus.cancelled);
    expect(
      events.any(
          (event) => event.type == AiSeminarRuntimeEventType.synthesisReady),
      isFalse,
    );
    final parent = await graphStore.getRun('s2');
    expect(parent, isNotNull);
    expect(parent!.status, SubAgentRunStatus.interrupted);
    final parentEvents = await graphStore.listEvents('s2');
    expect(
        parentEvents
            .map((event) => event.status)
            .whereType<SubAgentRunStatus>(),
        [
          SubAgentRunStatus.running,
          SubAgentRunStatus.interrupted,
        ]);
  });

  test('cancel token closes empty role stream as cancelled', () async {
    final roleStarted = Completer<void>();
    final releaseRole = Completer<void>();
    final token = AiSeminarCancellationToken();
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (_, cancelToken) async* {
        if (!roleStarted.isCompleted) roleStarted.complete();
        cancelToken.onCancel(() {
          if (!releaseRole.isCompleted) releaseRole.complete();
        });
        await releaseRole.future;
      },
      now: () => 1000,
    );

    final eventsFuture = service
        .run(
          AiSeminarSessionContract(id: 's-empty-cancel', question: 'Cancel?'),
          cancelToken: token,
        )
        .toList();
    await roleStarted.future;

    token.cancel();

    final events = await eventsFuture;
    expect(events.last.type, AiSeminarRuntimeEventType.cancelled);
    expect(events.last.run!.status, AiSeminarRunStatus.cancelled);
    expect(events.last.message, 'AI Seminar cancelled.');
  });

  test('model role executor rejects missing or unknown role values', () async {
    final executor = AiSeminarModelRoleExecutor(
      generateStream: (_, {conversationId}) => Stream.value(
        '{"responseText":"critical response","evidenceRefIds":["e1"]}',
      ),
    );

    expect(
      () => executor
          .streamRole(
            AiSeminarRoleInvocation(
              session: AiSeminarSessionContract(id: 's3', question: 'Reject?'),
              role: AiSeminarRole.critical,
              evidenceBundle: bundle(),
              priorTurns: const [],
              prompt: 'prompt',
            ),
            AiSeminarCancellationToken(),
          )
          .toList(),
      throwsFormatException,
    );

    final unknownRoleExecutor = AiSeminarModelRoleExecutor(
      generateStream: (_, {conversationId}) => Stream.value(
        '{"role":"unknown","responseText":"critical response","evidenceRefIds":["e1"]}',
      ),
    );

    expect(
      () => unknownRoleExecutor
          .streamRole(
            AiSeminarRoleInvocation(
              session: AiSeminarSessionContract(id: 's4', question: 'Reject?'),
              role: AiSeminarRole.critical,
              evidenceBundle: bundle(),
              priorTurns: const [],
              prompt: 'prompt',
            ),
            AiSeminarCancellationToken(),
          )
          .toList(),
      throwsFormatException,
    );
  });

  test('model role executor rejects blank role response text', () async {
    final executor = AiSeminarModelRoleExecutor(
      generateStream: (_, {conversationId}) => Stream.value(
        '{"role":"critical","responseText":"   ","evidenceRefIds":["e1"]}',
      ),
    );

    expect(
      () => executor
          .streamRole(
            AiSeminarRoleInvocation(
              session: AiSeminarSessionContract(
                id: 's-blank-role-response',
                question: 'Reject blank role response?',
              ),
              role: AiSeminarRole.critical,
              evidenceBundle: bundle(),
              priorTurns: const [],
              prompt: 'prompt',
            ),
            AiSeminarCancellationToken(),
          )
          .toList(),
      throwsFormatException,
    );
  });

  test('model role executor uses agent stream for allowed role tools',
      () async {
    var agentStreamUsed = false;
    final toolEvents = <AgentToolCallEvent>[];
    final executor = AiSeminarModelRoleExecutor(
      generateStream: (_, {conversationId}) => Stream.value(
        '{"role":"critical","responseText":"plain response","evidenceRefIds":["e1"]}',
      ),
      agentGenerateStream: (invocation, messages, {conversationId}) async* {
        agentStreamUsed = true;
        expect(conversationId, 's-agent-role');
        expect(messages, isNotEmpty);
        await invocation.toolCallObserver?.call(const AgentToolCallEvent(
          callId: 'call-role-agent-1',
          toolId: 'semantic_search_current_book',
          input: {'query': 'agency'},
          status: AgentToolCallEventStatus.running,
        ));
        yield '{"role":"critical","responseText":"agent response","evidenceRefIds":["e1"]}';
      },
    );

    final chunks = await executor
        .streamRole(
          AiSeminarRoleInvocation(
            session: AiSeminarSessionContract(
              id: 's-agent-role',
              question: 'Use tools?',
              bookId: 7,
              roleProfiles: [
                AiSeminarRoleProfile(
                  role: AiSeminarRole.critical,
                  allowedToolIds: const ['semantic_search_current_book'],
                ),
              ],
            ),
            role: AiSeminarRole.critical,
            evidenceBundle: bundle(),
            priorTurns: const [],
            prompt: 'prompt',
            toolCallObserver: toolEvents.add,
          ),
          AiSeminarCancellationToken(),
        )
        .toList();

    expect(agentStreamUsed, isTrue);
    expect(chunks.last.completedTurn!.responseText, 'agent response');
    expect(toolEvents.single.toolId, 'semantic_search_current_book');
    expect(toolEvents.single.status, AgentToolCallEventStatus.running);
  });

  test('model role executor tells agent stream the controlled tool boundary',
      () async {
    final executor = AiSeminarModelRoleExecutor(
      agentGenerateStream: (invocation, messages, {conversationId}) async* {
        final systemPrompt = messages.first.contentAsString;
        expect(systemPrompt, contains('Available read-only tools'));
        expect(systemPrompt, contains('semantic_search_current_book'));
        expect(systemPrompt, contains('notes_search'));
        expect(systemPrompt, contains('Do not call tools outside this list'));
        expect(systemPrompt, contains('Return the final Seminar role JSON'));
        yield '{"role":"critical","responseText":"agent response","evidenceRefIds":["e1"]}';
      },
    );

    final chunks = await executor
        .streamRole(
          AiSeminarRoleInvocation(
            session: AiSeminarSessionContract(
              id: 's-agent-tool-boundary',
              question: 'Use controlled tools?',
              bookId: 7,
              roleProfiles: [
                AiSeminarRoleProfile(
                  role: AiSeminarRole.critical,
                  allowedToolIds: const [
                    'semantic_search_current_book',
                    'notes_search',
                  ],
                ),
              ],
            ),
            role: AiSeminarRole.critical,
            evidenceBundle: bundle(),
            priorTurns: const [],
            prompt: 'prompt',
          ),
          AiSeminarCancellationToken(),
        )
        .toList();

    expect(chunks.last.completedTurn!.responseText, 'agent response');
  });

  test('model role executor parses agent stream reply tags after tools',
      () async {
    final json =
        '{"role":"critical","responseText":"agent json response","evidenceRefIds":["e1"]}';
    final payload =
        "<tool-step name='semantic_search_current_book' status='success' "
        "input_b64='eyJxdWVyeSI6ImFnZW5jeSJ9'/>"
        "<reply text_b64='${base64Encode(utf8.encode(json))}'/>";
    final executor = AiSeminarModelRoleExecutor(
      agentGenerateStream: (invocation, messages, {conversationId}) async* {
        yield payload;
      },
    );

    final chunks = await executor
        .streamRole(
          AiSeminarRoleInvocation(
            session: AiSeminarSessionContract(
              id: 's-agent-reply-tag',
              question: 'Parse tools?',
              bookId: 7,
              roleProfiles: [
                AiSeminarRoleProfile(
                  role: AiSeminarRole.critical,
                  allowedToolIds: const ['semantic_search_current_book'],
                ),
              ],
            ),
            role: AiSeminarRole.critical,
            evidenceBundle: bundle(),
            priorTurns: const [],
            prompt: 'prompt',
          ),
          AiSeminarCancellationToken(),
        )
        .toList();

    expect(chunks.last.completedTurn!.responseText, 'agent json response');
  });

  test('model role executor rejects agent stream without final reply',
      () async {
    final executor = AiSeminarModelRoleExecutor(
      agentGenerateStream: (invocation, messages, {conversationId}) async* {
        yield "<tool-step name='semantic_search_current_book' "
            "status='success' input_b64='eyJxdWVyeSI6ImFnZW5jeSJ9'/>";
      },
    );

    expect(
      () => executor
          .streamRole(
            AiSeminarRoleInvocation(
              session: AiSeminarSessionContract(
                id: 's-agent-missing-reply',
                question: 'Reject missing reply?',
                bookId: 7,
                roleProfiles: [
                  AiSeminarRoleProfile(
                    role: AiSeminarRole.critical,
                    allowedToolIds: const ['semantic_search_current_book'],
                  ),
                ],
              ),
              role: AiSeminarRole.critical,
              evidenceBundle: bundle(),
              priorTurns: const [],
              prompt: 'prompt',
            ),
            AiSeminarCancellationToken(),
          )
          .toList(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('final reply'),
        ),
      ),
    );
  });

  test('model role executor emits tool-step timeline events', () async {
    final json =
        '{"role":"critical","responseText":"agent json response","evidenceRefIds":["e1"]}';
    final inputB64 = base64Encode(utf8.encode('{"query":"agency"}'));
    final outputB64 = base64Encode(utf8.encode('Found 2 matches.'));
    final executor = AiSeminarModelRoleExecutor(
      agentGenerateStream: (invocation, messages, {conversationId}) async* {
        yield "<tool-step name='semantic_search_current_book' "
            "status='running' input_b64='$inputB64'/>";
        yield "<tool-step name='semantic_search_current_book' "
            "status='success' input_b64='$inputB64' "
            "output_b64='$outputB64' result_count='2'/>"
            "<reply text_b64='${base64Encode(utf8.encode(json))}'/>";
      },
    );
    final toolEvents = <AgentToolCallEvent>[];

    final chunks = await executor
        .streamRole(
          AiSeminarRoleInvocation(
            session: AiSeminarSessionContract(
              id: 's-agent-tool-step',
              question: 'Parse tool steps?',
              bookId: 7,
              roleProfiles: [
                AiSeminarRoleProfile(
                  role: AiSeminarRole.critical,
                  allowedToolIds: const ['semantic_search_current_book'],
                ),
              ],
            ),
            role: AiSeminarRole.critical,
            evidenceBundle: bundle(),
            priorTurns: const [],
            prompt: 'prompt',
            toolCallObserver: toolEvents.add,
          ),
          AiSeminarCancellationToken(),
        )
        .toList();

    expect(chunks.last.completedTurn!.responseText, 'agent json response');
    expect(toolEvents.map((event) => event.status), [
      AgentToolCallEventStatus.running,
      AgentToolCallEventStatus.completed,
    ]);
    expect(toolEvents.map((event) => event.toolId), [
      'semantic_search_current_book',
      'semantic_search_current_book',
    ]);
    expect(toolEvents.first.input, {'query': 'agency'});
    expect(toolEvents.last.output, 'Found 2 matches.');
    expect(toolEvents.last.resultCount, 2);
  });

  test('model role executor filters tool-step events outside role allowlist',
      () async {
    final json =
        '{"role":"critical","responseText":"agent json response","evidenceRefIds":["e1"]}';
    final semanticInputB64 =
        base64Encode(utf8.encode('{"query":"allowed evidence"}'));
    final writeInputB64 =
        base64Encode(utf8.encode('{"text":"unapproved write"}'));
    final executor = AiSeminarModelRoleExecutor(
      agentGenerateStream: (invocation, messages, {conversationId}) async* {
        yield "<tool-step name='semantic_search_current_book' "
            "status='success' call_id='call-allowed-search' "
            "input_b64='$semanticInputB64'/>"
            "<tool-step name='memory_append' "
            "status='success' call_id='call-write-memory' "
            "input_b64='$writeInputB64'/>"
            "<reply text_b64='${base64Encode(utf8.encode(json))}'/>";
      },
    );
    final toolEvents = <AgentToolCallEvent>[];

    final chunks = await executor
        .streamRole(
          AiSeminarRoleInvocation(
            session: AiSeminarSessionContract(
              id: 's-agent-tool-step-allowlist',
              question: 'Filter tool steps?',
              bookId: 7,
              roleProfiles: [
                AiSeminarRoleProfile(
                  role: AiSeminarRole.critical,
                  allowedToolIds: const ['semantic_search_current_book'],
                ),
              ],
            ),
            role: AiSeminarRole.critical,
            evidenceBundle: bundle(),
            priorTurns: const [],
            prompt: 'prompt',
            toolCallObserver: toolEvents.add,
          ),
          AiSeminarCancellationToken(),
        )
        .toList();

    expect(chunks.last.completedTurn!.responseText, 'agent json response');
    expect(toolEvents.map((event) => event.toolId), [
      'semantic_search_current_book',
    ]);
    expect(toolEvents.any((event) => event.toolId == 'memory_append'), isFalse);
  });

  test('model role executor filters library fallback tools in reading sessions',
      () async {
    final json =
        '{"role":"critical","responseText":"agent json response","evidenceRefIds":["e1"]}';
    final inputB64 =
        base64Encode(utf8.encode('{"query":"library-wide evidence"}'));
    final executor = AiSeminarModelRoleExecutor(
      agentGenerateStream: (invocation, messages, {conversationId}) async* {
        yield "<tool-step name='semantic_search_library' "
            "status='success' call_id='call-library-search' "
            "input_b64='$inputB64'/>"
            "<reply text_b64='${base64Encode(utf8.encode(json))}'/>";
      },
    );
    final toolEvents = <AgentToolCallEvent>[];

    final chunks = await executor
        .streamRole(
          AiSeminarRoleInvocation(
            session: AiSeminarSessionContract(
              id: 's-agent-tool-step-reading-scene',
              question: 'Filter fallback tool steps?',
              bookId: 7,
              roleProfiles: [
                AiSeminarRoleProfile(
                  role: AiSeminarRole.critical,
                  allowedToolIds: const [
                    'semantic_search_current_book',
                    'semantic_search_library',
                  ],
                ),
              ],
            ),
            role: AiSeminarRole.critical,
            evidenceBundle: bundle(),
            priorTurns: const [],
            prompt: 'prompt',
            toolCallObserver: toolEvents.add,
          ),
          AiSeminarCancellationToken(),
        )
        .toList();

    expect(chunks.last.completedTurn!.responseText, 'agent json response');
    expect(
      toolEvents.any((event) => event.toolId == 'semantic_search_library'),
      isFalse,
    );
  });

  test('model role executor deduplicates observed tool-step events', () async {
    final json =
        '{"role":"critical","responseText":"agent json response","evidenceRefIds":["e1"]}';
    final inputB64 = base64Encode(utf8.encode('{"query":"agency"}'));
    final outputB64 = base64Encode(utf8.encode('Found 2 matches.'));
    final executor = AiSeminarModelRoleExecutor(
      agentGenerateStream: (invocation, messages, {conversationId}) async* {
        await invocation.toolCallObserver?.call(const AgentToolCallEvent(
          callId: 'call-search-1',
          toolId: 'semantic_search_current_book',
          input: {'query': 'agency'},
          status: AgentToolCallEventStatus.running,
        ));
        yield "<tool-step name='semantic_search_current_book' "
            "status='pending' call_id='call-search-1' "
            "input_b64='$inputB64'/>";
        await invocation.toolCallObserver?.call(const AgentToolCallEvent(
          callId: 'call-search-1',
          toolId: 'semantic_search_current_book',
          input: {'query': 'agency'},
          status: AgentToolCallEventStatus.completed,
          output: 'Found 2 matches.',
          resultCount: 2,
        ));
        yield "<tool-step name='semantic_search_current_book' "
            "status='success' call_id='call-search-1' "
            "input_b64='$inputB64' output_b64='$outputB64' "
            "result_count='2'/>"
            "<reply text_b64='${base64Encode(utf8.encode(json))}'/>";
      },
    );
    final toolEvents = <AgentToolCallEvent>[];

    final chunks = await executor
        .streamRole(
          AiSeminarRoleInvocation(
            session: AiSeminarSessionContract(
              id: 's-agent-tool-step-dedupe',
              question: 'Dedupe tool steps?',
              bookId: 7,
              roleProfiles: [
                AiSeminarRoleProfile(
                  role: AiSeminarRole.critical,
                  allowedToolIds: const ['semantic_search_current_book'],
                ),
              ],
            ),
            role: AiSeminarRole.critical,
            evidenceBundle: bundle(),
            priorTurns: const [],
            prompt: 'prompt',
            toolCallObserver: toolEvents.add,
          ),
          AiSeminarCancellationToken(),
        )
        .toList();

    expect(chunks.last.completedTurn!.responseText, 'agent json response');
    expect(toolEvents.map((event) => event.status), [
      AgentToolCallEventStatus.running,
      AgentToolCallEventStatus.completed,
    ]);
    expect(toolEvents.map((event) => event.callId), [
      'call-search-1',
      'call-search-1',
    ]);
    expect(toolEvents.last.output, 'Found 2 matches.');
  });

  test('model role executor parses non self closing agent reply tags',
      () async {
    final json =
        '{"role":"critical","responseText":"non self closing reply","evidenceRefIds":["e1"]}';
    final payload =
        "<tool-step name='semantic_search_current_book' status='success' "
        "input_b64='eyJxdWVyeSI6ImFnZW5jeSJ9'/>"
        "<reply text_b64='${base64Encode(utf8.encode(json))}'></reply>";
    final executor = AiSeminarModelRoleExecutor(
      agentGenerateStream: (invocation, messages, {conversationId}) async* {
        yield payload;
      },
    );

    final chunks = await executor
        .streamRole(
          AiSeminarRoleInvocation(
            session: AiSeminarSessionContract(
              id: 's-agent-reply-tag-paired',
              question: 'Parse paired reply?',
              bookId: 7,
              roleProfiles: [
                AiSeminarRoleProfile(
                  role: AiSeminarRole.critical,
                  allowedToolIds: const ['semantic_search_current_book'],
                ),
              ],
            ),
            role: AiSeminarRole.critical,
            evidenceBundle: bundle(),
            priorTurns: const [],
            prompt: 'prompt',
          ),
          AiSeminarCancellationToken(),
        )
        .toList();

    expect(chunks.last.completedTurn!.responseText, 'non self closing reply');
  });

  test('model role executor hides agent timeline tags from role partials',
      () async {
    final json =
        '{"role":"critical","responseText":"clean agent response","evidenceRefIds":["e1"]}';
    final executor = AiSeminarModelRoleExecutor(
      agentGenerateStream: (invocation, messages, {conversationId}) async* {
        yield "<tool-step name='semantic_search_current_book' "
            "status='running' input_b64='eyJxdWVyeSI6ImFnZW5jeSJ9'/>";
        yield "<tool-step name='semantic_search_current_book' "
            "status='success' input_b64='eyJxdWVyeSI6ImFnZW5jeSJ9'/>"
            "<reply text_b64='${base64Encode(utf8.encode(json))}'/>";
      },
    );

    final chunks = await executor
        .streamRole(
          AiSeminarRoleInvocation(
            session: AiSeminarSessionContract(
              id: 's-agent-timeline-partial',
              question: 'Hide timeline?',
              bookId: 7,
              roleProfiles: [
                AiSeminarRoleProfile(
                  role: AiSeminarRole.critical,
                  allowedToolIds: const ['semantic_search_current_book'],
                ),
              ],
            ),
            role: AiSeminarRole.critical,
            evidenceBundle: bundle(),
            priorTurns: const [],
            prompt: 'prompt',
          ),
          AiSeminarCancellationToken(),
        )
        .toList();

    final partialTexts =
        chunks.map((chunk) => chunk.partialText).whereType<String>().toList();
    expect(partialTexts.any((text) => text.contains('<tool-step')), isFalse);
    expect(partialTexts, contains('clean agent response'));
    expect(chunks.last.completedTurn!.responseText, 'clean agent response');
  });

  test('model role executor hides agent thinking tags from role partials',
      () async {
    final json =
        '{"role":"critical","responseText":"clean thinking response","evidenceRefIds":["e1"]}';
    final executor = AiSeminarModelRoleExecutor(
      agentGenerateStream: (invocation, messages, {conversationId}) async* {
        yield '<think>checking semantic evidence</think>';
        yield "<reply text_b64='${base64Encode(utf8.encode(json))}'/>";
      },
    );

    final chunks = await executor
        .streamRole(
          AiSeminarRoleInvocation(
            session: AiSeminarSessionContract(
              id: 's-agent-thinking-partial',
              question: 'Hide thinking?',
              bookId: 7,
              roleProfiles: [
                AiSeminarRoleProfile(
                  role: AiSeminarRole.critical,
                  allowedToolIds: const ['semantic_search_current_book'],
                ),
              ],
            ),
            role: AiSeminarRole.critical,
            evidenceBundle: bundle(),
            priorTurns: const [],
            prompt: 'prompt',
          ),
          AiSeminarCancellationToken(),
        )
        .toList();

    final partialTexts =
        chunks.map((chunk) => chunk.partialText).whereType<String>().toList();
    final thinkingTexts =
        chunks.map((chunk) => chunk.thinkingText).whereType<String>().toList();
    expect(thinkingTexts, contains('checking semantic evidence'));
    expect(partialTexts.any((text) => text.contains('<think>')), isFalse);
    expect(partialTexts, contains('clean thinking response'));
    expect(chunks.last.completedTurn!.responseText, 'clean thinking response');
  });

  test('model role executor ignores trailing agent timeline after reply',
      () async {
    final json =
        '{"role":"critical","responseText":"reply before trailing timeline","evidenceRefIds":["e1"]}';
    final executor = AiSeminarModelRoleExecutor(
      agentGenerateStream: (invocation, messages, {conversationId}) async* {
        yield "<tool-step name='semantic_search_current_book' "
            "status='success' input_b64='eyJxdWVyeSI6ImFnZW5jeSJ9'/>"
            "<reply text_b64='${base64Encode(utf8.encode(json))}'/>";
        yield "<tool-step name='notes_search' "
            "status='success' input_b64='eyJxdWVyeSI6ImFnZW5jeSJ9'/>";
      },
    );

    final chunks = await executor
        .streamRole(
          AiSeminarRoleInvocation(
            session: AiSeminarSessionContract(
              id: 's-agent-trailing-timeline',
              question: 'Ignore trailing timeline?',
              bookId: 7,
              roleProfiles: [
                AiSeminarRoleProfile(
                  role: AiSeminarRole.critical,
                  allowedToolIds: const ['semantic_search_current_book'],
                ),
              ],
            ),
            role: AiSeminarRole.critical,
            evidenceBundle: bundle(),
            priorTurns: const [],
            prompt: 'prompt',
          ),
          AiSeminarCancellationToken(),
        )
        .toList();

    expect(
      chunks.last.completedTurn!.responseText,
      'reply before trailing timeline',
    );
  });

  test('model role executor ignores trailing raw text after agent reply',
      () async {
    final json =
        '{"role":"critical","responseText":"reply before trailing raw text","evidenceRefIds":["e1"]}';
    final executor = AiSeminarModelRoleExecutor(
      agentGenerateStream: (invocation, messages, {conversationId}) async* {
        yield "<reply text_b64='${base64Encode(utf8.encode(json))}'/>";
        yield 'done';
      },
    );

    final chunks = await executor
        .streamRole(
          AiSeminarRoleInvocation(
            session: AiSeminarSessionContract(
              id: 's-agent-trailing-raw-text',
              question: 'Ignore trailing raw text?',
              bookId: 7,
              roleProfiles: [
                AiSeminarRoleProfile(
                  role: AiSeminarRole.critical,
                  allowedToolIds: const ['semantic_search_current_book'],
                ),
              ],
            ),
            role: AiSeminarRole.critical,
            evidenceBundle: bundle(),
            priorTurns: const [],
            prompt: 'prompt',
          ),
          AiSeminarCancellationToken(),
        )
        .toList();

    expect(
      chunks.last.completedTurn!.responseText,
      'reply before trailing raw text',
    );
  });

  test('model role executor attaches provider usage delta to completed turn',
      () async {
    final executor = AiSeminarModelRoleExecutor(
      generateStream: (_, {conversationId}) async* {
        final tracker = ensureAiUsageTracker(conversationId);
        tracker.recordApiCall(inputTokens: 9, outputTokens: 4);
        yield '{"role":"critical","responseText":"critical response","evidenceRefIds":["e1"]}';
      },
    );

    final chunks = await executor
        .streamRole(
          AiSeminarRoleInvocation(
            session: AiSeminarSessionContract(
              id: 's-provider-delta',
              question: 'Usage?',
            ),
            role: AiSeminarRole.critical,
            evidenceBundle: bundle(),
            priorTurns: const [],
            prompt: 'prompt',
          ),
          AiSeminarCancellationToken(),
        )
        .toList();
    final completedTurn = chunks.last.completedTurn!;

    expect(completedTurn.tokenUsage!.source, 'provider-reported');
    expect(completedTurn.tokenUsage!.inputTokens, 9);
    expect(completedTurn.tokenUsage!.outputTokens, 4);
    expect(completedTurn.tokenUsage!.isEstimated, false);
    expect(
      completedTurn.tokenUsage!.estimationMethod,
      'provider-usage-tracker-v1',
    );
  });
}
