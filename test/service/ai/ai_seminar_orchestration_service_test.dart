import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/ai/ai_seminar_orchestration_service.dart';

void main() {
  SourceRef traceableRef() => SourceRef(
        bookId: 1,
        href: 'Text/ch.xhtml',
        sourceTextSnippet: 'The source passage.',
        sourceKind: SourceRefKind.currentBookRag,
      );

  AiSeminarEvidenceBundle bundle() => AiSeminarEvidenceBundle(
        query: 'What is the argument?',
        evidence: [
          AiSeminarEvidence(
            id: 'e1',
            scope: AiSeminarEvidenceScope.currentBook,
            text: 'The source passage.',
            sourceRef: traceableRef(),
          ),
        ],
      );

  test('runs default roles serially and returns a review-ready synthesis',
      () async {
    final order = <AiSeminarRole>[];
    final service = AiSeminarOrchestrationService(
      fetchEvidence: (_) async => bundle(),
      executeRole: (invocation) async {
        order.add(invocation.role);
        return AiSeminarRoleTurn(
          id: 'turn-${invocation.role.asString}',
          role: invocation.role,
          prompt: invocation.prompt,
          responseText: '${invocation.role.asString} response',
          evidenceRefIds: const ['e1'],
          whiteboardEntries: [
            if (invocation.role == AiSeminarRole.critical)
              const AiSeminarWhiteboardEntry(
                id: 'w-critical',
                kind: AiSeminarWhiteboardKind.disagreement,
                text: 'The claim needs a narrower scope.',
                role: AiSeminarRole.critical,
                evidenceRefIds: ['e1'],
              ),
            if (invocation.role == AiSeminarRole.synthesizer)
              const AiSeminarWhiteboardEntry(
                id: 'card-hidden-premise',
                kind: AiSeminarWhiteboardKind.candidateCard,
                text: 'Hidden premise: the author assumes X.',
                role: AiSeminarRole.synthesizer,
                evidenceRefIds: ['e1'],
              ),
            if (invocation.role == AiSeminarRole.synthesizer)
              const AiSeminarWhiteboardEntry(
                id: 'review-hidden-premise',
                kind: AiSeminarWhiteboardKind.reviewSuggestion,
                text: 'What premise should be reviewed later?',
                role: AiSeminarRole.synthesizer,
                evidenceRefIds: ['e1'],
              ),
          ],
        );
      },
    );

    final run = await service.run(
      AiSeminarSessionContract(
        id: 's1',
        question: 'What is the argument?',
        bookId: 1,
      ),
    );

    expect(order, [
      AiSeminarRole.critical,
      AiSeminarRole.supportive,
      AiSeminarRole.synthesizer,
    ]);
    expect(run.status, AiSeminarRunStatus.completed);
    expect(run.readyForReview, true);
    expect(run.synthesis!.summary, 'synthesizer response');
    expect(run.synthesis!.criticalView, 'critical response');
    expect(run.synthesis!.supportiveView, 'supportive response');
    expect(run.synthesis!.candidateCards.single.id, 'card-hidden-premise');
    expect(run.synthesis!.candidateReviewQuestions,
        ['What premise should be reviewed later?']);
    expect(run.synthesis!.evidence.single.sourceRef.hasEvidence, true);
  });

  test('keeps synthesizer last when verifier is enabled', () async {
    final order = <AiSeminarRole>[];
    final service = AiSeminarOrchestrationService(
      fetchEvidence: (_) async => bundle(),
      executeRole: (invocation) async {
        order.add(invocation.role);
        return AiSeminarRoleTurn(
          id: 'turn-${invocation.role.asString}',
          role: invocation.role,
          prompt: invocation.prompt,
          responseText: '${invocation.role.asString} response',
          evidenceRefIds: const ['e1'],
        );
      },
    );

    await service.run(
      AiSeminarSessionContract(
        id: 's2',
        question: 'Verify this.',
        roles: const [AiSeminarRole.verifier],
      ),
    );

    expect(order, [
      AiSeminarRole.critical,
      AiSeminarRole.supportive,
      AiSeminarRole.verifier,
      AiSeminarRole.synthesizer,
    ]);
  });

  test('does not execute roles when evidence cannot prove origin', () async {
    var executed = false;
    final service = AiSeminarOrchestrationService(
      fetchEvidence: (_) async => AiSeminarEvidenceBundle(
        query: 'claim',
        evidence: [
          AiSeminarEvidence(
            id: 'e1',
            scope: AiSeminarEvidenceScope.currentBook,
            text: 'Detached text.',
            sourceRef: SourceRef(
              sourceTextSnippet: 'Detached text.',
              sourceKind: SourceRefKind.external,
            ),
          ),
        ],
      ),
      executeRole: (_) async {
        executed = true;
        throw StateError('should not run');
      },
    );

    final run = await service.run(
      AiSeminarSessionContract(id: 's3', question: 'claim'),
    );

    expect(run.status, AiSeminarRunStatus.needsEvidence);
    expect(run.turns, isEmpty);
    expect(run.readyForReview, false);
    expect(executed, false);
  });

  test('stops before synthesis when roles omit evidence refs', () async {
    final service = AiSeminarOrchestrationService(
      fetchEvidence: (_) async => bundle(),
      executeRole: (invocation) async => AiSeminarRoleTurn(
        id: 'turn-${invocation.role.asString}',
        role: invocation.role,
        prompt: invocation.prompt,
        responseText: '${invocation.role.asString} response',
      ),
    );

    final run = await service.run(
      AiSeminarSessionContract(id: 's4', question: 'argument', bookId: 1),
    );

    expect(run.status, AiSeminarRunStatus.needsEvidence);
    expect(run.readyForReview, false);
    expect(run.turns, isEmpty);
    expect(run.synthesis, isNull);
  });

  test('fails before prior turns are polluted when executor returns wrong role',
      () async {
    final seenPriorTurns = <List<AiSeminarRoleTurn>>[];
    final service = AiSeminarOrchestrationService(
      fetchEvidence: (_) async => bundle(),
      executeRole: (invocation) async {
        seenPriorTurns.add(invocation.priorTurns);
        return AiSeminarRoleTurn(
          id: 'turn-wrong-role',
          role: AiSeminarRole.synthesizer,
          prompt: invocation.prompt,
          responseText: 'wrong role response',
          evidenceRefIds: const ['e1'],
        );
      },
    );

    final run = await service.run(
      AiSeminarSessionContract(id: 's5', question: 'argument', bookId: 1),
    );

    expect(run.status, AiSeminarRunStatus.failed);
    expect(run.turns, isEmpty);
    expect(run.message, contains('returned synthesizer for critical'));
    expect(seenPriorTurns, hasLength(1));
    expect(seenPriorTurns.single, isEmpty);
  });

  test('stops before later roles when a role turn cites missing evidence',
      () async {
    final invokedRoles = <AiSeminarRole>[];
    final service = AiSeminarOrchestrationService(
      fetchEvidence: (_) async => bundle(),
      executeRole: (invocation) async {
        invokedRoles.add(invocation.role);
        return AiSeminarRoleTurn(
          id: 'turn-${invocation.role.asString}',
          role: invocation.role,
          prompt: invocation.prompt,
          responseText: '${invocation.role.asString} response',
          evidenceRefIds: const ['missing-evidence'],
        );
      },
    );

    final run = await service.run(
      AiSeminarSessionContract(id: 's6', question: 'argument', bookId: 1),
    );

    expect(run.status, AiSeminarRunStatus.needsEvidence);
    expect(run.turns, isEmpty);
    expect(run.readyForReview, false);
    expect(run.message, contains('untraceable evidence'));
    expect(invokedRoles, [AiSeminarRole.critical]);
  });
}
