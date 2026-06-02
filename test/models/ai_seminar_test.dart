import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/ai/ai_seminar_orchestration_service.dart';

void main() {
  group('AiSeminarSessionContract', () {
    test('uses the fixed default roles and keeps web disabled by default', () {
      final session = AiSeminarSessionContract(
        id: 's1',
        question: 'What is the argument?',
        bookId: 7,
      );

      expect(session.roles, AiSeminarRole.defaultRoles);
      expect(session.hasVerifier, false);
      expect(session.scopes, [AiSeminarEvidenceScope.currentBook]);
      expect(session.allowWeb, false);
      expect(session.writeRequiresApproval, true);
    });

    test('allows verifier but ignores unknown role wire values', () {
      final restored = AiSeminarSessionContract.fromJson(const {
        'id': 's2',
        'question': 'Verify this claim',
        'roles': ['verifier', 'invented-role'],
        'scopes': ['library', 'future-scope'],
        'allowWeb': true,
        'writeRequiresApproval': false,
        'maxRounds': 99,
      });

      expect(restored.roles, [
        AiSeminarRole.critical,
        AiSeminarRole.supportive,
        AiSeminarRole.synthesizer,
        AiSeminarRole.verifier,
      ]);
      expect(restored.scopes, [AiSeminarEvidenceScope.library]);
      expect(restored.allowWeb, true);
      expect(restored.writeRequiresApproval, false);
      expect(restored.maxRounds, 5);
    });

    test('round-trips local budget policy', () {
      final session = AiSeminarSessionContract(
        id: 's-budget',
        question: 'Keep this bounded.',
        budgetPolicy: const AiSeminarBudgetPolicy(
          maxRoleOutputTokens: 120,
          maxRunTokens: 500,
          maxRunCostUsd: 0.05,
          inputCostPerMillionTokens: 2,
          outputCostPerMillionTokens: 8,
          cacheReadCostPerMillionTokens: 0.2,
          cacheWriteCostPerMillionTokens: 1,
          costPriceSource: 'test-pricing-v1',
        ),
      );

      final restored = AiSeminarSessionContract.fromJson(session.toJson());

      expect(restored.budgetPolicy!.maxRoleOutputTokens, 120);
      expect(restored.budgetPolicy!.maxRunTokens, 500);
      expect(restored.budgetPolicy!.hasTokenLimits, true);
      expect(restored.budgetPolicy!.maxRunCostUsd, 0.05);
      expect(restored.budgetPolicy!.inputCostPerMillionTokens, 2);
      expect(restored.budgetPolicy!.outputCostPerMillionTokens, 8);
      expect(restored.budgetPolicy!.cacheReadCostPerMillionTokens, 0.2);
      expect(restored.budgetPolicy!.cacheWriteCostPerMillionTokens, 1);
      expect(restored.budgetPolicy!.costPriceSource, 'test-pricing-v1');
      expect(restored.budgetPolicy!.hasCostLimit, true);
    });

    test('round-trips role prompt profiles', () {
      final session = AiSeminarSessionContract(
        id: 's-role-profile',
        question: 'Who should challenge this claim?',
        roleProfiles: [
          AiSeminarRoleProfile(
            role: AiSeminarRole.critical,
            name: 'Evidence Challenger',
            customPrompt: 'Challenge causal claims and name missing evidence.',
          ),
        ],
      );

      final restored = AiSeminarSessionContract.fromJson(session.toJson());
      final profile = restored.roleProfileFor(AiSeminarRole.critical);

      expect(profile?.name, 'Evidence Challenger');
      expect(
        profile?.customPrompt,
        'Challenge causal claims and name missing evidence.',
      );
    });

    test('round-trips role governance and filters unsafe tool scope', () {
      final session = AiSeminarSessionContract(
        id: 's-role-governance',
        question: 'Who should challenge this claim?',
        roleProfiles: [
          AiSeminarRoleProfile(
            role: AiSeminarRole.supportive,
            enabled: false,
            evidenceScopes: const [
              AiSeminarEvidenceScope.currentBook,
              AiSeminarEvidenceScope.library,
              AiSeminarEvidenceScope.library,
            ],
            allowedToolIds: const [
              'semantic_search_current_book',
              'semantic_search_library',
              'create_note',
              'spawn_sub_agent',
              'unknown_tool',
              '',
            ],
          ),
          AiSeminarRoleProfile(
            role: AiSeminarRole.critical,
            customPrompt: 'Use this API key api key: placeholder-value',
          ),
        ],
      );

      final restored = AiSeminarSessionContract.fromJson(session.toJson());
      final supportive = restored.roleProfileFor(AiSeminarRole.supportive);
      final critical = restored.roleProfileFor(AiSeminarRole.critical);

      expect(restored.roles, [
        AiSeminarRole.critical,
        AiSeminarRole.synthesizer,
      ]);
      expect(supportive?.enabled, false);
      expect(supportive?.evidenceScopes, [
        AiSeminarEvidenceScope.currentBook,
        AiSeminarEvidenceScope.library,
      ]);
      expect(supportive?.allowedToolIds, [
        'semantic_search_current_book',
        'semantic_search_library',
      ]);
      expect(critical, isNull);
    });

    test('execution order does not re-add disabled session roles', () {
      final session = AiSeminarSessionContract(
        id: 's-role-disabled',
        question: 'Who should speak?',
        roleProfiles: [
          AiSeminarRoleProfile(
            role: AiSeminarRole.supportive,
            enabled: false,
          ),
        ],
      );

      expect(session.roles, [
        AiSeminarRole.critical,
        AiSeminarRole.synthesizer,
      ]);
      expect(
        AiSeminarOrchestrationService.executionOrder(session.roles),
        [
          AiSeminarRole.critical,
          AiSeminarRole.synthesizer,
        ],
      );
    });

    test('round-trips reader selection source refs', () {
      final sourceRef = SourceRef(
        bookId: 42,
        cfi: 'epubcfi(/6/4)',
        jumpLink: 'paperreader://reader/open?bookId=42&cfi=epubcfi%28/6/4%29',
        sourceTextSnippet: 'Evidence-backed learning needs jump links.',
        sourceKind: SourceRefKind.reader,
      );
      final session = AiSeminarSessionContract(
        id: 's-selection',
        question: 'Discuss this selected passage.',
        bookId: 42,
        sourceRefs: [sourceRef],
      );

      final restored = AiSeminarSessionContract.fromJson(session.toJson());

      expect(restored.sourceRefs, hasLength(1));
      expect(restored.sourceRefs.single.bookId, 42);
      expect(restored.sourceRefs.single.cfi, 'epubcfi(/6/4)');
      expect(restored.sourceRefs.single.sourceTextSnippet,
          'Evidence-backed learning needs jump links.');
      expect(restored.sourceRefs.single.sourceKind, SourceRefKind.reader);
      expect(restored.sourceRefs.single.canJumpBack, true);
    });
  });

  group('AiSeminarEvidenceBundle', () {
    test('requires each evidence item to carry a traceable SourceRef', () {
      final bundle = AiSeminarEvidenceBundle(
        query: 'claim',
        evidence: [
          AiSeminarEvidence(
            id: 'e1',
            scope: AiSeminarEvidenceScope.currentBook,
            text: 'source text',
            sourceRef: SourceRef(
              bookId: 1,
              href: 'Text/ch.xhtml',
              sourceTextSnippet: 'source text',
              sourceKind: SourceRefKind.currentBookRag,
            ),
          ),
        ],
      );

      expect(bundle.allEvidenceTraceable, true);
      final json = bundle.toJson();
      final evidence = (json['evidence'] as List).single as Map;
      expect(evidence['sourceRef'], isA<Map>());
      expect(
        (evidence['sourceRef'] as Map)['sourceTextSnippet'],
        'source text',
      );
    });

    test('detects evidence that cannot jump back or prove origin', () {
      final bundle = AiSeminarEvidenceBundle(
        query: 'claim',
        evidence: [
          AiSeminarEvidence(
            id: 'e1',
            scope: AiSeminarEvidenceScope.currentBook,
            text: 'untraceable',
            sourceRef: SourceRef(sourceKind: SourceRefKind.currentBookRag),
          ),
        ],
      );

      expect(bundle.allEvidenceTraceable, false);
    });
  });

  group('AiSeminarWhiteboardEntry', () {
    test('claims and candidate cards must trace evidence refs', () {
      const claim = AiSeminarWhiteboardEntry(
        id: 'w1',
        kind: AiSeminarWhiteboardKind.claim,
        text: 'The author assumes X.',
      );
      const card = AiSeminarWhiteboardEntry(
        id: 'w2',
        kind: AiSeminarWhiteboardKind.candidateCard,
        text: 'X as hidden premise',
        evidenceRefIds: ['e1'],
      );

      expect(claim.isTraceable, false);
      expect(card.isTraceable, true);
      expect(card.requiresReview, true);
    });

    test('candidate cards round-trip concept refs', () {
      const entry = AiSeminarWhiteboardEntry(
        id: 'w3',
        kind: AiSeminarWhiteboardKind.candidateCard,
        text: 'Hidden premise card',
        evidenceRefIds: ['e1'],
        conceptRefs: ['Hidden premise', 'Argument structure'],
      );

      final restored = AiSeminarWhiteboardEntry.fromJson(entry.toJson());

      expect(restored.conceptRefs, ['Hidden premise', 'Argument structure']);
      expect(restored.hasTraceableEvidence({'e1'}), true);
    });
  });

  group('AiSeminarTokenUsage', () {
    test('role turn and run round-trip local estimated token usage', () {
      const usage = AiSeminarTokenUsage(
        inputTokens: 12,
        outputTokens: 5,
        isEstimated: true,
        estimationMethod: 'local-char-estimate-v1',
      );
      const turn = AiSeminarRoleTurn(
        id: 'turn-critical',
        role: AiSeminarRole.critical,
        prompt: 'prompt',
        responseText: 'response',
        evidenceRefIds: ['e1'],
        tokenUsage: usage,
      );

      final restoredTurn = AiSeminarRoleTurn.fromJson(turn.toJson());

      expect(restoredTurn.tokenUsage!.inputTokens, 12);
      expect(restoredTurn.tokenUsage!.outputTokens, 5);
      expect(restoredTurn.tokenUsage!.totalTokens, 17);
      expect(
          restoredTurn.tokenUsage!.estimationMethod, 'local-char-estimate-v1');

      final run = AiSeminarRun(
        session: AiSeminarSessionContract(id: 's-usage', question: 'Usage?'),
        status: AiSeminarRunStatus.completed,
        evidenceBundle: const AiSeminarEvidenceBundle(
          query: 'Usage?',
          evidence: [],
        ),
        turns: const [turn],
        tokenUsage: usage,
      );
      final restoredRun = AiSeminarRun.fromJson(run.toJson());

      expect(restoredRun.tokenUsage!.totalTokens, 17);
      expect(restoredRun.turns.single.tokenUsage!.totalTokens, 17);
    });

    test('role turn and run round-trip provider-reported token usage', () {
      const providerUsage = AiSeminarTokenUsage(
        inputTokens: 20,
        outputTokens: 8,
        isEstimated: false,
        estimationMethod: 'provider-usage-tracker-v1',
        source: 'provider-reported',
        cacheReadTokens: 3,
        cacheWriteTokens: 2,
      );
      const turn = AiSeminarRoleTurn(
        id: 'turn-critical',
        role: AiSeminarRole.critical,
        prompt: 'prompt',
        responseText: 'response',
        evidenceRefIds: ['e1'],
        tokenUsage: providerUsage,
      );

      final restoredTurn = AiSeminarRoleTurn.fromJson(turn.toJson());

      expect(restoredTurn.tokenUsage!.source, 'provider-reported');
      expect(restoredTurn.tokenUsage!.inputTokens, 20);
      expect(restoredTurn.tokenUsage!.outputTokens, 8);
      expect(restoredTurn.tokenUsage!.cacheReadTokens, 3);
      expect(restoredTurn.tokenUsage!.cacheWriteTokens, 2);
      expect(restoredTurn.tokenUsage!.isEstimated, false);

      final run = AiSeminarRun(
        session: AiSeminarSessionContract(
          id: 's-provider-usage',
          question: 'Usage?',
        ),
        status: AiSeminarRunStatus.completed,
        evidenceBundle: const AiSeminarEvidenceBundle(
          query: 'Usage?',
          evidence: [],
        ),
        turns: const [turn],
        tokenUsage: providerUsage,
      );
      final restoredRun = AiSeminarRun.fromJson(run.toJson());

      expect(restoredRun.tokenUsage!.totalTokens, 28);
      expect(restoredRun.tokenUsage!.source, 'provider-reported');
      expect(
        restoredRun.turns.single.tokenUsage!.estimationMethod,
        'provider-usage-tracker-v1',
      );
    });

    test('aggregates mixed local and provider usage with neutral method', () {
      final usage = AiSeminarTokenUsage.aggregate(const [
        AiSeminarTokenUsage(
          inputTokens: 10,
          outputTokens: 5,
          isEstimated: false,
          estimationMethod: 'provider-usage-tracker-v1',
          source: 'provider-reported',
        ),
        AiSeminarTokenUsage(
          inputTokens: 4,
          outputTokens: 2,
          isEstimated: true,
          estimationMethod: 'local-char-estimate-v1',
          source: 'local-estimate',
        ),
      ]);

      expect(usage!.inputTokens, 14);
      expect(usage.outputTokens, 7);
      expect(usage.isEstimated, true);
      expect(usage.source, 'mixed');
      expect(usage.estimationMethod, 'mixed-token-usage');
    });
  });

  group('AiSeminarDirectorState', () {
    test('round-trips director ledger and user intervention', () {
      const state = AiSeminarDirectorState(
        sessionId: 's-director',
        turnCount: 2,
        completedRoles: [AiSeminarRole.critical],
        completedRoleTurnIds: ['turn-critical-1'],
        evidenceLedger: ['e1', 'e2'],
        whiteboardLedger: ['w-claim-1', 'w-disagreement-1'],
        disagreementIds: ['w-disagreement-1'],
        evidenceRefreshCount: 1,
        nextIntent: AiSeminarDirectorNextIntent.refreshEvidence,
        lastUserIntervention: AiSeminarUserIntervention(
          id: 'u1',
          text: '请让批判者重新查证据。',
          requestedAction: AiSeminarUserInterventionAction.refreshEvidence,
          targetRole: AiSeminarRole.critical,
          createdAt: 1234,
        ),
      );

      final restored = AiSeminarDirectorState.fromJson(state.toJson());

      expect(restored.sessionId, 's-director');
      expect(restored.turnCount, 2);
      expect(restored.completedRoles, [AiSeminarRole.critical]);
      expect(restored.completedRoleTurnIds, ['turn-critical-1']);
      expect(restored.evidenceLedger, ['e1', 'e2']);
      expect(restored.whiteboardLedger, ['w-claim-1', 'w-disagreement-1']);
      expect(restored.disagreementIds, ['w-disagreement-1']);
      expect(restored.evidenceRefreshCount, 1);
      expect(restored.nextIntent, AiSeminarDirectorNextIntent.refreshEvidence);
      expect(restored.lastUserIntervention!.targetRole, AiSeminarRole.critical);
      expect(restored.lastUserIntervention!.isEvidence, false);
      expect(
        restored.lastUserIntervention!.toJson().containsKey('evidenceRefIds'),
        false,
      );
    });

    test('skips completed roles when deciding what still needs a turn', () {
      const state = AiSeminarDirectorState(
        sessionId: 's-director',
        completedRoles: [AiSeminarRole.critical, AiSeminarRole.verifier],
        completedRoleTurnIds: ['turn-critical-1', 'turn-verifier-1'],
      );

      expect(
        state.remainingRolesFor(const [
          AiSeminarRole.critical,
          AiSeminarRole.supportive,
          AiSeminarRole.verifier,
          AiSeminarRole.synthesizer,
        ]),
        [AiSeminarRole.supportive, AiSeminarRole.synthesizer],
      );
    });

    test('normalizes unknown wire values and duplicate ledger entries', () {
      final restored = AiSeminarDirectorState.fromJson(const {
        'sessionId': ' s-director ',
        'turnCount': -3,
        'completedRoles': ['critical', 'invented-role', 'critical'],
        'completedRoleTurnIds': [' turn-critical-1 ', '', 'turn-critical-1'],
        'evidenceLedger': ['e1', 'e1', ''],
        'whiteboardLedger': ['w1', 'w1'],
        'disagreementIds': ['w-disagreement', 'w-disagreement'],
        'evidenceRefreshCount': -2,
        'nextIntent': 'invented-intent',
        'lastUserIntervention': {
          'id': ' u1 ',
          'text': '  请总结。 ',
          'requestedAction': 'invented-action',
          'targetRole': 'invented-role',
          'createdAt': 'not-a-number',
          'evidenceRefIds': ['should-not-survive'],
        },
      });

      expect(restored.sessionId, 's-director');
      expect(restored.turnCount, 0);
      expect(restored.completedRoles, [AiSeminarRole.critical]);
      expect(restored.completedRoleTurnIds, ['turn-critical-1']);
      expect(restored.evidenceLedger, ['e1']);
      expect(restored.whiteboardLedger, ['w1']);
      expect(restored.disagreementIds, ['w-disagreement']);
      expect(restored.evidenceRefreshCount, 0);
      expect(restored.nextIntent, AiSeminarDirectorNextIntent.runRole);
      expect(
        restored.lastUserIntervention!.requestedAction,
        AiSeminarUserInterventionAction.clarify,
      );
      expect(restored.lastUserIntervention!.targetRole, isNull);
      expect(restored.lastUserIntervention!.createdAt, isNull);
    });

    test('ignores malformed ledger list wire shapes', () {
      final restored = AiSeminarDirectorState.fromJson(const {
        'sessionId': 's-director',
        'completedRoles': 'critical',
        'completedRoleTurnIds': {'turn': 'critical'},
        'evidenceLedger': true,
        'whiteboardLedger': 42,
        'disagreementIds': {'id': 'w1'},
      });

      expect(restored.sessionId, 's-director');
      expect(restored.completedRoles, isEmpty);
      expect(restored.completedRoleTurnIds, isEmpty);
      expect(restored.evidenceLedger, isEmpty);
      expect(restored.whiteboardLedger, isEmpty);
      expect(restored.disagreementIds, isEmpty);
    });
  });

  group('AiSeminarBillingSnapshot', () {
    test('run round-trips pricing usage estimate and invoice status', () {
      const usage = AiSeminarTokenUsage(
        inputTokens: 1000,
        outputTokens: 250,
        isEstimated: false,
        estimationMethod: 'provider-usage-tracker-v1',
        source: AiSeminarTokenUsage.sourceProviderReported,
        cacheReadTokens: 100,
        apiCalls: 3,
      );
      const billing = AiSeminarBillingSnapshot(
        providerId: 'local-gateway',
        providerName: 'Local Gateway',
        modelId: 'gpt-5.5',
        usageSnapshot: usage,
        pricingSource: 'test-pricing-v1',
        pricingCapturedAt: 1234,
        estimatedCostUsd: 0.0042,
        invoiceStatus: AiSeminarInvoiceReconciliationStatus.failed,
        invoiceReason: 'Provider invoice API rejected the request.',
      );

      final run = AiSeminarRun(
        session: AiSeminarSessionContract(
          id: 's-billing',
          question: 'Billing?',
        ),
        status: AiSeminarRunStatus.completed,
        evidenceBundle: const AiSeminarEvidenceBundle(
          query: 'Billing?',
          evidence: [],
        ),
        tokenUsage: usage,
        estimatedCostUsd: 0.0042,
        costPriceSource: 'test-pricing-v1',
        billingSnapshot: billing,
      );

      final restored = AiSeminarRun.fromJson(run.toJson());

      expect(restored.billingSnapshot, isNotNull);
      expect(restored.billingSnapshot!.providerId, 'local-gateway');
      expect(restored.billingSnapshot!.modelId, 'gpt-5.5');
      expect(restored.billingSnapshot!.usageSnapshot.source,
          AiSeminarTokenUsage.sourceProviderReported);
      expect(restored.billingSnapshot!.pricingSource, 'test-pricing-v1');
      expect(restored.billingSnapshot!.estimatedCostUsd, 0.0042);
      expect(
        restored.billingSnapshot!.invoiceStatus,
        AiSeminarInvoiceReconciliationStatus.failed,
      );
      expect(
        restored.billingSnapshot!.invoiceReason,
        contains('invoice API'),
      );
    });
  });

  group('AiSeminarSynthesis', () {
    test('handoff is review-ready but not auto-applied to user assets', () {
      final synthesis = AiSeminarSynthesis(
        summary: 'A balanced answer.',
        supportiveView: 'The text supports the thesis.',
        criticalView: 'The evidence is incomplete.',
        candidateCards: const [
          AiSeminarWhiteboardEntry(
            id: 'card1',
            kind: AiSeminarWhiteboardKind.candidateCard,
            text: 'Candidate card',
            evidenceRefIds: ['e1'],
          ),
        ],
        candidateReviewQuestions: const [
          'What is the strongest counterexample?',
        ],
        evidenceRefIds: const ['e1'],
        evidence: [
          AiSeminarEvidence(
            id: 'e1',
            scope: AiSeminarEvidenceScope.currentBook,
            text: 'source text',
            sourceRef: SourceRef(
              bookId: 1,
              href: 'Text/ch.xhtml',
              sourceTextSnippet: 'source text',
              sourceKind: SourceRefKind.currentBookRag,
            ),
          ),
        ],
      );

      expect(synthesis.readyForReview, true);
      expect(synthesis.hasTraceableHandoff, true);
      final restored = AiSeminarSynthesis.fromJson(synthesis.toJson());
      expect(restored.candidateCards.single.requiresReview, true);
      expect(restored.candidateReviewQuestions, isNotEmpty);
    });

    test('handoff rejects missing or hash-only evidence references', () {
      final hashOnly = AiSeminarSynthesis(
        summary: 'Summary',
        supportiveView: 'Support',
        criticalView: 'Critique',
        candidateCards: const [
          AiSeminarWhiteboardEntry(
            id: 'card1',
            kind: AiSeminarWhiteboardKind.candidateCard,
            text: 'Candidate card',
            evidenceRefIds: ['e1'],
          ),
        ],
        evidenceRefIds: const ['e1'],
        evidence: [
          AiSeminarEvidence(
            id: 'e1',
            scope: AiSeminarEvidenceScope.currentBook,
            text: 'detached text',
            sourceRef: SourceRef(
              sourceTextSnippet: 'detached text',
              sourceKind: SourceRefKind.external,
            ),
          ),
        ],
      );
      final missing = AiSeminarSynthesis(
        summary: 'Summary',
        supportiveView: 'Support',
        criticalView: 'Critique',
        candidateCards: const [
          AiSeminarWhiteboardEntry(
            id: 'card1',
            kind: AiSeminarWhiteboardKind.candidateCard,
            text: 'Candidate card',
            evidenceRefIds: ['missing'],
          ),
        ],
        evidenceRefIds: const ['missing'],
        evidence: [
          AiSeminarEvidence(
            id: 'e1',
            scope: AiSeminarEvidenceScope.currentBook,
            text: 'source text',
            sourceRef: SourceRef(
              bookId: 1,
              href: 'Text/ch.xhtml',
              sourceTextSnippet: 'source text',
              sourceKind: SourceRefKind.currentBookRag,
            ),
          ),
        ],
      );

      expect(hashOnly.hasTraceableHandoff, false);
      expect(missing.hasTraceableHandoff, false);
    });
  });
}
