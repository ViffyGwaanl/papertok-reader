import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/providers/ai_seminar_runtime.dart';
import 'package:papertok_reader/widgets/ai/seminar/setup/seminar_run_card_resume_widgets.dart';
import 'package:papertok_reader/widgets/ai/seminar/setup/seminar_run_card_setup_widgets.dart';

void main() {
  test('Seminar setup copy describes runs instead of cards or panels', () {
    final source = [
      File('lib/widgets/ai/seminar/setup/seminar_run_setup_sheet.dart')
          .readAsStringSync(),
      File('lib/widgets/ai/seminar/setup/seminar_run_card_setup_widgets.dart')
          .readAsStringSync(),
    ].join('\n');

    expect(source, isNot(contains('即将插入的研讨卡')));
    expect(source, isNot(contains('next Seminar card')));
    expect(source, isNot(contains('panel can continue')));
    expect(source, isNot(contains('只影响这张研讨卡')));
    expect(source, isNot(contains('Only this Seminar card changes')));
    expect(source, contains('即将开始的研讨'));
    expect(source, contains('next Seminar run'));
    expect(source, contains('只影响本次研讨'));
    expect(source, contains('Only this Seminar run changes'));
  });

  testWidgets('SeminarRunCardSetup renders fields and wires callbacks',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final questionController = TextEditingController(text: 'Initial question');
    final promptController = TextEditingController(text: 'Prompt');
    addTearDown(questionController.dispose);
    addTearDown(promptController.dispose);
    var toggledSetup = 0;
    var question = '';
    var toggledRole = AiSeminarRole.synthesizer;
    var prompt = '';
    AiSeminarEvidenceScope? toggledScope;
    String? toggledTool;
    var rounds = 0;
    final card = AiSeminarRunCardMeta(
      question: 'Initial question',
      sessionId: 'session-1',
      roleIds: const ['critical'],
      maxRounds: 2,
      roleProfiles: [
        AiSeminarRoleProfile(
          role: AiSeminarRole.critical,
          customPrompt: 'Prompt',
          evidenceScopes: const [AiSeminarEvidenceScope.currentBook],
          allowedToolIds: const ['semantic_search_current_book'],
        ),
      ],
      createdAt: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SeminarRunCardSetup(
              card: card,
              zh: false,
              isExpanded: true,
              evidenceSummary: 'Evidence: Current book',
              toolSummary: '1 tools',
              roleSummary: 'Roles: Critical',
              roles: seminarCardSetupRoles(card),
              evidenceScopeOptions: const [
                AiSeminarEvidenceScope.currentBook,
                AiSeminarEvidenceScope.library,
              ],
              toolIds: const ['semantic_search_current_book', 'notes_search'],
              roleLabelBuilder: _roleLabel,
              evidenceScopeLabelBuilder: (scope) => 'Scope ${scope.asString}',
              toolLabelBuilder: (toolId) => 'Tool $toolId',
              questionController: questionController,
              rolePromptControllerBuilder: (_) => promptController,
              roleEvidenceScopesBuilder: (_) =>
                  {AiSeminarEvidenceScope.currentBook},
              roleAllowedToolIdsBuilder: (_) =>
                  {'semantic_search_current_book'},
              onToggleExpanded: () => toggledSetup += 1,
              onQuestionChanged: (value) => question = value,
              onToggleRole: (role) => toggledRole = role,
              onRolePromptChanged: (_, value) => prompt = value,
              onToggleRoleEvidenceScope: (_, scope) => toggledScope = scope,
              onToggleRoleTool: (_, toolId) => toggledTool = toolId,
              onMaxRoundsChanged: (value) => rounds = value,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Run setup'), findsOneWidget);
    expect(
      find.text('Roles: Critical · Evidence: Current book · 1 tools'),
      findsOneWidget,
    );
    expect(find.text('Seminar question'), findsOneWidget);
    expect(find.text('Critical'), findsOneWidget);
    expect(find.text('Run read-only tools'), findsOneWidget);

    await tester.tap(find.text('Hide setup'));
    await tester.enterText(
      find.byKey(const ValueKey('seminar-chat-card-question-input-session-1')),
      'Updated question',
    );
    await tester.enterText(
      find.byKey(
        const ValueKey('seminar-chat-card-role-critical-prompt-session-1'),
      ),
      'Updated prompt',
    );
    await tester.tap(
      find.byKey(
        const ValueKey(
          'seminar-chat-card-role-critical-scope-library-session-1',
        ),
      ),
    );
    await tester.tap(
      find.byKey(
        const ValueKey(
          'seminar-chat-card-role-critical-tool-notes_search-session-1',
        ),
      ),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('seminar-chat-card-rounds-plus-session-1')),
    );
    await tester.tap(
      find.byKey(const ValueKey('seminar-chat-card-rounds-plus-session-1')),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('seminar-chat-card-role-critical-session-1')),
    );
    await tester.tap(
      find.byKey(const ValueKey('seminar-chat-card-role-critical-session-1')),
    );
    await tester.pump();

    expect(toggledSetup, 1);
    expect(question, 'Updated question');
    expect(prompt, 'Updated prompt');
    expect(toggledScope, AiSeminarEvidenceScope.library);
    expect(toggledTool, 'notes_search');
    expect(rounds, 3);
    expect(toggledRole, AiSeminarRole.critical);
  });

  testWidgets('Seminar card controls render executable actions',
      (tester) async {
    var started = 0;
    var cancelled = 0;
    var action = '';
    final controls = seminarRunCardHeaderControls(
      sessionId: 'session-1',
      snapshot: const AiSeminarRunCardSnapshot(
        messageParts: [
          AiSeminarRunCardMessagePart(
            type: 'agent_status',
            agentRunId: 'agent-1',
            label: 'role-waiting-input',
            actionIds: ['send-input', 'resume-agent'],
          ),
        ],
      ),
      canCancelFromCard: true,
      zh: false,
      cancelActionBuilder: () => SeminarRunCardCancelAction(
        sessionId: 'session-1',
        zh: false,
        onCancel: () => cancelled += 1,
      ),
      actionWidgetBuilder: (_, actionId) => TextButton(
        onPressed: () => action = actionId,
        child: Text('Action $actionId'),
      ),
    );

    expect(controls, hasLength(2));
    expect(
      seminarRunCardHeaderControls(
        sessionId: '',
        snapshot: null,
        canCancelFromCard: true,
        zh: false,
        cancelActionBuilder: () => const SizedBox.shrink(),
        actionWidgetBuilder: (_, __) => const SizedBox.shrink(),
      ),
      isEmpty,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SeminarRunCardStartAction(
                sessionId: 'session-1',
                isSubmitting: false,
                zh: false,
                onStart: () => started += 1,
              ),
              ...controls,
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Start Seminar'));
    await tester.tap(find.text('Cancel seminar'));
    await tester.tap(find.text('Action send-input'));
    await tester.pump();

    expect(started, 1);
    expect(cancelled, 1);
    expect(action, 'send-input');
    expect(find.text('Action resume-agent'), findsNothing);
  });

  testWidgets('SeminarRunCardResumeBanner renders checkpoint details',
      (tester) async {
    var opened = 0;
    var continued = 0;
    final state = _resumableState('session-1');
    final card = AiSeminarRunCardMeta(
      question: 'Explain this idea?',
      sessionId: 'session-1',
      createdAt: 1,
    );

    expect(shouldShowSeminarCardResumeBanner(card, state), isTrue);
    expect(seminarResumeProviderLabel(state), 'OpenAI / gpt-test');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SeminarRunCardResumeBanner(
              card: card,
              runtimeState: state,
              showDetails: true,
              isSubmitting: false,
              zh: false,
              roleLabelBuilder: _roleLabel,
              onOpen: () => opened += 1,
              onContinue: () => continued += 1,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Resumable checkpoint'), findsOneWidget);
    expect(find.text('Continue seminar'), findsOneWidget);
    expect(find.text('Checkpoint details'), findsWidgets);
    expect(find.text('Resumable · completed: Critical'), findsOneWidget);
    expect(find.text('1 evidence items'), findsOneWidget);
    expect(find.text('Continue Supportive'), findsOneWidget);
    expect(find.text('OpenAI / gpt-test'), findsOneWidget);

    await tester.tap(find.text('Continue seminar'));
    await tester.tap(find.text('Hide checkpoint'));
    await tester.pump();

    expect(continued, 1);
    expect(opened, 1);
  });
}

String _roleLabel(AiSeminarRole role) {
  return switch (role) {
    AiSeminarRole.critical => 'Critical',
    AiSeminarRole.supportive => 'Supportive',
    AiSeminarRole.synthesizer => 'Synthesizer',
    AiSeminarRole.verifier => 'Verifier',
  };
}

AiSeminarRuntimeState _resumableState(String sessionId) {
  final sourceRef = SourceRef(
    bookId: 7,
    href: 'Text/ch1.xhtml',
    cfi: 'epubcfi(/6/8)',
    sourceTextSnippet: 'The source passage.',
    sourceKind: SourceRefKind.currentBookRag,
  );
  final backgroundJob = AiSeminarBackgroundJobSnapshot(
    id: 'job-$sessionId',
    sessionId: sessionId,
    status: AiSeminarBackgroundJobStatus.running,
    startedAt: 1000,
    updatedAt: 1001,
  );
  return AiSeminarRuntimeState.initial().copyWith(
    session: AiSeminarSessionContract(
      id: sessionId,
      question: 'Explain this idea?',
      roles: const [AiSeminarRole.critical, AiSeminarRole.supportive],
      billingContext: const AiSeminarBillingContext(
        providerId: 'openai',
        providerName: 'OpenAI',
        modelId: 'gpt-test',
      ),
    ),
    status: AiSeminarRunStatus.running,
    evidenceBundle: AiSeminarEvidenceBundle(
      query: 'Explain this idea?',
      evidence: [
        AiSeminarEvidence(
          id: 'e1',
          scope: AiSeminarEvidenceScope.currentBook,
          text: 'The source passage.',
          sourceRef: sourceRef,
        ),
      ],
    ),
    turns: const [
      AiSeminarRoleTurn(
        id: 'turn-critical',
        role: AiSeminarRole.critical,
        prompt: 'prompt',
        responseText: 'critical response',
      ),
    ],
    backgroundJob: backgroundJob,
    backgroundJobs: [backgroundJob],
    restoredFromLocalCache: true,
  );
}
