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
}
