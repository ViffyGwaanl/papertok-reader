import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/ai/ai_seminar_orchestration_service.dart';
import 'package:papertok_reader/service/ai/ai_seminar_runtime_service.dart';

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

  test('stops before synthesis when role output budget is exceeded', () async {
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
      now: () => 1000,
    );

    final events = await service
        .run(
          AiSeminarSessionContract(
            id: 's-role-budget',
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
  });

  test('cancels active role stream when local role output budget is exceeded',
      () async {
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
      now: () => 1000,
    );

    final events = await service
        .run(
          AiSeminarSessionContract(
            id: 's-partial-budget',
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
    late AiSeminarCancellationToken token;
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
      now: () => 1000,
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
}
