import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/enums/ai_tool_scene.dart';
import 'package:papertok_reader/models/ai_agent_governance.dart';
import 'package:papertok_reader/service/ai/tools/ai_tool_registry.dart';

void main() {
  test('default scene filtering remains unchanged without governance matrix',
      () {
    final definitions = AiToolRegistry.definitionsForScene(
      AiToolRegistry.defaultEnabledToolIds(),
      AiToolScene.reading,
    );

    final ids = definitions.map((definition) => definition.id).toSet();
    expect(ids, contains('semantic_search_current_book'));
    expect(ids, contains('create_note'));
    expect(ids, contains('web_search'));
    expect(ids, isNot(contains('bookshelf_lookup')));
  });

  test('seminar governance keeps read tools and excludes write/web tools', () {
    final definitions = AiToolRegistry.definitionsForScene(
      AiToolRegistry.defaultEnabledToolIds(),
      AiToolScene.reading,
      permissionMatrix: AiToolPermissionMatrix.defaultMatrix,
      agentScene: AiAgentScene.seminar,
    );

    final ids = definitions.map((definition) => definition.id).toSet();
    expect(ids, contains('current_reading_metadata'));
    expect(ids, contains('semantic_search_current_book'));
    expect(ids, isNot(contains('semantic_search_library')));
    expect(ids, contains('spawn_sub_agent'));
    expect(ids, isNot(contains('create_note')));
    expect(ids, isNot(contains('create_highlight')));
    expect(ids, isNot(contains('web_search')));
  });

  test('seminar library fallback is only selected outside reader context', () {
    final definitions = AiToolRegistry.definitionsForScene(
      AiToolRegistry.defaultEnabledToolIds(),
      AiToolScene.library,
      permissionMatrix: AiToolPermissionMatrix.seminarLibraryFallbackMatrix,
      agentScene: AiAgentScene.seminar,
    );

    final ids = definitions.map((definition) => definition.id).toSet();
    expect(ids, contains('semantic_search_library'));
    expect(ids, isNot(contains('semantic_search_current_book')));
    expect(ids, isNot(contains('web_search')));
  });

  test('sanitizeIdsForAgentScene applies the permission matrix', () {
    final ids = AiToolRegistry.sanitizeIdsForAgentScene(
      [
        'semantic_search_current_book',
        'create_note',
        'web_search',
        'unknown_tool',
      ],
      AiAgentScene.seminar,
    );

    expect(ids, ['semantic_search_current_book']);
  });

  test('governance can further restrict concurrency safety', () {
    const matrix = AiToolPermissionMatrix([
      AiToolPermissionRule(
        toolId: 'semantic_search_current_book',
        scenes: {AiAgentScene.seminar},
        concurrencySafe: false,
      ),
    ]);

    expect(
      AiToolRegistry.isConcurrencySafeForId(
        'semantic_search_current_book',
        permissionMatrix: matrix,
      ),
      isFalse,
    );
    expect(AiToolRegistry.isConcurrencySafeForId('calculator'), isTrue);
  });
}
