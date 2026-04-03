import 'package:anx_reader/enums/ai_tool_risk_level.dart';
import 'package:anx_reader/enums/ai_tool_scene.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/current_reading.dart';
import 'package:anx_reader/service/ai/annotation_ledger.dart';
import 'package:anx_reader/service/ai/book_content_cache.dart';
import 'package:anx_reader/service/ai/tools/apply_book_tags_tool.dart';
import 'package:anx_reader/service/ai/tools/book_content_search_tool.dart';
import 'package:anx_reader/service/ai/tools/create_highlight_tool.dart';
import 'package:anx_reader/service/ai/tools/create_note_tool.dart';
import 'package:anx_reader/service/ai/tools/books_tags_list_tool.dart';
import 'package:anx_reader/service/ai/tools/bookshelf_lookup_tool.dart';
import 'package:anx_reader/service/ai/tools/bookshelf_organize_tool.dart';
import 'package:anx_reader/service/ai/tools/calculator_tool.dart';
import 'package:anx_reader/service/ai/tools/calendar_create_event_tool.dart';
import 'package:anx_reader/service/ai/tools/calendar_delete_event_tool.dart';
import 'package:anx_reader/service/ai/tools/calendar_get_event_tool.dart';
import 'package:anx_reader/service/ai/tools/calendar_list_calendars_tool.dart';
import 'package:anx_reader/service/ai/tools/calendar_list_events_tool.dart';
import 'package:anx_reader/service/ai/tools/calendar_update_event_tool.dart';
import 'package:anx_reader/service/ai/tools/chapter_content_by_href_tool.dart';
import 'package:anx_reader/service/ai/tools/current_book_toc_tool.dart';
import 'package:anx_reader/service/ai/tools/current_chapter_content_tool.dart';
import 'package:anx_reader/service/ai/tools/resolve_cfi_tool.dart';
import 'package:anx_reader/service/ai/tools/current_book_fulltext_tool.dart';
import 'package:anx_reader/service/ai/tools/semantic_search_current_book_tool.dart';
import 'package:anx_reader/service/ai/tools/semantic_search_library_tool.dart';
import 'package:anx_reader/service/ai/tools/current_reading_metadata_tool.dart';
import 'package:anx_reader/service/ai/tools/current_time_tool.dart';
import 'package:anx_reader/service/ai/tools/fetch_url_tool.dart';
import 'package:anx_reader/service/ai/tools/mindmap_tool.dart';
import 'package:anx_reader/service/ai/tools/notes_search_tool.dart';
import 'package:anx_reader/service/ai/tools/memory_tools.dart';
import 'package:anx_reader/service/ai/tools/reminders_create_list_tool.dart';
import 'package:anx_reader/service/ai/tools/reminders_create_tool.dart';
import 'package:anx_reader/service/ai/tools/reminders_delete_list_tool.dart';
import 'package:anx_reader/service/ai/tools/reminders_delete_tool.dart';
import 'package:anx_reader/service/ai/tools/reminders_get_tool.dart';
import 'package:anx_reader/service/ai/tools/reminders_list_lists_tool.dart';
import 'package:anx_reader/service/ai/tools/reminders_list_tool.dart';
import 'package:anx_reader/service/ai/tools/reminders_rename_list_tool.dart';
import 'package:anx_reader/service/ai/tools/reminders_complete_tool.dart';
import 'package:anx_reader/service/ai/tools/reminders_uncomplete_tool.dart';
import 'package:anx_reader/service/ai/tools/reminders_update_tool.dart';
import 'package:anx_reader/service/ai/tools/shortcuts_run_tool.dart';
import 'package:anx_reader/service/ai/tools/reading_history_tool.dart';
import 'package:anx_reader/service/ai/tools/spawn_sub_agent_tool.dart';
import 'package:anx_reader/service/ai/tools/tags_list_tool.dart';
import 'package:anx_reader/service/ai/tools/web_search_tool.dart';
import 'package:anx_reader/service/ai/tools/repository/book_content_search_repository.dart';
import 'package:anx_reader/service/ai/tools/repository/books_repository.dart';
import 'package:anx_reader/service/ai/tools/repository/groups_repository.dart';
import 'package:anx_reader/service/ai/tools/repository/notes_repository.dart';
import 'package:anx_reader/service/ai/tools/repository/reading_history_repository.dart';
import 'package:anx_reader/service/ai/tools/repository/tag_repository.dart';
import 'package:riverpod/riverpod.dart';
import 'package:langchain_core/tools.dart';

/// Context object shared by AI tools so builders don't need long constructors.
///
/// Centralises reading state so that individual tools do not need to reach
/// into Riverpod providers themselves, improving testability and reducing
/// coupling between tools and Flutter state management.
class AiToolContext {
  AiToolContext({
    required this.ref,
    this.currentBookId,
    this.currentBookTitle,
    this.currentChapterId,
    this.currentChapterTitle,
    this.currentPageNumber,
    this.selectedText,
    this.conversationId,
    this.locale,
    AnnotationLedger? externalAnnotationLedger,
  }) : _externalAnnotationLedger = externalAnnotationLedger;

  final Ref ref;

  /// ID of the book currently open in the reader (null when not reading).
  final String? currentBookId;

  /// Title of the book currently open in the reader.
  final String? currentBookTitle;

  /// ID of the chapter visible on screen.
  final String? currentChapterId;

  /// Title of the chapter visible on screen.
  final String? currentChapterTitle;

  /// Current page number (if available).
  final int? currentPageNumber;

  /// Text the user has selected/highlighted in the reader.
  final String? selectedText;

  /// Active conversation session ID.
  final String? conversationId;

  /// User's locale code (e.g. 'zh-CN', 'en').
  final String? locale;

  late final NotesRepository notesRepository = NotesRepository();
  late final BooksRepository booksRepository = BooksRepository();
  late final BookContentSearchRepository bookContentSearchRepository =
      BookContentSearchRepository(booksRepository: booksRepository);
  late final GroupsRepository groupsRepository = GroupsRepository();
  late final ReadingHistoryRepository readingHistoryRepository =
      ReadingHistoryRepository();
  late final TagRepository tagRepository = TagRepository();

  /// Chapter content LRU cache (shared across tools within a conversation).
  late final BookContentCache bookContentCache = BookContentCache();

  final AnnotationLedger? _externalAnnotationLedger;

  /// Tracks annotations created by AI during this conversation.
  /// Uses session-level ledger if provided, otherwise creates a local one.
  late final AnnotationLedger annotationLedger =
      _externalAnnotationLedger ?? AnnotationLedger();

  bool get isReading => ref.read(currentReadingProvider).isReading;

  /// Current scene derived from reading state.
  AiToolScene get currentScene =>
      isReading ? AiToolScene.reading : AiToolScene.library;
}

/// AiToolRiskLevel is defined in lib/enums/ai_tool_risk_level.dart.

class AiToolDefinition {
  const AiToolDefinition({
    required this.id,
    required this.displayNameBuilder,
    required this.descriptionBuilder,
    required this.build,
    this.riskLevel = AiToolRiskLevel.readOnly,
    this.alwaysRequireApproval = false,
    this.scenes = const {AiToolScene.global},
    this.isConcurrencySafe = true,
  });

  final String id;
  final String Function(L10n l10n) displayNameBuilder;
  final String Function(L10n l10n) descriptionBuilder;
  final Tool Function(AiToolContext context) build;

  /// Tool risk level for approval decisions.
  final AiToolRiskLevel riskLevel;

  /// Force Tool Safety approval prompt even if user config would skip prompts.
  ///
  /// Used for sensitive write tools (e.g. local memory mutations) that must be
  /// explicitly approved each time.
  final bool alwaysRequireApproval;

  /// Scenes in which this tool should be available.
  /// Tools with [AiToolScene.global] are always included.
  final Set<AiToolScene> scenes;

  /// Whether this tool can run concurrently with other concurrent-safe tools.
  /// Read-only tools should be `true`; write/destructive tools `false`.
  final bool isConcurrencySafe;

  String displayName(L10n l10n) => displayNameBuilder(l10n);

  String description(L10n l10n) => descriptionBuilder(l10n);

  String displayNameOrDefault([L10n? l10n]) =>
      l10n == null ? id : displayName(l10n);

  String descriptionOrDefault([L10n? l10n]) =>
      l10n == null ? '' : description(l10n);
}

class AiToolRegistry {
  static final List<AiToolDefinition> _definitions = [
    // ── Global tools (available everywhere) ──
    calculatorToolDefinition,
    currentTimeToolDefinition,
    fetchUrlToolDefinition,
    createWebSearchToolDefinition(),
    createSpawnSubAgentToolDefinition(),

    // ── System tools (calendar, reminders, shortcuts) ──
    calendarListCalendarsToolDefinition,
    calendarListEventsToolDefinition,
    calendarGetEventToolDefinition,
    calendarCreateEventToolDefinition,
    calendarUpdateEventToolDefinition,
    calendarDeleteEventToolDefinition,
    remindersListListsToolDefinition,
    remindersListToolDefinition,
    remindersGetToolDefinition,
    remindersCreateToolDefinition,
    remindersUpdateToolDefinition,
    remindersCompleteToolDefinition,
    remindersUncompleteToolDefinition,
    remindersDeleteToolDefinition,
    remindersCreateListToolDefinition,
    remindersRenameListToolDefinition,
    remindersDeleteListToolDefinition,
    shortcutsRunToolDefinition,

    // ── Reading tools (only when a book is open) ──
    mindmapToolDefinition,
    bookContentSearchToolDefinition,
    createHighlightToolDefinition,
    createNoteToolDefinition,
    currentReadingMetadataToolDefinition,
    currentBookTocToolDefinition,
    currentChapterContentToolDefinition,
    chapterContentByHrefToolDefinition,
    currentBookFulltextToolDefinition,
    resolveCfiToolDefinition,
    semanticSearchCurrentBookToolDefinition,

    // ── Library tools (bookshelf / notes / history) ──
    bookshelfLookupToolDefinition,
    bookshelfOrganizeToolDefinition,
    notesSearchToolDefinition,
    readingHistoryToolDefinition,
    semanticSearchLibraryToolDefinition,
    tagsListToolDefinition,
    booksTagsListToolDefinition,
    applyBookTagsToolDefinition,

    // ── Memory tools (global) ──
    memoryReadToolDefinition,
    memorySearchToolDefinition,
    memoryAppendToolDefinition,
    memoryReplaceToolDefinition,
  ];

  static final Map<String, AiToolDefinition> _definitionMap = {
    for (final def in _definitions) def.id: def,
  };

  /// Scene overrides for tools that are NOT global.
  /// Tools not listed here default to {AiToolScene.global}.
  static const Map<String, Set<AiToolScene>> _sceneOverrides = {
    // Reading-only tools
    'book_content_search': {AiToolScene.reading},
    'current_reading_metadata': {AiToolScene.reading},
    'current_book_toc': {AiToolScene.reading},
    'current_chapter_content': {AiToolScene.reading},
    'chapter_content_by_href': {AiToolScene.reading},
    'current_book_fulltext': {AiToolScene.reading},
    'resolve_cfi': {AiToolScene.reading},
    'semantic_search_current_book': {AiToolScene.reading},
    'mindmap': {AiToolScene.reading},
    'create_highlight': {AiToolScene.reading},
    'create_note': {AiToolScene.reading},
    // Library-only tools
    'bookshelf_lookup': {AiToolScene.library},
    'bookshelf_organize': {AiToolScene.library},
    'notes_search': {AiToolScene.library, AiToolScene.reading},
    'reading_history': {AiToolScene.library},
    'semantic_search_library': {AiToolScene.library},
    'tags_list': {AiToolScene.library},
    'books_tags_list': {AiToolScene.library},
    'apply_book_tags': {AiToolScene.library},
    // System tools
    'calendar_list_calendars': {AiToolScene.system, AiToolScene.library},
    'calendar_list_events': {AiToolScene.system, AiToolScene.library},
    'calendar_get_event': {AiToolScene.system, AiToolScene.library},
    'calendar_create_event': {AiToolScene.system, AiToolScene.library},
    'calendar_update_event': {AiToolScene.system, AiToolScene.library},
    'calendar_delete_event': {AiToolScene.system, AiToolScene.library},
    'reminders_list_lists': {AiToolScene.system, AiToolScene.library},
    'reminders_list': {AiToolScene.system, AiToolScene.library},
    'reminders_get': {AiToolScene.system, AiToolScene.library},
    'reminders_create': {AiToolScene.system, AiToolScene.library},
    'reminders_update': {AiToolScene.system, AiToolScene.library},
    'reminders_complete': {AiToolScene.system, AiToolScene.library},
    'reminders_uncomplete': {AiToolScene.system, AiToolScene.library},
    'reminders_delete': {AiToolScene.system, AiToolScene.library},
    'reminders_create_list': {AiToolScene.system, AiToolScene.library},
    'reminders_rename_list': {AiToolScene.system, AiToolScene.library},
    'reminders_delete_list': {AiToolScene.system, AiToolScene.library},
    'shortcuts_run': {AiToolScene.system, AiToolScene.library},
  };

  /// Tools that are NOT concurrency-safe (write/destructive tools).
  static const Set<String> _nonConcurrentTools = {
    'bookshelf_organize',
    'apply_book_tags',
    'create_highlight',
    'create_note',
    'memory_append',
    'memory_replace',
    'calendar_create_event',
    'calendar_update_event',
    'calendar_delete_event',
    'reminders_create',
    'reminders_update',
    'reminders_complete',
    'reminders_uncomplete',
    'reminders_delete',
    'reminders_create_list',
    'reminders_rename_list',
    'reminders_delete_list',
    'shortcuts_run',
    'spawn_sub_agent',
  };

  /// Returns the effective scenes for a tool, considering overrides.
  static Set<AiToolScene> scenesForId(String id) =>
      _sceneOverrides[id] ?? const {AiToolScene.global};

  /// Returns whether a tool is concurrency-safe.
  static bool isConcurrencySafeForId(String id) =>
      !_nonConcurrentTools.contains(id);

  static List<AiToolDefinition> get definitions =>
      List<AiToolDefinition>.unmodifiable(_definitions);

  static AiToolDefinition? byId(String id) => _definitionMap[id];

  static List<String> defaultEnabledToolIds() =>
      _definitions.map((def) => def.id).toList(growable: false);

  static List<String> sanitizeIds(List<String> ids) {
    final seen = <String>{};
    final filtered = <String>[];
    for (final id in ids) {
      if (_definitionMap.containsKey(id) && seen.add(id)) {
        filtered.add(id);
      }
    }
    return filtered;
  }

  static List<Tool> buildTools(AiToolContext context, List<String> enabledIds) {
    final enabled = enabledIds.toSet();
    return _definitions
        .where((def) => enabled.contains(def.id))
        .map((def) => def.build(context))
        .toList(growable: false);
  }

  static bool _isToolVisibleInScene(String toolId, AiToolScene scene) {
    final toolScenes = scenesForId(toolId);
    return toolScenes.contains(AiToolScene.global) ||
        toolScenes.contains(scene);
  }

  /// Build tools filtered by scene context.
  ///
  /// Only returns tools whose scenes include [AiToolScene.global] or [scene].
  static List<Tool> buildToolsForScene(
    AiToolContext context,
    List<String> enabledIds,
    AiToolScene scene,
  ) {
    final enabled = enabledIds.toSet();
    return _definitions
        .where((def) =>
            enabled.contains(def.id) && _isToolVisibleInScene(def.id, scene))
        .map((def) => def.build(context))
        .toList(growable: false);
  }

  /// Returns definitions filtered by scene (for system prompt generation).
  static List<AiToolDefinition> definitionsForScene(
    List<String> enabledIds,
    AiToolScene scene,
  ) {
    final enabled = enabledIds.toSet();
    return _definitions
        .where((def) =>
            enabled.contains(def.id) && _isToolVisibleInScene(def.id, scene))
        .toList(growable: false);
  }

  static String displayNameForId(String id, {L10n? l10n}) =>
      _definitionMap[id]?.displayNameOrDefault(l10n) ?? id;

  static String descriptionForId(String id, {L10n? l10n}) =>
      _definitionMap[id]?.descriptionOrDefault(l10n) ?? '';
}
