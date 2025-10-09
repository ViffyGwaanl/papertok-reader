import 'package:anx_reader/providers/current_reading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:langchain_anthropic/langchain_anthropic.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:langchain_core/tools.dart';
import 'package:langchain_google/langchain_google.dart';
import 'package:langchain_openai/langchain_openai.dart';

import 'langchain_ai_config.dart';
import 'tools/bookshelf_lookup_tool.dart';
import 'tools/bookshelf_organize_tool.dart';
import 'tools/calculator_tool.dart';
import 'tools/chapter_content_by_href_tool.dart';
import 'tools/current_book_toc_tool.dart';
import 'tools/current_chapter_content_tool.dart';
import 'tools/current_reading_metadata_tool.dart';
import 'tools/current_time_tool.dart';
import 'tools/notes_search_tool.dart';
import 'tools/reading_history_tool.dart';
import 'tools/repository/books_repository.dart';
import 'tools/repository/groups_repository.dart';
import 'tools/repository/notes_repository.dart';
import 'tools/repository/reading_history_repository.dart';

/// Factory responsible for building chat models based on user preferences.
class LangchainAiRegistry {
  const LangchainAiRegistry(this.ref);
  final WidgetRef? ref;

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
    if (useAgent) {
      assert(ref != null, 'ref must be provided when useAgent is true');
    }

    final isReading =
        ref != null && ref!.read(currentReadingProvider).isReading;

    final tools =
        useAgent ? _buildTools(config, isReading, ref!) : const <Tool>[];
    final systemMessage = useAgent ? _buildAgentSystemMessage(isReading) : null;
    return LangchainPipeline(
      model: model,
      tools: tools,
      systemMessage: systemMessage,
    );
  }

  List<Tool> _buildTools(
      LangchainAiConfig config, bool isReading, WidgetRef ref) {
    final notesRepository = NotesRepository();
    final booksRepository = BooksRepository();
    final groupsRepository = GroupsRepository();
    final historyRepository = ReadingHistoryRepository();

    return [
      calculatorTool,
      NotesSearchTool(notesRepository).tool,
      BookshelfLookupTool(booksRepository).tool,
      BookshelfOrganizeTool(booksRepository, groupsRepository).tool,
      currentTimeTool,
      ReadingHistoryTool(historyRepository).tool,
      // if (isReading && ref != null) ...[
      currentReadingMetadataTool(ref),
      currentBookTocTool(ref),
      currentChapterContentTool(ref),
      chapterContentByHrefTool(ref),
      // ],
    ];
  }

  ChatMessage _buildAgentSystemMessage(bool isReading) {

    final guidance =
        '''You are the Anx Reader assistant. When users ask for help:
- Use `notes_search` to retrieve highlights or annotations. Include book title, chapter, and a concise snippet when summarising results.
- Use `bookshelf_lookup` to inspect the user's library (title, author, progress). Combine with other knowledge to answer queries about available books.
- Use `bookshelf_organize` to draft regrouping plans. 
- Use `calculator` only for arithmetic operations.
- Use `current_time` when the user needs the current date or time. Prefer local time but mention UTC when relevant.
- Use `reading_history` to summarise or retrieve reading sessions; mention total minutes and relevant books.
- Use `current_reading_metadata` to inspect the reader's active book, chapter, and progress before giving guidance about the current session.
- Use `current_book_toc` to understand the table of contents and plan navigation.
- Use `current_chapter_content` to retrieve the text of the chapter the reader currently has open.
- Use `chapter_content_by_href` to fetch the text of another chapter by its href when additional context is required.
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
