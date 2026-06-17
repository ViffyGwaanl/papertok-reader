import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/widgets/ai/seminar/roles/seminar_role_widgets.dart';

void main() {
  testWidgets('SeminarSnapshotRoleTile renders summary and evidence callback',
      (tester) async {
    AiSeminarRunCardEvidenceSnapshot? selectedEvidence;
    const evidence = AiSeminarRunCardEvidenceSnapshot(
      id: 'current-1',
      title: 'Evidence title',
      snippet: 'Evidence snippet',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SeminarSnapshotRoleTile(
            role: const AiSeminarRunCardRoleSummary(
              roleId: 'critical',
              label: 'Critical',
              summary: 'A careful role summary.',
              evidenceRefs: [evidence],
            ),
            label: 'Critical',
            icon: Icons.psychology_outlined,
            zh: false,
            onEvidencePressed: (evidence) => selectedEvidence = evidence,
          ),
        ),
      ),
    );

    expect(find.text('Critical'), findsOneWidget);
    expect(find.text('A careful role summary.'), findsOneWidget);
    expect(find.text('Evidence 1'), findsOneWidget);

    await tester.tap(find.text('Evidence 1'));
    await tester.pump();

    expect(selectedEvidence, evidence);
  });

  testWidgets('SeminarSnapshotDiscussionTimeline renders turns and streaming',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SeminarSnapshotDiscussionTimeline(
              roles: const [
                AiSeminarRunCardRoleSummary(
                  roleId: 'critical',
                  label: 'Critical',
                  summary: 'Turn summary.',
                  evidenceRefs: [
                    AiSeminarRunCardEvidenceSnapshot(
                      id: 'current-1',
                      title: 'Evidence title',
                      snippet: 'Evidence snippet',
                    ),
                  ],
                ),
              ],
              rolePartials: const [
                AiSeminarRunCardRoleSummary(
                  roleId: 'supportive',
                  label: 'Supportive',
                  summary: 'Partial thought.',
                ),
              ],
              liveRole: AiSeminarRole.synthesizer,
              liveRoleText: 'Live thought.',
              zh: false,
              roleLabelBuilder: _roleLabel,
              roleIconBuilder: (_) => Icons.person_outline,
              onEvidencePressed: (_) {},
              evidenceTileBuilder: (_, fallbackIndex) =>
                  Text('Evidence tile $fallbackIndex'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Discussion timeline'), findsOneWidget);
    expect(find.text('1 · Critical'), findsOneWidget);
    expect(find.text('Turn summary.'), findsOneWidget);
    expect(find.text('Evidence used by this turn'), findsOneWidget);
    expect(find.text('Evidence tile 1'), findsOneWidget);
    expect(find.text('Role turn streaming'), findsNWidgets(2));
    expect(find.text('Supportive'), findsOneWidget);
    expect(find.text('Partial thought.'), findsOneWidget);
    expect(find.text('Synthesizer'), findsOneWidget);
    expect(find.text('Live thought.'), findsOneWidget);
  });

  testWidgets('SeminarSnapshotAgentStatusTile renders controls and composer',
      (tester) async {
    var pressed = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SeminarSnapshotAgentStatusTile(
            part: const AiSeminarRunCardMessagePart(
              type: 'agent_status',
              agentRunId: 'seminar-agent-1',
              parentRunId: 'seminar-chat-history',
              roleId: 'critical',
              actionIds: ['send-input', 'wait-agent'],
              allowedToolIds: ['semantic_search_current_book'],
              label: 'running',
              text: 'Role is thinking.',
            ),
            zh: false,
            statusLabelBuilder: (_) => 'Running',
            roleLabelBuilder: _roleLabel,
            actionLabelBuilder: (actionId) =>
                actionId == 'wait-agent' ? 'Wait for role' : 'Send input',
            actionEnabledBuilder: (actionId) => actionId == 'send-input',
            actionWidgetBuilder: (actionId) => TextButton(
              onPressed: () => pressed++,
              child:
                  Text(actionId == 'wait-agent' ? 'Wait for role' : actionId),
            ),
            allowedToolIdsBuilder: (toolIds) => toolIds,
            toolLabelBuilder: (_) => 'Current-book semantic search',
            agentInputComposer: const Text('Composer'),
          ),
        ),
      ),
    );

    expect(find.text('Role status'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Critical'), findsOneWidget);
    expect(find.text('Role is thinking.'), findsOneWidget);
    expect(find.text('Allowed tools'), findsOneWidget);
    expect(find.text('Current-book semantic search'), findsOneWidget);
    expect(find.text('Recorded controls'), findsOneWidget);
    expect(find.text('Wait for role'), findsOneWidget);
    expect(find.text('Composer'), findsOneWidget);

    await tester.tap(find.text('Wait for role'));
    await tester.pump();

    expect(pressed, 1);
  });
}

String _roleLabel(String roleId) => switch (roleId) {
      'critical' => 'Critical',
      'supportive' => 'Supportive',
      'synthesizer' => 'Synthesizer',
      _ => roleId,
    };
