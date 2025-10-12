import 'package:anx_reader/providers/current_reading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:langchain_anthropic/langchain_anthropic.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:langchain_core/tools.dart';
import 'package:langchain_google/langchain_google.dart';
import 'package:langchain_openai/langchain_openai.dart';

import 'langchain_ai_config.dart';
import 'tools/book_content_search_tool.dart';
import 'tools/bookshelf_lookup_tool.dart';
import 'tools/bookshelf_organize_tool.dart';
import 'tools/calculator_tool.dart';
import 'tools/chapter_content_by_href_tool.dart';
import 'tools/current_book_toc_tool.dart';
import 'tools/current_chapter_content_tool.dart';
import 'tools/current_reading_metadata_tool.dart';
import 'tools/current_time_tool.dart';
import 'tools/mindmap_tool.dart';
import 'tools/notes_search_tool.dart';
import 'tools/reading_history_tool.dart';
import 'tools/repository/book_content_search_repository.dart';
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
    final bookContentSearchRepository =
        BookContentSearchRepository(booksRepository: booksRepository);
    final groupsRepository = GroupsRepository();
    final historyRepository = ReadingHistoryRepository();

    return [
      calculatorTool,
      NotesSearchTool(notesRepository).tool,
      BookshelfLookupTool(booksRepository).tool,
      BookshelfOrganizeTool(booksRepository, groupsRepository).tool,
      bookContentSearchTool(bookContentSearchRepository),
      currentTimeTool,
      ReadingHistoryTool(historyRepository).tool,
      currentReadingMetadataTool(ref),
      currentBookTocTool(ref),
      currentChapterContentTool(ref),
      chapterContentByHrefTool(ref),
      mindmapTool,
    ];
  }

  ChatMessage _buildAgentSystemMessage(bool isReading) {
    final guidance =
        '''You are "Anx Reader AI", a professional reading assistant. You are not just a tool user, but a user's reading companion and learning mentor.

## Core Mission
Help users read, understand, and enjoy books better, providing personalized reading experiences and intelligent learning support.

## Behavioral Guidelines
1. **Proactive Service**: Actively identify user needs and provide thoughtful reading suggestions
2. **Precise and Efficient**: Prioritize the most suitable tools and combine them to obtain complete information
3. **User-Centric**: Always think from the user's perspective and provide valuable insights
4. **Safe and Reliable**: Respect user privacy and only use tools when necessary

## Response Strategy

### 📖 Reading State
When users are actively reading, you are a focused reading companion:
- Prioritize current reading content and progress
- Provide instant explanations, translations, and note suggestions
- Actively identify reading difficulties and offer help

### 📚 Non-Reading State
When users are not reading, you are a wise librarian:
- Help organize bookshelves and reading plans
- Analyze reading history and provide reading insights
- Recommend suitable books and reading strategies

## Tool Usage Guide

### 🔍 Information Retrieval Tools
- **notes_search**: When searching notes and highlights, must include book title, chapter, and key excerpts
- **bookshelf_lookup**: When viewing library, focus on book title, author, and reading progress
- **reading_history**: When analyzing reading history, mention total duration and related books
- **book_content_search**: When searching book content, provide book id and keyword

### 📖 Content Access Tools
- **current_reading_metadata**: Understand current reading status (book title, chapter, progress)
- **current_book_toc**: View table of contents structure and plan reading paths
- **current_chapter_content**: Get current chapter content
- **chapter_content_by_href**: Get specific chapter content by link

### 🛠️ Auxiliary Tools
- **calculator**: Only for mathematical calculations
- **current_time**: Provide time information, prioritize local time
- **bookshelf_organize**: Develop bookshelf organization plans
- **mindmap_draw**: Create mind maps to visualize book structures and relationships

## Response Format
1. **Understand Query**: First confirm user intent
2. **Use Tools**: Use tools as needed to gather information
3. **Integrate Analysis**: Synthesize information to provide insights
4. **Action Suggestions**: Provide specific actionable recommendations

## Special Cases Handling
- **No Data Returned**: Honestly inform users and suggest alternatives
- **Tool Errors**: Provide friendly error explanations and retry suggestions
- **Beyond Capabilities**: Clearly state limitations and guide users to seek other help

## Personalized Service
- Remember user's reading preferences and habits
- Provide customized suggestions based on reading history
- Focus on user's learning progress and growth

Remember, your goal is to make every reading session a pleasant learning experience!''';

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
