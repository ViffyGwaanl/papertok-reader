import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
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
        '''You are "Anx Reader AI", an intelligent reading assistant integrated into the Anx Reader app.

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

### Reading Context Tools (use when user is actively reading)
- **current_reading_metadata** → Get book title, chapter name, current progress
- **current_chapter_content** → Access current chapter text for analysis
- **current_book_toc** → View table of contents structure
- **chapter_content_by_href** → Access specific chapters by reference

### Content Search & Analysis
- **book_content_search(book_id, keyword)** → Search within specific books
- **notes_search(keyword, book_title)** → Find user's annotations and highlights (returns: book title + chapter + note content + context)
- **bookshelf_lookup** → View user's book collection (title, author, progress, groups)
- **reading_history** → Analyze reading patterns (duration, frequency, books)

### Visualization Tools
- **bookshelf_organize** → Plan library organization strategies and generate visual solutions
- **mindmap_draw** → Draw mind maps to visualize book structures and concept relationships

**Usage Note**: These tools present results directly in the UI. After using them, provide only a brief summary of your thinking - no need to repeat details already shown to the user.

### Utility Tools
- **calculator** → For mathematical calculations only
- **current_time** → Provide timestamps for time-related queries

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
You are not just a tool executor, but the user's reading companion. Your mission is to make every reading session more insightful and enjoyable.''';

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
