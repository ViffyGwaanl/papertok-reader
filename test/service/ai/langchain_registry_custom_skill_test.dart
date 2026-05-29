import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/enums/ai_tool_scene.dart';
import 'package:papertok_reader/models/ai_agent_governance.dart';
import 'package:papertok_reader/service/ai/langchain_ai_config.dart';
import 'package:papertok_reader/service/ai/langchain_registry.dart';
import 'package:papertok_reader/service/ai/skills/ai_skill.dart';
import 'package:papertok_reader/service/ai/skills/ai_skill_registry.dart';
import 'package:papertok_reader/service/ai/skills/custom_skill_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('custom skill limits tools to declared read-only contract', () {
    const skill = AiSkill(
      id: 'slow_reader',
      name: 'Slow Reader',
      description: 'Local evidence only.',
      systemPromptAppend: 'Use only the current passage.',
      isBuiltIn: false,
      allowedToolIds: ['current_chapter_content'],
      sceneIds: ['reading'],
    );

    final ids = LangchainAiRegistry.enabledToolIdsForActiveSkill(
      [
        'current_chapter_content',
        'current_book_toc',
        'semantic_search_current_book',
      ],
      activeSkill: skill,
      toolScene: AiToolScene.reading,
      agentScene: AiAgentScene.reading,
    );

    expect(ids, ['current_chapter_content']);
  });

  test('custom skill is ignored outside its declared scenes', () {
    const skill = AiSkill(
      id: 'review_only',
      name: 'Review Only',
      description: 'Review scene only.',
      systemPromptAppend: 'Audit review evidence.',
      isBuiltIn: false,
      allowedToolIds: ['resolve_cfi'],
      sceneIds: ['review'],
    );

    final ids = LangchainAiRegistry.enabledToolIdsForActiveSkill(
      ['resolve_cfi'],
      activeSkill: skill,
      toolScene: AiToolScene.reading,
      agentScene: AiAgentScene.reading,
    );

    expect(ids, isEmpty);
    expect(
      LangchainAiRegistry.activeSkillForScene(
        skill,
        AiAgentScene.reading,
      ),
      isNull,
    );
  });

  test('built-in skills keep existing enabled tool set', () {
    const skill = AiSkill(
      id: 'reading_companion',
      name: 'Reading Companion',
      description: 'Built-in.',
      systemPromptAppend: 'Explain.',
    );

    final ids = LangchainAiRegistry.enabledToolIdsForActiveSkill(
      ['current_chapter_content', 'create_note'],
      activeSkill: skill,
      toolScene: AiToolScene.reading,
      agentScene: AiAgentScene.reading,
    );

    expect(ids, ['current_chapter_content', 'create_note']);
  });

  test('active custom skill injects prompt and narrows runtime pipeline tools',
      () async {
    await CustomSkillStore().importJson('''
{
  "schemaVersion": 1,
  "id": "library_terms",
  "name": "Library Terms",
  "description": "Explain terms from library evidence.",
  "systemPromptAppend": "Custom runtime prompt: cite library evidence only.",
  "allowedToolIds": ["semantic_search_library"],
  "scenes": ["library"],
  "enabled": true
}
''');
    Prefs().activeAiSkillId = 'library_terms';
    Prefs().enabledAiToolIds = [
      'semantic_search_library',
      'bookshelf_lookup',
      'notes_search',
    ];

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
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final pipeline = container.read(pipelineProvider);
    final activeSkill = AiSkillRegistry.byId('library_terms');

    expect(activeSkill, isNotNull);
    expect(
      pipeline.systemMessage!.contentAsString,
      contains('Custom runtime prompt: cite library evidence only.'),
    );
    expect(pipeline.agentScene, AiAgentScene.library);
    expect(
      pipeline.tools.map((tool) => tool.name),
      ['semantic_search_library'],
    );
    expect(
      LangchainAiRegistry.shouldIncludeMcpTools(
        pipeline.agentScene!,
        activeSkill: activeSkill,
      ),
      false,
    );
  });
}
