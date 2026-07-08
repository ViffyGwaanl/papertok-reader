import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/widgets/ai/seminar/participation/seminar_participation_widgets.dart';

void main() {
  testWidgets('SeminarSnapshotReaderTurnTile renders reader turn metadata',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SeminarSnapshotReaderTurnTile(
            part: const AiSeminarRunCardMessagePart(
              type: 'reader_turn',
              roleId: 'skeptic',
              label: 'ask-role',
              text: 'Please challenge this claim.',
              toolId: 'semantic_search',
              query: 'chapter evidence',
              status: 'completed',
              completedAt: 123,
              agentRunId: 'run-1',
              parentRunId: 'parent-1',
            ),
            zh: false,
            roleLabelBuilder: (roleId) => 'Role $roleId',
            actionLabelBuilder: (action) => 'Action $action',
            statusLabelBuilder: (_) => 'Processed',
            completedAtLabelBuilder: (_, __) => 'Processed at now',
            toolLabelBuilder: (toolId) => 'Tool $toolId',
          ),
        ),
      ),
    );

    expect(find.text('Action ask-role · Role skeptic'), findsOneWidget);
    expect(find.text('Please challenge this claim.'), findsOneWidget);
    expect(find.text('Tool: Tool semantic_search'), findsOneWidget);
    expect(find.text('Query: chapter evidence'), findsOneWidget);
    expect(find.text('Processed'), findsOneWidget);
    expect(find.text('Processed at now'), findsOneWidget);
    expect(find.text('Agent trace'), findsOneWidget);
    expect(find.text('Run record'), findsNWidgets(2));
    expect(find.text('Parent run'), findsOneWidget);
  });

  testWidgets('SeminarSnapshotReaderComposerTile renders reader options',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SeminarSnapshotReaderComposerTile(
            part: const AiSeminarRunCardMessagePart(
              type: 'reader_composer',
              text: 'Choose the next turn.',
              actionIds: ['ask-role', 'synthesize'],
              roleIds: ['skeptic', 'synthesizer'],
              defaultActionId: 'ask-role',
              defaultRoleId: 'skeptic',
              selectedActionId: 'synthesize',
              selectedRoleId: 'synthesizer',
              draftText: 'Draft response',
            ),
            zh: false,
            roleLabelBuilder: (roleId) => 'Role $roleId',
            actionLabelBuilder: (action) => 'Action $action',
          ),
        ),
      ),
    );

    expect(
      find.text('This Seminar can continue with a reader turn'),
      findsOneWidget,
    );
    expect(find.text('Choose the next turn.'), findsOneWidget);
    expect(find.text('Default action'), findsOneWidget);
    expect(find.text('Action ask-role'), findsWidgets);
    expect(find.text('Default role'), findsOneWidget);
    expect(find.text('Role skeptic'), findsWidgets);
    expect(find.text('Current action'), findsOneWidget);
    expect(find.text('Action synthesize'), findsWidgets);
    expect(find.text('Current role'), findsOneWidget);
    expect(find.text('Role synthesizer'), findsWidgets);
    expect(find.text('Draft reply'), findsOneWidget);
    expect(find.text('Draft response'), findsOneWidget);
    expect(find.text('Available actions'), findsOneWidget);
    expect(find.text('Available roles'), findsOneWidget);
  });

  testWidgets('SeminarSnapshotDirectorCueTile renders controls and input',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SeminarSnapshotDirectorCueTile(
            part: const AiSeminarRunCardMessagePart(
              type: 'director_state',
              label: 'ask-user',
              text: 'Waiting for the reader.',
              actionIds: ['send-input', 'close-agent'],
              agentRunId: 'agent-1',
            ),
            zh: false,
            directorCueLabelBuilder: (_) => 'Director waiting',
            actionLabelBuilder: (action) =>
                seminarAgentControlActionLabel(action, zh: false),
            actionEnabledBuilder: (action) => action == 'send-input',
            actionWidgetBuilder: (action) => Text('Recorded $action'),
            agentInputComposer: const Text('Input composer'),
          ),
        ),
      ),
    );

    expect(find.text('Director waiting'), findsOneWidget);
    expect(find.text('Waiting for the reader.'), findsOneWidget);
    expect(find.text('Recorded controls'), findsOneWidget);
    expect(find.text('Recorded close-agent'), findsOneWidget);
    expect(find.text('Input composer'), findsOneWidget);
  });

  testWidgets('SeminarAgentControlAction invokes executable action',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SeminarAgentControlAction(
            actionId: 'resume-agent',
            agentRunId: 'agent-1',
            label: 'Resume role',
            icon: Icons.restart_alt_outlined,
            isExecutable: true,
            isSubmitting: false,
            onPressed: () => taps += 1,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Resume role'));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('SeminarAgentControlAction falls back to recorded chip',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SeminarAgentControlAction(
            actionId: 'wait-agent',
            agentRunId: '',
            label: 'Wait for role',
            icon: Icons.hourglass_empty_outlined,
            isExecutable: false,
            isSubmitting: false,
            onPressed: null,
          ),
        ),
      ),
    );

    expect(find.text('Wait for role'), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('SeminarAgentInputComposer submits entered text', (tester) async {
    final controller = TextEditingController(text: 'hello');
    var changes = 0;
    var submits = 0;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SeminarAgentInputComposer(
            agentRunId: 'agent-1',
            controller: controller,
            zh: false,
            isSubmitting: false,
            onChanged: (_) => changes += 1,
            onSubmit: () => submits += 1,
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('seminar-chat-card-agent-input-agent-1')),
      'hello again',
    );
    await tester.tap(
      find.byKey(
        const ValueKey('seminar-chat-card-agent-input-submit-agent-1'),
      ),
    );
    await tester.pump();

    expect(changes, 1);
    expect(submits, 1);
  });

  test('seminarAgentControlActionIsExecutable follows status rules', () {
    const part = AiSeminarRunCardMessagePart(
      type: 'agent_status',
      agentRunId: 'agent-1',
      label: 'role-waiting-input',
    );

    expect(
      seminarAgentControlActionIsExecutable(
        part,
        actionId: 'send-input',
        sessionId: 'session-1',
      ),
      isTrue,
    );
    expect(
      seminarAgentControlActionIsExecutable(
        part,
        actionId: 'resume-agent',
        sessionId: 'session-1',
      ),
      isFalse,
    );
  });
}
