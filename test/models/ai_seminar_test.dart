import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/source_ref.dart';

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
        ),
      );

      final restored = AiSeminarSessionContract.fromJson(session.toJson());

      expect(restored.budgetPolicy!.maxRoleOutputTokens, 120);
      expect(restored.budgetPolicy!.maxRunTokens, 500);
      expect(restored.budgetPolicy!.hasTokenLimits, true);
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
