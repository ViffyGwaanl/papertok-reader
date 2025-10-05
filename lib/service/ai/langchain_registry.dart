import 'package:langchain_anthropic/langchain_anthropic.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:langchain_core/tools.dart';
import 'package:langchain_google/langchain_google.dart';
import 'package:langchain_openai/langchain_openai.dart';

import 'langchain_ai_config.dart';
import 'repository/books_repository.dart';
import 'repository/notes_repository.dart';
import 'tools/bookshelf_lookup_tool.dart';
import 'tools/calculator_tool.dart';
import 'tools/current_time_tool.dart';
import 'tools/notes_search_tool.dart';

/// Factory responsible for building chat models based on user preferences.
class LangchainAiRegistry {
  const LangchainAiRegistry();

  LangchainPipeline resolve(
    LangchainAiConfig config, {
    bool useAgent = false,
  }) {
    switch (config.identifier) {
      case 'claude':
        return _buildPipeline(
          config,
          _buildAnthropic(config),
          useAgent: useAgent,
        );
      case 'gemini':
        return _buildPipeline(
          config,
          _buildGoogle(config),
          useAgent: useAgent,
        );
      case 'deepseek':
      case 'openrouter':
      case 'openai':
      default:
        return _buildPipeline(
          config,
          _buildOpenAi(config),
          useAgent: useAgent,
        );
    }
  }

  BaseChatModel _buildOpenAi(LangchainAiConfig config) {
    return ChatOpenAI(
      apiKey: config.apiKey.isEmpty ? null : config.apiKey,
      baseUrl: config.baseUrl ?? 'https://api.openai.com/v1',
      headers: config.headers.isEmpty ? null : config.headers,
      defaultOptions: config.toOpenAIOptions(),
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
    return ChatGoogleGenerativeAI(
      apiKey: config.apiKey.isEmpty ? null : config.apiKey,
      baseUrl: config.baseUrl,
      headers: config.headers.isEmpty ? null : config.headers,
      defaultOptions: config.toGoogleOptions(),
    );
  }

  LangchainPipeline _buildPipeline(
    LangchainAiConfig config,
    BaseChatModel model, {
    required bool useAgent,
  }) {
    final tools = useAgent ? _buildTools(config) : const <Tool>[];
    final systemMessage = useAgent ? _buildAgentSystemMessage() : null;
    return LangchainPipeline(
      model: model,
      tools: tools,
      systemMessage: systemMessage,
    );
  }

  List<Tool> _buildTools(LangchainAiConfig config) {
    final notesRepository = NotesRepository();
    final booksRepository = BooksRepository();

    return [
      calculatorTool,
      NotesSearchTool(notesRepository).tool,
      BookshelfLookupTool(booksRepository).tool,
      currentTimeTool,
    ];
  }

  ChatMessage _buildAgentSystemMessage() {
    const guidance = '''You are the Anx Reader assistant. When users ask for help:
- Use `notes_search` to retrieve highlights or annotations. Include book title, chapter, and a concise snippet when summarising results.
- Use `bookshelf_lookup` to inspect the user\'s library (title, author, progress). Combine with other knowledge to answer queries about available books.
- Use `calculator` only for arithmetic operations.
- Use `current_time` when the user needs the current date or time. Prefer local time but mention UTC when relevant.
If a tool returns no data, explain that to the user and suggest next steps.''';

    return ChatMessage.system(guidance);
  }
}

class LangchainPipeline {
  const LangchainPipeline({
    required this.model,
    required this.tools,
    this.systemMessage,
  });

  final BaseChatModel model;
  final List<Tool> tools;
  final ChatMessage? systemMessage;
}
