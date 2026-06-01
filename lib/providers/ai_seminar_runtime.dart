import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/service/ai/ai_seminar_evidence_broker.dart';
import 'package:papertok_reader/service/ai/ai_seminar_orchestration_service.dart';
import 'package:papertok_reader/service/ai/ai_seminar_provider_context.dart';
import 'package:papertok_reader/service/ai/ai_seminar_runtime_service.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/rag/semantic_search_current_book.dart';
import 'package:papertok_reader/service/rag/semantic_search_library.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';

final aiSeminarRuntimeServiceProvider = Provider<AiSeminarRuntimeService>(
  (ref) {
    final currentBookSearch = SemanticSearchCurrentBook(
      maxFallbackVectorRows:
          SemanticSearchCurrentBook.toolFallbackVectorRowBudget,
    );
    final librarySearch = SemanticSearchLibrary();
    final broker = AiSeminarEvidenceBroker(
      currentBookSearch: (session) {
        final bookId = session.bookId;
        if (bookId == null) {
          return Future.value(
            AiSemanticSearchResult(
              ok: false,
              bookId: -1,
              query: session.question,
              evidence: const [],
              message: 'No current book is attached to this seminar session.',
            ),
          );
        }
        return currentBookSearch.search(
          bookId: bookId,
          query: session.question,
        );
      },
      librarySearch: (session) => librarySearch.search(query: session.question),
    );
    const executor = AiSeminarModelRoleExecutor();
    return AiSeminarRuntimeService(
      fetchEvidence: broker.fetch,
      streamRole: executor.streamRole,
    );
  },
);

final aiSeminarReviewItemStoreProvider = Provider<ReviewItemStore>((ref) {
  return ReviewItemStore();
});

final aiSeminarProviderContextServiceProvider =
    Provider<AiSeminarProviderContextService>((ref) {
  return const AiSeminarProviderContextService();
});

final aiSeminarKnowledgeCardStoreProvider = Provider<KnowledgeCardStore>((ref) {
  return KnowledgeCardStore();
});

final aiSeminarRuntimeProvider =
    StateNotifierProvider<AiSeminarRuntimeNotifier, AiSeminarRuntimeState>(
  (ref) => AiSeminarRuntimeNotifier(
    ref.watch(aiSeminarRuntimeServiceProvider),
    ref.watch(aiSeminarReviewItemStoreProvider),
    ref.watch(aiSeminarKnowledgeCardStoreProvider),
    ref.watch(aiSeminarProviderContextServiceProvider),
  ),
);

class AiSeminarReviewHandoffResult {
  const AiSeminarReviewHandoffResult({
    required this.reviewItemId,
    required this.knowledgeCardIds,
    required this.flashcardIds,
  });

  final String reviewItemId;
  final List<String> knowledgeCardIds;
  final List<String> flashcardIds;
}

enum AiSeminarBackgroundJobStatus {
  running('running'),
  queued('queued'),
  completed('completed'),
  needsEvidence('needs-evidence'),
  cancelled('cancelled'),
  failed('failed'),
  interrupted('interrupted');

  const AiSeminarBackgroundJobStatus(this.asString);

  final String asString;

  bool get isTerminal =>
      this != AiSeminarBackgroundJobStatus.running &&
      this != AiSeminarBackgroundJobStatus.queued;

  static AiSeminarBackgroundJobStatus fromString(String? value) {
    for (final status in AiSeminarBackgroundJobStatus.values) {
      if (status.asString == value) return status;
    }
    return AiSeminarBackgroundJobStatus.interrupted;
  }
}

class AiSeminarBackgroundJobSnapshot {
  const AiSeminarBackgroundJobSnapshot({
    required this.id,
    required this.sessionId,
    required this.status,
    required this.startedAt,
    required this.updatedAt,
    this.completedAt,
    this.message,
    this.session,
  });

  final String id;
  final String sessionId;
  final AiSeminarBackgroundJobStatus status;
  final int startedAt;
  final int updatedAt;
  final int? completedAt;
  final String? message;
  final AiSeminarSessionContract? session;

  bool get isActive => status == AiSeminarBackgroundJobStatus.running;
  bool get isQueued => status == AiSeminarBackgroundJobStatus.queued;

  AiSeminarBackgroundJobSnapshot copyWith({
    AiSeminarBackgroundJobStatus? status,
    int? updatedAt,
    Object? completedAt = _unset,
    Object? message = _unset,
    Object? session = _unset,
  }) {
    return AiSeminarBackgroundJobSnapshot(
      id: id,
      sessionId: sessionId,
      status: status ?? this.status,
      startedAt: startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: identical(completedAt, _unset)
          ? this.completedAt
          : completedAt as int?,
      message: identical(message, _unset) ? this.message : message as String?,
      session: identical(session, _unset)
          ? this.session
          : session as AiSeminarSessionContract?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sessionId': sessionId,
        'status': status.asString,
        'startedAt': startedAt,
        'updatedAt': updatedAt,
        if (completedAt != null) 'completedAt': completedAt,
        if (message != null && message!.trim().isNotEmpty) 'message': message,
        if (session != null && isQueued) 'session': session!.toJson(),
      };

  factory AiSeminarBackgroundJobSnapshot.fromJson(Map<String, dynamic> json) {
    return AiSeminarBackgroundJobSnapshot(
      id: (json['id'] ?? '').toString(),
      sessionId: (json['sessionId'] ?? '').toString(),
      status: AiSeminarBackgroundJobStatus.fromString(
        json['status']?.toString(),
      ),
      startedAt: (json['startedAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      completedAt: (json['completedAt'] as num?)?.toInt(),
      message: json['message']?.toString(),
      session: json['session'] is Map
          ? AiSeminarSessionContract.fromJson(
              Map<String, dynamic>.from(json['session'] as Map),
            )
          : null,
    );
  }
}

class AiSeminarRuntimeState {
  const AiSeminarRuntimeState({
    required this.status,
    this.session,
    this.evidenceBundle,
    this.activeRole,
    this.partialRoleText,
    this.turns = const <AiSeminarRoleTurn>[],
    this.whiteboardEntries = const <AiSeminarWhiteboardEntry>[],
    this.directorState,
    this.synthesis,
    this.lastRun,
    this.error,
    this.startedAt,
    this.completedAt,
    this.providerDiagnostics,
    this.backgroundJob,
    this.backgroundJobs = const <AiSeminarBackgroundJobSnapshot>[],
    this.restoredFromLocalCache = false,
  });

  factory AiSeminarRuntimeState.initial({
    AiSeminarProviderDiagnostics? providerDiagnostics,
  }) {
    return AiSeminarRuntimeState(
      status: AiSeminarRunStatus.draft,
      providerDiagnostics: providerDiagnostics,
    );
  }

  final AiSeminarRunStatus status;
  final AiSeminarSessionContract? session;
  final AiSeminarEvidenceBundle? evidenceBundle;
  final AiSeminarRole? activeRole;
  final String? partialRoleText;
  final List<AiSeminarRoleTurn> turns;
  final List<AiSeminarWhiteboardEntry> whiteboardEntries;
  final AiSeminarDirectorState? directorState;
  final AiSeminarSynthesis? synthesis;
  final AiSeminarRun? lastRun;
  final String? error;
  final int? startedAt;
  final int? completedAt;
  final AiSeminarProviderDiagnostics? providerDiagnostics;
  final AiSeminarBackgroundJobSnapshot? backgroundJob;
  final List<AiSeminarBackgroundJobSnapshot> backgroundJobs;
  final bool restoredFromLocalCache;

  bool get canCancel => status == AiSeminarRunStatus.running;

  bool get canRetry =>
      session != null &&
      (status == AiSeminarRunStatus.failed ||
          status == AiSeminarRunStatus.needsEvidence ||
          status == AiSeminarRunStatus.cancelled);

  bool get canSendToReview => lastRun?.readyForReview == true;

  AiSeminarTokenUsage? get tokenUsage =>
      lastRun?.tokenUsage ?? AiSeminarTokenUsage.aggregateRoleTurns(turns);

  AiSeminarRuntimeState copyWith({
    AiSeminarRunStatus? status,
    AiSeminarSessionContract? session,
    AiSeminarEvidenceBundle? evidenceBundle,
    Object? activeRole = _unset,
    Object? partialRoleText = _unset,
    List<AiSeminarRoleTurn>? turns,
    List<AiSeminarWhiteboardEntry>? whiteboardEntries,
    Object? directorState = _unset,
    Object? synthesis = _unset,
    Object? lastRun = _unset,
    String? error,
    bool clearError = false,
    int? startedAt,
    int? completedAt,
    AiSeminarProviderDiagnostics? providerDiagnostics,
    Object? backgroundJob = _unset,
    List<AiSeminarBackgroundJobSnapshot>? backgroundJobs,
    bool? restoredFromLocalCache,
  }) {
    return AiSeminarRuntimeState(
      status: status ?? this.status,
      session: session ?? this.session,
      evidenceBundle: evidenceBundle ?? this.evidenceBundle,
      activeRole: identical(activeRole, _unset)
          ? this.activeRole
          : activeRole as AiSeminarRole?,
      partialRoleText: identical(partialRoleText, _unset)
          ? this.partialRoleText
          : partialRoleText as String?,
      turns: turns ?? this.turns,
      whiteboardEntries: whiteboardEntries ?? this.whiteboardEntries,
      directorState: identical(directorState, _unset)
          ? this.directorState
          : directorState as AiSeminarDirectorState?,
      synthesis: identical(synthesis, _unset)
          ? this.synthesis
          : synthesis as AiSeminarSynthesis?,
      lastRun:
          identical(lastRun, _unset) ? this.lastRun : lastRun as AiSeminarRun?,
      error: clearError ? null : error ?? this.error,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      providerDiagnostics: providerDiagnostics ?? this.providerDiagnostics,
      backgroundJob: identical(backgroundJob, _unset)
          ? this.backgroundJob
          : backgroundJob as AiSeminarBackgroundJobSnapshot?,
      backgroundJobs: backgroundJobs ?? this.backgroundJobs,
      restoredFromLocalCache:
          restoredFromLocalCache ?? this.restoredFromLocalCache,
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status.asString,
        if (session != null) 'session': session!.toJson(),
        if (evidenceBundle != null) 'evidenceBundle': evidenceBundle!.toJson(),
        if (activeRole != null) 'activeRole': activeRole!.asString,
        if (partialRoleText != null) 'partialRoleText': partialRoleText,
        'turns': turns.map((turn) => turn.toJson()).toList(growable: false),
        'whiteboardEntries': whiteboardEntries
            .map((entry) => entry.toJson())
            .toList(growable: false),
        if (directorState != null) 'directorState': directorState!.toJson(),
        if (synthesis != null) 'synthesis': synthesis!.toJson(),
        if (lastRun != null) 'lastRun': lastRun!.toJson(),
        if (error != null) 'error': error,
        if (startedAt != null) 'startedAt': startedAt,
        if (completedAt != null) 'completedAt': completedAt,
        if (providerDiagnostics != null)
          'providerDiagnostics': providerDiagnostics!.toJson(),
        if (backgroundJob != null) 'backgroundJob': backgroundJob!.toJson(),
        if (backgroundJobs.isNotEmpty)
          'backgroundJobs':
              backgroundJobs.map((job) => job.toJson()).toList(growable: false),
      };

  factory AiSeminarRuntimeState.fromJson(Map<String, dynamic> json) {
    final backgroundJob = json['backgroundJob'] is Map
        ? AiSeminarBackgroundJobSnapshot.fromJson(
            Map<String, dynamic>.from(json['backgroundJob'] as Map),
          )
        : null;
    final backgroundJobs = (json['backgroundJobs'] as List?)
            ?.whereType<Map>()
            .map((job) => AiSeminarBackgroundJobSnapshot.fromJson(
                  Map<String, dynamic>.from(job),
                ))
            .toList(growable: false) ??
        [
          if (backgroundJob != null) backgroundJob,
        ];
    return AiSeminarRuntimeState(
      status: AiSeminarRunStatus.fromString(json['status']?.toString()),
      session: json['session'] is Map
          ? AiSeminarSessionContract.fromJson(
              Map<String, dynamic>.from(json['session'] as Map),
            )
          : null,
      evidenceBundle: json['evidenceBundle'] is Map
          ? AiSeminarEvidenceBundle.fromJson(
              Map<String, dynamic>.from(json['evidenceBundle'] as Map),
            )
          : null,
      activeRole: AiSeminarRole.fromString(json['activeRole']?.toString()),
      partialRoleText: json['partialRoleText']?.toString(),
      turns: (json['turns'] as List?)
              ?.whereType<Map>()
              .map((turn) => AiSeminarRoleTurn.fromJson(
                    Map<String, dynamic>.from(turn),
                  ))
              .toList(growable: false) ??
          const <AiSeminarRoleTurn>[],
      whiteboardEntries: (json['whiteboardEntries'] as List?)
              ?.whereType<Map>()
              .map((entry) => AiSeminarWhiteboardEntry.fromJson(
                    Map<String, dynamic>.from(entry),
                  ))
              .toList(growable: false) ??
          const <AiSeminarWhiteboardEntry>[],
      directorState: json['directorState'] is Map
          ? AiSeminarDirectorState.fromJson(
              Map<String, dynamic>.from(json['directorState'] as Map),
            )
          : null,
      synthesis: json['synthesis'] is Map
          ? AiSeminarSynthesis.fromJson(
              Map<String, dynamic>.from(json['synthesis'] as Map),
            )
          : null,
      lastRun: json['lastRun'] is Map
          ? AiSeminarRun.fromJson(
              Map<String, dynamic>.from(json['lastRun'] as Map),
            )
          : null,
      error: json['error']?.toString(),
      startedAt: (json['startedAt'] as num?)?.toInt(),
      completedAt: (json['completedAt'] as num?)?.toInt(),
      providerDiagnostics: json['providerDiagnostics'] is Map
          ? AiSeminarProviderDiagnostics.fromJson(
              Map<String, dynamic>.from(json['providerDiagnostics'] as Map),
            )
          : null,
      backgroundJob: backgroundJob,
      backgroundJobs: AiSeminarRuntimeNotifier._normalizeBackgroundJobs(
        backgroundJobs,
      ),
    );
  }
}

class AiSeminarRuntimeNotifier extends StateNotifier<AiSeminarRuntimeState> {
  AiSeminarRuntimeNotifier(
    this._service,
    this._reviewStore,
    this._knowledgeCardStore,
    this._providerContext,
  ) : super(
          _initialState(_providerContext),
        ) {
    if (state.restoredFromLocalCache &&
        state.status == AiSeminarRunStatus.running) {
      unawaited(_resumeRestoredRunningSession());
    }
  }

  final AiSeminarRuntimeService _service;
  final ReviewItemStore _reviewStore;
  final KnowledgeCardStore _knowledgeCardStore;
  final AiSeminarProviderContextService _providerContext;
  AiSeminarCancellationToken? _activeToken;
  int _generation = 0;
  static const String _providerInvoiceNotConnectedReason =
      'Provider invoice import is not connected for this run.';

  Future<void> start(AiSeminarSessionContract session) async {
    final jobStartedAt = _nextBackgroundJobStartedAt(
      DateTime.now().millisecondsSinceEpoch,
    );
    final providerDiagnostics = _providerContext.resolve();
    final resolvedSession = _sessionWithCurrentProviderBudget(
      session,
      providerDiagnostics,
    );
    if (state.backgroundJob?.isActive == true &&
        state.status == AiSeminarRunStatus.running) {
      final queuedJob = _newBackgroundJob(
        resolvedSession,
        startedAt: jobStartedAt,
        status: AiSeminarBackgroundJobStatus.queued,
        message: 'AI Seminar queued behind the active run.',
      );
      state = state.copyWith(
        backgroundJobs: _upsertBackgroundJob(state.backgroundJobs, queuedJob),
        clearError: true,
      );
      await _persistState();
      return;
    }

    final backgroundJob = _newBackgroundJob(
      resolvedSession,
      startedAt: jobStartedAt,
    );
    await _runResolvedSession(
      resolvedSession,
      backgroundJob,
      providerDiagnostics,
    );
  }

  Future<void> _runResolvedSession(
    AiSeminarSessionContract resolvedSession,
    AiSeminarBackgroundJobSnapshot backgroundJob,
    AiSeminarProviderDiagnostics providerDiagnostics, {
    AiSeminarRuntimeCheckpoint? checkpoint,
    AiSeminarDirectorState? directorStateSeed,
    bool startQueuedAfterCompletion = true,
  }) async {
    final generation = ++_generation;
    final token = AiSeminarCancellationToken();
    _activeToken?.cancel();
    _activeToken = token;
    if (!mounted) return;
    final runningJob = backgroundJob.copyWith(
      status: AiSeminarBackgroundJobStatus.running,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      completedAt: null,
      message: null,
      session: backgroundJob.session ?? resolvedSession,
    );
    final backgroundJobs = _upsertBackgroundJob(
      state.backgroundJobs,
      runningJob,
    );
    final checkpointWhiteboardEntries = checkpoint == null
        ? const <AiSeminarWhiteboardEntry>[]
        : checkpoint.completedTurns
            .expand((turn) => turn.whiteboardEntries)
            .toList(growable: false);
    state = AiSeminarRuntimeState.initial(
      providerDiagnostics: providerDiagnostics,
    ).copyWith(
      session: resolvedSession,
      status: AiSeminarRunStatus.running,
      clearError: true,
      activeRole: null,
      partialRoleText: null,
      synthesis: null,
      lastRun: null,
      evidenceBundle: checkpoint?.evidenceBundle,
      turns: checkpoint?.completedTurns ?? const <AiSeminarRoleTurn>[],
      whiteboardEntries: checkpointWhiteboardEntries,
      directorState: _directorStateFor(
        session: resolvedSession,
        evidenceBundle: checkpoint?.evidenceBundle,
        turns: checkpoint?.completedTurns ?? const <AiSeminarRoleTurn>[],
        whiteboardEntries: checkpointWhiteboardEntries,
        previous: directorStateSeed,
      ),
      startedAt: runningJob.startedAt,
      backgroundJob: runningJob,
      backgroundJobs: backgroundJobs,
    );
    await _persistState();
    if (!mounted) return;

    await for (final event in _service.run(
      resolvedSession,
      cancelToken: token,
      checkpoint: checkpoint,
    )) {
      if (!mounted || generation != _generation) return;
      _applyEvent(event);
      if (event.type != AiSeminarRuntimeEventType.roleDelta) {
        await _persistState();
      }
      if (event.status?.isTerminal == true) {
        _activeToken = null;
      }
    }
    if (mounted && generation == _generation && startQueuedAfterCompletion) {
      await _startNextQueuedJobIfAvailable();
    }
  }

  Future<void> _resumeRestoredRunningSession() async {
    if (!mounted) return;
    final session = state.session;
    final evidenceBundle = state.evidenceBundle;
    final backgroundJob = state.backgroundJob;
    if (session == null || evidenceBundle == null || backgroundJob == null) {
      _markRestoredRunningInterrupted();
      return;
    }
    if (backgroundJob.status != AiSeminarBackgroundJobStatus.running) {
      _markRestoredRunningInterrupted();
      return;
    }
    final currentDiagnostics = _providerContext.resolve();
    if (!_canResumeWithCurrentProvider(session, currentDiagnostics)) {
      _markRestoredRunningInterrupted();
      return;
    }
    if (_shouldResumeUserDirectedRole(state)) {
      await executeDirectorNextStep();
      return;
    }
    await _runResolvedSession(
      _sessionWithCurrentProviderBudget(session, currentDiagnostics),
      backgroundJob,
      currentDiagnostics,
      checkpoint: AiSeminarRuntimeCheckpoint(
        evidenceBundle: evidenceBundle,
        completedTurns: state.turns,
        startedAt: state.startedAt ?? backgroundJob.startedAt,
      ),
      directorStateSeed: state.directorState,
    );
  }

  static bool _shouldResumeUserDirectedRole(AiSeminarRuntimeState state) {
    final directorState = state.directorState;
    if (state.status != AiSeminarRunStatus.running) return false;
    if (directorState == null) return false;
    final intervention = directorState.lastUserIntervention;
    if (directorState.nextIntent != AiSeminarDirectorNextIntent.runRole ||
        intervention == null) {
      return false;
    }
    return switch (intervention.requestedAction) {
      AiSeminarUserInterventionAction.askRole ||
      AiSeminarUserInterventionAction.clarify =>
        true,
      AiSeminarUserInterventionAction.refreshEvidence ||
      AiSeminarUserInterventionAction.synthesize =>
        false,
    };
  }

  static AiSeminarDirectorState _directorStateWithEvidenceRefresh(
    AiSeminarDirectorState state,
    int evidenceRefreshCount,
  ) {
    return AiSeminarDirectorState(
      sessionId: state.sessionId,
      turnCount: state.turnCount,
      completedRoles: state.completedRoles,
      completedRoleTurnIds: state.completedRoleTurnIds,
      evidenceLedger: state.evidenceLedger,
      whiteboardLedger: state.whiteboardLedger,
      disagreementIds: state.disagreementIds,
      evidenceRefreshCount: evidenceRefreshCount,
      nextIntent: state.nextIntent,
      lastUserIntervention: state.lastUserIntervention,
    );
  }

  void _markRestoredRunningInterrupted() {
    if (!mounted) return;
    final restored = state;
    final session = restored.session;
    final completedAt = DateTime.now().millisecondsSinceEpoch;
    final backgroundJob = _markBackgroundJob(
      restored.backgroundJob ??
          (session == null
              ? null
              : _newBackgroundJob(
                  session,
                  startedAt: restored.startedAt ?? completedAt,
                )),
      AiSeminarBackgroundJobStatus.interrupted,
      updatedAt: completedAt,
      completedAt: completedAt,
      message:
          'AI Seminar was interrupted before it could finish. Retry to run it again.',
    );
    final evidenceBundle = restored.evidenceBundle ??
        AiSeminarEvidenceBundle(
          query: session?.question ?? '',
          evidence: const <AiSeminarEvidence>[],
        );
    final billingSnapshot = session == null
        ? null
        : _billingSnapshot(
            session: session,
            turns: restored.turns,
            completedAt: completedAt,
          );
    final tokenUsage = AiSeminarTokenUsage.aggregateRoleTurns(
      restored.turns,
    );
    final run = session == null
        ? null
        : AiSeminarRun(
            session: session,
            status: AiSeminarRunStatus.cancelled,
            evidenceBundle: evidenceBundle,
            turns: restored.turns,
            startedAt: restored.startedAt,
            completedAt: completedAt,
            tokenUsage: tokenUsage,
            estimatedCostUsd: billingSnapshot?.estimatedCostUsd ??
                _estimatedRunCostUsd(session.budgetPolicy, restored.turns),
            costPriceSource: billingSnapshot?.pricingSource ??
                _costPriceSource(session.budgetPolicy, restored.turns),
            billingSnapshot: billingSnapshot,
            message:
                'AI Seminar was interrupted before it could finish. Retry to run it again.',
          );
    final interruptedJobs = _interruptNonTerminalBackgroundJobs(
      _upsertBackgroundJob(restored.backgroundJobs, backgroundJob),
      completedAt,
    );
    state = restored.copyWith(
      status: AiSeminarRunStatus.cancelled,
      evidenceBundle: evidenceBundle,
      lastRun: run,
      activeRole: null,
      partialRoleText: null,
      directorState: _directorStateFor(
        session: session,
        evidenceBundle: evidenceBundle,
        turns: restored.turns,
        whiteboardEntries: restored.whiteboardEntries,
      ),
      backgroundJob: _backgroundJobFromList(backgroundJob, interruptedJobs),
      backgroundJobs: interruptedJobs,
      error:
          'AI Seminar was interrupted before it could finish. Retry to run it again.',
      completedAt: completedAt,
    );
    unawaited(_persistState());
  }

  void cancel() {
    final session = state.session;
    if (session == null || !state.canCancel) return;
    _activeToken?.cancel();
    _activeToken = null;
    _generation += 1;
    final evidenceBundle = state.evidenceBundle ??
        AiSeminarEvidenceBundle(query: session.question, evidence: const []);
    final completedAt = DateTime.now().millisecondsSinceEpoch;
    final billingSnapshot = _billingSnapshot(
      session: session,
      turns: state.turns,
      completedAt: completedAt,
    );
    final tokenUsage = AiSeminarTokenUsage.aggregateRoleTurns(state.turns);
    final estimatedCostUsd = billingSnapshot?.estimatedCostUsd ??
        _estimatedRunCostUsd(session.budgetPolicy, state.turns);
    final costPriceSource = billingSnapshot?.pricingSource ??
        _costPriceSource(session.budgetPolicy, state.turns);
    final run = AiSeminarRun(
      session: session,
      status: AiSeminarRunStatus.cancelled,
      evidenceBundle: evidenceBundle,
      turns: state.turns,
      startedAt: state.startedAt,
      completedAt: completedAt,
      tokenUsage: tokenUsage,
      estimatedCostUsd: estimatedCostUsd,
      costPriceSource: costPriceSource,
      billingSnapshot: billingSnapshot,
      message: 'AI Seminar cancelled.',
    );
    final backgroundJob = _markBackgroundJob(
      state.backgroundJob,
      AiSeminarBackgroundJobStatus.cancelled,
      updatedAt: completedAt,
      completedAt: completedAt,
      message: run.message,
    );
    state = state.copyWith(
      status: AiSeminarRunStatus.cancelled,
      activeRole: null,
      partialRoleText: null,
      lastRun: run,
      error: run.message,
      completedAt: run.completedAt,
      backgroundJob: backgroundJob,
      backgroundJobs: _upsertBackgroundJob(state.backgroundJobs, backgroundJob),
    );
    _persistState();
    unawaited(_startNextQueuedJobIfAvailable());
  }

  void cancelBackgroundJob(String jobId) {
    if (jobId.trim().isEmpty) return;
    if (state.backgroundJob?.id == jobId) {
      cancel();
      return;
    }
    AiSeminarBackgroundJobSnapshot? queuedJob;
    for (final job in state.backgroundJobs) {
      if (job.id == jobId && job.isQueued) {
        queuedJob = job;
        break;
      }
    }
    if (queuedJob == null) return;
    final completedAt = DateTime.now().millisecondsSinceEpoch;
    final cancelledJob = _markBackgroundJob(
      queuedJob,
      AiSeminarBackgroundJobStatus.cancelled,
      updatedAt: completedAt,
      completedAt: completedAt,
      message: 'Queued AI Seminar cancelled.',
    );
    state = state.copyWith(
      backgroundJobs: _upsertBackgroundJob(state.backgroundJobs, cancelledJob),
      clearError: true,
    );
    _persistState();
  }

  Future<void> retry() async {
    final session = state.session;
    if (session == null || !state.canRetry) return;
    await start(session);
  }

  Future<void> recordUserIntervention({
    required String text,
    required AiSeminarUserInterventionAction requestedAction,
    AiSeminarRole? targetRole,
    int? now,
  }) async {
    final session = state.session;
    if (session == null) {
      const message = 'AI Seminar user turn requires an active session.';
      state = state.copyWith(error: message);
      throw StateError(message);
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      const message = 'AI Seminar user turn cannot be empty.';
      state = state.copyWith(error: message);
      throw StateError(message);
    }
    final baseDirector = state.directorState ??
        _directorStateFor(
          session: session,
          evidenceBundle: state.evidenceBundle,
          turns: state.turns,
          whiteboardEntries: state.whiteboardEntries,
        );
    if (baseDirector == null) {
      const message = 'AI Seminar Director state is not available.';
      state = state.copyWith(error: message);
      throw StateError(message);
    }
    final createdAt = now ?? DateTime.now().millisecondsSinceEpoch;
    final intervention = AiSeminarUserIntervention(
      id: 'user-$createdAt',
      text: trimmed,
      requestedAction: requestedAction,
      targetRole: requestedAction == AiSeminarUserInterventionAction.askRole
          ? targetRole ?? AiSeminarRole.critical
          : null,
      createdAt: createdAt,
    );
    final nextDirector = AiSeminarDirectorState(
      sessionId: baseDirector.sessionId,
      turnCount: baseDirector.turnCount,
      completedRoles: baseDirector.completedRoles,
      completedRoleTurnIds: baseDirector.completedRoleTurnIds,
      evidenceLedger: baseDirector.evidenceLedger,
      whiteboardLedger: baseDirector.whiteboardLedger,
      disagreementIds: baseDirector.disagreementIds,
      evidenceRefreshCount: baseDirector.evidenceRefreshCount,
      nextIntent: _nextIntentForUserIntervention(requestedAction),
      lastUserIntervention: intervention,
    );
    state = state.copyWith(
      directorState: nextDirector,
      clearError: true,
    );
    await _persistState();
  }

  Future<void> executeDirectorNextStep() async {
    final session = state.session;
    final evidenceBundle = state.evidenceBundle;
    final directorState = state.directorState;
    final intervention = directorState?.lastUserIntervention;
    if (session == null || evidenceBundle == null || directorState == null) {
      const message = 'AI Seminar Director step requires an active session.';
      state = state.copyWith(error: message);
      throw StateError(message);
    }
    if (directorState.nextIntent ==
        AiSeminarDirectorNextIntent.refreshEvidence) {
      await _executeEvidenceRefreshStep(session, directorState);
      return;
    }
    if (directorState.nextIntent != AiSeminarDirectorNextIntent.runRole ||
        intervention == null) {
      const message =
          'AI Seminar Director step is not ready for a reader-directed role.';
      state = state.copyWith(error: message);
      throw StateError(message);
    }

    final targetRole = intervention.targetRole ?? AiSeminarRole.critical;
    final generation = ++_generation;
    final token = AiSeminarCancellationToken();
    _activeToken?.cancel();
    _activeToken = token;
    final existingRunningJob =
        state.backgroundJob?.isActive == true ? state.backgroundJob : null;
    final startedAt = existingRunningJob?.startedAt ??
        _nextBackgroundJobStartedAt(DateTime.now().millisecondsSinceEpoch);
    final backgroundJob = existingRunningJob ??
        _newBackgroundJob(
          session,
          startedAt: startedAt,
          message: 'AI Seminar reader-directed role turn.',
        );
    final runningJob = backgroundJob.copyWith(
      status: AiSeminarBackgroundJobStatus.running,
      updatedAt: startedAt,
      completedAt: null,
      message: null,
      session: session,
    );
    state = state.copyWith(
      status: AiSeminarRunStatus.running,
      activeRole: null,
      partialRoleText: null,
      synthesis: null,
      lastRun: null,
      startedAt: state.startedAt ?? startedAt,
      completedAt: null,
      backgroundJob: runningJob,
      backgroundJobs: _upsertBackgroundJob(state.backgroundJobs, runningJob),
      clearError: true,
    );
    await _persistState();

    await for (final event in _service.runUserDirectedRole(
      session,
      evidenceBundle: evidenceBundle,
      priorTurns: state.turns,
      intervention: intervention,
      targetRole: targetRole,
      cancelToken: token,
    )) {
      if (!mounted || generation != _generation) return;
      _applyEvent(event);
      if (event.type != AiSeminarRuntimeEventType.roleDelta) {
        await _persistState();
      }
      if (event.status?.isTerminal == true) {
        _activeToken = null;
      }
    }
    if (!mounted || generation != _generation) return;
    if (state.status == AiSeminarRunStatus.running) {
      _completeUserDirectedRoleStep(session, evidenceBundle);
      await _persistState();
    }
    if (mounted && generation == _generation) {
      _activeToken = null;
      await _startNextQueuedJobIfAvailable();
    }
  }

  Future<void> _executeEvidenceRefreshStep(
    AiSeminarSessionContract session,
    AiSeminarDirectorState directorState,
  ) async {
    final providerDiagnostics = _providerContext.resolve();
    final resolvedSession = _sessionWithCurrentProviderBudget(
      session,
      providerDiagnostics,
    );
    final startedAt = _nextBackgroundJobStartedAt(
      DateTime.now().millisecondsSinceEpoch,
    );
    final backgroundJob = _newBackgroundJob(
      resolvedSession,
      startedAt: startedAt,
      message: 'AI Seminar refreshing evidence.',
    );
    final previous = _directorStateWithEvidenceRefresh(
      directorState,
      directorState.evidenceRefreshCount + 1,
    );
    await _runResolvedSession(
      resolvedSession,
      backgroundJob,
      providerDiagnostics,
      directorStateSeed: previous,
      startQueuedAfterCompletion: false,
    );
    if (!mounted) return;
    final refreshedDirector = _directorStateFor(
      session: state.session ?? resolvedSession,
      evidenceBundle: state.evidenceBundle,
      turns: state.turns,
      whiteboardEntries: state.whiteboardEntries,
      previous: previous,
    );
    state = state.copyWith(
      directorState: refreshedDirector ?? previous,
      clearError: true,
    );
    await _persistState();
    await _startNextQueuedJobIfAvailable();
  }

  void restore(AiSeminarRuntimeState restored) {
    _activeToken?.cancel();
    _activeToken = null;
    _generation += 1;
    state = restored;
    _persistState();
  }

  Future<void> discardLocalRuntimeState() async {
    _activeToken?.cancel();
    _activeToken = null;
    _generation += 1;
    try {
      await Prefs().prefs.remove(aiSeminarRuntimeStateV1PrefsKey);
    } catch (_) {
      // Best-effort local recovery cache cleanup.
    }
    state = AiSeminarRuntimeState.initial(
      providerDiagnostics: _providerContext.resolve(),
    );
  }

  Future<void> _startNextQueuedJobIfAvailable() async {
    if (!mounted) return;
    if (_activeToken != null || state.status == AiSeminarRunStatus.running) {
      return;
    }
    AiSeminarBackgroundJobSnapshot? queuedJob;
    for (final job in state.backgroundJobs) {
      if (job.isQueued && job.session != null) {
        queuedJob = job;
        break;
      }
    }
    if (queuedJob == null) return;
    if (!mounted) return;
    await _runResolvedSession(
      queuedJob.session!,
      queuedJob,
      _providerContext.resolve(),
    );
  }

  Future<AiSeminarReviewHandoffResult> sendToReview({int? now}) async {
    final run = state.lastRun;
    final synthesis = state.synthesis;
    if (run == null || synthesis == null || !run.readyForReview) {
      final message = 'AI Seminar synthesis is not ready for Review handoff.';
      state = state.copyWith(error: message);
      throw StateError(message);
    }

    try {
      final reviewItem = SeminarSynthesisReviewAdapter.fromSynthesis(
        seminarId: run.session.id,
        synthesis: synthesis,
        now: now,
      );
      await _reviewStore.upsert(reviewItem);

      final insertedCardIds = <String>[];
      final cards = SeminarSynthesisReviewAdapter.knowledgeCardsFromSynthesis(
        seminarId: run.session.id,
        synthesis: synthesis,
        now: now,
      );
      for (final card in cards) {
        final result = await _knowledgeCardStore.upsertCandidate(card);
        if (result.inserted) {
          insertedCardIds.add(result.card.id);
        }
        final cardReviewItem = KnowledgeCardReviewAdapter.fromKnowledgeCard(
          result.card,
          now: now,
        );
        if (cardReviewItem.status == ReviewItemStatus.draft ||
            cardReviewItem.status == ReviewItemStatus.pending) {
          await _reviewStore.upsert(cardReviewItem);
        }
      }
      final flashcards = SeminarSynthesisReviewAdapter.flashcardsFromSynthesis(
        seminarId: run.session.id,
        synthesis: synthesis,
        now: now,
      );
      for (final flashcard in flashcards) {
        await _reviewStore.upsert(flashcard);
      }

      state = state.copyWith(clearError: true);
      await _persistState();
      return AiSeminarReviewHandoffResult(
        reviewItemId: reviewItem.id,
        knowledgeCardIds: insertedCardIds,
        flashcardIds:
            flashcards.map((flashcard) => flashcard.sourceId).toList(),
      );
    } catch (error) {
      state = state.copyWith(error: error.toString());
      rethrow;
    }
  }

  Future<void> _persistState() async {
    try {
      if (!mounted) return;
      if (state.session == null && state.status == AiSeminarRunStatus.draft) {
        await Prefs().prefs.remove(aiSeminarRuntimeStateV1PrefsKey);
        return;
      }
      await Prefs().prefs.setString(
            aiSeminarRuntimeStateV1PrefsKey,
            jsonEncode(state.toJson()),
          );
    } catch (_) {
      // Best-effort local recovery cache; runtime must continue without it.
    }
  }

  void _applyEvent(AiSeminarRuntimeEvent event) {
    switch (event.type) {
      case AiSeminarRuntimeEventType.sessionStarted:
        final now = DateTime.now().millisecondsSinceEpoch;
        final backgroundJob = _markBackgroundJob(
          state.backgroundJob,
          AiSeminarBackgroundJobStatus.running,
          updatedAt: now,
        );
        state = state.copyWith(
          status: AiSeminarRunStatus.running,
          startedAt: state.startedAt ?? now,
          backgroundJob: backgroundJob,
          backgroundJobs:
              _upsertBackgroundJob(state.backgroundJobs, backgroundJob),
          directorState: _directorStateFor(
            session: state.session,
            evidenceBundle: state.evidenceBundle,
            turns: state.turns,
            whiteboardEntries: state.whiteboardEntries,
            previous: state.directorState,
          ),
          clearError: true,
        );
        break;
      case AiSeminarRuntimeEventType.evidenceReady:
        state = state.copyWith(
          evidenceBundle: event.evidenceBundle,
          directorState: _directorStateFor(
            session: state.session,
            evidenceBundle: event.evidenceBundle,
            turns: state.turns,
            whiteboardEntries: state.whiteboardEntries,
            previous: state.directorState,
          ),
          clearError: true,
        );
        break;
      case AiSeminarRuntimeEventType.roleStarted:
        state = state.copyWith(
          activeRole: event.activeRole,
          partialRoleText: '',
          clearError: true,
        );
        break;
      case AiSeminarRuntimeEventType.roleDelta:
        state = state.copyWith(
          activeRole: event.activeRole,
          partialRoleText: event.partialText,
          clearError: true,
        );
        break;
      case AiSeminarRuntimeEventType.roleCompleted:
      case AiSeminarRuntimeEventType.whiteboardUpdated:
        state = state.copyWith(
          turns: event.turns,
          whiteboardEntries: event.whiteboardEntries,
          directorState: _directorStateFor(
            session: state.session,
            evidenceBundle: state.evidenceBundle,
            turns: event.turns,
            whiteboardEntries: event.whiteboardEntries,
            previous: state.directorState,
          ),
          activeRole: null,
          partialRoleText: null,
          clearError: true,
        );
        break;
      case AiSeminarRuntimeEventType.synthesisReady:
        final completedAt =
            event.run?.completedAt ?? DateTime.now().millisecondsSinceEpoch;
        final backgroundJob = _markBackgroundJob(
          state.backgroundJob,
          AiSeminarBackgroundJobStatus.completed,
          updatedAt: completedAt,
          completedAt: completedAt,
        );
        state = state.copyWith(
          status: AiSeminarRunStatus.completed,
          turns: event.turns,
          whiteboardEntries: event.whiteboardEntries,
          directorState: _directorStateFor(
            session: state.session,
            evidenceBundle: state.evidenceBundle,
            turns: event.turns,
            whiteboardEntries: event.whiteboardEntries,
            previous: state.directorState,
          ),
          synthesis: event.synthesis,
          lastRun: event.run,
          activeRole: null,
          partialRoleText: null,
          completedAt: completedAt,
          backgroundJob: backgroundJob,
          backgroundJobs:
              _upsertBackgroundJob(state.backgroundJobs, backgroundJob),
          clearError: true,
        );
        break;
      case AiSeminarRuntimeEventType.needsEvidence:
      case AiSeminarRuntimeEventType.failed:
      case AiSeminarRuntimeEventType.cancelled:
        final completedAt =
            event.run?.completedAt ?? DateTime.now().millisecondsSinceEpoch;
        final backgroundJob = _markBackgroundJob(
          state.backgroundJob,
          _backgroundStatusForRun(event.status),
          updatedAt: completedAt,
          completedAt: completedAt,
          message: event.message,
        );
        state = state.copyWith(
          status: event.status,
          evidenceBundle: event.evidenceBundle,
          turns: event.turns,
          whiteboardEntries: event.whiteboardEntries,
          directorState: _directorStateFor(
            session: state.session,
            evidenceBundle: event.evidenceBundle,
            turns: event.turns,
            whiteboardEntries: event.whiteboardEntries,
            previous: state.directorState,
            nextIntent: event.status == AiSeminarRunStatus.needsEvidence
                ? AiSeminarDirectorNextIntent.refreshEvidence
                : state.directorState?.nextIntent ??
                    AiSeminarDirectorNextIntent.runRole,
          ),
          synthesis: event.synthesis,
          lastRun: event.run,
          activeRole: null,
          partialRoleText: null,
          error: event.message,
          completedAt: completedAt,
          backgroundJob: backgroundJob,
          backgroundJobs:
              _upsertBackgroundJob(state.backgroundJobs, backgroundJob),
        );
        break;
    }
  }

  void _completeUserDirectedRoleStep(
    AiSeminarSessionContract session,
    AiSeminarEvidenceBundle evidenceBundle,
  ) {
    final completedAt = DateTime.now().millisecondsSinceEpoch;
    final synthesis = AiSeminarOrchestrationService.synthesize(
      session: session,
      evidenceBundle: evidenceBundle,
      turns: state.turns,
    );
    final billingSnapshot = _billingSnapshot(
      session: session,
      turns: state.turns,
      completedAt: completedAt,
    );
    final tokenUsage = AiSeminarTokenUsage.aggregateRoleTurns(state.turns);
    final run = AiSeminarRun(
      session: session,
      status: AiSeminarRunStatus.completed,
      evidenceBundle: evidenceBundle,
      turns: List.unmodifiable(state.turns),
      synthesis: synthesis,
      startedAt: state.startedAt,
      completedAt: completedAt,
      tokenUsage: tokenUsage,
      estimatedCostUsd: billingSnapshot?.estimatedCostUsd ??
          _estimatedRunCostUsd(session.budgetPolicy, state.turns),
      costPriceSource: billingSnapshot?.pricingSource ??
          _costPriceSource(session.budgetPolicy, state.turns),
      billingSnapshot: billingSnapshot,
    );
    final backgroundJob = _markBackgroundJob(
      state.backgroundJob,
      AiSeminarBackgroundJobStatus.completed,
      updatedAt: completedAt,
      completedAt: completedAt,
    );
    state = state.copyWith(
      status: AiSeminarRunStatus.completed,
      synthesis: synthesis,
      lastRun: run,
      activeRole: null,
      partialRoleText: null,
      completedAt: completedAt,
      directorState: _directorStateFor(
        session: session,
        evidenceBundle: evidenceBundle,
        turns: state.turns,
        whiteboardEntries: state.whiteboardEntries,
        previous: state.directorState,
        nextIntent: AiSeminarDirectorNextIntent.end,
      ),
      backgroundJob: backgroundJob,
      backgroundJobs: _upsertBackgroundJob(state.backgroundJobs, backgroundJob),
      clearError: true,
    );
  }

  AiSeminarDirectorState? _directorStateFor({
    required AiSeminarSessionContract? session,
    required AiSeminarEvidenceBundle? evidenceBundle,
    required List<AiSeminarRoleTurn> turns,
    required List<AiSeminarWhiteboardEntry> whiteboardEntries,
    AiSeminarDirectorState? previous,
    AiSeminarDirectorNextIntent? nextIntent,
  }) {
    if (session == null) return previous;
    final completedTurns =
        turns.where((turn) => !turn.isFailed).toList(growable: false);
    final evidenceIds = <String>[
      if (previous != null) ...previous.evidenceLedger,
      if (evidenceBundle != null)
        ...evidenceBundle.evidence.map((item) => item.id),
    ];
    final allWhiteboardEntries = <AiSeminarWhiteboardEntry>[
      for (final turn in completedTurns) ...turn.whiteboardEntries,
      ...whiteboardEntries,
    ];
    final dedupedWhiteboardEntries = _dedupeWhiteboardEntries(
      allWhiteboardEntries,
    );
    final resolvedNextIntent = nextIntent ??
        _nextDirectorIntent(
          session: session,
          evidenceBundle: evidenceBundle,
          completedTurns: completedTurns,
          whiteboardEntries: dedupedWhiteboardEntries,
          previous: previous,
        );
    return AiSeminarDirectorState(
      sessionId: session.id,
      turnCount: completedTurns.length,
      completedRoles: completedTurns.map((turn) => turn.role).toList(),
      completedRoleTurnIds: completedTurns.map((turn) => turn.id).toList(),
      evidenceLedger: evidenceIds,
      whiteboardLedger:
          dedupedWhiteboardEntries.map((entry) => entry.id).toList(),
      disagreementIds: dedupedWhiteboardEntries
          .where((entry) => entry.kind == AiSeminarWhiteboardKind.disagreement)
          .map((entry) => entry.id)
          .toList(),
      evidenceRefreshCount: previous?.evidenceRefreshCount ?? 0,
      nextIntent: resolvedNextIntent,
      lastUserIntervention: previous?.lastUserIntervention,
    );
  }

  AiSeminarDirectorNextIntent _nextDirectorIntent({
    required AiSeminarSessionContract session,
    required AiSeminarEvidenceBundle? evidenceBundle,
    required List<AiSeminarRoleTurn> completedTurns,
    required List<AiSeminarWhiteboardEntry> whiteboardEntries,
    required AiSeminarDirectorState? previous,
  }) {
    if (evidenceBundle == null) {
      return AiSeminarDirectorNextIntent.runRole;
    }
    if (evidenceBundle.evidence.isEmpty ||
        !evidenceBundle.allEvidenceTraceable) {
      return AiSeminarDirectorNextIntent.refreshEvidence;
    }
    final plannedRoles = AiSeminarOrchestrationService.executionOrder(
      session.roles,
    );
    final completedRoles = completedTurns.map((turn) => turn.role).toSet();
    final hasRemainingRole =
        plannedRoles.any((role) => !completedRoles.contains(role));
    if (hasRemainingRole) {
      return AiSeminarDirectorNextIntent.runRole;
    }

    final hasOpenQuestion = whiteboardEntries.any(
      (entry) => entry.kind == AiSeminarWhiteboardKind.openQuestion,
    );
    if (hasOpenQuestion) {
      return AiSeminarDirectorNextIntent.askUser;
    }

    final hasDisagreement = whiteboardEntries.any(
      (entry) => entry.kind == AiSeminarWhiteboardKind.disagreement,
    );
    if (hasDisagreement) {
      final refreshBudget = (session.maxRounds - 1).clamp(0, 4);
      final refreshCount = previous?.evidenceRefreshCount ?? 0;
      if (refreshCount < refreshBudget) {
        return AiSeminarDirectorNextIntent.refreshEvidence;
      }
      return AiSeminarDirectorNextIntent.askUser;
    }

    return AiSeminarDirectorNextIntent.end;
  }

  static AiSeminarDirectorNextIntent _nextIntentForUserIntervention(
    AiSeminarUserInterventionAction action,
  ) {
    return switch (action) {
      AiSeminarUserInterventionAction.refreshEvidence =>
        AiSeminarDirectorNextIntent.refreshEvidence,
      AiSeminarUserInterventionAction.synthesize =>
        AiSeminarDirectorNextIntent.synthesize,
      AiSeminarUserInterventionAction.askRole ||
      AiSeminarUserInterventionAction.clarify =>
        AiSeminarDirectorNextIntent.runRole,
    };
  }

  static List<AiSeminarWhiteboardEntry> _dedupeWhiteboardEntries(
    List<AiSeminarWhiteboardEntry> entries,
  ) {
    final out = <AiSeminarWhiteboardEntry>[];
    final seen = <String>{};
    for (final entry in entries) {
      final id = entry.id.trim();
      if (id.isEmpty) continue;
      if (seen.add(id)) out.add(entry);
    }
    return List.unmodifiable(out);
  }

  static AiSeminarRuntimeState _initialState(
    AiSeminarProviderContextService providerContext,
  ) {
    final diagnostics = providerContext.resolve();
    final raw = Prefs().prefs.getString(aiSeminarRuntimeStateV1PrefsKey);
    if (raw == null || raw.trim().isEmpty) {
      return AiSeminarRuntimeState.initial(providerDiagnostics: diagnostics);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        Prefs().prefs.remove(aiSeminarRuntimeStateV1PrefsKey);
        return AiSeminarRuntimeState.initial(providerDiagnostics: diagnostics);
      }
      final decodedState = AiSeminarRuntimeState.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      final restored = decodedState.copyWith(
        providerDiagnostics: decodedState.providerDiagnostics ?? diagnostics,
        restoredFromLocalCache: true,
      );
      if (restored.status == AiSeminarRunStatus.running) {
        final completedAt = DateTime.now().millisecondsSinceEpoch;
        final session = restored.session;
        final evidenceBundle = restored.evidenceBundle;
        if (session != null &&
            evidenceBundle != null &&
            _canResumeWithCurrentProvider(session, diagnostics) &&
            AiSeminarRuntimeService.canResumeCheckpoint(
              session: session,
              evidenceBundle: evidenceBundle,
              completedTurns: restored.turns,
            )) {
          final resumableSession = _sessionWithCurrentProviderBudget(
            session,
            diagnostics,
          );
          final activeJob = (restored.backgroundJob ??
                  _newBackgroundJob(
                    resumableSession,
                    startedAt: restored.startedAt ?? completedAt,
                  ))
              .copyWith(
            status: AiSeminarBackgroundJobStatus.running,
            updatedAt: completedAt,
            completedAt: null,
            message:
                'AI Seminar restored from local checkpoint and will resume.',
            session: resumableSession,
          );
          final repairedJobs = _interruptNonActiveRestoredJobs(
            _upsertBackgroundJob(restored.backgroundJobs, activeJob),
            activeJob,
            completedAt,
          );
          final resumable = restored.copyWith(
            session: resumableSession,
            status: AiSeminarRunStatus.running,
            providerDiagnostics: diagnostics,
            evidenceBundle: evidenceBundle,
            activeRole: null,
            partialRoleText: null,
            backgroundJob: _backgroundJobFromList(activeJob, repairedJobs),
            backgroundJobs: repairedJobs,
            clearError: true,
          );
          _rewriteLocalRecoveryCache(resumable);
          return resumable;
        }
        final backgroundJob = _markBackgroundJob(
          restored.backgroundJob ??
              (session == null
                  ? null
                  : _newBackgroundJob(
                      session,
                      startedAt: restored.startedAt ?? completedAt,
                    )),
          AiSeminarBackgroundJobStatus.interrupted,
          updatedAt: completedAt,
          completedAt: completedAt,
          message:
              'AI Seminar was interrupted before it could finish. Retry to run it again.',
        );
        final fallbackEvidenceBundle = restored.evidenceBundle ??
            AiSeminarEvidenceBundle(
              query: session?.question ?? '',
              evidence: const <AiSeminarEvidence>[],
            );
        const fallbackTurns = <AiSeminarRoleTurn>[];
        final billingSnapshot = session == null
            ? null
            : _billingSnapshot(
                session: session,
                turns: fallbackTurns,
                completedAt: completedAt,
              );
        final tokenUsage = AiSeminarTokenUsage.aggregateRoleTurns(
          fallbackTurns,
        );
        final run = session == null
            ? null
            : AiSeminarRun(
                session: session,
                status: AiSeminarRunStatus.cancelled,
                evidenceBundle: fallbackEvidenceBundle,
                turns: fallbackTurns,
                startedAt: restored.startedAt,
                completedAt: completedAt,
                tokenUsage: tokenUsage,
                estimatedCostUsd: billingSnapshot?.estimatedCostUsd ??
                    _estimatedRunCostUsd(session.budgetPolicy, fallbackTurns),
                costPriceSource: billingSnapshot?.pricingSource ??
                    _costPriceSource(session.budgetPolicy, fallbackTurns),
                billingSnapshot: billingSnapshot,
                message:
                    'AI Seminar was interrupted before it could finish. Retry to run it again.',
              );
        final interruptedJobs = _interruptNonTerminalBackgroundJobs(
          _upsertBackgroundJob(restored.backgroundJobs, backgroundJob),
          completedAt,
        );
        AiSeminarBackgroundJobSnapshot? interruptedBackgroundJob =
            backgroundJob;
        if (backgroundJob != null) {
          for (final job in interruptedJobs) {
            if (job.id == backgroundJob.id) {
              interruptedBackgroundJob = job;
              break;
            }
          }
        }
        final interrupted = restored.copyWith(
          status: AiSeminarRunStatus.cancelled,
          evidenceBundle: fallbackEvidenceBundle,
          turns: fallbackTurns,
          whiteboardEntries: const <AiSeminarWhiteboardEntry>[],
          directorState: null,
          lastRun: run,
          activeRole: null,
          partialRoleText: null,
          backgroundJob: interruptedBackgroundJob,
          backgroundJobs: interruptedJobs,
          error:
              'AI Seminar was interrupted before it could finish. Retry to run it again.',
          completedAt: completedAt,
        );
        _rewriteLocalRecoveryCache(interrupted);
        return interrupted;
      }
      if (restored.backgroundJobs.any((job) => !job.status.isTerminal)) {
        final completedAt = DateTime.now().millisecondsSinceEpoch;
        final interruptedPendingJobs = _interruptNonTerminalBackgroundJobs(
          restored.backgroundJobs,
          completedAt,
        );
        final repaired = restored.copyWith(
          backgroundJob: _backgroundJobFromList(
            restored.backgroundJob,
            interruptedPendingJobs,
          ),
          backgroundJobs: interruptedPendingJobs,
        );
        _rewriteLocalRecoveryCache(repaired);
        return repaired;
      }
      return restored;
    } catch (_) {
      Prefs().prefs.remove(aiSeminarRuntimeStateV1PrefsKey);
      return AiSeminarRuntimeState.initial(providerDiagnostics: diagnostics);
    }
  }

  static void _rewriteLocalRecoveryCache(AiSeminarRuntimeState state) {
    try {
      unawaited(
        Prefs().prefs.setString(
              aiSeminarRuntimeStateV1PrefsKey,
              jsonEncode(state.toJson()),
            ),
      );
    } catch (_) {
      // Best-effort local recovery cache cleanup.
    }
  }

  static AiSeminarBackgroundJobSnapshot _newBackgroundJob(
    AiSeminarSessionContract session, {
    required int startedAt,
    AiSeminarBackgroundJobStatus status = AiSeminarBackgroundJobStatus.running,
    String? message,
  }) {
    return AiSeminarBackgroundJobSnapshot(
      id: _backgroundJobId(session, startedAt),
      sessionId: session.id,
      status: status,
      startedAt: startedAt,
      updatedAt: startedAt,
      message: message,
      session: session,
    );
  }

  static String _backgroundJobId(
    AiSeminarSessionContract session,
    int startedAt,
  ) {
    final safeSessionId = session.id
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .trim();
    final sessionPart = safeSessionId.isEmpty ? 'session' : safeSessionId;
    return 'seminar-job-$sessionPart-$startedAt';
  }

  static AiSeminarBackgroundJobSnapshot? _markBackgroundJob(
    AiSeminarBackgroundJobSnapshot? job,
    AiSeminarBackgroundJobStatus status, {
    required int updatedAt,
    int? completedAt,
    String? message,
  }) {
    if (job == null) return null;
    return job.copyWith(
      status: status,
      updatedAt: updatedAt,
      completedAt: status.isTerminal ? completedAt ?? updatedAt : null,
      message: message,
    );
  }

  static List<AiSeminarBackgroundJobSnapshot> _upsertBackgroundJob(
    List<AiSeminarBackgroundJobSnapshot> jobs,
    AiSeminarBackgroundJobSnapshot? job,
  ) {
    if (job == null) return _normalizeBackgroundJobs(jobs);
    final merged = <AiSeminarBackgroundJobSnapshot>[];
    var replaced = false;
    for (final existing in jobs) {
      if (existing.id.trim().isEmpty) continue;
      if (existing.id == job.id) {
        merged.add(job);
        replaced = true;
      } else {
        merged.add(existing);
      }
    }
    if (!replaced && job.id.trim().isNotEmpty) {
      merged.add(job);
    }
    return _normalizeBackgroundJobs(merged);
  }

  static List<AiSeminarBackgroundJobSnapshot> _normalizeBackgroundJobs(
    List<AiSeminarBackgroundJobSnapshot> jobs,
  ) {
    final byId = <String, AiSeminarBackgroundJobSnapshot>{};
    for (final job in jobs) {
      final id = job.id.trim();
      if (id.isEmpty) continue;
      byId[id] = job;
    }
    final normalized = byId.values.toList(growable: false)
      ..sort((a, b) {
        final started = a.startedAt.compareTo(b.startedAt);
        if (started != 0) return started;
        return a.id.compareTo(b.id);
      });
    final offset = normalized.length > _maxSeminarBackgroundJobs
        ? normalized.length - _maxSeminarBackgroundJobs
        : 0;
    return List<AiSeminarBackgroundJobSnapshot>.unmodifiable(
      normalized.skip(offset),
    );
  }

  static List<AiSeminarBackgroundJobSnapshot>
      _interruptNonTerminalBackgroundJobs(
    List<AiSeminarBackgroundJobSnapshot> jobs,
    int completedAt,
  ) {
    return _normalizeBackgroundJobs(
      jobs.map((job) {
        if (job.status.isTerminal) return job;
        return job.copyWith(
          status: AiSeminarBackgroundJobStatus.interrupted,
          updatedAt: completedAt,
          completedAt: completedAt,
          message: job.isQueued
              ? 'Queued AI Seminar was interrupted before it could start. Start it again manually.'
              : 'AI Seminar was interrupted before it could finish. Retry to run it again.',
        );
      }).toList(growable: false),
    );
  }

  static List<AiSeminarBackgroundJobSnapshot> _interruptNonActiveRestoredJobs(
    List<AiSeminarBackgroundJobSnapshot> jobs,
    AiSeminarBackgroundJobSnapshot activeJob,
    int completedAt,
  ) {
    return _normalizeBackgroundJobs(
      jobs.map((job) {
        if (job.id == activeJob.id) return activeJob;
        if (job.status.isTerminal) return job;
        return job.copyWith(
          status: AiSeminarBackgroundJobStatus.interrupted,
          updatedAt: completedAt,
          completedAt: completedAt,
          message: job.isQueued
              ? 'Queued AI Seminar was interrupted before it could start. Start it again manually.'
              : 'AI Seminar was interrupted before it could finish. Retry to run it again.',
        );
      }).toList(growable: false),
    );
  }

  static AiSeminarBackgroundJobSnapshot? _backgroundJobFromList(
    AiSeminarBackgroundJobSnapshot? backgroundJob,
    List<AiSeminarBackgroundJobSnapshot> jobs,
  ) {
    if (backgroundJob == null) return null;
    for (final job in jobs) {
      if (job.id == backgroundJob.id) return job;
    }
    return backgroundJob;
  }

  int _nextBackgroundJobStartedAt(int candidate) {
    var latest = state.backgroundJob?.startedAt ?? 0;
    for (final job in state.backgroundJobs) {
      if (job.startedAt > latest) {
        latest = job.startedAt;
      }
    }
    return candidate <= latest ? latest + 1 : candidate;
  }

  static AiSeminarBackgroundJobStatus _backgroundStatusForRun(
    AiSeminarRunStatus? status,
  ) {
    return switch (status) {
      AiSeminarRunStatus.completed => AiSeminarBackgroundJobStatus.completed,
      AiSeminarRunStatus.needsEvidence =>
        AiSeminarBackgroundJobStatus.needsEvidence,
      AiSeminarRunStatus.cancelled => AiSeminarBackgroundJobStatus.cancelled,
      AiSeminarRunStatus.failed => AiSeminarBackgroundJobStatus.failed,
      _ => AiSeminarBackgroundJobStatus.interrupted,
    };
  }

  static AiSeminarSessionContract _sessionWithCurrentProviderBudget(
    AiSeminarSessionContract session,
    AiSeminarProviderDiagnostics diagnostics,
  ) {
    final budgetPolicy = _budgetPolicyWithCurrentProviderPricing(
      session.budgetPolicy,
      diagnostics,
    );
    return AiSeminarSessionContract(
      id: session.id,
      question: session.question,
      bookId: session.bookId,
      roles: session.roles,
      scopes: session.scopes,
      sourceRefs: session.sourceRefs,
      allowWeb: session.allowWeb,
      writeRequiresApproval: session.writeRequiresApproval,
      maxRounds: session.maxRounds,
      budgetPolicy: budgetPolicy,
      billingContext: _billingContextForCurrentProvider(diagnostics),
      roleProfiles: session.roleProfiles,
      createdAt: session.createdAt,
    );
  }

  static AiSeminarBillingContext _billingContextForCurrentProvider(
    AiSeminarProviderDiagnostics diagnostics,
  ) {
    return AiSeminarBillingContext(
      providerId: diagnostics.providerId,
      providerName: diagnostics.providerName,
      providerType: diagnostics.providerType,
      modelId: diagnostics.modelId,
      pricingSource: diagnostics.costPriceSource,
      pricingCapturedAt: DateTime.now().millisecondsSinceEpoch,
      inputCostPerMillionTokens: diagnostics.inputCostPerMillionTokens,
      outputCostPerMillionTokens: diagnostics.outputCostPerMillionTokens,
      cacheReadCostPerMillionTokens: diagnostics.cacheReadCostPerMillionTokens,
      cacheWriteCostPerMillionTokens:
          diagnostics.cacheWriteCostPerMillionTokens,
    ).normalized;
  }

  static bool _canResumeWithCurrentProvider(
    AiSeminarSessionContract session,
    AiSeminarProviderDiagnostics diagnostics,
  ) {
    final context = session.billingContext;
    if (context == null) return false;
    if (context.providerId.trim() != diagnostics.providerId.trim()) {
      return false;
    }
    if (context.modelId.trim() != diagnostics.modelId.trim()) {
      return false;
    }
    return _billingPricingMatchesCurrentProvider(context, diagnostics);
  }

  static bool _billingPricingMatchesCurrentProvider(
    AiSeminarBillingContext context,
    AiSeminarProviderDiagnostics diagnostics,
  ) {
    final capturedHasPricing = context.inputCostPerMillionTokens != null ||
        context.outputCostPerMillionTokens != null ||
        context.cacheReadCostPerMillionTokens != null ||
        context.cacheWriteCostPerMillionTokens != null ||
        (context.pricingSource?.trim().isNotEmpty == true);
    if (!capturedHasPricing) return !diagnostics.hasPricingMetadata;
    if (!diagnostics.hasPricingMetadata) return false;
    return context.inputCostPerMillionTokens ==
            diagnostics.inputCostPerMillionTokens &&
        context.outputCostPerMillionTokens ==
            diagnostics.outputCostPerMillionTokens &&
        context.cacheReadCostPerMillionTokens ==
            diagnostics.cacheReadCostPerMillionTokens &&
        context.cacheWriteCostPerMillionTokens ==
            diagnostics.cacheWriteCostPerMillionTokens &&
        (context.pricingSource?.trim() ?? '') ==
            (diagnostics.costPriceSource?.trim() ?? '');
  }

  static AiSeminarBudgetPolicy? _budgetPolicyWithCurrentProviderPricing(
    AiSeminarBudgetPolicy? policy,
    AiSeminarProviderDiagnostics diagnostics,
  ) {
    if (policy == null) return null;
    final hasCurrentPricing = diagnostics.hasPricingMetadata;
    final hasCostCap = policy.maxRunCostUsd != null &&
        policy.maxRunCostUsd! > 0 &&
        hasCurrentPricing;
    final resolved = AiSeminarBudgetPolicy(
      maxRoleOutputTokens: policy.maxRoleOutputTokens,
      maxRunTokens: policy.maxRunTokens,
      maxRunCostUsd: hasCostCap ? policy.maxRunCostUsd : null,
      inputCostPerMillionTokens:
          hasCostCap ? diagnostics.inputCostPerMillionTokens : null,
      outputCostPerMillionTokens:
          hasCostCap ? diagnostics.outputCostPerMillionTokens : null,
      cacheReadCostPerMillionTokens:
          hasCostCap ? diagnostics.cacheReadCostPerMillionTokens : null,
      cacheWriteCostPerMillionTokens:
          hasCostCap ? diagnostics.cacheWriteCostPerMillionTokens : null,
      costPriceSource: hasCostCap ? diagnostics.costPriceSource : null,
    ).normalized;
    return resolved.hasLimits ? resolved : null;
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
    AiSeminarBudgetPolicy? policy,
    List<AiSeminarRoleTurn> turns,
  ) {
    if (turns.isEmpty) return null;
    if (policy == null || !policy.hasPricingMetadata) return null;
    return policy.costPriceSource;
  }
}

const int _maxSeminarBackgroundJobs = 20;
const Object _unset = Object();
