import 'dart:io';

import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/enums/ai_thinking_mode.dart';
import 'package:papertok_reader/enums/ai_tool_scene.dart';
import 'package:papertok_reader/models/ai_agent_governance.dart';
import 'package:papertok_reader/providers/current_reading.dart';
import 'package:papertok_reader/service/ai/annotation_ledger.dart';
import 'package:papertok_reader/service/ai/skills/ai_skill.dart';
import 'package:papertok_reader/service/ai/skills/ai_skill_registry.dart';
import 'package:papertok_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:papertok_reader/service/mcp/mcp_tool_registry.dart';
import 'package:riverpod/riverpod.dart';
import 'package:langchain_anthropic/langchain_anthropic.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:langchain_core/tools.dart';
import 'package:langchain_openai/langchain_openai.dart';

import 'chat_deepseek.dart';
import 'gemini_chat_with_thinking.dart';
import 'openai_responses_chat_model.dart';

import 'langchain_ai_config.dart';

/// Factory responsible for building chat models based on user preferences.
class LangchainAiRegistry {
  const LangchainAiRegistry(this.ref);
  final Ref? ref;

  LangchainPipeline resolve(
    LangchainAiConfig config, {
    bool useAgent = false,
    AnnotationLedger? annotationLedger,
  }) {
    switch (config.identifier) {
      case 'claude':
        return _buildPipeline(
          config,
          _buildAnthropic(config),
          useAgent: useAgent,
          annotationLedger: annotationLedger,
        );
      case 'gemini':
        return _buildPipeline(
          config,
          _buildGoogle(config),
          useAgent: useAgent,
          annotationLedger: annotationLedger,
        );
      case 'openai-responses':
        return _buildPipeline(
          config,
          _buildOpenAiResponses(config),
          useAgent: useAgent,
          annotationLedger: annotationLedger,
        );
      case 'deepseek':
        return _buildPipeline(
          config,
          _buildDeepSeek(config),
          useAgent: useAgent,
          annotationLedger: annotationLedger,
        );
      case 'openrouter':
      case 'openai':
      default:
        return _buildPipeline(
          config,
          _buildOpenAi(config),
          useAgent: useAgent,
          annotationLedger: annotationLedger,
        );
    }
  }

  BaseChatModel _buildDeepSeek(LangchainAiConfig config) {
    return ChatDeepSeek(
      apiKey: config.apiKey,
      baseUrl: config.baseUrl,
      headers: config.headers.isEmpty ? null : config.headers,
      defaultOptions: config.toOpenAIOptions(),
    );
  }

  BaseChatModel _buildOpenAi(LangchainAiConfig config) {
    return ChatOpenAI(
      apiKey: config.apiKey.isEmpty ? null : config.apiKey,
      baseUrl: config.baseUrl ?? 'https://api.openai.com/v1',
      headers: config.headers.isEmpty ? null : config.headers,
      defaultOptions: config.toOpenAIOptions(),
    );
  }

  BaseChatModel _buildOpenAiResponses(LangchainAiConfig config) {
    // For Responses API, we treat `auto` as a reasonable default effort.
    // This affects request-side behavior only.
    final defaultOptions = config.toOpenAIOptions();
    final patchedOptions = (config.thinkingMode == AiThinkingMode.auto &&
            defaultOptions.reasoningEffort == null)
        ? defaultOptions.copyWith(
            reasoningEffort: ChatOpenAIReasoningEffort.medium,
          )
        : defaultOptions;

    final usePreviousResponseId = config.responsesUsePreviousResponseId ?? true;
    final requestReasoningSummary =
        config.responsesRequestReasoningSummary ?? usePreviousResponseId;

    return ChatOpenAIResponses(
      apiKey: config.apiKey,
      baseUrl: config.baseUrl ?? 'https://api.openai.com/v1',
      headers: config.headers.isEmpty ? null : config.headers,
      usePreviousResponseId: usePreviousResponseId,
      requestReasoningSummary: requestReasoningSummary,
      defaultOptions: patchedOptions,
    );
  }

  BaseChatModel _buildAnthropic(LangchainAiConfig config) {
    return ChatAnthropic(
      apiKey: config.apiKey.isEmpty ? null : config.apiKey,
      baseUrl: config.baseUrl ?? 'https://api.anthropic.com/v1',
      headers: config.headers.isEmpty ? null : config.headers,
      defaultOptions: config.toAnthropicOptions(),
    );
  }

  BaseChatModel _buildGoogle(LangchainAiConfig config) {
    return ChatGoogleGenerativeAIWithThinking(
      apiKey: config.apiKey.isEmpty ? null : config.apiKey,
      baseUrl: config.baseUrl,
      headers: config.headers.isEmpty ? null : config.headers,
      defaultOptions: config.toGoogleOptions(),
      thinkingMode: config.thinkingMode,
      includeThoughts: config.includeThoughts,
    );
  }

  LangchainPipeline _buildPipeline(
    LangchainAiConfig config,
    BaseChatModel model, {
    required bool useAgent,
    AnnotationLedger? annotationLedger,
  }) {
    if (useAgent) {
      assert(ref != null, 'ref must be provided when useAgent is true');
    }

    final isReading =
        useAgent && ref != null && ref!.read(currentReadingProvider).isReading;
    final scene = isReading ? AiToolScene.reading : AiToolScene.library;

    var tools = const <Tool>[];
    ChatMessage? systemMessage;
    AiToolPermissionMatrix? permissionMatrix;
    AiAgentScene? agentScene;

    if (useAgent) {
      final enabledIds = Prefs().enabledAiToolIds;
      final activeSkillId = Prefs().activeAiSkillId;
      final activeSkill = AiSkillRegistry.byId(activeSkillId);
      final activeAgentScene = agentSceneFor(
        toolScene: scene,
        activeSkill: activeSkill,
      );
      agentScene = activeAgentScene;
      permissionMatrix = isSeminarSkill(activeSkill)
          ? seminarPermissionMatrixFor(toolScene: scene)
          : null;
      final toolContext = AiToolContext(
        ref: ref!,
        externalAnnotationLedger: annotationLedger,
        agentSceneOverride: activeAgentScene,
        toolPermissionMatrix: permissionMatrix,
      );

      // Scene-aware filtering: only include tools relevant to the
      // current context (reading vs library), plus global tools.
      final baseTools = AiToolRegistry.buildToolsForScene(
        toolContext,
        enabledIds,
        scene,
        permissionMatrix: permissionMatrix,
        agentScene: activeAgentScene,
      );

      final mcp = shouldIncludeMcpTools(activeAgentScene)
          ? McpToolRegistry.buildCachedTools()
          : (tools: const <Tool>[], descriptors: const <McpToolDescriptor>[]);
      // Sort tools alphabetically by name for stable prompt cache hits.
      // When the tool list is identical across requests, LLM providers
      // (Anthropic, OpenAI) can reuse cached system prompt tokens.
      tools = <Tool>[...baseTools, ...mcp.tools]
        ..sort((a, b) => a.name.compareTo(b.name));

      final enabledDefs = AiToolRegistry.definitionsForScene(
        enabledIds,
        scene,
        permissionMatrix: permissionMatrix,
        agentScene: activeAgentScene,
      );

      systemMessage = _buildAgentSystemMessage(
        isReading: isReading,
        enabledTools: enabledDefs,
        mcpTools: mcp.descriptors,
        annotationLedger: toolContext.annotationLedger,
        activeSkill: activeSkill,
      );
    }

    return LangchainPipeline(
      model: model,
      tools: tools,
      systemMessage: systemMessage,
      permissionMatrix: permissionMatrix,
      agentScene: agentScene,
    );
  }

  static bool isSeminarSkill(AiSkill? activeSkill) =>
      activeSkill?.id == 'seminar_mode';

  static AiAgentScene agentSceneFor({
    required AiToolScene toolScene,
    AiSkill? activeSkill,
  }) {
    if (isSeminarSkill(activeSkill)) return AiAgentScene.seminar;
    return AiToolRegistry.agentSceneForToolScene(toolScene);
  }

  static bool shouldIncludeMcpTools(AiAgentScene agentScene) {
    return agentScene != AiAgentScene.seminar;
  }

  static AiToolPermissionMatrix seminarPermissionMatrixFor({
    required AiToolScene toolScene,
  }) {
    return switch (toolScene) {
      AiToolScene.library =>
        AiToolPermissionMatrix.seminarLibraryFallbackMatrix,
      AiToolScene.reading => AiToolPermissionMatrix.defaultMatrix,
      AiToolScene.system ||
      AiToolScene.global =>
        AiToolPermissionMatrix.defaultMatrix,
    };
  }

  ChatMessage _buildAgentSystemMessage({
    required bool isReading,
    required List<AiToolDefinition> enabledTools,
    required List<McpToolDescriptor> mcpTools,
    AnnotationLedger? annotationLedger,
    AiSkill? activeSkill,
  }) {
    final currentLanguageCode =
        Prefs().locale?.languageCode ?? Platform.localeName;

    // Map language code to language name
    final languageMap = {
      'zh': '简体中文',
      'zh-CN': '简体中文',
      'zh-Hans': '简体中文',
      'zh-TW': '繁體中文',
      'zh-Hant': '繁體中文',
      'en': 'English',
      'ja': '日本語',
      'ko': '한국어',
      'fr': 'Français',
      'de': 'Deutsch',
      'es': 'Español',
      'ru': 'Русский',
      'ar': 'العربية',
      'tr': 'Türkçe',
    };

    final languageName = languageMap[currentLanguageCode] ??
        languageMap[currentLanguageCode.split('_').first] ??
        currentLanguageCode;

    final readingStateContext = isReading
        ? '📖 User is currently reading - You are a focused reading companion, providing instant comprehension help, translation, and note-taking assistance.'
        : '📚 User is browsing the library - You are a wise librarian, helping organize books and plan reading strategies.';

    final guidance =
        '''You are "Paper Reader AI", an intelligent reading assistant integrated into the Paper Reader app.

## Your Role
A knowledgeable reading companion who helps users understand, organize, and enjoy their reading experience through intelligent tool usage and thoughtful insights.

## Current Context
$readingStateContext

## Tool Usage Principles
1. **Gather context first** - Use tools to understand the situation before responding
2. **Combine tools efficiently** - Use multiple tools in parallel or sequence when needed
3. **Prioritize specific tools** - When user is reading, prefer current_* series tools over general search
4. **Be transparent** - Briefly explain your reasoning when using complex tool combinations

## Available Tools & Usage Scenarios
${_formatToolCatalog(enabledTools)}

${_formatMcpToolCatalog(mcpTools)}

## Response Strategy

### When answering user queries:
1. **Understand intent** - What does the user really want?
2. **Gather data** - Use tools to collect relevant information
3. **Synthesize** - Connect information pieces into coherent insights
4. **Deliver value** - Provide actionable suggestions or clear answers

### Communication Style:
- **Concise yet complete** - No unnecessary elaboration
- **Evidence-based** - Reference specific content from tool results
- **Context-adaptive** - Adjust tone based on reading state
- **Reasonable defaults** - When ambiguous, proactively ask for clarification
- **Language consistency** - Unless the user explicitly uses another language, always respond in **$languageName**, regardless of the language used in their question

### Markdown Example

You can use Markdown to format text easily. Here are some examples:

- **Bold Text**: **This text is bold**
- *Italic Text*: *This text is italicized*
- [Link](https://www.example.com): [This is a link](https://www.example.com)
- Lists:
  1. Item 1
  2. Item 2
  3. Item 3

### LaTeX Example

You can also use LaTeX for mathematical expressions. Here's an example:

- **Equation**: \\( f(x) = x^2 + 2x + 1 \\)
- **Integral**: \\( \\int_{0}^{1} x^2 \\, dx \\)
- **Matrix**:

\\[
\\begin{bmatrix}
1 & 2 & 3 \\\\
4 & 5 & 6 \\\\
7 & 8 & 9
\\end{bmatrix}
\\]


## Error Handling
- **No results** → Suggest alternative search strategies or verify book/chapter context
- **Tool failure** → Acknowledge the issue and try alternative approaches
- **Out of scope** → Clearly state limitations and suggest manual alternatives

## Important Constraints
- Respect user privacy - only access data through provided tools
- Stay focused on reading-related assistance
- Don't make assumptions about unavailable data
- Use the user's language for responses

## Remember
You are not just a tool executor, but the user's reading companion. Your mission is to make every reading session more insightful and enjoyable.
${activeSkill?.systemPromptAppend ?? ''}${annotationLedger?.toSystemPromptSection() ?? ''}''';

    return ChatMessage.system(guidance);
  }

  String _formatToolCatalog(List<AiToolDefinition> enabledTools) {
    if (enabledTools.isEmpty) {
      return '_No tools are currently enabled by the user._';
    }
    return enabledTools
        .map(
          (tool) =>
              '- **${tool.displayNameOrDefault()}** → ${tool.descriptionOrDefault()}',
        )
        .join('\n');
  }

  String _formatMcpToolCatalog(List<McpToolDescriptor> tools) {
    if (tools.isEmpty) {
      return '_No external MCP tools are available (refresh tools in Settings → AI Tools → MCP Servers)._';
    }

    const maxLines = 25;
    final items = tools.take(maxLines).toList(growable: false);

    final lines = items
        .map(
          (t) =>
              '- **${t.toolName}** → ${t.serverName} · ${t.displayName}${t.description.trim().isEmpty ? '' : ' — ${t.description.trim()}'}',
        )
        .join('\n');

    final truncated = tools.length > maxLines
        ? '\n_(${tools.length - maxLines} more MCP tools not shown...)_'
        : '';

    return '### External MCP Tools\n$lines$truncated';
  }
}

class LangchainPipeline {
  const LangchainPipeline({
    required this.model,
    required this.tools,
    this.systemMessage,
    this.permissionMatrix,
    this.agentScene,
  });

  final BaseChatModel model;
  final List<Tool> tools;
  final ChatMessage? systemMessage;
  final AiToolPermissionMatrix? permissionMatrix;
  final AiAgentScene? agentScene;
}
