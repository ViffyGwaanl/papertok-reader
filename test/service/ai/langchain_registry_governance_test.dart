import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:papertok_reader/enums/ai_tool_scene.dart';
import 'package:papertok_reader/models/ai_agent_governance.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/service/ai/langchain_ai_config.dart';
import 'package:papertok_reader/service/ai/langchain_registry.dart';
import 'package:papertok_reader/service/ai/skills/ai_skill_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

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

  test('stale seminar mode active skill is ignored for normal chat pipeline',
      () {
    Prefs().activeAiSkillId = 'seminar_mode';
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final pipelineProvider = Provider(
      (ref) => LangchainAiRegistry(ref).resolve(
        LangchainAiConfig(
          identifier: 'openai',
          model: 'test-model',
          apiKey: '',
        ),
        useAgent: true,
      ),
    );
    final pipeline = container.read(pipelineProvider);

    expect(pipeline.agentScene, isNot(AiAgentScene.seminar));
    expect(pipeline.permissionMatrix, isNull);
    expect(
      pipeline.systemMessage!.contentAsString,
      isNot(contains('Active Skill: Seminar Mode')),
      reason:
          'AI Seminar must be started as a native AI Chat run, not restored as a legacy prompt skill.',
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
