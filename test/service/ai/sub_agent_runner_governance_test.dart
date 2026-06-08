import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_agent_governance.dart';
import 'package:papertok_reader/service/ai/sub_agent_runner.dart';

void main() {
  test('sub-agent default filtering is governed and no-web', () {
    final ids = SubAgentRunner.allowedToolIdsForAgent(agentType: 'research');

    expect(ids, isNot(contains('web_search')));
    expect(ids, isNot(contains('fetch_url')));
    expect(ids, contains('book_content_search'));
    expect(ids, contains('semantic_search_current_book'));
    expect(ids, isNot(contains('semantic_search_library')));
    expect(ids, isNot(contains('spawn_sub_agent')));
  });

  test('seminar governance removes web tools from research sub-agent', () {
    final ids = SubAgentRunner.allowedToolIdsForAgent(
      agentType: 'research',
      permissionMatrix: AiToolPermissionMatrix.defaultMatrix,
      agentScene: AiAgentScene.seminar,
    );

    expect(ids, contains('book_content_search'));
    expect(ids, contains('semantic_search_current_book'));
    expect(ids, isNot(contains('semantic_search_library')));
    expect(ids, contains('current_reading_metadata'));
    expect(ids, isNot(contains('web_search')));
    expect(ids, isNot(contains('fetch_url')));
  });

  test('sub-agent fallback matrix allows library search outside reading', () {
    final ids = SubAgentRunner.allowedToolIdsForAgent(
      agentType: 'research',
      permissionMatrix: AiToolPermissionMatrix.seminarLibraryFallbackMatrix,
      agentScene: AiAgentScene.seminar,
    );

    expect(ids, contains('semantic_search_library'));
    expect(ids, isNot(contains('semantic_search_current_book')));
    expect(ids, isNot(contains('web_search')));
  });

  test('sub-agent filters matrix-approved approval tools without approval path',
      () {
    const matrix = AiToolPermissionMatrix([
      AiToolPermissionRule(
        toolId: 'semantic_search_current_book',
        scenes: {AiAgentScene.reading},
        requiresApproval: true,
        readOnly: false,
        concurrencySafe: false,
      ),
      AiToolPermissionRule(
        toolId: 'book_content_search',
        scenes: {AiAgentScene.reading},
      ),
    ]);

    final ids = SubAgentRunner.allowedToolIdsForAgent(
      agentType: 'research',
      permissionMatrix: matrix,
      agentScene: AiAgentScene.reading,
    );

    expect(ids, contains('book_content_search'));
    expect(ids, isNot(contains('semantic_search_current_book')));
  });

  test('governance policy blocks recursive spawn when present in a custom set',
      () {
    const policy = SubAgentGovernancePolicy();

    expect(policy.canUseToolInsideSubAgent('spawn_sub_agent'), isFalse);
    expect(policy.canUseToolInsideSubAgent('semantic_search_current_book'),
        isTrue);
  });

  test('tracked sub-agent run exposes native agent metadata', () async {
    final startedAt = DateTime.utc(2026, 6, 4, 12);

    final result = await SubAgentRunner.runTracked(
      task: 'Find traceable evidence for the selected claim.',
      agentType: 'research',
      maxSteps: 30,
      agentScene: AiAgentScene.seminar,
      agentRunId: 'agent-run-test-1',
      parentRunId: 'seminar-parent-run',
      clock: () => startedAt,
      executor: (plan) async {
        expect(plan.agentRunId, 'agent-run-test-1');
        expect(plan.parentRunId, 'seminar-parent-run');
        expect(plan.agentType, 'research');
        expect(plan.maxSteps, 15);
        expect(plan.allowedToolIds, contains('book_content_search'));
        expect(plan.allowedToolIds,
            isNot(containsAll(['web_search', 'spawn_sub_agent'])));
        return 'Evidence A cites the current book.';
      },
    );

    expect(result.agentRunId, 'agent-run-test-1');
    expect(result.parentRunId, 'seminar-parent-run');
    expect(result.status, SubAgentRunStatus.completed);
    expect(result.status.asString, 'completed');
    expect(result.agentType, 'research');
    expect(result.maxSteps, 15);
    expect(result.result, 'Evidence A cites the current book.');
    expect(result.error, isNull);
    expect(result.startedAt, startedAt);
    expect(result.finishedAt, startedAt);
    expect(result.allowedToolIds, contains('book_content_search'));
    expect(result.allowedToolIds,
        isNot(containsAll(['web_search', 'spawn_sub_agent'])));

    expect(result.toJson(), {
      'agentRunId': 'agent-run-test-1',
      'parentRunId': 'seminar-parent-run',
      'agentType': 'research',
      'task': 'Find traceable evidence for the selected claim.',
      'status': 'completed',
      'maxSteps': 15,
      'agentScene': 'seminar',
      'allowedToolIds': result.allowedToolIds,
      'startedAt': startedAt.toIso8601String(),
      'finishedAt': startedAt.toIso8601String(),
      'result': 'Evidence A cites the current book.',
    });
  });
}
