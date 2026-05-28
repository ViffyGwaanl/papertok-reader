import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/enums/ai_tool_scene.dart';
import 'package:papertok_reader/models/ai_agent_governance.dart';
import 'package:papertok_reader/service/ai/langchain_registry.dart';
import 'package:papertok_reader/service/ai/skills/ai_skill_registry.dart';

void main() {
  test('seminar skill maps runtime to seminar governance scene', () {
    final seminar = AiSkillRegistry.byId('seminar_mode');

    expect(LangchainAiRegistry.isSeminarSkill(seminar), isTrue);
    expect(
      LangchainAiRegistry.agentSceneFor(
        toolScene: AiToolScene.reading,
        activeSkill: seminar,
      ),
      AiAgentScene.seminar,
    );
    expect(
      LangchainAiRegistry.shouldIncludeMcpTools(AiAgentScene.seminar),
      isFalse,
    );
    expect(
      LangchainAiRegistry.seminarPermissionMatrixFor(
        toolScene: AiToolScene.reading,
      ).isAllowed(
        scene: AiAgentScene.seminar,
        toolId: 'semantic_search_library',
      ),
      isFalse,
    );
    expect(
      LangchainAiRegistry.seminarPermissionMatrixFor(
        toolScene: AiToolScene.library,
      ).isAllowed(
        scene: AiAgentScene.seminar,
        toolId: 'semantic_search_library',
      ),
      isTrue,
    );
  });

  test('non-seminar skill keeps existing reading/library scene mapping', () {
    final companion = AiSkillRegistry.byId('reading_companion');

    expect(LangchainAiRegistry.isSeminarSkill(companion), isFalse);
    expect(
      LangchainAiRegistry.agentSceneFor(
        toolScene: AiToolScene.reading,
        activeSkill: companion,
      ),
      AiAgentScene.reading,
    );
    expect(
      LangchainAiRegistry.shouldIncludeMcpTools(AiAgentScene.reading),
      isTrue,
    );
  });
}
