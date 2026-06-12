import 'dart:async';
import 'dart:convert';

import 'package:langchain_core/chat_models.dart';
import 'package:papertok_reader/models/ai_agent_governance.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/service/ai/agent_run_graph_store.dart';
import 'package:papertok_reader/service/ai/agent_tool_call_event.dart';
import 'package:papertok_reader/service/ai/ai_seminar_orchestration_service.dart';
import 'package:papertok_reader/service/ai/ai_usage_tracker.dart';
import 'package:papertok_reader/service/ai/index.dart';
import 'package:papertok_reader/service/ai/sub_agent_runner.dart';
import 'package:papertok_reader/service/ai/tools/util/json_repair.dart';

typedef AiSeminarStreamingRoleExecutor = Stream<AiSeminarRoleStreamChunk>
    Function(
  AiSeminarRoleInvocation invocation,
  AiSeminarCancellationToken cancelToken,
);

typedef AiSeminarGenerateStream = Stream<String> Function(
  List<ChatMessage> messages, {
  String? conversationId,
});

typedef AiSeminarAgentGenerateStream = Stream<String> Function(
  AiSeminarRoleInvocation invocation,
  List<ChatMessage> messages, {
  String? conversationId,
});

class AiSeminarCancellationToken {
  final List<void Function()> _callbacks = [];
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void onCancel(void Function() callback) {
    if (_isCancelled) {
      callback();
      return;
    }
    _callbacks.add(callback);
  }

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    for (final callback in List<void Function()>.from(_callbacks)) {
      callback();
    }
    _callbacks.clear();
  }
}

class AiSeminarRoleStreamChunk {
  const AiSeminarRoleStreamChunk({
    this.thinkingText,
    this.partialText,
    this.completedTurn,
  });

  final String? thinkingText;
  final String? partialText;
  final AiSeminarRoleTurn? completedTurn;
}

class AiSeminarRuntimeCheckpoint {
  const AiSeminarRuntimeCheckpoint({
    required this.evidenceBundle,
    this.completedTurns = const <AiSeminarRoleTurn>[],
    this.startedAt,
  });

  final AiSeminarEvidenceBundle evidenceBundle;
  final List<AiSeminarRoleTurn> completedTurns;
  final int? startedAt;
}

enum AiSeminarRuntimeEventType {
  sessionStarted,
  evidenceReady,
  roleStarted,
  roleThinking,
  roleToolCall,
  roleDelta,
  roleCompleted,
  whiteboardUpdated,
  synthesisReady,
  needsEvidence,
  cancelled,
  failed,
}

class AiSeminarRuntimeEvent {
  const AiSeminarRuntimeEvent({
    required this.type,
    required this.session,
    this.status,
    this.evidenceBundle,
    this.activeRole,
    this.partialText,
    this.turn,
    this.turns = const <AiSeminarRoleTurn>[],
    this.whiteboardEntries = const <AiSeminarWhiteboardEntry>[],
    this.synthesis,
    this.run,
    this.agentRunEvent,
    this.message,
  });

  final AiSeminarRuntimeEventType type;
  final AiSeminarSessionContract session;
  final AiSeminarRunStatus? status;
  final AiSeminarEvidenceBundle? evidenceBundle;
  final AiSeminarRole? activeRole;
  final String? partialText;
  final AiSeminarRoleTurn? turn;
  final List<AiSeminarRoleTurn> turns;
  final List<AiSeminarWhiteboardEntry> whiteboardEntries;
  final AiSeminarSynthesis? synthesis;
  final AiSeminarRun? run;
  final AgentRunEvent? agentRunEvent;
  final String? message;
}

abstract class _AiSeminarRoleRuntimeStreamItem {
  const _AiSeminarRoleRuntimeStreamItem();
}

class _AiSeminarRoleChunkRuntimeStreamItem
    extends _AiSeminarRoleRuntimeStreamItem {
  const _AiSeminarRoleChunkRuntimeStreamItem(
    this.chunk, {
    required this.cancelledWhenReceived,
  });

  final AiSeminarRoleStreamChunk chunk;
  final bool cancelledWhenReceived;
}

class _AiSeminarRoleToolCallRuntimeStreamItem
    extends _AiSeminarRoleRuntimeStreamItem {
  const _AiSeminarRoleToolCallRuntimeStreamItem(this.event);

  final AgentRunEvent event;
}

class _AiSeminarRoleDoneRuntimeStreamItem
    extends _AiSeminarRoleRuntimeStreamItem {
  const _AiSeminarRoleDoneRuntimeStreamItem();
}

class AiSeminarRuntimeService {
  const AiSeminarRuntimeService({
    required AiSeminarEvidenceFetcher fetchEvidence,
    required AiSeminarStreamingRoleExecutor streamRole,
    AgentRunGraphStore? agentRunGraphStore,
    AiSeminarClock? now,
  })  : _fetchEvidence = fetchEvidence,
        _streamRole = streamRole,
        _agentRunGraphStore = agentRunGraphStore,
        _now = now;
  final AiSeminarEvidenceFetcher _fetchEvidence;
  final AiSeminarStreamingRoleExecutor _streamRole;
  final AgentRunGraphStore? _agentRunGraphStore;
  final AiSeminarClock? _now;
  static const String _localTokenEstimateMethod = 'local-char-estimate-v1';
  static const String _providerInvoiceNotConnectedReason = 'Provider invoice import is not connected for this run.';
  Future<AiSeminarEvidenceBundle> fetchEvidenceBundle(AiSeminarSessionContract session) => _fetchEvidence(session);

  static bool canResumeCheckpoint({
    required AiSeminarSessionContract session,
    required AiSeminarEvidenceBundle evidenceBundle,
    required List<AiSeminarRoleTurn> completedTurns,
  }) {
    if (evidenceBundle.evidence.isEmpty ||
        !evidenceBundle.allEvidenceTraceable) {
      return false;
    }
    final executionOrder = AiSeminarOrchestrationService.executionOrder(
      session.roles,
    );
    return _validatedCheckpointTurns(
          session,
          evidenceBundle,
          completedTurns,
          executionOrder,
        ) !=
        null;
  }

  Stream<AiSeminarRuntimeEvent> run(
    AiSeminarSessionContract session, {
    AiSeminarCancellationToken? cancelToken,
    AiSeminarRuntimeCheckpoint? checkpoint,
  }) async* {
    final token = cancelToken ?? AiSeminarCancellationToken();
    final startedAt = checkpoint?.startedAt ?? _nowMs();
    await _agentRunGraphStore?.upsertFromSeminarSessionStart(
      session: session,
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedAt),
    );
    yield AiSeminarRuntimeEvent(
      type: AiSeminarRuntimeEventType.sessionStarted,
      session: session,
      status: AiSeminarRunStatus.running,
      evidenceBundle: checkpoint?.evidenceBundle,
      turns: checkpoint?.completedTurns ?? const <AiSeminarRoleTurn>[],
      whiteboardEntries: checkpoint == null
          ? const <AiSeminarWhiteboardEntry>[]
          : _whiteboardEntries(checkpoint.completedTurns),
    );

    late final AiSeminarEvidenceBundle evidenceBundle;
    if (checkpoint != null) {
      evidenceBundle = checkpoint.evidenceBundle;
    } else {
      try {
        await _agentRunGraphStore?.upsertEvent(AgentRunEvent(
          eventId: '${session.id}:thinking:evidence_collection',
          runId: session.id,
          type: AgentRunEventType.thinking,
          createdAt: _nowDateTime(),
          roleId: 'director',
          nickname: 'Director',
          delta: 'Director is collecting traceable evidence for the seminar.',
        ));
        await _upsertSeminarEvidenceToolCallStatusEvents(
          session: session,
          status: SubAgentRunStatus.running,
        );
        evidenceBundle = await _fetchEvidence(session);
      } catch (error) {
        await _upsertSeminarEvidenceToolCallStatusEvents(
          session: session,
          status: SubAgentRunStatus.errored,
          error: error.toString(),
        );
        yield await _recordTerminalRun(_failedEvent(
          session: session,
          evidenceBundle: const AiSeminarEvidenceBundle(
            query: '',
            evidence: <AiSeminarEvidence>[],
          ),
          startedAt: startedAt,
          message: error.toString(),
        ));
        return;
      }
    }

    if (token.isCancelled) {
      yield await _recordTerminalRun(_cancelledEvent(
        session: session,
        evidenceBundle: evidenceBundle,
        startedAt: startedAt,
      ));
      return;
    }

    await _upsertSeminarEvidenceToolCallEvents(
      session: session,
      evidenceBundle: evidenceBundle,
    );

    yield AiSeminarRuntimeEvent(
      type: AiSeminarRuntimeEventType.evidenceReady,
      session: session,
      status: AiSeminarRunStatus.running,
      evidenceBundle: evidenceBundle,
    );

    if (evidenceBundle.evidence.isEmpty ||
        !evidenceBundle.allEvidenceTraceable) {
      yield await _recordTerminalRun(_needsEvidenceEvent(
        session: session,
        evidenceBundle: evidenceBundle,
        startedAt: startedAt,
        message: 'AI Seminar requires traceable current-source evidence.',
      ));
      return;
    }

    final executionOrder = AiSeminarOrchestrationService.executionOrder(
      session.roles,
    );
    final resumeTurns = checkpoint == null
        ? const <AiSeminarRoleTurn>[]
        : _validatedCheckpointTurns(
            session,
            evidenceBundle,
            checkpoint.completedTurns,
            executionOrder,
          );
    if (resumeTurns == null) {
      yield await _recordTerminalRun(_failedEvent(
        session: session,
        evidenceBundle: evidenceBundle,
        startedAt: startedAt,
        message:
            'AI Seminar checkpoint is invalid and cannot be resumed safely.',
      ));
      return;
    }
    final resumeTurnsWithUsage = _checkpointTurnsWithTokenUsage(
      session: session,
      evidenceBundle: evidenceBundle,
      turns: resumeTurns,
    );
    final turns = List<AiSeminarRoleTurn>.from(resumeTurnsWithUsage);
    final localBudgetTurns = _localBudgetTurnsForCheckpoint(
      session: session,
      evidenceBundle: evidenceBundle,
      turns: resumeTurns,
    );

    for (var roleIndex = turns.length;
        roleIndex < executionOrder.length;
        roleIndex++) {
      final role = executionOrder[roleIndex];
      final roleRunId = _seminarRoleRunId(
        session: session,
        role: role,
        index: roleIndex,
      );
      if (token.isCancelled) {
        yield await _recordTerminalRun(_cancelledEvent(
          session: session,
          evidenceBundle: evidenceBundle,
          startedAt: startedAt,
          turns: turns,
        ));
        return;
      }

      final roleEvidenceBundle =
          AiSeminarOrchestrationService.evidenceBundleForRole(
        session: session,
        role: role,
        evidenceBundle: evidenceBundle,
      );
      await _agentRunGraphStore?.upsertFromSeminarRoleStart(
        session: session,
        role: role,
        runId: roleRunId,
        startedAt: _nowDateTime(),
      );
      await _upsertSeminarRoleToolCallEvents(
        session: session,
        role: role,
        runId: roleRunId,
        evidenceBundle: roleEvidenceBundle,
      );
      await _upsertSeminarRoleThinkingEvent(
        session: session,
        role: role,
        runId: roleRunId,
      );
      yield AiSeminarRuntimeEvent(
        type: AiSeminarRuntimeEventType.roleStarted,
        session: session,
        status: AiSeminarRunStatus.running,
        evidenceBundle: evidenceBundle,
        activeRole: role,
        turns: List.unmodifiable(turns),
        whiteboardEntries: _whiteboardEntries(turns),
      );

      AiSeminarRoleTurn? completedTurn;
      final roleTraceableEvidenceIds =
          _traceableEvidenceIds(roleEvidenceBundle);
      final roleRuntimeController =
          StreamController<_AiSeminarRoleRuntimeStreamItem>();
      final invocation = AiSeminarRoleInvocation(
        session: session,
        role: role,
        evidenceBundle: roleEvidenceBundle,
        priorTurns: List.unmodifiable(turns),
        prompt: AiSeminarOrchestrationService.promptForRole(
          session: session,
          role: role,
          evidenceBundle: roleEvidenceBundle,
          priorTurns: turns,
        ),
        toolCallObserver: (event) async {
          final agentRunEvent = await _upsertSeminarRoleAgentToolCallEvent(
            session: session,
            role: role,
            runId: roleRunId,
            event: event,
          );
          if (agentRunEvent != null) {
            if (!roleRuntimeController.isClosed) {
              roleRuntimeController.add(
                _AiSeminarRoleToolCallRuntimeStreamItem(agentRunEvent),
              );
            }
          }
        },
      );
      StreamSubscription<AiSeminarRoleStreamChunk>? roleStreamSubscription;
      try {
        var deltaIndex = 0;
        roleStreamSubscription = _streamRole(invocation, token).listen(
          (chunk) {
            if (!roleRuntimeController.isClosed) {
              roleRuntimeController.add(
                _AiSeminarRoleChunkRuntimeStreamItem(
                  chunk,
                  cancelledWhenReceived: token.isCancelled,
                ),
              );
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!roleRuntimeController.isClosed) {
              roleRuntimeController.addError(error, stackTrace);
            }
          },
          onDone: () {
            if (!roleRuntimeController.isClosed) {
              roleRuntimeController.add(
                const _AiSeminarRoleDoneRuntimeStreamItem(),
              );
            }
          },
        );
        await for (final runtimeItem in roleRuntimeController.stream) {
          if (runtimeItem is _AiSeminarRoleDoneRuntimeStreamItem) {
            break;
          }
          if (runtimeItem is _AiSeminarRoleToolCallRuntimeStreamItem) {
            yield _seminarRoleAgentToolCallRuntimeEvent(
              session: session,
              evidenceBundle: evidenceBundle,
              role: role,
              turns: turns,
              whiteboardEntries: _whiteboardEntries(turns),
              agentRunEvent: runtimeItem.event,
            );
            continue;
          }
          final chunk =
              (runtimeItem as _AiSeminarRoleChunkRuntimeStreamItem).chunk;
          final shouldPreserveCompletedTurnAfterCancel =
              chunk.completedTurn != null && !runtimeItem.cancelledWhenReceived;
          if (token.isCancelled && !shouldPreserveCompletedTurnAfterCancel) {
            yield await _recordTerminalRun(_cancelledEvent(
              session: session,
              evidenceBundle: evidenceBundle,
              startedAt: startedAt,
              turns: turns,
            ));
            return;
          }
          final thinkingText = chunk.thinkingText?.trim();
          if (thinkingText != null && thinkingText.isNotEmpty) {
            final agentRunEvent = await _upsertSeminarRoleStreamThinkingEvent(
              session: session,
              role: role,
              runId: roleRunId,
              thinkingText: thinkingText,
            );
            yield AiSeminarRuntimeEvent(
              type: AiSeminarRuntimeEventType.roleThinking,
              session: session,
              status: AiSeminarRunStatus.running,
              evidenceBundle: evidenceBundle,
              activeRole: role,
              turns: List.unmodifiable(turns),
              whiteboardEntries: _whiteboardEntries(turns),
              agentRunEvent: agentRunEvent,
            );
          }
          final partialText = chunk.partialText;
          if (partialText != null) {
            final roleOutputLimit = session.budgetPolicy?.maxRoleOutputTokens;
            final partialOutputTokens = _estimateTokenCount(partialText);
            if (roleOutputLimit != null &&
                partialOutputTokens > roleOutputLimit) {
              final message =
                  'AI Seminar role ${role.asString} exceeded local role output token budget '
                  '($partialOutputTokens > $roleOutputLimit).';
              token.cancel();
              await _upsertSeminarRoleErroredStatus(
                session: session,
                role: role,
                runId: roleRunId,
                message: message,
              );
              yield await _recordTerminalRun(_failedEvent(
                session: session,
                evidenceBundle: evidenceBundle,
                startedAt: startedAt,
                turns: turns,
                message: message,
              ));
              return;
            }
            await _upsertSeminarRoleDeltaEvent(
              session: session,
              role: role,
              runId: roleRunId,
              deltaIndex: deltaIndex++,
              partialText: partialText,
            );
            yield AiSeminarRuntimeEvent(
              type: AiSeminarRuntimeEventType.roleDelta,
              session: session,
              status: AiSeminarRunStatus.running,
              evidenceBundle: evidenceBundle,
              activeRole: role,
              partialText: partialText,
              turns: List.unmodifiable(turns),
              whiteboardEntries: _whiteboardEntries(turns),
            );
          }
          if (chunk.completedTurn != null) {
            completedTurn = chunk.completedTurn;
          }
        }
      } catch (error) {
        await _upsertSeminarRoleErroredStatus(
          session: session,
          role: role,
          runId: roleRunId,
          message: error.toString(),
        );
        yield await _recordTerminalRun(_failedEvent(
          session: session,
          evidenceBundle: evidenceBundle,
          startedAt: startedAt,
          turns: turns,
          message: error.toString(),
        ));
        return;
      } finally {
        await roleStreamSubscription?.cancel();
        if (!roleRuntimeController.isClosed) {
          await roleRuntimeController.close();
        }
      }

      final turn = completedTurn;
      if (token.isCancelled && turn == null) {
        await _upsertSeminarRoleShutdownStatus(
          session: session,
          role: role,
          runId: roleRunId,
        );
        yield await _recordTerminalRun(_cancelledEvent(
          session: session,
          evidenceBundle: evidenceBundle,
          startedAt: startedAt,
          turns: turns,
        ));
        return;
      }
      if (turn == null) {
        final message = 'AI Seminar role ${role.asString} produced no turn.';
        await _upsertSeminarRoleErroredStatus(
          session: session,
          role: role,
          runId: roleRunId,
          message: message,
        );
        yield await _recordTerminalRun(_failedEvent(
          session: session,
          evidenceBundle: evidenceBundle,
          startedAt: startedAt,
          turns: turns,
          message: message,
        ));
        return;
      }
      if (turn.role != role) {
        final message =
            'AI Seminar executor returned ${turn.role.asString} for ${role.asString}.';
        await _upsertSeminarRoleErroredStatus(
          session: session,
          role: role,
          runId: roleRunId,
          message: message,
        );
        yield await _recordTerminalRun(_failedEvent(
          session: session,
          evidenceBundle: evidenceBundle,
          startedAt: startedAt,
          turns: turns,
          message: message,
        ));
        return;
      }
      if (turn.isFailed) {
        final message =
            turn.error ?? 'AI Seminar role ${role.asString} failed.';
        await _upsertSeminarRoleErroredStatus(
          session: session,
          role: role,
          runId: roleRunId,
          message: message,
        );
        yield await _recordTerminalRun(_failedEvent(
          session: session,
          evidenceBundle: evidenceBundle,
          startedAt: startedAt,
          turns: [...turns, _stripTokenUsage(turn)],
          message: message,
        ));
        return;
      }
      if (!turn.hasTraceableEvidence(roleTraceableEvidenceIds)) {
        await _upsertSeminarRoleInterruptedStatus(
          session: session,
          role: role,
          runId: roleRunId,
          message:
              'AI Seminar role ${role.asString} cited missing or untraceable evidence.',
        );
        yield await _recordTerminalRun(_needsEvidenceEvent(
          session: session,
          evidenceBundle: evidenceBundle,
          startedAt: startedAt,
          turns: turns,
          message:
              'AI Seminar role ${role.asString} cited missing or untraceable evidence.',
        ));
        return;
      }

      final localBudgetUsage = _estimatedTokenUsage(
        invocation: invocation,
        turn: turn,
      );
      final localBudgetTurn = _copyTurnWithTokenUsage(
        turn,
        localBudgetUsage,
      );
      final nextBudgetTurns = [...localBudgetTurns, localBudgetTurn];
      final budgetFailure = _budgetFailureMessage(
        session.budgetPolicy,
        localBudgetTurn,
        nextBudgetTurns,
      );
      if (budgetFailure != null) {
        await _upsertSeminarRoleErroredStatus(
          session: session,
          role: role,
          runId: roleRunId,
          message: budgetFailure,
        );
        yield await _recordTerminalRun(_failedEvent(
          session: session,
          evidenceBundle: evidenceBundle,
          startedAt: startedAt,
          turns: nextBudgetTurns,
          message: budgetFailure,
        ));
        return;
      }

      final turnWithUsage = _attachEstimatedTokenUsage(
        invocation: invocation,
        turn: turn,
      );
      final nextTurns = [...turns, turnWithUsage];
      final costFailure = _costBudgetFailureMessage(
        session.budgetPolicy,
        nextTurns,
      );
      if (costFailure != null) {
        await _upsertSeminarRoleErroredStatus(
          session: session,
          role: role,
          runId: roleRunId,
          message: costFailure,
        );
        yield await _recordTerminalRun(_failedEvent(
          session: session,
          evidenceBundle: evidenceBundle,
          startedAt: startedAt,
          turns: nextTurns,
          message: costFailure,
        ));
        return;
      }

      turns.add(turnWithUsage);
      await _agentRunGraphStore?.upsertFromSeminarRoleTurn(
        session: session,
        turn: turnWithUsage,
        runId: roleRunId,
        evidenceRefs: _seminarEvidenceSnapshotsForTurn(
          evidenceBundle,
          turnWithUsage,
        ),
      );
      localBudgetTurns.add(localBudgetTurn);
      final whiteboardEntries = _whiteboardEntries(turns);
      yield AiSeminarRuntimeEvent(
        type: AiSeminarRuntimeEventType.roleCompleted,
        session: session,
        status: AiSeminarRunStatus.running,
        evidenceBundle: evidenceBundle,
        activeRole: role,
        turn: turnWithUsage,
        turns: List.unmodifiable(turns),
        whiteboardEntries: whiteboardEntries,
      );
      yield AiSeminarRuntimeEvent(
        type: AiSeminarRuntimeEventType.whiteboardUpdated,
        session: session,
        status: AiSeminarRunStatus.running,
        evidenceBundle: evidenceBundle,
        turns: List.unmodifiable(turns),
        whiteboardEntries: whiteboardEntries,
      );
    }

    if (token.isCancelled) {
      yield await _recordTerminalRun(_cancelledEvent(
        session: session,
        evidenceBundle: evidenceBundle,
        startedAt: startedAt,
        turns: turns,
      ));
      return;
    }

    await _agentRunGraphStore?.upsertEvent(AgentRunEvent(
      eventId: '${session.id}:thinking:synthesis',
      runId: session.id,
      type: AgentRunEventType.thinking,
      createdAt: _nowDateTime(),
      roleId: 'director',
      nickname: 'Director',
      delta: 'Director is synthesizing the seminar into traceable conclusions.',
    ));
    final synthesis = AiSeminarOrchestrationService.synthesize(
      session: session,
      evidenceBundle: evidenceBundle,
      turns: turns,
    );
    final status = synthesis.hasTraceableHandoff
        ? AiSeminarRunStatus.completed
        : AiSeminarRunStatus.needsEvidence;
    final completedAt = _nowMs();
    final billingSnapshot = _billingSnapshot(
      session: session,
      turns: turns,
      completedAt: completedAt,
    );
    final tokenUsage = AiSeminarTokenUsage.aggregateRoleTurns(turns);
    final estimatedCostUsd = billingSnapshot?.estimatedCostUsd ??
        _estimatedRunCostUsd(session, turns);
    final costPriceSource =
        billingSnapshot?.pricingSource ?? _costPriceSource(session, turns);
    final run = AiSeminarRun(
      session: session,
      status: status,
      evidenceBundle: evidenceBundle,
      turns: List.unmodifiable(turns),
      synthesis: synthesis,
      startedAt: startedAt,
      completedAt: completedAt,
      tokenUsage: tokenUsage,
      estimatedCostUsd: estimatedCostUsd,
      costPriceSource: costPriceSource,
      billingSnapshot: billingSnapshot,
      message: status == AiSeminarRunStatus.needsEvidence
          ? 'AI Seminar synthesis is missing traceable handoff evidence.'
          : null,
    );
    await _agentRunGraphStore?.upsertFromSeminarRun(run);
    yield AiSeminarRuntimeEvent(
      type: status == AiSeminarRunStatus.completed
          ? AiSeminarRuntimeEventType.synthesisReady
          : AiSeminarRuntimeEventType.needsEvidence,
      session: session,
      status: status,
      evidenceBundle: evidenceBundle,
      turns: List.unmodifiable(turns),
      whiteboardEntries: _whiteboardEntries(turns),
      synthesis: synthesis,
      run: run,
      message: run.message,
    );
  }

  Future<void> recordDirectorWaitingInput({
    required AiSeminarSessionContract session,
    String? prompt,
  }) async {
    final store = _agentRunGraphStore;
    if (store == null) return;
    final createdAt = _nowDateTime();
    final trimmedPrompt = _trimmedOrNull(prompt);
    await store.upsertEvent(AgentRunEvent(
      eventId: '${session.id}:thinking:waiting_input',
      runId: session.id,
      type: AgentRunEventType.thinking,
      createdAt: createdAt,
      roleId: 'director',
      nickname: 'Director',
      delta: trimmedPrompt == null
          ? 'Director is waiting for reader input.'
          : 'Director is waiting for reader input: $trimmedPrompt',
    ));
    await store.upsertEvent(AgentRunEvent(
      eventId: '${session.id}:status:waiting_input',
      runId: session.id,
      type: AgentRunEventType.status,
      createdAt: createdAt,
      status: SubAgentRunStatus.waitingInput,
      roleId: 'director',
      nickname: 'Director',
      roleIds: _seminarReaderTargetRoleIds(session),
      delta: trimmedPrompt,
    ));
  }

  Stream<AiSeminarRuntimeEvent> runPendingAgentControl(
    AiSeminarSessionContract session, {
    required String childRunId,
    required AiSeminarEvidenceBundle evidenceBundle,
    required List<AiSeminarRoleTurn> priorTurns,
    AiSeminarCancellationToken? cancelToken,
    void Function(AiSeminarUserIntervention intervention)? onIntervention,
  }) async* {
    final store = _agentRunGraphStore;
    if (store == null) return;
    final normalizedChildRunId = childRunId.trim();
    if (normalizedChildRunId.isEmpty) return;
    final childRun = await store.getRun(normalizedChildRunId);
    if (childRun?.parentRunId != session.id) return;
    final controls = await store.listPendingControlEvents(
      parentRunId: session.id,
      childRunId: normalizedChildRunId,
    );
    if (controls.isEmpty) return;
    final control = _preferredPendingControlForRun(
      controls,
      status: childRun!.status,
    );
    final intervention = _interventionFromControlEvent(
      control,
      fallbackRoleId: childRun.roleId,
    );
    if (intervention == null || intervention.targetRole == null) return;
    onIntervention?.call(intervention);
    final controlPriorTurns = _priorTurnsForPendingControl(
      priorTurns: priorTurns,
      control: control,
      targetRole: intervention.targetRole!,
    );

    var completedControlledRole = false;
    await for (final event in runUserDirectedRole(
      session,
      evidenceBundle: evidenceBundle,
      priorTurns: controlPriorTurns,
      intervention: intervention,
      targetRole: intervention.targetRole!,
      agentRunId: normalizedChildRunId,
      cancelToken: cancelToken,
    )) {
      if (event.type == AiSeminarRuntimeEventType.roleCompleted) {
        completedControlledRole = true;
      }
      yield event;
    }
    if (!completedControlledRole) return;
    await store.acknowledgeControlEvent(
      parentRunId: session.id,
      childRunId: normalizedChildRunId,
      eventId: control.eventId,
      now: _nowDateTime(),
    );
  }

  Stream<AiSeminarRuntimeEvent> runUserDirectedRole(
    AiSeminarSessionContract session, {
    required AiSeminarEvidenceBundle evidenceBundle,
    required List<AiSeminarRoleTurn> priorTurns,
    required AiSeminarUserIntervention intervention,
    required AiSeminarRole targetRole,
    String? agentRunId,
    AiSeminarCancellationToken? cancelToken,
  }) async* {
    final token = cancelToken ?? AiSeminarCancellationToken();
    final startedAt = _nowMs();
    final roleRunId = _trimmedOrNull(agentRunId) ??
        _seminarRoleRunId(
          session: session,
          role: targetRole,
          index: priorTurns.length,
        );
    if (evidenceBundle.evidence.isEmpty ||
        !evidenceBundle.allEvidenceTraceable) {
      const message = 'AI Seminar requires traceable current-source evidence.';
      await _upsertSeminarRoleInterruptedStatus(
        session: session,
        role: targetRole,
        runId: roleRunId,
        message: message,
      );
      yield _needsEvidenceEvent(
        session: session,
        evidenceBundle: evidenceBundle,
        startedAt: startedAt,
        turns: priorTurns,
        message: message,
      );
      return;
    }

    final traceableEvidenceIds = _traceableEvidenceIds(evidenceBundle);
    if (priorTurns.any(
      (turn) =>
          turn.isFailed || !turn.hasTraceableEvidence(traceableEvidenceIds),
    )) {
      const message =
          'AI Seminar prior turns need traceable evidence before a reader-directed role can continue.';
      await _upsertSeminarRoleInterruptedStatus(
        session: session,
        role: targetRole,
        runId: roleRunId,
        message: message,
      );
      yield _needsEvidenceEvent(
        session: session,
        evidenceBundle: evidenceBundle,
        startedAt: startedAt,
        turns: priorTurns,
        message: message,
      );
      return;
    }

    final turns = List<AiSeminarRoleTurn>.from(
      _checkpointTurnsWithTokenUsage(
        session: session,
        evidenceBundle: evidenceBundle,
        turns: priorTurns,
      ),
    );
    final localBudgetTurns = _localBudgetTurnsForCheckpoint(
      session: session,
      evidenceBundle: evidenceBundle,
      turns: priorTurns,
    );
    final whiteboardEntries = _whiteboardEntries(turns);
    final roleEvidenceBundle =
        AiSeminarOrchestrationService.evidenceBundleForRole(
      session: session,
      role: targetRole,
      evidenceBundle: evidenceBundle,
    );
    final roleTraceableEvidenceIds = _traceableEvidenceIds(roleEvidenceBundle);
    await _agentRunGraphStore?.upsertFromSeminarRoleStart(
      session: session,
      role: targetRole,
      runId: roleRunId,
      startedAt: _nowDateTime(),
    );
    await _upsertSeminarRoleToolCallEvents(
      session: session,
      role: targetRole,
      runId: roleRunId,
      evidenceBundle: roleEvidenceBundle,
    );
    await _upsertSeminarRoleThinkingEvent(
      session: session,
      role: targetRole,
      runId: roleRunId,
    );
    yield AiSeminarRuntimeEvent(
      type: AiSeminarRuntimeEventType.roleStarted,
      session: session,
      status: AiSeminarRunStatus.running,
      evidenceBundle: evidenceBundle,
      activeRole: targetRole,
      turns: List.unmodifiable(turns),
      whiteboardEntries: whiteboardEntries,
    );

    final roleRuntimeController =
        StreamController<_AiSeminarRoleRuntimeStreamItem>();
    final invocation = AiSeminarRoleInvocation(
      session: session,
      role: targetRole,
      evidenceBundle: roleEvidenceBundle,
      priorTurns: List.unmodifiable(turns),
      prompt: AiSeminarOrchestrationService.promptForUserInterventionRole(
        session: session,
        role: targetRole,
        evidenceBundle: roleEvidenceBundle,
        priorTurns: turns,
        intervention: intervention,
      ),
      toolCallObserver: (event) async {
        final agentRunEvent = await _upsertSeminarRoleAgentToolCallEvent(
          session: session,
          role: targetRole,
          runId: roleRunId,
          event: event,
        );
        if (agentRunEvent != null) {
          if (!roleRuntimeController.isClosed) {
            roleRuntimeController.add(
              _AiSeminarRoleToolCallRuntimeStreamItem(agentRunEvent),
            );
          }
        }
      },
    );
    AiSeminarRoleTurn? completedTurn;
    StreamSubscription<AiSeminarRoleStreamChunk>? roleStreamSubscription;
    try {
      var deltaIndex = 0;
      roleStreamSubscription = _streamRole(invocation, token).listen(
        (chunk) {
          if (!roleRuntimeController.isClosed) {
            roleRuntimeController.add(
              _AiSeminarRoleChunkRuntimeStreamItem(
                chunk,
                cancelledWhenReceived: token.isCancelled,
              ),
            );
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!roleRuntimeController.isClosed) {
            roleRuntimeController.addError(error, stackTrace);
          }
        },
        onDone: () {
          if (!roleRuntimeController.isClosed) {
            roleRuntimeController.add(
              const _AiSeminarRoleDoneRuntimeStreamItem(),
            );
          }
        },
      );
      await for (final runtimeItem in roleRuntimeController.stream) {
        if (runtimeItem is _AiSeminarRoleDoneRuntimeStreamItem) {
          break;
        }
        if (runtimeItem is _AiSeminarRoleToolCallRuntimeStreamItem) {
          yield _seminarRoleAgentToolCallRuntimeEvent(
            session: session,
            evidenceBundle: evidenceBundle,
            role: targetRole,
            turns: turns,
            whiteboardEntries: whiteboardEntries,
            agentRunEvent: runtimeItem.event,
          );
          continue;
        }
        final chunk =
            (runtimeItem as _AiSeminarRoleChunkRuntimeStreamItem).chunk;
        final shouldPreserveCompletedTurnAfterCancel =
            chunk.completedTurn != null && !runtimeItem.cancelledWhenReceived;
        if (token.isCancelled && !shouldPreserveCompletedTurnAfterCancel) {
          await _upsertSeminarRoleShutdownStatus(
            session: session,
            role: targetRole,
            runId: roleRunId,
          );
          yield await _recordTerminalRun(_cancelledEvent(
            session: session,
            evidenceBundle: evidenceBundle,
            startedAt: startedAt,
            turns: turns,
          ));
          return;
        }
        final thinkingText = chunk.thinkingText?.trim();
        if (thinkingText != null && thinkingText.isNotEmpty) {
          final agentRunEvent = await _upsertSeminarRoleStreamThinkingEvent(
            session: session,
            role: targetRole,
            runId: roleRunId,
            thinkingText: thinkingText,
          );
          yield AiSeminarRuntimeEvent(
            type: AiSeminarRuntimeEventType.roleThinking,
            session: session,
            status: AiSeminarRunStatus.running,
            evidenceBundle: evidenceBundle,
            activeRole: targetRole,
            turns: List.unmodifiable(turns),
            whiteboardEntries: whiteboardEntries,
            agentRunEvent: agentRunEvent,
          );
        }
        final partialText = chunk.partialText;
        if (partialText != null) {
          final roleOutputLimit = session.budgetPolicy?.maxRoleOutputTokens;
          final partialOutputTokens = _estimateTokenCount(partialText);
          if (roleOutputLimit != null &&
              partialOutputTokens > roleOutputLimit) {
            final message =
                'AI Seminar role ${targetRole.asString} exceeded local role output token budget '
                '($partialOutputTokens > $roleOutputLimit).';
            token.cancel();
            await _upsertSeminarRoleErroredStatus(
              session: session,
              role: targetRole,
              runId: roleRunId,
              message: message,
            );
            yield _failedEvent(
              session: session,
              evidenceBundle: evidenceBundle,
              startedAt: startedAt,
              turns: turns,
              message: message,
            );
            return;
          }
          await _upsertSeminarRoleDeltaEvent(
            session: session,
            role: targetRole,
            runId: roleRunId,
            deltaIndex: deltaIndex++,
            partialText: partialText,
          );
          yield AiSeminarRuntimeEvent(
            type: AiSeminarRuntimeEventType.roleDelta,
            session: session,
            status: AiSeminarRunStatus.running,
            evidenceBundle: evidenceBundle,
            activeRole: targetRole,
            partialText: partialText,
            turns: List.unmodifiable(turns),
            whiteboardEntries: _whiteboardEntries(turns),
          );
        }
        if (chunk.completedTurn != null) {
          completedTurn = chunk.completedTurn;
        }
      }
    } catch (error) {
      await _upsertSeminarRoleErroredStatus(
        session: session,
        role: targetRole,
        runId: roleRunId,
        message: error.toString(),
      );
      yield _failedEvent(
        session: session,
        evidenceBundle: evidenceBundle,
        startedAt: startedAt,
        turns: turns,
        message: error.toString(),
      );
      return;
    } finally {
      await roleStreamSubscription?.cancel();
      if (!roleRuntimeController.isClosed) {
        await roleRuntimeController.close();
      }
    }

    final turn = completedTurn;
    if (token.isCancelled && turn == null) {
      await _upsertSeminarRoleShutdownStatus(
        session: session,
        role: targetRole,
        runId: roleRunId,
      );
      yield await _recordTerminalRun(_cancelledEvent(
        session: session,
        evidenceBundle: evidenceBundle,
        startedAt: startedAt,
        turns: turns,
      ));
      return;
    }
    if (turn == null) {
      final message =
          'AI Seminar role ${targetRole.asString} produced no turn.';
      await _upsertSeminarRoleErroredStatus(
        session: session,
        role: targetRole,
        runId: roleRunId,
        message: message,
      );
      yield _failedEvent(
        session: session,
        evidenceBundle: evidenceBundle,
        startedAt: startedAt,
        turns: turns,
        message: message,
      );
      return;
    }
    if (turn.role != targetRole) {
      final message =
          'AI Seminar executor returned ${turn.role.asString} for ${targetRole.asString}.';
      await _upsertSeminarRoleErroredStatus(
        session: session,
        role: targetRole,
        runId: roleRunId,
        message: message,
      );
      yield _failedEvent(
        session: session,
        evidenceBundle: evidenceBundle,
        startedAt: startedAt,
        turns: turns,
        message: message,
      );
      return;
    }
    if (turn.isFailed) {
      final message =
          turn.error ?? 'AI Seminar role ${targetRole.asString} failed.';
      await _upsertSeminarRoleErroredStatus(
        session: session,
        role: targetRole,
        runId: roleRunId,
        message: message,
      );
      yield _failedEvent(
        session: session,
        evidenceBundle: evidenceBundle,
        startedAt: startedAt,
        turns: [...turns, _stripTokenUsage(turn)],
        message: message,
      );
      return;
    }
    if (!turn.hasTraceableEvidence(roleTraceableEvidenceIds)) {
      await _upsertSeminarRoleInterruptedStatus(
        session: session,
        role: targetRole,
        runId: roleRunId,
        message:
            'AI Seminar role ${targetRole.asString} cited missing or untraceable evidence.',
      );
      yield _needsEvidenceEvent(
        session: session,
        evidenceBundle: evidenceBundle,
        startedAt: startedAt,
        turns: turns,
        message:
            'AI Seminar role ${targetRole.asString} cited missing or untraceable evidence.',
      );
      return;
    }

    final localBudgetTurn = _copyTurnWithTokenUsage(
      turn,
      _estimatedTokenUsage(invocation: invocation, turn: turn),
    );
    final nextBudgetTurns = [...localBudgetTurns, localBudgetTurn];
    final budgetFailure = _budgetFailureMessage(
      session.budgetPolicy,
      localBudgetTurn,
      nextBudgetTurns,
    );
    if (budgetFailure != null) {
      await _upsertSeminarRoleErroredStatus(
        session: session,
        role: targetRole,
        runId: roleRunId,
        message: budgetFailure,
      );
      yield _failedEvent(
        session: session,
        evidenceBundle: evidenceBundle,
        startedAt: startedAt,
        turns: nextBudgetTurns,
        message: budgetFailure,
      );
      return;
    }

    final turnWithUsage = _attachEstimatedTokenUsage(
      invocation: invocation,
      turn: turn,
    );
    final nextTurns = [...turns, turnWithUsage];
    final costFailure = _costBudgetFailureMessage(
      session.budgetPolicy,
      nextTurns,
    );
    if (costFailure != null) {
      await _upsertSeminarRoleErroredStatus(
        session: session,
        role: targetRole,
        runId: roleRunId,
        message: costFailure,
      );
      yield _failedEvent(
        session: session,
        evidenceBundle: evidenceBundle,
        startedAt: startedAt,
        turns: nextTurns,
        message: costFailure,
      );
      return;
    }

    await _agentRunGraphStore?.upsertFromSeminarRoleTurn(
      session: session,
      turn: turnWithUsage,
      runId: roleRunId,
      evidenceRefs: _seminarEvidenceSnapshotsForTurn(
        evidenceBundle,
        turnWithUsage,
      ),
    );
    final nextWhiteboardEntries = _whiteboardEntries(nextTurns);
    yield AiSeminarRuntimeEvent(
      type: AiSeminarRuntimeEventType.roleCompleted,
      session: session,
      status: AiSeminarRunStatus.running,
      evidenceBundle: evidenceBundle,
      activeRole: targetRole,
      turn: turnWithUsage,
      turns: List.unmodifiable(nextTurns),
      whiteboardEntries: nextWhiteboardEntries,
    );
    yield AiSeminarRuntimeEvent(
      type: AiSeminarRuntimeEventType.whiteboardUpdated,
      session: session,
      status: AiSeminarRunStatus.running,
      evidenceBundle: evidenceBundle,
      turns: List.unmodifiable(nextTurns),
      whiteboardEntries: nextWhiteboardEntries,
    );
  }

  AiSeminarRuntimeEvent _failedEvent({
    required AiSeminarSessionContract session,
    required AiSeminarEvidenceBundle evidenceBundle,
    required int startedAt,
    List<AiSeminarRoleTurn> turns = const <AiSeminarRoleTurn>[],
    String? message,
  }) {
    final completedAt = _nowMs();
    final billingSnapshot = _billingSnapshot(
      session: session,
      turns: turns,
      completedAt: completedAt,
    );
    final tokenUsage = AiSeminarTokenUsage.aggregateRoleTurns(turns);
    final estimatedCostUsd = billingSnapshot?.estimatedCostUsd ??
        _estimatedRunCostUsd(session, turns);
    final costPriceSource =
        billingSnapshot?.pricingSource ?? _costPriceSource(session, turns);
    final run = AiSeminarRun(
      session: session,
      status: AiSeminarRunStatus.failed,
      evidenceBundle: evidenceBundle,
      turns: List.unmodifiable(turns),
      startedAt: startedAt,
      completedAt: completedAt,
      tokenUsage: tokenUsage,
      estimatedCostUsd: estimatedCostUsd,
      costPriceSource: costPriceSource,
      billingSnapshot: billingSnapshot,
      message: message,
    );
    return AiSeminarRuntimeEvent(
      type: AiSeminarRuntimeEventType.failed,
      session: session,
      status: AiSeminarRunStatus.failed,
      evidenceBundle: evidenceBundle,
      turns: List.unmodifiable(turns),
      whiteboardEntries: _whiteboardEntries(turns),
      run: run,
      message: message,
    );
  }

  Future<AiSeminarRuntimeEvent> _recordTerminalRun(
    AiSeminarRuntimeEvent event,
  ) async {
    final run = event.run;
    if (run != null) {
      await _agentRunGraphStore?.upsertFromSeminarRun(run);
    }
    return event;
  }

  AiSeminarRuntimeEvent _needsEvidenceEvent({
    required AiSeminarSessionContract session,
    required AiSeminarEvidenceBundle evidenceBundle,
    required int startedAt,
    List<AiSeminarRoleTurn> turns = const <AiSeminarRoleTurn>[],
    String? message,
  }) {
    final completedAt = _nowMs();
    final billingSnapshot = _billingSnapshot(
      session: session,
      turns: turns,
      completedAt: completedAt,
    );
    final tokenUsage = AiSeminarTokenUsage.aggregateRoleTurns(turns);
    final estimatedCostUsd = billingSnapshot?.estimatedCostUsd ??
        _estimatedRunCostUsd(session, turns);
    final costPriceSource =
        billingSnapshot?.pricingSource ?? _costPriceSource(session, turns);
    final run = AiSeminarRun(
      session: session,
      status: AiSeminarRunStatus.needsEvidence,
      evidenceBundle: evidenceBundle,
      turns: List.unmodifiable(turns),
      startedAt: startedAt,
      completedAt: completedAt,
      tokenUsage: tokenUsage,
      estimatedCostUsd: estimatedCostUsd,
      costPriceSource: costPriceSource,
      billingSnapshot: billingSnapshot,
      message: message,
    );
    return AiSeminarRuntimeEvent(
      type: AiSeminarRuntimeEventType.needsEvidence,
      session: session,
      status: AiSeminarRunStatus.needsEvidence,
      evidenceBundle: evidenceBundle,
      turns: List.unmodifiable(turns),
      whiteboardEntries: _whiteboardEntries(turns),
      run: run,
      message: message,
    );
  }

  AiSeminarRuntimeEvent _cancelledEvent({
    required AiSeminarSessionContract session,
    required AiSeminarEvidenceBundle evidenceBundle,
    required int startedAt,
    List<AiSeminarRoleTurn> turns = const <AiSeminarRoleTurn>[],
  }) {
    final completedAt = _nowMs();
    final billingSnapshot = _billingSnapshot(
      session: session,
      turns: turns,
      completedAt: completedAt,
    );
    final tokenUsage = AiSeminarTokenUsage.aggregateRoleTurns(turns);
    final estimatedCostUsd = billingSnapshot?.estimatedCostUsd ??
        _estimatedRunCostUsd(session, turns);
    final costPriceSource =
        billingSnapshot?.pricingSource ?? _costPriceSource(session, turns);
    final run = AiSeminarRun(
      session: session,
      status: AiSeminarRunStatus.cancelled,
      evidenceBundle: evidenceBundle,
      turns: List.unmodifiable(turns),
      startedAt: startedAt,
      completedAt: completedAt,
      tokenUsage: tokenUsage,
      estimatedCostUsd: estimatedCostUsd,
      costPriceSource: costPriceSource,
      billingSnapshot: billingSnapshot,
      message: 'AI Seminar cancelled.',
    );
    return AiSeminarRuntimeEvent(
      type: AiSeminarRuntimeEventType.cancelled,
      session: session,
      status: AiSeminarRunStatus.cancelled,
      evidenceBundle: evidenceBundle,
      turns: List.unmodifiable(turns),
      whiteboardEntries: _whiteboardEntries(turns),
      run: run,
      message: run.message,
    );
  }

  int _nowMs() => _now?.call() ?? DateTime.now().millisecondsSinceEpoch;

  DateTime _nowDateTime() => DateTime.fromMillisecondsSinceEpoch(_nowMs());

  String? _trimmedOrNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  AiSeminarUserIntervention? _interventionFromControlEvent(
    AgentRunEvent event, {
    required String? fallbackRoleId,
  }) {
    if (event.type != AgentRunEventType.userInput &&
        event.type != AgentRunEventType.resumeRequest &&
        event.type != AgentRunEventType.retryRequest) {
      return null;
    }
    final text = _trimmedOrNull(event.delta) ??
        switch (event.type) {
          AgentRunEventType.resumeRequest => 'Resume requested.',
          AgentRunEventType.retryRequest => 'Retry requested.',
          _ => null,
        };
    if (text == null) return null;
    final targetRole = AiSeminarRole.fromString(event.roleId) ??
        AiSeminarRole.fromString(fallbackRoleId);
    if (targetRole == null) return null;
    return AiSeminarUserIntervention(
      id: event.eventId,
      text: text,
      requestedAction: AiSeminarUserInterventionAction.askRole,
      targetRole: targetRole,
      createdAt: event.createdAt.millisecondsSinceEpoch,
    );
  }

  AgentRunEvent _preferredPendingControlForRun(
    List<AgentRunEvent> controls, {
    required SubAgentRunStatus status,
  }) {
    final preferredType = switch (status) {
      SubAgentRunStatus.errored => AgentRunEventType.retryRequest,
      SubAgentRunStatus.interrupted => AgentRunEventType.resumeRequest,
      SubAgentRunStatus.waitingInput => AgentRunEventType.userInput,
      _ => null,
    };
    if (preferredType != null) {
      for (final control in controls) {
        if (control.type == preferredType) return control;
      }
    }
    return controls.first;
  }

  List<AiSeminarRoleTurn> _priorTurnsForPendingControl({
    required List<AiSeminarRoleTurn> priorTurns,
    required AgentRunEvent control,
    required AiSeminarRole targetRole,
  }) {
    if (control.type != AgentRunEventType.retryRequest) {
      return priorTurns;
    }
    return priorTurns
        .where((turn) => !(turn.role == targetRole && turn.isFailed))
        .toList(growable: false);
  }

  List<String> _seminarReaderTargetRoleIds(AiSeminarSessionContract session) {
    final roles = session.roles.isEmpty
        ? AiSeminarRole.defaultRoles
        : session.roles.toList(growable: false);
    final nonSynthesizerRoles = roles
        .where((role) => role != AiSeminarRole.synthesizer)
        .toList(growable: false);
    final effectiveRoles =
        nonSynthesizerRoles.isEmpty ? roles : nonSynthesizerRoles;
    return effectiveRoles
        .map((role) => role.asString)
        .where((roleId) => roleId.trim().isNotEmpty)
        .toList(growable: false);
  }

  static String _seminarRoleRunId({
    required AiSeminarSessionContract session,
    required AiSeminarRole role,
    required int index,
  }) =>
      '${session.id}:role-${role.asString}-$index';

  Future<void> _upsertSeminarRoleDeltaEvent({
    required AiSeminarSessionContract session,
    required AiSeminarRole role,
    required String runId,
    required int deltaIndex,
    required String partialText,
  }) async {
    await _agentRunGraphStore?.upsertEvent(AgentRunEvent(
      eventId: '$runId:delta:$deltaIndex',
      runId: runId,
      parentRunId: session.id,
      type: AgentRunEventType.messageDelta,
      createdAt: _nowDateTime(),
      roleId: role.asString,
      nickname: seminarRoleNickname(role),
      delta: partialText,
    ));
  }

  Future<void> _upsertSeminarRoleThinkingEvent({
    required AiSeminarSessionContract session,
    required AiSeminarRole role,
    required String runId,
  }) async {
    final nickname = seminarRoleNickname(role);
    await _agentRunGraphStore?.upsertEvent(AgentRunEvent(
      eventId: '$runId:thinking:start',
      runId: runId,
      parentRunId: session.id,
      type: AgentRunEventType.thinking,
      createdAt: _nowDateTime(),
      roleId: role.asString,
      nickname: nickname,
      delta: '$nickname is preparing an evidence-grounded seminar response.',
    ));
  }

  Future<AgentRunEvent> _upsertSeminarRoleStreamThinkingEvent({
    required AiSeminarSessionContract session,
    required AiSeminarRole role,
    required String runId,
    required String thinkingText,
  }) async {
    final nickname = seminarRoleNickname(role);
    final event = AgentRunEvent(
      eventId: '$runId:thinking:stream:0',
      runId: runId,
      parentRunId: session.id,
      type: AgentRunEventType.thinking,
      createdAt: _nowDateTime(),
      roleId: role.asString,
      nickname: nickname,
      delta: thinkingText,
    );
    await _agentRunGraphStore?.upsertEvent(event);
    return event;
  }

  Future<void> _upsertSeminarRoleInterruptedStatus({
    required AiSeminarSessionContract session,
    required AiSeminarRole role,
    required String runId,
    required String message,
  }) async {
    final store = _agentRunGraphStore;
    if (store == null) return;
    final now = _nowDateTime();
    final existing = await store.getRun(runId);
    final finishedAt = existing == null || now.isAfter(existing.startedAt)
        ? now
        : existing.startedAt.add(const Duration(microseconds: 1));
    final base = existing ??
        AgentRunRecord.fromSeminarRoleStart(
          session: session,
          role: role,
          runId: runId,
          startedAt: finishedAt,
        );
    await store.upsertRun(base.copyWith(
      status: SubAgentRunStatus.interrupted,
      finishedAt: finishedAt,
      error: message,
    ));
  }

  Future<void> _upsertSeminarRoleErroredStatus({
    required AiSeminarSessionContract session,
    required AiSeminarRole role,
    required String runId,
    required String message,
  }) async {
    final store = _agentRunGraphStore;
    if (store == null) return;
    final now = _nowDateTime();
    final existing = await store.getRun(runId);
    final finishedAt = existing == null || now.isAfter(existing.startedAt)
        ? now
        : existing.startedAt.add(const Duration(microseconds: 1));
    final base = existing ??
        AgentRunRecord.fromSeminarRoleStart(
          session: session,
          role: role,
          runId: runId,
          startedAt: finishedAt,
        );
    await store.upsertRun(base.copyWith(
      status: SubAgentRunStatus.errored,
      finishedAt: finishedAt,
      error: message,
    ));
  }

  Future<void> _upsertSeminarRoleShutdownStatus({
    required AiSeminarSessionContract session,
    required AiSeminarRole role,
    required String runId,
  }) async {
    final store = _agentRunGraphStore;
    if (store == null) return;
    final now = _nowDateTime();
    final existing = await store.getRun(runId);
    final finishedAt = existing == null || now.isAfter(existing.startedAt)
        ? now
        : existing.startedAt.add(const Duration(microseconds: 1));
    final base = existing ??
        AgentRunRecord.fromSeminarRoleStart(
          session: session,
          role: role,
          runId: runId,
          startedAt: finishedAt,
        );
    await store.upsertRun(base.copyWith(
      status: SubAgentRunStatus.shutdown,
      finishedAt: finishedAt,
      error: 'AI Seminar role cancelled.',
    ));
  }

  Future<void> _upsertSeminarRoleToolCallEvents({
    required AiSeminarSessionContract session,
    required AiSeminarRole role,
    required String runId,
    required AiSeminarEvidenceBundle evidenceBundle,
  }) async {
    final store = _agentRunGraphStore;
    if (store == null) return;
    final allowedToolIds = _effectiveSeminarRoleToolIds(
      session: session,
      role: role,
    );
    if (allowedToolIds.isEmpty) return;

    final evidenceByToolId = <String, List<AiSeminarEvidence>>{};
    for (final evidence in evidenceBundle.evidence) {
      if (!evidence.isTraceable) continue;
      final toolId = _seminarEvidenceScopeToolId(evidence.scope);
      if (toolId == null || !allowedToolIds.contains(toolId)) continue;
      evidenceByToolId.putIfAbsent(toolId, () => <AiSeminarEvidence>[]).add(
            evidence,
          );
    }

    final query = evidenceBundle.query.trim().isNotEmpty
        ? evidenceBundle.query.trim()
        : session.question.trim();
    final roleId = role.asString;
    for (final toolId in allowedToolIds) {
      final evidence = evidenceByToolId[toolId] ?? const <AiSeminarEvidence>[];
      if (evidence.isEmpty) continue;
      await store.upsertEvent(AgentRunEvent(
        eventId: '$runId:tool:$toolId',
        runId: runId,
        parentRunId: session.id,
        type: AgentRunEventType.toolCall,
        createdAt: _nowDateTime(),
        status: SubAgentRunStatus.completed,
        roleId: roleId,
        nickname: seminarRoleNickname(role),
        toolId: toolId,
        query: query,
        result: _seminarEvidenceToolCallResultText(evidence.length),
        resultCount: evidence.length,
        roleIds: [roleId],
        evidenceRefs: evidence
            .map(_seminarEvidenceSnapshotFromEvidence)
            .where((snapshot) => !snapshot.isEmpty)
            .toList(growable: false),
      ));
    }
  }

  Future<AgentRunEvent?> _upsertSeminarRoleAgentToolCallEvent({
    required AiSeminarSessionContract session,
    required AiSeminarRole role,
    required String runId,
    required AgentToolCallEvent event,
  }) async {
    final agentRunEvent = _seminarRoleAgentToolCallRunEvent(
      session: session,
      role: role,
      runId: runId,
      event: event,
    );
    if (agentRunEvent == null) return null;
    await _agentRunGraphStore?.upsertEvent(agentRunEvent);
    return agentRunEvent;
  }

  AgentRunEvent? _seminarRoleAgentToolCallRunEvent({
    required AiSeminarSessionContract session,
    required AiSeminarRole role,
    required String runId,
    required AgentToolCallEvent event,
  }) {
    final toolId = event.toolId.trim();
    if (toolId.isEmpty) return null;
    final allowedToolIds = _effectiveSeminarRoleToolIds(
      session: session,
      role: role,
    ).toSet();
    if (!allowedToolIds.contains(toolId)) return null;
    final roleId = role.asString;
    return AgentRunEvent(
      eventId: '$runId:tool:${agentToolCallEventIdSegment(event)}',
      runId: runId,
      parentRunId: session.id,
      type: AgentRunEventType.toolCall,
      createdAt: _nowDateTime(),
      status: _subAgentStatusForToolCall(event.status),
      roleId: roleId,
      nickname: seminarRoleNickname(role),
      toolId: toolId,
      query: _queryFromToolInput(event.input),
      result: event.output,
      error: event.error,
      resultCount: event.resultCount ?? 0,
      roleIds: [roleId],
      actionIds: _seminarRoleAgentToolCallActionIds(event.status),
    );
  }

  static List<String> _seminarRoleAgentToolCallActionIds(
    AgentToolCallEventStatus status,
  ) {
    return switch (status) {
      AgentToolCallEventStatus.running => const [
          'wait-tool-call',
          'cancel-tool-call',
        ],
      AgentToolCallEventStatus.completed ||
      AgentToolCallEventStatus.errored =>
        const <String>[],
    };
  }

  static AiSeminarRuntimeEvent _seminarRoleAgentToolCallRuntimeEvent({
    required AiSeminarSessionContract session,
    required AiSeminarEvidenceBundle evidenceBundle,
    required AiSeminarRole role,
    required List<AiSeminarRoleTurn> turns,
    required List<AiSeminarWhiteboardEntry> whiteboardEntries,
    required AgentRunEvent agentRunEvent,
  }) {
    return AiSeminarRuntimeEvent(
      type: AiSeminarRuntimeEventType.roleToolCall,
      session: session,
      status: AiSeminarRunStatus.running,
      evidenceBundle: evidenceBundle,
      activeRole: role,
      turns: List.unmodifiable(turns),
      whiteboardEntries: whiteboardEntries,
      agentRunEvent: agentRunEvent,
    );
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

  Future<void> _upsertSeminarEvidenceToolCallEvents({
    required AiSeminarSessionContract session,
    required AiSeminarEvidenceBundle evidenceBundle,
  }) async {
    final store = _agentRunGraphStore;
    if (store == null) return;
    final evidenceByToolId = <String, List<AiSeminarEvidence>>{};
    for (final evidence in evidenceBundle.evidence) {
      if (!evidence.isTraceable) continue;
      final toolId = _seminarEvidenceScopeToolId(evidence.scope);
      if (toolId == null || toolId.isEmpty) continue;
      evidenceByToolId.putIfAbsent(toolId, () => <AiSeminarEvidence>[]).add(
            evidence,
          );
    }
    final query = evidenceBundle.query.trim().isNotEmpty
        ? evidenceBundle.query.trim()
        : session.question.trim();
    for (final scope in _sessionEvidenceToolCallScopes(session)) {
      final toolId = _seminarEvidenceScopeToolId(scope);
      if (toolId == null || toolId.isEmpty) continue;
      final evidence = evidenceByToolId[toolId] ?? const <AiSeminarEvidence>[];
      final eventId = '${session.id}:tool:${scope.asString}';
      await store.upsertEvent(AgentRunEvent(
        eventId: eventId,
        runId: eventId,
        parentRunId: session.id,
        type: AgentRunEventType.toolCall,
        createdAt: _nowDateTime(),
        status: SubAgentRunStatus.completed,
        toolId: toolId,
        query: query,
        result: _seminarEvidenceToolCallResultText(evidence.length),
        resultCount: evidence.length,
        roleIds: _seminarToolCallRoleIdsForScope(session, scope),
        evidenceRefs: evidence
            .map(_seminarEvidenceSnapshotFromEvidence)
            .where((snapshot) => !snapshot.isEmpty)
            .toList(growable: false),
      ));
    }
  }

  Future<void> _upsertSeminarEvidenceToolCallStatusEvents({
    required AiSeminarSessionContract session,
    required SubAgentRunStatus status,
    String? error,
  }) async {
    final store = _agentRunGraphStore;
    if (store == null) return;
    final query = session.question.trim();
    for (final scope in _sessionEvidenceToolCallScopes(session)) {
      final toolId = _seminarEvidenceScopeToolId(scope);
      if (toolId == null || toolId.isEmpty) continue;
      final eventId = '${session.id}:tool:${scope.asString}';
      await store.upsertEvent(AgentRunEvent(
        eventId: eventId,
        runId: eventId,
        parentRunId: session.id,
        type: AgentRunEventType.toolCall,
        createdAt: _nowDateTime(),
        status: status,
        toolId: toolId,
        query: query,
        roleIds: _seminarToolCallRoleIdsForScope(session, scope),
        error: error,
      ));
    }
  }

  static List<AiSeminarEvidenceScope> _sessionEvidenceToolCallScopes(
    AiSeminarSessionContract session,
  ) {
    final out = <AiSeminarEvidenceScope>[];
    final seenToolIds = <String>{};
    for (final scope in session.scopes) {
      final toolId = _seminarEvidenceScopeToolId(scope);
      if (toolId == null || toolId.isEmpty || !seenToolIds.add(toolId)) {
        continue;
      }
      out.add(scope);
    }
    return out;
  }

  static String _seminarEvidenceToolCallResultText(int resultCount) {
    if (resultCount == 1) {
      return 'Returned 1 traceable evidence chunk.';
    }
    return 'Returned $resultCount traceable evidence chunks.';
  }

  static String? _seminarEvidenceScopeToolId(AiSeminarEvidenceScope scope) {
    switch (scope) {
      case AiSeminarEvidenceScope.currentChapter:
      case AiSeminarEvidenceScope.currentBook:
        return 'semantic_search_current_book';
      case AiSeminarEvidenceScope.library:
        return 'semantic_search_library';
      case AiSeminarEvidenceScope.notes:
        return 'notes_search';
      case AiSeminarEvidenceScope.memory:
        return 'memory_search';
      case AiSeminarEvidenceScope.conceptGraph:
        return 'concept_graph_search';
    }
  }

  static List<String> _seminarToolCallRoleIdsForScope(
    AiSeminarSessionContract session,
    AiSeminarEvidenceScope scope,
  ) {
    final out = <String>[];
    for (final role in session.roles) {
      final profile = session.roleProfileFor(role);
      if (!_seminarRoleProfileCanSeeScope(profile, scope)) continue;
      final roleId = role.asString.trim();
      if (roleId.isNotEmpty && !out.contains(roleId)) out.add(roleId);
    }
    return out;
  }

  static bool _seminarRoleProfileCanSeeScope(
    AiSeminarRoleProfile? profile,
    AiSeminarEvidenceScope scope,
  ) {
    final scopes = profile?.evidenceScopes ?? const <AiSeminarEvidenceScope>[];
    if (scopes.isEmpty) return true;
    if (scopes.contains(scope)) return true;
    return scope == AiSeminarEvidenceScope.currentBook &&
        scopes.contains(AiSeminarEvidenceScope.currentChapter);
  }

  static AiSeminarRunCardEvidenceSnapshot _seminarEvidenceSnapshotFromEvidence(
    AiSeminarEvidence evidence,
  ) {
    final ref = evidence.sourceRef;
    return AiSeminarRunCardEvidenceSnapshot(
      id: evidence.id,
      title: _trimmedOrFallback(
        ref.sourceTitle,
        _trimmedOrFallback(ref.locationLabel, evidence.scope.asString),
      ),
      snippet: _trimmedOrFallback(ref.sourceTextSnippet, evidence.text),
      sourceRef: ref,
    );
  }

  static List<AiSeminarRunCardEvidenceSnapshot>
      _seminarEvidenceSnapshotsForTurn(
    AiSeminarEvidenceBundle evidenceBundle,
    AiSeminarRoleTurn turn,
  ) {
    final ids = turn.evidenceRefIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return const <AiSeminarRunCardEvidenceSnapshot>[];
    return evidenceBundle.evidence
        .where((item) => ids.contains(item.id.trim()))
        .map(_seminarEvidenceSnapshotFromEvidence)
        .where((item) => !item.isEmpty)
        .toList(growable: false);
  }

  static String _trimmedOrFallback(String? value, String fallback) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? fallback.trim() : trimmed;
  }

  static Set<String> _traceableEvidenceIds(AiSeminarEvidenceBundle bundle) {
    return bundle.evidence
        .where((item) => item.isTraceable)
        .map((item) => item.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  static List<AiSeminarWhiteboardEntry> _whiteboardEntries(
    List<AiSeminarRoleTurn> turns,
  ) {
    return turns
        .expand((turn) => turn.whiteboardEntries)
        .toList(growable: false);
  }

  static List<AiSeminarRoleTurn>? _validatedCheckpointTurns(
    AiSeminarSessionContract session,
    AiSeminarEvidenceBundle evidenceBundle,
    List<AiSeminarRoleTurn> checkpointTurns,
    List<AiSeminarRole> executionOrder,
  ) {
    if (checkpointTurns.length > executionOrder.length) return null;
    final out = <AiSeminarRoleTurn>[];
    for (var index = 0; index < checkpointTurns.length; index += 1) {
      final turn = checkpointTurns[index];
      if (turn.role != executionOrder[index]) return null;
      if (turn.isFailed) return null;
      final roleEvidenceBundle =
          AiSeminarOrchestrationService.evidenceBundleForRole(
        session: session,
        role: turn.role,
        evidenceBundle: evidenceBundle,
      );
      final roleTraceableEvidenceIds =
          _traceableEvidenceIds(roleEvidenceBundle);
      if (!turn.hasTraceableEvidence(roleTraceableEvidenceIds)) return null;
      out.add(turn);
    }
    return List.unmodifiable(out);
  }

  static List<AiSeminarRoleTurn> _localBudgetTurnsForCheckpoint({
    required AiSeminarSessionContract session,
    required AiSeminarEvidenceBundle evidenceBundle,
    required List<AiSeminarRoleTurn> turns,
  }) {
    final budgetTurns = <AiSeminarRoleTurn>[];
    for (final turn in turns) {
      final invocation = AiSeminarRoleInvocation(
        session: session,
        role: turn.role,
        evidenceBundle: evidenceBundle,
        priorTurns: List.unmodifiable(budgetTurns),
        prompt: turn.prompt,
      );
      budgetTurns.add(
        _copyTurnWithTokenUsage(
          turn,
          _estimatedTokenUsage(invocation: invocation, turn: turn),
        ),
      );
    }
    return budgetTurns;
  }

  static List<AiSeminarRoleTurn> _checkpointTurnsWithTokenUsage({
    required AiSeminarSessionContract session,
    required AiSeminarEvidenceBundle evidenceBundle,
    required List<AiSeminarRoleTurn> turns,
  }) {
    final restoredTurns = <AiSeminarRoleTurn>[];
    for (final turn in turns) {
      final invocation = AiSeminarRoleInvocation(
        session: session,
        role: turn.role,
        evidenceBundle: evidenceBundle,
        priorTurns: List.unmodifiable(restoredTurns),
        prompt: turn.prompt,
      );
      restoredTurns.add(
        _attachEstimatedTokenUsage(invocation: invocation, turn: turn),
      );
    }
    return restoredTurns;
  }

  static AiSeminarRoleTurn _attachEstimatedTokenUsage({
    required AiSeminarRoleInvocation invocation,
    required AiSeminarRoleTurn turn,
  }) {
    if (turn.tokenUsage != null) return turn;
    return _copyTurnWithTokenUsage(
      turn,
      _estimatedTokenUsage(invocation: invocation, turn: turn),
    );
  }

  static AiSeminarTokenUsage _estimatedTokenUsage({
    required AiSeminarRoleInvocation invocation,
    required AiSeminarRoleTurn turn,
  }) {
    return AiSeminarTokenUsage(
      inputTokens: _estimateTokenCount(_inputTextForInvocation(invocation)),
      outputTokens: _estimateTokenCount(turn.responseText),
      isEstimated: true,
      estimationMethod: _localTokenEstimateMethod,
      source: AiSeminarTokenUsage.sourceLocalEstimate,
    );
  }

  static AiSeminarRoleTurn _copyTurnWithTokenUsage(
    AiSeminarRoleTurn turn,
    AiSeminarTokenUsage usage,
  ) {
    return AiSeminarRoleTurn(
      id: turn.id,
      role: turn.role,
      prompt: turn.prompt,
      responseText: turn.responseText,
      evidenceRefIds: turn.evidenceRefIds,
      whiteboardEntries: turn.whiteboardEntries,
      startedAt: turn.startedAt,
      completedAt: turn.completedAt,
      error: turn.error,
      tokenUsage: usage,
    );
  }

  static AiSeminarRoleTurn _stripTokenUsage(AiSeminarRoleTurn turn) {
    if (turn.tokenUsage == null) return turn;
    return AiSeminarRoleTurn(
      id: turn.id,
      role: turn.role,
      prompt: turn.prompt,
      responseText: turn.responseText,
      evidenceRefIds: turn.evidenceRefIds,
      whiteboardEntries: turn.whiteboardEntries,
      startedAt: turn.startedAt,
      completedAt: turn.completedAt,
      error: turn.error,
    );
  }

  static String? _budgetFailureMessage(
    AiSeminarBudgetPolicy? policy,
    AiSeminarRoleTurn turn,
    List<AiSeminarRoleTurn> nextTurns,
  ) {
    if (policy == null || !policy.hasTokenLimits) return null;
    final usage = turn.tokenUsage;
    final roleLimit = policy.maxRoleOutputTokens;
    if (usage != null && roleLimit != null && usage.outputTokens > roleLimit) {
      return 'AI Seminar role ${turn.role.asString} exceeded local role output token budget '
          '(${usage.outputTokens} > $roleLimit).';
    }
    final runLimit = policy.maxRunTokens;
    final runUsage = AiSeminarTokenUsage.aggregateRoleTurns(nextTurns);
    if (runUsage != null &&
        runLimit != null &&
        runUsage.totalTokens > runLimit) {
      return 'AI Seminar exceeded local run token budget '
          '(${runUsage.totalTokens} > $runLimit).';
    }
    return null;
  }

  static String? _costBudgetFailureMessage(
    AiSeminarBudgetPolicy? policy,
    List<AiSeminarRoleTurn> nextTurns,
  ) {
    if (policy == null || !policy.hasCostLimit) return null;
    final estimatedCost = _estimatedRunCostUsdForRates(
      usage: AiSeminarTokenUsage.aggregateRoleTurns(nextTurns),
      inputCostPerMillionTokens: policy.inputCostPerMillionTokens,
      outputCostPerMillionTokens: policy.outputCostPerMillionTokens,
      cacheReadCostPerMillionTokens: policy.cacheReadCostPerMillionTokens,
      cacheWriteCostPerMillionTokens: policy.cacheWriteCostPerMillionTokens,
    );
    final limit = policy.maxRunCostUsd;
    if (estimatedCost == null || limit == null || estimatedCost <= limit) {
      return null;
    }
    return 'AI Seminar exceeded estimated run cost cap '
        '(\$${estimatedCost.toStringAsFixed(4)} > '
        '\$${limit.toStringAsFixed(4)}).';
  }

  static AiSeminarBillingSnapshot? _billingSnapshot({
    required AiSeminarSessionContract session,
    required List<AiSeminarRoleTurn> turns,
    required int completedAt,
  }) {
    final usage = AiSeminarTokenUsage.aggregateRoleTurns(turns);
    if (usage == null) return null;
    final context = session.billingContext;
    final policy = session.budgetPolicy;
    final inputCostPerMillionTokens =
        context?.inputCostPerMillionTokens ?? policy?.inputCostPerMillionTokens;
    final outputCostPerMillionTokens = context?.outputCostPerMillionTokens ??
        policy?.outputCostPerMillionTokens;
    final cacheReadCostPerMillionTokens =
        context?.cacheReadCostPerMillionTokens ??
            policy?.cacheReadCostPerMillionTokens;
    final cacheWriteCostPerMillionTokens =
        context?.cacheWriteCostPerMillionTokens ??
            policy?.cacheWriteCostPerMillionTokens;
    final estimatedCost = _estimatedRunCostUsdForRates(
      usage: usage,
      inputCostPerMillionTokens: inputCostPerMillionTokens,
      outputCostPerMillionTokens: outputCostPerMillionTokens,
      cacheReadCostPerMillionTokens: cacheReadCostPerMillionTokens,
      cacheWriteCostPerMillionTokens: cacheWriteCostPerMillionTokens,
    );
    return AiSeminarBillingSnapshot(
      providerId: context?.providerId ?? '',
      providerName: context?.providerName ?? '',
      providerType: context?.providerType,
      modelId: context?.modelId ?? '',
      usageSnapshot: usage,
      pricingSource: context?.pricingSource ?? policy?.costPriceSource,
      pricingVersion: context?.pricingVersion,
      pricingCapturedAt: context?.pricingCapturedAt ?? completedAt,
      currency: context?.currency ?? 'USD',
      inputCostPerMillionTokens: inputCostPerMillionTokens,
      outputCostPerMillionTokens: outputCostPerMillionTokens,
      cacheReadCostPerMillionTokens: cacheReadCostPerMillionTokens,
      cacheWriteCostPerMillionTokens: cacheWriteCostPerMillionTokens,
      estimatedCostUsd: estimatedCost,
      invoiceStatus: AiSeminarInvoiceReconciliationStatus.notConnected,
      invoiceReason: _providerInvoiceNotConnectedReason,
    );
  }

  static double? _estimatedRunCostUsd(
    AiSeminarSessionContract session,
    List<AiSeminarRoleTurn> turns,
  ) {
    final context = session.billingContext;
    final policy = session.budgetPolicy;
    return _estimatedRunCostUsdForRates(
      usage: AiSeminarTokenUsage.aggregateRoleTurns(turns),
      inputCostPerMillionTokens: context?.inputCostPerMillionTokens ??
          policy?.inputCostPerMillionTokens,
      outputCostPerMillionTokens: context?.outputCostPerMillionTokens ??
          policy?.outputCostPerMillionTokens,
      cacheReadCostPerMillionTokens: context?.cacheReadCostPerMillionTokens ??
          policy?.cacheReadCostPerMillionTokens,
      cacheWriteCostPerMillionTokens: context?.cacheWriteCostPerMillionTokens ??
          policy?.cacheWriteCostPerMillionTokens,
    );
  }

  static double? _estimatedRunCostUsdForRates({
    required AiSeminarTokenUsage? usage,
    required double? inputCostPerMillionTokens,
    required double? outputCostPerMillionTokens,
    double? cacheReadCostPerMillionTokens,
    double? cacheWriteCostPerMillionTokens,
  }) {
    if (inputCostPerMillionTokens == null ||
        inputCostPerMillionTokens <= 0 ||
        outputCostPerMillionTokens == null ||
        outputCostPerMillionTokens <= 0) {
      return null;
    }
    if (usage == null) return null;
    final inputTokens =
        usage.inputTokens - usage.cacheReadTokens - usage.cacheWriteTokens;
    final billableInputTokens = inputTokens < 0 ? 0 : inputTokens;
    final inputCost = billableInputTokens * inputCostPerMillionTokens / 1000000;
    final outputCost =
        usage.outputTokens * outputCostPerMillionTokens / 1000000;
    final cacheReadCost =
        usage.cacheReadTokens * (cacheReadCostPerMillionTokens ?? 0) / 1000000;
    final cacheWriteCost = usage.cacheWriteTokens *
        (cacheWriteCostPerMillionTokens ?? 0) /
        1000000;
    final cost = inputCost + outputCost + cacheReadCost + cacheWriteCost;
    if (cost <= 0) return null;
    return cost;
  }

  static String? _costPriceSource(
    AiSeminarSessionContract session,
    List<AiSeminarRoleTurn> turns,
  ) {
    if (turns.isEmpty) return null;
    final context = session.billingContext;
    if (context?.hasPricingMetadata == true) return context?.pricingSource;
    final policy = session.budgetPolicy;
    if (policy == null || !policy.hasPricingMetadata) return null;
    return policy.costPriceSource;
  }

  static String _inputTextForInvocation(AiSeminarRoleInvocation invocation) {
    final evidenceText = invocation.evidenceBundle.evidence
        .map((evidence) => '${evidence.id}: ${evidence.text}')
        .join('\n');
    return [
      invocation.prompt,
      if (evidenceText.trim().isNotEmpty) evidenceText,
    ].join('\n');
  }

  static int _estimateTokenCount(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    var ascii = 0;
    var nonAscii = 0;
    for (final codePoint in trimmed.runes) {
      if (codePoint <= 0x7F) {
        ascii += 1;
      } else {
        nonAscii += 1;
      }
    }
    final estimate = (ascii / 4) + (nonAscii / 2);
    return estimate.ceil().clamp(1, 1 << 31);
  }
}

class AiSeminarModelRoleExecutor {
  const AiSeminarModelRoleExecutor({
    AiSeminarGenerateStream? generateStream,
    AiSeminarAgentGenerateStream? agentGenerateStream,
  })  : _generateStream = generateStream,
        _agentGenerateStream = agentGenerateStream;

  final AiSeminarGenerateStream? _generateStream;
  final AiSeminarAgentGenerateStream? _agentGenerateStream;

  Stream<AiSeminarRoleStreamChunk> streamRole(
    AiSeminarRoleInvocation invocation,
    AiSeminarCancellationToken cancelToken,
  ) async* {
    cancelToken.onCancel(cancelActiveAiRequest);
    var latest = '';
    final beforeUsage = _UsageSnapshot.capture(
      getUsageTracker(invocation.session.id),
    );
    final messages = _messagesForInvocation(invocation);
    final agentGenerateStream = _agentGenerateStream;
    final roleAllowedTools = _effectiveSeminarRoleToolIds(
      session: invocation.session,
      role: invocation.role,
    );
    final roleAllowedToolSet = roleAllowedTools.toSet();
    final usesAgentStream =
        agentGenerateStream != null && roleAllowedTools.isNotEmpty;
    final originalToolCallObserver = invocation.toolCallObserver;
    final forwardedToolCallKeys = <String>{};
    Future<void> forwardToolCallEvent(AgentToolCallEvent event) async {
      if (originalToolCallObserver == null) return;
      if (!roleAllowedToolSet.contains(event.toolId.trim())) return;
      final key = _agentToolCallEventForwardKey(event);
      if (!forwardedToolCallKeys.add(key)) return;
      await originalToolCallObserver(event);
    }

    final streamInvocation = usesAgentStream && originalToolCallObserver != null
        ? AiSeminarRoleInvocation(
            session: invocation.session,
            role: invocation.role,
            evidenceBundle: invocation.evidenceBundle,
            priorTurns: invocation.priorTurns,
            prompt: invocation.prompt,
            toolCallObserver: forwardToolCallEvent,
          )
        : invocation;
    final stream = usesAgentStream
        ? agentGenerateStream(
            streamInvocation,
            messages,
            conversationId: invocation.session.id,
          )
        : (_generateStream ?? _defaultGenerateStream)(
            messages,
            conversationId: invocation.session.id,
          );

    var hasAgentReplyPayload = false;
    await for (final chunk in stream) {
      if (cancelToken.isCancelled) return;
      if (usesAgentStream && originalToolCallObserver != null) {
        for (final event in _agentToolCallEventsForStreamChunk(chunk)) {
          await forwardToolCallEvent(event);
        }
      }
      final hasChunkReplyPayload =
          usesAgentStream && _hasAgentReplyPayload(chunk);
      final completedPayload = _completedPayloadForStreamChunk(
        raw: chunk,
        usesAgentStream: usesAgentStream,
      );
      if (completedPayload != null) {
        if (!usesAgentStream || hasChunkReplyPayload || !hasAgentReplyPayload) {
          latest = completedPayload;
        }
        if (hasChunkReplyPayload) {
          hasAgentReplyPayload = true;
        }
      }
      final thinkingText = _thinkingTextForStreamChunk(
        raw: chunk,
        usesAgentStream: usesAgentStream,
      );
      if (thinkingText != null) {
        yield AiSeminarRoleStreamChunk(thinkingText: thinkingText);
      }
      final partialText = _partialTextForStreamChunk(
        raw: chunk,
        usesAgentStream: usesAgentStream,
      );
      if (partialText != null) {
        yield AiSeminarRoleStreamChunk(partialText: partialText);
      }
    }
    if (cancelToken.isCancelled) return;
    if (usesAgentStream && latest.trim().isEmpty) {
      throw const FormatException(
        'Seminar agent stream must include a final reply payload.',
      );
    }
    final parsedTurn = _parseTurn(invocation: invocation, raw: latest);
    final providerUsage = _providerUsageDelta(
      beforeUsage,
      _UsageSnapshot.capture(getUsageTracker(invocation.session.id)),
    );
    yield AiSeminarRoleStreamChunk(
      completedTurn: parsedTurn.isFailed || providerUsage == null
          ? parsedTurn
          : AiSeminarRuntimeService._copyTurnWithTokenUsage(
              parsedTurn,
              providerUsage,
            ),
    );
  }

  static String? _partialTextForStreamChunk({
    required String raw,
    required bool usesAgentStream,
  }) {
    if (!usesAgentStream) return raw;
    final payload = _roleJsonPayload(raw).trim();
    if (payload.isEmpty) return null;
    final containsTimeline = _containsAgentTimelineTag(raw);
    try {
      final decoded = jsonDecode(repairJson(payload));
      if (decoded is Map) {
        final responseText = decoded['responseText']?.toString().trim();
        if (responseText != null && responseText.isNotEmpty) {
          return responseText;
        }
      }
    } catch (_) {
      if (containsTimeline) return null;
      return payload;
    }
    if (containsTimeline) return null;
    return payload;
  }

  static String? _completedPayloadForStreamChunk({
    required String raw,
    required bool usesAgentStream,
  }) {
    if (!usesAgentStream) return raw;
    final replyTexts = _decodedAgentReplyTexts(raw);
    for (final text in replyTexts.reversed) {
      if (text.trim().isNotEmpty) return text;
    }
    if (_containsAgentTimelineTag(raw)) return null;
    return raw.trim().isEmpty ? null : raw;
  }

  static String? _thinkingTextForStreamChunk({
    required String raw,
    required bool usesAgentStream,
  }) {
    if (!usesAgentStream) return null;
    final thinkingText = _decodedAgentThinkingText(raw).trim();
    return thinkingText.isEmpty ? null : thinkingText;
  }

  static AiSeminarTokenUsage? _providerUsageDelta(
    _UsageSnapshot before,
    _UsageSnapshot after,
  ) {
    final inputTokens = after.inputTokens - before.inputTokens;
    final outputTokens = after.outputTokens - before.outputTokens;
    final cacheReadTokens = after.cacheReadTokens - before.cacheReadTokens;
    final cacheWriteTokens = after.cacheWriteTokens - before.cacheWriteTokens;
    final apiCalls = after.apiCalls - before.apiCalls;
    if (inputTokens <= 0 &&
        outputTokens <= 0 &&
        cacheReadTokens <= 0 &&
        cacheWriteTokens <= 0) {
      return null;
    }
    return AiSeminarTokenUsage(
      inputTokens: inputTokens < 0 ? 0 : inputTokens,
      outputTokens: outputTokens < 0 ? 0 : outputTokens,
      cacheReadTokens: cacheReadTokens < 0 ? 0 : cacheReadTokens,
      cacheWriteTokens: cacheWriteTokens < 0 ? 0 : cacheWriteTokens,
      apiCalls: apiCalls > 0 ? apiCalls : null,
      isEstimated: false,
      estimationMethod: 'provider-usage-tracker-v1',
      source: AiSeminarTokenUsage.sourceProviderReported,
    );
  }

  static Stream<String> _defaultGenerateStream(
    List<ChatMessage> messages, {
    String? conversationId,
  }) {
    return aiGenerateStream(
      messages,
      useAgent: false,
      conversationId: conversationId,
    );
  }

  static List<ChatMessage> _messagesForInvocation(
    AiSeminarRoleInvocation invocation,
  ) {
    final evidenceLines = invocation.evidenceBundle.evidence.map((evidence) {
      return '- ${evidence.id}: ${evidence.text}';
    }).join('\n');
    final controlledToolGuidance =
        _controlledToolGuidanceForInvocation(invocation);
    return [
      ChatMessage.system('''
You are a PaperTok AI Seminar role executor.
Return only JSON. Do not wrap it in markdown.
Schema:
{
  "role": "${invocation.role.asString}",
  "responseText": "role answer",
  "evidenceRefIds": ["evidence-id"],
  "whiteboardEntries": [
    {
      "id": "short-id",
      "kind": "claim|evidenceRef|disagreement|openQuestion|candidateCard|reviewSuggestion",
      "text": "entry text",
      "evidenceRefIds": ["evidence-id"],
      "conceptRefs": ["short concept label"]
    }
  ]
}
Every claim, disagreement, candidateCard, or reviewSuggestion must cite supplied evidence ids.
For candidateCard entries, include 1-3 concise conceptRefs that can seed a draft concept graph after user Review.
$controlledToolGuidance
'''),
      ChatMessage.humanText('''
${invocation.prompt}

Supplied evidence:
$evidenceLines
      '''),
    ];
  }

  static String _controlledToolGuidanceForInvocation(
    AiSeminarRoleInvocation invocation,
  ) {
    final allowedTools = _effectiveSeminarRoleToolIds(
      session: invocation.session,
      role: invocation.role,
    );
    if (allowedTools.isEmpty) {
      return 'No role tools are available in this Seminar turn. Use only the supplied evidence.';
    }
    return [
      'Available read-only tools: ${allowedTools.join(', ')}.',
      'Do not call tools outside this list.',
      'Use tools only to gather or verify evidence for this Seminar role.',
      'Return the final Seminar role JSON using the schema above after any tool use.',
    ].join('\n');
  }

  static AiSeminarRoleTurn _parseTurn({
    required AiSeminarRoleInvocation invocation,
    required String raw,
  }) {
    final decoded = jsonDecode(repairJson(_roleJsonPayload(raw)));
    if (decoded is! Map) {
      throw const FormatException('Seminar role output must be a JSON object.');
    }
    final json = Map<String, dynamic>.from(decoded);
    final roleValue = json['role']?.toString().trim();
    final role = AiSeminarRole.fromString(roleValue);
    if (roleValue == null || role == null) {
      throw const FormatException(
        'Seminar role output must include a known role.',
      );
    }
    if (role != invocation.role) {
      throw FormatException(
        'Seminar role output returned ${role.asString} for ${invocation.role.asString}.',
      );
    }
    final responseText = (json['responseText'] ?? '').toString().trim();
    if (responseText.isEmpty) {
      throw const FormatException(
        'Seminar role output must include non-empty responseText.',
      );
    }
    final evidenceRefIds = AiSeminarSynthesis.stringList(
      json['evidenceRefIds'],
    );
    final whiteboardEntries = (json['whiteboardEntries'] as List?)
            ?.whereType<Map>()
            .map((entry) => AiSeminarWhiteboardEntry.fromJson(
                  Map<String, dynamic>.from(entry),
                ))
            .toList(growable: false) ??
        const <AiSeminarWhiteboardEntry>[];
    return AiSeminarRoleTurn(
      id: 'turn-${invocation.session.id}-${invocation.role.asString}',
      role: role,
      prompt: invocation.prompt,
      responseText: responseText,
      evidenceRefIds: evidenceRefIds,
      whiteboardEntries: whiteboardEntries,
      completedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static String _roleJsonPayload(String raw) {
    final replyTexts = _decodedAgentReplyTexts(raw);
    for (final text in replyTexts.reversed) {
      final trimmed = text.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return raw;
  }

  static List<String> _decodedAgentReplyTexts(String raw) {
    final matches = RegExp(
      r'''<reply\b[^>]*\btext_b64=(['"])(.*?)\1[^>]*(?:/>|>\s*</reply\s*>)''',
      dotAll: true,
      caseSensitive: false,
    ).allMatches(raw);
    final out = <String>[];
    for (final match in matches) {
      final encoded = match.group(2);
      if (encoded == null || encoded.isEmpty) continue;
      try {
        final decodedAttr = Uri.decodeComponent(encoded);
        out.add(utf8.decode(base64Decode(decodedAttr)));
      } catch (_) {
        // Ignore malformed UI tags and fall back to the raw payload.
      }
    }
    return out;
  }

  static bool _hasAgentReplyPayload(String raw) {
    return _decodedAgentReplyTexts(raw).any((text) => text.trim().isNotEmpty);
  }

  static String _decodedAgentThinkingText(String raw) {
    final matches = RegExp(
      r'''<think\b[^>]*>(.*?)</think\s*>''',
      dotAll: true,
      caseSensitive: false,
    ).allMatches(raw);
    String latest = '';
    for (final match in matches) {
      latest = match.group(1) ?? '';
    }
    return latest;
  }

  static List<AgentToolCallEvent> _agentToolCallEventsForStreamChunk(
    String raw,
  ) {
    final matches = RegExp(
      r'''<tool-step\b([^>]*?)(?:/>|>\s*</tool-step\s*>)''',
      dotAll: true,
      caseSensitive: false,
    ).allMatches(raw);
    final out = <AgentToolCallEvent>[];
    for (final match in matches) {
      final attrs = _agentTimelineTagAttributes(match.group(1) ?? '');
      final toolId = _firstNonEmptyAttribute(attrs, const [
        'name',
        'tool',
        'tool_id',
        'toolId',
      ]);
      final status = _agentToolCallStatusFromValue(attrs['status']);
      if (toolId == null || status == null) continue;
      final input =
          _agentToolCallInputFromAttributes(attrs) ?? const <String, dynamic>{};
      out.add(AgentToolCallEvent(
        callId: _firstNonEmptyAttribute(attrs, const [
              'id',
              'call_id',
              'callId',
            ]) ??
            '',
        toolId: toolId,
        input: input,
        status: status,
        output: _decodedAgentTimelineTextAttribute(attrs['output_b64']) ??
            _trimmedOrNull(attrs['output']),
        error: _decodedAgentTimelineTextAttribute(attrs['error_b64']) ??
            _trimmedOrNull(attrs['error']),
        resultCount: int.tryParse(attrs['result_count']?.trim() ?? '') ??
            int.tryParse(attrs['resultCount']?.trim() ?? ''),
      ));
    }
    return out;
  }

  static String _agentToolCallEventForwardKey(AgentToolCallEvent event) {
    return [
      event.toolId.trim(),
      agentToolCallEventIdSegment(event),
      event.status.name,
    ].join('|');
  }

  static Map<String, String> _agentTimelineTagAttributes(String raw) {
    final attrs = <String, String>{};
    final matches = RegExp(
      r'''([A-Za-z_][A-Za-z0-9_-]*)\s*=\s*(['"])(.*?)\2''',
      dotAll: true,
    ).allMatches(raw);
    for (final match in matches) {
      final key = match.group(1);
      final value = match.group(3);
      if (key == null || value == null) continue;
      attrs[key] = value;
    }
    return attrs;
  }

  static String? _firstNonEmptyAttribute(
    Map<String, String> attrs,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = _trimmedOrNull(attrs[key]);
      if (value != null) return value;
    }
    return null;
  }

  static String? _trimmedOrNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static AgentToolCallEventStatus? _agentToolCallStatusFromValue(
    String? value,
  ) {
    return switch (value?.trim().toLowerCase()) {
      'running' || 'pending' => AgentToolCallEventStatus.running,
      'success' ||
      'succeeded' ||
      'complete' ||
      'completed' =>
        AgentToolCallEventStatus.completed,
      'error' ||
      'errored' ||
      'failed' ||
      'failure' =>
        AgentToolCallEventStatus.errored,
      _ => null,
    };
  }

  static Map<String, dynamic>? _agentToolCallInputFromAttributes(
    Map<String, String> attrs,
  ) {
    final encoded = attrs['input_b64'];
    if (encoded != null && encoded.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(
          utf8.decode(base64Decode(Uri.decodeComponent(encoded.trim()))),
        );
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return null;
      }
    }
    final raw = attrs['input'];
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw.trim());
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return {'input': raw.trim()};
      }
    }
    return null;
  }

  static String? _decodedAgentTimelineTextAttribute(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      return utf8.decode(base64Decode(Uri.decodeComponent(value.trim())));
    } catch (_) {
      return null;
    }
  }

  static bool _containsAgentTimelineTag(String raw) {
    return RegExp(
      r'''<\s*(?:tool-step|reply|think)\b''',
      caseSensitive: false,
    ).hasMatch(raw);
  }
}

List<String> _effectiveSeminarRoleToolIds({
  required AiSeminarSessionContract session,
  required AiSeminarRole role,
}) {
  final requested =
      session.roleProfileFor(role)?.allowedToolIds ?? const <String>[];
  if (requested.isEmpty) return const <String>[];
  final matrix = session.bookId == null
      ? AiToolPermissionMatrix.seminarLibraryFallbackMatrix
      : AiToolPermissionMatrix.defaultMatrix;
  final out = <String>[];
  for (final raw in requested) {
    final toolId = raw.trim();
    if (toolId.isEmpty || out.contains(toolId)) continue;
    final rule = matrix.ruleFor(toolId);
    if (rule == null ||
        !rule.readOnly ||
        rule.requiresApproval ||
        rule.allowsExternalNetwork ||
        !matrix.isAllowed(scene: AiAgentScene.seminar, toolId: toolId)) {
      continue;
    }
    out.add(toolId);
  }
  return List.unmodifiable(out);
}

class _UsageSnapshot {
  const _UsageSnapshot({
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheReadTokens,
    required this.cacheWriteTokens,
    required this.apiCalls,
  });

  factory _UsageSnapshot.capture(AiUsageTracker? tracker) {
    if (tracker == null) {
      return const _UsageSnapshot(
        inputTokens: 0,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheWriteTokens: 0,
        apiCalls: 0,
      );
    }
    return _UsageSnapshot(
      inputTokens: tracker.inputTokens,
      outputTokens: tracker.outputTokens,
      cacheReadTokens: tracker.cacheReadTokens,
      cacheWriteTokens: tracker.cacheWriteTokens,
      apiCalls: tracker.apiCalls,
    );
  }

  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final int apiCalls;
}
