import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/models/ai_agent_governance.dart';
import 'package:papertok_reader/service/ai/skills/ai_skill_registry.dart';
import 'package:papertok_reader/service/ai/skills/custom_skill_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('imports valid custom skill contract and exposes runtime skill',
      () async {
    final result = await CustomSkillStore().importJson('''
{
  "schemaVersion": 1,
  "id": "slow_reader",
  "name": "Slow Reader",
  "description": "Explain one passage with local evidence.",
  "systemPromptAppend": "Move slowly and cite current-book evidence.",
  "allowedToolIds": ["current_chapter_content", "resolve_cfi"],
  "scenes": ["reading"],
  "enabled": true
}
''');

    expect(result.accepted, true);
    expect(result.errors, isEmpty);

    final contracts = CustomSkillStore().contracts();
    expect(contracts, hasLength(1));
    expect(contracts.single.id, 'slow_reader');
    expect(
        contracts.single.canInject(AiToolPermissionMatrix.defaultMatrix), true);

    final skill = AiSkillRegistry.byId('slow_reader');
    expect(skill, isNotNull);
    expect(skill!.isBuiltIn, false);
    expect(skill.allowedToolIds, ['current_chapter_content', 'resolve_cfi']);
    expect(skill.sceneIds, ['reading']);
    expect(
        AiSkillRegistry.allSkills().map((s) => s.id), contains('slow_reader'));
  });

  test('rejects unsafe custom skill without persisting or activating',
      () async {
    final result = await CustomSkillStore().importJson('''
{
  "schemaVersion": 1,
  "id": "unsafe_writer",
  "name": "Unsafe Writer",
  "systemPromptAppend": "Write notes immediately.",
  "allowedToolIds": ["create_note", "spawn_sub_agent"],
  "scenes": ["reading"],
  "enabled": true
}
''');

    expect(result.accepted, false);
    expect(result.errors,
        contains('custom skills cannot request write tool: create_note'));
    expect(result.errors,
        contains('custom skills cannot request recursive sub-agent access'));
    expect(CustomSkillStore().contracts(), isEmpty);
    expect(AiSkillRegistry.byId('unsafe_writer'), isNull);
  });

  test('upserts custom skill by id and disabled skill is not injected',
      () async {
    await CustomSkillStore().importJson('''
{
  "schemaVersion": 1,
  "id": "local_terms",
  "name": "Local Terms",
  "systemPromptAppend": "Define terms from the current book.",
  "allowedToolIds": ["current_chapter_content"],
  "scenes": ["reading"],
  "enabled": true
}
''');

    final result = await CustomSkillStore().importJson('''
{
  "schemaVersion": 1,
  "id": "local_terms",
  "name": "Local Terms Disabled",
  "systemPromptAppend": "Define terms but stay inactive.",
  "allowedToolIds": ["current_chapter_content"],
  "scenes": ["reading"],
  "enabled": false
}
''');

    expect(result.accepted, true);
    final contracts = CustomSkillStore().contracts();
    expect(contracts, hasLength(1));
    expect(contracts.single.name, 'Local Terms Disabled');
    expect(contracts.single.enabled, false);
    expect(AiSkillRegistry.byId('local_terms'), isNull);
  });
}
