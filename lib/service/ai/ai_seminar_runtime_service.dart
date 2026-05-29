import 'dart:async';
import 'dart:convert';

import 'package:langchain_core/chat_models.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/service/ai/ai_seminar_orchestration_service.dart';
import 'package:papertok_reader/service/ai/ai_usage_tracker.dart';
import 'package:papertok_reader/service/ai/index.dart';
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
    this.partialText,
    this.completedTurn,
  });

  final String? partialText;
  final AiSeminarRoleTurn? completedTurn;
}

enum AiSeminarRuntimeEventType {
  sessionStarted,
  evidenceReady,
  roleStarted,
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
  final String? message;
}

class AiSeminarRuntimeService {
  const AiSeminarRuntimeService({
    required AiSeminarEvidenceFetcher fetchEvidence,
    required AiSeminarStreamingRoleExecutor streamRole,
    AiSeminarClock? now,
  })  : _fetchEvidence = fetchEvidence,
        _streamRole = streamRole,
        _now = now;

  final AiSeminarEvidenceFetcher _fetchEvidence;
  final AiSeminarStreamingRoleExecutor _streamRole;
  final AiSeminarClock? _now;
  static const String _localTokenEstimateMethod = 'local-char-estimate-v1';

  Stream<AiSeminarRuntimeEvent> run(
    AiSeminarSessionContract session, {
    AiSeminarCancellationToken? cancelToken,
  }) async* {
    final token = cancelToken ?? AiSeminarCancellationToken();
    final startedAt = _nowMs();
    yield AiSeminarRuntimeEvent(
      type: AiSeminarRuntimeEventType.sessionStarted,
      session: session,
      status: AiSeminarRunStatus.running,
    );

    late final AiSeminarEvidenceBundle evidenceBundle;
    try {
      evidenceBundle = await _fetchEvidence(session);
    } catch (error) {
      yield _failedEvent(
        session: session,
        evidenceBundle: const AiSeminarEvidenceBundle(
          query: '',
          evidence: <AiSeminarEvidence>[],
        ),
        startedAt: startedAt,
        message: error.toString(),
      );
      return;
    }

    if (token.isCancelled) {
      yield _cancelledEvent(
        session: session,
        evidenceBundle: evidenceBundle,
        startedAt: startedAt,
      );
      return;
    }

    yield AiSeminarRuntimeEvent(
      type: AiSeminarRuntimeEventType.evidenceReady,
      session: session,
      status: AiSeminarRunStatus.running,
      evidenceBundle: evidenceBundle,
    );

    if (evidenceBundle.evidence.isEmpty ||
        !evidenceBundle.allEvidenceTraceable) {
      yield _needsEvidenceEvent(
        session: session,
        evidenceBundle: evidenceBundle,
        startedAt: startedAt,
        message: 'AI Seminar requires traceable current-source evidence.',
      );
      return;
    }

    final traceableEvidenceIds = _traceableEvidenceIds(evidenceBundle);
    final turns = <AiSeminarRoleTurn>[];
    final localBudgetTurns = <AiSeminarRoleTurn>[];

    for (final role in AiSeminarOrchestrationService.executionOrder(
      session.roles,
    )) {
      if (token.isCancelled) {
        yield _cancelledEvent(
          session: session,
          evidenceBundle: evidenceBundle,
          startedAt: startedAt,
          turns: turns,
        );
        return;
      }

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
      final invocation = AiSeminarRoleInvocation(
        session: session,
        role: role,
        evidenceBundle: evidenceBundle,
        priorTurns: List.unmodifiable(turns),
        prompt: AiSeminarOrchestrationService.promptForRole(
          session: session,
          role: role,
          evidenceBundle: evidenceBundle,
          priorTurns: turns,
        ),
      );
      try {
        await for (final chunk in _streamRole(
          invocation,
          token,
        )) {
          if (token.isCancelled) {
            yield _cancelledEvent(
              session: session,
              evidenceBundle: evidenceBundle,
              startedAt: startedAt,
              turns: turns,
            );
            return;
          }
          final partialText = chunk.partialText;
          if (partialText != null) {
            final roleOutputLimit = session.budgetPolicy?.maxRoleOutputTokens;
            final partialOutputTokens = _estimateTokenCount(partialText);
            if (roleOutputLimit != null &&
                partialOutputTokens > roleOutputLimit) {
              token.cancel();
              yield _failedEvent(
                session: session,
                evidenceBundle: evidenceBundle,
                startedAt: startedAt,
                turns: turns,
                message:
                    'AI Seminar role ${role.asString} exceeded local role output token budget '
                    '($partialOutputTokens > $roleOutputLimit).',
              );
              return;
            }
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
        yield _failedEvent(
          session: session,
          evidenceBundle: evidenceBundle,
          startedAt: startedAt,
          turns: turns,
          message: error.toString(),
        );
        return;
      }

      final turn = completedTurn;
      if (turn == null) {
        yield _failedEvent(
          session: session,
          evidenceBundle: evidenceBundle,
          startedAt: startedAt,
          turns: turns,
          message: 'AI Seminar role ${role.asString} produced no turn.',
        );
        return;
      }
      if (turn.role != role) {
        yield _failedEvent(
          session: session,
          evidenceBundle: evidenceBundle,
          startedAt: startedAt,
          turns: turns,
          message:
              'AI Seminar executor returned ${turn.role.asString} for ${role.asString}.',
        );
        return;
      }
      if (turn.isFailed) {
        yield _failedEvent(
          session: session,
          evidenceBundle: evidenceBundle,
          startedAt: startedAt,
          turns: [...turns, _stripTokenUsage(turn)],
          message: turn.error,
        );
        return;
      }
      if (!turn.hasTraceableEvidence(traceableEvidenceIds)) {
        yield _needsEvidenceEvent(
          session: session,
          evidenceBundle: evidenceBundle,
          startedAt: startedAt,
          turns: turns,
          message:
              'AI Seminar role ${role.asString} cited missing or untraceable evidence.',
        );
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
        yield _failedEvent(
          session: session,
          evidenceBundle: evidenceBundle,
          startedAt: startedAt,
          turns: nextTurns,
          message: costFailure,
        );
        return;
      }

      turns.add(turnWithUsage);
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
      yield _cancelledEvent(
        session: session,
        evidenceBundle: evidenceBundle,
        startedAt: startedAt,
        turns: turns,
      );
      return;
    }

    final synthesis = AiSeminarOrchestrationService.synthesize(
      session: session,
      evidenceBundle: evidenceBundle,
      turns: turns,
    );
    final status = synthesis.hasTraceableHandoff
        ? AiSeminarRunStatus.completed
        : AiSeminarRunStatus.needsEvidence;
    final run = AiSeminarRun(
      session: session,
      status: status,
      evidenceBundle: evidenceBundle,
      turns: List.unmodifiable(turns),
      synthesis: synthesis,
      startedAt: startedAt,
      completedAt: _nowMs(),
      tokenUsage: AiSeminarTokenUsage.aggregateRoleTurns(turns),
      estimatedCostUsd: _estimatedRunCostUsd(session.budgetPolicy, turns),
      costPriceSource: _costPriceSource(session.budgetPolicy, turns),
      message: status == AiSeminarRunStatus.needsEvidence
          ? 'AI Seminar synthesis is missing traceable handoff evidence.'
          : null,
    );
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

  AiSeminarRuntimeEvent _failedEvent({
    required AiSeminarSessionContract session,
    required AiSeminarEvidenceBundle evidenceBundle,
    required int startedAt,
    List<AiSeminarRoleTurn> turns = const <AiSeminarRoleTurn>[],
    String? message,
  }) {
    final run = AiSeminarRun(
      session: session,
      status: AiSeminarRunStatus.failed,
      evidenceBundle: evidenceBundle,
      turns: List.unmodifiable(turns),
      startedAt: startedAt,
      completedAt: _nowMs(),
      tokenUsage: AiSeminarTokenUsage.aggregateRoleTurns(turns),
      estimatedCostUsd: _estimatedRunCostUsd(session.budgetPolicy, turns),
      costPriceSource: _costPriceSource(session.budgetPolicy, turns),
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

  AiSeminarRuntimeEvent _needsEvidenceEvent({
    required AiSeminarSessionContract session,
    required AiSeminarEvidenceBundle evidenceBundle,
    required int startedAt,
    List<AiSeminarRoleTurn> turns = const <AiSeminarRoleTurn>[],
    String? message,
  }) {
    final run = AiSeminarRun(
      session: session,
      status: AiSeminarRunStatus.needsEvidence,
      evidenceBundle: evidenceBundle,
      turns: List.unmodifiable(turns),
      startedAt: startedAt,
      completedAt: _nowMs(),
      tokenUsage: AiSeminarTokenUsage.aggregateRoleTurns(turns),
      estimatedCostUsd: _estimatedRunCostUsd(session.budgetPolicy, turns),
      costPriceSource: _costPriceSource(session.budgetPolicy, turns),
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
    final run = AiSeminarRun(
      session: session,
      status: AiSeminarRunStatus.cancelled,
      evidenceBundle: evidenceBundle,
      turns: List.unmodifiable(turns),
      startedAt: startedAt,
      completedAt: _nowMs(),
      tokenUsage: AiSeminarTokenUsage.aggregateRoleTurns(turns),
      estimatedCostUsd: _estimatedRunCostUsd(session.budgetPolicy, turns),
      costPriceSource: _costPriceSource(session.budgetPolicy, turns),
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
    final estimatedCost = _estimatedRunCostUsd(policy, nextTurns);
    final limit = policy.maxRunCostUsd;
    if (estimatedCost == null || limit == null || estimatedCost <= limit) {
      return null;
    }
    return 'AI Seminar exceeded estimated run cost cap '
        '(\$${estimatedCost.toStringAsFixed(4)} > '
        '\$${limit.toStringAsFixed(4)}).';
  }

  static double? _estimatedRunCostUsd(
    AiSeminarBudgetPolicy? policy,
    List<AiSeminarRoleTurn> turns,
  ) {
    if (policy == null || !policy.hasPricingMetadata) return null;
    final usage = AiSeminarTokenUsage.aggregateRoleTurns(turns);
    if (usage == null) return null;
    final inputTokens =
        usage.inputTokens - usage.cacheReadTokens - usage.cacheWriteTokens;
    final billableInputTokens = inputTokens < 0 ? 0 : inputTokens;
    final inputCost =
        billableInputTokens * (policy.inputCostPerMillionTokens ?? 0) / 1000000;
    final outputCost =
        usage.outputTokens * (policy.outputCostPerMillionTokens ?? 0) / 1000000;
    final cacheReadCost = usage.cacheReadTokens *
        (policy.cacheReadCostPerMillionTokens ?? 0) /
        1000000;
    final cacheWriteCost = usage.cacheWriteTokens *
        (policy.cacheWriteCostPerMillionTokens ?? 0) /
        1000000;
    final cost = inputCost + outputCost + cacheReadCost + cacheWriteCost;
    if (cost <= 0) return null;
    return cost;
  }

  static String? _costPriceSource(
    AiSeminarBudgetPolicy? policy,
    List<AiSeminarRoleTurn> turns,
  ) {
    if (turns.isEmpty) return null;
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
  const AiSeminarModelRoleExecutor({AiSeminarGenerateStream? generateStream})
      : _generateStream = generateStream;

  final AiSeminarGenerateStream? _generateStream;

  Stream<AiSeminarRoleStreamChunk> streamRole(
    AiSeminarRoleInvocation invocation,
    AiSeminarCancellationToken cancelToken,
  ) async* {
    cancelToken.onCancel(cancelActiveAiRequest);
    var latest = '';
    final beforeUsage = _UsageSnapshot.capture(
      getUsageTracker(invocation.session.id),
    );
    final stream = (_generateStream ?? _defaultGenerateStream)(
      _messagesForInvocation(invocation),
      conversationId: invocation.session.id,
    );

    await for (final chunk in stream) {
      if (cancelToken.isCancelled) return;
      latest = chunk;
      yield AiSeminarRoleStreamChunk(partialText: chunk);
    }
    if (cancelToken.isCancelled) return;
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
'''),
      ChatMessage.humanText('''
${invocation.prompt}

Supplied evidence:
$evidenceLines
'''),
    ];
  }

  static AiSeminarRoleTurn _parseTurn({
    required AiSeminarRoleInvocation invocation,
    required String raw,
  }) {
    final decoded = jsonDecode(repairJson(raw));
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
    final responseText = (json['responseText'] ?? '').toString();
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
