import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/ai_model_capability.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/ai_provider_meta.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/providers/ai_seminar_runtime.dart';
import 'package:papertok_reader/service/ai/ai_seminar_provider_context.dart';
import 'package:papertok_reader/service/knowledge/concept_graph_store.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/ai/ai_seminar_runtime_service.dart';
import 'package:papertok_reader/service/review/review_inbox_controller.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  void configureProvider({bool withPricing = false}) {
    const now = 1000;
    Prefs().aiProvidersV1 = const [
      AiProviderMeta(
        id: 'local-gateway',
        name: 'Local Gateway',
        type: AiProviderType.openaiCompatible,
        enabled: true,
        isBuiltIn: false,
        createdAt: now,
        updatedAt: now,
      ),
    ];
    Prefs().selectedAiService = 'local-gateway';
    Prefs().saveAiConfig('local-gateway', const {
      'model': 'gpt-5.5',
      'url': 'http://localhost:3003/v1/',
    });
    Prefs().saveAiModelCapabilitiesCacheV1(
      'local-gateway',
      [
        AiModelCapability(
          id: 'gpt-5.5',
          contextWindow: 128000,
          maxOutputTokens: 8192,
          supportsTools: true,
          supportsImages: true,
          supportsThinking: true,
          inputCostPerMillionTokens: withPricing ? 2 : null,
          outputCostPerMillionTokens: withPricing ? 8 : null,
          cacheReadCostPerMillionTokens: withPricing ? 0.2 : null,
          cacheWriteCostPerMillionTokens: withPricing ? 1 : null,
          pricingSource: withPricing ? 'current-pricing-v1' : null,
        ),
      ],
    );
  }

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

  AiSeminarRuntimeService service({bool failFirst = false}) {
    var calls = 0;
    return AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        calls += 1;
        if (failFirst && calls == 1) {
          throw StateError('model unavailable');
        }
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
              if (invocation.role == AiSeminarRole.synthesizer)
                const AiSeminarWhiteboardEntry(
                  id: 'card-1',
                  kind: AiSeminarWhiteboardKind.candidateCard,
                  text: 'Candidate card',
                  evidenceRefIds: ['e1'],
                  conceptRefs: ['Seminar concept'],
                ),
              if (invocation.role == AiSeminarRole.synthesizer)
                const AiSeminarWhiteboardEntry(
                  id: 'review-1',
                  kind: AiSeminarWhiteboardKind.reviewSuggestion,
                  text: 'What should be reviewed later?',
                  evidenceRefIds: ['e1'],
                ),
            ],
          ),
        );
      },
      now: () => 1000,
    );
  }

  test('start captures evidence role turns whiteboard and synthesis', () async {
    configureProvider();
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(aiSeminarRuntimeProvider.notifier).start(
          AiSeminarSessionContract(id: 's1', question: 'Explain this.'),
        );
    final state = container.read(aiSeminarRuntimeProvider);

    expect(state.status, AiSeminarRunStatus.completed);
    expect(state.evidenceBundle!.evidence.single.id, 'e1');
    expect(state.turns.map((turn) => turn.role), [
      AiSeminarRole.critical,
      AiSeminarRole.supportive,
      AiSeminarRole.synthesizer,
    ]);
    expect(
      state.whiteboardEntries.map((entry) => entry.id),
      containsAll(['card-1', 'review-1']),
    );
    expect(state.synthesis!.summary, 'synthesizer response');
    expect(state.turns.first.tokenUsage, isNotNull);
    expect(state.lastRun!.tokenUsage!.totalTokens, greaterThan(0));
    expect(state.canRetry, false);
  });

  test('start captures provider diagnostics before streaming roles', () async {
    configureProvider();
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(aiSeminarRuntimeProvider.notifier).start(
          AiSeminarSessionContract(id: 's-provider', question: 'Explain this.'),
        );
    final state = container.read(aiSeminarRuntimeProvider);

    expect(state.providerDiagnostics?.providerName, 'Local Gateway');
    expect(state.providerDiagnostics?.modelId, 'gpt-5.5');
    expect(state.providerDiagnostics?.contextWindow, 128000);
    expect(state.providerDiagnostics?.seminarReady, true);
    expect(
      state.providerDiagnostics?.costStatus,
      AiSeminarCostStatus.unknown,
    );
  });

  test('manual cancel preserves billing snapshot for completed turns',
      () async {
    configureProvider(withPricing: true);
    final firstTurnDone = Completer<void>();
    final releaseStream = Completer<void>();
    final service = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, token) async* {
        if (invocation.role == AiSeminarRole.critical) {
          yield AiSeminarRoleStreamChunk(
            completedTurn: AiSeminarRoleTurn(
              id: 'turn-${invocation.role.asString}',
              role: invocation.role,
              prompt: invocation.prompt,
              responseText: '${invocation.role.asString} response',
              evidenceRefIds: const ['e1'],
              tokenUsage: const AiSeminarTokenUsage(
                inputTokens: 1000,
                outputTokens: 200,
                isEstimated: false,
                estimationMethod: 'provider-usage-tracker-v1',
                source: AiSeminarTokenUsage.sourceProviderReported,
              ),
            ),
          );
          if (!firstTurnDone.isCompleted) firstTurnDone.complete();
          return;
        }
        token.onCancel(() {
          if (!releaseStream.isCompleted) releaseStream.complete();
        });
        await releaseStream.future;
      },
      now: () => 1000,
    );
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(aiSeminarRuntimeProvider.notifier);

    final startFuture = notifier.start(
      AiSeminarSessionContract(id: 's-cancel-billing', question: 'Cancel?'),
    );
    await firstTurnDone.future;

    notifier.cancel();
    await startFuture;
    final state = container.read(aiSeminarRuntimeProvider);
    final billing = state.lastRun!.billingSnapshot!;

    expect(state.status, AiSeminarRunStatus.cancelled);
    expect(billing.usageSnapshot.source,
        AiSeminarTokenUsage.sourceProviderReported);
    expect(billing.pricingSource, 'current-pricing-v1');
    expect(billing.invoiceStatus,
        AiSeminarInvoiceReconciliationStatus.notConnected);
    expect(billing.isProviderInvoice, false);
  });

  test('retry clears failed partial state and reruns the same session',
      () async {
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(
          service(failFirst: true),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(aiSeminarRuntimeProvider.notifier);

    await notifier.start(
      AiSeminarSessionContract(id: 's2', question: 'Retry this.'),
    );
    expect(container.read(aiSeminarRuntimeProvider).status,
        AiSeminarRunStatus.failed);

    await notifier.retry();
    final state = container.read(aiSeminarRuntimeProvider);

    expect(state.status, AiSeminarRunStatus.completed);
    expect(state.partialRoleText, isNull);
    expect(state.activeRole, isNull);
    expect(state.turns, hasLength(3));
  });

  test('state serializes enough runtime data for restoration', () async {
    final state = AiSeminarRuntimeState.initial().copyWith(
      session: AiSeminarSessionContract(id: 's3', question: 'Restore?'),
      status: AiSeminarRunStatus.running,
      evidenceBundle: bundle(),
      activeRole: AiSeminarRole.critical,
      partialRoleText: 'critical partial',
      providerDiagnostics: const AiSeminarProviderDiagnostics(
        providerId: 'local-gateway',
        providerName: 'Local Gateway',
        providerType: 'openai',
        modelId: 'gpt-5.5',
        hasProviderConfig: true,
        hasCapabilityCache: true,
        seminarReady: true,
        contextWindow: 128000,
        maxOutputTokens: 8192,
        supportsTools: true,
        supportsImages: true,
        supportsThinking: true,
        costStatus: AiSeminarCostStatus.unknown,
        costUnknownReason: 'Provider pricing metadata is unavailable.',
      ),
      turns: const [
        AiSeminarRoleTurn(
          id: 'turn-critical',
          role: AiSeminarRole.critical,
          prompt: 'prompt',
          responseText: 'critical response',
          evidenceRefIds: ['e1'],
          tokenUsage: AiSeminarTokenUsage(
            inputTokens: 12,
            outputTokens: 4,
            isEstimated: true,
            estimationMethod: 'local-char-estimate-v1',
          ),
        ),
      ],
      lastRun: AiSeminarRun(
        session: AiSeminarSessionContract(id: 's3', question: 'Restore?'),
        status: AiSeminarRunStatus.completed,
        evidenceBundle: bundle(),
        turns: const [
          AiSeminarRoleTurn(
            id: 'turn-critical',
            role: AiSeminarRole.critical,
            prompt: 'prompt',
            responseText: 'critical response',
            evidenceRefIds: ['e1'],
            tokenUsage: AiSeminarTokenUsage(
              inputTokens: 12,
              outputTokens: 4,
              isEstimated: true,
              estimationMethod: 'local-char-estimate-v1',
            ),
          ),
        ],
        tokenUsage: AiSeminarTokenUsage(
          inputTokens: 12,
          outputTokens: 4,
          isEstimated: true,
          estimationMethod: 'local-char-estimate-v1',
        ),
      ),
    );

    final restored = AiSeminarRuntimeState.fromJson(state.toJson());

    expect(restored.session!.id, 's3');
    expect(restored.status, AiSeminarRunStatus.running);
    expect(restored.evidenceBundle!.evidence.single.id, 'e1');
    expect(restored.activeRole, AiSeminarRole.critical);
    expect(restored.partialRoleText, 'critical partial');
    expect(restored.providerDiagnostics!.providerName, 'Local Gateway');
    expect(restored.providerDiagnostics!.modelId, 'gpt-5.5');
    expect(restored.providerDiagnostics!.costUnknownReason,
        contains('pricing metadata'));
    expect(restored.turns.single.tokenUsage!.totalTokens, 16);
    expect(restored.lastRun!.tokenUsage!.totalTokens, 16);
  });

  test('completed seminar runtime state is persisted and restored', () async {
    configureProvider();
    final firstContainer = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
      ],
    );

    await firstContainer.read(aiSeminarRuntimeProvider.notifier).start(
          AiSeminarSessionContract(
            id: 's-persisted',
            question: 'Persist this seminar.',
          ),
        );
    firstContainer.dispose();

    final secondContainer = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
      ],
    );
    addTearDown(secondContainer.dispose);
    final restored = secondContainer.read(aiSeminarRuntimeProvider);

    expect(restored.status, AiSeminarRunStatus.completed);
    expect(restored.session!.id, 's-persisted');
    expect(restored.turns, hasLength(3));
    expect(restored.lastRun!.readyForReview, true);
    expect(restored.lastRun!.tokenUsage!.totalTokens, greaterThan(0));
  });

  test('running seminar runtime state restores as interrupted retryable state',
      () async {
    configureProvider();
    final runningState = AiSeminarRuntimeState.initial().copyWith(
      session: AiSeminarSessionContract(id: 's-running', question: 'Resume?'),
      status: AiSeminarRunStatus.running,
      evidenceBundle: bundle(),
      activeRole: AiSeminarRole.critical,
      partialRoleText: 'partial answer',
      turns: const [],
    );
    await Prefs().prefs.setString(
          aiSeminarRuntimeStateV1PrefsKey,
          jsonEncode(runningState.toJson()),
        );

    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
      ],
    );
    addTearDown(container.dispose);
    final restored = container.read(aiSeminarRuntimeProvider);

    expect(restored.status, AiSeminarRunStatus.cancelled);
    expect(restored.canRetry, true);
    expect(restored.activeRole, isNull);
    expect(restored.partialRoleText, isNull);
    expect(restored.error, contains('interrupted'));
    await Future<void>.delayed(Duration.zero);
    final persisted = jsonDecode(
      Prefs().prefs.getString(aiSeminarRuntimeStateV1PrefsKey)!,
    ) as Map<String, dynamic>;
    expect(persisted['status'], AiSeminarRunStatus.cancelled.asString);
    expect(persisted.containsKey('activeRole'), isFalse);
    expect(persisted.containsKey('partialRoleText'), isFalse);
  });

  test(
      'interrupted restore keeps captured billing snapshot for completed turns',
      () async {
    configureProvider(withPricing: true);
    final runningState = AiSeminarRuntimeState.initial().copyWith(
      session: AiSeminarSessionContract(
        id: 's-running-billing',
        question: 'Resume billing?',
        budgetPolicy: const AiSeminarBudgetPolicy(
          inputCostPerMillionTokens: 20,
          outputCostPerMillionTokens: 80,
          costPriceSource: 'current-pricing-should-not-win',
        ),
        billingContext: const AiSeminarBillingContext(
          providerId: 'captured-provider',
          providerName: 'Captured Provider',
          providerType: 'openai-compatible',
          modelId: 'captured-model',
          pricingSource: 'captured-pricing-v1',
          pricingCapturedAt: 12345,
          inputCostPerMillionTokens: 2,
          outputCostPerMillionTokens: 8,
        ),
      ),
      status: AiSeminarRunStatus.running,
      evidenceBundle: bundle(),
      activeRole: AiSeminarRole.supportive,
      partialRoleText: 'partial answer',
      turns: const [
        AiSeminarRoleTurn(
          id: 'turn-critical',
          role: AiSeminarRole.critical,
          prompt: 'prompt',
          responseText: 'critical response',
          evidenceRefIds: ['e1'],
          tokenUsage: AiSeminarTokenUsage(
            inputTokens: 1000,
            outputTokens: 200,
            isEstimated: false,
            estimationMethod: 'provider-usage-tracker-v1',
            source: AiSeminarTokenUsage.sourceProviderReported,
          ),
        ),
      ],
    );
    await Prefs().prefs.setString(
          aiSeminarRuntimeStateV1PrefsKey,
          jsonEncode(runningState.toJson()),
        );

    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
      ],
    );
    addTearDown(container.dispose);
    final restored = container.read(aiSeminarRuntimeProvider);
    final billing = restored.lastRun!.billingSnapshot!;

    expect(restored.status, AiSeminarRunStatus.cancelled);
    expect(restored.lastRun!.status, AiSeminarRunStatus.cancelled);
    expect(billing.providerId, 'captured-provider');
    expect(billing.modelId, 'captured-model');
    expect(billing.pricingSource, 'captured-pricing-v1');
    expect(billing.pricingCapturedAt, 12345);
    expect(billing.usageSnapshot.source,
        AiSeminarTokenUsage.sourceProviderReported);
    expect(billing.estimatedCostUsd, closeTo(0.0036, 0.000001));
    expect(
      billing.invoiceStatus,
      AiSeminarInvoiceReconciliationStatus.notConnected,
    );
  });

  test('restored seminar keeps persisted provider diagnostics', () async {
    configureProvider();
    final state = AiSeminarRuntimeState.initial(
      providerDiagnostics: const AiSeminarProviderDiagnostics(
        providerId: 'original-provider',
        providerName: 'Original Provider',
        providerType: 'openai',
        modelId: 'original-model',
        hasProviderConfig: true,
        hasCapabilityCache: true,
        seminarReady: true,
        costStatus: AiSeminarCostStatus.unknown,
        costUnknownReason: 'Provider pricing metadata is unavailable.',
      ),
    ).copyWith(
      session: AiSeminarSessionContract(id: 's-provider', question: 'Restore?'),
      status: AiSeminarRunStatus.completed,
      evidenceBundle: bundle(),
      turns: const [],
    );
    await Prefs().prefs.setString(
          aiSeminarRuntimeStateV1PrefsKey,
          jsonEncode(state.toJson()),
        );

    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
      ],
    );
    addTearDown(container.dispose);
    final restored = container.read(aiSeminarRuntimeProvider);

    expect(restored.providerDiagnostics?.providerName, 'Original Provider');
    expect(restored.providerDiagnostics?.modelId, 'original-model');
  });

  test('restored seminar keeps session budget policy for retry', () async {
    configureProvider();
    final runningState = AiSeminarRuntimeState.initial().copyWith(
      session: AiSeminarSessionContract(
        id: 's-budget-retry',
        question: 'Retry budget?',
        budgetPolicy: const AiSeminarBudgetPolicy(
          maxRoleOutputTokens: 1,
          maxRunTokens: 50,
        ),
      ),
      status: AiSeminarRunStatus.running,
      evidenceBundle: bundle(),
      activeRole: AiSeminarRole.critical,
      partialRoleText: 'partial answer',
      turns: const [],
    );
    await Prefs().prefs.setString(
          aiSeminarRuntimeStateV1PrefsKey,
          jsonEncode(runningState.toJson()),
        );

    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(aiSeminarRuntimeProvider.notifier);

    expect(
      container
          .read(aiSeminarRuntimeProvider)
          .session!
          .budgetPolicy!
          .maxRoleOutputTokens,
      1,
    );

    await notifier.retry();
    final retried = container.read(aiSeminarRuntimeProvider);

    expect(retried.status, AiSeminarRunStatus.failed);
    expect(retried.error, contains('role output token budget'));
    expect(retried.session!.budgetPolicy!.maxRoleOutputTokens, 1);
  });

  test(
      'retry strips stale restored cost cap when current provider lacks pricing',
      () async {
    configureProvider();
    final runningState = AiSeminarRuntimeState.initial().copyWith(
      session: AiSeminarSessionContract(
        id: 's-stale-cost-retry',
        question: 'Retry cost?',
        budgetPolicy: const AiSeminarBudgetPolicy(
          maxRunCostUsd: 0.000001,
          inputCostPerMillionTokens: 2,
          outputCostPerMillionTokens: 8,
          costPriceSource: 'stale-pricing-v0',
        ),
      ),
      status: AiSeminarRunStatus.running,
      evidenceBundle: bundle(),
      activeRole: AiSeminarRole.critical,
      partialRoleText: 'partial answer',
      turns: const [],
    );
    await Prefs().prefs.setString(
          aiSeminarRuntimeStateV1PrefsKey,
          jsonEncode(runningState.toJson()),
        );

    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(aiSeminarRuntimeProvider.notifier);

    expect(container.read(aiSeminarRuntimeProvider).canRetry, true);

    await notifier.retry();
    final retried = container.read(aiSeminarRuntimeProvider);

    expect(retried.status, AiSeminarRunStatus.completed);
    expect(retried.session!.budgetPolicy, isNull);
    expect(retried.lastRun!.estimatedCostUsd, isNull);
  });

  test('cost cap failure cannot be sent to Review and leaves stores empty',
      () async {
    configureProvider(withPricing: true);
    final tempRoot = await Directory.systemTemp.createTemp();
    addTearDown(() => tempRoot.deleteSync(recursive: true));
    final reviewStore = ReviewItemStore(rootDir: tempRoot);
    final cardStore = KnowledgeCardStore(rootDir: tempRoot);
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
        aiSeminarReviewItemStoreProvider.overrideWithValue(reviewStore),
        aiSeminarKnowledgeCardStoreProvider.overrideWithValue(cardStore),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(aiSeminarRuntimeProvider.notifier);

    await notifier.start(
      AiSeminarSessionContract(
        id: 's-cost-review-block',
        question: 'Cost cap?',
        budgetPolicy: const AiSeminarBudgetPolicy(
          maxRunCostUsd: 0.000001,
          inputCostPerMillionTokens: 1,
          outputCostPerMillionTokens: 1,
          costPriceSource: 'stale-pricing-v0',
        ),
      ),
    );
    final state = container.read(aiSeminarRuntimeProvider);

    expect(state.status, AiSeminarRunStatus.failed);
    expect(state.error, contains('run cost cap'));
    expect(state.canSendToReview, false);
    await expectLater(notifier.sendToReview(), throwsStateError);
    expect(await reviewStore.list(), isEmpty);
    expect(await cardStore.list(), isEmpty);
  });

  test('sendToReview hands off synthesis candidate cards and flashcards',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp();
    addTearDown(() => tempRoot.deleteSync(recursive: true));
    final reviewStore = ReviewItemStore(rootDir: tempRoot);
    final cardStore = KnowledgeCardStore(rootDir: tempRoot);
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
        aiSeminarReviewItemStoreProvider.overrideWithValue(reviewStore),
        aiSeminarKnowledgeCardStoreProvider.overrideWithValue(cardStore),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(aiSeminarRuntimeProvider.notifier);
    await notifier.start(
      AiSeminarSessionContract(id: 's4', question: 'Send this to Review.'),
    );

    final result = await notifier.sendToReview(now: 200);
    final pendingItems =
        await reviewStore.list(status: ReviewItemStatus.pending);
    final seminarCards =
        await cardStore.list(origin: KnowledgeCardOrigin.seminar);

    expect(result.reviewItemId, 'seminar-synthesis:s4');
    expect(result.knowledgeCardIds, ['seminar:s4:card-1']);
    expect(result.flashcardIds, ['seminar:s4:question-1']);
    expect(
      pendingItems.map((item) => item.sourceType).toSet(),
      containsAll({
        ReviewItemSourceType.seminarSynthesis,
        ReviewItemSourceType.knowledgeCard,
        ReviewItemSourceType.flashcardCandidate,
      }),
    );
    expect(seminarCards.single.reviewState, KnowledgeCardReviewState.pending);
    expect(seminarCards.single.isUserAsset, false);
    expect(seminarCards.single.conceptRefs, ['Seminar concept']);
  });

  test('seminar candidate concepts seed graph candidates after Review apply',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp();
    addTearDown(() => tempRoot.deleteSync(recursive: true));
    final reviewStore = ReviewItemStore(rootDir: tempRoot);
    final cardStore = KnowledgeCardStore(rootDir: tempRoot);
    final graphStore = ConceptGraphStore(rootDir: tempRoot);
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
        aiSeminarReviewItemStoreProvider.overrideWithValue(reviewStore),
        aiSeminarKnowledgeCardStoreProvider.overrideWithValue(cardStore),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(aiSeminarRuntimeProvider.notifier);

    await notifier.start(
      AiSeminarSessionContract(id: 's6', question: 'Seed graph.'),
    );
    await notifier.sendToReview(now: 400);
    final cardItem = (await reviewStore.list(
      status: ReviewItemStatus.pending,
      sourceType: ReviewItemSourceType.knowledgeCard,
    ))
        .single;
    final controller = ReviewInboxController(
      rootDir: tempRoot,
      reviewStore: reviewStore,
      knowledgeCardStore: cardStore,
      conceptGraphStore: graphStore,
      now: () => 401,
    );

    await controller.approve(cardItem.id);
    await controller.apply(cardItem.id);

    final conceptNodes = (await graphStore.listNodes())
        .where((node) => node.type == ConceptNodeType.concept)
        .toList(growable: false);
    final relationItems = await reviewStore.list(
      status: ReviewItemStatus.pending,
      sourceType: ReviewItemSourceType.conceptGraphRelation,
    );

    expect(conceptNodes.map((node) => node.label), contains('Seminar concept'));
    expect(relationItems, isNotEmpty);
  });

  test('sendToReview retry repairs candidate card review item', () async {
    final tempRoot = await Directory.systemTemp.createTemp();
    addTearDown(() => tempRoot.deleteSync(recursive: true));
    final reviewStore = _FailsFirstKnowledgeCardReviewStore(rootDir: tempRoot);
    final cardStore = KnowledgeCardStore(rootDir: tempRoot);
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
        aiSeminarReviewItemStoreProvider.overrideWithValue(reviewStore),
        aiSeminarKnowledgeCardStoreProvider.overrideWithValue(cardStore),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(aiSeminarRuntimeProvider.notifier);

    await notifier.start(
      AiSeminarSessionContract(id: 's5', question: 'Repair ReviewItem.'),
    );

    await expectLater(
      notifier.sendToReview(now: 300),
      throwsA(isA<StateError>()),
    );
    expect(await cardStore.list(origin: KnowledgeCardOrigin.seminar),
        hasLength(1));

    final result = await notifier.sendToReview(now: 301);
    final pendingItems =
        await reviewStore.list(status: ReviewItemStatus.pending);

    expect(result.knowledgeCardIds, isEmpty);
    expect(
      pendingItems.where(
        (item) => item.sourceType == ReviewItemSourceType.knowledgeCard,
      ),
      hasLength(1),
    );
  });
}

class _FailsFirstKnowledgeCardReviewStore extends ReviewItemStore {
  _FailsFirstKnowledgeCardReviewStore({required super.rootDir});

  var _remainingFailures = 1;

  @override
  Future<ReviewItem> upsert(ReviewItem item) {
    if (item.sourceType == ReviewItemSourceType.knowledgeCard &&
        _remainingFailures > 0) {
      _remainingFailures -= 1;
      return Future<ReviewItem>.error(StateError('simulated review write'));
    }
    return super.upsert(item);
  }
}
