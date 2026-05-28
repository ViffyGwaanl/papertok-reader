import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/agents.dart';
import 'package:langchain_core/tools.dart';
import 'package:papertok_reader/models/ai_agent_governance.dart';
import 'package:papertok_reader/service/ai/tool_orchestrator.dart';

void main() {
  Tool fakeTool(String name) => Tool.fromFunction<Map<String, dynamic>, String>(
        name: name,
        description: name,
        inputJsonSchema: const {'type': 'object'},
        func: (_) => 'ok',
      );

  AgentAction action(String id, String tool) => AgentAction(
        id: id,
        tool: tool,
        toolInput: const <String, dynamic>{},
      );

  test('permission matrix concurrency rule affects execution batching',
      () async {
    const matrix = AiToolPermissionMatrix([
      AiToolPermissionRule(
        toolId: 'calculator',
        scenes: {AiAgentScene.seminar},
        concurrencySafe: false,
      ),
    ]);
    final orchestrator = ToolOrchestrator(permissionMatrix: matrix);
    var active = 0;
    var maxActive = 0;

    final results = await orchestrator.execute(
      [
        action('a1', 'calculator'),
        action('a2', 'calculator'),
      ],
      {'calculator': fakeTool('calculator')},
      (_, __) async {
        active += 1;
        if (active > maxActive) maxActive = active;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        active -= 1;
        return 'ok';
      },
    ).toList();

    expect(results, hasLength(2));
    expect(results.every((result) => !result.isError), true);
    expect(maxActive, 1);
  });
}
