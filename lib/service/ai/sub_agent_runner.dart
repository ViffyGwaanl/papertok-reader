import 'dart:async';

import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/service/ai/langchain_ai_config.dart';
import 'package:papertok_reader/service/ai/langchain_registry.dart';
import 'package:papertok_reader/service/ai/langchain_runner.dart';
import 'package:papertok_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:papertok_reader/utils/log/common.dart';
import 'package:langchain_core/chat_models.dart';

/// Runs a lightweight sub-agent with isolated context and restricted tools.
///
/// Sub-agents cannot spawn further sub-agents (prevents infinite recursion)
/// and have no UI approval delegate (auto-approve read-only tools).
class SubAgentRunner {
  const SubAgentRunner._();

  /// Tool IDs available to each agent type.
  static const _agentToolSets = <String, List<String>>{
    'research': [
      'web_search',
      'fetch_url',
      'book_content_search',
      'semantic_search_current_book',
      'current_reading_metadata',
    ],
    'summarize': [
      'current_chapter_content',
      'chapter_content_by_href',
      'current_book_toc',
      'current_reading_metadata',
      'current_book_fulltext',
    ],
    'verify': [
      'book_content_search',
      'semantic_search_current_book',
      'chapter_content_by_href',
      'notes_search',
      'fetch_url',
    ],
  };

  /// Runs a sub-agent with the given [task] and returns its final output text.
  ///
  /// [agentType]: one of 'research', 'summarize', 'verify'.
  /// [maxSteps]: maximum tool-use iterations (1-15, default 8).
  /// [toolContext]: shared tool context from the parent agent.
  static Future<String> run({
    required String task,
    required String agentType,
    required AiToolContext toolContext,
    int maxSteps = 8,
  }) async {
    final type = _agentToolSets.containsKey(agentType) ? agentType : 'research';
    final toolIds = _agentToolSets[type]!;

    AnxLog.info('SubAgent: starting type=$type task="${_truncate(task, 80)}" '
        'maxSteps=$maxSteps tools=${toolIds.length}');

    // Build model from current config (same provider as parent).
    final serviceId = Prefs().selectedAiService;
    final config = Prefs().getAiConfig(serviceId);
    final providerMeta = Prefs().getAiProviderMeta(serviceId);
    final registryId =
        LangchainAiConfig.registryIdentifierForProvider(providerMeta);
    final langConfig = LangchainAiConfig.fromPrefs(registryId, config);

    final registry = LangchainAiRegistry(toolContext.ref);
    final pipeline = registry.resolve(langConfig);

    // Build restricted tool set (no spawn_sub_agent to prevent recursion).
    final tools = AiToolRegistry.buildTools(toolContext, toolIds);

    // Create isolated runner with no approval delegate.
    final runner = CancelableLangchainRunner();

    final systemPrompt = ChatMessage.system(
      'You are a focused sub-agent of type "$type". '
      'Your sole task: $task\n\n'
      'Rules:\n'
      '- Complete the task efficiently using available tools.\n'
      '- Return a clear, structured answer.\n'
      '- Do NOT ask the user questions — gather info via tools.\n'
      '- Do NOT create/modify user data (highlights, notes, etc.).\n',
    );

    // Accumulate all stream output.
    final buffer = StringBuffer();
    final stream = runner.streamAgent(
      model: pipeline.model,
      tools: tools,
      history: const [],
      inputMessage: ChatMessage.humanText(task) as HumanChatMessage,
      systemMessage: systemPrompt,
      maxIterations: maxSteps.clamp(1, 15),
    );

    try {
      await for (final chunk in stream) {
        buffer.clear();
        buffer.write(chunk);
      }
    } catch (e) {
      AnxLog.warning('SubAgent: execution error: $e');
      if (buffer.isEmpty) {
        return 'Sub-agent error: $e';
      }
    }

    final result = buffer.toString().trim();
    AnxLog.info(
        'SubAgent: completed type=$type resultLen=${result.length}');
    return result.isEmpty ? 'Sub-agent produced no output.' : result;
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}...';
}
