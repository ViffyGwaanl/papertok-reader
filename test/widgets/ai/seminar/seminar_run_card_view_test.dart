import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/providers/ai_seminar_runtime.dart';
import 'package:papertok_reader/widgets/ai/seminar/seminar_run_card_view.dart';

void main() {
  testWidgets('SeminarRunCardView shows follow-up hint for completed cards',
      (tester) async {
    await tester.pumpWidget(
      _Harness(
        child: SeminarRunCardView(
          card: _card(status: 'completed'),
          runtimeState: AiSeminarRuntimeState.initial(),
          bindings: _bindings(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Question'), findsOneWidget);
    expect(
      find.textContaining('ask follow-ups about its conclusions'),
      findsOneWidget,
    );
  });

  testWidgets('SeminarRunCardView shows estimated cost on completed run',
      (tester) async {
    final session = AiSeminarSessionContract(
      id: 'session-1',
      question: 'Question',
    );
    final run = AiSeminarRun(
      session: session,
      status: AiSeminarRunStatus.completed,
      evidenceBundle: const AiSeminarEvidenceBundle(
        query: 'q',
        evidence: [],
      ),
      estimatedCostUsd: 0.034,
    );
    final state = AiSeminarRuntimeState.initial().copyWith(
      status: AiSeminarRunStatus.completed,
      session: session,
      lastRun: run,
    );

    await tester.pumpWidget(
      _Harness(
        child: SeminarRunCardView(
          card: _card(status: 'completed'),
          runtimeState: state,
          bindings: _bindings(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('\$0.034'), findsOneWidget);
  });

  testWidgets('SeminarRunCardView wires ignored action restore callback',
      (tester) async {
    String? restoredSessionId;
    await tester.pumpWidget(
      _Harness(
        child: SeminarRunCardView(
          card: _card(),
          runtimeState: AiSeminarRuntimeState.initial(),
          bindings: _bindings(
            ignoredActionSessionIds: {'session-1'},
            restoreSeminarRunCardAssetActions: (sessionId) async {
              restoredSessionId = sessionId;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Suggestions ignored'), findsOneWidget);

    await tester.tap(find.text('Restore'));
    await tester.pump();

    expect(restoredSessionId, 'session-1');
  });
}

class _Harness extends StatelessWidget {
  const _Harness({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    );
  }
}

AiSeminarRunCardMeta _card({String status = 'draft'}) {
  return AiSeminarRunCardMeta(
    question: 'Question',
    sessionId: 'session-1',
    status: status,
    roleIds: const ['critical', 'supportive'],
    evidenceScopeIds: const ['current_book'],
    maxRounds: 2,
    createdAt: 1,
  );
}

SeminarRunCardBindings _bindings({
  Set<String> ignoredActionSessionIds = const <String>{},
  Future<void> Function(String? sessionId)? restoreSeminarRunCardAssetActions,
}) {
  Future<void> noop(String? sessionId) async {}
  return SeminarRunCardBindings(
    isChineseLocale: false,
    sentToReviewSessionIds: const <String>{},
    savedKnowledgeCardIds: const <String>{},
    spacedReviewFlashcardIds: const <String>{},
    conceptNodeIds: const <String>{},
    ignoredActionSessionIds: ignoredActionSessionIds,
    resumeDetailSessionIds: const <String>{},
    localizedSeminarCardText: ({required zh, required en}) => en,
    seminarSynthesisKnowledgeCardSourceRefs: (_) => const <SourceRef>[],
    seminarSynthesisKnowledgeCardId: (_) => null,
    seminarSynthesisReviewFlashcardId: (_) => null,
    seminarSynthesisConceptNodeId: (_) => null,
    shouldShowSeminarCardStartAction: (_, __) => false,
    seminarSnapshotHasOnlyRunSetup: (_) => false,
    shouldShowSeminarCardCancelAction: (_, __) => false,
    buildSeminarRunCardCancelActionView: (_) => const SizedBox.shrink(),
    buildSeminarAgentControlActionView: (
      _, {
      required actionId,
      required sessionId,
    }) =>
        const SizedBox.shrink(),
    seminarStatusLabel: (status, _) => status,
    seminarRoleCountLabel: (count) => '$count roles',
    seminarEvidenceScopeSummary: (_, __) => 'Evidence',
    seminarSourceCountLabel: (count) => '$count sources',
    buildSeminarRunCardSetupView: (_) => const SizedBox.shrink(),
    buildSeminarRunSnapshot: (
      _,
      __,
      ___, {
      required bookId,
      required evidenceScopeIds,
    }) =>
        const SizedBox.shrink(),
    buildSeminarRunCardStartActionView: (_) => const SizedBox.shrink(),
    buildSeminarRunCardResumeBannerView: (
      _,
      __, {
      required showDetails,
      required onOpen,
      required onContinue,
    }) =>
        const SizedBox.shrink(),
    continueSeminarRunCardFromCheckpoint: noop,
    sendActiveSeminarRunCardToReview: noop,
    saveActiveSeminarRunCardKnowledgeCard: noop,
    editActiveSeminarRunCardKnowledgeCard: noop,
    undoActiveSeminarRunCardKnowledgeCard: noop,
    addActiveSeminarRunCardSpacedReview: noop,
    undoActiveSeminarRunCardSpacedReview: noop,
    addActiveSeminarRunCardConceptGraph: noop,
    undoActiveSeminarRunCardConceptGraph: noop,
    ignoreSeminarRunCardAssetActions: noop,
    restoreSeminarRunCardAssetActions:
        restoreSeminarRunCardAssetActions ?? noop,
    onToggleRecoveryDetails: (_, __) {},
  );
}
