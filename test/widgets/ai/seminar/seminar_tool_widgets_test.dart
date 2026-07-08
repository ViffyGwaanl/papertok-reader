import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/widgets/ai/seminar/tools/seminar_tool_widgets.dart';

void main() {
  testWidgets('SeminarSnapshotAgentTraceRows renders trace labels',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SeminarSnapshotAgentTraceRows(
            'seminar-tool-call-6f4b',
            parentRunId: 'seminar-chat-history',
            zh: false,
          ),
        ),
      ),
    );

    expect(find.text('Agent trace'), findsOneWidget);
    expect(find.text('Parent run'), findsOneWidget);
    expect(find.textContaining('Tool call'), findsOneWidget);
    expect(find.text('This seminar'), findsOneWidget);
  });

  testWidgets('SeminarToolCallAction invokes enabled action', (tester) async {
    var pressed = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SeminarToolCallAction(
            actionId: 'wait-tool-call',
            label: 'Retrieving evidence...',
            icon: Icons.hourglass_empty_outlined,
            isExecutable: true,
            isSubmitting: false,
            toolCallId: 'tool-1',
            agentRunId: 'agent-1',
            onPressed: () => pressed++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Retrieving evidence...'));
    await tester.pump();

    expect(pressed, 1);
  });

  testWidgets('SeminarSnapshotToolCallTile renders controls and evidence',
      (tester) async {
    var pressed = 0;
    const toolCall = AiSeminarRunCardToolCallSnapshot(
      id: 'tool-1',
      agentRunId: 'seminar-tool-call-6f4b',
      parentRunId: 'seminar-chat-history',
      toolId: 'semantic_search_current_book',
      label: 'Current-book semantic search',
      query: 'attention',
      resultCount: 2,
      text: 'Returned passages',
      roleIds: ['critical'],
      actionIds: ['wait-tool-call'],
      evidenceRefs: [
        AiSeminarRunCardEvidenceSnapshot(
          id: 'current-1',
          title: 'Evidence title',
          snippet: 'Evidence snippet',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SeminarSnapshotToolCallTile(
            toolCall: toolCall,
            label: 'Current-book semantic search',
            statusLabel: null,
            startedAtLabel: null,
            completedAtLabel: null,
            durationLabel: null,
            visibleRoleLabels: 'Critical',
            outputLabel: 'Tool output',
            zh: false,
            actionLabelBuilder: (_) => 'Retrieving evidence...',
            actionIconBuilder: (_) => Icons.hourglass_empty_outlined,
            actionEnabledBuilder: (_) => true,
            actionPressedBuilder: (_) => () => pressed++,
            evidenceTileBuilder: (_) => const Text('Evidence tile'),
          ),
        ),
      ),
    );

    expect(find.text('Current-book semantic search'), findsOneWidget);
    expect(find.text('Query: attention'), findsOneWidget);
    expect(find.text('Visible roles'), findsOneWidget);
    expect(find.text('Critical'), findsOneWidget);
    expect(find.text('Tool output'), findsOneWidget);
    expect(find.text('Evidence tile'), findsOneWidget);

    await tester.tap(find.text('Retrieving evidence...'));
    await tester.pump();

    expect(pressed, 1);
  });
}
