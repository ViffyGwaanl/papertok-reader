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

  test('scoped Seminar runtime providers isolate run state', () async {
    configureProvider();
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(aiSeminarRuntimeScopedProvider('seminar-run-a').notifier)
        .start(
          AiSeminarSessionContract(
            id: 'seminar-run-a',
            question: 'Explain run A.',
          ),
        );
    await container
        .read(aiSeminarRuntimeScopedProvider('seminar-run-b').notifier)
        .start(
          AiSeminarSessionContract(
            id: 'seminar-run-b',
            question: 'Explain run B.',
          ),
        );

    final runA = container.read(
      aiSeminarRuntimeScopedProvider('seminar-run-a'),
    );
    final runB = container.read(
      aiSeminarRuntimeScopedProvider('seminar-run-b'),
    );
    final legacy = container.read(aiSeminarRuntimeProvider);

    expect(runA.session?.id, 'seminar-run-a');
    expect(runA.session?.question, 'Explain run A.');
    expect(runA.status, AiSeminarRunStatus.completed);
    expect(runA.turns, hasLength(3));
    expect(runB.session?.id, 'seminar-run-b');
    expect(runB.session?.question, 'Explain run B.');
    expect(runB.status, AiSeminarRunStatus.completed);
    expect(runB.turns, hasLength(3));
    expect(legacy.session, isNull);
    expect(legacy.status, AiSeminarRunStatus.draft);
  });

  test('scoped Seminar runtime providers serialize model runs', () async {
    configureProvider();
    final firstRoleStarted = Completer<void>();
    final releaseFirstRole = Completer<void>();
    final secondRoleStarted = Completer<void>();
    final runtimeService = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        if (invocation.session.id == 'seminar-run-a' &&
            invocation.role == AiSeminarRole.critical) {
          if (!firstRoleStarted.isCompleted) firstRoleStarted.complete();
          await releaseFirstRole.future;
        }
        if (invocation.session.id == 'seminar-run-b' &&
            invocation.role == AiSeminarRole.critical) {
          if (!secondRoleStarted.isCompleted) secondRoleStarted.complete();
        }
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.session.id}-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText:
                '${invocation.session.id} ${invocation.role.asString}',
            evidenceRefIds: const ['e1'],
          ),
        );
      },
      now: () => 1000,
    );
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(runtimeService),
      ],
    );
    addTearDown(container.dispose);

    final firstStart = container
        .read(aiSeminarRuntimeScopedProvider('seminar-run-a').notifier)
        .start(
          AiSeminarSessionContract(
            id: 'seminar-run-a',
            question: 'Explain run A.',
          ),
        );
    await firstRoleStarted.future;

    final secondStart = container
        .read(aiSeminarRuntimeScopedProvider('seminar-run-b').notifier)
        .start(
          AiSeminarSessionContract(
            id: 'seminar-run-b',
            question: 'Explain run B.',
          ),
        );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(secondRoleStarted.isCompleted, isFalse);

    releaseFirstRole.complete();
    await secondRoleStarted.future;
    await Future.wait([firstStart, secondStart]);

    expect(
      container.read(aiSeminarRuntimeScopedProvider('seminar-run-a')).status,
      AiSeminarRunStatus.completed,
    );
    expect(
      container.read(aiSeminarRuntimeScopedProvider('seminar-run-b')).status,
      AiSeminarRunStatus.completed,
    );
  });

  test('scoped Seminar runtime resumes from persisted checkpoint', () async {
    configureProvider();
    final invokedRoles = <AiSeminarRole>[];
    final resumeCompleted = Completer<void>();
    const sessionId = 'seminar-chat-resume';
    final runningState = AiSeminarRuntimeState.initial().copyWith(
      session: AiSeminarSessionContract(
        id: sessionId,
        question: 'Resume the chat seminar.',
        billingContext: AiSeminarBillingContext(
          providerId: 'local-gateway',
          providerName: 'Local Gateway',
          providerType: 'openai-compatible',
          modelId: 'gpt-5.5',
        ),
      ),
      status: AiSeminarRunStatus.running,
      backgroundJob: const AiSeminarBackgroundJobSnapshot(
        id: 'job-scoped-running-resume',
        sessionId: sessionId,
        status: AiSeminarBackgroundJobStatus.running,
        startedAt: 900,
        updatedAt: 901,
      ),
      backgroundJobs: const [
        AiSeminarBackgroundJobSnapshot(
          id: 'job-scoped-running-resume',
          sessionId: sessionId,
          status: AiSeminarBackgroundJobStatus.running,
          startedAt: 900,
          updatedAt: 901,
        ),
      ],
      evidenceBundle: bundle(),
      activeRole: AiSeminarRole.supportive,
      partialRoleText: 'partial scoped stream should be ignored',
      turns: const [
        AiSeminarRoleTurn(
          id: 'turn-critical',
          role: AiSeminarRole.critical,
          prompt: 'critical prompt',
          responseText: 'critical response',
          evidenceRefIds: ['e1'],
          tokenUsage: AiSeminarTokenUsage(
            inputTokens: 10,
            outputTokens: 4,
            isEstimated: true,
            estimationMethod: 'local-char-estimate-v1',
          ),
        ),
      ],
    );
    await Prefs().prefs.setString(
          '$aiSeminarRuntimeScopedStateV1PrefsPrefix'
          '${Uri.encodeComponent(sessionId)}',
          jsonEncode(runningState.toJson()),
        );
    final resumeService = AiSeminarRuntimeService(
      fetchEvidence: (_) async {
        fail('scoped restored resume should use persisted evidence');
      },
      streamRole: (invocation, _) async* {
        invokedRoles.add(invocation.role);
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
          ),
        );
        if (invocation.role == AiSeminarRole.synthesizer &&
            !resumeCompleted.isCompleted) {
          resumeCompleted.complete();
        }
      },
      now: () => 1000,
    );
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(resumeService),
      ],
    );
    addTearDown(container.dispose);

    container.read(aiSeminarRuntimeScopedProvider(sessionId));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(invokedRoles, isEmpty);
    final resumeFuture = container
        .read(aiSeminarRuntimeScopedProvider(sessionId).notifier)
        .resumeRestoredRunning();
    await resumeCompleted.future.timeout(const Duration(seconds: 2));
    await resumeFuture;
    for (var i = 0; i < 20; i += 1) {
      if (container.read(aiSeminarRuntimeScopedProvider(sessionId)).status !=
          AiSeminarRunStatus.running) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final restored = container.read(aiSeminarRuntimeScopedProvider(sessionId));
    final legacy = container.read(aiSeminarRuntimeProvider);

    expect(invokedRoles, [
      AiSeminarRole.supportive,
      AiSeminarRole.synthesizer,
    ]);
    expect(restored.status, AiSeminarRunStatus.completed);
    expect(restored.session!.id, sessionId);
    expect(restored.restoredFromLocalCache, isTrue);
    expect(restored.turns.map((turn) => turn.role), [
      AiSeminarRole.critical,
      AiSeminarRole.supportive,
      AiSeminarRole.synthesizer,
    ]);
    expect(restored.backgroundJob!.id, 'job-scoped-running-resume');
    expect(
        restored.backgroundJob!.status, AiSeminarBackgroundJobStatus.completed);
    expect(legacy.session, isNull);
  });

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
    expect(
      state.directorState!.whiteboardLedger,
      ['card-1', 'review-1'],
    );
    expect(state.directorState!.nextIntent, AiSeminarDirectorNextIntent.end);
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

  test('director asks for user input when completed run leaves open questions',
      () async {
    configureProvider();
    final runtimeService = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
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
                  id: 'open-question-1',
                  kind: AiSeminarWhiteboardKind.openQuestion,
                  text: 'Which interpretation should the reader test next?',
                  role: AiSeminarRole.synthesizer,
                  evidenceRefIds: ['e1'],
                ),
            ],
          ),
        );
      },
      now: () => 1000,
    );
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(runtimeService),
      ],
    );
    addTearDown(container.dispose);

    await container.read(aiSeminarRuntimeProvider.notifier).start(
          AiSeminarSessionContract(id: 's-open-question', question: 'Explain.'),
        );
    final state = container.read(aiSeminarRuntimeProvider);

    expect(state.status, AiSeminarRunStatus.completed);
    expect(
        state.directorState!.nextIntent, AiSeminarDirectorNextIntent.askUser);
    expect(state.directorState!.needsUserInput, true);
    expect(state.directorState!.whiteboardLedger, contains('open-question-1'));
  });

  test('auto refresh asks reader when disagreement exhausts round budget',
      () async {
    configureProvider();
    var fetchCount = 0;
    final runtimeService = AiSeminarRuntimeService(
      fetchEvidence: (_) async {
        fetchCount += 1;
        return bundle();
      },
      streamRole: (invocation, _) async* {
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
                  id: 'disagreement-1',
                  kind: AiSeminarWhiteboardKind.disagreement,
                  text: 'The supportive reading misses a contradiction.',
                  role: AiSeminarRole.critical,
                  evidenceRefIds: ['e1'],
                ),
            ],
          ),
        );
      },
      now: () => 1000,
    );
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(runtimeService),
      ],
    );
    addTearDown(container.dispose);

    await container.read(aiSeminarRuntimeProvider.notifier).start(
          AiSeminarSessionContract(
            id: 's-disagreement',
            question: 'Compare these readings.',
          ),
        );
    final state = container.read(aiSeminarRuntimeProvider);

    expect(fetchCount, 2);
    expect(state.status, AiSeminarRunStatus.completed);
    expect(
      state.directorState!.nextIntent,
      AiSeminarDirectorNextIntent.askUser,
    );
    expect(state.directorState!.evidenceRefreshCount, 1);
    expect(state.directorState!.disagreementIds, ['disagreement-1']);
  });

  test('auto refreshes evidence when disagreement still has round budget',
      () async {
    configureProvider();
    var fetchCount = 0;
    final runtimeService = AiSeminarRuntimeService(
      fetchEvidence: (_) async {
        fetchCount += 1;
        final evidenceId = fetchCount == 1 ? 'e1' : 'e2';
        return AiSeminarEvidenceBundle(
          query: 'Compare these readings.',
          evidence: [
            AiSeminarEvidence(
              id: evidenceId,
              scope: AiSeminarEvidenceScope.currentBook,
              text: fetchCount == 1
                  ? 'The first source passage.'
                  : 'The refreshed source passage.',
              sourceRef: traceableRef(),
            ),
          ],
        );
      },
      streamRole: (invocation, _) async* {
        final evidenceId = invocation.evidenceBundle.evidence.single.id;
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}-$evidenceId',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText:
                '${invocation.role.asString} response using $evidenceId',
            evidenceRefIds: [evidenceId],
            whiteboardEntries: [
              if (evidenceId == 'e1' &&
                  invocation.role == AiSeminarRole.critical)
                const AiSeminarWhiteboardEntry(
                  id: 'disagreement-1',
                  kind: AiSeminarWhiteboardKind.disagreement,
                  text: 'The supportive reading misses a contradiction.',
                  role: AiSeminarRole.critical,
                  evidenceRefIds: ['e1'],
                ),
            ],
          ),
        );
      },
      now: () => 1000,
    );
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(runtimeService),
      ],
    );
    addTearDown(container.dispose);

    await container.read(aiSeminarRuntimeProvider.notifier).start(
          AiSeminarSessionContract(
            id: 's-auto-refresh-disagreement',
            question: 'Compare these readings.',
            maxRounds: 2,
          ),
        );
    final state = container.read(aiSeminarRuntimeProvider);

    expect(fetchCount, 2);
    expect(state.status, AiSeminarRunStatus.completed);
    expect(state.evidenceBundle!.evidence.map((item) => item.id), ['e2']);
    expect(state.turns.map((turn) => turn.id), [
      'turn-critical-e2',
      'turn-supportive-e2',
      'turn-synthesizer-e2',
    ]);
    expect(state.directorState!.evidenceRefreshCount, 1);
    expect(state.directorState!.disagreementIds, isEmpty);
    expect(state.directorState!.nextIntent, AiSeminarDirectorNextIntent.end);
    expect(state.synthesis!.summary, 'synthesizer response using e2');
  });

  test('records user intervention without turning it into evidence', () async {
    configureProvider();
    final runtimeService = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
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
                  id: 'open-question-1',
                  kind: AiSeminarWhiteboardKind.openQuestion,
                  text: 'Which interpretation should the reader test next?',
                  role: AiSeminarRole.synthesizer,
                  evidenceRefIds: ['e1'],
                ),
            ],
          ),
        );
      },
      now: () => 1000,
    );
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(runtimeService),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(aiSeminarRuntimeProvider.notifier);

    await notifier.start(
      AiSeminarSessionContract(id: 's-user-turn', question: 'Explain.'),
    );
    await notifier.recordUserIntervention(
      text: '我认为这里应该先区分定义和例子。',
      requestedAction: AiSeminarUserInterventionAction.askRole,
      targetRole: AiSeminarRole.critical,
      now: 1234,
    );
    final state = container.read(aiSeminarRuntimeProvider);

    expect(
        state.directorState!.nextIntent, AiSeminarDirectorNextIntent.runRole);
    expect(
      state.directorState!.lastUserIntervention!.requestedAction,
      AiSeminarUserInterventionAction.askRole,
    );
    expect(state.directorState!.lastUserIntervention!.targetRole,
        AiSeminarRole.critical);
    expect(state.directorState!.lastUserIntervention!.text, '我认为这里应该先区分定义和例子。');
    expect(state.directorState!.lastUserIntervention!.isEvidence, false);
    expect(state.evidenceBundle!.evidence.map((item) => item.id), ['e1']);

    final persisted = jsonDecode(
      Prefs().prefs.getString(aiSeminarRuntimeStateV1PrefsKey)!,
    ) as Map<String, dynamic>;
    final intervention =
        persisted['directorState']['lastUserIntervention'] as Map;
    expect(intervention['text'], '我认为这里应该先区分定义和例子。');
    expect(intervention.containsKey('evidenceRefIds'), false);
  });

  test('executes user requested role turn after reader intervention', () async {
    configureProvider();
    final prompts = <String>[];
    final runtimeService = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        prompts.add(invocation.prompt);
        final isFollowUp = invocation.priorTurns.length >= 3;
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: isFollowUp
                ? 'turn-${invocation.role.asString}-follow-up'
                : 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: isFollowUp
                ? '${invocation.role.asString} follow-up response'
                : '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
            whiteboardEntries: [
              if (invocation.role == AiSeminarRole.synthesizer && !isFollowUp)
                const AiSeminarWhiteboardEntry(
                  id: 'open-question-1',
                  kind: AiSeminarWhiteboardKind.openQuestion,
                  text: 'Which interpretation should the reader test next?',
                  role: AiSeminarRole.synthesizer,
                  evidenceRefIds: ['e1'],
                ),
            ],
          ),
        );
      },
      now: () => 1000,
    );
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(runtimeService),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(aiSeminarRuntimeProvider.notifier);

    await notifier.start(
      AiSeminarSessionContract(id: 's-user-follow-up', question: 'Explain.'),
    );
    await notifier.recordUserIntervention(
      text: '请 critical 角色直接回应这个疑点。',
      requestedAction: AiSeminarUserInterventionAction.askRole,
      targetRole: AiSeminarRole.critical,
      now: 1234,
    );
    await notifier.executeDirectorNextStep();
    final state = container.read(aiSeminarRuntimeProvider);

    expect(state.status, AiSeminarRunStatus.completed);
    expect(state.turns.map((turn) => turn.id), [
      'turn-critical',
      'turn-supportive',
      'turn-synthesizer',
      'turn-critical-follow-up',
    ]);
    expect(state.turns.last.role, AiSeminarRole.critical);
    expect(state.turns.last.responseText, 'critical follow-up response');
    expect(state.turns.last.prompt, contains('请 critical 角色直接回应这个疑点。'));
    expect(
        prompts.last, contains('Reader intervention: 请 critical 角色直接回应这个疑点。'));
    expect(state.synthesis!.criticalView, 'critical follow-up response');
    expect(state.lastRun!.turns.map((turn) => turn.id),
        contains('turn-critical-follow-up'));
    expect(state.directorState!.lastUserIntervention!.isEvidence, false);
    expect(state.evidenceBundle!.evidence.map((item) => item.id), ['e1']);
  });

  test('rejects reader requested role disabled for the active session',
      () async {
    configureProvider();
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(aiSeminarRuntimeProvider.notifier);

    await notifier.start(
      AiSeminarSessionContract(
        id: 's-disabled-user-role',
        question: 'Explain.',
        roleProfiles: [
          AiSeminarRoleProfile(
            role: AiSeminarRole.critical,
            enabled: false,
          ),
        ],
      ),
    );

    await expectLater(
      notifier.recordUserIntervention(
        text: '请 critical 角色继续回应。',
        requestedAction: AiSeminarUserInterventionAction.askRole,
        targetRole: AiSeminarRole.critical,
        now: 1234,
      ),
      throwsA(isA<StateError>()),
    );
    final state = container.read(aiSeminarRuntimeProvider);
    expect(state.session!.roles, isNot(contains(AiSeminarRole.critical)));
    expect(state.error, contains('not enabled'));
    expect(state.directorState?.lastUserIntervention, isNull);
  });

  test('executes reader requested synthesize without rerunning roles',
      () async {
    configureProvider();
    var fetchCount = 0;
    var roleCount = 0;
    final runtimeService = AiSeminarRuntimeService(
      fetchEvidence: (_) async {
        fetchCount += 1;
        return bundle();
      },
      streamRole: (invocation, _) async* {
        roleCount += 1;
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
                  id: 'open-question-1',
                  kind: AiSeminarWhiteboardKind.openQuestion,
                  text: 'Should the reader ask for more evidence?',
                  role: AiSeminarRole.synthesizer,
                  evidenceRefIds: ['e1'],
                ),
            ],
          ),
        );
      },
      now: () => 1000,
    );
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(runtimeService),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(aiSeminarRuntimeProvider.notifier);

    await notifier.start(
      AiSeminarSessionContract(id: 's-synthesize', question: 'Explain.'),
    );
    expect(fetchCount, 1);
    expect(roleCount, 3);
    await notifier.recordUserIntervention(
      text: '这些观点够了，请先整理阶段结论。',
      requestedAction: AiSeminarUserInterventionAction.synthesize,
      now: 1234,
    );
    await notifier.executeDirectorNextStep();
    final state = container.read(aiSeminarRuntimeProvider);

    expect(fetchCount, 1);
    expect(roleCount, 3);
    expect(state.status, AiSeminarRunStatus.completed);
    expect(state.turns.map((turn) => turn.id), [
      'turn-critical',
      'turn-supportive',
      'turn-synthesizer',
    ]);
    expect(state.synthesis!.summary, 'synthesizer response');
    expect(state.lastRun!.synthesis!.summary, 'synthesizer response');
    expect(state.directorState!.nextIntent, AiSeminarDirectorNextIntent.end);
    expect(
      state.directorState!.lastUserIntervention!.requestedAction,
      AiSeminarUserInterventionAction.synthesize,
    );
    expect(state.directorState!.lastUserIntervention!.isEvidence, false);
    expect(
      state.directorState!.lastUserIntervention!.toJson().containsKey(
            'evidenceRefIds',
          ),
      false,
    );
  });

  test('executes reader requested evidence refresh before rerunning roles',
      () async {
    configureProvider();
    var fetchCount = 0;
    final runtimeService = AiSeminarRuntimeService(
      fetchEvidence: (_) async {
        fetchCount += 1;
        return AiSeminarEvidenceBundle(
          query: 'What is the claim?',
          evidence: [
            AiSeminarEvidence(
              id: fetchCount == 1 ? 'e1' : 'e2',
              scope: AiSeminarEvidenceScope.currentBook,
              text: fetchCount == 1
                  ? 'The first source passage.'
                  : 'The refreshed source passage.',
              sourceRef: traceableRef(),
            ),
          ],
        );
      },
      streamRole: (invocation, _) async* {
        final evidenceId = invocation.evidenceBundle.evidence.single.id;
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}-$evidenceId',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText:
                '${invocation.role.asString} response using $evidenceId',
            evidenceRefIds: [evidenceId],
          ),
        );
      },
      now: () => 1000,
    );
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(runtimeService),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(aiSeminarRuntimeProvider.notifier);

    await notifier.start(
      AiSeminarSessionContract(id: 's-refresh-evidence', question: 'Explain.'),
    );
    await notifier.recordUserIntervention(
      text: '请重新找更直接的证据。',
      requestedAction: AiSeminarUserInterventionAction.refreshEvidence,
      now: 1234,
    );
    await notifier.executeDirectorNextStep();
    final state = container.read(aiSeminarRuntimeProvider);

    expect(fetchCount, 2);
    expect(state.status, AiSeminarRunStatus.completed);
    expect(state.evidenceBundle!.evidence.map((item) => item.id), ['e2']);
    expect(state.turns.map((turn) => turn.id), [
      'turn-critical-e2',
      'turn-supportive-e2',
      'turn-synthesizer-e2',
    ]);
    expect(state.synthesis!.summary, 'synthesizer response using e2');
    expect(state.directorState!.evidenceRefreshCount, 1);
    expect(
      state.directorState!.lastUserIntervention!.requestedAction,
      AiSeminarUserInterventionAction.refreshEvidence,
    );
    expect(state.directorState!.lastUserIntervention!.isEvidence, false);
    expect(
      state.directorState!.lastUserIntervention!.toJson().containsKey(
            'evidenceRefIds',
          ),
      false,
    );
  });

  test('start tracks a persisted background job through completion', () async {
    configureProvider();
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(aiSeminarRuntimeProvider.notifier).start(
          AiSeminarSessionContract(
            id: 's-background',
            question: 'Run in background.',
          ),
        );
    final state = container.read(aiSeminarRuntimeProvider);
    final job = state.backgroundJob!;

    expect(job.sessionId, 's-background');
    expect(job.id, contains('s-background'));
    expect(job.status, AiSeminarBackgroundJobStatus.completed);
    expect(job.completedAt, isNotNull);

    final persisted = jsonDecode(
      Prefs().prefs.getString(aiSeminarRuntimeStateV1PrefsKey)!,
    ) as Map<String, dynamic>;
    expect(persisted['backgroundJob']['id'], job.id);
    expect(
      persisted['backgroundJob']['status'],
      AiSeminarBackgroundJobStatus.completed.asString,
    );
  });

  test('records multiple seminar background jobs in a local ledger', () async {
    configureProvider();
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(aiSeminarRuntimeProvider.notifier).start(
          AiSeminarSessionContract(id: 's-ledger-1', question: 'First run.'),
        );
    await container.read(aiSeminarRuntimeProvider.notifier).start(
          AiSeminarSessionContract(id: 's-ledger-2', question: 'Second run.'),
        );

    final state = container.read(aiSeminarRuntimeProvider);
    expect(state.backgroundJob!.sessionId, 's-ledger-2');
    expect(state.backgroundJobs.map((job) => job.sessionId), [
      's-ledger-1',
      's-ledger-2',
    ]);
    expect(
      state.backgroundJobs.map((job) => job.status).toSet(),
      {AiSeminarBackgroundJobStatus.completed},
    );

    final persisted = jsonDecode(
      Prefs().prefs.getString(aiSeminarRuntimeStateV1PrefsKey)!,
    ) as Map<String, dynamic>;
    final persistedJobs = (persisted['backgroundJobs'] as List).cast<Map>();
    expect(
      persistedJobs.map((job) => job['sessionId']),
      ['s-ledger-1', 's-ledger-2'],
    );
  });

  test('needs-evidence terminal run marks background job needs-evidence',
      () async {
    configureProvider();
    final untraceableService = AiSeminarRuntimeService(
      fetchEvidence: (_) async => AiSeminarEvidenceBundle(
        query: 'Needs evidence?',
        evidence: [
          AiSeminarEvidence(
            id: 'e1',
            scope: AiSeminarEvidenceScope.currentBook,
            text: 'Untraceable source.',
            sourceRef: SourceRef(sourceKind: SourceRefKind.currentBookRag),
          ),
        ],
      ),
      streamRole: (_, __) async* {
        fail('roles should not run without traceable evidence');
      },
      now: () => 1000,
    );
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(untraceableService),
      ],
    );
    addTearDown(container.dispose);

    await container.read(aiSeminarRuntimeProvider.notifier).start(
          AiSeminarSessionContract(
            id: 's-needs-evidence',
            question: 'Needs evidence?',
          ),
        );

    final state = container.read(aiSeminarRuntimeProvider);
    expect(state.status, AiSeminarRunStatus.needsEvidence);
    expect(
      state.backgroundJob!.status,
      AiSeminarBackgroundJobStatus.needsEvidence,
    );
    expect(state.backgroundJob!.completedAt, isNotNull);
    expect(state.synthesis, isNull);
    expect(state.canSendToReview, false);
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
    expect(
      state.backgroundJob!.status,
      AiSeminarBackgroundJobStatus.cancelled,
    );
  });

  test('cancelBackgroundJob only cancels the active job id', () async {
    configureProvider();
    final activeRoleStarted = Completer<void>();
    final releaseActiveRole = Completer<void>();
    final customService = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, token) async* {
        if (invocation.session.id == 's-active-job-cancel') {
          if (!activeRoleStarted.isCompleted) activeRoleStarted.complete();
          token.onCancel(() {
            if (!releaseActiveRole.isCompleted) releaseActiveRole.complete();
          });
          await releaseActiveRole.future;
          return;
        }
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
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(customService),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(aiSeminarRuntimeProvider.notifier);

    await notifier.start(
      AiSeminarSessionContract(id: 's-old-job', question: 'Old run.'),
    );
    final oldJobId = container.read(aiSeminarRuntimeProvider).backgroundJob!.id;
    final startFuture = notifier.start(
      AiSeminarSessionContract(
        id: 's-active-job-cancel',
        question: 'Active run.',
      ),
    );
    await activeRoleStarted.future;
    final activeJobId =
        container.read(aiSeminarRuntimeProvider).backgroundJob!.id;

    notifier.cancelBackgroundJob(oldJobId);
    expect(container.read(aiSeminarRuntimeProvider).status,
        AiSeminarRunStatus.running);
    expect(releaseActiveRole.isCompleted, false);

    notifier.cancelBackgroundJob(activeJobId);
    await startFuture;
    final state = container.read(aiSeminarRuntimeProvider);

    expect(state.status, AiSeminarRunStatus.cancelled);
    expect(state.backgroundJob!.id, activeJobId);
    expect(
      state.backgroundJob!.status,
      AiSeminarBackgroundJobStatus.cancelled,
    );
    expect(
      state.backgroundJobs.map((job) => job.status),
      [
        AiSeminarBackgroundJobStatus.completed,
        AiSeminarBackgroundJobStatus.cancelled,
      ],
    );
  });

  test('starting a new seminar queues behind the active job', () async {
    configureProvider();
    final previousRoleStarted = Completer<void>();
    final previousRoleReleased = Completer<void>();
    final secondRunCompleted = Completer<void>();
    final customService = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, token) async* {
        if (invocation.session.id == 's-replaced-job') {
          if (!previousRoleStarted.isCompleted) previousRoleStarted.complete();
          token.onCancel(() {
            if (!previousRoleReleased.isCompleted) {
              previousRoleReleased.complete();
            }
          });
          await previousRoleReleased.future;
        }
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
          ),
        );
        if (invocation.session.id == 's-newer-job' &&
            invocation.role == AiSeminarRole.synthesizer &&
            !secondRunCompleted.isCompleted) {
          secondRunCompleted.complete();
        }
      },
      now: () => 1000,
    );
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(customService),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(aiSeminarRuntimeProvider.notifier);

    final firstRun = notifier.start(
      AiSeminarSessionContract(id: 's-replaced-job', question: 'Replace me.'),
    );
    await previousRoleStarted.future;
    final replacedJobId =
        container.read(aiSeminarRuntimeProvider).backgroundJob!.id;

    await notifier.start(
      AiSeminarSessionContract(id: 's-newer-job', question: 'New run.'),
    );
    final queuedState = container.read(aiSeminarRuntimeProvider);

    expect(previousRoleReleased.isCompleted, false);
    expect(queuedState.status, AiSeminarRunStatus.running);
    expect(queuedState.backgroundJob!.id, replacedJobId);
    expect(
      queuedState.backgroundJobs.map((job) => job.sessionId),
      ['s-replaced-job', 's-newer-job'],
    );
    expect(
      queuedState.backgroundJobs
          .firstWhere((job) => job.sessionId == 's-newer-job')
          .status,
      AiSeminarBackgroundJobStatus.queued,
    );

    previousRoleReleased.complete();
    await firstRun;
    await secondRunCompleted.future;
    final state = container.read(aiSeminarRuntimeProvider);

    expect(previousRoleReleased.isCompleted, true);
    expect(state.status, AiSeminarRunStatus.completed);
    expect(state.backgroundJob!.sessionId, 's-newer-job');
    expect(
      state.backgroundJobs.firstWhere((job) => job.id == replacedJobId).status,
      AiSeminarBackgroundJobStatus.completed,
    );
    expect(
      state.backgroundJobs.map((job) => job.sessionId),
      ['s-replaced-job', 's-newer-job'],
    );
    expect(
      state.backgroundJobs.map((job) => job.status),
      [
        AiSeminarBackgroundJobStatus.completed,
        AiSeminarBackgroundJobStatus.completed,
      ],
    );
  });

  test('queued seminar start rebinds billing context to the current provider',
      () async {
    configureProvider();
    final firstRoleStarted = Completer<void>();
    final releaseFirstRole = Completer<void>();
    final queuedCompleted = Completer<void>();
    final queuedProviderIds = <String?>[];
    final customService = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        if (invocation.session.id == 's-provider-switch-active' &&
            invocation.role == AiSeminarRole.critical) {
          if (!firstRoleStarted.isCompleted) firstRoleStarted.complete();
          await releaseFirstRole.future;
        }
        if (invocation.session.id == 's-provider-switch-queued') {
          queuedProviderIds.add(invocation.session.billingContext?.providerId);
        }
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.session.id}-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText:
                '${invocation.session.id} ${invocation.role.asString}',
            evidenceRefIds: const ['e1'],
          ),
        );
        if (invocation.session.id == 's-provider-switch-queued' &&
            invocation.role == AiSeminarRole.synthesizer &&
            !queuedCompleted.isCompleted) {
          queuedCompleted.complete();
        }
      },
      now: () => 1000,
    );
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(customService),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(aiSeminarRuntimeProvider.notifier);

    final firstRun = notifier.start(
      AiSeminarSessionContract(
        id: 's-provider-switch-active',
        question: 'Active on the old provider.',
      ),
    );
    await firstRoleStarted.future;

    await notifier.start(
      AiSeminarSessionContract(
        id: 's-provider-switch-queued',
        question: 'Queued before provider switch.',
      ),
    );
    Prefs().aiProvidersV1 = const [
      AiProviderMeta(
        id: 'local-gateway',
        name: 'Local Gateway',
        type: AiProviderType.openaiCompatible,
        enabled: true,
        isBuiltIn: false,
        createdAt: 1000,
        updatedAt: 1000,
      ),
      AiProviderMeta(
        id: 'second-gateway',
        name: 'Second Gateway',
        type: AiProviderType.openaiCompatible,
        enabled: true,
        isBuiltIn: false,
        createdAt: 1001,
        updatedAt: 1001,
      ),
    ];
    Prefs().selectedAiService = 'second-gateway';
    Prefs().saveAiConfig('second-gateway', const {
      'model': 'gpt-6',
      'url': 'http://localhost:3004/v1/',
    });
    Prefs().saveAiModelCapabilitiesCacheV1(
      'second-gateway',
      [
        AiModelCapability(
          id: 'gpt-6',
          contextWindow: 128000,
          maxOutputTokens: 8192,
          supportsTools: true,
          supportsImages: true,
          supportsThinking: true,
          inputCostPerMillionTokens: 3,
          outputCostPerMillionTokens: 9,
          pricingSource: 'second-pricing-v1',
        ),
      ],
    );

    releaseFirstRole.complete();
    await firstRun;
    await queuedCompleted.future.timeout(const Duration(seconds: 2));
    final state = container.read(aiSeminarRuntimeProvider);

    expect(queuedProviderIds, isNotEmpty);
    expect(queuedProviderIds.toSet(), {'second-gateway'});
    expect(state.session!.billingContext!.providerId, 'second-gateway');
    expect(state.session!.billingContext!.modelId, 'gpt-6');
  });

  test('stale completed generation does not start queued seminar after restore',
      () async {
    configureProvider();
    final firstRoleStarted = Completer<void>();
    final releaseFirstRole = Completer<void>();
    var queuedRoleStarted = false;
    final customService = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, _) async* {
        if (invocation.session.id == 's-stale-complete' &&
            invocation.role == AiSeminarRole.critical) {
          if (!firstRoleStarted.isCompleted) firstRoleStarted.complete();
          await releaseFirstRole.future;
        }
        if (invocation.session.id == 's-queued-after-stale-restore') {
          queuedRoleStarted = true;
        }
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.session.id}-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
          ),
        );
      },
      now: () => 1000,
    );
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(customService),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(aiSeminarRuntimeProvider.notifier);
    var restoredCompletedGeneration = false;
    final subscription = container.listen<AiSeminarRuntimeState>(
      aiSeminarRuntimeProvider,
      (previous, next) {
        if (restoredCompletedGeneration) return;
        if (next.status == AiSeminarRunStatus.completed &&
            next.backgroundJob?.sessionId == 's-stale-complete') {
          restoredCompletedGeneration = true;
          notifier.restore(next);
        }
      },
    );
    addTearDown(subscription.close);

    final firstRun = notifier.start(
      AiSeminarSessionContract(
        id: 's-stale-complete',
        question: 'First run.',
      ),
    );
    await firstRoleStarted.future;

    await notifier.start(
      AiSeminarSessionContract(
        id: 's-queued-after-stale-restore',
        question: 'Queued run.',
      ),
    );
    releaseFirstRole.complete();
    await firstRun;
    await Future<void>.delayed(Duration.zero);
    final state = container.read(aiSeminarRuntimeProvider);

    expect(restoredCompletedGeneration, true);
    expect(queuedRoleStarted, false);
    expect(state.backgroundJob!.sessionId, 's-stale-complete');
    expect(
      state.backgroundJobs
          .firstWhere((job) => job.sessionId == 's-queued-after-stale-restore')
          .status,
      AiSeminarBackgroundJobStatus.queued,
    );
  });

  test('queued seminar starts after automatic evidence refresh settles',
      () async {
    configureProvider();
    var firstFetchCount = 0;
    final refreshedRoleStarted = Completer<void>();
    final releaseRefreshedRole = Completer<void>();
    final queuedCompleted = Completer<void>();
    final customService = AiSeminarRuntimeService(
      fetchEvidence: (session) async {
        if (session.id == 's-queued-after-auto-refresh') {
          return AiSeminarEvidenceBundle(
            query: session.question,
            evidence: [
              AiSeminarEvidence(
                id: 'e3',
                scope: AiSeminarEvidenceScope.currentBook,
                text: 'The queued source passage.',
                sourceRef: traceableRef(),
              ),
            ],
          );
        }
        firstFetchCount += 1;
        final evidenceId = firstFetchCount == 1 ? 'e1' : 'e2';
        return AiSeminarEvidenceBundle(
          query: session.question,
          evidence: [
            AiSeminarEvidence(
              id: evidenceId,
              scope: AiSeminarEvidenceScope.currentBook,
              text: firstFetchCount == 1
                  ? 'The first source passage.'
                  : 'The refreshed source passage.',
              sourceRef: traceableRef(),
            ),
          ],
        );
      },
      streamRole: (invocation, _) async* {
        final sessionId = invocation.session.id;
        final evidenceId = invocation.evidenceBundle.evidence.single.id;
        if (sessionId == 's-auto-refresh-with-queue' &&
            evidenceId == 'e2' &&
            invocation.role == AiSeminarRole.critical) {
          if (!refreshedRoleStarted.isCompleted) {
            refreshedRoleStarted.complete();
          }
          await releaseRefreshedRole.future;
        }
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-$sessionId-${invocation.role.asString}-$evidenceId',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText:
                '${invocation.role.asString} response using $evidenceId',
            evidenceRefIds: [evidenceId],
            whiteboardEntries: [
              if (sessionId == 's-auto-refresh-with-queue' &&
                  evidenceId == 'e1' &&
                  invocation.role == AiSeminarRole.critical)
                const AiSeminarWhiteboardEntry(
                  id: 'disagreement-1',
                  kind: AiSeminarWhiteboardKind.disagreement,
                  text: 'The supportive reading misses a contradiction.',
                  role: AiSeminarRole.critical,
                  evidenceRefIds: ['e1'],
                ),
            ],
          ),
        );
        if (sessionId == 's-queued-after-auto-refresh' &&
            invocation.role == AiSeminarRole.synthesizer &&
            !queuedCompleted.isCompleted) {
          queuedCompleted.complete();
        }
      },
      now: () => 1000,
    );
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(customService),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(aiSeminarRuntimeProvider.notifier);

    final firstRun = notifier.start(
      AiSeminarSessionContract(
        id: 's-auto-refresh-with-queue',
        question: 'First run.',
        maxRounds: 2,
      ),
    );
    await refreshedRoleStarted.future;

    await notifier.start(
      AiSeminarSessionContract(
        id: 's-queued-after-auto-refresh',
        question: 'Queued run.',
      ),
    );
    final queuedState = container.read(aiSeminarRuntimeProvider);
    expect(queuedState.status, AiSeminarRunStatus.running);
    expect(
      queuedState.backgroundJobs
          .firstWhere((job) => job.sessionId == 's-queued-after-auto-refresh')
          .status,
      AiSeminarBackgroundJobStatus.queued,
    );

    releaseRefreshedRole.complete();
    await firstRun;
    await queuedCompleted.future;
    final state = container.read(aiSeminarRuntimeProvider);

    expect(firstFetchCount, 2);
    expect(state.status, AiSeminarRunStatus.completed);
    expect(state.session!.id, 's-queued-after-auto-refresh');
    expect(state.directorState!.evidenceRefreshCount, 0);
    expect(
      state.backgroundJobs.map((job) => job.status),
      [
        AiSeminarBackgroundJobStatus.completed,
        AiSeminarBackgroundJobStatus.completed,
        AiSeminarBackgroundJobStatus.completed,
      ],
    );
    expect(
      state.backgroundJobs.map((job) => job.sessionId),
      [
        's-auto-refresh-with-queue',
        's-auto-refresh-with-queue',
        's-queued-after-auto-refresh',
      ],
    );
  });

  test('cancelBackgroundJob cancels queued jobs without cancelling active run',
      () async {
    configureProvider();
    final activeRoleStarted = Completer<void>();
    final releaseActiveRole = Completer<void>();
    final customService = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (invocation, token) async* {
        if (invocation.session.id == 's-active-queue-cancel') {
          if (!activeRoleStarted.isCompleted) activeRoleStarted.complete();
          token.onCancel(() {
            if (!releaseActiveRole.isCompleted) releaseActiveRole.complete();
          });
          await releaseActiveRole.future;
        }
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
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(customService),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(aiSeminarRuntimeProvider.notifier);

    final activeRun = notifier.start(
      AiSeminarSessionContract(
        id: 's-active-queue-cancel',
        question: 'Active run.',
      ),
    );
    await activeRoleStarted.future;

    await notifier.start(
      AiSeminarSessionContract(
        id: 's-queued-cancel',
        question: 'Queued run.',
      ),
    );
    final queuedJobId = container
        .read(aiSeminarRuntimeProvider)
        .backgroundJobs
        .firstWhere((job) => job.sessionId == 's-queued-cancel')
        .id;

    notifier.cancelBackgroundJob(queuedJobId);
    final queuedCancelled = container.read(aiSeminarRuntimeProvider);

    expect(queuedCancelled.status, AiSeminarRunStatus.running);
    expect(releaseActiveRole.isCompleted, false);
    expect(
      queuedCancelled.backgroundJobs
          .firstWhere((job) => job.id == queuedJobId)
          .status,
      AiSeminarBackgroundJobStatus.cancelled,
    );

    releaseActiveRole.complete();
    await activeRun;
    final state = container.read(aiSeminarRuntimeProvider);

    expect(state.status, AiSeminarRunStatus.completed);
    expect(state.backgroundJob!.sessionId, 's-active-queue-cancel');
    expect(
      state.backgroundJobs.map((job) => job.sessionId),
      ['s-active-queue-cancel', 's-queued-cancel'],
    );
    expect(
      state.backgroundJobs.firstWhere((job) => job.id == queuedJobId).status,
      AiSeminarBackgroundJobStatus.cancelled,
    );
  });

  test('queued seminar jobs restore as interrupted snapshots', () async {
    configureProvider();
    final runningState = AiSeminarRuntimeState.initial().copyWith(
      session: AiSeminarSessionContract(
        id: 's-active-before-restore',
        question: 'Active before restore?',
      ),
      status: AiSeminarRunStatus.running,
      backgroundJob: const AiSeminarBackgroundJobSnapshot(
        id: 'job-active-before-restore',
        sessionId: 's-active-before-restore',
        status: AiSeminarBackgroundJobStatus.running,
        startedAt: 100,
        updatedAt: 100,
      ),
      backgroundJobs: [
        const AiSeminarBackgroundJobSnapshot(
          id: 'job-active-before-restore',
          sessionId: 's-active-before-restore',
          status: AiSeminarBackgroundJobStatus.running,
          startedAt: 100,
          updatedAt: 100,
        ),
        AiSeminarBackgroundJobSnapshot(
          id: 'job-queued-before-restore',
          sessionId: 's-queued-before-restore',
          status: AiSeminarBackgroundJobStatus.queued,
          startedAt: 101,
          updatedAt: 101,
          session: AiSeminarSessionContract(
            id: 's-queued-before-restore',
            question: 'Queued before restore?',
          ),
        ),
      ],
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
    expect(
      restored.backgroundJobs.map((job) => job.status),
      [
        AiSeminarBackgroundJobStatus.interrupted,
        AiSeminarBackgroundJobStatus.interrupted,
      ],
    );
    expect(restored.backgroundJobs.last.sessionId, 's-queued-before-restore');
    expect(restored.canSendToReview, false);
  });

  test('terminal restored state interrupts queued seminar snapshots', () async {
    configureProvider();
    final completedState = AiSeminarRuntimeState.initial().copyWith(
      session: AiSeminarSessionContract(
        id: 's-completed-before-restore',
        question: 'Completed before restore?',
      ),
      status: AiSeminarRunStatus.completed,
      backgroundJob: const AiSeminarBackgroundJobSnapshot(
        id: 'job-completed-before-restore',
        sessionId: 's-completed-before-restore',
        status: AiSeminarBackgroundJobStatus.completed,
        startedAt: 100,
        updatedAt: 110,
        completedAt: 110,
      ),
      backgroundJobs: [
        const AiSeminarBackgroundJobSnapshot(
          id: 'job-completed-before-restore',
          sessionId: 's-completed-before-restore',
          status: AiSeminarBackgroundJobStatus.completed,
          startedAt: 100,
          updatedAt: 110,
          completedAt: 110,
        ),
        AiSeminarBackgroundJobSnapshot(
          id: 'job-queued-after-completed',
          sessionId: 's-queued-after-completed',
          status: AiSeminarBackgroundJobStatus.queued,
          startedAt: 111,
          updatedAt: 111,
          session: AiSeminarSessionContract(
            id: 's-queued-after-completed',
            question: 'Queued after completed?',
          ),
        ),
      ],
      evidenceBundle: bundle(),
      turns: const [],
    );
    await Prefs().prefs.setString(
          aiSeminarRuntimeStateV1PrefsKey,
          jsonEncode(completedState.toJson()),
        );

    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
      ],
    );
    addTearDown(container.dispose);
    final restored = container.read(aiSeminarRuntimeProvider);

    expect(restored.status, AiSeminarRunStatus.completed);
    expect(
        restored.backgroundJob!.status, AiSeminarBackgroundJobStatus.completed);
    expect(
      restored.backgroundJobs.map((job) => job.status),
      [
        AiSeminarBackgroundJobStatus.completed,
        AiSeminarBackgroundJobStatus.interrupted,
      ],
    );

    await Future<void>.delayed(Duration.zero);
    final persisted = jsonDecode(
      Prefs().prefs.getString(aiSeminarRuntimeStateV1PrefsKey)!,
    ) as Map<String, dynamic>;
    final persistedJobs = (persisted['backgroundJobs'] as List).cast<Map>();
    expect(persistedJobs.last['status'],
        AiSeminarBackgroundJobStatus.interrupted.asString);
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
    final failedState = container.read(aiSeminarRuntimeProvider);
    expect(failedState.status, AiSeminarRunStatus.failed);
    expect(
      failedState.backgroundJob!.status,
      AiSeminarBackgroundJobStatus.failed,
    );
    final failedJobId = failedState.backgroundJob!.id;

    await notifier.retry();
    final state = container.read(aiSeminarRuntimeProvider);

    expect(state.status, AiSeminarRunStatus.completed);
    expect(state.backgroundJob!.id, isNot(failedJobId));
    expect(state.backgroundJob!.status, AiSeminarBackgroundJobStatus.completed);
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
      directorState: const AiSeminarDirectorState(
        sessionId: 's3',
        turnCount: 1,
        completedRoles: [AiSeminarRole.critical],
        completedRoleTurnIds: ['turn-critical'],
        evidenceLedger: ['e1'],
        whiteboardLedger: ['w-disagreement'],
        disagreementIds: ['w-disagreement'],
        evidenceRefreshCount: 1,
        nextIntent: AiSeminarDirectorNextIntent.refreshEvidence,
        lastUserIntervention: AiSeminarUserIntervention(
          id: 'u1',
          text: '请重新找证据。',
          requestedAction: AiSeminarUserInterventionAction.refreshEvidence,
          createdAt: 1234,
        ),
      ),
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
    expect(restored.directorState!.sessionId, 's3');
    expect(restored.directorState!.completedRoles, [AiSeminarRole.critical]);
    expect(restored.directorState!.evidenceLedger, ['e1']);
    expect(
      restored.directorState!.nextIntent,
      AiSeminarDirectorNextIntent.refreshEvidence,
    );
    expect(restored.directorState!.lastUserIntervention!.isEvidence, false);
    expect(restored.lastRun!.tokenUsage!.totalTokens, 16);
  });

  test('malformed director state does not discard runtime recovery cache',
      () async {
    configureProvider();
    final cachedState = AiSeminarRuntimeState.initial().copyWith(
      session: AiSeminarSessionContract(
        id: 's-malformed-director',
        question: 'Recover around malformed director state?',
      ),
      status: AiSeminarRunStatus.completed,
      evidenceBundle: bundle(),
      directorState: const AiSeminarDirectorState(
        sessionId: 's-malformed-director',
        completedRoles: [AiSeminarRole.critical],
        completedRoleTurnIds: ['turn-critical'],
        evidenceLedger: ['e1'],
        whiteboardLedger: ['w1'],
        disagreementIds: ['w1'],
      ),
    );
    final raw = cachedState.toJson();
    raw['directorState'] = {
      ...(raw['directorState'] as Map<String, dynamic>),
      'completedRoles': 'critical',
      'completedRoleTurnIds': {'turn': 'critical'},
      'evidenceLedger': true,
      'whiteboardLedger': 42,
      'disagreementIds': {'id': 'w1'},
    };
    await Prefs().prefs.setString(
          aiSeminarRuntimeStateV1PrefsKey,
          jsonEncode(raw),
        );

    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
      ],
    );
    addTearDown(container.dispose);
    final restored = container.read(aiSeminarRuntimeProvider);

    expect(restored.session!.id, 's-malformed-director');
    expect(restored.status, AiSeminarRunStatus.completed);
    expect(restored.evidenceBundle!.evidence.single.id, 'e1');
    expect(restored.directorState!.completedRoles, isEmpty);
    expect(restored.directorState!.completedRoleTurnIds, isEmpty);
    expect(restored.directorState!.evidenceLedger, isEmpty);
    expect(restored.directorState!.whiteboardLedger, isEmpty);
    expect(restored.directorState!.disagreementIds, isEmpty);
    expect(
      Prefs().prefs.getString(aiSeminarRuntimeStateV1PrefsKey),
      isNotNull,
    );
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

  test('running seminar runtime state resumes from persisted checkpoint',
      () async {
    configureProvider();
    final invokedRoles = <AiSeminarRole>[];
    final resumeCompleted = Completer<void>();
    final runningState = AiSeminarRuntimeState.initial().copyWith(
      session: AiSeminarSessionContract(
        id: 's-running-resume',
        question: 'Resume?',
        billingContext: AiSeminarBillingContext(
          providerId: 'local-gateway',
          providerName: 'Local Gateway',
          providerType: 'openai-compatible',
          modelId: 'gpt-5.5',
        ),
      ),
      status: AiSeminarRunStatus.running,
      backgroundJob: const AiSeminarBackgroundJobSnapshot(
        id: 'job-running-resume',
        sessionId: 's-running-resume',
        status: AiSeminarBackgroundJobStatus.running,
        startedAt: 900,
        updatedAt: 901,
      ),
      backgroundJobs: const [
        AiSeminarBackgroundJobSnapshot(
          id: 'job-running-resume',
          sessionId: 's-running-resume',
          status: AiSeminarBackgroundJobStatus.running,
          startedAt: 900,
          updatedAt: 901,
        ),
      ],
      evidenceBundle: bundle(),
      activeRole: AiSeminarRole.supportive,
      partialRoleText: 'partial text should be ignored',
      turns: const [
        AiSeminarRoleTurn(
          id: 'turn-critical',
          role: AiSeminarRole.critical,
          prompt: 'critical prompt',
          responseText: 'critical response',
          evidenceRefIds: ['e1'],
          tokenUsage: AiSeminarTokenUsage(
            inputTokens: 10,
            outputTokens: 4,
            isEstimated: true,
            estimationMethod: 'local-char-estimate-v1',
          ),
        ),
      ],
    );
    await Prefs().prefs.setString(
          aiSeminarRuntimeStateV1PrefsKey,
          jsonEncode(runningState.toJson()),
        );
    final resumeService = AiSeminarRuntimeService(
      fetchEvidence: (_) async {
        fail('restored resume should use persisted evidence');
      },
      streamRole: (invocation, _) async* {
        invokedRoles.add(invocation.role);
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
          ),
        );
        if (invocation.role == AiSeminarRole.synthesizer &&
            !resumeCompleted.isCompleted) {
          resumeCompleted.complete();
        }
      },
      now: () => 1000,
    );

    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(resumeService),
      ],
    );
    addTearDown(container.dispose);
    container.read(aiSeminarRuntimeProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(invokedRoles, isEmpty);
    final resumeFuture = container
        .read(aiSeminarRuntimeProvider.notifier)
        .resumeRestoredRunning();
    await resumeCompleted.future.timeout(const Duration(seconds: 2));
    await resumeFuture;
    for (var i = 0; i < 20; i += 1) {
      if (container.read(aiSeminarRuntimeProvider).status !=
          AiSeminarRunStatus.running) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final restored = container.read(aiSeminarRuntimeProvider);

    expect(invokedRoles, [
      AiSeminarRole.supportive,
      AiSeminarRole.synthesizer,
    ]);
    expect(restored.status, AiSeminarRunStatus.completed);
    expect(restored.backgroundJob!.id, 'job-running-resume');
    expect(
      restored.backgroundJob!.status,
      AiSeminarBackgroundJobStatus.completed,
    );
    expect(restored.activeRole, isNull);
    expect(restored.partialRoleText, isNull);
    expect(restored.turns.map((turn) => turn.role), [
      AiSeminarRole.critical,
      AiSeminarRole.supportive,
      AiSeminarRole.synthesizer,
    ]);
  });

  test('restored running seminar keeps queued job and starts it after resume',
      () async {
    configureProvider();
    final invokedSessions = <String>[];
    final activeResumeStarted = Completer<void>();
    final releaseActiveResume = Completer<void>();
    final queuedCompleted = Completer<void>();
    final activeSession = AiSeminarSessionContract(
      id: 's-restored-active',
      question: 'Resume the active discussion?',
      billingContext: AiSeminarBillingContext(
        providerId: 'local-gateway',
        providerName: 'Local Gateway',
        providerType: 'openai-compatible',
        modelId: 'gpt-5.5',
      ),
    );
    final queuedSession = AiSeminarSessionContract(
      id: 's-restored-queued',
      question: 'Continue the queued discussion?',
    );
    final runningState = AiSeminarRuntimeState.initial().copyWith(
      session: activeSession,
      status: AiSeminarRunStatus.running,
      backgroundJob: const AiSeminarBackgroundJobSnapshot(
        id: 'job-restored-active',
        sessionId: 's-restored-active',
        status: AiSeminarBackgroundJobStatus.running,
        startedAt: 900,
        updatedAt: 901,
      ),
      backgroundJobs: [
        const AiSeminarBackgroundJobSnapshot(
          id: 'job-restored-active',
          sessionId: 's-restored-active',
          status: AiSeminarBackgroundJobStatus.running,
          startedAt: 900,
          updatedAt: 901,
        ),
        AiSeminarBackgroundJobSnapshot(
          id: 'job-restored-queued',
          sessionId: 's-restored-queued',
          status: AiSeminarBackgroundJobStatus.queued,
          startedAt: 902,
          updatedAt: 902,
          message: 'AI Seminar queued behind the active run.',
          session: queuedSession,
        ),
      ],
      evidenceBundle: bundle(),
      turns: const [
        AiSeminarRoleTurn(
          id: 'turn-critical',
          role: AiSeminarRole.critical,
          prompt: 'critical prompt',
          responseText: 'critical response',
          evidenceRefIds: ['e1'],
          tokenUsage: AiSeminarTokenUsage(
            inputTokens: 10,
            outputTokens: 4,
            isEstimated: true,
            estimationMethod: 'local-char-estimate-v1',
          ),
        ),
      ],
    );
    await Prefs().prefs.setString(
          aiSeminarRuntimeStateV1PrefsKey,
          jsonEncode(runningState.toJson()),
        );
    final resumeService = AiSeminarRuntimeService(
      fetchEvidence: (session) async {
        if (session.id == 's-restored-active') {
          fail('restored resume should use persisted evidence');
        }
        return bundle();
      },
      streamRole: (invocation, _) async* {
        invokedSessions.add(invocation.session.id);
        if (invocation.session.id == 's-restored-active' &&
            invocation.role == AiSeminarRole.supportive) {
          if (!activeResumeStarted.isCompleted) {
            activeResumeStarted.complete();
          }
          await releaseActiveResume.future;
        }
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.session.id}-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText:
                '${invocation.session.id} ${invocation.role.asString}',
            evidenceRefIds: const ['e1'],
          ),
        );
        if (invocation.session.id == 's-restored-queued' &&
            invocation.role == AiSeminarRole.synthesizer &&
            !queuedCompleted.isCompleted) {
          queuedCompleted.complete();
        }
      },
      now: () => 1000,
    );

    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(resumeService),
      ],
    );
    addTearDown(container.dispose);
    container.read(aiSeminarRuntimeProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(invokedSessions, isEmpty);

    expect(
      container
          .read(aiSeminarRuntimeProvider)
          .backgroundJobs
          .firstWhere((job) => job.sessionId == 's-restored-queued')
          .status,
      AiSeminarBackgroundJobStatus.queued,
    );

    final resumeFuture = container
        .read(aiSeminarRuntimeProvider.notifier)
        .resumeRestoredRunning();
    await activeResumeStarted.future.timeout(const Duration(seconds: 2));
    releaseActiveResume.complete();
    await queuedCompleted.future.timeout(const Duration(seconds: 2));
    await resumeFuture;
    for (var i = 0; i < 20; i += 1) {
      if (container.read(aiSeminarRuntimeProvider).status !=
          AiSeminarRunStatus.running) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final restored = container.read(aiSeminarRuntimeProvider);

    expect(invokedSessions, [
      's-restored-active',
      's-restored-active',
      's-restored-queued',
      's-restored-queued',
      's-restored-queued',
    ]);
    expect(restored.status, AiSeminarRunStatus.completed);
    expect(restored.backgroundJob!.sessionId, 's-restored-queued');
    expect(restored.restoredFromLocalCache, isFalse);
    expect(
      restored.backgroundJobs.map((job) => job.status),
      [
        AiSeminarBackgroundJobStatus.completed,
        AiSeminarBackgroundJobStatus.completed,
      ],
    );
  });

  test('manual start after restored state clears recovery marker', () async {
    configureProvider();
    final restoredState = AiSeminarRuntimeState.initial().copyWith(
      session: AiSeminarSessionContract(
        id: 's-restored-completed',
        question: 'Restored completed state?',
      ),
      status: AiSeminarRunStatus.completed,
      evidenceBundle: bundle(),
      turns: const [
        AiSeminarRoleTurn(
          id: 'turn-critical',
          role: AiSeminarRole.critical,
          prompt: 'critical prompt',
          responseText: 'critical response',
          evidenceRefIds: ['e1'],
        ),
      ],
    );
    await Prefs().prefs.setString(
          aiSeminarRuntimeStateV1PrefsKey,
          jsonEncode(restoredState.toJson()),
        );
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(aiSeminarRuntimeProvider).restoredFromLocalCache,
        isTrue);

    await container.read(aiSeminarRuntimeProvider.notifier).start(
          AiSeminarSessionContract(
            id: 's-manual-after-restore',
            question: 'Start a fresh Seminar.',
          ),
        );
    final freshRun = container.read(aiSeminarRuntimeProvider);

    expect(freshRun.status, AiSeminarRunStatus.completed);
    expect(freshRun.session!.id, 's-manual-after-restore');
    expect(freshRun.restoredFromLocalCache, isFalse);
  });

  test('running user-directed role state resumes the requested follow-up',
      () async {
    configureProvider();
    final invokedRoles = <AiSeminarRole>[];
    final runningState = AiSeminarRuntimeState.initial().copyWith(
      session: AiSeminarSessionContract(
        id: 's-running-user-follow-up',
        question: 'Resume user follow-up?',
        billingContext: const AiSeminarBillingContext(
          providerId: 'local-gateway',
          providerName: 'Local Gateway',
          providerType: 'openai-compatible',
          modelId: 'gpt-5.5',
        ),
      ),
      status: AiSeminarRunStatus.running,
      backgroundJob: const AiSeminarBackgroundJobSnapshot(
        id: 'job-running-user-follow-up',
        sessionId: 's-running-user-follow-up',
        status: AiSeminarBackgroundJobStatus.running,
        startedAt: 900,
        updatedAt: 901,
      ),
      backgroundJobs: const [
        AiSeminarBackgroundJobSnapshot(
          id: 'job-running-user-follow-up',
          sessionId: 's-running-user-follow-up',
          status: AiSeminarBackgroundJobStatus.running,
          startedAt: 900,
          updatedAt: 901,
        ),
      ],
      evidenceBundle: bundle(),
      activeRole: AiSeminarRole.critical,
      partialRoleText: 'partial user-directed answer',
      turns: const [
        AiSeminarRoleTurn(
          id: 'turn-critical',
          role: AiSeminarRole.critical,
          prompt: 'critical prompt',
          responseText: 'critical response',
          evidenceRefIds: ['e1'],
        ),
        AiSeminarRoleTurn(
          id: 'turn-supportive',
          role: AiSeminarRole.supportive,
          prompt: 'supportive prompt',
          responseText: 'supportive response',
          evidenceRefIds: ['e1'],
        ),
        AiSeminarRoleTurn(
          id: 'turn-synthesizer',
          role: AiSeminarRole.synthesizer,
          prompt: 'synthesizer prompt',
          responseText: 'synthesizer response',
          evidenceRefIds: ['e1'],
        ),
      ],
      directorState: const AiSeminarDirectorState(
        sessionId: 's-running-user-follow-up',
        turnCount: 3,
        completedRoles: [
          AiSeminarRole.critical,
          AiSeminarRole.supportive,
          AiSeminarRole.synthesizer,
        ],
        completedRoleTurnIds: [
          'turn-critical',
          'turn-supportive',
          'turn-synthesizer',
        ],
        evidenceLedger: ['e1'],
        nextIntent: AiSeminarDirectorNextIntent.runRole,
        lastUserIntervention: AiSeminarUserIntervention(
          id: 'user-1234',
          text: '请 critical 继续回应我的疑问。',
          requestedAction: AiSeminarUserInterventionAction.askRole,
          targetRole: AiSeminarRole.critical,
          createdAt: 1234,
        ),
      ),
    );
    await Prefs().prefs.setString(
          aiSeminarRuntimeStateV1PrefsKey,
          jsonEncode(runningState.toJson()),
        );
    final resumeService = AiSeminarRuntimeService(
      fetchEvidence: (_) async {
        fail('restored user-directed resume should use persisted evidence');
      },
      streamRole: (invocation, _) async* {
        invokedRoles.add(invocation.role);
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}-follow-up',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} follow-up response',
            evidenceRefIds: const ['e1'],
          ),
        );
      },
      now: () => 1000,
    );

    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(resumeService),
      ],
    );
    addTearDown(container.dispose);
    container.read(aiSeminarRuntimeProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(invokedRoles, isEmpty);
    await container
        .read(aiSeminarRuntimeProvider.notifier)
        .resumeRestoredRunning();
    for (var i = 0; i < 20; i += 1) {
      if (container.read(aiSeminarRuntimeProvider).status !=
          AiSeminarRunStatus.running) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final restored = container.read(aiSeminarRuntimeProvider);

    expect(invokedRoles, [AiSeminarRole.critical]);
    expect(restored.status, AiSeminarRunStatus.completed);
    expect(restored.backgroundJob!.id, 'job-running-user-follow-up');
    expect(
      restored.backgroundJob!.status,
      AiSeminarBackgroundJobStatus.completed,
    );
    expect(restored.turns.last.id, 'turn-critical-follow-up');
    expect(restored.turns.last.prompt, contains('请 critical 继续回应我的疑问。'));
    expect(restored.partialRoleText, isNull);
    expect(restored.synthesis!.criticalView, 'critical follow-up response');
  });

  test('running refresh evidence checkpoint resumes the refreshed role queue',
      () async {
    configureProvider();
    final invokedRoles = <AiSeminarRole>[];
    final refreshedBundle = AiSeminarEvidenceBundle(
      query: 'What is the claim?',
      evidence: [
        AiSeminarEvidence(
          id: 'e2',
          scope: AiSeminarEvidenceScope.currentBook,
          text: 'The refreshed source passage.',
          sourceRef: traceableRef(),
        ),
      ],
    );
    final runningState = AiSeminarRuntimeState.initial().copyWith(
      session: AiSeminarSessionContract(
        id: 's-running-refresh-evidence',
        question: 'Resume refreshed evidence?',
        billingContext: const AiSeminarBillingContext(
          providerId: 'local-gateway',
          providerName: 'Local Gateway',
          providerType: 'openai-compatible',
          modelId: 'gpt-5.5',
        ),
      ),
      status: AiSeminarRunStatus.running,
      backgroundJob: const AiSeminarBackgroundJobSnapshot(
        id: 'job-running-refresh-evidence',
        sessionId: 's-running-refresh-evidence',
        status: AiSeminarBackgroundJobStatus.running,
        startedAt: 900,
        updatedAt: 901,
      ),
      backgroundJobs: const [
        AiSeminarBackgroundJobSnapshot(
          id: 'job-running-refresh-evidence',
          sessionId: 's-running-refresh-evidence',
          status: AiSeminarBackgroundJobStatus.running,
          startedAt: 900,
          updatedAt: 901,
        ),
      ],
      evidenceBundle: refreshedBundle,
      activeRole: AiSeminarRole.critical,
      partialRoleText: 'partial refreshed role should be ignored',
      directorState: const AiSeminarDirectorState(
        sessionId: 's-running-refresh-evidence',
        evidenceLedger: ['e1', 'e2'],
        evidenceRefreshCount: 1,
        nextIntent: AiSeminarDirectorNextIntent.runRole,
        lastUserIntervention: AiSeminarUserIntervention(
          id: 'user-1234',
          text: '请重新找更直接的证据。',
          requestedAction: AiSeminarUserInterventionAction.refreshEvidence,
          createdAt: 1234,
        ),
      ),
    );
    await Prefs().prefs.setString(
          aiSeminarRuntimeStateV1PrefsKey,
          jsonEncode(runningState.toJson()),
        );
    final resumeService = AiSeminarRuntimeService(
      fetchEvidence: (_) async {
        fail('refreshed checkpoint resume should use persisted evidence');
      },
      streamRole: (invocation, _) async* {
        invokedRoles.add(invocation.role);
        final evidenceId = invocation.evidenceBundle.evidence.single.id;
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}-$evidenceId',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText:
                '${invocation.role.asString} response using $evidenceId',
            evidenceRefIds: [evidenceId],
          ),
        );
      },
      now: () => 1000,
    );

    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(resumeService),
      ],
    );
    addTearDown(container.dispose);
    container.read(aiSeminarRuntimeProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(invokedRoles, isEmpty);
    await container
        .read(aiSeminarRuntimeProvider.notifier)
        .resumeRestoredRunning();
    for (var i = 0; i < 20; i += 1) {
      if (container.read(aiSeminarRuntimeProvider).status !=
          AiSeminarRunStatus.running) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final restored = container.read(aiSeminarRuntimeProvider);

    expect(invokedRoles, [
      AiSeminarRole.critical,
      AiSeminarRole.supportive,
      AiSeminarRole.synthesizer,
    ]);
    expect(restored.status, AiSeminarRunStatus.completed);
    expect(restored.evidenceBundle!.evidence.map((item) => item.id), ['e2']);
    expect(restored.directorState!.evidenceRefreshCount, 1);
    expect(
      restored.directorState!.lastUserIntervention!.requestedAction,
      AiSeminarUserInterventionAction.refreshEvidence,
    );
    expect(restored.turns.map((turn) => turn.id), [
      'turn-critical-e2',
      'turn-supportive-e2',
      'turn-synthesizer-e2',
    ]);
  });

  test('queued seminar does not inherit refreshed director state', () async {
    configureProvider();
    var refreshFetchCount = 0;
    var heldRefreshRole = false;
    final refreshRoleStarted = Completer<void>();
    final allowRefreshToFinish = Completer<void>();
    final invokedBySession = <String, List<AiSeminarRole>>{};
    AiSeminarEvidenceBundle evidenceFor(String id, String text) {
      return AiSeminarEvidenceBundle(
        query: 'What is the claim?',
        evidence: [
          AiSeminarEvidence(
            id: id,
            scope: AiSeminarEvidenceScope.currentBook,
            text: text,
            sourceRef: traceableRef(),
          ),
        ],
      );
    }

    final runtimeService = AiSeminarRuntimeService(
      fetchEvidence: (session) async {
        if (session.id == 's-queued-after-refresh') {
          return evidenceFor('e3', 'The queued source passage.');
        }
        refreshFetchCount += 1;
        return refreshFetchCount == 1
            ? evidenceFor('e1', 'The first source passage.')
            : evidenceFor('e2', 'The refreshed source passage.');
      },
      streamRole: (invocation, _) async* {
        final sessionId = invocation.session.id;
        final evidenceId = invocation.evidenceBundle.evidence.single.id;
        invokedBySession.putIfAbsent(sessionId, () => []).add(invocation.role);
        if (sessionId == 's-refresh-with-queue' &&
            evidenceId == 'e2' &&
            !heldRefreshRole) {
          heldRefreshRole = true;
          refreshRoleStarted.complete();
          await allowRefreshToFinish.future;
        }
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-$sessionId-${invocation.role.asString}-$evidenceId',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText:
                '${invocation.role.asString} response using $evidenceId',
            evidenceRefIds: [evidenceId],
          ),
        );
      },
      now: () => 1000,
    );
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(runtimeService),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(aiSeminarRuntimeProvider.notifier);

    await notifier.start(
      AiSeminarSessionContract(
        id: 's-refresh-with-queue',
        question: 'Explain.',
      ),
    );
    await notifier.recordUserIntervention(
      text: '请重新找更直接的证据。',
      requestedAction: AiSeminarUserInterventionAction.refreshEvidence,
      now: 1234,
    );
    final refreshFuture = notifier.executeDirectorNextStep();
    await refreshRoleStarted.future.timeout(const Duration(seconds: 2));
    await notifier.start(
      AiSeminarSessionContract(
        id: 's-queued-after-refresh',
        question: 'Queued question.',
      ),
    );
    allowRefreshToFinish.complete();
    await refreshFuture;
    final state = container.read(aiSeminarRuntimeProvider);

    expect(state.session!.id, 's-queued-after-refresh');
    expect(state.evidenceBundle!.evidence.map((item) => item.id), ['e3']);
    expect(state.turns.map((turn) => turn.id), [
      'turn-s-queued-after-refresh-critical-e3',
      'turn-s-queued-after-refresh-supportive-e3',
      'turn-s-queued-after-refresh-synthesizer-e3',
    ]);
    expect(state.directorState!.sessionId, 's-queued-after-refresh');
    expect(state.directorState!.evidenceRefreshCount, 0);
    expect(state.directorState!.lastUserIntervention, isNull);
    expect(invokedBySession['s-queued-after-refresh'], [
      AiSeminarRole.critical,
      AiSeminarRole.supportive,
      AiSeminarRole.synthesizer,
    ]);
  });

  test('invalid restored checkpoint falls back to interrupted without resume',
      () async {
    configureProvider();
    final runningState = AiSeminarRuntimeState.initial().copyWith(
      session: AiSeminarSessionContract(
        id: 's-invalid-running-resume',
        question: 'Resume?',
        billingContext: const AiSeminarBillingContext(
          providerId: 'local-gateway',
          providerName: 'Local Gateway',
          providerType: 'openai-compatible',
          modelId: 'gpt-5.5',
        ),
      ),
      status: AiSeminarRunStatus.running,
      backgroundJob: const AiSeminarBackgroundJobSnapshot(
        id: 'job-invalid-running-resume',
        sessionId: 's-invalid-running-resume',
        status: AiSeminarBackgroundJobStatus.running,
        startedAt: 900,
        updatedAt: 901,
      ),
      backgroundJobs: const [
        AiSeminarBackgroundJobSnapshot(
          id: 'job-invalid-running-resume',
          sessionId: 's-invalid-running-resume',
          status: AiSeminarBackgroundJobStatus.running,
          startedAt: 900,
          updatedAt: 901,
        ),
      ],
      evidenceBundle: bundle(),
      turns: const [
        AiSeminarRoleTurn(
          id: 'turn-supportive',
          role: AiSeminarRole.supportive,
          prompt: 'supportive prompt',
          responseText: 'supportive response',
          evidenceRefIds: ['e1'],
        ),
      ],
      directorState: const AiSeminarDirectorState(
        sessionId: 's-invalid-running-resume',
        turnCount: 5,
        completedRoles: [AiSeminarRole.critical, AiSeminarRole.supportive],
        completedRoleTurnIds: ['stale-turn'],
        evidenceLedger: ['stale-evidence'],
        whiteboardLedger: ['stale-whiteboard'],
      ),
    );
    await Prefs().prefs.setString(
          aiSeminarRuntimeStateV1PrefsKey,
          jsonEncode(runningState.toJson()),
        );
    var invoked = false;
    final resumeService = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (_, __) async* {
        invoked = true;
      },
    );

    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(resumeService),
      ],
    );
    addTearDown(container.dispose);
    final restored = container.read(aiSeminarRuntimeProvider);
    await Future<void>.delayed(Duration.zero);

    expect(invoked, false);
    expect(restored.status, AiSeminarRunStatus.cancelled);
    expect(restored.canRetry, true);
    expect(restored.turns, isEmpty);
    expect(restored.directorState, isNull);
    expect(restored.lastRun!.turns, isEmpty);
    expect(
      restored.backgroundJob!.status,
      AiSeminarBackgroundJobStatus.interrupted,
    );
  });

  test(
      'running seminar with evidence but no completed roles resumes from first role',
      () async {
    configureProvider();
    final invokedRoles = <AiSeminarRole>[];
    final resumeService = AiSeminarRuntimeService(
      fetchEvidence: (_) async {
        fail('restored evidence should be reused instead of refetched');
      },
      streamRole: (invocation, _) async* {
        invokedRoles.add(invocation.role);
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
    final runningState = AiSeminarRuntimeState.initial().copyWith(
      session: AiSeminarSessionContract(
        id: 's-running',
        question: 'Resume?',
        billingContext: const AiSeminarBillingContext(
          providerId: 'local-gateway',
          providerName: 'Local Gateway',
          providerType: 'openai-compatible',
          modelId: 'gpt-5.5',
        ),
      ),
      status: AiSeminarRunStatus.running,
      backgroundJob: const AiSeminarBackgroundJobSnapshot(
        id: 'job-s-running',
        sessionId: 's-running',
        status: AiSeminarBackgroundJobStatus.running,
        startedAt: 11111,
        updatedAt: 11111,
      ),
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
        aiSeminarRuntimeServiceProvider.overrideWithValue(resumeService),
      ],
    );
    addTearDown(container.dispose);
    container.read(aiSeminarRuntimeProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(invokedRoles, isEmpty);
    await container
        .read(aiSeminarRuntimeProvider.notifier)
        .resumeRestoredRunning();
    for (var i = 0; i < 20; i += 1) {
      if (container.read(aiSeminarRuntimeProvider).status !=
          AiSeminarRunStatus.running) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final restored = container.read(aiSeminarRuntimeProvider);

    expect(restored.status, AiSeminarRunStatus.completed);
    expect(restored.activeRole, isNull);
    expect(restored.partialRoleText, isNull);
    expect(restored.error, isNull);
    expect(invokedRoles, [
      AiSeminarRole.critical,
      AiSeminarRole.supportive,
      AiSeminarRole.synthesizer,
    ]);
    expect(restored.lastRun!.turns.map((turn) => turn.role), invokedRoles);
    expect(restored.backgroundJob!.id, 'job-s-running');
    expect(
      restored.backgroundJob!.status,
      AiSeminarBackgroundJobStatus.completed,
    );
    final persisted = jsonDecode(
      Prefs().prefs.getString(aiSeminarRuntimeStateV1PrefsKey)!,
    ) as Map<String, dynamic>;
    expect(persisted['status'], AiSeminarRunStatus.completed.asString);
    expect(persisted.containsKey('activeRole'), isFalse);
    expect(persisted.containsKey('partialRoleText'), isFalse);
  });

  test('checkpoint restore uses matching current billing context after resume',
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
          providerId: 'local-gateway',
          providerName: 'Local Gateway',
          providerType: 'openai-compatible',
          modelId: 'gpt-5.5',
          pricingSource: 'current-pricing-v1',
          pricingCapturedAt: 12345,
          inputCostPerMillionTokens: 2,
          outputCostPerMillionTokens: 8,
          cacheReadCostPerMillionTokens: 0.2,
          cacheWriteCostPerMillionTokens: 1,
        ),
      ),
      status: AiSeminarRunStatus.running,
      backgroundJob: const AiSeminarBackgroundJobSnapshot(
        id: 'job-s-running-billing',
        sessionId: 's-running-billing',
        status: AiSeminarBackgroundJobStatus.running,
        startedAt: 11111,
        updatedAt: 11111,
      ),
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
      directorState: const AiSeminarDirectorState(
        sessionId: 's-provider-changed',
        turnCount: 6,
        completedRoles: [AiSeminarRole.synthesizer],
        completedRoleTurnIds: ['stale-turn'],
        evidenceLedger: ['stale-evidence'],
        whiteboardLedger: ['stale-whiteboard'],
      ),
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
    container.read(aiSeminarRuntimeProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await container
        .read(aiSeminarRuntimeProvider.notifier)
        .resumeRestoredRunning();
    for (var i = 0; i < 20; i += 1) {
      if (container.read(aiSeminarRuntimeProvider).status !=
          AiSeminarRunStatus.running) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final restored = container.read(aiSeminarRuntimeProvider);
    final billing = restored.lastRun!.billingSnapshot!;

    expect(restored.status, AiSeminarRunStatus.completed);
    expect(restored.lastRun!.status, AiSeminarRunStatus.completed);
    expect(restored.backgroundJob!.id, 'job-s-running-billing');
    expect(
      restored.backgroundJob!.status,
      AiSeminarBackgroundJobStatus.completed,
    );
    expect(billing.providerId, 'local-gateway');
    expect(billing.modelId, 'gpt-5.5');
    expect(billing.pricingSource, 'current-pricing-v1');
    expect(billing.pricingCapturedAt, isNotNull);
    expect(billing.usageSnapshot.source, AiSeminarTokenUsage.sourceMixed);
    expect(billing.estimatedCostUsd, greaterThan(0.0036));
    expect(
      billing.invoiceStatus,
      AiSeminarInvoiceReconciliationStatus.notConnected,
    );
  });

  test('restored checkpoint interrupts when provider context changed',
      () async {
    configureProvider(withPricing: true);
    final runningState = AiSeminarRuntimeState.initial().copyWith(
      session: AiSeminarSessionContract(
        id: 's-provider-changed',
        question: 'Provider changed?',
        billingContext: AiSeminarBillingContext(
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
      backgroundJob: const AiSeminarBackgroundJobSnapshot(
        id: 'job-provider-changed',
        sessionId: 's-provider-changed',
        status: AiSeminarBackgroundJobStatus.running,
        startedAt: 11111,
        updatedAt: 11111,
      ),
      evidenceBundle: bundle(),
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
    var invoked = false;
    final resumeService = AiSeminarRuntimeService(
      fetchEvidence: (_) async => bundle(),
      streamRole: (_, __) async* {
        invoked = true;
      },
    );

    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(resumeService),
      ],
    );
    addTearDown(container.dispose);
    final restored = container.read(aiSeminarRuntimeProvider);
    await Future<void>.delayed(Duration.zero);

    expect(invoked, false);
    expect(restored.status, AiSeminarRunStatus.cancelled);
    expect(restored.canRetry, true);
    expect(restored.turns, isEmpty);
    expect(restored.directorState, isNull);
    expect(
      restored.backgroundJob!.status,
      AiSeminarBackgroundJobStatus.interrupted,
    );
  });

  test('background job snapshot round-trips and unknown status is interrupted',
      () {
    const job = AiSeminarBackgroundJobSnapshot(
      id: 'job-1',
      sessionId: 'session-1',
      status: AiSeminarBackgroundJobStatus.running,
      startedAt: 10,
      updatedAt: 20,
      message: 'working',
    );

    final restored = AiSeminarBackgroundJobSnapshot.fromJson(job.toJson());
    final unknown = AiSeminarBackgroundJobSnapshot.fromJson(
      const {
        'id': 'job-2',
        'sessionId': 'session-2',
        'status': 'provider-disappeared',
        'startedAt': 1,
        'updatedAt': 2,
      },
    );

    expect(restored.id, 'job-1');
    expect(restored.status, AiSeminarBackgroundJobStatus.running);
    expect(restored.message, 'working');
    expect(unknown.status, AiSeminarBackgroundJobStatus.interrupted);
  });

  test('interrupted restore does not fake completion or review readiness',
      () async {
    configureProvider();
    final runningState = AiSeminarRuntimeState.initial().copyWith(
      session: AiSeminarSessionContract(
        id: 's-partial-restore',
        question: 'Partial?',
      ),
      status: AiSeminarRunStatus.running,
      backgroundJob: const AiSeminarBackgroundJobSnapshot(
        id: 'job-partial-restore',
        sessionId: 's-partial-restore',
        status: AiSeminarBackgroundJobStatus.running,
        startedAt: 100,
        updatedAt: 100,
      ),
      evidenceBundle: bundle(),
      activeRole: AiSeminarRole.critical,
      partialRoleText: 'partial stream text that is not a completed turn',
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
    expect(restored.backgroundJob!.status,
        AiSeminarBackgroundJobStatus.interrupted);
    expect(restored.activeRole, isNull);
    expect(restored.partialRoleText, isNull);
    expect(restored.turns, isEmpty);
    expect(restored.synthesis, isNull);
    expect(restored.lastRun!.readyForReview, false);
    expect(restored.canSendToReview, false);
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
