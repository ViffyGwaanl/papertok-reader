import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_agent_governance.dart';

void main() {
  test('permission matrix keeps seminar mostly read-only', () {
    const matrix = AiToolPermissionMatrix.defaultMatrix;

    expect(
      matrix.isAllowed(
        scene: AiAgentScene.seminar,
        toolId: 'semantic_search_current_book',
      ),
      true,
    );
    expect(
      matrix.isAllowed(
        scene: AiAgentScene.seminar,
        toolId: 'semantic_search_library',
      ),
      false,
    );
    expect(
      matrix.isAllowed(scene: AiAgentScene.seminar, toolId: 'create_note'),
      false,
    );
    expect(matrix.requiresApproval('create_note'), true);
  });

  test('seminar library fallback matrix is separate from reading seminar', () {
    const fallback = AiToolPermissionMatrix.seminarLibraryFallbackMatrix;

    expect(
      fallback.isAllowed(
        scene: AiAgentScene.seminar,
        toolId: 'semantic_search_library',
      ),
      true,
    );
    expect(
      fallback.isAllowed(
        scene: AiAgentScene.seminar,
        toolId: 'semantic_search_current_book',
      ),
      false,
    );
  });

  test('sub-agent governance forbids recursive spawn by default', () {
    const policy = SubAgentGovernancePolicy();
    const matrix = AiToolPermissionMatrix.defaultMatrix;
    final readRule = matrix.ruleFor('semantic_search_current_book')!;
    final spawnRule = matrix.ruleFor('spawn_sub_agent')!;

    expect(policy.canUseToolInsideSubAgent('spawn_sub_agent'), false);
    expect(policy.canRunInParallel(readRule), true);
    expect(policy.canRunInParallel(spawnRule), false);
  });

  test('custom skills cannot request unknown tools or recursive subagents', () {
    const skill = CustomSkillContract(
      id: 'custom',
      name: 'Custom',
      systemPromptAppend: 'Be useful.',
      allowedToolIds: ['semantic_search_current_book', 'spawn_sub_agent', '*'],
    );

    final errors = skill.validate(AiToolPermissionMatrix.defaultMatrix);
    expect(errors,
        contains('custom skills cannot request recursive sub-agent access'));
    expect(errors, contains('unknown tool: *'));
  });

  test('custom skill contract parses safe fixture maps', () {
    final skill = CustomSkillContract.fromJson({
      'schemaVersion': 1,
      'id': 'explain_selection',
      'name': 'Explain Selection',
      'description': 'Explain selected text with local evidence.',
      'systemPromptAppend': 'Use the selected text and cite sources.',
      'allowedToolIds': ['current_chapter_content', 'resolve_cfi'],
      'scenes': ['reading', 'review'],
      'enabled': true,
    });

    expect(skill.schemaVersion, 1);
    expect(skill.id, 'explain_selection');
    expect(skill.description, contains('local evidence'));
    expect(skill.scenes, [AiAgentScene.reading, AiAgentScene.review]);
    expect(skill.enabled, true);
    expect(skill.validate(AiToolPermissionMatrix.defaultMatrix), isEmpty);
    expect(skill.canInject(AiToolPermissionMatrix.defaultMatrix), true);
    expect(skill.toJson()['schemaVersion'], 1);
  });

  test('custom skill contract requires explicit integer schema version', () {
    final missing = CustomSkillContract.fromJson({
      'id': 'missing_schema',
      'name': 'Missing Schema',
      'systemPromptAppend': 'Stay local.',
      'allowedToolIds': ['current_chapter_content'],
      'scenes': ['reading'],
      'enabled': true,
    });
    final malformed = CustomSkillContract.fromJson({
      'schemaVersion': '1',
      'id': 'malformed_schema',
      'name': 'Malformed Schema',
      'systemPromptAppend': 'Stay local.',
      'allowedToolIds': ['current_chapter_content'],
      'scenes': ['reading'],
      'enabled': true,
    });

    expect(missing.validate(AiToolPermissionMatrix.defaultMatrix),
        contains('schemaVersion is required'));
    expect(missing.canInject(AiToolPermissionMatrix.defaultMatrix), false);
    expect(malformed.validate(AiToolPermissionMatrix.defaultMatrix),
        contains('schemaVersion must be an integer'));
    expect(malformed.canInject(AiToolPermissionMatrix.defaultMatrix), false);
  });

  test('custom skill parser reports malformed field types', () {
    final skill = CustomSkillContract.fromJson({
      'schemaVersion': 1,
      'id': 42,
      'name': 42,
      'systemPromptAppend': ['not', 'a', 'string'],
      'allowedToolIds': 'current_chapter_content',
      'scenes': 'reading',
      'enabled': 'true',
    });

    final errors = skill.validate(AiToolPermissionMatrix.defaultMatrix);

    expect(errors, contains('id must be a string'));
    expect(errors, contains('name must be a string'));
    expect(errors, contains('systemPromptAppend must be a string'));
    expect(errors, contains('allowedToolIds must be a list'));
    expect(errors, contains('scenes must be a list'));
    expect(errors, contains('enabled must be a boolean'));
    expect(skill.canInject(AiToolPermissionMatrix.defaultMatrix), false);
  });

  test('custom skill runtime injection requires enabled and valid contract',
      () {
    final disabled = CustomSkillContract.fromJson({
      'schemaVersion': 1,
      'id': 'safe_disabled',
      'name': 'Safe Disabled',
      'systemPromptAppend': 'Stay local.',
      'allowedToolIds': ['current_chapter_content'],
      'scenes': ['reading'],
      'enabled': false,
    });
    final invalid = CustomSkillContract.fromJson({
      'schemaVersion': 1,
      'id': 'unsafe_enabled',
      'name': 'Unsafe Enabled',
      'systemPromptAppend': 'Write without review.',
      'allowedToolIds': ['create_note'],
      'scenes': ['reading'],
      'enabled': true,
    });

    expect(disabled.validate(AiToolPermissionMatrix.defaultMatrix), isEmpty);
    expect(disabled.canInject(AiToolPermissionMatrix.defaultMatrix), false);
    expect(invalid.validate(AiToolPermissionMatrix.defaultMatrix),
        contains('custom skills cannot request write tool: create_note'));
    expect(invalid.canInject(AiToolPermissionMatrix.defaultMatrix), false);
  });

  test('custom skill contract rejects unknown schema fields and unsafe scenes',
      () {
    final skill = CustomSkillContract.fromJson({
      'schemaVersion': 2,
      'id': 'unsafe',
      'name': 'Unsafe',
      'systemPromptAppend': 'Do anything.',
      'allowedToolIds': ['create_note', 'web_search'],
      'scenes': ['seminar', 'system', 'unknown-scene'],
      'extra': true,
    });

    final errors = skill.validate(AiToolPermissionMatrix.defaultMatrix);

    expect(errors, contains('unsupported schemaVersion: 2'));
    expect(errors, contains('unknown field: extra'));
    expect(errors, contains('custom skills cannot request system scene'));
    expect(errors, contains('unknown scene: unknown-scene'));
    expect(
        errors, contains('tool not allowed in requested scenes: web_search'));
    expect(errors,
        contains('custom skills cannot request write tool: create_note'));
  });

  test('provider capability exposes seminar readiness', () {
    const capable = ProviderCapability(
      providerId: 'p',
      modelId: 'm',
      contextWindow: 32000,
      supportsTools: true,
    );
    const weak = ProviderCapability(
      providerId: 'p',
      modelId: 'small',
      contextWindow: 8000,
      supportsTools: true,
    );

    expect(capable.canRunSeminar, true);
    expect(weak.canRunSeminar, false);
  });
}
