import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/service/ai/ai_seminar_evidence_broker.dart';
import 'package:papertok_reader/service/ai/ai_seminar_provider_context.dart';
import 'package:papertok_reader/service/ai/ai_seminar_runtime_service.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/rag/semantic_search_current_book.dart';
import 'package:papertok_reader/service/rag/semantic_search_library.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';

final aiSeminarRuntimeServiceProvider = Provider<AiSeminarRuntimeService>(
  (ref) {
    final currentBookSearch = SemanticSearchCurrentBook();
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

class AiSeminarRuntimeState {
  const AiSeminarRuntimeState({
    required this.status,
    this.session,
    this.evidenceBundle,
    this.activeRole,
    this.partialRoleText,
    this.turns = const <AiSeminarRoleTurn>[],
    this.whiteboardEntries = const <AiSeminarWhiteboardEntry>[],
    this.synthesis,
    this.lastRun,
    this.error,
    this.startedAt,
    this.completedAt,
    this.providerDiagnostics,
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
  final AiSeminarSynthesis? synthesis;
  final AiSeminarRun? lastRun;
  final String? error;
  final int? startedAt;
  final int? completedAt;
  final AiSeminarProviderDiagnostics? providerDiagnostics;
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
    Object? synthesis = _unset,
    Object? lastRun = _unset,
    String? error,
    bool clearError = false,
    int? startedAt,
    int? completedAt,
    AiSeminarProviderDiagnostics? providerDiagnostics,
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
      synthesis: identical(synthesis, _unset)
          ? this.synthesis
          : synthesis as AiSeminarSynthesis?,
      lastRun:
          identical(lastRun, _unset) ? this.lastRun : lastRun as AiSeminarRun?,
      error: clearError ? null : error ?? this.error,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      providerDiagnostics: providerDiagnostics ?? this.providerDiagnostics,
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
        if (synthesis != null) 'synthesis': synthesis!.toJson(),
        if (lastRun != null) 'lastRun': lastRun!.toJson(),
        if (error != null) 'error': error,
        if (startedAt != null) 'startedAt': startedAt,
        if (completedAt != null) 'completedAt': completedAt,
        if (providerDiagnostics != null)
          'providerDiagnostics': providerDiagnostics!.toJson(),
      };

  factory AiSeminarRuntimeState.fromJson(Map<String, dynamic> json) {
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
        );

  final AiSeminarRuntimeService _service;
  final ReviewItemStore _reviewStore;
  final KnowledgeCardStore _knowledgeCardStore;
  final AiSeminarProviderContextService _providerContext;
  AiSeminarCancellationToken? _activeToken;
  int _generation = 0;

  Future<void> start(AiSeminarSessionContract session) async {
    final generation = ++_generation;
    final token = AiSeminarCancellationToken();
    final providerDiagnostics = _providerContext.resolve();
    final resolvedSession = _sessionWithCurrentProviderBudget(
      session,
      providerDiagnostics,
    );
    _activeToken = token;
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
      turns: const <AiSeminarRoleTurn>[],
      whiteboardEntries: const <AiSeminarWhiteboardEntry>[],
    );
    await _persistState();

    await for (final event in _service.run(
      resolvedSession,
      cancelToken: token,
    )) {
      if (generation != _generation) return;
      _applyEvent(event);
      if (event.type != AiSeminarRuntimeEventType.roleDelta) {
        await _persistState();
      }
      if (event.status?.isTerminal == true) {
        _activeToken = null;
      }
    }
  }

  void cancel() {
    final session = state.session;
    if (session == null || !state.canCancel) return;
    _activeToken?.cancel();
    _activeToken = null;
    _generation += 1;
    final evidenceBundle = state.evidenceBundle ??
        AiSeminarEvidenceBundle(query: session.question, evidence: const []);
    final run = AiSeminarRun(
      session: session,
      status: AiSeminarRunStatus.cancelled,
      evidenceBundle: evidenceBundle,
      turns: state.turns,
      startedAt: state.startedAt,
      completedAt: DateTime.now().millisecondsSinceEpoch,
      tokenUsage: AiSeminarTokenUsage.aggregateRoleTurns(state.turns),
      estimatedCostUsd: _estimatedRunCostUsd(
        session.budgetPolicy,
        state.turns,
      ),
      costPriceSource: _costPriceSource(session.budgetPolicy, state.turns),
      message: 'AI Seminar cancelled.',
    );
    state = state.copyWith(
      status: AiSeminarRunStatus.cancelled,
      activeRole: null,
      partialRoleText: null,
      lastRun: run,
      error: run.message,
      completedAt: run.completedAt,
    );
    _persistState();
  }

  Future<void> retry() async {
    final session = state.session;
    if (session == null || !state.canRetry) return;
    await start(session);
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
        state = state.copyWith(
          status: AiSeminarRunStatus.running,
          startedAt: DateTime.now().millisecondsSinceEpoch,
          clearError: true,
        );
        break;
      case AiSeminarRuntimeEventType.evidenceReady:
        state = state.copyWith(
          evidenceBundle: event.evidenceBundle,
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
          activeRole: null,
          partialRoleText: null,
          clearError: true,
        );
        break;
      case AiSeminarRuntimeEventType.synthesisReady:
        state = state.copyWith(
          status: AiSeminarRunStatus.completed,
          turns: event.turns,
          whiteboardEntries: event.whiteboardEntries,
          synthesis: event.synthesis,
          lastRun: event.run,
          activeRole: null,
          partialRoleText: null,
          completedAt: event.run?.completedAt,
          clearError: true,
        );
        break;
      case AiSeminarRuntimeEventType.needsEvidence:
      case AiSeminarRuntimeEventType.failed:
      case AiSeminarRuntimeEventType.cancelled:
        state = state.copyWith(
          status: event.status,
          evidenceBundle: event.evidenceBundle,
          turns: event.turns,
          whiteboardEntries: event.whiteboardEntries,
          synthesis: event.synthesis,
          lastRun: event.run,
          activeRole: null,
          partialRoleText: null,
          error: event.message,
          completedAt: event.run?.completedAt,
        );
        break;
    }
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
        final interrupted = restored.copyWith(
          status: AiSeminarRunStatus.cancelled,
          activeRole: null,
          partialRoleText: null,
          error:
              'AI Seminar was interrupted before it could finish. Retry to run it again.',
          completedAt: DateTime.now().millisecondsSinceEpoch,
        );
        _rewriteLocalRecoveryCache(interrupted);
        return interrupted;
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
      allowWeb: session.allowWeb,
      writeRequiresApproval: session.writeRequiresApproval,
      maxRounds: session.maxRounds,
      budgetPolicy: budgetPolicy,
      createdAt: session.createdAt,
    );
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

  static String? _costPriceSource(
    AiSeminarBudgetPolicy? policy,
    List<AiSeminarRoleTurn> turns,
  ) {
    if (turns.isEmpty) return null;
    if (policy == null || !policy.hasPricingMetadata) return null;
    return policy.costPriceSource;
  }
}

const Object _unset = Object();
