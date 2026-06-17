import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:papertok_reader/app/app_globals.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/providers/ai_chat.dart';
import 'package:papertok_reader/providers/ai_draft_input.dart';
import 'package:papertok_reader/providers/ai_history.dart';
import 'package:papertok_reader/providers/current_reading.dart';
import 'package:papertok_reader/providers/spaced_review.dart';
import 'package:papertok_reader/service/ai/ai_services.dart';
import 'package:papertok_reader/service/ai/ai_history.dart';
import 'package:papertok_reader/models/ai_agent_governance.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/ai_provider_meta.dart';
import 'package:papertok_reader/enums/ai_thinking_mode.dart';
import 'package:papertok_reader/models/concept_graph.dart';
import 'package:papertok_reader/models/current_reading_state.dart';
import 'package:papertok_reader/page/settings_page/custom_skills.dart';
import 'package:papertok_reader/providers/ai_seminar_runtime.dart';
import 'package:papertok_reader/providers/concept_graph_explorer.dart';
import 'package:papertok_reader/service/ai/agent_run_event_message_part_adapter.dart';
import 'package:papertok_reader/service/ai/agent_run_graph_store.dart';
import 'package:papertok_reader/service/ai/sub_agent_runner.dart';
import 'package:papertok_reader/service/memory/memory_candidate.dart';
import 'package:papertok_reader/service/memory/memory_workflow_policy.dart';
import 'package:papertok_reader/service/memory/memory_workflow_service.dart';
import 'package:papertok_reader/utils/toast/common.dart';
import 'package:papertok_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:papertok_reader/utils/ai_reasoning_parser.dart';
import 'package:papertok_reader/widgets/ai/seminar/evidence/seminar_evidence_widgets.dart';
import 'package:papertok_reader/widgets/ai/seminar/seminar_autoscroll_policy.dart';
import 'package:papertok_reader/widgets/ai/seminar/shared/seminar_snapshot_widgets.dart';
import 'package:papertok_reader/widgets/ai/seminar/seminar_stable_width_section.dart';
import 'package:papertok_reader/widgets/ai/seminar/tools/seminar_tool_widgets.dart';
import 'package:papertok_reader/widgets/ai/seminar/start_seminar_tool_bridge.dart';
import 'package:papertok_reader/widgets/ai/tool_step_tile.dart';
import 'package:papertok_reader/widgets/ai/tool_tiles/apply_book_tags_step_tile.dart';
import 'package:papertok_reader/widgets/ai/tool_tiles/mindmap_step_tile.dart';
import 'package:papertok_reader/widgets/ai/tool_tiles/organize_bookshelf_step_tile.dart';
import 'package:papertok_reader/widgets/ai/tool_tiles/tool_tile_base.dart';
import 'package:papertok_reader/widgets/delete_confirm.dart';
import 'package:papertok_reader/widgets/knowledge/knowledge_card_detail_page.dart';
import 'package:papertok_reader/widgets/markdown/styled_markdown.dart';
import 'package:papertok_reader/widgets/ai/attachment_picker_dialog.dart';
import 'package:papertok_reader/widgets/common/pt_bottom_sheet.dart';
import 'package:papertok_reader/widgets/common/pt_dialog.dart';
import 'package:papertok_reader/service/ai/skills/ai_skill.dart';
import 'package:papertok_reader/service/ai/skills/ai_skill_registry.dart';
import 'package:papertok_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:papertok_reader/service/deeplink/paperreader_source_opener.dart';
import 'package:papertok_reader/service/knowledge/ai_chat_knowledge_card_producer.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/models/attachment_item.dart';
import 'package:papertok_reader/models/book_import_item.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/book.dart';
import 'package:papertok_reader/service/receive_file/share_inbox_cleanup_service.dart';
import 'package:papertok_reader/service/receive_file/share_inbox_paths.dart';
import 'package:papertok_reader/service/receive_file/share_safe_import.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/common/pt_collapsible_card.dart';
import 'package:papertok_reader/widgets/common/anx_segmented_button.dart';
import 'package:papertok_reader/utils/get_path/get_base_path.dart';
import 'package:papertok_reader/utils/get_path/get_cache_dir.dart';
import 'package:papertok_reader/utils/page_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:path/path.dart' as p;
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:papertok_reader/models/ai_quick_prompt_chip.dart';

part 'seminar/setup/seminar_run_setup_sheet.dart';

class _ConfigurableSkillPickerRow extends StatelessWidget {
  const _ConfigurableSkillPickerRow({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.configLabel,
    required this.onSelect,
    required this.onConfigure,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final IconData icon;
  final String configLabel;
  final VoidCallback onSelect;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          HapticFeedback.selectionClick();
          onSelect();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? ClaudePalette.accentTint(context)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected
                    ? ClaudePalette.accent(context)
                    : ClaudePalette.secondary(context),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                        color: ClaudePalette.fg(context),
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: ClaudePalette.secondary(context),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.check_rounded,
                  size: 20,
                  color: ClaudePalette.accent(context),
                ),
              ],
              const SizedBox(width: 8),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onConfigure,
                icon: const Icon(Icons.tune_outlined, size: 16),
                label: Text(configLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BuiltInSkillPromptSettingsSheet extends StatefulWidget {
  const _BuiltInSkillPromptSettingsSheet({
    required this.initialPrompt,
    required this.description,
    required this.label,
    required this.hint,
    required this.clearLabel,
    required this.cancelLabel,
    required this.saveLabel,
    required this.onClear,
    required this.onSave,
  });

  final String initialPrompt;
  final String description;
  final String label;
  final String hint;
  final String clearLabel;
  final String cancelLabel;
  final String saveLabel;
  final VoidCallback onClear;
  final ValueChanged<String> onSave;

  @override
  State<_BuiltInSkillPromptSettingsSheet> createState() =>
      _BuiltInSkillPromptSettingsSheetState();
}

class _BuiltInSkillPromptSettingsSheetState
    extends State<_BuiltInSkillPromptSettingsSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPrompt);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.description,
            style: TextStyle(
              fontSize: 13,
              color: ClaudePalette.secondary(context),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            minLines: 4,
            maxLines: 8,
            maxLength: Prefs.aiSkillCustomPromptMaxChars,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: widget.label,
              hintText: widget.hint,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: widget.onClear,
                child: Text(widget.clearLabel),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(widget.cancelLabel),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => widget.onSave(_controller.text),
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(widget.saveLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AiChatStream extends ConsumerStatefulWidget {
  const AiChatStream({
    super.key,
    this.initialMessage,
    this.sendImmediate = false,
    this.quickPromptChips = const [],
    this.trailing,
    this.scrollController,
    this.onRequestMinimize,
    this.bottomPadding = 0,
    this.inputSafeAreaBottom = true,
    this.resizeToAvoidBottomInset = true,
    this.emptyStateBuilder,
    this.chatKnowledgeCardProducer,
    this.memoryWorkflowService,
    this.sourceOpener,
    this.initialSourceRef,
    this.uiVisible = true,
  });

  final String? initialMessage;
  final bool sendImmediate;
  final List<AiQuickPromptChip> quickPromptChips;
  final List<Widget>? trailing;

  /// Optional external scroll controller used for the message list.
  ///
  /// This is mainly for integrating with [DraggableScrollableSheet].
  final ScrollController? scrollController;

  /// Optional callback used by bottom-sheet mode to minimize the sheet.
  final VoidCallback? onRequestMinimize;

  /// Extra bottom padding used for bottom overlays (e.g. floating home tab bar).
  ///
  /// This is applied as *internal* padding inside the input box so the bar can
  /// float above the content without leaving a visible blank gap.
  final double bottomPadding;

  /// Whether the input box should add the system bottom safe area.
  ///
  /// On Home AI tab we set this to false because HomePage already places a
  /// floating tab bar with its own bottom safe area.
  final bool inputSafeAreaBottom;

  /// When AiChatStream is used inside another Scaffold (e.g. Home tab page),
  /// letting both Scaffolds handle viewInsets can cause the keyboard inset to be
  /// applied twice on iOS, leaving a large blank gap above the keyboard.
  final bool resizeToAvoidBottomInset;

  /// Custom empty state builder.
  ///
  /// This is mainly for the Home AI tab where we want a cleaner design.
  /// The callback can be used to send a prompt directly.
  final Widget Function(
          BuildContext context, void Function(String prompt) send)?
      emptyStateBuilder;

  final AiChatKnowledgeCardProducer? chatKnowledgeCardProducer;
  final MemoryWorkflowService? memoryWorkflowService;
  final PaperReaderSourceOpener? sourceOpener;
  final SourceRef? initialSourceRef;
  final bool uiVisible;

  @override
  ConsumerState<AiChatStream> createState() => AiChatStreamState();
}

enum _MessageMemoryAction {
  rememberNow,
  saveToLongTerm,
  addToReviewInbox,
  undoDirectSave,
}

enum _SeminarRunSnapshotSubview {
  overview('overview'),
  status('status'),
  thinking('thinking'),
  controls('controls'),
  tools('tools'),
  evidence('evidence'),
  roles('roles'),
  disagreements('disagreements'),
  whiteboard('whiteboard'),
  summary('summary'),
  artifacts('artifacts'),
  review('review');

  const _SeminarRunSnapshotSubview(this.id);

  final String id;
}

class AiChatStreamState extends ConsumerState<AiChatStream> {
  static const List<String> _seminarRoleToolIds = <String>[
    'semantic_search_current_book',
    'semantic_search_library',
    'notes_search',
    'memory_search',
    'concept_graph_search',
    'resolve_cfi',
  ];

  final TextEditingController inputController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final MemoryWorkflowService _memoryWorkflow =
      widget.memoryWorkflowService ?? MemoryWorkflowService();
  late final AiChatKnowledgeCardProducer _chatKnowledgeCards =
      widget.chatKnowledgeCardProducer ?? AiChatKnowledgeCardProducer();
  late final PaperReaderSourceOpener _sourceOpener =
      widget.sourceOpener ?? openPaperReaderSource;

  bool _suppressDraftSync = false;
  final Map<String, String> _lastSeminarCardSignatures = {};
  final Map<String, TextEditingController> _seminarCardReplyControllers = {};
  final Map<String, TextEditingController> _seminarCardQuestionControllers = {};
  final Map<String, TextEditingController> _seminarCardRolePromptControllers =
      {};
  final Map<String, TextEditingController> _seminarAgentInputControllers = {};
  final Map<String, GlobalKey> _seminarEvidenceTileKeys = {};
  final Map<String, AiSeminarRole> _seminarCardSelectedRoles = {};
  final Map<String, String> _seminarCardSelectedActionIds = {};
  final Map<String, _SeminarRunSnapshotSubview> _seminarCardSnapshotSubviews =
      {};
  final Set<String> _seminarCardSetupExpandedSessionIds = <String>{};
  final Set<String> _seminarCardResumeDetailSessionIds = <String>{};
  final Set<String> _seminarCardTimelineExpandedSessionIds = <String>{};
  final Set<String> _seminarAgentInputExpandedRunIds = <String>{};
  final Set<String> _seminarCardSubmittingSessionIds = <String>{};
  final Set<String> _seminarCardSavedKnowledgeCardIds = <String>{};
  final Set<String> _seminarCardSpacedReviewFlashcardIds = <String>{};
  final Set<String> _seminarCardConceptNodeIds = <String>{};
  final Set<String> _seminarCardIgnoredActionSessionIds = <String>{};
  final Set<String> _seminarCardSentToReviewSessionIds = <String>{};
  final StartSeminarToolBridge _startSeminarToolBridge =
      StartSeminarToolBridge();
  final Map<String, MemoryCandidate> _directMemoryByMessageKey =
      <String, MemoryCandidate>{};

  String? _seminarRuntimeScopeId(String? raw) =>
      raw == null || raw.trim().isEmpty ? null : raw.trim();

  String _newSeminarChatSessionId() =>
      'seminar-chat-${DateTime.now().microsecondsSinceEpoch}';

  String? _seminarSynthesisKnowledgeCardId(String? sessionId) {
    final normalizedSessionId = sessionId?.trim();
    if (normalizedSessionId == null || normalizedSessionId.isEmpty) {
      return null;
    }
    return 'seminar:$normalizedSessionId:synthesis-card';
  }

  String? _seminarSynthesisReviewFlashcardId(String? sessionId) {
    final normalizedSessionId = sessionId?.trim();
    if (normalizedSessionId == null || normalizedSessionId.isEmpty) {
      return null;
    }
    return 'seminar:$normalizedSessionId:synthesis-review';
  }

  String? _seminarSynthesisConceptNodeId(String? sessionId) {
    final normalizedSessionId = sessionId?.trim();
    if (normalizedSessionId == null || normalizedSessionId.isEmpty) {
      return null;
    }
    return 'seminar:$normalizedSessionId:synthesis-node';
  }

  AiSeminarRuntimeState _watchSeminarRuntimeState(String? sessionId) {
    final scopeId = _seminarRuntimeScopeId(sessionId);
    return scopeId == null
        ? ref.watch(aiSeminarRuntimeProvider)
        : ref.watch(aiSeminarRuntimeScopedProvider(scopeId));
  }

  AiSeminarRuntimeState _readSeminarRuntimeState(String? sessionId) {
    final scopeId = _seminarRuntimeScopeId(sessionId);
    return scopeId == null
        ? ref.read(aiSeminarRuntimeProvider)
        : ref.read(aiSeminarRuntimeScopedProvider(scopeId));
  }

  AiSeminarRuntimeNotifier _readSeminarRuntimeNotifier(String? sessionId) {
    final scopeId = _seminarRuntimeScopeId(sessionId);
    return scopeId == null
        ? ref.read(aiSeminarRuntimeProvider.notifier)
        : ref.read(aiSeminarRuntimeScopedProvider(scopeId).notifier);
  }

  void _onDraftInputChanged() {
    if (_suppressDraftSync) return;
    if (inputController.text.trim().isEmpty) {
      _draftSourceRef = null;
      _draftSourceRefSeedText = null;
    }
    try {
      ref.read(aiChatDraftInputProvider.notifier).set(inputController.text);
    } catch (_) {
      // Best-effort.
    }
  }

  late ScrollController _scrollController;
  bool _ownsScrollController = false;

  bool get _isStreaming => ref.read(aiChatStreamingProvider);

  // Bottom sheet convenience gesture: swipe down on input box to minimize.
  double _inputSwipeDownDy = 0;

  // Auto-scroll: do not jump on open; streaming follows only near bottom.
  bool _pinnedToBottom = false;
  bool _showScrollShortcut = false;
  bool _hasNewContentBelow = false;
  String _scrollShortcutContentSignature = '';

  // For each user turn, the assistant may have multiple generated variants.
  // We keep a lightweight UI-only selection index per turn.
  final Map<int, int> _selectedVariantByUserIndex = {};
  final Map<int, SourceRef> _sourceRefByUserIndex = {};
  SourceRef? _draftSourceRef;
  String? _draftSourceRefSeedText;
  bool _uiVisibleSyncScheduled = false;
  AiHistoryScope _historyScope = AiHistoryScope.currentBook;
  int? _historyScopeBookId;

  // Attachments for multimodal chat (sent to the model)
  final List<AttachmentItem> _attachments = [];

  // Book files queued for bookshelf import (UI-only; never sent to the model).
  final List<BookImportItem> _pendingBookImports = [];

  // Cache decoded base64 images for chat bubbles to avoid flicker during
  // streaming rebuilds.
  // Key: base64 string (no data: prefix).
  final LinkedHashMap<String, Uint8List> _decodedImageCache = LinkedHashMap();
  static const int _decodedImageCacheMaxEntries = 32;

  late final List<AiServiceOption> _builtInOptions;
  late final Map<String, AiServiceOption> _builtInById;
  late List<AiProviderMeta> _providers;
  late String _selectedProviderId;

  late List<String> _suggestedPrompts;
  late List<String> _starterPrompts;
  bool _starterPromptsReady = false;

  List<Map<String, String>> _getQuickPrompts(BuildContext context) {
    // Use customized prompts if available.
    final custom = Prefs().aiInputQuickPrompts;
    if (custom.isNotEmpty) {
      return custom
          .where((p) => p.enabled)
          .map((p) => {'label': p.label, 'prompt': p.prompt})
          .toList();
    }
    // Fall back to localized defaults.
    return [
      {
        'label': L10n.of(context).aiQuickPromptExplain,
        'prompt': L10n.of(context).aiQuickPromptExplainText,
      },
      {
        'label': L10n.of(context).aiQuickPromptOpinion,
        'prompt': L10n.of(context).aiQuickPromptOpinionText,
      },
      {
        'label': L10n.of(context).aiQuickPromptSummary,
        'prompt': L10n.of(context).aiQuickPromptSummaryText,
      },
      {
        'label': L10n.of(context).aiQuickPromptAnalyze,
        'prompt': L10n.of(context).aiQuickPromptAnalyzeText,
      },
      {
        'label': L10n.of(context).aiQuickPromptSuggest,
        'prompt': L10n.of(context).aiQuickPromptSuggestText,
      },
    ];
  }

  void _handleScroll() {
    // Be defensive: scroll controller may be swapped/rebuilt by the sheet.
    try {
      if (!_scrollController.hasClients) return;
      final pinnedToBottom = SeminarAutoScrollPolicy.isPinnedToBottom(
        maxScrollExtent: _scrollController.position.maxScrollExtent,
        pixels: _scrollController.offset,
      );
      final showShortcut = SeminarAutoScrollPolicy.shouldShowShortcut(
        maxScrollExtent: _scrollController.position.maxScrollExtent,
        pixels: _scrollController.offset,
      );
      final hasNewContentBelow = pinnedToBottom ? false : _hasNewContentBelow;
      if (pinnedToBottom == _pinnedToBottom &&
          showShortcut == _showScrollShortcut &&
          hasNewContentBelow == _hasNewContentBelow) {
        return;
      }
      setState(() {
        _pinnedToBottom = pinnedToBottom;
        _showScrollShortcut = showShortcut;
        _hasNewContentBelow = hasNewContentBelow;
      });
    } catch (_) {
      // Ignore (e.g. controller disposed during rebuild).
    }
  }

  void _attachScrollController(ScrollController? external) {
    // Detach old controller.
    try {
      _scrollController.removeListener(_handleScroll);
    } catch (_) {}

    if (_ownsScrollController) {
      try {
        _scrollController.dispose();
      } catch (_) {}
    }

    _ownsScrollController = external == null;
    _scrollController = external ?? ScrollController();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void initState() {
    super.initState();
    _scheduleSyncUiVisible();

    _scrollController = ScrollController();
    _attachScrollController(widget.scrollController);

    _starterPrompts = const [];
    _builtInOptions = buildDefaultAiServices();
    _builtInById = {
      for (final option in _builtInOptions) option.identifier: option,
    };

    _ensureProvidersInitialized();
    _providers = Prefs().aiProvidersV1;

    _selectedProviderId = Prefs().selectedAiService;
    if (!_isProviderSelectable(_selectedProviderId)) {
      _selectedProviderId = _fallbackProviderId(_providers);
      Prefs().selectedAiService = _selectedProviderId;
    }
    // Shared draft input (allows other pages to insert snippets).
    final draft = ref.read(aiChatDraftInputProvider);
    final initial = draft.isNotEmpty ? draft : (widget.initialMessage ?? '');
    inputController.text = initial;
    _draftSourceRef = widget.initialSourceRef;
    _draftSourceRefSeedText = widget.initialSourceRef == null ? null : initial;
    ref.read(aiChatDraftInputProvider.notifier).set(initial);
    inputController.addListener(_onDraftInputChanged);

    // Share Sheet may enqueue pending book imports before the chat UI builds.
    pendingShareBookImportPaths.addListener(_drainPendingShareBookImports);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _drainPendingShareBookImports();
    });

    _suggestedPrompts = const [];
    if (widget.sendImmediate) {
      _sendMessage();
    }
  }

  @override
  void didUpdateWidget(covariant AiChatStream oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.scrollController != widget.scrollController) {
      _attachScrollController(widget.scrollController);
    }
    if (oldWidget.uiVisible != widget.uiVisible) {
      _scheduleSyncUiVisible();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Initialize localized starter prompts using the widget's own context.
    // Avoid depending on a global navigator context in initState.
    if (!_starterPromptsReady) {
      final l10n = L10n.of(context);
      _starterPrompts = [
        l10n.quickPrompt1,
        l10n.quickPrompt2,
        l10n.quickPrompt3,
        l10n.quickPrompt4,
        l10n.quickPrompt5,
        l10n.quickPrompt6,
        l10n.quickPrompt7,
        l10n.quickPrompt8,
        l10n.quickPrompt9,
        l10n.quickPrompt10,
        l10n.quickPrompt11,
        l10n.quickPrompt12,
      ];
      _suggestedPrompts = _pickSuggestedPrompts();
      _starterPromptsReady = true;
    }
  }

  @override
  void dispose() {
    try {
      pendingShareBookImportPaths.removeListener(_drainPendingShareBookImports);
    } catch (_) {}
    try {
      inputController.removeListener(_onDraftInputChanged);
    } catch (_) {}
    inputController.dispose();
    for (final controller in _seminarCardReplyControllers.values) {
      controller.dispose();
    }
    for (final controller in _seminarCardQuestionControllers.values) {
      controller.dispose();
    }
    for (final controller in _seminarCardRolePromptControllers.values) {
      controller.dispose();
    }
    for (final controller in _seminarAgentInputControllers.values) {
      controller.dispose();
    }
    try {
      _scrollController.removeListener(_handleScroll);
    } catch (_) {}
    if (_ownsScrollController) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  void _scheduleSyncUiVisible() {
    if (_uiVisibleSyncScheduled) {
      return;
    }
    _uiVisibleSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _uiVisibleSyncScheduled = false;
      if (!mounted) {
        return;
      }
      final visible = widget.uiVisible;
      ref.read(aiChatProvider.notifier).setStreamingUiVisible(visible);
    });
  }

  void _ensureProvidersInitialized() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final builtIns = _builtInOptions.map((option) {
      final type = switch (option.identifier) {
        'claude' => AiProviderType.anthropic,
        'gemini' => AiProviderType.gemini,
        'openai-responses' => AiProviderType.openaiResponses,
        _ => AiProviderType.openaiCompatible,
      };

      return AiProviderMeta(
        id: option.identifier,
        name: option.title,
        type: type,
        enabled: true,
        isBuiltIn: true,
        createdAt: now,
        updatedAt: now,
        logoKey: option.logo,
      );
    }).toList(growable: false);

    Prefs().ensureAiProvidersV1Initialized(builtIns: builtIns);
  }

  AiProviderMeta? _providerById(String id) {
    for (final p in _providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  bool _isProviderSelectable(String id) {
    final p = _providerById(id);
    return p != null && p.enabled;
  }

  String _fallbackProviderId(List<AiProviderMeta> providers) {
    for (final p in providers) {
      if (p.id == 'openai' && p.enabled) return p.id;
    }
    for (final p in providers) {
      if (p.enabled) return p.id;
    }
    return 'openai';
  }

  AiProviderMeta get _currentProvider {
    return _providerById(_selectedProviderId) ??
        (_providers.isNotEmpty
            ? _providers.first
            : AiProviderMeta(
                id: 'openai',
                name: 'OpenAI',
                type: AiProviderType.openaiCompatible,
                enabled: true,
                isBuiltIn: true,
                createdAt: 0,
                updatedAt: 0,
              ));
  }

  AiServiceOption? _builtInOptionForProvider(AiProviderMeta meta) {
    final exact = _builtInById[meta.id];
    if (exact != null) return exact;

    // Custom providers: fall back to the built-in logo/model per type.
    switch (meta.type) {
      case AiProviderType.anthropic:
        return _builtInById['claude'];
      case AiProviderType.gemini:
        return _builtInById['gemini'];
      case AiProviderType.openaiResponses:
        return _builtInById['openai-responses'];
      case AiProviderType.openaiCompatible:
        return _builtInById['openai'];
    }
  }

  String _providerLogoKey(AiProviderMeta meta) {
    return meta.logoKey ?? _builtInOptionForProvider(meta)?.logo ?? '';
  }

  String _modelLabel(String providerId) {
    final stored = Prefs().getAiConfig(providerId);
    final model = stored['model']?.trim();
    if (model != null && model.isNotEmpty) {
      return model;
    }

    final meta = _providerById(providerId);
    final builtIn = meta == null
        ? _builtInById[providerId]
        : _builtInOptionForProvider(meta);

    return builtIn?.defaultModel ?? '';
  }

  Future<void> _onProviderSelected(String providerId) async {
    if (_isStreaming || providerId == _selectedProviderId) return;
    if (!_isProviderSelectable(providerId)) return;

    await _flushMemoryBeforeContextSwitch();

    Prefs().selectedAiService = providerId;
    setState(() {
      _selectedProviderId = providerId;
    });
  }

  Future<void> _flushMemoryBeforeContextSwitch() async {
    final prefs = Prefs();
    if (!prefs.memorySessionDigestEnabled) {
      return;
    }

    final messages =
        ref.read(aiChatProvider).asData?.value ?? const <ChatMessage>[];
    if (messages.length < 2) {
      return;
    }

    try {
      ref.read(aiChatProvider.notifier).persistCurrentConversation(ref);
      await _memoryWorkflow.captureSessionDigest(
        messages: messages,
        dailyStrategy: prefs.memoryWorkflowDailyStrategy,
        conversationId: ref.read(aiChatProvider.notifier).currentSessionId,
        triggerKind: 'provider_switch',
      );
    } catch (_) {
      // Best effort only. Provider switching should not hard-fail on digest.
    }
  }

  AiThinkingMode _thinkingModeForProvider(String providerId) {
    final existing = Prefs().getAiConfig(providerId);
    return aiThinkingModeFromString(existing['thinking_mode'] ?? 'auto');
  }

  bool _includeThoughtsForProvider(AiProviderMeta provider) {
    if (provider.type != AiProviderType.gemini) {
      return false;
    }
    final existing = Prefs().getAiConfig(provider.id);
    final raw = (existing['include_thoughts'] ?? 'true').trim().toLowerCase();
    return raw != 'false' && raw != '0' && raw != 'no';
  }

  String _thinkingModeLabel(AiThinkingMode mode, L10n l10n) {
    switch (mode) {
      case AiThinkingMode.off:
        return l10n.aiThinkingOff;
      case AiThinkingMode.auto:
        return l10n.aiThinkingAuto;
      case AiThinkingMode.minimal:
        return l10n.aiThinkingMinimal;
      case AiThinkingMode.low:
        return l10n.aiThinkingLow;
      case AiThinkingMode.medium:
        return l10n.aiThinkingMedium;
      case AiThinkingMode.high:
        return l10n.aiThinkingHigh;
    }
  }

  List<AiThinkingMode> _supportedThinkingModes(AiProviderMeta provider) {
    final stored = Prefs().getAiConfig(provider.id);
    final model = (stored['model'] ?? '').trim().toLowerCase();

    switch (provider.type) {
      case AiProviderType.openaiCompatible:
      case AiProviderType.openaiResponses:
        return const [
          AiThinkingMode.off,
          AiThinkingMode.auto,
          AiThinkingMode.minimal,
          AiThinkingMode.low,
          AiThinkingMode.medium,
          AiThinkingMode.high,
        ];
      case AiProviderType.anthropic:
        return const [
          AiThinkingMode.off,
          AiThinkingMode.auto,
          AiThinkingMode.low,
          AiThinkingMode.medium,
          AiThinkingMode.high,
        ];
      case AiProviderType.gemini:
        // Best-effort gating based on Gemini official doc.
        if (model.contains('gemini-3-pro')) {
          return const [
            AiThinkingMode.auto,
            AiThinkingMode.low,
            AiThinkingMode.high,
          ];
        }
        if (model.contains('gemini-2.5-pro')) {
          // Doc says: cannot disable thinking.
          return const [
            AiThinkingMode.auto,
            AiThinkingMode.low,
            AiThinkingMode.medium,
            AiThinkingMode.high,
          ];
        }
        return const [
          AiThinkingMode.off,
          AiThinkingMode.auto,
          AiThinkingMode.minimal,
          AiThinkingMode.low,
          AiThinkingMode.medium,
          AiThinkingMode.high,
        ];
    }
  }

  IconData _thinkingIcon(AiThinkingMode mode) {
    switch (mode) {
      case AiThinkingMode.off:
        return Icons.lightbulb_outline;
      case AiThinkingMode.auto:
        return Icons.auto_awesome;
      case AiThinkingMode.minimal:
        return Icons.lightbulb_outline;
      case AiThinkingMode.low:
        return Icons.lightbulb_outline;
      case AiThinkingMode.medium:
        return Icons.lightbulb;
      case AiThinkingMode.high:
        return Icons.lightbulb;
    }
  }

  String _localizedSkillName(BuildContext context, AiSkill skill) {
    final l = L10n.of(context);
    switch (skill.id) {
      case 'paper_analyzer':
        return l.aiSkillPaperAnalyzerName;
      case 'flashcard_generator':
        return l.aiSkillFlashcardGeneratorName;
      case 'debate_partner':
        return l.aiSkillDebatePartnerName;
      case 'vocab_extractor':
        return l.aiSkillVocabExtractorName;
      case 'reading_companion':
        return l.aiSkillReadingCompanionName;
      default:
        return skill.name;
    }
  }

  String _localizedSkillDesc(BuildContext context, AiSkill skill) {
    final l = L10n.of(context);
    switch (skill.id) {
      case 'paper_analyzer':
        return l.aiSkillPaperAnalyzerDesc;
      case 'flashcard_generator':
        return l.aiSkillFlashcardGeneratorDesc;
      case 'debate_partner':
        return l.aiSkillDebatePartnerDesc;
      case 'vocab_extractor':
        return l.aiSkillVocabExtractorDesc;
      case 'reading_companion':
        return l.aiSkillReadingCompanionDesc;
      default:
        return skill.description;
    }
  }

  static const String _noSkillSentinel = '__none__';

  Widget _buildSkillButton(BuildContext context) {
    final activeId = Prefs().activeAiSkillId;
    final active = AiSkillRegistry.activeChatSkillById(activeId);
    final isActive = active != null;

    // Use a non-null sentinel for the "no skill" item. PopupMenuButton<T?>
    // treats `value: null` the same as "menu dismissed", so onSelected never
    // fires — we can't distinguish a tap on "no skill" from tapping outside.
    return PopupMenuButton<String>(
      icon: Icon(
        isActive ? Icons.auto_fix_high : Icons.auto_fix_high_outlined,
        size: 18,
        color: isActive ? Theme.of(context).colorScheme.primary : null,
      ),
      tooltip: L10n.of(context).aiSkillsTooltip,
      onSelected: (value) {
        setState(() {
          Prefs().activeAiSkillId = value == _noSkillSentinel ? null : value;
        });
      },
      itemBuilder: (context) {
        final skills = AiSkillRegistry.selectableActiveSkills();
        return [
          PopupMenuItem<String>(
            value: _noSkillSentinel,
            child: Row(
              children: [
                Icon(Icons.block,
                    size: 16,
                    color: !isActive
                        ? Theme.of(context).colorScheme.primary
                        : null),
                const SizedBox(width: 8),
                Text(L10n.of(context).aiSkillNone),
                if (!isActive) ...[
                  const Spacer(),
                  Icon(Icons.check,
                      size: 16, color: Theme.of(context).colorScheme.primary),
                ],
              ],
            ),
          ),
          const PopupMenuDivider(),
          ...skills.map((skill) {
            final selected = skill.id == activeId;
            return PopupMenuItem<String>(
              value: skill.id,
              child: Row(
                children: [
                  Icon(
                    Icons.auto_fix_high,
                    size: 16,
                    color:
                        selected ? Theme.of(context).colorScheme.primary : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_localizedSkillName(context, skill),
                            style: TextStyle(
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            )),
                        Text(_localizedSkillDesc(context, skill),
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check,
                        size: 16, color: Theme.of(context).colorScheme.primary),
                ],
              ),
            );
          }),
        ];
      },
    );
  }

  Future<void> _editThinkingMode() async {
    if (_isStreaming) return;

    final l10n = L10n.of(context);
    final provider = _currentProvider;
    final supported = _supportedThinkingModes(provider);

    await PTBottomSheet.show<void>(
      context,
      title: l10n.aiThinkingTitle,
      subtitle: provider.name,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            final liveCurrent = _thinkingModeForProvider(provider.id);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (provider.type == AiProviderType.gemini)
                  SwitchListTile.adaptive(
                    title:
                        Text(l10n.settingsAiProviderCenterIncludeThoughtsTitle),
                    subtitle:
                        Text(l10n.settingsAiProviderCenterIncludeThoughtsDesc),
                    value: _includeThoughtsForProvider(provider),
                    onChanged: (v) {
                      final next = Map<String, String>.from(
                        Prefs().getAiConfig(provider.id),
                      );
                      next['include_thoughts'] = v ? 'true' : 'false';
                      Prefs().saveAiConfig(provider.id, next);
                      setState(() {});
                      setLocalState(() {});
                    },
                  ),
                for (final mode in AiThinkingMode.values)
                  Opacity(
                    opacity: supported.contains(mode) ? 1.0 : 0.4,
                    child: IgnorePointer(
                      ignoring: !supported.contains(mode),
                      child: PTPickerRow<AiThinkingMode>(
                        value: mode,
                        groupValue: liveCurrent,
                        title: _thinkingModeLabel(mode, l10n),
                        leading: _thinkingIcon(mode),
                        onChanged: (v) {
                          final next = Map<String, String>.from(
                            Prefs().getAiConfig(provider.id),
                          );
                          next['thinking_mode'] = aiThinkingModeToString(v);
                          Prefs().saveAiConfig(provider.id, next);
                          setState(() {});
                          Navigator.of(ctx).pop();
                        },
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editCurrentModel() async {
    if (_isStreaming) return;

    final l10n = L10n.of(context);
    final provider = _currentProvider;

    final existing = Prefs().getAiConfig(provider.id);
    final controller = TextEditingController(
      text: (existing['model'] ?? '').trim(),
    );
    final cached =
        Prefs().getAiModelsCacheV1(provider.id)?.models ?? const <String>[];

    try {
      final ok = await PTBottomSheet.show<bool>(
        context,
        title: l10n.aiChatEditModelTitle,
        subtitle: provider.name,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setLocalState) {
              String selected = controller.text.trim();
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (cached.isNotEmpty) ...[
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(ctx).size.height * 0.45,
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final m in cached)
                            PTPickerRow<String>(
                              value: m,
                              groupValue: selected,
                              title: m,
                              onChanged: (v) {
                                controller.text = v;
                                setLocalState(() {});
                              },
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: l10n.aiChatModelLabel,
                    ),
                    onChanged: (_) => setLocalState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: Text(l10n.commonCancel),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: Text(l10n.commonSave),
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      );

      if (ok != true || !mounted) return;

      final nextModel = controller.text.trim();
      final next = Map<String, String>.from(existing);
      if (nextModel.isEmpty) {
        next.remove('model');
      } else {
        next['model'] = nextModel;
      }

      Prefs().saveAiConfig(provider.id, next);
      setState(() {});
    } finally {
      controller.dispose();
    }
  }

  List<String> _pickSuggestedPrompts() {
    final prompts = List<String>.from(_starterPrompts)..shuffle();
    return prompts.take(3).toList(growable: false);
  }

  void _scrollToBottom({
    bool force = false,
    bool clearNewContentIndicator = false,
  }) {
    final isScrolling = _scrollController.hasClients &&
        _scrollController.position.isScrollingNotifier.value;
    if (!force &&
        !SeminarAutoScrollPolicy.shouldFollowStreaming(
          pinnedToBottom: _pinnedToBottom,
          userScrollInProgress: isScrolling,
        )) {
      return;
    }
    if (clearNewContentIndicator &&
        (_hasNewContentBelow || _showScrollShortcut || !_pinnedToBottom)) {
      setState(() {
        _hasNewContentBelow = false;
        _showScrollShortcut = false;
        _pinnedToBottom = true;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (_scrollController.hasClients) {
          final target = _scrollController.position.maxScrollExtent;
          if (_isStreaming) {
            _scrollController.jumpTo(target);
          } else {
            _scrollController.animateTo(
              target,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          }
        }
      } catch (_) {
        // Ignore (e.g. controller disposed/replaced while minimizing).
      }
    });
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (!_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.minScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      } catch (_) {
        // Ignore (e.g. controller disposed/replaced while minimizing).
      }
    });
  }

  Widget _buildHistoryDrawer(BuildContext context) {
    final historyState = ref.watch(aiHistoryProvider);
    final reading = ref.watch(currentReadingProvider);
    final currentBookId = reading.isReading ? reading.book?.id : null;
    final selectedScope = currentBookId == null
        ? AiHistoryScope.all
        : _historyScopeBookId == currentBookId
            ? _historyScope
            : AiHistoryScope.currentBook;
    return Container(
      color: ClaudePalette.bg(context),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      L10n.of(context).conversationHistory,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: ClaudePalette.fg(context),
                      ),
                    ),
                  ),
                  DeleteConfirm(
                    delete: () => _confirmClearHistory(context),
                    deleteIcon: Icon(
                      Icons.delete_sweep_outlined,
                      size: 22,
                      color: ClaudePalette.secondary(context),
                    ),
                  ),
                ],
              ),
            ),
            if (currentBookId != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: AnxSegmentedButton<AiHistoryScope>(
                    selected: {selectedScope},
                    showSelectedIcon: false,
                    segments: [
                      SegmentButtonItem(
                        value: AiHistoryScope.currentBook,
                        label: _currentBookScopeLabel(context),
                        icon: const Icon(Icons.menu_book_outlined),
                      ),
                      SegmentButtonItem(
                        value: AiHistoryScope.all,
                        label: L10n.of(context).settingsShareInboxFilterAll,
                        icon: const Icon(Icons.forum_outlined),
                      ),
                    ],
                    onSelectionChanged: (selection) {
                      final next = selection.isEmpty ? null : selection.first;
                      if (next == null) return;
                      setState(() {
                        _historyScopeBookId = currentBookId;
                        _historyScope = next;
                      });
                    },
                  ),
                ),
              ),
            Expanded(
              child: historyState.when(
                data: (items) {
                  final scopedItems = filterAiHistoryForBook(
                    items,
                    currentBookId: currentBookId,
                    scope: selectedScope,
                  );
                  if (scopedItems.isEmpty) {
                    return Center(
                      child: Text(
                        L10n.of(context).noConversationTip,
                        style: TextStyle(
                          fontSize: 13,
                          color: ClaudePalette.secondary(context),
                        ),
                      ),
                    );
                  }
                  final currentSessionId =
                      ref.watch(aiChatProvider.notifier).currentSessionId;
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: scopedItems.length,
                    separatorBuilder: (_, __) => Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Divider(
                        height: 0.5,
                        thickness: 0.5,
                        color: ClaudePalette.divider(context),
                      ),
                    ),
                    itemBuilder: (context, index) {
                      final entry = scopedItems[index];
                      return _buildHistoryTile(
                        context,
                        entry,
                        isSelected: entry.id == currentSessionId,
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(
                  child: Text(
                    L10n.of(context).failedToLoadHistoryTip,
                    style: TextStyle(
                      fontSize: 13,
                      color: ClaudePalette.secondary(context),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _currentBookScopeLabel(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return languageCode == 'zh' ? '当前书' : 'Current book';
  }

  Widget _buildHistoryTile(
    BuildContext context,
    AiChatHistoryEntry entry, {
    bool isSelected = false,
  }) {
    final provider = _providerByIdFromPrefs(entry.serviceId) ??
        _providerById(entry.serviceId);
    final title = _deriveTitle(entry);
    final subtitle = _buildHistorySubtitle(provider, entry);

    return Dismissible(
      key: ValueKey('history-${entry.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: ClaudePalette.accent(context),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(
          Icons.delete_outline,
          color: Colors.white,
          size: 22,
        ),
      ),
      confirmDismiss: (_) async {
        await _confirmDeleteHistory(context, entry);
        return true;
      },
      child: Material(
        color:
            isSelected ? ClaudePalette.accentTint(context) : Colors.transparent,
        child: InkWell(
          onTap: () => _handleHistoryTap(context, entry),
          onLongPress: () => _renameHistoryEntry(context, entry),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: ClaudePalette.fg(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: ClaudePalette.secondary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTimestamp(entry.updatedAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: ClaudePalette.tertiary(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _buildHistorySubtitle(
    AiProviderMeta? provider,
    AiChatHistoryEntry entry,
  ) {
    final serviceLabel = provider?.name ?? entry.serviceId;
    if (entry.model.isEmpty) {
      return serviceLabel;
    }
    return '$serviceLabel · ${entry.model}';
  }

  AiProviderMeta? _providerByIdFromPrefs(String id) {
    return Prefs().getAiProviderMeta(id);
  }

  String _deriveTitle(AiChatHistoryEntry entry) {
    final stored = (entry.title ?? '').trim();
    if (stored.isNotEmpty) {
      return stored;
    }
    for (final message in entry.messages) {
      if (message is AIChatMessage) {
        final content = message.contentAsString.trim();
        if (content.isNotEmpty) {
          final firstLine = content.split('\n').first.trim();
          return firstLine;
        }
      }
    }
    if (entry.messages.isNotEmpty) {
      return 'Conversation';
    }
    return 'Empty conversation';
  }

  String _formatTimestamp(int timestamp) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final date =
        '${dateTime.year}-${twoDigits(dateTime.month)}-${twoDigits(dateTime.day)}';
    final time = '${twoDigits(dateTime.hour)}:${twoDigits(dateTime.minute)}';
    return '$date $time';
  }

  Future<void> _handleHistoryTap(
    BuildContext context,
    AiChatHistoryEntry entry,
  ) async {
    if (_isStreaming) {
      unawaited(ref.read(aiChatProvider.notifier).cancelStreaming());
    }

    ref.read(aiChatProvider.notifier).loadHistoryEntry(entry);
    if (mounted) {
      setState(() {
        _selectedProviderId = entry.serviceId;
        _sourceRefByUserIndex.clear();
        _draftSourceRef = null;
        _draftSourceRefSeedText = null;
      });
    }

    Navigator.of(context).pop();
    _pinnedToBottom = true;
    _scrollToBottom(force: true);
  }

  Future<void> _renameHistoryEntry(
    BuildContext context,
    AiChatHistoryEntry entry,
  ) async {
    final controller = TextEditingController(text: _deriveTitle(entry));
    final renamed = await PTDialog.show<String>(
      context,
      title: 'Rename conversation',
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Title',
        ),
      ),
      actions: [
        PTDialogAction(
          label: L10n.of(context).commonCancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        PTDialogAction(
          label: L10n.of(context).commonSave,
          isDefault: true,
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
        ),
      ],
    );

    final nextTitle = (renamed ?? '').trim();
    if (nextTitle.isEmpty) {
      return;
    }

    final updated = entry.copyWith(
      title: nextTitle,
      titleSource: 'manual',
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await ref.read(aiHistoryProvider.notifier).upsert(updated);
  }

  Future<void> _confirmDeleteHistory(
    BuildContext context,
    AiChatHistoryEntry entry,
  ) async {
    await ref.read(aiHistoryProvider.notifier).remove(entry.id);

    final currentSessionId = ref.read(aiChatProvider.notifier).currentSessionId;
    if (currentSessionId == entry.id) {
      ref.read(aiChatProvider.notifier).clear();
    }
  }

  Future<void> _confirmClearHistory(BuildContext context) async {
    await ref.read(aiHistoryProvider.notifier).clear();
    ref.read(aiChatProvider.notifier).clear();
    if (mounted) {
      setState(() {
        _sourceRefByUserIndex.clear();
        _draftSourceRef = null;
        _draftSourceRefSeedText = null;
      });
    }
  }

  // Streaming lifecycle is managed by [aiChatProvider] so UI minimize/close
  // does not interrupt generation.

  void sendCurrentDraft() {
    _sendMessage();
  }

  void _sendMessage() {
    if (_isStreaming) {
      return;
    }

    final message = inputController.text.trim();
    if (message.isEmpty && _attachments.isEmpty) return;
    final draftSourceRef = _sourceRefForCurrentDraft(message);

    inputController.clear();
    _draftSourceRef = null;
    _draftSourceRefSeedText = null;

    final attachments =
        _attachments.isEmpty ? null : List<AttachmentItem>.from(_attachments);
    if (_attachments.isNotEmpty) {
      setState(() {
        _attachments.clear();
      });
    }

    _pinnedToBottom = true;
    ref.read(aiChatProvider.notifier).startStreaming(
          message,
          false,
          attachments: attachments,
          userSourceRef: draftSourceRef,
        );
    if (draftSourceRef != null) {
      final messages =
          ref.read(aiChatProvider).asData?.value ?? const <ChatMessage>[];
      final userIndex = _findLastHumanIndex(messages);
      if (userIndex != null) {
        _sourceRefByUserIndex[userIndex] = draftSourceRef;
      }
    }
    _scrollToBottom(force: true);
  }

  SourceRef? _sourceRefForCurrentDraft(String message) {
    final sourceRef = _draftSourceRef;
    if (sourceRef == null) return null;

    final current = _normalizeDraftSourceMatchText(message);
    if (current.isEmpty) return null;

    final seed = _normalizeDraftSourceMatchText(
      _draftSourceRefSeedText ?? sourceRef.sourceTextSnippet ?? '',
    );
    final snippet = _normalizeDraftSourceMatchText(
      sourceRef.sourceTextSnippet ?? '',
    );

    if (_containsSourceText(current, seed) ||
        _containsSourceText(current, snippet)) {
      return sourceRef;
    }
    return null;
  }

  bool _containsSourceText(String current, String sourceText) {
    if (sourceText.isEmpty) return false;
    if (current == sourceText) return true;
    if (sourceText.length < 12) return false;
    return current.contains(sourceText);
  }

  String _normalizeDraftSourceMatchText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  void _regenerateFromUserIndex(int userIndex) {
    if (_isStreaming) {
      return;
    }

    _pinnedToBottom = true;
    ref.read(aiChatProvider.notifier).startStreaming(
          '',
          true,
          regenerateFromUserIndex: userIndex,
        );
    _scrollToBottom(force: true);
  }

  void _editUserMessageAndRegenerate(
    int userIndex,
    String newText, {
    List<AttachmentItem>? attachments,
  }) {
    if (_isStreaming) {
      return;
    }

    _pinnedToBottom = true;
    ref.read(aiChatProvider.notifier).startStreaming(
          newText,
          true,
          regenerateFromUserIndex: userIndex,
          replaceUserMessage: true,
          attachments: attachments,
        );
    _scrollToBottom(force: true);
  }

  void _copyPlainText(String text) {
    Clipboard.setData(ClipboardData(text: text));
    AnxToast.show(L10n.of(context).notesPageCopied);
  }

  Future<void> _confirmRegenerateFromUserIndex(
    int userIndex, {
    required bool isLastTurn,
  }) async {
    if (_isStreaming) {
      return;
    }

    if (!isLastTurn) {
      final confirmed = await PTDialog.show<bool>(
        context,
        title: L10n.of(context).aiChatRegenerateFromHereConfirmTitle,
        message: L10n.of(context).aiChatRegenerateFromHereConfirmBody,
        actions: [
          PTDialogAction(
            label: L10n.of(context).commonCancel,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          PTDialogAction(
            label: L10n.of(context).commonConfirm,
            isDefault: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      );
      if (confirmed != true) {
        return;
      }
    }

    _regenerateFromUserIndex(userIndex);
  }

  Future<void> _showEditUserMessageDialog(
    int userIndex,
    HumanChatMessage message,
  ) async {
    if (_isStreaming) {
      return;
    }

    final controller = TextEditingController(
      text: _extractUserTextFromHuman(message),
    );
    final editableAttachments =
        _extractAttachmentItemsFromHuman(message).toList(growable: true);
    try {
      final edited = await PTDialog.show<_EditUserMessageResult>(
        context,
        title: L10n.of(context).aiChatEditUserMessageTitle,
        content: SizedBox(
          width: 520,
          child: StatefulBuilder(
            builder: (context, setStateDialog) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: controller,
                      maxLength: 20000,
                      maxLines: 6,
                      minLines: 1,
                      autofocus: true,
                    ),
                    if (editableAttachments.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        '附件 ${editableAttachments.length}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < editableAttachments.length; i++)
                            _buildEditableAttachmentChip(
                              editableAttachments[i],
                              onRemove: () {
                                setStateDialog(() {
                                  editableAttachments.removeAt(i);
                                });
                              },
                              onPreview: editableAttachments[i].type ==
                                      AttachmentType.image
                                  ? () {
                                      final imageIndexes = <int>[];
                                      for (var j = 0;
                                          j < editableAttachments.length;
                                          j++) {
                                        if (editableAttachments[j].type ==
                                            AttachmentType.image) {
                                          imageIndexes.add(j);
                                        }
                                      }
                                      final initialImageIndex =
                                          imageIndexes.indexOf(i);
                                      final images = editableAttachments
                                          .where((a) =>
                                              a.type == AttachmentType.image)
                                          .map((a) => a.bytes)
                                          .toList(growable: false);
                                      _showImageGallery(
                                        images,
                                        initialIndex: initialImageIndex < 0
                                            ? 0
                                            : initialImageIndex,
                                      );
                                    }
                                  : null,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          PTDialogAction(
            label: L10n.of(context).commonCancel,
            onPressed: () => Navigator.of(context).pop(),
          ),
          PTDialogAction(
            label: L10n.of(context).commonSave,
            isDefault: true,
            onPressed: () {
              Navigator.of(context).pop(
                _EditUserMessageResult(
                  text: controller.text.trim(),
                  attachments: List<AttachmentItem>.from(editableAttachments),
                ),
              );
            },
          ),
        ],
      );

      if (edited == null) {
        return;
      }

      final confirmed = await PTDialog.show<bool>(
        context,
        title: L10n.of(context).aiChatRegenerateFromHereConfirmTitle,
        message: L10n.of(context).aiChatRegenerateFromHereConfirmBody,
        actions: [
          PTDialogAction(
            label: L10n.of(context).commonCancel,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          PTDialogAction(
            label: L10n.of(context).commonConfirm,
            isDefault: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      );

      if (confirmed != true) {
        return;
      }

      _editUserMessageAndRegenerate(
        userIndex,
        edited.text,
        attachments: edited.attachments,
      );
    } finally {
      controller.dispose();
    }
  }

  void _useQuickPrompt(String prompt) {
    inputController.text = '$prompt ${inputController.text}';
    _sendMessage();
  }

  // Wave L: default icon mapping for the quick-suggestion chip strip. The
  // existing quick prompt bank is string-only, so we pick a reasonable glyph
  // by index and fall back to a lightbulb for custom user-defined prompts.
  static const List<IconData> _quickSuggestionIcons = [
    Icons.auto_awesome_outlined,
    Icons.psychology_outlined,
    Icons.summarize_outlined,
    Icons.insights_outlined,
    Icons.lightbulb_outline,
    Icons.translate_outlined,
    Icons.style_outlined,
    Icons.help_outline,
  ];

  // Wave S: detect whether the composer is attached to a reading surface so
  // we can render a small mode label inside the pill. We use the chat context
  // notice as a cheap proxy — when the user is reading a book the AI chat
  // surface publishes a notice, otherwise we fall back to "Chat".
  Widget _buildQuickSuggestions(List<Map<String, String>> quickPrompts) {
    if (quickPrompts.isEmpty) {
      return const SizedBox.shrink();
    }
    // Wave S: ghost-pill chips — lighter background, tighter padding, and
    // secondary text/icon color so they read as context suggestions rather
    // than primary CTAs.
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: quickPrompts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final prompt = quickPrompts[index];
          final icon =
              _quickSuggestionIcons[index % _quickSuggestionIcons.length];
          return Material(
            color: Colors.transparent,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () {
                HapticFeedback.selectionClick();
                _useQuickPrompt(prompt['prompt']!);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: ClaudePalette.bg(context).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: ClaudePalette.divider(context),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: ClaudePalette.secondary(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      prompt['label'] ?? '',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: ClaudePalette.secondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _clearMessage() {
    if (_isStreaming) {
      return;
    }

    unawaited(_endCurrentSession());
  }

  Future<void> _showAttachmentPicker() async {
    if (_isStreaming) return;

    await PTBottomSheet.show<void>(
      context,
      builder: (ctx) {
        return AttachmentPickerDialog(
          onPicked: (items) {
            _addAttachments(items);
          },
        );
      },
    );
  }

  // Local-only state for toggles surfaced in the Add-to-Chat sheet but not
  // yet wired to a backend. Persistence is intentionally out of scope for
  // this wave (UI only).
  bool _webSearchEnabled = false;

  Future<void> _showAddToChatSheet(BuildContext context) async {
    if (_isStreaming) return;
    final l10n = L10n.of(context);
    final activeSkill =
        AiSkillRegistry.activeChatSkillById(Prefs().activeAiSkillId);

    Widget bigCard({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: AspectRatio(
          aspectRatio: 1,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  color: ClaudePalette.elevated(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: ClaudePalette.divider(context),
                    width: 0.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 26, color: ClaudePalette.accent(context)),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: ClaudePalette.fg(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget toggleRow({
      required IconData icon,
      required String title,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: ClaudePalette.secondary(context)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  color: ClaudePalette.fg(context),
                ),
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeTrackColor: ClaudePalette.accent(context),
            ),
          ],
        ),
      );
    }

    Widget navRow({
      required IconData icon,
      required String title,
      String? trailingValue,
      required VoidCallback onTap,
    }) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: ClaudePalette.secondary(context)),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      color: ClaudePalette.fg(context),
                    ),
                  ),
                ),
                if (trailingValue != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(
                      trailingValue,
                      style: TextStyle(
                        fontSize: 13,
                        color: ClaudePalette.tertiary(context),
                      ),
                    ),
                  ),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: ClaudePalette.tertiary(context)),
              ],
            ),
          ),
        ),
      );
    }

    Widget seminarFeatureCard(BuildContext sheetContext) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.of(sheetContext).pop();
            _openSeminarRuntimeFromChat();
          },
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.22),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.groups_2_outlined,
                  size: 22,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.aiChatSeminarFeatureTitle,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: ClaudePalette.fg(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.aiChatSeminarFeatureDesc,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.25,
                          color: ClaudePalette.secondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: const ValueKey('ai-chat-seminar-run-setup'),
                      tooltip: _skillSettingsText(
                        zh: '本次研讨设置',
                        en: 'Run setup',
                      ),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.tune_outlined, size: 18),
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        unawaited(_showSeminarRunSetupSheet());
                      },
                    ),
                    Text(
                      l10n.aiChatSeminarFeatureAction,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    await PTBottomSheet.show<void>(
      context,
      title: l10n.aiChatAddToChatTitle,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            final provider = _currentProvider;
            final thinkingMode = _thinkingModeForProvider(provider.id);
            final thinkingOn = thinkingMode != AiThinkingMode.off;
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      bigCard(
                        icon: Icons.photo_camera_outlined,
                        label: l10n.aiChatAttachCamera,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showAttachmentPicker();
                        },
                      ),
                      const SizedBox(width: 10),
                      bigCard(
                        icon: Icons.photo_library_outlined,
                        label: l10n.aiChatAttachPhotos,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showAttachmentPicker();
                        },
                      ),
                      const SizedBox(width: 10),
                      bigCard(
                        icon: Icons.folder_outlined,
                        label: l10n.aiChatAttachFiles,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _showAttachmentPicker();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(height: 1, color: ClaudePalette.divider(context)),
                  const SizedBox(height: 6),
                  toggleRow(
                    icon: Icons.travel_explore_outlined,
                    title: l10n.aiChatWebSearch,
                    value: _webSearchEnabled,
                    onChanged: (v) {
                      setLocalState(() => _webSearchEnabled = v);
                      setState(() {});
                    },
                  ),
                  toggleRow(
                    icon: Icons.psychology_outlined,
                    title: l10n.aiChatExtendedThinking,
                    value: thinkingOn,
                    onChanged: (v) {
                      final next = Map<String, String>.from(
                        Prefs().getAiConfig(provider.id),
                      );
                      next['thinking_mode'] = aiThinkingModeToString(
                        v ? AiThinkingMode.high : AiThinkingMode.off,
                      );
                      Prefs().saveAiConfig(provider.id, next);
                      setLocalState(() {});
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 6),
                  Divider(height: 1, color: ClaudePalette.divider(context)),
                  const SizedBox(height: 6),
                  seminarFeatureCard(ctx),
                  const SizedBox(height: 6),
                  navRow(
                    icon: Icons.style_outlined,
                    title: l10n.aiChatChooseStyle,
                    trailingValue: activeSkill == null
                        ? l10n.aiSkillNone
                        : _localizedSkillName(context, activeSkill),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _showSkillPickerSheet();
                    },
                  ),
                  navRow(
                    icon: Icons.tune,
                    title: l10n.aiChatEditModelTitle,
                    trailingValue: _modelLabel(_selectedProviderId),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _editCurrentModel();
                    },
                  ),
                  navRow(
                    icon: Icons.psychology_alt_outlined,
                    title: l10n.aiThinkingTitle,
                    trailingValue: _thinkingModeLabel(thinkingMode, l10n),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _editThinkingMode();
                    },
                  ),
                  navRow(
                    icon: Icons.folder_special_outlined,
                    title: l10n.aiChatAddToProject,
                    onTap: () {
                      Navigator.of(ctx).pop();
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showSkillPickerSheet() async {
    final l10n = L10n.of(context);
    final activeId =
        AiSkillRegistry.activeChatSkillById(Prefs().activeAiSkillId)?.id;
    await PTBottomSheet.show<void>(
      context,
      title: l10n.aiChatChooseStyle,
      builder: (ctx) {
        final skills = AiSkillRegistry.selectableActiveSkills();
        return ListView(
          shrinkWrap: true,
          children: [
            PTPickerRow<String>(
              value: '',
              groupValue: activeId ?? '',
              title: l10n.aiSkillNone,
              leading: Icons.block,
              onChanged: (_) {
                Prefs().activeAiSkillId = null;
                setState(() {});
                Navigator.of(ctx).pop();
              },
            ),
            for (final skill in skills)
              if (!skill.isBuiltIn)
                _ConfigurableSkillPickerRow(
                  selected: activeId == skill.id,
                  title: _localizedSkillName(context, skill),
                  subtitle: _localizedSkillDesc(context, skill),
                  icon: Icons.extension_outlined,
                  configLabel: l10n.settingsAiCustomSkillsTitle,
                  onSelect: () {
                    Prefs().activeAiSkillId = skill.id;
                    setState(() {});
                    Navigator.of(ctx).pop();
                  },
                  onConfigure: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).push(
                      CupertinoStyleRoute(
                        page: const CustomSkillsPage(),
                      ),
                    );
                  },
                )
              else
                _ConfigurableSkillPickerRow(
                  selected: activeId == skill.id,
                  title: _localizedSkillName(context, skill),
                  subtitle: _localizedSkillDesc(context, skill),
                  icon: Icons.auto_fix_high,
                  configLabel: _skillSettingsText(
                    zh: '技能设置',
                    en: 'Skill settings',
                  ),
                  onSelect: () {
                    Prefs().activeAiSkillId = skill.id;
                    setState(() {});
                    Navigator.of(ctx).pop();
                  },
                  onConfigure: () {
                    Navigator.of(ctx).pop();
                    unawaited(_showBuiltInSkillPromptSettings(skill));
                  },
                ),
          ],
        );
      },
    );
  }

  Future<void> _showBuiltInSkillPromptSettings(AiSkill skill) async {
    final l10n = L10n.of(context);
    await PTBottomSheet.show<void>(
      context,
      title: _skillSettingsTitle(skill),
      builder: (ctx) {
        return _BuiltInSkillPromptSettingsSheet(
          initialPrompt: Prefs().aiSkillCustomPromptFor(skill.id) ?? '',
          description: _skillSettingsText(
            zh: '这里的内容会附加到该风格的系统提示词里。它只影响新的 AI 请求，不会改变已有历史消息。',
            en: 'These instructions are appended to this style prompt. They affect new AI requests only and do not rewrite chat history.',
          ),
          label: _skillSettingsText(
            zh: '自定义附加提示词',
            en: 'Custom prompt add-on',
          ),
          hint: _skillSettingsText(
            zh: '例如：回答时先列出证据，再给出结论。',
            en: 'Example: list the evidence first, then state the conclusion.',
          ),
          clearLabel: _skillSettingsText(zh: '清除', en: 'Clear'),
          cancelLabel: l10n.commonCancel,
          saveLabel: l10n.commonSave,
          onClear: () {
            Prefs().setAiSkillCustomPrompt(skill.id, null);
            if (mounted) setState(() {});
            Navigator.of(ctx).pop();
            _showToastIfAvailable(l10n.commonSaved);
          },
          onSave: (value) {
            Prefs().setAiSkillCustomPrompt(skill.id, value);
            if (mounted) setState(() {});
            Navigator.of(ctx).pop();
            _showToastIfAvailable(l10n.commonSaved);
          },
        );
      },
    );
  }

  String _skillSettingsTitle(AiSkill skill) {
    final skillName = _localizedSkillName(context, skill);
    return _skillSettingsText(
      zh: '$skillName设置',
      en: '$skillName settings',
    );
  }

  String _skillSettingsText({
    required String zh,
    required String en,
  }) {
    return _isChineseLocale ? zh : en;
  }

  void _showToastIfAvailable(String message) {
    if (navigatorKey.currentContext == null) return;
    AnxToast.show(message);
  }

  Future<void> _showSeminarRunSetupSheet() async {
    final l10n = L10n.of(context);
    await PTBottomSheet.show<void>(
      context,
      title: _skillSettingsText(
        zh: '本次研讨设置',
        en: 'Run Seminar setup',
      ),
      builder: (ctx) {
        return _SeminarRunSetupSheet(
          initialQuestion: inputController.text.trim(),
          cancelLabel: l10n.commonCancel,
          startLabel: l10n.seminarStart,
          onStart: (question, config) {
            Navigator.of(ctx).pop();
            _openSeminarRuntimeFromChat(
              overrideQuestion: question,
              runConfig: config,
            );
          },
        );
      },
    );
  }

  void _openSeminarRuntimeFromChat({
    String? overrideQuestion,
    _SeminarRunConfig? runConfig,
  }) {
    if (!mounted) return;
    final reading = ref.read(currentReadingProvider);
    final question = (overrideQuestion ?? inputController.text).trim();
    final sourceRef = _draftSourceRefSeedText == inputController.text
        ? _draftSourceRef
        : null;
    final seminarSessionId = _newSeminarChatSessionId();
    unawaited(
      ref.read(aiChatProvider.notifier).appendSeminarRunCard(
            question: question,
            bookId: reading.book?.id,
            sourceRef: sourceRef,
            seminarSessionId: seminarSessionId,
            includeVerifier: runConfig?.includeVerifier,
            maxRounds: runConfig?.maxRounds,
            roleProfiles: runConfig?.roleProfiles,
          ),
    );
    _suppressDraftSync = true;
    inputController.clear();
    _suppressDraftSync = false;
    try {
      ref.read(aiChatDraftInputProvider.notifier).set('');
    } catch (_) {}

    setState(() {
      _lastSeminarCardSignatures.remove(seminarSessionId);
    });
  }

  void openNativeSeminarCard({
    String? question,
    String? sessionId,
    int? bookId,
    SourceRef? sourceRef,
    List<AiSeminarRoleProfile>? roleProfiles,
    int? maxRounds,
    bool? includeVerifier,
  }) {
    if (!mounted) return;
    final reading = ref.read(currentReadingProvider);
    final trimmedQuestion = question?.trim() ?? '';
    final normalizedSessionId = sessionId?.trim();
    final resolvedSessionId =
        normalizedSessionId == null || normalizedSessionId.isEmpty
            ? _newSeminarChatSessionId()
            : normalizedSessionId;
    unawaited(
      ref.read(aiChatProvider.notifier).appendSeminarRunCard(
            question: trimmedQuestion,
            bookId: sourceRef?.bookId ?? bookId ?? reading.book?.id,
            sourceRef: sourceRef,
            seminarSessionId: resolvedSessionId,
            includeVerifier: includeVerifier,
            maxRounds: maxRounds,
            roleProfiles: roleProfiles,
          ),
    );
    setState(() {
      _lastSeminarCardSignatures.remove(resolvedSessionId);
    });
  }

  void _scheduleStartSeminarToolBridges(List<ChatMessage> messages) {
    final requests = _startSeminarToolBridge.takeNewRequests(messages);
    if (requests.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final request in requests) {
        unawaited(_launchStartSeminarToolRequest(request));
      }
    });
  }

  Future<void> _launchStartSeminarToolRequest(
    StartSeminarToolRequest request,
  ) async {
    if (!mounted) return;
    final reading = ref.read(currentReadingProvider);
    final launch = _startSeminarToolBridge.buildLaunch(
      request: request,
      bookId: reading.book?.id,
      defaultRoleProfiles: Prefs().aiSeminarRoleProfiles,
      includeVerifier: Prefs().aiSeminarIncludeVerifier,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    final appendFuture = ref.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: request.input.question,
          bookId: reading.book?.id,
          seminarSessionId: request.sessionId,
          includeVerifier: launch.includeVerifier,
          roleProfiles: launch.roleProfilesForAppend,
        );
    unawaited(appendFuture.catchError((_) {}));
    await _startSeminarRunCardFromChat(launch.card);
  }

  void _syncSeminarRunCardSnapshot(
    String? rawSessionId,
    AiSeminarRuntimeState state,
  ) {
    unawaited(_syncSeminarRunCardSnapshotNow(rawSessionId, state));
  }

  Future<void> _syncSeminarRunCardSnapshotNow(
    String? rawSessionId,
    AiSeminarRuntimeState state,
  ) async {
    final sessionId = rawSessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) return;
    final runtimeSession = state.session;
    if (runtimeSession == null || runtimeSession.id != sessionId) return;

    final citedEvidence = _seminarCitedTraceableEvidenceFromState(state);
    final snapshot = _seminarRunCardSnapshotFromState(
      state,
      citedEvidence: citedEvidence,
    );
    final sourceRefCount = citedEvidence.length;
    final signature = jsonEncode({
      'sessionId': sessionId,
      'status': state.status.asString,
      'sourceRefCount': sourceRefCount,
      'snapshot': snapshot?.toJson(),
    });
    if (signature == _lastSeminarCardSignatures[sessionId]) return;
    _lastSeminarCardSignatures[sessionId] = signature;
    await Future<bool>.microtask(() {
      if (!mounted) return false;
      return ref.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
            seminarSessionId: sessionId,
            status: state.status.asString,
            sourceRefCount: sourceRefCount,
            snapshot: snapshot,
          );
    });
  }

  AiSeminarRunCardSnapshot? _seminarRunCardSnapshotFromState(
    AiSeminarRuntimeState state, {
    required List<AiSeminarEvidence> citedEvidence,
  }) {
    final evidence = citedEvidence
        .map(
          (item) => AiSeminarRunCardEvidenceSnapshot(
            id: item.id,
            title: _seminarEvidenceSnapshotTitle(item),
            snippet: _seminarEvidenceSnapshotSnippet(item),
            sourceRef: item.sourceRef,
          ),
        )
        .where((item) => !item.isEmpty)
        .toList(growable: false);
    final evidenceById = <String, AiSeminarEvidence>{
      for (final item in citedEvidence)
        if (item.id.trim().isNotEmpty) item.id.trim(): item,
    };
    final toolCalls = _seminarToolCallSnapshotsFromState(
      state,
      citedEvidence: citedEvidence,
    );
    final disagreementDetails = _seminarDisagreementDetailsFromState(
      state,
      evidenceById,
    );
    final contradictionScans = _seminarContradictionScanPartsFromDisagreements(
      disagreementDetails,
    );
    final completedRoleTurns = <MapEntry<int, AiSeminarRoleTurn>>[];
    for (var index = 0; index < state.turns.length; index++) {
      final turn = state.turns[index];
      if (turn.isFailed || turn.responseText.trim().isEmpty) continue;
      completedRoleTurns.add(MapEntry<int, AiSeminarRoleTurn>(index, turn));
    }
    final roleSummaries = completedRoleTurns
        .map(
          (entry) => AiSeminarRunCardRoleSummary(
            roleId: entry.value.role.asString,
            label: _seminarRoleFallbackLabel(entry.value.role.asString),
            summary: entry.value.responseText.trim(),
            evidenceRefs: _seminarEvidenceSnapshotsForIds(
              entry.value.evidenceRefIds,
              evidenceById,
            ),
          ),
        )
        .toList(growable: false);
    final roleTurnParts = completedRoleTurns
        .map(
          (entry) => AiSeminarRunCardMessagePart(
            type: 'role_turn',
            agentRunId: _seminarRoleTurnAgentRunIdFromState(
              state,
              entry.value,
              entry.key,
            ),
            parentRunId: _seminarRoleTurnParentRunIdFromState(state),
            roleId: entry.value.role.asString,
            label: _seminarRoleFallbackLabel(entry.value.role.asString),
            text: entry.value.responseText.trim(),
            evidenceRefs: _seminarEvidenceSnapshotsForIds(
              entry.value.evidenceRefIds,
              evidenceById,
            ),
          ),
        )
        .toList(growable: false);
    final synthesis = state.synthesis;
    final directorState = state.directorState;
    final readerTurn = directorState?.lastUserIntervention;
    final stoppedDirectorPart = _seminarStoppedDirectorStatePartFromState(
      state,
    );
    final failedDirectorPart = _seminarFailedDirectorStatePartFromState(state);
    final directorPart = _seminarDirectorStatePartFromState(state);
    final directorThinkingPart = _seminarDirectorThinkingPartFromState(state);
    final disagreementRebuttals = _seminarDisagreementRebuttalPartsFromState(
      state,
      evidenceById,
    );
    final artifactActionsPart = _seminarArtifactActionsPartFromState(
      state,
      evidenceById,
    );
    final activeRole = state.activeRole;
    final partialRoleText = state.partialRoleText?.trim() ?? '';
    final activeRoleStatusPart =
        _seminarActiveRoleStatusMessagePartFromState(state);
    final completedRoleToolCallParts =
        _seminarCompletedRoleToolCallPartsFromState(
      state,
      completedRoleTurns,
    );
    final activeRoleToolCallParts =
        _seminarActiveRoleToolCallPartsFromState(state);
    final liveRoleAgentToolCallParts =
        _seminarLiveRoleAgentToolCallPartsFromState(state);
    final liveRoleAgentThinkingParts =
        _seminarLiveRoleAgentThinkingPartsFromState(state);
    final activeRoleRunId = activeRole == null || state.session == null
        ? null
        : '${state.session!.id}:role-${activeRole.asString}-${state.turns.length}';
    final hasLiveThinkingForActiveRole = activeRoleRunId != null &&
        liveRoleAgentThinkingParts.any(
          (part) => part.agentRunId == activeRoleRunId,
        );
    final activeRoleThinkingPart =
        _seminarActiveRoleThinkingMessagePartFromState(state);
    final activeRolePartialPart =
        _seminarActiveRolePartialMessagePartFromState(state);
    final directorSessionId = directorState?.sessionId.trim();
    final messageParts = <AiSeminarRunCardMessagePart>[
      if (evidence.isNotEmpty)
        AiSeminarRunCardMessagePart(
          type: 'evidence',
          id: 'evidence-bundle',
          label: _localizedSeminarCardText(
            zh: '证据快照',
            en: 'Evidence snapshot',
          ),
          evidenceRefs: evidence,
        ),
      if (activeRoleStatusPart != null) activeRoleStatusPart,
      ...liveRoleAgentToolCallParts,
      for (final toolCall in toolCalls)
        AiSeminarRunCardMessagePart(
          type: 'tool_call',
          id: toolCall.id,
          agentRunId: toolCall.agentRunId,
          parentRunId: toolCall.parentRunId,
          toolId: toolCall.toolId,
          status: toolCall.status,
          label: toolCall.label,
          text: toolCall.text,
          query: toolCall.query,
          resultCount: toolCall.resultCount,
          roleIds: toolCall.roleIds,
          evidenceRefs: toolCall.evidenceRefs,
        ),
      ...completedRoleToolCallParts,
      ...activeRoleToolCallParts,
      if (directorThinkingPart != null) directorThinkingPart,
      ...liveRoleAgentThinkingParts,
      ...roleTurnParts,
      if (activeRole != null &&
          partialRoleText.isEmpty &&
          !hasLiveThinkingForActiveRole &&
          activeRoleThinkingPart != null)
        activeRoleThinkingPart,
      if (activeRole != null &&
          partialRoleText.isNotEmpty &&
          activeRolePartialPart != null)
        activeRolePartialPart,
      if (readerTurn != null && _shouldIncludeSeminarReaderTurn(readerTurn))
        AiSeminarRunCardMessagePart(
          type: 'reader_turn',
          id: readerTurn.id,
          agentRunId: _seminarReaderTurnAgentRunId(readerTurn),
          parentRunId: _seminarReaderTurnParentRunId(state, readerTurn),
          roleId: readerTurn.targetRole?.asString,
          label: _seminarReaderTurnLabel(readerTurn),
          status: _seminarReaderTurnStatusFromState(state, readerTurn),
          text: _seminarReaderTurnText(readerTurn),
          completedAt: _seminarReaderTurnCompletedAtFromState(
            state,
            readerTurn,
          ),
        ),
      if (stoppedDirectorPart != null) stoppedDirectorPart,
      if (failedDirectorPart != null) failedDirectorPart,
      if (directorPart != null) directorPart,
      if (directorState?.needsUserInput == true)
        AiSeminarRunCardMessagePart(
          type: 'reader_composer',
          id: directorSessionId != null && directorSessionId.isNotEmpty
              ? 'composer-$directorSessionId'
              : null,
          label: directorState!.nextIntent.asString,
          text: _seminarCardFirstOpenQuestion(state),
          roleIds: _seminarComposerRoleIdsFromState(state),
          actionIds: const [
            'ask-role',
            'refresh-evidence',
            'synthesize',
            'clarify',
          ],
          defaultRoleId: _seminarComposerDefaultRoleIdFromState(state),
          defaultActionId: 'ask-role',
          selectedRoleId: _seminarComposerSelectedRoleIdFromState(state),
          selectedActionId: _seminarComposerSelectedActionIdFromState(state),
          draftText: _seminarComposerDraftTextFromState(state),
        ),
      if (synthesis != null && synthesis.summary.trim().isNotEmpty)
        AiSeminarRunCardMessagePart(
          type: 'synthesis',
          agentRunId: _seminarRoleTurnParentRunIdFromState(state),
          text: synthesis.summary.trim(),
          evidenceRefs: synthesis.evidenceRefIds
              .map((id) => evidenceById[id.trim()])
              .whereType<AiSeminarEvidence>()
              .map(
                (item) => AiSeminarRunCardEvidenceSnapshot(
                  id: item.id,
                  title: _seminarEvidenceSnapshotTitle(item),
                  snippet: _seminarEvidenceSnapshotSnippet(item),
                  sourceRef: item.sourceRef,
                ),
              )
              .where((item) => !item.isEmpty)
              .toList(growable: false),
        ),
      if (synthesis != null)
        ..._seminarReviewTriagePartsFromSynthesis(
          synthesis,
          evidenceById,
        ),
      if (artifactActionsPart != null) artifactActionsPart,
      for (final detail in disagreementDetails)
        AiSeminarRunCardMessagePart(
          type: 'disagreement',
          text: detail.text,
          roleIds: detail.roleIds,
          evidenceRefs: detail.evidenceRefs,
        ),
      ...contradictionScans,
      ...disagreementRebuttals,
    ];
    final snapshot = AiSeminarRunCardSnapshot(
      evidence: evidence,
      toolCalls: toolCalls,
      roleSummaries: roleSummaries,
      messageParts: messageParts,
      synthesisSummary: synthesis?.summary.trim(),
      disagreements: synthesis?.disagreements ?? const <String>[],
      disagreementDetails: disagreementDetails,
      openQuestions: synthesis?.openQuestions ?? const <String>[],
    );
    return snapshot.isEmpty ? null : snapshot;
  }

  AiSeminarRunCardMessagePart? _seminarActiveRoleStatusMessagePartFromState(
    AiSeminarRuntimeState state,
  ) {
    final session = state.session;
    final activeRole = state.activeRole;
    if (session == null ||
        activeRole == null ||
        state.status != AiSeminarRunStatus.running) {
      return null;
    }
    final sessionId = session.id.trim();
    if (sessionId.isEmpty) return null;
    final roleId = activeRole.asString;
    final activeControlRunId = state.activeAgentControlRunId?.trim();
    final runId = activeControlRunId != null && activeControlRunId.isNotEmpty
        ? activeControlRunId
        : '$sessionId:role-$roleId-${state.turns.length}';
    final profile = session.roleProfileFor(activeRole);
    final allowedToolIds = _effectiveSeminarStatusAllowedToolIds(
      profile?.allowedToolIds ?? const <String>[],
      bookId: session.bookId,
    );
    return seminarMessagePartFromAgentRunEvent(AgentRunEvent(
      eventId: '$runId:status:running:live',
      runId: runId,
      parentRunId: sessionId,
      type: AgentRunEventType.status,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        state.startedAt ?? session.createdAt ?? 0,
      ),
      status: SubAgentRunStatus.running,
      roleId: roleId,
      nickname: _seminarRoleFallbackLabel(roleId),
      allowedToolIds: allowedToolIds,
    ));
  }

  List<AiSeminarRunCardMessagePart> _seminarActiveRoleToolCallPartsFromState(
    AiSeminarRuntimeState state,
  ) {
    final activeRole = state.activeRole;
    if (activeRole == null) return const <AiSeminarRunCardMessagePart>[];
    return _seminarRoleToolCallPartsFromState(
      state,
      role: activeRole,
      turnIndex: state.turns.length,
    );
  }

  List<AiSeminarRunCardMessagePart> _seminarLiveRoleAgentToolCallPartsFromState(
    AiSeminarRuntimeState state,
  ) {
    final sessionId = state.session?.id.trim();
    if (sessionId == null || sessionId.isEmpty) {
      return const <AiSeminarRunCardMessagePart>[];
    }
    final events = state.roleAgentToolCallEvents.where(
      (event) =>
          event.type == AgentRunEventType.toolCall &&
          event.parentRunId?.trim() == sessionId,
    );
    return seminarMessagePartsFromAgentRunEvents(events)
        .where((part) => part.type.trim() == 'tool_call')
        .where((part) => !part.isEmpty)
        .where(
          (part) => _seminarSnapshotMessagePartVisibleInContext(
            part,
            bookId: state.session?.bookId,
            evidenceScopeIds: state.session?.scopes
                    .map((scope) => scope.asString)
                    .toList(growable: false) ??
                const <String>[],
          ),
        )
        .toList(growable: false);
  }

  List<AiSeminarRunCardMessagePart> _seminarLiveRoleAgentThinkingPartsFromState(
    AiSeminarRuntimeState state,
  ) {
    final sessionId = state.session?.id.trim();
    if (sessionId == null || sessionId.isEmpty) {
      return const <AiSeminarRunCardMessagePart>[];
    }
    final events = state.roleAgentThinkingEvents.where(
      (event) =>
          event.type == AgentRunEventType.thinking &&
          event.parentRunId?.trim() == sessionId &&
          (state.partialRoleText?.trim().isNotEmpty != true ||
              state.activeRole == null ||
              event.roleId != state.activeRole!.asString),
    );
    return seminarMessagePartsFromAgentRunEvents(events)
        .where((part) => !part.isEmpty)
        .toList(growable: false);
  }

  List<AiSeminarRunCardMessagePart> _seminarCompletedRoleToolCallPartsFromState(
    AiSeminarRuntimeState state,
    List<MapEntry<int, AiSeminarRoleTurn>> completedRoleTurns,
  ) {
    if (completedRoleTurns.isEmpty) {
      return const <AiSeminarRunCardMessagePart>[];
    }
    final out = <AiSeminarRunCardMessagePart>[];
    for (final entry in completedRoleTurns) {
      out.addAll(_seminarRoleToolCallPartsFromState(
        state,
        role: entry.value.role,
        turnIndex: entry.key,
      ));
    }
    return out;
  }

  List<AiSeminarRunCardMessagePart> _seminarRoleToolCallPartsFromState(
    AiSeminarRuntimeState state, {
    required AiSeminarRole role,
    required int turnIndex,
  }) {
    final session = state.session;
    final bundle = state.evidenceBundle;
    if (session == null || bundle == null || bundle.evidence.isEmpty) {
      return const <AiSeminarRunCardMessagePart>[];
    }
    final profile = session.roleProfileFor(role);
    final allowedToolIds = _effectiveSeminarStatusAllowedToolIds(
      profile?.allowedToolIds ?? const <String>[],
      bookId: session.bookId,
    );
    if (allowedToolIds.isEmpty) return const <AiSeminarRunCardMessagePart>[];

    final evidenceByToolId = <String, List<AiSeminarEvidence>>{};
    for (final evidence in bundle.evidence) {
      if (!evidence.isTraceable) continue;
      if (!_seminarRoleProfileCanSeeScope(profile, evidence.scope)) continue;
      final toolId = _seminarEvidenceScopeToolId(evidence.scope);
      if (toolId == null || !allowedToolIds.contains(toolId)) continue;
      evidenceByToolId.putIfAbsent(toolId, () => <AiSeminarEvidence>[]).add(
            evidence,
          );
    }

    final sessionId = session.id.trim();
    if (sessionId.isEmpty) return const <AiSeminarRunCardMessagePart>[];
    final roleId = role.asString;
    final runId = '$sessionId:role-$roleId-$turnIndex';
    final liveToolIds = state.roleAgentToolCallEvents
        .where(
          (event) =>
              event.type == AgentRunEventType.toolCall &&
              event.runId.trim() == runId,
        )
        .map((event) => event.toolId?.trim() ?? '')
        .where((toolId) => toolId.isNotEmpty)
        .toSet();
    final query = bundle.query.trim().isNotEmpty
        ? bundle.query.trim()
        : session.question.trim();
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      state.startedAt ?? session.createdAt ?? 0,
    );
    final out = <AiSeminarRunCardMessagePart>[];
    for (final toolId in allowedToolIds) {
      if (liveToolIds.contains(toolId)) continue;
      final evidence = evidenceByToolId[toolId] ?? const <AiSeminarEvidence>[];
      if (evidence.isEmpty) continue;
      final part = seminarMessagePartFromAgentRunEvent(AgentRunEvent(
        eventId: '$runId:tool:$toolId',
        runId: runId,
        parentRunId: sessionId,
        type: AgentRunEventType.toolCall,
        createdAt: createdAt,
        status: SubAgentRunStatus.completed,
        roleId: roleId,
        nickname: _seminarRoleFallbackLabel(roleId),
        toolId: toolId,
        query: query,
        result: _seminarToolCallSummaryText(evidence.length),
        resultCount: evidence.length,
        roleIds: [roleId],
        evidenceRefs: evidence
            .map(_seminarEvidenceSnapshotFromEvidence)
            .where((snapshot) => !snapshot.isEmpty)
            .toList(growable: false),
      ));
      if (part != null && !part.isEmpty) out.add(part);
    }
    return out;
  }

  String _seminarReaderTurnLabel(AiSeminarUserIntervention readerTurn) {
    final id = readerTurn.id.trim();
    if (id.contains(':user-input:')) return 'send-input';
    if (id.contains(':resume-request:')) return 'resume-agent';
    if (id.contains(':retry-request:')) return 'retry-agent-control';
    return readerTurn.requestedAction.asString;
  }

  String? _seminarReaderTurnText(AiSeminarUserIntervention readerTurn) {
    final text = readerTurn.text.trim();
    if (text.isEmpty) return null;
    final label = _seminarReaderTurnLabel(readerTurn);
    if (label == 'resume-agent' && text == 'Resume requested.') return null;
    if (label == 'retry-agent-control' && text == 'Retry requested.') {
      return null;
    }
    return text;
  }

  bool _shouldIncludeSeminarReaderTurn(
    AiSeminarUserIntervention readerTurn,
  ) {
    if (readerTurn.text.trim().isNotEmpty) return true;
    final id = readerTurn.id.trim();
    return id.contains(':resume-request:') || id.contains(':retry-request:');
  }

  String? _seminarReaderTurnAgentRunId(
    AiSeminarUserIntervention readerTurn,
  ) {
    final id = readerTurn.id.trim();
    for (final marker in const [
      ':user-input:',
      ':resume-request:',
      ':retry-request:',
    ]) {
      final index = id.indexOf(marker);
      if (index > 0) return id.substring(0, index);
    }
    return null;
  }

  String? _seminarReaderTurnParentRunId(
    AiSeminarRuntimeState state,
    AiSeminarUserIntervention readerTurn,
  ) {
    if (_seminarReaderTurnAgentRunId(readerTurn) == null) return null;
    final sessionId = state.session?.id.trim();
    if (sessionId == null || sessionId.isEmpty) return null;
    return sessionId;
  }

  String? _seminarReaderTurnStatusFromState(
    AiSeminarRuntimeState state,
    AiSeminarUserIntervention readerTurn,
  ) {
    if (!_isSeminarAgentControlReaderTurn(readerTurn)) return null;
    if (state.status == AiSeminarRunStatus.completed) return 'completed';
    if (state.status == AiSeminarRunStatus.cancelled) return 'cancelled';
    if (state.status == AiSeminarRunStatus.running) {
      final activeRole = state.activeRole;
      if (activeRole != null) {
        if (activeRole == readerTurn.targetRole) return 'running';
        return null;
      }
      final activeControlRunId = state.activeAgentControlRunId?.trim();
      if (activeControlRunId != null &&
          activeControlRunId.isNotEmpty &&
          activeControlRunId == _seminarReaderTurnAgentRunId(readerTurn)) {
        return 'running';
      }
    }
    return null;
  }

  int? _seminarReaderTurnCompletedAtFromState(
    AiSeminarRuntimeState state,
    AiSeminarUserIntervention readerTurn,
  ) {
    final status = _seminarReaderTurnStatusFromState(state, readerTurn);
    if (status != 'completed' && status != 'cancelled') {
      return null;
    }
    return state.completedAt;
  }

  bool _isSeminarAgentControlReaderTurn(
    AiSeminarUserIntervention readerTurn,
  ) {
    final id = readerTurn.id.trim();
    return id.contains(':user-input:') ||
        id.contains(':resume-request:') ||
        id.contains(':retry-request:');
  }

  String? _seminarRoleTurnParentRunIdFromState(
    AiSeminarRuntimeState state,
  ) {
    final sessionId = state.session?.id.trim();
    if (sessionId == null || sessionId.isEmpty) return null;
    return sessionId;
  }

  String? _seminarRoleTurnAgentRunIdFromState(
    AiSeminarRuntimeState state,
    AiSeminarRoleTurn turn,
    int turnIndex,
  ) {
    final parentRunId = _seminarRoleTurnParentRunIdFromState(state);
    if (parentRunId == null) return null;
    final turnId = turn.id.trim();
    if (turnId.startsWith('$parentRunId:role-')) return turnId;
    if (turnId.startsWith('role-')) return '$parentRunId:$turnId';
    return '$parentRunId:role-${turn.role.asString}-$turnIndex';
  }

  AiSeminarRunCardMessagePart? _seminarDirectorThinkingPartFromState(
    AiSeminarRuntimeState state,
  ) {
    final directorState = state.directorState;
    if (directorState == null) return null;
    final text = _seminarDirectorThinkingTextFromState(state)?.trim();
    if (text == null || text.isEmpty) return null;
    final sessionId = directorState.sessionId.trim();
    return AiSeminarRunCardMessagePart(
      type: 'thinking',
      id: sessionId.isEmpty
          ? null
          : 'director-thinking-$sessionId-${directorState.nextIntent.asString}',
      agentRunId: sessionId.isEmpty ? null : sessionId,
      label: directorState.nextIntent.asString,
      text: text,
    );
  }

  String? _seminarDirectorThinkingTextFromState(
    AiSeminarRuntimeState state,
  ) {
    switch (state.directorState?.nextIntent) {
      case AiSeminarDirectorNextIntent.runRole:
        return _localizedSeminarCardText(
          zh: '主持人正在协调下一位角色基于证据发言。',
          en: 'Director is coordinating the next evidence-bound role turn.',
        );
      case AiSeminarDirectorNextIntent.refreshEvidence:
        return _localizedSeminarCardText(
          zh: '正在补充证据,已有发言保留',
          en: 'Director is checking which disagreements need more evidence.',
        );
      case AiSeminarDirectorNextIntent.askUser:
        return null;
      case AiSeminarDirectorNextIntent.synthesize:
        return _localizedSeminarCardText(
          zh: '正在整理总结…',
          en: 'Director is preparing an evidence-bound synthesis.',
        );
      case AiSeminarDirectorNextIntent.end:
        if (state.synthesis == null && state.turns.isEmpty) return null;
        return _localizedSeminarCardText(
          zh: '主持人已基于证据和角色发言出总结。',
          en: 'Director reviewed evidence and role turns before synthesis.',
        );
      case null:
        return null;
    }
  }

  AiSeminarRunCardMessagePart? _seminarActiveRolePartialMessagePartFromState(
    AiSeminarRuntimeState state,
  ) {
    final session = state.session;
    final activeRole = state.activeRole;
    final partialText = state.partialRoleText?.trim();
    if (session == null ||
        activeRole == null ||
        partialText == null ||
        partialText.isEmpty) {
      return null;
    }
    final runId =
        '${session.id}:role-${activeRole.asString}-${state.turns.length}';
    return seminarMessagePartFromAgentRunEvent(AgentRunEvent(
      eventId: '$runId:delta:latest',
      runId: runId,
      parentRunId: session.id,
      type: AgentRunEventType.messageDelta,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        state.startedAt ?? session.createdAt ?? 0,
      ),
      roleId: activeRole.asString,
      nickname: _seminarRoleFallbackLabel(activeRole.asString),
      delta: partialText,
    ));
  }

  AiSeminarRunCardMessagePart? _seminarActiveRoleThinkingMessagePartFromState(
    AiSeminarRuntimeState state,
  ) {
    final session = state.session;
    final activeRole = state.activeRole;
    final partialText = state.partialRoleText?.trim() ?? '';
    if (session == null || activeRole == null || partialText.isNotEmpty) {
      return null;
    }
    final runId =
        '${session.id}:role-${activeRole.asString}-${state.turns.length}';
    final nickname = _seminarRoleFallbackLabel(activeRole.asString);
    return seminarMessagePartFromAgentRunEvent(AgentRunEvent(
      eventId: '$runId:thinking:start',
      runId: runId,
      parentRunId: session.id,
      type: AgentRunEventType.thinking,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        state.startedAt ?? session.createdAt ?? 0,
      ),
      roleId: activeRole.asString,
      nickname: nickname,
      delta: _localizedSeminarCardText(
        zh: '$nickname正在准备基于证据发言。',
        en: '$nickname is preparing an evidence-grounded seminar response.',
      ),
    ));
  }

  AiSeminarRunCardMessagePart? _seminarDirectorStatePartFromState(
    AiSeminarRuntimeState state,
  ) {
    final directorState = state.directorState;
    if (directorState == null ||
        directorState.nextIntent == AiSeminarDirectorNextIntent.runRole) {
      return null;
    }
    final sessionId = directorState.sessionId.trim();
    return AiSeminarRunCardMessagePart(
      type: 'director_state',
      id: sessionId.isEmpty ? null : 'director-$sessionId',
      label: directorState.nextIntent.asString,
      text: _seminarDirectorCueTextFromState(state),
    );
  }

  AiSeminarRunCardMessagePart? _seminarFailedDirectorStatePartFromState(
    AiSeminarRuntimeState state,
  ) {
    if (state.status != AiSeminarRunStatus.failed) return null;
    final sessionId = state.session?.id.trim();
    final error = state.error?.trim();
    if (sessionId == null ||
        sessionId.isEmpty ||
        error == null ||
        error.isEmpty) {
      return null;
    }
    return AiSeminarRunCardMessagePart(
      type: 'director_state',
      id: 'director-$sessionId:failed',
      agentRunId: sessionId,
      roleId: 'director',
      label: 'failed',
      status: 'failed',
      text: error,
      actionIds: const ['retry-agent-control'],
    );
  }

  AiSeminarRunCardMessagePart? _seminarStoppedDirectorStatePartFromState(
    AiSeminarRuntimeState state,
  ) {
    if (state.status != AiSeminarRunStatus.cancelled) return null;
    final sessionId = state.session?.id.trim();
    if (sessionId == null || sessionId.isEmpty) return null;
    final message = state.error?.trim();
    return AiSeminarRunCardMessagePart(
      type: 'director_state',
      id: 'director-$sessionId:stopped',
      agentRunId: sessionId,
      roleId: 'director',
      label: 'stopped',
      status: 'cancelled',
      text: message != null && message.isNotEmpty
          ? message
          : _localizedSeminarCardText(
              zh: 'AI 研讨会已停止。',
              en: 'AI Seminar was stopped.',
            ),
    );
  }

  String? _seminarDirectorCueTextFromState(AiSeminarRuntimeState state) {
    final directorState = state.directorState;
    switch (directorState?.nextIntent) {
      case AiSeminarDirectorNextIntent.askUser:
        return _seminarCardFirstOpenQuestion(state);
      case AiSeminarDirectorNextIntent.refreshEvidence:
        final error = state.error?.trim();
        if (error != null && error.isNotEmpty) return error;
        final firstDisagreement = _seminarCardFirstDisagreement(state);
        if (firstDisagreement != null && firstDisagreement.isNotEmpty) {
          return firstDisagreement;
        }
        return _localizedSeminarCardText(
          zh: '需要补充可追踪证据。',
          en: 'Traceable evidence needs to be refreshed.',
        );
      case AiSeminarDirectorNextIntent.synthesize:
        final text = directorState?.lastUserIntervention?.text.trim();
        return text == null || text.isEmpty ? null : text;
      case AiSeminarDirectorNextIntent.end:
        final summary = state.synthesis?.summary.trim();
        return summary == null || summary.isEmpty ? null : summary;
      case AiSeminarDirectorNextIntent.runRole:
      case null:
        return null;
    }
  }

  String? _seminarCardFirstDisagreement(AiSeminarRuntimeState state) {
    for (final entry in state.whiteboardEntries) {
      if (entry.kind != AiSeminarWhiteboardKind.disagreement) continue;
      final text = entry.text.trim();
      if (text.isNotEmpty) return text;
    }
    final synthesisDisagreement = state.synthesis?.disagreements
        .map((item) => item.trim())
        .firstWhere((item) => item.isNotEmpty, orElse: () => '');
    return synthesisDisagreement == null || synthesisDisagreement.isEmpty
        ? null
        : synthesisDisagreement;
  }

  List<AiSeminarRunCardMessagePart> _seminarReviewTriagePartsFromSynthesis(
    AiSeminarSynthesis synthesis,
    Map<String, AiSeminarEvidence> evidenceById,
  ) {
    if (!synthesis.readyForReview || !synthesis.hasTraceableHandoff) {
      return const <AiSeminarRunCardMessagePart>[];
    }
    final parts = <AiSeminarRunCardMessagePart>[];
    for (final reason in _seminarReviewReasonTexts(synthesis)) {
      parts.add(
        AiSeminarRunCardMessagePart(
          type: 'review_triage',
          label: 'reason',
          text: reason,
        ),
      );
    }
    final suggestion = _seminarReviewTriageSuggestionText(synthesis);
    if (suggestion != null && suggestion.isNotEmpty) {
      parts.add(
        AiSeminarRunCardMessagePart(
          type: 'review_triage',
          label: 'ai-suggestion',
          text: suggestion,
        ),
      );
    }
    parts.add(
      AiSeminarRunCardMessagePart(
        type: 'review_triage',
        label: 'risk',
        text: _seminarReviewRiskLevel(synthesis),
      ),
    );
    parts.add(
      AiSeminarRunCardMessagePart(
        type: 'review_triage',
        label: 'suggested-action',
        text: _seminarReviewSuggestedAction(synthesis),
      ),
    );
    for (final candidate in synthesis.candidateCards) {
      final text = candidate.text.trim();
      if (text.isEmpty) continue;
      final evidenceRefs = _seminarEvidenceSnapshotsForIds(
        candidate.evidenceRefIds,
        evidenceById,
      );
      parts.add(
        AiSeminarRunCardMessagePart(
          type: 'review_triage',
          label: 'knowledge-card',
          text: text,
          evidenceRefs: evidenceRefs,
        ),
      );
    }
    final synthesisEvidenceRefs = _seminarEvidenceSnapshotsForIds(
      synthesis.evidenceRefIds,
      evidenceById,
    );
    final seenQuestions = <String>{};
    for (final rawQuestion in synthesis.candidateReviewQuestions) {
      final question = rawQuestion.trim();
      if (question.isEmpty || !seenQuestions.add(question.toLowerCase())) {
        continue;
      }
      parts.add(
        AiSeminarRunCardMessagePart(
          type: 'review_triage',
          label: 'spaced-review',
          text: question,
          evidenceRefs: synthesisEvidenceRefs,
        ),
      );
    }
    return parts;
  }

  AiSeminarRunCardMessagePart? _seminarArtifactActionsPartForCurrentState(
    AiSeminarRuntimeState state,
  ) {
    final citedEvidence = _seminarCitedTraceableEvidenceFromState(state);
    final evidenceById = <String, AiSeminarEvidence>{
      for (final item in citedEvidence)
        if (item.id.trim().isNotEmpty) item.id.trim(): item,
    };
    return _seminarArtifactActionsPartFromState(state, evidenceById);
  }

  AiSeminarRunCardMessagePart? _seminarArtifactActionsPartFromState(
    AiSeminarRuntimeState state,
    Map<String, AiSeminarEvidence> evidenceById,
  ) {
    final sessionId = state.session?.id.trim();
    final synthesis = state.synthesis;
    if (sessionId == null ||
        sessionId.isEmpty ||
        synthesis == null ||
        synthesis.summary.trim().isEmpty) {
      return null;
    }
    final hasTraceableSynthesisRefs =
        _seminarSynthesisKnowledgeCardSourceRefs(state).isNotEmpty;
    final knowledgeCardId = _seminarSynthesisKnowledgeCardId(sessionId);
    final hasSavedKnowledgeCard = knowledgeCardId != null &&
        _seminarCardSavedKnowledgeCardIds.contains(knowledgeCardId);
    final reviewFlashcardId = _seminarSynthesisReviewFlashcardId(sessionId);
    final hasAddedSpacedReview = reviewFlashcardId != null &&
        _seminarCardSpacedReviewFlashcardIds.contains(reviewFlashcardId);
    final conceptNodeId = _seminarSynthesisConceptNodeId(sessionId);
    final hasAddedConceptGraph = conceptNodeId != null &&
        _seminarCardConceptNodeIds.contains(conceptNodeId);
    final hasSentToReview =
        _seminarCardSentToReviewSessionIds.contains(sessionId.trim());
    final canReviewHandoff = state.canSendToReview || hasSentToReview;
    final isIgnored =
        _seminarCardIgnoredActionSessionIds.contains(sessionId.trim());
    final evidenceRefs = _seminarEvidenceSnapshotsForIds(
      synthesis.evidenceRefIds,
      evidenceById,
    );
    if (isIgnored && (hasTraceableSynthesisRefs || canReviewHandoff)) {
      return AiSeminarRunCardMessagePart(
        type: 'artifact_actions',
        id: 'artifact-actions-$sessionId',
        agentRunId: sessionId,
        label: 'ignored',
        text: _localizedSeminarCardText(
          zh: '沉淀建议已忽略；可恢复操作。',
          en: 'Artifact suggestions ignored; actions can be restored.',
        ),
        actionIds: const [
          'artifact-actions-ignored',
          'restore-artifact-actions',
        ],
        evidenceRefs: evidenceRefs,
      );
    }
    final actionIds = <String>[
      if (hasTraceableSynthesisRefs) ...[
        if (hasSavedKnowledgeCard) ...[
          'knowledge-card-saved',
          'undo-knowledge-card',
        ] else ...[
          'save-knowledge-card',
          'edit-knowledge-card',
        ],
        if (hasAddedSpacedReview) ...[
          'spaced-review-added',
          'undo-spaced-review',
        ] else
          'add-spaced-review',
        if (hasAddedConceptGraph) ...[
          'concept-graph-added',
          'undo-concept-graph',
        ] else
          'add-concept-graph',
      ],
      if (canReviewHandoff)
        hasSentToReview ? 'sent-to-review' : 'send-to-review',
      if (hasTraceableSynthesisRefs || canReviewHandoff)
        'ignore-artifact-actions',
    ];
    if (actionIds.isEmpty) return null;
    return AiSeminarRunCardMessagePart(
      type: 'artifact_actions',
      id: 'artifact-actions-$sessionId',
      agentRunId: sessionId,
      label: 'available',
      text: _seminarArtifactActionsText(
        canSaveInline: hasTraceableSynthesisRefs,
        canSendToReview: state.canSendToReview,
        hasSavedKnowledgeCard: hasSavedKnowledgeCard,
        hasAddedSpacedReview: hasAddedSpacedReview,
        hasAddedConceptGraph: hasAddedConceptGraph,
        hasSentToReview: hasSentToReview,
      ),
      actionIds: actionIds,
      evidenceRefs: evidenceRefs,
    );
  }

  String _seminarArtifactActionsText({
    required bool canSaveInline,
    required bool canSendToReview,
    required bool hasSavedKnowledgeCard,
    required bool hasAddedSpacedReview,
    required bool hasAddedConceptGraph,
    required bool hasSentToReview,
  }) {
    final completed = <String>[
      if (hasSavedKnowledgeCard)
        _localizedSeminarCardText(
          zh: '知识卡已保存',
          en: 'KnowledgeCard saved',
        ),
      if (hasAddedSpacedReview)
        _localizedSeminarCardText(
          zh: '复习已加入',
          en: 'Review added',
        ),
      if (hasAddedConceptGraph)
        _localizedSeminarCardText(
          zh: '图谱已加入',
          en: 'Graph added',
        ),
      if (hasSentToReview)
        _localizedSeminarCardText(
          zh: '异常已送审',
          en: 'Exception sent to triage',
        ),
    ];
    if (completed.isNotEmpty) {
      final prefix = completed.join(_localizedSeminarCardText(
        zh: '；',
        en: '; ',
      ));
      if (canSendToReview && !hasSentToReview) {
        return _localizedSeminarCardText(
          zh: '$prefix；仍可继续处理其他沉淀动作，异常时可送审。',
          en: '$prefix; remaining artifact actions are still available, and exceptions can go to triage.',
        );
      }
      if (!canSaveInline) return prefix;
      return _localizedSeminarCardText(
        zh: '$prefix；仍可继续处理其他沉淀动作。',
        en: '$prefix; remaining artifact actions are still available.',
      );
    }
    if (canSaveInline && canSendToReview) {
      return _localizedSeminarCardText(
        zh: '可保存为知识卡、加入复习、加入我的图谱；异常时可送审。',
        en: 'Can be saved as a card, review, or graph item; exceptions can go to triage.',
      );
    }
    if (canSaveInline) {
      return _localizedSeminarCardText(
        zh: '可保存为知识卡、加入复习或加入我的图谱。',
        en: 'Can be saved as a card, review, or graph item.',
      );
    }
    return _localizedSeminarCardText(
      zh: '异常内容可送审处理。',
      en: 'Exception content can go to triage.',
    );
  }

  List<AiSeminarRunCardMessagePart>
      _seminarContradictionScanPartsFromDisagreements(
    List<AiSeminarRunCardDisagreementDetail> disagreementDetails,
  ) {
    final parts = <AiSeminarRunCardMessagePart>[];
    final seen = <String>{};
    for (final detail in disagreementDetails) {
      final text = detail.text.trim();
      if (text.isEmpty) continue;
      final key = text.toLowerCase();
      if (!seen.add(key)) continue;
      parts.add(
        AiSeminarRunCardMessagePart(
          type: 'contradiction_scan',
          id: 'contradiction-scan-${parts.length + 1}',
          label: detail.evidenceRefs.where((item) => !item.isEmpty).isEmpty
              ? 'evidence-gap'
              : 'disagreement',
          text: text,
          roleIds: detail.roleIds,
          evidenceRefs: detail.evidenceRefs,
        ),
      );
    }
    return _seminarPrioritizedContradictionScanParts(parts);
  }

  List<AiSeminarRunCardMessagePart> _seminarDisagreementRebuttalPartsFromState(
    AiSeminarRuntimeState state,
    Map<String, AiSeminarEvidence> evidenceById,
  ) {
    final parts = <AiSeminarRunCardMessagePart>[];
    final seenTurnKeys = <String>{};

    void addRebuttal({
      required AiSeminarRoleTurn turn,
      required String disagreement,
    }) {
      final text = turn.responseText.trim();
      final label = disagreement.trim();
      if (turn.isFailed || text.isEmpty || label.isEmpty) return;
      final turnId = turn.id.trim();
      final key = turnId.isNotEmpty
          ? turnId
          : [
              turn.role.asString,
              label.toLowerCase(),
              text,
            ].join('\n');
      if (!seenTurnKeys.add(key)) return;
      parts.add(
        AiSeminarRunCardMessagePart(
          type: 'disagreement_rebuttal',
          id: turnId.isEmpty ? null : turnId,
          roleId: turn.role.asString,
          label: label,
          text: text,
          evidenceRefs: _seminarEvidenceSnapshotsForIds(
            turn.evidenceRefIds,
            evidenceById,
          ),
        ),
      );
    }

    for (final turn in state.turns) {
      final disagreement = _seminarDisagreementFromRolePrompt(turn.prompt);
      if (disagreement == null || disagreement.isEmpty) continue;
      addRebuttal(turn: turn, disagreement: disagreement);
    }
    if (parts.isNotEmpty) return parts;

    final intervention = state.directorState?.lastUserIntervention;
    final targetRole = intervention?.targetRole;
    final disagreement = _seminarDisagreementFromIntervention(intervention);
    if (intervention == null ||
        intervention.requestedAction !=
            AiSeminarUserInterventionAction.askRole ||
        targetRole == null ||
        disagreement == null ||
        disagreement.isEmpty) {
      return const <AiSeminarRunCardMessagePart>[];
    }
    AiSeminarRoleTurn? rebuttalTurn;
    for (final turn in state.turns.reversed) {
      if (turn.role == targetRole &&
          !turn.isFailed &&
          turn.responseText.trim().isNotEmpty) {
        rebuttalTurn = turn;
        break;
      }
    }
    if (rebuttalTurn == null) return const <AiSeminarRunCardMessagePart>[];
    addRebuttal(turn: rebuttalTurn, disagreement: disagreement);
    return parts;
  }

  String? _seminarDisagreementFromRolePrompt(String prompt) {
    const marker = 'Reader intervention:';
    final markerIndex = prompt.indexOf(marker);
    if (markerIndex < 0) return null;
    final afterMarker =
        prompt.substring(markerIndex + marker.length).trimLeft();
    final lineBreak = afterMarker.indexOf('\n');
    final interventionText = lineBreak < 0
        ? afterMarker.trim()
        : afterMarker.substring(0, lineBreak).trim();
    return _seminarDisagreementFromInterventionText(interventionText);
  }

  String? _seminarDisagreementFromIntervention(
    AiSeminarUserIntervention? intervention,
  ) {
    return _seminarDisagreementFromInterventionText(intervention?.text);
  }

  String? _seminarDisagreementFromInterventionText(String? rawText) {
    final text = rawText?.trim() ?? '';
    if (text.isEmpty) return null;
    const zhPrefix = '围绕分歧继续反驳：';
    const enPrefix = 'Continue the rebuttal around this disagreement: ';
    if (text.startsWith(zhPrefix)) {
      return text.substring(zhPrefix.length).trim();
    }
    if (text.startsWith(enPrefix)) {
      return text.substring(enPrefix.length).trim();
    }
    return null;
  }

  List<AiSeminarRunCardEvidenceSnapshot> _seminarEvidenceSnapshotsForIds(
    List<String> evidenceIds,
    Map<String, AiSeminarEvidence> evidenceById,
  ) {
    return evidenceIds
        .map((id) => evidenceById[id.trim()])
        .whereType<AiSeminarEvidence>()
        .where((item) => item.isTraceable)
        .map(
          (item) => AiSeminarRunCardEvidenceSnapshot(
            id: item.id,
            title: _seminarEvidenceSnapshotTitle(item),
            snippet: _seminarEvidenceSnapshotSnippet(item),
            sourceRef: item.sourceRef,
          ),
        )
        .where((item) => !item.isEmpty)
        .toList(growable: false);
  }

  List<AiSeminarRunCardToolCallSnapshot> _seminarToolCallSnapshotsFromState(
    AiSeminarRuntimeState state, {
    required List<AiSeminarEvidence> citedEvidence,
  }) {
    final bundle = state.evidenceBundle;
    if (bundle == null || bundle.evidence.isEmpty) {
      return bundle == null && state.status == AiSeminarRunStatus.running
          ? _seminarPendingToolCallSnapshotsFromState(state)
          : const <AiSeminarRunCardToolCallSnapshot>[];
    }

    final citedById = <String, AiSeminarEvidence>{
      for (final item in citedEvidence)
        if (item.id.trim().isNotEmpty) item.id.trim(): item,
    };
    final evidenceByScope = <AiSeminarEvidenceScope, List<AiSeminarEvidence>>{};
    for (final item in bundle.evidence) {
      if (!item.isTraceable) continue;
      if (!_seminarSessionCanShowEvidenceScope(state.session, item.scope)) {
        continue;
      }
      evidenceByScope.putIfAbsent(item.scope, () => <AiSeminarEvidence>[]).add(
            item,
          );
    }
    final out = <AiSeminarRunCardToolCallSnapshot>[];
    for (final entry in evidenceByScope.entries) {
      final toolId = _seminarEvidenceScopeToolId(entry.key);
      if (toolId == null) continue;
      final evidenceRefs = entry.value
          .where((item) => citedById.containsKey(item.id.trim()))
          .map(_seminarEvidenceSnapshotFromEvidence)
          .where((item) => !item.isEmpty)
          .toList(growable: false);
      final fallbackEvidenceRefs = evidenceRefs.isNotEmpty
          ? evidenceRefs
          : entry.value
              .map(_seminarEvidenceSnapshotFromEvidence)
              .where((item) => !item.isEmpty)
              .toList(growable: false);
      final call = AiSeminarRunCardToolCallSnapshot(
        id: 'evidence-${entry.key.asString}',
        toolId: toolId,
        status: 'completed',
        query: bundle.query.trim().isNotEmpty
            ? bundle.query.trim()
            : state.session?.question.trim() ?? '',
        text: _seminarToolCallSummaryText(entry.value.length),
        resultCount: entry.value.length,
        roleIds: _seminarToolCallRoleIdsForScope(state, entry.key),
        evidenceRefs: fallbackEvidenceRefs,
      );
      if (!call.isEmpty) out.add(call);
    }
    return out;
  }

  bool _seminarSessionCanShowEvidenceScope(
    AiSeminarSessionContract? session,
    AiSeminarEvidenceScope scope,
  ) {
    if (session == null) return true;
    final scopes = session.scopes;
    if (scopes.contains(scope)) return true;
    if (scope == AiSeminarEvidenceScope.currentBook) {
      return scopes.contains(AiSeminarEvidenceScope.currentChapter);
    }
    if (scope == AiSeminarEvidenceScope.currentChapter) {
      return scopes.contains(AiSeminarEvidenceScope.currentBook);
    }
    return false;
  }

  List<AiSeminarRunCardToolCallSnapshot>
      _seminarPendingToolCallSnapshotsFromState(
    AiSeminarRuntimeState state,
  ) {
    final session = state.session;
    if (session == null) return const <AiSeminarRunCardToolCallSnapshot>[];
    final out = <AiSeminarRunCardToolCallSnapshot>[];
    final seenToolIds = <String>{};
    for (final scope in session.scopes) {
      final toolId = _seminarEvidenceScopeToolId(scope);
      if (toolId == null || !seenToolIds.add(toolId)) continue;
      final call = AiSeminarRunCardToolCallSnapshot(
        id: 'evidence-${scope.asString}-pending',
        toolId: toolId,
        status: 'running',
        query: session.question,
        resultCount: 0,
        roleIds: _seminarToolCallRoleIdsForScope(state, scope),
      );
      if (!call.isEmpty) out.add(call);
    }
    return out.take(5).toList(growable: false);
  }

  List<String> _seminarToolCallRoleIdsForScope(
    AiSeminarRuntimeState state,
    AiSeminarEvidenceScope scope,
  ) {
    final session = state.session;
    if (session == null) return const <String>[];
    final out = <String>[];
    for (final role in session.roles) {
      final profile = session.roleProfileFor(role);
      if (!_seminarRoleProfileCanSeeScope(profile, scope)) continue;
      final roleId = role.asString.trim();
      if (roleId.isNotEmpty && !out.contains(roleId)) out.add(roleId);
    }
    return out;
  }

  bool _seminarRoleProfileCanSeeScope(
    AiSeminarRoleProfile? profile,
    AiSeminarEvidenceScope scope,
  ) {
    final scopes = profile?.evidenceScopes ?? const <AiSeminarEvidenceScope>[];
    if (scopes.isEmpty) return true;
    if (scopes.contains(scope)) return true;
    return scope == AiSeminarEvidenceScope.currentBook &&
        scopes.contains(AiSeminarEvidenceScope.currentChapter);
  }

  AiSeminarRunCardEvidenceSnapshot _seminarEvidenceSnapshotFromEvidence(
    AiSeminarEvidence evidence,
  ) {
    return AiSeminarRunCardEvidenceSnapshot(
      id: evidence.id,
      title: _seminarEvidenceSnapshotTitle(evidence),
      snippet: _seminarEvidenceSnapshotSnippet(evidence),
      sourceRef: evidence.sourceRef,
    );
  }

  String? _seminarEvidenceScopeToolId(AiSeminarEvidenceScope scope) {
    switch (scope) {
      case AiSeminarEvidenceScope.currentChapter:
      case AiSeminarEvidenceScope.currentBook:
        return 'semantic_search_current_book';
      case AiSeminarEvidenceScope.library:
        return 'semantic_search_library';
      case AiSeminarEvidenceScope.notes:
        return 'notes_search';
      case AiSeminarEvidenceScope.memory:
        return 'memory_search';
      case AiSeminarEvidenceScope.conceptGraph:
        return 'concept_graph_search';
    }
  }

  List<AiSeminarRunCardDisagreementDetail> _seminarDisagreementDetailsFromState(
    AiSeminarRuntimeState state,
    Map<String, AiSeminarEvidence> evidenceById,
  ) {
    final entries = <AiSeminarWhiteboardEntry>[];
    final seen = <String>{};

    void addEntry(AiSeminarWhiteboardEntry entry) {
      if (entry.kind != AiSeminarWhiteboardKind.disagreement) return;
      final id = entry.id.trim();
      final text = entry.text.trim();
      final key = id.isNotEmpty ? id : text;
      if (key.isEmpty || !seen.add(key)) return;
      entries.add(entry);
    }

    for (final turn in state.turns) {
      if (turn.isFailed) continue;
      for (final entry in turn.whiteboardEntries) {
        addEntry(entry);
      }
    }
    for (final entry in state.whiteboardEntries) {
      addEntry(entry);
    }

    return entries
        .map(
          (entry) => AiSeminarRunCardDisagreementDetail(
            text: entry.text,
            roleIds: _seminarDisagreementRoleIds(entry, state.turns),
            evidenceRefs: entry.evidenceRefIds
                .map((id) => evidenceById[id.trim()])
                .whereType<AiSeminarEvidence>()
                .map(
                  (item) => AiSeminarRunCardEvidenceSnapshot(
                    id: item.id,
                    title: _seminarEvidenceSnapshotTitle(item),
                    snippet: _seminarEvidenceSnapshotSnippet(item),
                    sourceRef: item.sourceRef,
                  ),
                )
                .where((item) => !item.isEmpty)
                .toList(growable: false),
          ),
        )
        .where((detail) => !detail.isEmpty)
        .toList(growable: false);
  }

  List<String> _seminarDisagreementRoleIds(
    AiSeminarWhiteboardEntry entry,
    List<AiSeminarRoleTurn> turns,
  ) {
    final out = <String>[];
    void addRole(AiSeminarRole? role) {
      final roleId = role?.asString.trim();
      if (roleId == null || roleId.isEmpty || out.contains(roleId)) return;
      out.add(roleId);
    }

    addRole(entry.role);
    for (final turn in turns) {
      if (turn.isFailed) continue;
      final hasEntry = turn.whiteboardEntries.any((item) {
        final itemId = item.id.trim();
        final entryId = entry.id.trim();
        if (itemId.isNotEmpty && entryId.isNotEmpty && itemId == entryId) {
          return true;
        }
        return item.text.trim().isNotEmpty &&
            item.text.trim() == entry.text.trim();
      });
      if (hasEntry) addRole(turn.role);
    }
    return out;
  }

  List<AiSeminarEvidence> _seminarCitedTraceableEvidenceFromState(
    AiSeminarRuntimeState state,
  ) {
    final rawEvidence = state.synthesis?.evidence.isNotEmpty == true
        ? state.synthesis!.evidence
        : state.evidenceBundle?.evidence ?? const <AiSeminarEvidence>[];
    final traceableById = <String, AiSeminarEvidence>{};
    for (final item in rawEvidence) {
      final id = item.id.trim();
      if (id.isEmpty || !item.isTraceable) continue;
      traceableById.putIfAbsent(id, () => item);
    }
    if (traceableById.isEmpty) return const <AiSeminarEvidence>[];

    final citedIds = <String>[];
    final seen = <String>{};
    void addRefs(Iterable<String> refs) {
      for (final raw in refs) {
        final id = raw.trim();
        if (id.isEmpty || !traceableById.containsKey(id)) continue;
        if (seen.add(id)) citedIds.add(id);
      }
    }

    final synthesis = state.synthesis;
    if (synthesis != null) {
      addRefs(synthesis.evidenceRefIds);
      for (final card in synthesis.candidateCards) {
        addRefs(card.evidenceRefIds);
      }
    }
    for (final turn in state.turns) {
      if (turn.isFailed) continue;
      addRefs(turn.evidenceRefIds);
      for (final entry in turn.whiteboardEntries) {
        addRefs(entry.evidenceRefIds);
      }
    }

    return citedIds.map((id) => traceableById[id]!).toList(growable: false);
  }

  String _seminarEvidenceSnapshotTitle(AiSeminarEvidence evidence) {
    final ref = evidence.sourceRef;
    final direct = ref.sourceTitle?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final location = ref.locationLabel?.trim();
    if (location != null && location.isNotEmpty) return location;
    final href = ref.href?.trim();
    if (href != null && href.isNotEmpty) return href;
    final chunkId = ref.chunkId;
    if (chunkId != null) return 'Chunk $chunkId';
    return _seminarEvidenceScopeLabel(
      evidence.scope.asString,
      L10n.of(context),
    );
  }

  String _seminarEvidenceSnapshotSnippet(AiSeminarEvidence evidence) {
    final sourceSnippet = evidence.sourceRef.sourceTextSnippet?.trim();
    if (sourceSnippet != null && sourceSnippet.isNotEmpty) {
      return sourceSnippet;
    }
    return evidence.text.trim();
  }

  void prefillDraft({
    String? message,
    List<AttachmentItem>? attachments,
    bool replaceAttachments = false,
    SourceRef? sourceRef,
  }) {
    if (message != null) {
      _draftSourceRef = sourceRef;
      _draftSourceRefSeedText = sourceRef == null ? null : message;
      _suppressDraftSync = true;
      inputController.text = message;
      inputController.selection = TextSelection.fromPosition(
        TextPosition(offset: inputController.text.length),
      );
      _suppressDraftSync = false;
      try {
        ref.read(aiChatDraftInputProvider.notifier).set(inputController.text);
      } catch (_) {}
    }

    if (attachments != null && attachments.isNotEmpty) {
      if (replaceAttachments) {
        setState(() {
          _attachments.clear();
        });
      }
      _addAttachments(attachments);
    }
  }

  void _addAttachments(List<AttachmentItem> items) {
    if (items.isEmpty) return;

    final maxImages = Prefs().aiChatImageAttachmentMaxCountV1;
    var imageCount =
        _attachments.where((a) => a.type == AttachmentType.image).length;

    final selectedImages =
        items.where((a) => a.type == AttachmentType.image).length;
    final accepted = <AttachmentItem>[];
    var acceptedImages = 0;
    var exceeded = false;

    for (final attachment in items) {
      if (attachment.type == AttachmentType.image) {
        if (imageCount >= maxImages) {
          exceeded = true;
          continue;
        }
        imageCount += 1;
        acceptedImages += 1;
      }
      accepted.add(attachment);
    }

    if (exceeded) {
      final code = Localizations.localeOf(context).languageCode.toLowerCase();
      final message = code.startsWith('zh')
          ? '本次选了 $selectedImages 张图片，已按上限保留前 $acceptedImages 张。'
          : 'Selected $selectedImages images, kept the first $acceptedImages within the limit.';
      AnxToast.show(message);
    }

    if (accepted.isEmpty) return;

    setState(() {
      _attachments.addAll(accepted);
    });
  }

  void _removeAttachment(int index) {
    setState(() {
      if (index >= 0 && index < _attachments.length) {
        _attachments.removeAt(index);
      }
    });
  }

  void _clearAttachments() {
    setState(() {
      _attachments.clear();
    });
  }

  void _drainPendingShareBookImports() {
    final pending = pendingShareBookImportPaths.value;
    if (pending.isEmpty) return;

    // Clear first to avoid re-entrancy loops.
    pendingShareBookImportPaths.value = <String>[];

    final files = pending
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .map((p) => File(p))
        .toList();

    _addBookImportFiles(files);
  }

  void _addBookImportFiles(List<File> files) {
    if (files.isEmpty) return;

    final existing = _pendingBookImports.map((e) => e.file.path).toSet();
    final next = <BookImportItem>[];

    for (final f in files) {
      final path = f.path.trim();
      if (path.isEmpty) continue;
      if (existing.contains(path)) continue;
      next.add(BookImportItem(file: f, filename: p.basename(path)));
    }

    if (next.isEmpty) return;

    setState(() {
      _pendingBookImports.addAll(next);
    });
  }

  Future<void> _removeBookImportAt(int index) async {
    if (index < 0 || index >= _pendingBookImports.length) return;
    final item = _pendingBookImports[index];

    setState(() {
      if (index < 0 || index >= _pendingBookImports.length) return;
      _pendingBookImports.removeAt(index);
    });

    // Cleanup-after-use: if the user dismisses the card, we can delete our
    // managed inbox copy.
    if (!Prefs().sharePanelCleanupAfterUseV1) return;

    final info = ShareInboxPaths.tryParse(item.file.path);
    if (info == null) return;

    try {
      final within = await ShareInboxPaths.isWithinInboxRoot(
          item.file.path, info.inboxRoot);
      if (!within) return;

      if (await item.file.exists()) {
        await item.file.delete();
      }

      await ShareInboxCleanupService.cleanupEventDirsIfSafe(
        eventDirs: [info.eventDir],
      );
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _importBookImportAt(int index) async {
    if (index < 0 || index >= _pendingBookImports.length) return;

    final item = _pendingBookImports[index];
    final files = await ShareSafeImport.prepareImportFiles([item.file.path]);
    if (files.isEmpty) return;

    importBookList(files, context, ref);

    setState(() {
      _pendingBookImports.removeWhere((e) => e.file.path == item.file.path);
    });

    if (Prefs().sharePanelCleanupAfterUseV1) {
      Future<void>.delayed(const Duration(seconds: 2), () {
        ShareInboxCleanupService.cleanupEventDirsIfSafe(
          eventDirs: [item.file.path],
        );
      });
    }
  }

  void _regenerateLastMessage() {
    if (_isStreaming) {
      return;
    }
    final messages = ref.read(aiChatProvider).value;
    if (messages == null || messages.isEmpty) {
      return;
    }

    for (int i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      if (message is HumanChatMessage) {
        _regenerateFromUserIndex(i);
        break;
      }
    }
  }

  String _assistantMemoryText(String content) {
    final parsed = parseReasoningContent(content);
    return _buildCopyableText(parsed, content).trim();
  }

  Future<bool> _confirmLongTermWrite(String previewText) async {
    final prefs = Prefs();
    if (!prefs.memoryLongTermConfirmEnabled) {
      return true;
    }

    final l10n = L10n.of(context);
    final confirmed = await PTDialog.show<bool>(
      context,
      title: l10n.memoryLongTermConfirmDialogTitle,
      content: Text(
        l10n.memoryLongTermConfirmDialogBody(
          previewText.trim().replaceAll(RegExp(r'\s+'), ' '),
        ),
        maxLines: 6,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          color: ClaudePalette.secondary(context),
          height: 1.35,
        ),
      ),
      actions: [
        PTDialogAction(
          label: l10n.commonCancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        PTDialogAction(
          label: l10n.commonConfirm,
          isDefault: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );

    return confirmed == true;
  }

  Future<void> _endCurrentSession() async {
    if (_isStreaming) {
      return;
    }

    final messages =
        ref.read(aiChatProvider).asData?.value ?? const <ChatMessage>[];
    if (messages.isEmpty) {
      _clearCurrentConversationState();
      return;
    }

    final prefs = Prefs();
    final l10n = L10n.of(context);
    final dailyStrategy = prefs.memoryWorkflowDailyStrategy;
    final body = !prefs.memorySessionDigestEnabled
        ? l10n.aiChatEndSessionBodyNoDigest
        : switch (dailyStrategy) {
            MemoryWorkflowDailyStrategy.smartDaily =>
              l10n.aiChatEndSessionBodySmartDaily,
            MemoryWorkflowDailyStrategy.autoDaily =>
              l10n.aiChatEndSessionBodyAutoDaily,
            MemoryWorkflowDailyStrategy.reviewInbox =>
              l10n.aiChatEndSessionBodyReviewInbox,
          };
    final confirmed = await PTDialog.show<bool>(
      context,
      title: l10n.aiChatEndSessionTitle,
      message: body,
      actions: [
        PTDialogAction(
          label: l10n.commonCancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        PTDialogAction(
          label: l10n.aiChatEndSessionAction,
          isDefault: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );

    if (confirmed != true) {
      return;
    }

    ref.read(aiChatProvider.notifier).persistCurrentConversation(ref);

    if (prefs.memorySessionDigestEnabled) {
      try {
        final result = await _memoryWorkflow.captureSessionDigest(
          messages: messages,
          dailyStrategy: dailyStrategy,
          conversationId: ref.read(aiChatProvider.notifier).currentSessionId,
        );
        if (!mounted) return;
        if (result.candidates.isEmpty) {
          AnxToast.show(l10n.memorySessionDigestNoCandidates);
        } else if (result.directSaveCount > 0 && result.reviewInboxCount > 0) {
          AnxToast.show(
            '${l10n.memorySessionDigestSavedToDaily(result.directSaveCount)}; '
            '${l10n.memorySessionDigestAddedToInbox(result.reviewInboxCount)}',
          );
        } else if (result.directSaveCount > 0) {
          AnxToast.show(
            l10n.memorySessionDigestSavedToDaily(result.directSaveCount),
          );
        } else {
          AnxToast.show(
            l10n.memorySessionDigestAddedToInbox(result.reviewInboxCount),
          );
        }
      } catch (e) {
        if (!mounted) return;
        AnxToast.show('${l10n.memoryWorkflowActionFailed}: $e');
        return;
      }
    }

    _clearCurrentConversationState();
  }

  void _clearCurrentConversationState() {
    ref.read(aiChatProvider.notifier).clear();
    setState(() {
      _sourceRefByUserIndex.clear();
      _draftSourceRef = null;
      _draftSourceRefSeedText = null;
      _suggestedPrompts = _pickSuggestedPrompts();
    });
  }

  Future<void> _handleMessageMemoryAction(
    _MessageMemoryAction action, {
    required String text,
    required String sourceType,
    String? messageNodeId,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      AnxToast.show(L10n.of(context).memoryWorkflowNothingToSave);
      return;
    }

    final l10n = L10n.of(context);
    final conversationId = ref.read(aiChatProvider.notifier).currentSessionId;
    final actionKey = _messageMemoryActionKey(
      sourceType: sourceType,
      messageNodeId: messageNodeId,
      text: normalized,
    );
    final sourcePointer = conversationId == null
        ? messageNodeId
        : messageNodeId == null
            ? conversationId
            : '$conversationId#$messageNodeId';
    final rawContextRef =
        conversationId == null ? null : 'conversation:$conversationId';

    try {
      switch (action) {
        case _MessageMemoryAction.rememberNow:
          final candidate = await _memoryWorkflow.saveToDaily(
            text: normalized,
            sourceType: sourceType,
            conversationId: conversationId,
            messageNodeId: messageNodeId,
            displayText: normalized,
            sourcePointer: sourcePointer,
            rawContextRef: rawContextRef,
            triggerKind: 'manual_save',
          );
          if (!mounted) return;
          setState(() {
            _directMemoryByMessageKey[actionKey] = candidate;
          });
          AnxToast.show(l10n.memorySavedToDaily);
          break;
        case _MessageMemoryAction.saveToLongTerm:
          final confirmed = await _confirmLongTermWrite(normalized);
          if (!confirmed) {
            return;
          }
          final candidate = await _memoryWorkflow.saveToLongTerm(
            text: normalized,
            sourceType: sourceType,
            conversationId: conversationId,
            messageNodeId: messageNodeId,
            displayText: normalized,
            sourcePointer: sourcePointer,
            rawContextRef: rawContextRef,
            triggerKind: 'manual_save',
          );
          if (!mounted) return;
          setState(() {
            _directMemoryByMessageKey[actionKey] = candidate;
          });
          AnxToast.show(l10n.memorySavedToLongTerm);
          break;
        case _MessageMemoryAction.addToReviewInbox:
          await _memoryWorkflow.addToReviewInbox(
            text: normalized,
            targetDoc: MemoryDocTarget.daily,
            sourceType: sourceType,
            conversationId: conversationId,
            messageNodeId: messageNodeId,
            displayText: normalized,
            sourcePointer: sourcePointer,
            rawContextRef: rawContextRef,
            triggerKind: 'manual_save',
          );
          if (!mounted) return;
          AnxToast.show(l10n.memoryAddedToReviewInbox);
          break;
        case _MessageMemoryAction.undoDirectSave:
          final candidate = _directMemoryByMessageKey[actionKey];
          if (candidate == null) {
            AnxToast.show(l10n.memoryWorkflowNothingToSave);
            return;
          }
          await _memoryWorkflow.undoDirectSave(candidate.id);
          if (!mounted) return;
          setState(() {
            _directMemoryByMessageKey.remove(actionKey);
          });
          AnxToast.show(l10n.memoryDirectSaveUndone);
          break;
      }
    } catch (e) {
      if (!mounted) return;
      AnxToast.show('${l10n.memoryWorkflowActionFailed}: $e');
    }
  }

  String _messageMemoryActionKey({
    required String sourceType,
    required String? messageNodeId,
    required String text,
  }) {
    final node = messageNodeId?.trim();
    if (node != null && node.isNotEmpty) {
      return '$sourceType#$node';
    }
    return '$sourceType#${text.hashCode}';
  }

  Future<void> _handleAssistantKnowledgeCardAction({
    required String answer,
    String? userPrompt,
    required String messageNodeId,
    SourceRef? readerSourceRef,
  }) async {
    final normalizedAnswer = answer.trim();
    if (normalizedAnswer.isEmpty) {
      AnxToast.show(L10n.of(context).knowledgeCardAddFailed);
      return;
    }

    final l10n = L10n.of(context);
    final chatNotifier = ref.read(aiChatProvider.notifier);
    final conversationId = chatNotifier.currentSessionId;
    chatNotifier.persistCurrentConversation(ref);
    final reading = ref.read(currentReadingProvider);
    final useCurrentReaderFallback = readerSourceRef == null &&
        !chatNotifier.isLoadedHistoryConversation &&
        _readingCanCreateReaderSourceRef(reading);
    final book = useCurrentReaderFallback ? reading.book : null;

    try {
      final result = await _chatKnowledgeCards.createFromAssistantAnswer(
        assistantAnswer: normalizedAnswer,
        userPrompt: userPrompt,
        conversationId: conversationId,
        messageNodeId: messageNodeId,
        modelId: _modelLabel(_selectedProviderId),
        bookId: book?.id,
        bookTitle: book?.title,
        cfi: useCurrentReaderFallback ? reading.cfi?.trim() : null,
        chapterTitle: useCurrentReaderFallback ? reading.chapterTitle : null,
        readerSourceRef: readerSourceRef,
      );
      if (!mounted) return;
      final message = result.addedToReviewInbox
          ? (result.inserted
              ? l10n.knowledgeCardAddedToReviewInbox
              : l10n.knowledgeCardAlreadyInReviewInbox)
          : result.inserted
              ? l10n.knowledgeCardSavedInline
              : result.card.reviewState == KnowledgeCardReviewState.pending
                  ? l10n.knowledgeCardAlreadyInReviewInbox
                  : l10n.knowledgeCardAlreadySaved;
      showKnowledgeCardSavedSnackBar(context,
          message: message, card: result.card);
    } catch (_) {
      if (!mounted) return;
      AnxToast.show(l10n.knowledgeCardAddFailed);
    }
  }

  SourceRef? _readerSourceRefForUserIndex(int userIndex) {
    return _sourceRefByUserIndex[userIndex] ??
        ref.read(aiChatProvider.notifier).sourceRefForMessageIndex(userIndex);
  }

  bool _readingCanCreateReaderSourceRef(CurrentReadingState reading) {
    final bookId = reading.book?.id;
    final cfi = reading.cfi?.trim() ?? '';
    return reading.isReading && bookId != null && bookId > 0 && cfi.isNotEmpty;
  }

  _AiChatKnowledgeSourceStatus _knowledgeCardSourceStatus({
    required SourceRef? readerSourceRef,
  }) {
    final l10n = L10n.of(context);
    if (readerSourceRef != null &&
        (readerSourceRef.canJumpBack || readerSourceRef.hasBookAnchor)) {
      return _AiChatKnowledgeSourceStatus(
        label: l10n.reviewInboxTraceableSources(1),
        tooltip: _localizedSourceStatusText(
          zh: '可跳回原文',
          en: 'Can jump back to the source text',
        ),
        traceable: true,
      );
    }

    final reading = ref.watch(currentReadingProvider);
    final canUseCurrentReaderFallback =
        !ref.read(aiChatProvider.notifier).isLoadedHistoryConversation &&
            _readingCanCreateReaderSourceRef(reading);
    if (canUseCurrentReaderFallback) {
      return _AiChatKnowledgeSourceStatus(
        label: l10n.reviewInboxTraceableSources(1),
        tooltip: _localizedSourceStatusText(
          zh: '将使用当前阅读位置作为来源',
          en: 'Will use the current reading position as source',
        ),
        traceable: true,
      );
    }

    return _AiChatKnowledgeSourceStatus(
      label: l10n.reviewInboxUnavailableSources(1),
      tooltip: _localizedSourceStatusText(
        zh: '仅保留会话来源，不能跳回原文',
        en: 'Conversation source only; no reader deep link',
      ),
      traceable: false,
    );
  }

  String _localizedSourceStatusText({
    required String zh,
    required String en,
  }) {
    final language = Localizations.localeOf(context).languageCode;
    return language == 'zh' ? zh : en;
  }

  Widget _buildKnowledgeCardSourceStatusChip(
    _AiChatKnowledgeSourceStatus status,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground =
        status.traceable ? colorScheme.primary : colorScheme.outline;
    final background = status.traceable
        ? colorScheme.primary.withValues(alpha: 0.08)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.72);

    return Tooltip(
      message: status.tooltip,
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: foreground.withValues(alpha: 0.24)),
        ),
        child: Text(
          status.label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foreground,
                fontSize: 11,
              ),
        ),
      ),
    );
  }

  Widget _buildMessageMemoryMenu({
    required String text,
    required String sourceType,
    String? messageNodeId,
  }) {
    final l10n = L10n.of(context);
    final normalized = text.trim();
    final enabled = normalized.isNotEmpty && !_isStreaming;
    final actionKey = _messageMemoryActionKey(
      sourceType: sourceType,
      messageNodeId: messageNodeId,
      text: normalized,
    );
    final directCandidate = _directMemoryByMessageKey[actionKey];

    return PopupMenuButton<_MessageMemoryAction>(
      enabled: enabled,
      tooltip: l10n.memoryMessageActionsTooltip,
      onSelected: (action) => _handleMessageMemoryAction(
        action,
        text: text,
        sourceType: sourceType,
        messageNodeId: messageNodeId,
      ),
      itemBuilder: (context) => [
        if (directCandidate == null) ...[
          PopupMenuItem(
            value: _MessageMemoryAction.rememberNow,
            child: Text(l10n.memoryRememberThisAction),
          ),
          PopupMenuItem(
            value: _MessageMemoryAction.saveToLongTerm,
            child: Text(l10n.memorySaveToLongTermAction),
          ),
          PopupMenuItem(
            value: _MessageMemoryAction.addToReviewInbox,
            child: Text(l10n.memoryAddToReviewInboxAction),
          ),
        ] else
          PopupMenuItem(
            value: _MessageMemoryAction.undoDirectSave,
            child: Text(l10n.memoryUndoDirectSaveAction),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(
          Icons.bookmark_add_outlined,
          size: 20,
          color: enabled ? null : Theme.of(context).disabledColor,
        ),
      ),
    );
  }

  void _copyMessageContent(String content) {
    final parsed = parseReasoningContent(content);
    final clipboardText = _buildCopyableText(parsed, content);
    Clipboard.setData(ClipboardData(text: clipboardText));
    AnxToast.show(L10n.of(context).notesPageCopied);
  }

  void _cancelStreaming() {
    // Be tolerant: streaming state might be briefly out-of-sync during rebuilds.
    unawaited(ref.read(aiChatProvider.notifier).cancelStreaming());
  }

  ChatMessage? _getLastAssistantMessage() {
    final messages = ref.watch(aiChatProvider).asData?.value;
    if (messages == null || messages.isEmpty) {
      return null;
    }

    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i] is AIChatMessage) {
        return messages[i];
      }
    }
    return null;
  }

  void _ensureSelectedProviderValid() {
    if (_isProviderSelectable(_selectedProviderId)) {
      return;
    }

    final fallback = _fallbackProviderId(_providers);
    if (fallback == _selectedProviderId) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_isProviderSelectable(fallback)) return;
      Prefs().selectedAiService = fallback;
      setState(() {
        _selectedProviderId = fallback;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // Sync external draft updates (e.g. Memory page insertion) into the input.
    ref.listen<String>(aiChatDraftInputProvider, (_, next) {
      if (!mounted) return;
      if (next == inputController.text) return;

      _suppressDraftSync = true;
      inputController.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
      _suppressDraftSync = false;
    });

    final quickPrompts = _getQuickPrompts(context);
    final chatIsStreaming = ref.watch(aiChatStreamingProvider);
    final contextNotice = ref.watch(aiChatContextNoticeProvider);

    // Refresh providers in case user toggled enable/disable in Provider Center.
    _providers = Prefs().aiProvidersV1;
    _ensureSelectedProviderValid();

    final current = _currentProvider;
    final currentModel = _modelLabel(_selectedProviderId);

    var aiService = PopupMenuButton<String>(
      enabled: !chatIsStreaming,
      onSelected: _onProviderSelected,
      itemBuilder: (context) {
        final enabledProviders =
            _providers.where((provider) => provider.enabled).toList();

        return enabledProviders.map((provider) {
          final isSelected = provider.id == _selectedProviderId;
          final model = _modelLabel(provider.id);
          final logoKey = _providerLogoKey(provider);

          final label =
              model.isEmpty ? provider.name : '${provider.name} · $model';

          return PopupMenuItem<String>(
            value: provider.id,
            child: Row(
              children: [
                if (logoKey.isNotEmpty)
                  Image.asset(
                    logoKey,
                    width: 20,
                    height: 20,
                    errorBuilder: (_, __, ___) => const SizedBox(),
                  )
                else
                  const SizedBox(width: 20, height: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSelected) const Icon(Icons.check, size: 16),
              ],
            ),
          );
        }).toList(growable: false);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            _providerLogoKey(current),
            width: 20,
            height: 20,
            errorBuilder: (_, __, ___) => const SizedBox(),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              currentModel.isEmpty
                  ? current.name
                  : '${current.name} · $currentModel',
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more, size: 16),
        ],
      ),
    );
    // Wave L: watch draft text so the send/mic swap and suggestion visibility
    // react to every keystroke without manual setState.
    final draftText = ref.watch(aiChatDraftInputProvider);
    final draftIsEmpty = draftText.trim().isEmpty;
    final chatMessagesAsync = ref.watch(aiChatProvider);
    final chatIsEmpty = chatMessagesAsync.asData?.value.isEmpty ?? true;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Wave L: rounded pill composer with embedded + / send buttons, matching
    // Claude's reference surface. Attachments / context notices still live in
    // the Column above the pill.
    // Wave S: composer pill now stacks (text field → optional mode label →
    // action row) so the action buttons sit at the bottom of the pill even
    // when the text field grows to its multi-line max. All three action
    // surfaces (+, mic, send) are 32x32 to match the Claude reference.
    final composerPill = Container(
      decoration: BoxDecoration(
        color: ClaudePalette.elevated(context),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: ClaudePalette.divider(context),
          width: 0.5,
        ),
        boxShadow: isDarkMode
            ? [
                BoxShadow(
                  color: ClaudePalette.divider(context).withValues(alpha: 0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Expanding multiline text field (up to 5 lines).
          TextField(
            controller: inputController,
            style: TextStyle(
              fontSize: 16,
              color: ClaudePalette.fg(context),
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText: L10n.of(context).aiHintInputPlaceholder,
              hintStyle: TextStyle(
                fontSize: 16,
                color: ClaudePalette.secondary(context),
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
            maxLines: 5,
            minLines: 1,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _sendMessage(),
          ),
          // Action row sits at the bottom of the pill. Provider picker
          // lives inline right next to the `+` button so nothing renders
          // under the pill (user feedback: the secondary row below was
          // cluttering the bottom and the 'Chat' mode label was noise).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                // Leading + button opens the Add-to-Chat sheet.
                Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _showAddToChatSheet(context);
                    },
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: Icon(
                        Icons.add_rounded,
                        size: 20,
                        color: ClaudePalette.fg(context),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Inline provider / model picker (was a separate row below
                // the pill). Constrained with Flexible so long model names
                // get truncated instead of pushing the send button off.
                Flexible(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: aiService,
                  ),
                ),
                const Spacer(),
                // Minimize button (collapse the sheet).
                if (widget.onRequestMinimize != null)
                  Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        widget.onRequestMinimize!();
                      },
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 22,
                          color:
                              ClaudePalette.fg(context).withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                // Trailing send / stop / mic button.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: chatIsStreaming
                      ? Material(
                          key: const ValueKey('composer-stop'),
                          color: ClaudePalette.secondary(context),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              HapticFeedback.lightImpact();
                              _cancelStreaming();
                            },
                            child: const SizedBox(
                              width: 32,
                              height: 32,
                              child: Icon(
                                Icons.stop_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        )
                      : draftIsEmpty
                          ? Material(
                              key: const ValueKey('composer-mic'),
                              color: Colors.transparent,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                },
                                child: SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: Icon(
                                    Icons.graphic_eq_rounded,
                                    size: 20,
                                    color: ClaudePalette.fg(context),
                                  ),
                                ),
                              ),
                            )
                          : Material(
                              key: const ValueKey('composer-send'),
                              color: ClaudePalette.accent(context),
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  _sendMessage();
                                },
                                child: const SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: Icon(
                                    Icons.arrow_upward_rounded,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    Widget inputBox = Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SafeArea(
        top: false,
        bottom: widget.inputSafeAreaBottom,
        child: Padding(
          padding: EdgeInsets.only(bottom: widget.bottomPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if ((contextNotice ?? '').trim().isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    contextNotice!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              // Book import strip (UI-only)
              if (_pendingBookImports.isNotEmpty)
                Container(
                  height: 84,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _pendingBookImports.length,
                    itemBuilder: (context, index) {
                      final item = _pendingBookImports[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Container(
                          width: 220,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .secondaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.menu_book, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      item.filename,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item.extension.toUpperCase(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: L10n.of(context).exportAndImportImport,
                                onPressed: () => _importBookImportAt(index),
                                icon: const Icon(Icons.download),
                              ),
                              IconButton(
                                tooltip: L10n.of(context).commonRemove,
                                onPressed: () => _removeBookImportAt(index),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // Attachments strip
              if (_attachments.isNotEmpty)
                Container(
                  height: 80,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _attachments.length,
                    itemBuilder: (context, index) {
                      final attachment = _attachments[index];
                      Widget thumbnail;
                      if (attachment.type == AttachmentType.image) {
                        thumbnail = ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(
                            attachment.bytes,
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        );
                      } else {
                        thumbnail = Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .secondaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Icon(Icons.description, size: 28),
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Stack(
                          children: [
                            thumbnail,
                            Positioned(
                              top: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () => _removeAttachment(index),
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close,
                                      size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              composerPill,
              // Quick suggestion chip strip — rendered BELOW the pill
              // (Claude Code mobile reference) and only while the
              // conversation is empty so it feels like a first-run surface.
              if (chatIsEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 2),
                  child: _buildQuickSuggestions(quickPrompts),
                ),
              // Minimize affordance (only when the chat is a nested sheet
              // inside the reader) — tiny row with no provider info now
              // that aiService lives inside the pill.
              if (widget.onRequestMinimize != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 4),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: Icon(
                        Icons.keyboard_arrow_down,
                        size: 18,
                        color: ClaudePalette.secondary(context),
                      ),
                      onPressed: widget.onRequestMinimize,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (widget.onRequestMinimize != null) {
      inputBox = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) {
          _inputSwipeDownDy = 0;
        },
        onVerticalDragUpdate: (details) {
          final delta = details.primaryDelta ?? 0;
          if (delta > 0) {
            _inputSwipeDownDy += delta;
          }
        },
        onVerticalDragEnd: (_) {
          if (_inputSwipeDownDy > 24) {
            HapticFeedback.selectionClick();
            widget.onRequestMinimize?.call();
          }
          _inputSwipeDownDy = 0;
        },
        child: inputBox,
      );
    }

    Widget buildEmptyState() {
      if (widget.emptyStateBuilder != null) {
        final content = widget.emptyStateBuilder!(
          context,
          (prompt) {
            inputController.text = prompt;
            _sendMessage();
          },
        );

        // Keep scroll controller attached for DraggableScrollableSheet.
        return CustomScrollView(
          controller: _scrollController,
          physics: const ClampingScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: content,
            ),
          ],
        );
      }

      final theme = Theme.of(context);

      Widget buildQuickChipColumn() {
        if (widget.quickPromptChips.isEmpty) {
          return const SizedBox.shrink();
        }

        Widget actionButton(AiQuickPromptChip chip) {
          return SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: () {
                inputController.text = chip.prompt;
                _sendMessage();
              },
              icon: Icon(chip.icon, size: 18),
              label: Text(
                chip.label,
                overflow: TextOverflow.ellipsis,
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          );
        }

        final buttons = widget.quickPromptChips
            .map(
              (chip) => Padding(
                padding: const EdgeInsets.only(top: 10),
                child: actionButton(chip),
              ),
            )
            .toList(growable: false);

        return Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: buttons,
                ),
              ),
            ),
          ),
        );
      }

      final content = Stack(
        children: [
          if (widget.quickPromptChips.isEmpty)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    L10n.of(context).tryAQuickPrompt,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: _suggestedPrompts
                        .map(
                          (prompt) => ActionChip(
                            label: Text(prompt),
                            onPressed: () {
                              inputController.text = prompt;
                              _sendMessage();
                            },
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              ),
            ),
          buildQuickChipColumn(),
        ],
      );

      // IMPORTANT:
      // When used inside DraggableScrollableSheet, we must always attach the
      // provided ScrollController to a ScrollView; otherwise the sheet
      // controller won't be attached and programmatic minimize won't work.
      //
      // Use SliverFillRemaining to make the empty state fill the available
      // space, avoiding the "invisible frame" / clipped chip area.
      return CustomScrollView(
        controller: _scrollController,
        physics: const ClampingScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: content,
          ),
        ],
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          L10n.of(context).aiChat,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: ClaudePalette.fg(context),
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.chevron_left_rounded,
            size: 28,
            color: ClaudePalette.fg(context),
          ),
          tooltip: L10n.of(context).history,
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.text_fields,
              size: 22,
              color: ClaudePalette.fg(context),
            ),
            tooltip: L10n.of(context).font,
            onPressed: _showFontScaleSheet,
          ),
          IconButton(
            icon: Icon(
              Icons.edit_document,
              size: 22,
              color: ClaudePalette.fg(context),
            ),
            tooltip: L10n.of(context).aiChatEndSessionAction,
            onPressed: _clearMessage,
          ),
          if (widget.trailing != null) ...widget.trailing!,
        ],
      ),
      drawer: Drawer(
        child: _buildHistoryDrawer(context),
      ),
      body: Column(
        children: [
          Expanded(
            child: ref.watch(aiChatProvider).when(
                  data: (messages) {
                    if (messages.isEmpty) {
                      _resetScrollShortcutForEmptyList();
                      return buildEmptyState();
                    }

                    return _buildMessageList(messages);
                  },
                  loading: () => Skeletonizer.zone(child: Bone.multiText()),
                  error: (error, stack) => Center(child: Text('error: $error')),
                ),
          ),
          inputBox,
        ],
      ),
    );
  }

  double get _messageTextScale =>
      Prefs().aiChatFontScale.clamp(0.8, 1.4).toDouble();

  Widget _buildScaledMessageContent(Widget child) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(_messageTextScale),
      ),
      child: child,
    );
  }

  TextStyle _messageBodyTextStyle(BuildContext context) {
    return (Theme.of(context).textTheme.bodyMedium ??
            const TextStyle(fontSize: 14))
        .copyWith(height: 1.55);
  }

  String _scrollShortcutSignatureFor(List<ChatMessage> messages) {
    if (messages.isEmpty) return '0';
    final last = messages.last;
    final text = last is HumanChatMessage
        ? _extractUserTextFromHuman(last)
        : last.contentAsString;
    return Object.hash(messages.length, last.runtimeType, text.length, text)
        .toString();
  }

  void _syncScrollShortcutSignature(String signature) {
    if (_scrollShortcutContentSignature == signature) return;
    final previous = _scrollShortcutContentSignature;
    _scrollShortcutContentSignature = signature;
    if (!SeminarAutoScrollPolicy.shouldMarkNewContentBelow(
      pinnedToBottom: _pinnedToBottom,
      previousSignature: previous,
      currentSignature: signature,
    )) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasNewContentBelow) return;
      setState(() {
        _hasNewContentBelow = true;
      });
    });
  }

  void _resetScrollShortcutForEmptyList() {
    _scrollShortcutContentSignature = '';
    if (!_showScrollShortcut && !_hasNewContentBelow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _showScrollShortcut = false;
        _hasNewContentBelow = false;
      });
    });
  }

  Widget _buildScrollShortcutOverlay(Widget list) {
    return Stack(
      children: [
        Positioned.fill(child: list),
        if (_showScrollShortcut)
          PositionedDirectional(
            end: 14,
            bottom: 14,
            child: GestureDetector(
              onLongPress: _scrollToTop,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  FloatingActionButton.small(
                    heroTag: null,
                    tooltip: _localizedSeminarCardText(
                      zh: '回到底部;长按回顶部',
                      en: 'Back to bottom; hold for top',
                    ),
                    onPressed: () => _scrollToBottom(
                      force: true,
                      clearNewContentIndicator: true,
                    ),
                    child: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  if (_hasNewContentBelow)
                    PositionedDirectional(
                      top: -2,
                      end: -2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.error,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.surface,
                            width: 2,
                          ),
                        ),
                        child: const SizedBox(width: 12, height: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMessageList(List<ChatMessage> messages) {
    _scheduleStartSeminarToolBridges(messages);
    _syncScrollShortcutSignature(_scrollShortcutSignatureFor(messages));
    final lastHumanIndex = _findLastHumanIndex(messages);
    final isStreaming = ref.watch(aiChatStreamingProvider);

    final list = ListView.builder(
      controller: _scrollController,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isLastMessage = index == messages.length - 1;
        return _buildLinearMessageItem(
          messages,
          message,
          index,
          isStreaming && isLastMessage,
          lastHumanIndex: lastHumanIndex,
        );
      },
    );
    return _buildScrollShortcutOverlay(list);
  }

  int? _findLastHumanIndex(List<ChatMessage> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i] is HumanChatMessage) {
        return i;
      }
    }
    return null;
  }

  int? _findPrevHumanIndex(List<ChatMessage> messages, int fromIndex) {
    for (var i = fromIndex; i >= 0; i--) {
      if (messages[i] is HumanChatMessage) {
        return i;
      }
    }
    return null;
  }

  Widget _buildVariantSwitcher(
    int messageIndex,
    bool isStreaming,
  ) {
    final notifier = ref.read(aiChatProvider.notifier);
    final count = notifier.variantCountForMessageIndex(messageIndex);
    if (count <= 1) {
      return const SizedBox.shrink();
    }

    final selected = notifier.selectedVariantIndexForMessageIndex(messageIndex);
    final canNavigate = !_isStreaming && !isStreaming;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, size: 18),
          onPressed: canNavigate && selected > 0
              ? () {
                  notifier.switchVariantAtMessageIndexAndPersist(
                    messageIndex,
                    -1,
                    ref,
                  );
                }
              : null,
        ),
        Text('${selected + 1}/$count'),
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 18),
          onPressed: canNavigate && selected < count - 1
              ? () {
                  notifier.switchVariantAtMessageIndexAndPersist(
                    messageIndex,
                    1,
                    ref,
                  );
                }
              : null,
        ),
      ],
    );
  }

  Widget _buildLinearMessageItem(
    List<ChatMessage> allMessages,
    ChatMessage message,
    int index,
    bool isStreaming, {
    required int? lastHumanIndex,
  }) {
    final isUser = message is HumanChatMessage;
    final content =
        isUser ? _extractUserTextFromHuman(message) : message.contentAsString;

    final prevHumanIndex =
        isUser ? index : _findPrevHumanIndex(allMessages, index);
    final isLastTurn =
        prevHumanIndex != null && prevHumanIndex == lastHumanIndex;
    final seminarRunCard = isUser
        ? null
        : ref
            .read(aiChatProvider.notifier)
            .seminarRunCardForMessageIndex(index);
    final assistantReaderSourceRef = !isUser && prevHumanIndex != null
        ? _readerSourceRefForUserIndex(prevHumanIndex)
        : null;
    final assistantSourceStatus = isUser || seminarRunCard != null
        ? null
        : _knowledgeCardSourceStatus(
            readerSourceRef: assistantReaderSourceRef,
          );

    final maxBubbleWidth = MediaQuery.sizeOf(context).width * 0.8;

    Widget? footer;
    if (!isUser && seminarRunCard == null) {
      final segMeta =
          ref.read(aiChatProvider.notifier).segmentMetaForMessageIndex(index);
      final segText = segMeta?.footerText() ?? '';
      final isLastAssistant =
          index == allMessages.lastIndexWhere((m) => m is AIChatMessage);
      final usageSummary = ref.watch(aiChatUsageSummaryProvider);
      final cumulative =
          isLastAssistant && (usageSummary ?? '').trim().isNotEmpty
              ? '会话累计 $usageSummary'
              : '';
      final pieces = [segText, cumulative].where((s) => s.isNotEmpty).toList();
      if (pieces.isNotEmpty) {
        footer = Padding(
          padding: const EdgeInsets.only(top: 2, left: 2),
          child: Text(
            pieces.join('  ·  '),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        );
      }
    }

    return Padding(
      key: ValueKey('ai-chat-message-${message.runtimeType}-$index'),
      padding: EdgeInsets.fromLTRB(
        isUser ? 8.0 : 12.0,
        4.0,
        isUser ? 8.0 : 12.0,
        8.0,
      ),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: isUser ? maxBubbleWidth : double.infinity),
              child: Container(
                padding: isUser
                    ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
                    : EdgeInsets.zero,
                decoration: isUser
                    ? BoxDecoration(
                        color: ClaudePalette.accentTint(context),
                        borderRadius: BorderRadius.circular(18),
                      )
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildScaledMessageContent(
                      isUser
                          ? _buildHumanMessageBody(message)
                          : seminarRunCard == null
                              ? _buildAssistantSections(content, isStreaming)
                              : _buildSeminarRunCard(seminarRunCard),
                    ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      children: [
                        _buildVariantSwitcher(index, isStreaming),
                        if (isUser) ...[
                          TextButton(
                            onPressed: () => _showEditUserMessageDialog(
                              index,
                              message,
                            ),
                            child: Text(L10n.of(context).commonEdit),
                          ),
                          TextButton(
                            onPressed: () => _copyPlainText(content),
                            child: Text(L10n.of(context).commonCopy),
                          ),
                          _buildMessageMemoryMenu(
                            text: content,
                            sourceType: 'chat',
                            messageNodeId: 'user:$index',
                          ),
                        ] else if (seminarRunCard == null) ...[
                          if (prevHumanIndex != null)
                            TextButton(
                              onPressed: () => _confirmRegenerateFromUserIndex(
                                prevHumanIndex,
                                isLastTurn: isLastTurn,
                              ),
                              child: Text(L10n.of(context).aiRegenerate),
                            ),
                          TextButton(
                            onPressed: () => _copyMessageContent(content),
                            child: Text(L10n.of(context).commonCopy),
                          ),
                          if (assistantSourceStatus != null)
                            _buildKnowledgeCardSourceStatusChip(
                              assistantSourceStatus,
                            ),
                          TextButton(
                            onPressed: isStreaming
                                ? null
                                : () => _handleAssistantKnowledgeCardAction(
                                      answer: _assistantMemoryText(content),
                                      userPrompt: prevHumanIndex == null
                                          ? null
                                          : _humanTextAt(
                                              allMessages,
                                              prevHumanIndex,
                                            ),
                                      messageNodeId: 'assistant:$index',
                                      readerSourceRef: assistantReaderSourceRef,
                                    ),
                            child:
                                Text(L10n.of(context).contextMenuKnowledgeCard),
                          ),
                          _buildMessageMemoryMenu(
                            text: _assistantMemoryText(content),
                            sourceType: 'chat',
                            messageNodeId: 'assistant:$index',
                          ),
                        ],
                      ],
                    ),
                    if (footer != null) footer,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeminarRunCard(AiSeminarRunCardMeta card) {
    final l10n = L10n.of(context);
    final question = card.question.trim();
    final runtimeState = _watchSeminarRuntimeState(card.sessionId);
    _syncSeminarRunCardSnapshot(card.sessionId, runtimeState);
    final normalizedSessionId = card.sessionId?.trim();
    final hasSentToReview = normalizedSessionId != null &&
        normalizedSessionId.isNotEmpty &&
        _seminarCardSentToReviewSessionIds.contains(normalizedSessionId);
    final canSendToReview = card.sessionId != null &&
        runtimeState.session?.id == card.sessionId &&
        runtimeState.canSendToReview &&
        !hasSentToReview;
    final canSaveKnowledgeCard = card.sessionId != null &&
        runtimeState.session?.id == card.sessionId &&
        _seminarSynthesisKnowledgeCardSourceRefs(runtimeState).isNotEmpty;
    final canAddSpacedReview = canSaveKnowledgeCard;
    final canAddConceptGraph = canSaveKnowledgeCard;
    final knowledgeCardId = _seminarSynthesisKnowledgeCardId(card.sessionId);
    final hasSavedKnowledgeCard = knowledgeCardId != null &&
        _seminarCardSavedKnowledgeCardIds.contains(knowledgeCardId);
    final reviewFlashcardId =
        _seminarSynthesisReviewFlashcardId(card.sessionId);
    final hasAddedSpacedReview = reviewFlashcardId != null &&
        _seminarCardSpacedReviewFlashcardIds.contains(reviewFlashcardId);
    final conceptNodeId = _seminarSynthesisConceptNodeId(card.sessionId);
    final hasAddedConceptGraph = conceptNodeId != null &&
        _seminarCardConceptNodeIds.contains(conceptNodeId);
    final hasIgnoredActions = normalizedSessionId != null &&
        normalizedSessionId.isNotEmpty &&
        _seminarCardIgnoredActionSessionIds.contains(normalizedSessionId);
    final hasAnyAssetAction = canSaveKnowledgeCard ||
        canAddSpacedReview ||
        canAddConceptGraph ||
        canSendToReview;
    final canIgnoreAssetActions = normalizedSessionId != null &&
        normalizedSessionId.isNotEmpty &&
        !hasSavedKnowledgeCard &&
        !hasAddedSpacedReview &&
        !hasAddedConceptGraph &&
        hasAnyAssetAction;
    final canStartFromCard = _shouldShowSeminarCardStartAction(
      card,
      runtimeState,
    );
    final snapshot = card.snapshot;
    final shouldShowSnapshot = snapshot != null &&
        !snapshot.isEmpty &&
        !(canStartFromCard && _seminarSnapshotHasOnlyRunSetup(snapshot));
    final canCancelFromCard = _shouldShowSeminarCardCancelAction(
      card,
      runtimeState,
    );
    final headerControls = _seminarRunCardHeaderControls(
      card: card,
      snapshot: snapshot,
      canCancelFromCard: canCancelFromCard,
    );

    final showRecoveryDetails = normalizedSessionId != null &&
        normalizedSessionId.isNotEmpty &&
        _seminarCardResumeDetailSessionIds.contains(normalizedSessionId);

    void toggleRecoveryDetails() {
      if (normalizedSessionId == null || normalizedSessionId.isEmpty) return;
      setState(() {
        if (showRecoveryDetails) {
          _seminarCardResumeDetailSessionIds.remove(normalizedSessionId);
        } else {
          _seminarCardResumeDetailSessionIds.add(normalizedSessionId);
        }
      });
    }

    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: ClaudePalette.divider(context)),
            color: ClaudePalette.card(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.groups_2_outlined,
                    size: 18,
                    color: ClaudePalette.accent(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.aiChatSeminarFeatureTitle,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: ClaudePalette.fg(context),
                          ),
                    ),
                  ),
                  if (headerControls.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: headerControls,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              SeminarMetaChips(
                chips: [
                  SeminarMetaChipData(
                    icon: Icons.flag_outlined,
                    label: _seminarStatusLabel(card.status, l10n),
                  ),
                  SeminarMetaChipData(
                    icon: Icons.groups_2_outlined,
                    label: _seminarRoleCountLabel(card.roleIds.length),
                  ),
                  SeminarMetaChipData(
                    icon: Icons.manage_search_outlined,
                    label: _seminarEvidenceScopeSummary(
                      card.evidenceScopeIds,
                      l10n,
                    ),
                  ),
                  if (card.sourceRefCount > 0)
                    SeminarMetaChipData(
                      icon: Icons.link_outlined,
                      label: _seminarSourceCountLabel(card.sourceRefCount),
                    ),
                  if (card.writeRequiresApproval)
                    SeminarMetaChipData(
                      icon: Icons.fact_check_outlined,
                      label: _localizedSeminarCardText(
                        zh: '写入需确认',
                        en: 'Approval before write',
                      ),
                    ),
                  if (card.allowWeb)
                    SeminarMetaChipData(
                      icon: Icons.public_outlined,
                      label: _localizedSeminarCardText(
                        zh: '允许联网',
                        en: 'Web allowed',
                      ),
                    ),
                  if (card.maxRounds > 1)
                    SeminarMetaChipData(
                      icon: Icons.repeat_outlined,
                      label: _localizedSeminarCardText(
                        zh: '最多 ${card.maxRounds} 轮',
                        en: 'Up to ${card.maxRounds} rounds',
                      ),
                    ),
                ],
              ),
              if (question.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  question,
                  key: card.sessionId == null
                      ? null
                      : ValueKey(
                          'seminar-chat-card-question-${card.sessionId}'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: ClaudePalette.fg(context),
                        height: 1.35,
                      ),
                ),
              ],
              if (canStartFromCard) ...[
                const SizedBox(height: 12),
                SeminarFullWidthSection(child: _buildSeminarRunCardSetup(card)),
              ],
              if (shouldShowSnapshot) ...[
                const SizedBox(height: 9),
                KeyedSubtree(
                  key: card.sessionId == null
                      ? null
                      : ValueKey(
                          'seminar-chat-card-snapshot-${card.sessionId}'),
                  child: SeminarFullWidthSection(
                    child: _buildSeminarRunSnapshot(
                      card.sessionId,
                      snapshot,
                      runtimeState,
                      bookId: card.bookId,
                      evidenceScopeIds: card.evidenceScopeIds,
                    ),
                  ),
                ),
              ],
              if (canStartFromCard) ...[
                const SizedBox(height: 12),
                _buildSeminarRunCardStartAction(card),
              ],
              if (_shouldShowSeminarCardResumeBanner(card, runtimeState)) ...[
                const SizedBox(height: 12),
                _buildSeminarRunCardResumeBanner(
                  card,
                  runtimeState,
                  showDetails: showRecoveryDetails,
                  onOpen: toggleRecoveryDetails,
                  onContinue: () => _continueSeminarRunCardFromCheckpoint(
                    card.sessionId,
                  ),
                ),
              ],
              if (_shouldShowSeminarCardFollowUpHint(card, runtimeState)) ...[
                const SizedBox(height: 12),
                _buildSeminarRunCardFollowUpHint(),
              ],
              if (hasIgnoredActions) ...[
                const SizedBox(height: 12),
                _buildSeminarRunCardIgnoredActionsNotice(card.sessionId),
              ] else if (hasAnyAssetAction) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (canSaveKnowledgeCard)
                      hasSavedKnowledgeCard
                          ? OutlinedButton.icon(
                              icon: const Icon(Icons.undo_outlined, size: 18),
                              label: Text(
                                _localizedSeminarCardText(
                                  zh: '撤销保存',
                                  en: 'Undo save',
                                ),
                              ),
                              onPressed: () =>
                                  _undoActiveSeminarRunCardKnowledgeCard(
                                card.sessionId,
                              ),
                            )
                          : FilledButton.icon(
                              icon: const Icon(Icons.style_outlined, size: 18),
                              label: Text(
                                _localizedSeminarCardText(
                                  zh: '保存知识卡',
                                  en: 'Save card',
                                ),
                              ),
                              onPressed: () =>
                                  _saveActiveSeminarRunCardKnowledgeCard(
                                card.sessionId,
                              ),
                            ),
                    if (canSaveKnowledgeCard && !hasSavedKnowledgeCard)
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.edit_note_outlined, size: 18),
                        label: Text(
                          _localizedSeminarCardText(
                            zh: '编辑后保存',
                            en: 'Edit and save',
                          ),
                        ),
                        onPressed: () => _editActiveSeminarRunCardKnowledgeCard(
                          card.sessionId,
                        ),
                      ),
                    if (canAddSpacedReview)
                      hasAddedSpacedReview
                          ? OutlinedButton.icon(
                              icon: const Icon(Icons.undo_outlined, size: 18),
                              label: Text(
                                _localizedSeminarCardText(
                                  zh: '撤销复习',
                                  en: 'Undo review',
                                ),
                              ),
                              onPressed: () =>
                                  _undoActiveSeminarRunCardSpacedReview(
                                card.sessionId,
                              ),
                            )
                          : FilledButton.tonalIcon(
                              icon: const Icon(Icons.school_outlined, size: 18),
                              label: Text(
                                _localizedSeminarCardText(
                                  zh: '加入复习',
                                  en: 'Add review',
                                ),
                              ),
                              onPressed: () =>
                                  _addActiveSeminarRunCardSpacedReview(
                                card.sessionId,
                              ),
                            ),
                    if (canAddConceptGraph)
                      hasAddedConceptGraph
                          ? OutlinedButton.icon(
                              icon: const Icon(Icons.undo_outlined, size: 18),
                              label: Text(
                                _localizedSeminarCardText(
                                  zh: '撤销图谱',
                                  en: 'Undo graph',
                                ),
                              ),
                              onPressed: () =>
                                  _undoActiveSeminarRunCardConceptGraph(
                                card.sessionId,
                              ),
                            )
                          : FilledButton.tonalIcon(
                              icon: const Icon(
                                Icons.account_tree_outlined,
                                size: 18,
                              ),
                              label: Text(
                                _localizedSeminarCardText(
                                  zh: '加入我的图谱',
                                  en: 'Add to graph',
                                ),
                              ),
                              onPressed: () =>
                                  _addActiveSeminarRunCardConceptGraph(
                                card.sessionId,
                              ),
                            ),
                    if (canSendToReview)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.fact_check_outlined, size: 18),
                        label: Text(l10n.seminarSendToReview),
                        onPressed: () => _sendActiveSeminarRunCardToReview(
                          card.sessionId,
                        ),
                      ),
                    if (canIgnoreAssetActions)
                      TextButton.icon(
                        icon:
                            const Icon(Icons.visibility_off_outlined, size: 18),
                        label: Text(
                          _localizedSeminarCardText(
                            zh: '忽略',
                            en: 'Ignore',
                          ),
                        ),
                        onPressed: () =>
                            _ignoreSeminarRunCardAssetActions(card.sessionId),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeminarRunCardIgnoredActionsNotice(String? sessionId) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: ClaudePalette.bg(context).withValues(alpha: 0.55),
        border: Border.all(color: ClaudePalette.divider(context)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.visibility_off_outlined,
            size: 17,
            color: ClaudePalette.fg(context).withValues(alpha: 0.62),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _localizedSeminarCardText(
                zh: '已忽略本次沉淀建议',
                en: 'Suggestions ignored',
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ClaudePalette.fg(context).withValues(alpha: 0.62),
                  ),
            ),
          ),
          TextButton(
            onPressed: () => _restoreSeminarRunCardAssetActions(sessionId),
            child: Text(
              _localizedSeminarCardText(
                zh: '恢复操作',
                en: 'Restore',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeminarRunCardSetup(AiSeminarRunCardMeta card) {
    final l10n = L10n.of(context);
    final sessionId = card.sessionId?.trim();
    final isExpanded = sessionId != null &&
        _seminarCardSetupExpandedSessionIds.contains(sessionId);
    final expandedSessionId = isExpanded ? sessionId : null;
    final evidenceSummary =
        _seminarEvidenceScopeSummary(card.evidenceScopeIds, l10n);
    final toolCount = card.roleProfiles
        .expand((profile) => profile.allowedToolIds)
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .length;
    final toolSummary = _localizedSeminarCardText(
      zh: toolCount == 0 ? '只读工具：默认' : '只读工具：$toolCount 个',
      en: toolCount == 0 ? 'Read-only tools: default' : '$toolCount tools',
    );
    final roleSummary = _localizedSeminarCardText(
      zh: '角色：${_seminarRoleLabels(card.roleIds)}',
      en: 'Roles: ${_seminarRoleLabels(card.roleIds)}',
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ClaudePalette.divider(context)),
        color: ClaudePalette.accentTint(context).withValues(alpha: 0.35),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.tune_outlined,
                  size: 18,
                  color: ClaudePalette.accent(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _localizedSeminarCardText(
                          zh: '本次设置',
                          en: 'Run setup',
                        ),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: ClaudePalette.fg(context),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$roleSummary · $evidenceSummary · $toolSummary',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.3,
                            ),
                      ),
                    ],
                  ),
                ),
                if (sessionId != null && sessionId.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        if (isExpanded) {
                          _seminarCardSetupExpandedSessionIds.remove(sessionId);
                        } else {
                          _seminarCardSetupExpandedSessionIds.add(sessionId);
                        }
                      });
                    },
                    child: Text(
                      _localizedSeminarCardText(
                        zh: isExpanded ? '收起设置' : '调整设置',
                        en: isExpanded ? 'Hide setup' : 'Adjust setup',
                      ),
                    ),
                  ),
              ],
            ),
            if (expandedSessionId != null) ...[
              const SizedBox(height: 8),
              Divider(height: 1, color: ClaudePalette.divider(context)),
              const SizedBox(height: 8),
              _buildSeminarRunCardQuestionField(card, expandedSessionId),
              const SizedBox(height: 8),
              for (final role in _seminarCardSetupRoles(card)) ...[
                SwitchListTile(
                  key: ValueKey(
                    'seminar-chat-card-role-${role.asString}-$expandedSessionId',
                  ),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  secondary: Icon(
                    role == AiSeminarRole.verifier
                        ? Icons.verified_outlined
                        : Icons.record_voice_over_outlined,
                    size: 18,
                  ),
                  title: Text(_seminarRunRoleLabel(context, role)),
                  subtitle: Text(
                    _localizedSeminarCardText(
                      zh: '只影响这场研讨',
                      en: 'Only this seminar run',
                    ),
                  ),
                  value: card.roleIds.contains(role.asString),
                  onChanged: (_) => _toggleSeminarRunCardRole(card, role),
                ),
                if (card.roleIds.contains(role.asString))
                  _buildSeminarRunCardRolePromptField(
                    card,
                    role,
                    expandedSessionId,
                  ),
                if (card.roleIds.contains(role.asString))
                  _buildSeminarRunCardRoleEvidenceScopeRow(
                    card,
                    role,
                    expandedSessionId,
                  ),
                if (card.roleIds.contains(role.asString))
                  _buildSeminarRunCardRoleToolRow(
                    card,
                    role,
                    expandedSessionId,
                  ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _localizedSeminarCardText(
                        zh: '最多讨论轮次',
                        en: 'Max discussion rounds',
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: ClaudePalette.fg(context),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  IconButton(
                    key: ValueKey(
                      'seminar-chat-card-rounds-minus-$expandedSessionId',
                    ),
                    visualDensity: VisualDensity.compact,
                    tooltip: _localizedSeminarCardText(
                      zh: '减少轮次',
                      en: 'Decrease rounds',
                    ),
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    onPressed: card.maxRounds <= 1
                        ? null
                        : () => _updateSeminarRunCardMaxRounds(
                              card,
                              card.maxRounds - 1,
                            ),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      '${card.maxRounds}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: ClaudePalette.fg(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  IconButton(
                    key: ValueKey(
                      'seminar-chat-card-rounds-plus-$expandedSessionId',
                    ),
                    visualDensity: VisualDensity.compact,
                    tooltip: _localizedSeminarCardText(
                      zh: '增加轮次',
                      en: 'Increase rounds',
                    ),
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    onPressed: card.maxRounds >= 10
                        ? null
                        : () => _updateSeminarRunCardMaxRounds(
                              card,
                              card.maxRounds + 1,
                            ),
                  ),
                ],
              ),
              Text(
                _localizedSeminarCardText(
                  zh: '只影响本次研讨，不会写回全局 Settings。',
                  en: 'Only this Seminar run changes. Global settings stay unchanged.',
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ClaudePalette.secondary(context),
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSeminarRunCardQuestionField(
    AiSeminarRunCardMeta card,
    String sessionId,
  ) {
    final controller = _seminarCardQuestionController(card, sessionId);
    return TextField(
      key: ValueKey('seminar-chat-card-question-input-$sessionId'),
      controller: controller,
      minLines: 2,
      maxLines: 4,
      textInputAction: TextInputAction.newline,
      decoration: InputDecoration(
        isDense: true,
        labelText: _localizedSeminarCardText(
          zh: '本次研讨问题',
          en: 'Seminar question',
        ),
        hintText: _localizedSeminarCardText(
          zh: '只影响本次研讨，不写回全局 Settings。',
          en: 'Only this Seminar run changes. Global settings stay unchanged.',
        ),
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) {
        unawaited(_updateSeminarRunCardQuestion(card, value));
      },
    );
  }

  TextEditingController _seminarCardQuestionController(
    AiSeminarRunCardMeta card,
    String sessionId,
  ) {
    return _seminarCardQuestionControllers.putIfAbsent(
      sessionId,
      () => TextEditingController(text: card.question),
    );
  }

  Future<void> _updateSeminarRunCardQuestion(
    AiSeminarRunCardMeta card,
    String question,
  ) async {
    final sessionId = card.sessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) return;
    final updated =
        await ref.read(aiChatProvider.notifier).updateSeminarRunCardConfig(
              seminarSessionId: sessionId,
              question: question,
            );
    if (!mounted || !updated) return;
    setState(() {});
  }

  Future<void> _updateSeminarRunCardMaxRounds(
    AiSeminarRunCardMeta card,
    int nextMaxRounds,
  ) async {
    final sessionId = card.sessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) return;
    final updated =
        await ref.read(aiChatProvider.notifier).updateSeminarRunCardConfig(
              seminarSessionId: sessionId,
              maxRounds: nextMaxRounds,
            );
    if (!mounted || !updated) return;
    setState(() {});
  }

  List<AiSeminarRole> _seminarCardSetupRoles(AiSeminarRunCardMeta card) {
    const order = <AiSeminarRole>[
      AiSeminarRole.critical,
      AiSeminarRole.supportive,
      AiSeminarRole.verifier,
      AiSeminarRole.synthesizer,
    ];
    final seen = <AiSeminarRole>{};
    final roles = <AiSeminarRole>[];
    for (final role in order) {
      if (seen.add(role)) roles.add(role);
    }
    for (final roleId in card.roleIds) {
      final role = AiSeminarRole.fromString(roleId);
      if (role != null && seen.add(role)) roles.add(role);
    }
    return roles;
  }

  Future<void> _toggleSeminarRunCardRole(
    AiSeminarRunCardMeta card,
    AiSeminarRole role,
  ) async {
    final sessionId = card.sessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) return;
    final isEnabled = card.roleIds.contains(role.asString);
    final nextEnabled = !isEnabled;
    final nextRoleIds = _seminarRunCardRoleIdsWith(
      card.roleIds,
      role,
      enabled: nextEnabled,
    );
    final nextRoleProfiles = _seminarRoleProfilesWithEnabled(
      card.roleProfiles,
      role,
      enabled: nextEnabled,
    );
    final nextEvidenceScopeIds =
        _seminarRunCardEvidenceScopeIdsFor(nextRoleProfiles);
    final updated =
        await ref.read(aiChatProvider.notifier).updateSeminarRunCardConfig(
              seminarSessionId: sessionId,
              roleIds: nextRoleIds,
              evidenceScopeIds: nextEvidenceScopeIds,
              roleProfiles: nextRoleProfiles,
            );
    if (!mounted || !updated) return;
    setState(() {});
  }

  List<String> _seminarRunCardRoleIdsWith(
    List<String> rawRoleIds,
    AiSeminarRole role, {
    required bool enabled,
  }) {
    final selected = <AiSeminarRole>{};
    for (final raw in rawRoleIds) {
      final parsed = AiSeminarRole.fromString(raw);
      if (parsed != null) selected.add(parsed);
    }
    if (enabled) {
      selected.add(role);
    } else {
      selected.remove(role);
    }
    if (selected.isEmpty) selected.add(AiSeminarRole.synthesizer);
    const order = <AiSeminarRole>[
      AiSeminarRole.critical,
      AiSeminarRole.supportive,
      AiSeminarRole.verifier,
      AiSeminarRole.synthesizer,
    ];
    return order
        .where(selected.contains)
        .map((item) => item.asString)
        .toList(growable: false);
  }

  List<AiSeminarRoleProfile> _seminarRoleProfilesWithEnabled(
    List<AiSeminarRoleProfile> profiles,
    AiSeminarRole role, {
    required bool enabled,
  }) {
    final byRole = <AiSeminarRole, AiSeminarRoleProfile>{
      for (final profile in profiles) profile.role: profile,
    };
    final existing = byRole[role];
    final next = AiSeminarRoleProfile(
      role: role,
      name: existing?.name,
      customPrompt: existing?.customPrompt,
      enabled: enabled,
      evidenceScopes: existing?.evidenceScopes ?? const [],
      allowedToolIds: existing?.allowedToolIds ?? const [],
    );
    if (next.hasOverrides) {
      byRole[role] = next;
    } else {
      byRole.remove(role);
    }
    const order = <AiSeminarRole>[
      AiSeminarRole.critical,
      AiSeminarRole.supportive,
      AiSeminarRole.verifier,
      AiSeminarRole.synthesizer,
    ];
    return [
      for (final role in order)
        if (byRole[role] != null) byRole[role]!,
    ];
  }

  Widget _buildSeminarRunCardRolePromptField(
    AiSeminarRunCardMeta card,
    AiSeminarRole role,
    String sessionId,
  ) {
    final label = _seminarRunRoleLabel(context, role);
    final controller = _seminarCardRolePromptController(
      card,
      role,
      sessionId,
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 46, bottom: 8),
      child: TextField(
        key: ValueKey(
          'seminar-chat-card-role-${role.asString}-prompt-$sessionId',
        ),
        controller: controller,
        minLines: 2,
        maxLines: 4,
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(
          isDense: true,
          labelText: _localizedSeminarCardText(
            zh: '$label本次提示词',
            en: '$label run prompt',
          ),
          hintText: _localizedSeminarCardText(
            zh: '只影响这场研讨，不写回全局 Settings。',
            en: 'Only this seminar run. Global settings stay unchanged.',
          ),
          border: const OutlineInputBorder(),
        ),
        onChanged: (value) {
          unawaited(_updateSeminarRunCardRolePrompt(card, role, value));
        },
      ),
    );
  }

  TextEditingController _seminarCardRolePromptController(
    AiSeminarRunCardMeta card,
    AiSeminarRole role,
    String sessionId,
  ) {
    final key = '$sessionId:${role.asString}';
    return _seminarCardRolePromptControllers.putIfAbsent(
      key,
      () => TextEditingController(
        text:
            _seminarRoleProfileFor(card.roleProfiles, role)?.customPrompt ?? '',
      ),
    );
  }

  AiSeminarRoleProfile? _seminarRoleProfileFor(
    List<AiSeminarRoleProfile> profiles,
    AiSeminarRole role,
  ) {
    for (final profile in profiles) {
      if (profile.role == role) return profile;
    }
    return null;
  }

  Future<void> _updateSeminarRunCardRolePrompt(
    AiSeminarRunCardMeta card,
    AiSeminarRole role,
    String customPrompt,
  ) async {
    final sessionId = card.sessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) return;
    final nextRoleProfiles = _seminarRoleProfilesWithCustomPrompt(
      card.roleProfiles,
      role,
      customPrompt: customPrompt,
    );
    final updated =
        await ref.read(aiChatProvider.notifier).updateSeminarRunCardConfig(
              seminarSessionId: sessionId,
              roleProfiles: nextRoleProfiles,
            );
    if (!mounted || !updated) return;
    setState(() {});
  }

  List<AiSeminarRoleProfile> _seminarRoleProfilesWithCustomPrompt(
    List<AiSeminarRoleProfile> profiles,
    AiSeminarRole role, {
    required String customPrompt,
  }) {
    final byRole = <AiSeminarRole, AiSeminarRoleProfile>{
      for (final profile in profiles) profile.role: profile,
    };
    final existing = byRole[role];
    final next = AiSeminarRoleProfile(
      role: role,
      name: existing?.name,
      customPrompt: customPrompt,
      enabled: existing?.enabled ?? true,
      evidenceScopes: existing?.evidenceScopes ?? const [],
      allowedToolIds: existing?.allowedToolIds ?? const [],
    );
    if (next.hasOverrides) {
      byRole[role] = next;
    } else {
      byRole.remove(role);
    }
    const order = <AiSeminarRole>[
      AiSeminarRole.critical,
      AiSeminarRole.supportive,
      AiSeminarRole.verifier,
      AiSeminarRole.synthesizer,
    ];
    return [
      for (final orderedRole in order)
        if (byRole[orderedRole] != null) byRole[orderedRole]!,
    ];
  }

  Widget _buildSeminarRunCardRoleEvidenceScopeRow(
    AiSeminarRunCardMeta card,
    AiSeminarRole role,
    String sessionId,
  ) {
    final l10n = L10n.of(context);
    final selectedScopes = _seminarRunCardRoleEvidenceScopes(card, role);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 46, bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final scope in _nativeSeminarRunEvidenceScopeOptions)
            _SeminarRunEvidenceScopeChip(
              key: ValueKey(
                'seminar-chat-card-role-${role.asString}-scope-'
                '${scope.asString}-$sessionId',
              ),
              label: _seminarEvidenceScopeLabel(scope.asString, l10n),
              selected: selectedScopes.contains(scope),
              onPressed: () => _toggleSeminarRunCardRoleEvidenceScope(
                card,
                role,
                scope,
              ),
            ),
        ],
      ),
    );
  }

  Set<AiSeminarEvidenceScope> _seminarRunCardRoleEvidenceScopes(
    AiSeminarRunCardMeta card,
    AiSeminarRole role,
  ) {
    for (final profile in card.roleProfiles) {
      if (profile.role != role) continue;
      if (profile.evidenceScopes.isEmpty) break;
      return profile.evidenceScopes.toSet();
    }
    return <AiSeminarEvidenceScope>{AiSeminarEvidenceScope.currentBook};
  }

  Future<void> _toggleSeminarRunCardRoleEvidenceScope(
    AiSeminarRunCardMeta card,
    AiSeminarRole role,
    AiSeminarEvidenceScope scope,
  ) async {
    final sessionId = card.sessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) return;
    final selected = _seminarRunCardRoleEvidenceScopes(card, role);
    if (selected.contains(scope)) {
      if (selected.length == 1) return;
      selected.remove(scope);
    } else {
      selected.add(scope);
    }
    if (selected.isEmpty) {
      selected.add(AiSeminarEvidenceScope.currentBook);
    }
    final nextRoleProfiles = _seminarRoleProfilesWithEvidenceScopes(
      card.roleProfiles,
      role,
      evidenceScopes: selected.toList(growable: false),
    );
    final nextEvidenceScopeIds =
        _seminarRunCardEvidenceScopeIdsFor(nextRoleProfiles);
    final updated =
        await ref.read(aiChatProvider.notifier).updateSeminarRunCardConfig(
              seminarSessionId: sessionId,
              evidenceScopeIds: nextEvidenceScopeIds,
              roleProfiles: nextRoleProfiles,
            );
    if (!mounted || !updated) return;
    setState(() {});
  }

  List<AiSeminarRoleProfile> _seminarRoleProfilesWithEvidenceScopes(
    List<AiSeminarRoleProfile> profiles,
    AiSeminarRole role, {
    required List<AiSeminarEvidenceScope> evidenceScopes,
  }) {
    final byRole = <AiSeminarRole, AiSeminarRoleProfile>{
      for (final profile in profiles) profile.role: profile,
    };
    final existing = byRole[role];
    final next = AiSeminarRoleProfile(
      role: role,
      name: existing?.name,
      customPrompt: existing?.customPrompt,
      enabled: existing?.enabled ?? true,
      evidenceScopes: evidenceScopes,
      allowedToolIds: existing?.allowedToolIds ?? const [],
    );
    if (next.hasOverrides) {
      byRole[role] = next;
    } else {
      byRole.remove(role);
    }
    const order = <AiSeminarRole>[
      AiSeminarRole.critical,
      AiSeminarRole.supportive,
      AiSeminarRole.verifier,
      AiSeminarRole.synthesizer,
    ];
    return [
      for (final role in order)
        if (byRole[role] != null) byRole[role]!,
    ];
  }

  Widget _buildSeminarRunCardRoleToolRow(
    AiSeminarRunCardMeta card,
    AiSeminarRole role,
    String sessionId,
  ) {
    final selectedToolIds = _seminarRunCardRoleAllowedToolIds(card, role);
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 46, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _localizedSeminarCardText(
              zh: '本次只读工具',
              en: 'Run read-only tools',
            ),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: ClaudePalette.fg(context),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final toolId in _seminarRoleToolIds)
                _SeminarRunEvidenceScopeChip(
                  key: ValueKey(
                    'seminar-chat-card-role-${role.asString}-tool-'
                    '$toolId-$sessionId',
                  ),
                  label: _seminarToolDisplayLabel(toolId),
                  selected: selectedToolIds.contains(toolId),
                  onPressed: () => _toggleSeminarRunCardRoleTool(
                    card,
                    role,
                    toolId,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Set<String> _seminarRunCardRoleAllowedToolIds(
    AiSeminarRunCardMeta card,
    AiSeminarRole role,
  ) {
    for (final profile in card.roleProfiles) {
      if (profile.role != role) continue;
      return profile.allowedToolIds.toSet();
    }
    return <String>{};
  }

  Future<void> _toggleSeminarRunCardRoleTool(
    AiSeminarRunCardMeta card,
    AiSeminarRole role,
    String toolId,
  ) async {
    final sessionId = card.sessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) return;
    final selected = _seminarRunCardRoleAllowedToolIds(card, role);
    if (selected.contains(toolId)) {
      selected.remove(toolId);
    } else {
      selected.add(toolId);
    }
    final nextRoleProfiles = _seminarRoleProfilesWithAllowedToolIds(
      card.roleProfiles,
      role,
      allowedToolIds: selected.toList(growable: false),
    );
    final updated =
        await ref.read(aiChatProvider.notifier).updateSeminarRunCardConfig(
              seminarSessionId: sessionId,
              roleProfiles: nextRoleProfiles,
            );
    if (!mounted || !updated) return;
    setState(() {});
  }

  List<AiSeminarRoleProfile> _seminarRoleProfilesWithAllowedToolIds(
    List<AiSeminarRoleProfile> profiles,
    AiSeminarRole role, {
    required List<String> allowedToolIds,
  }) {
    final byRole = <AiSeminarRole, AiSeminarRoleProfile>{
      for (final profile in profiles) profile.role: profile,
    };
    final existing = byRole[role];
    final next = AiSeminarRoleProfile(
      role: role,
      name: existing?.name,
      customPrompt: existing?.customPrompt,
      enabled: existing?.enabled ?? true,
      evidenceScopes: existing?.evidenceScopes ?? const [],
      allowedToolIds: allowedToolIds,
    );
    if (next.hasOverrides) {
      byRole[role] = next;
    } else {
      byRole.remove(role);
    }
    const order = <AiSeminarRole>[
      AiSeminarRole.critical,
      AiSeminarRole.supportive,
      AiSeminarRole.verifier,
      AiSeminarRole.synthesizer,
    ];
    return [
      for (final role in order)
        if (byRole[role] != null) byRole[role]!,
    ];
  }

  List<String> _seminarRunCardEvidenceScopeIdsFor(
    List<AiSeminarRoleProfile> profiles,
  ) {
    final scopes = <AiSeminarEvidenceScope>[AiSeminarEvidenceScope.currentBook];
    for (final profile in profiles) {
      if (!profile.enabled) continue;
      for (final scope in profile.evidenceScopes) {
        if (!scopes.contains(scope)) scopes.add(scope);
      }
    }
    return scopes.map((scope) => scope.asString).toList(growable: false);
  }

  bool _shouldShowSeminarCardStartAction(
    AiSeminarRunCardMeta card,
    AiSeminarRuntimeState runtimeState,
  ) {
    final sessionId = card.sessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) return false;
    if (card.question.trim().isEmpty) return false;
    final snapshot = card.snapshot;
    if (snapshot != null &&
        !snapshot.isEmpty &&
        !_seminarSnapshotHasOnlyRunSetup(snapshot)) {
      return false;
    }
    if (card.status != 'ready' && card.status != 'draft') return false;
    if (runtimeState.session?.id == sessionId &&
        runtimeState.status != AiSeminarRunStatus.draft) {
      return false;
    }
    return true;
  }

  bool _seminarSnapshotHasOnlyRunSetup(AiSeminarRunCardSnapshot snapshot) {
    if (snapshot.evidence.where((item) => !item.isEmpty).isNotEmpty ||
        snapshot.toolCalls.where((item) => !item.isEmpty).isNotEmpty ||
        snapshot.roleSummaries.where((item) => !item.isEmpty).isNotEmpty ||
        (snapshot.synthesisSummary?.trim().isNotEmpty ?? false) ||
        snapshot.disagreements
            .where((item) => item.trim().isNotEmpty)
            .isNotEmpty ||
        snapshot.disagreementDetails
            .where((item) => !item.isEmpty)
            .isNotEmpty ||
        snapshot.openQuestions
            .where((item) => item.trim().isNotEmpty)
            .isNotEmpty) {
      return false;
    }
    final parts = snapshot.messageParts
        .where((part) => !part.isEmpty)
        .toList(growable: false);
    return parts.isNotEmpty &&
        parts.every((part) => part.type.trim() == 'seminar_run_setup');
  }

  Widget _buildSeminarRunCardStartAction(AiSeminarRunCardMeta card) {
    final sessionId = card.sessionId?.trim();
    final isSubmitting = sessionId != null &&
        _seminarCardSubmittingSessionIds.contains(sessionId);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: FilledButton.icon(
        key: sessionId == null
            ? null
            : ValueKey('seminar-chat-card-start-$sessionId'),
        icon: isSubmitting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.play_arrow_outlined, size: 18),
        label: Text(
          _localizedSeminarCardText(
            zh: '开始研讨',
            en: 'Start Seminar',
          ),
        ),
        onPressed:
            isSubmitting ? null : () => _startSeminarRunCardFromChat(card),
      ),
    );
  }

  bool _shouldShowSeminarCardCancelAction(
    AiSeminarRunCardMeta card,
    AiSeminarRuntimeState runtimeState,
  ) {
    final sessionId = card.sessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) return false;
    return runtimeState.session?.id == sessionId && runtimeState.canCancel;
  }

  List<Widget> _seminarRunCardHeaderControls({
    required AiSeminarRunCardMeta card,
    required AiSeminarRunCardSnapshot? snapshot,
    required bool canCancelFromCard,
  }) {
    final sessionId = card.sessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) return const [];
    final controls = <Widget>[
      if (canCancelFromCard) _buildSeminarRunCardCancelAction(card),
    ];
    if (snapshot != null) {
      for (final part in snapshot.messageParts) {
        final actionIds = part.actionIds
            .map((actionId) => actionId.trim())
            .where((actionId) =>
                _seminarAgentControlActionLabel(actionId).isNotEmpty)
            .where((actionId) => _seminarAgentControlActionIsExecutable(
                  part,
                  actionId: actionId,
                  sessionId: sessionId,
                ))
            .toList(growable: false);
        for (final actionId in actionIds) {
          controls.add(
            _seminarAgentControlAction(
              part,
              actionId: actionId,
              sessionId: sessionId,
            ),
          );
        }
      }
    }
    return controls;
  }

  Widget _buildSeminarRunCardCancelAction(AiSeminarRunCardMeta card) {
    final sessionId = card.sessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) {
      return const SizedBox.shrink();
    }
    return ActionChip(
      key: ValueKey('seminar-chat-card-cancel-$sessionId'),
      avatar: const Icon(Icons.stop_circle_outlined, size: 16),
      label: Text(
        _localizedSeminarCardText(
          zh: '取消研讨',
          en: 'Cancel seminar',
        ),
      ),
      onPressed: () => _cancelActiveSeminarRunCard(sessionId),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: ClaudePalette.divider(context)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  bool _shouldShowSeminarCardResumeBanner(
    AiSeminarRunCardMeta card,
    AiSeminarRuntimeState runtimeState,
  ) {
    final sessionId = card.sessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) return false;
    return runtimeState.session?.id == sessionId &&
        runtimeState.canResumeRestoredRunning;
  }

  Widget _buildSeminarRunCardResumeBanner(
    AiSeminarRunCardMeta card,
    AiSeminarRuntimeState runtimeState, {
    required bool showDetails,
    required VoidCallback onOpen,
    required VoidCallback onContinue,
  }) {
    final sessionId = card.sessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) {
      return const SizedBox.shrink();
    }
    final isSubmitting = _seminarCardSubmittingSessionIds.contains(sessionId);
    final completedRoleCount = runtimeState.turns
        .where((turn) => turn.responseText.trim().isNotEmpty)
        .length;
    final provider = runtimeState.providerDiagnostics;
    final providerLabel = provider == null || provider.modelId.trim().isEmpty
        ? ''
        : ' · ${provider.providerName} / ${provider.modelId}';
    final detail = _localizedSeminarCardText(
      zh: '已完成 $completedRoleCount 个角色，可直接继续缺失角色，也可展开断点详情$providerLabel。',
      en: '$completedRoleCount roles completed. Continue missing roles directly, or expand checkpoint details$providerLabel.',
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ClaudePalette.divider(context)),
        color: ClaudePalette.accentTint(context).withValues(alpha: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.restore_outlined,
                  size: 18,
                  color: ClaudePalette.accent(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _localizedSeminarCardText(
                          zh: '可从中断处继续',
                          en: 'Resumable checkpoint',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: ClaudePalette.fg(context),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.32,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: ValueKey('seminar-chat-card-continue-$sessionId'),
                  onPressed: isSubmitting ? null : onContinue,
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_outlined, size: 18),
                  label: Text(
                    _localizedSeminarCardText(
                      zh: '继续研讨',
                      en: 'Continue seminar',
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  key: ValueKey('seminar-chat-card-resume-$sessionId'),
                  onPressed: isSubmitting ? null : onOpen,
                  icon: Icon(
                    showDetails
                        ? Icons.expand_less_outlined
                        : Icons.expand_more_outlined,
                    size: 18,
                  ),
                  label: Text(
                    _localizedSeminarCardText(
                      zh: showDetails ? '收起断点' : '断点详情',
                      en: showDetails
                          ? 'Hide checkpoint'
                          : 'Checkpoint details',
                    ),
                  ),
                ),
              ],
            ),
            if (showDetails) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: ClaudePalette.divider(context)),
              const SizedBox(height: 10),
              _buildSeminarRunCardResumeDetails(runtimeState),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSeminarRunCardResumeDetails(
    AiSeminarRuntimeState runtimeState,
  ) {
    final completedRoles = _seminarResumeCompletedRoleLabels(runtimeState);
    final completedRoleText = completedRoles.isEmpty
        ? _localizedSeminarCardText(
            zh: '暂无已完成角色',
            en: 'No completed roles yet',
          )
        : completedRoles.join('、');
    final evidenceCount = runtimeState.evidenceBundle?.evidence.length ?? 0;
    final evidenceText = _localizedSeminarCardText(
      zh: '$evidenceCount 条证据',
      en: '$evidenceCount evidence items',
    );
    final providerText = _seminarResumeProviderLabel(runtimeState);
    final nextStepText = _seminarResumeNextStepLabel(runtimeState);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _localizedSeminarCardText(
            zh: '断点详情',
            en: 'Checkpoint details',
          ),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: ClaudePalette.fg(context),
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        _buildSeminarRunCardResumeDetailRow(
          icon: Icons.history_toggle_off_outlined,
          label: _localizedSeminarCardText(
            zh: '断点状态',
            en: 'Checkpoint',
          ),
          value: _localizedSeminarCardText(
            zh: '可继续 · 已完成：$completedRoleText',
            en: 'Resumable · completed: $completedRoleText',
          ),
        ),
        _buildSeminarRunCardResumeDetailRow(
          icon: Icons.manage_search_outlined,
          label: _localizedSeminarCardText(
            zh: '已保存证据',
            en: 'Saved evidence',
          ),
          value: evidenceText,
        ),
        _buildSeminarRunCardResumeDetailRow(
          icon: Icons.route_outlined,
          label: _localizedSeminarCardText(
            zh: '下一步',
            en: 'Next step',
          ),
          value: nextStepText,
        ),
        if (providerText.isNotEmpty)
          _buildSeminarRunCardResumeDetailRow(
            icon: Icons.memory_outlined,
            label: _localizedSeminarCardText(
              zh: '模型',
              en: 'Model',
            ),
            value: providerText,
          ),
      ],
    );
  }

  Widget _buildSeminarRunCardResumeDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 17,
            color: ClaudePalette.fg(context).withValues(alpha: 0.62),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ClaudePalette.secondary(context),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ClaudePalette.fg(context),
                    height: 1.32,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _seminarResumeCompletedRoleLabels(
    AiSeminarRuntimeState runtimeState,
  ) {
    final seen = <AiSeminarRole>{};
    final labels = <String>[];
    for (final turn in runtimeState.turns) {
      if (turn.responseText.trim().isEmpty || !seen.add(turn.role)) continue;
      labels.add(_seminarRunRoleLabel(context, turn.role));
    }
    return labels;
  }

  String _seminarResumeNextStepLabel(AiSeminarRuntimeState runtimeState) {
    final completed = runtimeState.turns
        .where((turn) => turn.responseText.trim().isNotEmpty)
        .map((turn) => turn.role)
        .toSet();
    final roles = runtimeState.session?.roles ?? AiSeminarRole.defaultRoles;
    for (final role in roles) {
      if (!completed.contains(role)) {
        final label = _seminarRunRoleLabel(context, role);
        return _localizedSeminarCardText(
          zh: '继续 $label',
          en: 'Continue $label',
        );
      }
    }
    return _localizedSeminarCardText(
      zh: '出总结',
      en: 'Synthesize',
    );
  }

  String _seminarResumeProviderLabel(AiSeminarRuntimeState runtimeState) {
    final diagnostics = runtimeState.providerDiagnostics;
    final diagnosticsProvider = diagnostics?.providerName.trim() ?? '';
    final diagnosticsModel = diagnostics?.modelId.trim() ?? '';
    if (diagnosticsProvider.isNotEmpty || diagnosticsModel.isNotEmpty) {
      return [
        if (diagnosticsProvider.isNotEmpty) diagnosticsProvider,
        if (diagnosticsModel.isNotEmpty) diagnosticsModel,
      ].join(' / ');
    }

    final billing = runtimeState.session?.billingContext;
    final providerName = billing?.providerName.trim() ?? '';
    final modelId = billing?.modelId.trim() ?? '';
    return [
      if (providerName.isNotEmpty) providerName,
      if (modelId.isNotEmpty) modelId,
    ].join(' / ');
  }

  Future<void> _continueSeminarRunCardFromCheckpoint(
    String? rawSessionId,
  ) async {
    final sessionId = rawSessionId?.trim();
    if (sessionId == null ||
        sessionId.isEmpty ||
        _seminarCardSubmittingSessionIds.contains(sessionId)) {
      return;
    }
    final runtimeState = _readSeminarRuntimeState(sessionId);
    if (runtimeState.session?.id != sessionId ||
        !runtimeState.canResumeRestoredRunning) {
      return;
    }
    setState(() => _seminarCardSubmittingSessionIds.add(sessionId));
    try {
      await _readSeminarRuntimeNotifier(sessionId).resumeRestoredRunning();
      if (!mounted) return;
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      _seminarCardSubmittingSessionIds.remove(sessionId);
      if (mounted) setState(() {});
    }
  }

  void _cancelActiveSeminarRunCard(String rawSessionId) {
    final sessionId = rawSessionId.trim();
    if (sessionId.isEmpty) return;
    final runtimeState = _readSeminarRuntimeState(sessionId);
    if (runtimeState.session?.id != sessionId || !runtimeState.canCancel) {
      return;
    }
    _readSeminarRuntimeNotifier(sessionId).cancel();
    _seminarCardSubmittingSessionIds.remove(sessionId);
    _lastSeminarCardSignatures.remove(sessionId);
    if (mounted) setState(() {});
  }

  Future<void> _startSeminarRunCardFromChat(
    AiSeminarRunCardMeta card,
  ) async {
    final sessionId = card.sessionId?.trim();
    if (sessionId == null ||
        sessionId.isEmpty ||
        _seminarCardSubmittingSessionIds.contains(sessionId)) {
      return;
    }
    final question = card.question.trim();
    if (question.isEmpty) return;
    final runtimeState = _readSeminarRuntimeState(sessionId);
    if (runtimeState.session?.id == sessionId &&
        runtimeState.status != AiSeminarRunStatus.draft) {
      return;
    }
    final roles = _seminarRunCardRoles(card);
    final now = DateTime.now().millisecondsSinceEpoch;
    setState(() => _seminarCardSubmittingSessionIds.add(sessionId));
    _lastSeminarCardSignatures.remove(sessionId);
    try {
      await _readSeminarRuntimeNotifier(sessionId).start(
        AiSeminarSessionContract(
          id: sessionId,
          question: question,
          bookId: card.sourceRef?.bookId ?? card.bookId,
          sourceRefs: [
            if (card.sourceRef != null) card.sourceRef!,
          ],
          roles: roles,
          maxRounds: card.maxRounds,
          roleProfiles: card.roleProfiles,
          createdAt: now,
        ),
      );
      if (!mounted) return;
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      _seminarCardSubmittingSessionIds.remove(sessionId);
      if (mounted) setState(() {});
    }
  }

  List<AiSeminarRole> _seminarRunCardRoles(AiSeminarRunCardMeta card) {
    final roles = card.roleIds
        .map(AiSeminarRole.fromString)
        .nonNulls
        .toList(growable: false);
    return roles.isEmpty ? const [AiSeminarRole.synthesizer] : roles;
  }

  // P1 F19b: the in-card participation layer is frozen. Completed cards show
  // a static hint pointing readers to the main composer, where seminar
  // conclusions are available through the F19a prompt digest.
  bool _shouldShowSeminarCardFollowUpHint(
    AiSeminarRunCardMeta card,
    AiSeminarRuntimeState runtimeState,
  ) {
    if (card.status.trim() == 'completed') return true;
    final sessionId = card.sessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) return false;
    return runtimeState.session?.id == sessionId &&
        runtimeState.status == AiSeminarRunStatus.completed;
  }

  Widget _buildSeminarRunCardFollowUpHint() {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.chat_bubble_outline,
          size: 16,
          color: theme.colorScheme.outline,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _localizedSeminarCardText(
              zh: '研讨已结束,可直接在下方对话框继续追问本场结论',
              en: 'Seminar finished — ask follow-ups about its conclusions '
                  'in the chat box below',
            ),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      ],
    );
  }

  TextEditingController _seminarCardReplyController(String sessionId) {
    return _seminarCardReplyControllers.putIfAbsent(
      sessionId,
      () => TextEditingController(),
    );
  }

  List<String> _seminarComposerRoleIdsFromState(
    AiSeminarRuntimeState runtimeState,
  ) {
    final sessionRoles = runtimeState.session?.roles;
    final roles = sessionRoles != null && sessionRoles.isNotEmpty
        ? sessionRoles
        : AiSeminarRole.defaultRoles;
    final nonSynthesizerRoles = roles
        .where((role) => role != AiSeminarRole.synthesizer)
        .toList(growable: false);
    final effectiveRoles =
        nonSynthesizerRoles.isEmpty ? roles : nonSynthesizerRoles;
    return effectiveRoles
        .map((role) => role.asString)
        .where((roleId) => roleId.trim().isNotEmpty)
        .toList(growable: false);
  }

  String? _seminarComposerDefaultRoleIdFromState(
    AiSeminarRuntimeState _,
  ) {
    return null;
  }

  String? _seminarComposerSelectedRoleIdFromState(
    AiSeminarRuntimeState runtimeState,
  ) {
    final sessionId = runtimeState.session?.id.trim();
    if (sessionId != null && sessionId.isNotEmpty) {
      final selectedRole = _seminarCardSelectedRoles[sessionId];
      if (selectedRole != null) return selectedRole.asString;
    }
    return null;
  }

  String? _seminarComposerSelectedActionIdFromState(
    AiSeminarRuntimeState runtimeState,
  ) {
    final sessionId = runtimeState.session?.id.trim();
    if (sessionId != null && sessionId.isNotEmpty) {
      final selectedAction = _seminarCardSelectedActionIds[sessionId]?.trim();
      if (selectedAction != null && selectedAction.isNotEmpty) {
        return selectedAction;
      }
    }
    return 'ask-role';
  }

  String? _seminarComposerDraftTextFromState(
    AiSeminarRuntimeState runtimeState,
  ) {
    final sessionId = runtimeState.session?.id.trim();
    if (sessionId == null || sessionId.isEmpty) return null;
    final draft = _seminarCardReplyControllers[sessionId]?.text.trim();
    return draft == null || draft.isEmpty ? null : draft;
  }

  String? _seminarCardFirstOpenQuestion(AiSeminarRuntimeState runtimeState) {
    final entries = <AiSeminarWhiteboardEntry>[
      ...runtimeState.whiteboardEntries,
      for (final turn in runtimeState.turns) ...turn.whiteboardEntries,
    ];
    for (final entry in entries) {
      if (entry.kind != AiSeminarWhiteboardKind.openQuestion) continue;
      final text = entry.text.trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  Future<void> _sendActiveSeminarRunCardToReview(String? sessionId) async {
    final l10n = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final normalizedSessionId = sessionId?.trim();
    final runtimeState = _readSeminarRuntimeState(normalizedSessionId);
    if (normalizedSessionId == null ||
        normalizedSessionId.isEmpty ||
        runtimeState.session?.id != normalizedSessionId ||
        !runtimeState.canSendToReview ||
        _seminarCardSentToReviewSessionIds.contains(normalizedSessionId)) {
      return;
    }
    try {
      final result =
          await _readSeminarRuntimeNotifier(normalizedSessionId).sendToReview();
      if (!mounted) return;
      setState(() {
        _seminarCardSentToReviewSessionIds.add(normalizedSessionId);
      });
      final artifactPart = _seminarArtifactActionsPartForCurrentState(
        _readSeminarRuntimeState(normalizedSessionId),
      );
      unawaited(
        _recordSeminarRunCardArtifactActionEvent(
          sessionId: normalizedSessionId,
          actionIds: const ['sent-to-review'],
          status: SubAgentRunStatus.completed,
          text: artifactPart?.text?.trim().isNotEmpty == true
              ? artifactPart!.text!.trim()
              : _localizedSeminarCardText(
                  zh: '异常已送审。',
                  en: 'Exception sent to Review Inbox.',
                ),
          evidenceRefs: artifactPart?.evidenceRefs ??
              const <AiSeminarRunCardEvidenceSnapshot>[],
        ),
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.seminarSentToReview(result.knowledgeCardIds.length),
          ),
        ),
      );
      await _syncSeminarRunCardSnapshotNow(
        normalizedSessionId,
        _readSeminarRuntimeState(normalizedSessionId),
      );
      if (!mounted) return;
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _recordSeminarRunCardArtifactActionEvent({
    required String sessionId,
    required List<String> actionIds,
    required SubAgentRunStatus status,
    required String text,
    List<AiSeminarRunCardEvidenceSnapshot> evidenceRefs =
        const <AiSeminarRunCardEvidenceSnapshot>[],
  }) async {
    final normalizedSessionId = sessionId.trim();
    final normalizedActions = actionIds
        .map((actionId) => actionId.trim())
        .where((actionId) => actionId.isNotEmpty)
        .toList(growable: false);
    if (normalizedSessionId.isEmpty || normalizedActions.isEmpty) return;
    if (documentPath.trim().isEmpty) return;
    final actionKey = normalizedActions.join('+');
    try {
      await AgentRunGraphStore().upsertEvent(AgentRunEvent(
        eventId: '$normalizedSessionId:artifact-action:$actionKey',
        runId: normalizedSessionId,
        type: AgentRunEventType.artifactAction,
        createdAt: DateTime.now(),
        status: status,
        roleId: 'director',
        nickname: 'Director',
        actionIds: normalizedActions,
        result: text.trim().isEmpty ? null : text.trim(),
        evidenceRefs: evidenceRefs
            .where((evidence) => !evidence.isEmpty)
            .toList(growable: false),
      ));
    } catch (_) {
      // Review handoff already succeeded; missing event replay should not undo it.
    }
  }

  Future<void> _recordSeminarRunCardArtifactActionsCurrentStateEvent({
    required String sessionId,
    required String markerActionId,
    required String text,
  }) async {
    final normalizedSessionId = sessionId.trim();
    final marker = markerActionId.trim();
    if (normalizedSessionId.isEmpty || marker.isEmpty) return;
    final artifactPart = _seminarArtifactActionsPartForCurrentState(
      _readSeminarRuntimeState(normalizedSessionId),
    );
    final actionIds = <String>[
      marker,
      ...?artifactPart?.actionIds.where(
        (actionId) => actionId.trim() != marker,
      ),
    ];
    await _recordSeminarRunCardArtifactActionEvent(
      sessionId: normalizedSessionId,
      actionIds: actionIds,
      status: SubAgentRunStatus.completed,
      text: text,
      evidenceRefs: artifactPart?.evidenceRefs ??
          const <AiSeminarRunCardEvidenceSnapshot>[],
    );
  }

  Future<void> _ignoreSeminarRunCardAssetActions(String? sessionId) async {
    final normalizedSessionId = sessionId?.trim();
    if (normalizedSessionId == null || normalizedSessionId.isEmpty) return;
    setState(() {
      _seminarCardIgnoredActionSessionIds.add(normalizedSessionId);
    });
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            _localizedSeminarCardText(
              zh: '已忽略本次沉淀建议。',
              en: 'Suggestions ignored for this Seminar.',
            ),
          ),
        ),
      );
    await _syncSeminarRunCardSnapshotNow(
      normalizedSessionId,
      _readSeminarRuntimeState(normalizedSessionId),
    );
    if (!mounted) return;
  }

  Future<void> _restoreSeminarRunCardAssetActions(String? sessionId) async {
    final normalizedSessionId = sessionId?.trim();
    if (normalizedSessionId == null || normalizedSessionId.isEmpty) return;
    setState(() {
      _seminarCardIgnoredActionSessionIds.remove(normalizedSessionId);
    });
    await _recordSeminarRunCardArtifactActionsCurrentStateEvent(
      sessionId: normalizedSessionId,
      markerActionId: 'restore-artifact-actions',
      text: _localizedSeminarCardText(
        zh: '沉淀建议已恢复。',
        en: 'Artifact suggestions restored.',
      ),
    );
    await _syncSeminarRunCardSnapshotNow(
      normalizedSessionId,
      _readSeminarRuntimeState(normalizedSessionId),
    );
    if (!mounted) return;
  }

  Future<void> _saveActiveSeminarRunCardKnowledgeCard(
    String? sessionId, {
    String? editedTitle,
    String? editedExplanation,
  }) async {
    final normalizedSessionId = sessionId?.trim();
    if (normalizedSessionId == null || normalizedSessionId.isEmpty) return;
    final cardId = _seminarSynthesisKnowledgeCardId(normalizedSessionId);
    if (cardId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final runtimeState = _readSeminarRuntimeState(normalizedSessionId);
    final synthesis = runtimeState.synthesis;
    final sourceRefs = _seminarSynthesisKnowledgeCardSourceRefs(runtimeState);
    if (runtimeState.session?.id != normalizedSessionId ||
        synthesis == null ||
        synthesis.summary.trim().isEmpty ||
        sourceRefs.isEmpty) {
      return;
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final quote = sourceRefs
        .map((ref) => ref.sourceTextSnippet ?? '')
        .firstWhere((text) => text.trim().isNotEmpty, orElse: () => '');
    final title = editedTitle?.trim().isNotEmpty == true
        ? editedTitle!.trim()
        : 'AI Seminar synthesis';
    final explanation = editedExplanation?.trim().isNotEmpty == true
        ? editedExplanation!.trim()
        : synthesis.summary.trim();
    final card = KnowledgeCard(
      id: cardId,
      title: title,
      quote: quote,
      explanation: explanation,
      sourceRefs: sourceRefs,
      reviewState: KnowledgeCardReviewState.draft,
      origin: KnowledgeCardOrigin.seminar,
      ownership: AiOutputOwnership.aiGeneratedDraft,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    try {
      final result =
          await ref.read(aiSeminarKnowledgeCardStoreProvider).upsertCandidate(
                card,
              );
      if (!mounted) return;
      final shouldSyncSnapshot = result.inserted || result.card.id == cardId;
      if (shouldSyncSnapshot) {
        setState(() => _seminarCardSavedKnowledgeCardIds.add(cardId));
      }
      showKnowledgeCardSavedSnackBar(
        context,
        message: _localizedSeminarCardText(
          zh: '已保存为知识卡。',
          en: 'Saved as a KnowledgeCard.',
        ),
        card: result.card,
      );
      if (shouldSyncSnapshot) {
        await _syncSeminarRunCardSnapshotNow(
          normalizedSessionId,
          _readSeminarRuntimeState(normalizedSessionId),
        );
        if (!mounted) return;
      }
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _editActiveSeminarRunCardKnowledgeCard(
    String? sessionId,
  ) async {
    final normalizedSessionId = sessionId?.trim();
    if (normalizedSessionId == null || normalizedSessionId.isEmpty) return;
    final runtimeState = _readSeminarRuntimeState(normalizedSessionId);
    final synthesis = runtimeState.synthesis;
    if (runtimeState.session?.id != normalizedSessionId ||
        synthesis == null ||
        synthesis.summary.trim().isEmpty ||
        _seminarSynthesisKnowledgeCardSourceRefs(runtimeState).isEmpty) {
      return;
    }
    final edited = await _showSeminarKnowledgeCardEditDialog(
      initialTitle: 'AI Seminar synthesis',
      initialExplanation: synthesis.summary.trim(),
    );
    if (!mounted || edited == null) return;
    await _saveActiveSeminarRunCardKnowledgeCard(
      normalizedSessionId,
      editedTitle: edited['title'],
      editedExplanation: edited['explanation'],
    );
  }

  Future<Map<String, String>?> _showSeminarKnowledgeCardEditDialog({
    required String initialTitle,
    required String initialExplanation,
  }) async {
    var title = initialTitle;
    var explanation = initialExplanation;
    String? explanationError;
    return showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                _localizedSeminarCardText(
                  zh: '编辑知识卡',
                  en: 'Edit KnowledgeCard',
                ),
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        key: const ValueKey('seminar-card-edit-title'),
                        initialValue: initialTitle,
                        decoration: InputDecoration(
                          labelText: _localizedSeminarCardText(
                            zh: '标题',
                            en: 'Title',
                          ),
                        ),
                        onChanged: (value) => title = value,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const ValueKey('seminar-card-edit-explanation'),
                        initialValue: initialExplanation,
                        minLines: 4,
                        maxLines: 8,
                        decoration: InputDecoration(
                          labelText: _localizedSeminarCardText(
                            zh: '解释',
                            en: 'Explanation',
                          ),
                          errorText: explanationError,
                        ),
                        onChanged: (value) => explanation = value,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    _localizedSeminarCardText(
                      zh: '取消',
                      en: 'Cancel',
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    final normalizedExplanation = explanation.trim();
                    if (normalizedExplanation.isEmpty) {
                      setDialogState(() {
                        explanationError = _localizedSeminarCardText(
                          zh: '解释不能为空',
                          en: 'Explanation is required',
                        );
                      });
                      return;
                    }
                    final normalizedTitle = title.trim();
                    Navigator.of(dialogContext).pop({
                      'title': normalizedTitle.isEmpty
                          ? initialTitle
                          : normalizedTitle,
                      'explanation': normalizedExplanation,
                    });
                  },
                  child: Text(
                    _localizedSeminarCardText(
                      zh: '保存',
                      en: 'Save',
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _undoActiveSeminarRunCardKnowledgeCard(
    String? sessionId,
  ) async {
    final cardId = _seminarSynthesisKnowledgeCardId(sessionId);
    if (cardId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final removed = await ref
          .read(aiSeminarKnowledgeCardStoreProvider)
          .removeDraftCandidate(cardId);
      if (!mounted) return;
      setState(() => _seminarCardSavedKnowledgeCardIds.remove(cardId));
      final normalizedSessionId = sessionId?.trim();
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            removed
                ? _localizedSeminarCardText(
                    zh: '已撤销知识卡保存。',
                    en: 'KnowledgeCard save undone.',
                  )
                : _localizedSeminarCardText(
                    zh: '这张知识卡已确认或已不存在，不能撤销。',
                    en: 'This KnowledgeCard was already confirmed or removed.',
                  ),
          ),
        ),
      );
      if (normalizedSessionId != null && normalizedSessionId.isNotEmpty) {
        if (removed) {
          await _recordSeminarRunCardArtifactActionsCurrentStateEvent(
            sessionId: normalizedSessionId,
            markerActionId: 'undo-knowledge-card',
            text: _localizedSeminarCardText(
              zh: '已撤销知识卡保存。',
              en: 'KnowledgeCard save undone.',
            ),
          );
        }
        await _syncSeminarRunCardSnapshotNow(
          normalizedSessionId,
          _readSeminarRuntimeState(normalizedSessionId),
        );
        if (!mounted) return;
      }
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _addActiveSeminarRunCardSpacedReview(
    String? sessionId,
  ) async {
    final normalizedSessionId = sessionId?.trim();
    if (normalizedSessionId == null || normalizedSessionId.isEmpty) return;
    final flashcardId = _seminarSynthesisReviewFlashcardId(normalizedSessionId);
    if (flashcardId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final runtimeState = _readSeminarRuntimeState(normalizedSessionId);
    final synthesis = runtimeState.synthesis;
    final sourceRefs = _seminarSynthesisKnowledgeCardSourceRefs(runtimeState);
    if (runtimeState.session?.id != normalizedSessionId ||
        synthesis == null ||
        synthesis.summary.trim().isEmpty ||
        sourceRefs.isEmpty) {
      return;
    }
    try {
      await ref.read(spacedReviewStoreProvider).upsertInlineFlashcard(
            flashcardId: flashcardId,
            prompt: _localizedSeminarCardText(
              zh: '复习这场 AI Seminar 的结论',
              en: 'Review this AI Seminar synthesis',
            ),
            answer: synthesis.summary.trim(),
            sourceRefs: sourceRefs,
          );
      if (!mounted) return;
      setState(() => _seminarCardSpacedReviewFlashcardIds.add(flashcardId));
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _localizedSeminarCardText(
              zh: '已加入复习。',
              en: 'Added to spaced review.',
            ),
          ),
        ),
      );
      await _syncSeminarRunCardSnapshotNow(
        normalizedSessionId,
        _readSeminarRuntimeState(normalizedSessionId),
      );
      if (!mounted) return;
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _undoActiveSeminarRunCardSpacedReview(
    String? sessionId,
  ) async {
    final flashcardId = _seminarSynthesisReviewFlashcardId(sessionId);
    if (flashcardId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final removed =
          await ref.read(spacedReviewStoreProvider).removeInlineFlashcard(
                flashcardId,
              );
      if (!mounted) return;
      setState(() => _seminarCardSpacedReviewFlashcardIds.remove(flashcardId));
      final normalizedSessionId = sessionId?.trim();
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            removed
                ? _localizedSeminarCardText(
                    zh: '已撤销复习。',
                    en: 'Spaced review undone.',
                  )
                : _localizedSeminarCardText(
                    zh: '这条复习已经有记录或已不存在，不能撤销。',
                    en: 'This review item was already reviewed or removed.',
                  ),
          ),
        ),
      );
      if (normalizedSessionId != null && normalizedSessionId.isNotEmpty) {
        if (removed) {
          await _recordSeminarRunCardArtifactActionsCurrentStateEvent(
            sessionId: normalizedSessionId,
            markerActionId: 'undo-spaced-review',
            text: _localizedSeminarCardText(
              zh: '已撤销复习。',
              en: 'Spaced review undone.',
            ),
          );
        }
        await _syncSeminarRunCardSnapshotNow(
          normalizedSessionId,
          _readSeminarRuntimeState(normalizedSessionId),
        );
        if (!mounted) return;
      }
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _addActiveSeminarRunCardConceptGraph(
    String? sessionId,
  ) async {
    final normalizedSessionId = sessionId?.trim();
    if (normalizedSessionId == null || normalizedSessionId.isEmpty) return;
    final nodeId = _seminarSynthesisConceptNodeId(normalizedSessionId);
    if (nodeId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final runtimeState = _readSeminarRuntimeState(normalizedSessionId);
    final synthesis = runtimeState.synthesis;
    final sourceRefs = _seminarSynthesisKnowledgeCardSourceRefs(runtimeState);
    if (runtimeState.session?.id != normalizedSessionId ||
        synthesis == null ||
        synthesis.summary.trim().isEmpty ||
        sourceRefs.isEmpty) {
      return;
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final summary = synthesis.summary.trim();
    try {
      await ref.read(conceptGraphStoreProvider).upsertNode(
            ConceptNode(
              id: nodeId,
              type: ConceptNodeType.claim,
              label: _seminarConceptNodeLabel(summary),
              summary: summary,
              sourceRefs: sourceRefs,
              ownership: AiOutputOwnership.aiGeneratedDraft,
              createdAt: timestamp,
              updatedAt: timestamp,
            ),
          );
      if (!mounted) return;
      setState(() => _seminarCardConceptNodeIds.add(nodeId));
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _localizedSeminarCardText(
              zh: '已加入我的图谱。',
              en: 'Added to my graph.',
            ),
          ),
        ),
      );
      await _syncSeminarRunCardSnapshotNow(
        normalizedSessionId,
        _readSeminarRuntimeState(normalizedSessionId),
      );
      if (!mounted) return;
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _undoActiveSeminarRunCardConceptGraph(
    String? sessionId,
  ) async {
    final nodeId = _seminarSynthesisConceptNodeId(sessionId);
    if (nodeId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final removed = await ref.read(conceptGraphStoreProvider).removeDraftNode(
            nodeId,
          );
      if (!mounted) return;
      setState(() => _seminarCardConceptNodeIds.remove(nodeId));
      final normalizedSessionId = sessionId?.trim();
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            removed
                ? _localizedSeminarCardText(
                    zh: '已撤销图谱保存。',
                    en: 'Graph save undone.',
                  )
                : _localizedSeminarCardText(
                    zh: '这个图谱节点已确认或已不存在，不能撤销。',
                    en: 'This graph node was already confirmed or removed.',
                  ),
          ),
        ),
      );
      if (normalizedSessionId != null && normalizedSessionId.isNotEmpty) {
        if (removed) {
          await _recordSeminarRunCardArtifactActionsCurrentStateEvent(
            sessionId: normalizedSessionId,
            markerActionId: 'undo-concept-graph',
            text: _localizedSeminarCardText(
              zh: '已撤销图谱保存。',
              en: 'Graph save undone.',
            ),
          );
        }
        await _syncSeminarRunCardSnapshotNow(
          normalizedSessionId,
          _readSeminarRuntimeState(normalizedSessionId),
        );
        if (!mounted) return;
      }
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String _seminarConceptNodeLabel(String summary) {
    final normalized = summary.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length <= 80) return normalized;
    return '${normalized.substring(0, 77)}...';
  }

  List<SourceRef> _seminarSynthesisKnowledgeCardSourceRefs(
    AiSeminarRuntimeState runtimeState,
  ) {
    final synthesis = runtimeState.synthesis;
    if (synthesis == null || synthesis.summary.trim().isEmpty) {
      return const <SourceRef>[];
    }
    final evidenceById = <String, AiSeminarEvidence>{
      for (final evidence in synthesis.evidence)
        if (evidence.id.trim().isNotEmpty) evidence.id.trim(): evidence,
    };
    final refs = <SourceRef>[];
    final seen = <String>{};
    for (final id in synthesis.evidenceRefIds) {
      final evidence = evidenceById[id.trim()];
      if (evidence == null || !evidence.sourceRef.hasEvidence) continue;
      final key = evidence.sourceRef.sourceHash ??
          evidence.sourceRef.jumpLink ??
          '${evidence.sourceRef.bookId}:${evidence.sourceRef.href}:${evidence.sourceRef.cfi}:${evidence.sourceRef.chunkId}:${evidence.sourceRef.sourceTextSnippet}';
      if (!seen.add(key)) continue;
      refs.add(evidence.sourceRef);
    }
    return refs;
  }

  Widget _buildSeminarRunSnapshot(
    String? sessionId,
    AiSeminarRunCardSnapshot snapshot,
    AiSeminarRuntimeState runtimeState, {
    required int? bookId,
    required List<String> evidenceScopeIds,
  }) {
    final allEvidence = _seminarSnapshotEvidence(snapshot);
    final evidence = allEvidence;
    final toolCalls = _seminarSnapshotToolCalls(
      snapshot,
      bookId: bookId,
      evidenceScopeIds: evidenceScopeIds,
    );
    final roles = _seminarSnapshotRoleTurns(snapshot);
    final readerTurns = _seminarSnapshotReaderTurns(snapshot);
    final isLiveSession = runtimeState.session?.id == sessionId;
    final hasLiveReaderComposer = isLiveSession &&
        runtimeState.evidenceBundle != null &&
        (runtimeState.status == AiSeminarRunStatus.completed ||
            runtimeState.directorState?.needsUserInput == true);
    final readerComposers = _seminarSnapshotReaderComposers(snapshot)
        .where((_) => !hasLiveReaderComposer)
        .toList(growable: false);
    final hasLiveDirectorCue =
        isLiveSession && runtimeState.directorState?.needsUserInput == true;
    final directorCues = _seminarSnapshotDirectorCues(snapshot)
        .where((_) => !hasLiveDirectorCue)
        .toList(growable: false);
    final agentStatuses = _seminarSnapshotAgentStatuses(snapshot);
    final synthesis = _seminarSnapshotSynthesisSummary(snapshot);
    final synthesisEvidenceRefs =
        _seminarSnapshotSynthesisEvidenceRefs(snapshot);
    final disagreements = snapshot.disagreements
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final disagreementDetails = _seminarSnapshotDisagreementDetailsFromParts(
      snapshot,
    );
    final disagreementRebuttals =
        _seminarSnapshotDisagreementRebuttals(snapshot);
    final contradictionScans = _seminarSnapshotContradictionScans(snapshot);
    final disagreementDetailTexts = disagreementDetails
        .map((item) => item.text.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final legacyOnlyDisagreements = disagreements
        .where((item) => !disagreementDetailTexts.contains(item))
        .toList(growable: false);
    final disagreementTexts = <String>[
      ...disagreementDetailTexts,
      ...legacyOnlyDisagreements,
    ];
    final openQuestions = snapshot.openQuestions
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final liveRole = isLiveSession ? runtimeState.activeRole : null;
    final liveRoleText =
        isLiveSession ? runtimeState.partialRoleText?.trim() ?? '' : '';
    final hasLiveRole = liveRole != null && liveRoleText.isNotEmpty;
    final rolePartials = _seminarSnapshotRolePartials(snapshot)
        .where(
          (partial) =>
              !(hasLiveRole && partial.roleId.trim() == liveRole.asString),
        )
        .toList(growable: false);
    final hasRolePartial = rolePartials.isNotEmpty || hasLiveRole;
    final nativeTimelineSourceParts = _seminarSnapshotNativeTimelineParts(
      snapshot,
      bookId: bookId,
      evidenceScopeIds: evidenceScopeIds,
    ).toList(growable: false);
    final hasLegacySnapshotContent =
        _seminarSnapshotHasLegacySnapshotContent(snapshot);
    final reviewTriageParts = _seminarSnapshotReviewTriageParts(snapshot);
    final artifactActionParts = _seminarSnapshotArtifactActionParts(snapshot);
    final controlDirectorCues =
        _seminarSnapshotControlDirectorCues(directorCues);
    final hasStatus = directorCues.isNotEmpty && !hasLegacySnapshotContent;
    final hasControlParts = controlDirectorCues.isNotEmpty ||
        agentStatuses.isNotEmpty ||
        readerComposers.isNotEmpty ||
        readerTurns.isNotEmpty;
    final hasControls = hasControlParts && !hasLegacySnapshotContent;
    final snapshotThinkingParts = _seminarSnapshotThinkingParts(snapshot);
    final runtimeThinkingParts = isLiveSession
        ? _seminarRuntimeThinkingParts(runtimeState)
        : const <AiSeminarRunCardMessagePart>[];
    final thinkingParts = runtimeThinkingParts.isNotEmpty
        ? _mergeSeminarNativeTimelineParts(
            runtimeThinkingParts,
            snapshotThinkingParts,
          )
        : snapshotThinkingParts;
    final availableSubViews = _seminarSnapshotAvailableSubviews(
      toolCalls: toolCalls,
      evidence: evidence,
      roles: roles,
      hasLiveRole: hasRolePartial,
      synthesis: synthesis,
      hasStatus: hasStatus,
      hasThinking: thinkingParts.isNotEmpty,
      hasControls: hasControls,
      hasReviewTriage: reviewTriageParts.isNotEmpty,
      hasArtifactActions: artifactActionParts.isNotEmpty,
      disagreements: disagreementTexts,
      hasContradictionScans: contradictionScans.isNotEmpty,
      hasDisagreementRebuttals: disagreementRebuttals.isNotEmpty,
      openQuestions: openQuestions,
    );
    final selectedSubview = _seminarSnapshotSelectedSubview(
      sessionId,
      availableSubViews,
    );
    final showOverview = selectedSubview == _SeminarRunSnapshotSubview.overview;
    final showNativeTimeline = showOverview &&
        _seminarSnapshotShouldUseNativeTimeline(
          snapshot,
          nativeTimelineSourceParts,
          allowLegacySnapshotContent: true,
        );
    final useCompactNativeTimeline =
        showNativeTimeline && hasLegacySnapshotContent;
    final collapsedNativeTimelineParts = useCompactNativeTimeline
        ? _seminarSnapshotCompactNativeTimelineParts(nativeTimelineSourceParts)
        : _seminarSnapshotCollapsedNativeTimelineParts(
            nativeTimelineSourceParts,
          );
    final isNativeTimelineExpanded = sessionId != null &&
        _seminarCardTimelineExpandedSessionIds.contains(sessionId);
    final canToggleNativeTimelineExpansion = sessionId != null &&
        nativeTimelineSourceParts.length > collapsedNativeTimelineParts.length;
    final nativeTimelineParts = isNativeTimelineExpanded
        ? nativeTimelineSourceParts
        : collapsedNativeTimelineParts;
    final hiddenNativeTimelinePartCount =
        nativeTimelineSourceParts.length - nativeTimelineParts.length;
    final showStatus =
        selectedSubview == _SeminarRunSnapshotSubview.status && hasStatus;
    final showThinking = thinkingParts.isNotEmpty &&
        ((showOverview && !showNativeTimeline) ||
            selectedSubview == _SeminarRunSnapshotSubview.thinking);
    final showControls =
        selectedSubview == _SeminarRunSnapshotSubview.controls && hasControls;
    final showToolCalls = selectedSubview == _SeminarRunSnapshotSubview.tools;
    final showTimeline = showOverview &&
        !showNativeTimeline &&
        (roles.isNotEmpty || hasRolePartial);
    final showDirectorCues =
        showOverview && !showNativeTimeline && directorCues.isNotEmpty;
    final showAgentStatuses =
        showOverview && !showNativeTimeline && agentStatuses.isNotEmpty;
    final showReaderActivity = showOverview &&
        !showNativeTimeline &&
        (readerComposers.isNotEmpty || readerTurns.isNotEmpty);
    final showEvidence = (showOverview &&
            !showNativeTimeline &&
            synthesisEvidenceRefs.isEmpty) ||
        selectedSubview == _SeminarRunSnapshotSubview.evidence;
    final showRoles = selectedSubview == _SeminarRunSnapshotSubview.roles;
    final showSummary = (showOverview && !showNativeTimeline) ||
        selectedSubview == _SeminarRunSnapshotSubview.summary;
    final showArtifacts =
        selectedSubview == _SeminarRunSnapshotSubview.artifacts;
    final showReview = selectedSubview == _SeminarRunSnapshotSubview.review;
    final showWhiteboard = (showOverview && !showNativeTimeline) ||
        selectedSubview == _SeminarRunSnapshotSubview.whiteboard;
    final showDisagreements =
        selectedSubview == _SeminarRunSnapshotSubview.disagreements;
    final activeSynthesis = isLiveSession ? runtimeState.synthesis : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sessionId != null && availableSubViews.length > 1) ...[
          _seminarSnapshotSubviewTabs(
            sessionId: sessionId,
            subviews: availableSubViews,
            selected: selectedSubview,
          ),
          const SizedBox(height: 8),
        ],
        if (showNativeTimeline) ...[
          _seminarSnapshotNativeTimeline(
            nativeTimelineParts,
            sessionId: sessionId,
            bookId: bookId,
            hiddenPartCount: hiddenNativeTimelinePartCount,
            canToggleExpansion: canToggleNativeTimelineExpansion,
            isExpanded: isNativeTimelineExpanded,
            showInlineEvidence:
                !useCompactNativeTimeline || isNativeTimelineExpanded,
            showTraceDetails:
                !useCompactNativeTimeline || isNativeTimelineExpanded,
          ),
          if (showToolCalls && toolCalls.isNotEmpty) const SizedBox(height: 10),
        ],
        if (showStatus) ...[
          SeminarSnapshotHeading(
            Icons.pending_actions_outlined,
            _localizedSeminarCardText(
              zh: '状态详情',
              en: 'Status details',
            ),
          ),
          const SizedBox(height: 6),
          for (final cue in directorCues)
            _seminarSnapshotDirectorCueTile(cue, sessionId: sessionId),
          if (showToolCalls && toolCalls.isNotEmpty) const SizedBox(height: 10),
        ],
        if (showThinking && thinkingParts.isNotEmpty) ...[
          SeminarSnapshotHeading(
            Icons.psychology_outlined,
            selectedSubview == _SeminarRunSnapshotSubview.thinking
                ? _localizedSeminarCardText(
                    zh: '思考详情',
                    en: 'Thinking details',
                  )
                : _localizedSeminarCardText(
                    zh: '思考',
                    en: 'Thinking',
                  ),
          ),
          const SizedBox(height: 6),
          for (final part in thinkingParts)
            _seminarSnapshotNativeTimelinePart(
              part,
              sessionId: sessionId,
              bookId: bookId,
              showInlineEvidence: true,
              showTraceDetails: true,
              roleTurnNumber: null,
            ),
          if (showToolCalls && toolCalls.isNotEmpty) const SizedBox(height: 10),
        ],
        if (showControls) ...[
          SeminarSnapshotHeading(
            Icons.tune_outlined,
            _localizedSeminarCardText(
              zh: '控制详情',
              en: 'Control details',
            ),
          ),
          const SizedBox(height: 6),
          for (final cue in controlDirectorCues)
            _seminarSnapshotDirectorCueTile(cue, sessionId: sessionId),
          for (final status in agentStatuses)
            _seminarSnapshotAgentStatusTile(
              status,
              sessionId: sessionId,
              bookId: bookId,
            ),
          for (final composer in readerComposers)
            _seminarSnapshotReaderComposerTile(composer),
          for (final readerTurn in readerTurns)
            _seminarSnapshotReaderTurnTile(readerTurn),
          if (showToolCalls && toolCalls.isNotEmpty) const SizedBox(height: 10),
        ],
        if (showTimeline) ...[
          _seminarSnapshotDiscussionTimeline(
            roles,
            rolePartials: rolePartials,
            liveRole: liveRole,
            liveRoleText: liveRoleText,
          ),
          if ((showToolCalls && toolCalls.isNotEmpty) ||
              (showEvidence && evidence.isNotEmpty) ||
              showAgentStatuses ||
              showDirectorCues ||
              showReaderActivity ||
              (showSummary && synthesis != null && synthesis.isNotEmpty) ||
              disagreementTexts.isNotEmpty ||
              openQuestions.isNotEmpty)
            const SizedBox(height: 10),
        ],
        if (showDirectorCues) ...[
          SeminarSnapshotHeading(
            Icons.psychology_outlined,
            _localizedSeminarCardText(
              zh: '主持人下一步',
              en: 'Director next step',
            ),
          ),
          const SizedBox(height: 6),
          for (final cue in directorCues)
            _seminarSnapshotDirectorCueTile(cue, sessionId: sessionId),
          if ((showToolCalls && toolCalls.isNotEmpty) ||
              (showEvidence && evidence.isNotEmpty) ||
              showAgentStatuses ||
              showReaderActivity ||
              (showSummary && synthesis != null && synthesis.isNotEmpty) ||
              disagreementTexts.isNotEmpty ||
              openQuestions.isNotEmpty)
            const SizedBox(height: 10),
        ],
        if (showAgentStatuses) ...[
          SeminarSnapshotHeading(
            Icons.support_agent_outlined,
            _localizedSeminarCardText(
              zh: '角色状态',
              en: 'Role status',
            ),
          ),
          const SizedBox(height: 6),
          for (final status in agentStatuses)
            _seminarSnapshotAgentStatusTile(
              status,
              sessionId: sessionId,
              bookId: bookId,
            ),
          if ((showToolCalls && toolCalls.isNotEmpty) ||
              (showEvidence && evidence.isNotEmpty) ||
              showReaderActivity ||
              (showSummary && synthesis != null && synthesis.isNotEmpty) ||
              disagreementTexts.isNotEmpty ||
              openQuestions.isNotEmpty)
            const SizedBox(height: 10),
        ],
        if (showReaderActivity) ...[
          SeminarSnapshotHeading(
            Icons.person_outline,
            _localizedSeminarCardText(
              zh: '读者参与',
              en: 'Reader turns',
            ),
          ),
          const SizedBox(height: 6),
          for (final composer in readerComposers)
            _seminarSnapshotReaderComposerTile(composer),
          for (final readerTurn in readerTurns)
            _seminarSnapshotReaderTurnTile(readerTurn),
          if ((showToolCalls && toolCalls.isNotEmpty) ||
              (showEvidence && evidence.isNotEmpty) ||
              (showSummary && synthesis != null && synthesis.isNotEmpty) ||
              disagreementTexts.isNotEmpty ||
              openQuestions.isNotEmpty)
            const SizedBox(height: 10),
        ],
        if (showToolCalls && toolCalls.isNotEmpty) ...[
          SeminarSnapshotHeading(
            Icons.travel_explore_outlined,
            _localizedSeminarCardText(
              zh: '工具调用详情',
              en: 'Tool call details',
            ),
          ),
          const SizedBox(height: 6),
          for (final item in toolCalls)
            SeminarSnapshotToolCallTile(
              toolCall: item,
              label: _seminarToolCallLabel(item),
              statusLabel: _seminarToolCallStatusLabel(item),
              startedAtLabel: _seminarToolCallStartedAtLabel(item),
              completedAtLabel: _seminarToolCallCompletedAtLabel(item),
              durationLabel: _seminarToolCallDurationLabel(item),
              visibleRoleLabels: _seminarToolCallVisibleRoleLabel(item),
              outputLabel: _seminarToolCallOutputLabel(item),
              zh: _isChineseLocale,
              actionLabelBuilder: _seminarToolCallActionLabel,
              actionIconBuilder: _seminarToolCallActionIcon,
              actionEnabledBuilder: (actionId) =>
                  _seminarToolCallActionIsExecutable(
                item,
                actionId: actionId,
                sessionId: sessionId,
              ),
              actionPressedBuilder: (actionId) => _seminarToolCallActionPressed(
                item,
                actionId: actionId,
                sessionId: sessionId,
              ),
              isSubmitting: _seminarCardSubmittingSessionIds.contains(
                sessionId?.trim(),
              ),
              evidenceTileBuilder: (evidence) => SeminarSnapshotEvidenceTile(
                evidence,
                zh: _isChineseLocale,
                missingSourceLabel: _seminarMissingSourceLabel,
                sourceAction: _seminarSnapshotEvidenceSourceAction(
                  evidence.sourceRef,
                ),
              ),
            ),
        ],
        if (showEvidence && evidence.isNotEmpty) ...[
          if ((showToolCalls && toolCalls.isNotEmpty) || showReaderActivity)
            const SizedBox(height: 10),
          SeminarSnapshotHeading(
            Icons.fact_check_outlined,
            _localizedSeminarCardText(
              zh: '证据快照',
              en: 'Evidence snapshot',
            ),
          ),
          const SizedBox(height: 6),
          for (var index = 0; index < evidence.length; index++)
            SeminarSnapshotEvidenceTile(
              evidence[index],
              key: _seminarEvidenceTileKey(evidence[index]),
              zh: _isChineseLocale,
              missingSourceLabel: _seminarMissingSourceLabel,
              sourceAction: _seminarSnapshotEvidenceSourceAction(
                evidence[index].sourceRef,
              ),
              fallbackIndex: index + 1,
            ),
        ],
        if (showRoles && (roles.isNotEmpty || hasRolePartial)) ...[
          if ((showToolCalls && toolCalls.isNotEmpty) ||
              showReaderActivity ||
              (showEvidence && evidence.isNotEmpty))
            const SizedBox(height: 10),
          SeminarSnapshotHeading(
            Icons.forum_outlined,
            _localizedSeminarCardText(
              zh: '角色观点',
              en: 'Role views',
            ),
          ),
          const SizedBox(height: 6),
          if (hasLiveRole) _seminarSnapshotLiveRoleTile(liveRole, liveRoleText),
          for (final partial in rolePartials)
            _seminarSnapshotRolePartialTile(partial),
          for (final role in roles) _seminarSnapshotRoleTile(role),
        ],
        if (showSummary && synthesis != null && synthesis.isNotEmpty) ...[
          if ((showToolCalls && toolCalls.isNotEmpty) ||
              showReaderActivity ||
              (showEvidence && evidence.isNotEmpty) ||
              (showRoles && roles.isNotEmpty))
            const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SeminarSnapshotHeading(
                  Icons.auto_awesome_outlined,
                  _localizedSeminarCardText(
                    zh: '研讨总结',
                    en: 'Seminar summary',
                  ),
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (snapshot.disagreements.isNotEmpty ||
                      disagreementDetails.isNotEmpty)
                    SeminarSnapshotTinyChip(
                      _seminarCountLabel(
                        disagreementTexts.length,
                        zhUnit: '个分歧',
                        enSingular: 'disagreement',
                        enPlural: 'disagreements',
                      ),
                    ),
                  if (snapshot.openQuestions.isNotEmpty)
                    SeminarSnapshotTinyChip(
                      _seminarCountLabel(
                        snapshot.openQuestions.length,
                        zhUnit: '个问题',
                        enSingular: 'question',
                        enPlural: 'questions',
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          SeminarSnapshotExpandableText(
            synthesis,
            collapsedMaxLines: 4,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ClaudePalette.fg(context),
                  height: 1.35,
                ),
          ),
          SeminarSnapshotCompactEvidenceRows(
            evidenceRefs: synthesisEvidenceRefs,
            linkedEvidenceLabel: _seminarLinkedEvidenceLabel,
            missingSourceLabel: _seminarMissingSourceLabel,
            sourceActionBuilder: (evidence) =>
                _seminarSnapshotEvidenceSourceAction(evidence.sourceRef),
          ),
        ],
        if (showDisagreements &&
            (disagreementTexts.isNotEmpty ||
                contradictionScans.isNotEmpty ||
                disagreementRebuttals.isNotEmpty)) ...[
          SeminarSnapshotHeading(
            Icons.report_problem_outlined,
            _localizedSeminarCardText(
              zh: '分歧视图',
              en: 'Disagreements view',
            ),
          ),
          const SizedBox(height: 6),
          if (contradictionScans.isNotEmpty)
            _seminarSnapshotContradictionScanTiles(
              contradictionScans,
              sessionId: sessionId,
            ),
          if (contradictionScans.isNotEmpty &&
              (disagreementRebuttals.isNotEmpty ||
                  disagreementDetails.isNotEmpty ||
                  legacyOnlyDisagreements.isNotEmpty))
            const SizedBox(height: 6),
          if (disagreementRebuttals.isNotEmpty)
            _seminarSnapshotDisagreementRebuttalTiles(disagreementRebuttals),
          if (disagreementRebuttals.isNotEmpty &&
              (disagreementDetails.isNotEmpty ||
                  legacyOnlyDisagreements.isNotEmpty))
            const SizedBox(height: 6),
          if (disagreementDetails.isNotEmpty)
            _seminarSnapshotDisagreementDetails(disagreementDetails),
          if (legacyOnlyDisagreements.isNotEmpty)
            _seminarSnapshotWhiteboardGroup(
              icon: Icons.report_problem_outlined,
              label: _localizedSeminarCardText(
                zh: '分歧',
                en: 'Disagreements',
              ),
              items: legacyOnlyDisagreements,
            ),
        ],
        if (showReview) ...[
          _seminarSnapshotReviewPreview(
            synthesis: synthesis,
            evidenceCount: allEvidence.length,
            activeSynthesis: activeSynthesis,
            reviewTriageParts: reviewTriageParts,
          ),
        ],
        if (showArtifacts && artifactActionParts.isNotEmpty) ...[
          SeminarSnapshotHeading(
            Icons.inventory_2_outlined,
            _localizedSeminarCardText(
              zh: '沉淀动作详情',
              en: 'Artifact action details',
            ),
          ),
          const SizedBox(height: 6),
          for (final part in artifactActionParts)
            _seminarSnapshotArtifactActionsPartTile(part),
        ],
        if (showWhiteboard &&
            (disagreementTexts.isNotEmpty || openQuestions.isNotEmpty)) ...[
          if ((showToolCalls && toolCalls.isNotEmpty) ||
              showReaderActivity ||
              (showEvidence && evidence.isNotEmpty) ||
              (showRoles && roles.isNotEmpty) ||
              (showSummary && synthesis != null))
            const SizedBox(height: 10),
          _seminarSnapshotWhiteboardSection(
            disagreements: disagreementTexts,
            openQuestions: openQuestions,
          ),
        ],
      ],
    );
  }

  List<AiSeminarRunCardEvidenceSnapshot> _seminarSnapshotEvidence(
    AiSeminarRunCardSnapshot snapshot,
  ) {
    final partEvidence = snapshot.messageParts
        .where((part) => _isSeminarEvidenceBundlePartType(part.type))
        .expand((part) => part.evidenceRefs)
        .where((item) => !item.isEmpty)
        .toList(growable: false);
    if (partEvidence.isNotEmpty) {
      return _dedupeSeminarSnapshotEvidence(partEvidence);
    }
    final messagePartEvidence = snapshot.messageParts
        .expand((part) => part.evidenceRefs)
        .where((item) => !item.isEmpty)
        .toList(growable: false);
    if (messagePartEvidence.isNotEmpty) {
      return _dedupeSeminarSnapshotEvidence(messagePartEvidence);
    }
    return _dedupeSeminarSnapshotEvidence(
      snapshot.evidence.where((item) => !item.isEmpty),
    );
  }

  List<AiSeminarRunCardEvidenceSnapshot> _dedupeSeminarSnapshotEvidence(
    Iterable<AiSeminarRunCardEvidenceSnapshot> evidence,
  ) {
    final out = <AiSeminarRunCardEvidenceSnapshot>[];
    final seen = <String>{};
    for (final item in evidence) {
      if (item.isEmpty) continue;
      final key = _seminarSnapshotEvidenceKey(item);
      if (!seen.add(key)) continue;
      out.add(item);
    }
    return out.toList(growable: false);
  }

  String _seminarSnapshotEvidenceKey(
    AiSeminarRunCardEvidenceSnapshot evidence,
  ) {
    final id = evidence.id?.trim();
    if (id != null && id.isNotEmpty) return 'id:$id';
    final sourceRef = evidence.sourceRef;
    return [
      evidence.title.trim(),
      evidence.snippet.trim(),
      sourceRef?.bookId.toString() ?? '',
      sourceRef?.cfi ?? '',
      sourceRef?.sourceKind.asString ?? '',
      sourceRef?.sourceTextSnippet ?? '',
    ].join('|');
  }

  GlobalKey _seminarEvidenceTileKey(
    AiSeminarRunCardEvidenceSnapshot evidence,
  ) {
    final key = _seminarSnapshotEvidenceKey(evidence);
    return _seminarEvidenceTileKeys.putIfAbsent(key, GlobalKey.new);
  }

  void _jumpToSeminarEvidenceRow(
    AiSeminarRunCardEvidenceSnapshot evidence,
  ) {
    final key = _seminarEvidenceTileKeys[_seminarSnapshotEvidenceKey(evidence)];
    final targetContext = key?.currentContext;
    if (targetContext != null) {
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
      return;
    }
    final sourceRef = evidence.sourceRef;
    if (sourceRef?.hasEvidence == true) {
      _openSeminarEvidenceSource(sourceRef!);
      return;
    }
    showPaperReaderSourceUnavailable(
      context,
      sourceRef == null ? const <SourceRef>[] : [sourceRef],
      _localizedSeminarCardText(
        zh: '没有可跳转的证据条目。',
        en: 'No jumpable evidence item available.',
      ),
    );
  }

  List<AiSeminarRunCardMessagePart> _seminarSnapshotReviewTriageParts(
    AiSeminarRunCardSnapshot snapshot,
  ) {
    return snapshot.messageParts
        .where((part) => part.type.trim() == 'review_triage')
        .where(
          (part) =>
              part.label?.trim().isNotEmpty == true &&
              part.text?.trim().isNotEmpty == true,
        )
        .toList(growable: false);
  }

  List<AiSeminarRunCardMessagePart> _seminarSnapshotArtifactActionParts(
    AiSeminarRunCardSnapshot snapshot,
  ) {
    return snapshot.messageParts
        .where((part) => part.type.trim() == 'artifact_actions')
        .where(_seminarSnapshotNativeTimelinePartHasContent)
        .toList(growable: false);
  }

  List<AiSeminarRunCardMessagePart> _seminarSnapshotThinkingParts(
    AiSeminarRunCardSnapshot snapshot,
  ) {
    final streamingRunIds = {
      for (final part in snapshot.messageParts)
        if (part.type.trim() == 'role_partial') part.agentRunId?.trim() ?? '',
    }..remove('');
    return snapshot.messageParts
        .where((part) => part.type.trim() == 'thinking')
        .where(
          (part) => !streamingRunIds.contains(part.agentRunId?.trim() ?? ''),
        )
        .where(_seminarSnapshotNativeTimelinePartHasContent)
        .toList(growable: false);
  }

  List<AiSeminarRunCardMessagePart> _seminarRuntimeThinkingParts(
    AiSeminarRuntimeState state,
  ) {
    final out = <AiSeminarRunCardMessagePart>[];
    final directorThinking = _seminarDirectorThinkingPartFromState(state);
    if (directorThinking != null) out.add(directorThinking);
    final liveRoleThinking = _seminarLiveRoleAgentThinkingPartsFromState(state);
    out.addAll(liveRoleThinking);
    final activeRole = state.activeRole;
    final session = state.session;
    if (activeRole != null && session != null) {
      final activeRunId =
          '${session.id}:role-${activeRole.asString}-${state.turns.length}';
      final hasLiveThinkingForActiveRole = liveRoleThinking.any(
        (part) => part.agentRunId == activeRunId,
      );
      if (!hasLiveThinkingForActiveRole) {
        final activeThinking =
            _seminarActiveRoleThinkingMessagePartFromState(state);
        if (activeThinking != null) out.add(activeThinking);
      }
    }
    return out
        .where(_seminarSnapshotNativeTimelinePartHasContent)
        .toList(growable: false);
  }

  List<AiSeminarRunCardRoleSummary> _seminarSnapshotRoleTurns(
    AiSeminarRunCardSnapshot snapshot,
  ) {
    final partRoles = snapshot.messageParts
        .where((part) => part.type.trim() == 'role_turn')
        .map(
          (part) => AiSeminarRunCardRoleSummary(
            roleId: part.roleId ?? '',
            label: part.label ?? '',
            summary: part.text ?? '',
            evidenceRefs: part.evidenceRefs,
          ),
        )
        .where((role) => !role.isEmpty)
        .toList(growable: false);
    if (partRoles.isNotEmpty) return partRoles;
    return snapshot.roleSummaries
        .where((role) => !role.isEmpty)
        .toList(growable: false);
  }

  List<AiSeminarRunCardMessagePart> _seminarSnapshotReaderTurns(
    AiSeminarRunCardSnapshot snapshot,
  ) {
    return snapshot.messageParts
        .where((part) => part.type.trim() == 'reader_turn')
        .where(_seminarSnapshotReaderTurnHasContent)
        .toList(growable: false);
  }

  bool _seminarSnapshotReaderTurnHasContent(
    AiSeminarRunCardMessagePart part,
  ) {
    return part.label?.trim().isNotEmpty == true ||
        part.status?.trim().isNotEmpty == true ||
        part.text?.trim().isNotEmpty == true ||
        part.roleId?.trim().isNotEmpty == true ||
        part.agentRunId?.trim().isNotEmpty == true ||
        part.actionIds.where((item) => item.trim().isNotEmpty).isNotEmpty ||
        part.evidenceRefs.where((item) => !item.isEmpty).isNotEmpty;
  }

  List<AiSeminarRunCardMessagePart> _seminarSnapshotReaderComposers(
    AiSeminarRunCardSnapshot snapshot,
  ) {
    return snapshot.messageParts
        .where((part) => part.type.trim() == 'reader_composer')
        .where(
          (part) =>
              part.actionIds
                  .where((item) => item.trim().isNotEmpty)
                  .isNotEmpty ||
              part.roleIds.where((item) => item.trim().isNotEmpty).isNotEmpty ||
              part.text?.trim().isNotEmpty == true,
        )
        .toList(growable: false);
  }

  List<AiSeminarRunCardMessagePart> _seminarSnapshotDirectorCues(
    AiSeminarRunCardSnapshot snapshot,
  ) {
    return snapshot.messageParts
        .where((part) => part.type.trim() == 'director_state')
        .where(
          (part) =>
              part.label?.trim().isNotEmpty == true ||
              part.text?.trim().isNotEmpty == true,
        )
        .toList(growable: false);
  }

  List<AiSeminarRunCardMessagePart> _seminarSnapshotControlDirectorCues(
    List<AiSeminarRunCardMessagePart> directorCues,
  ) {
    return directorCues
        .where(
          (part) => part.actionIds.any(
            (actionId) =>
                _seminarAgentControlActionLabel(actionId.trim()).isNotEmpty,
          ),
        )
        .toList(growable: false);
  }

  List<AiSeminarRunCardMessagePart> _seminarSnapshotAgentStatuses(
    AiSeminarRunCardSnapshot snapshot,
  ) {
    return snapshot.messageParts
        .where((part) => part.type.trim() == 'agent_status')
        .where(
          (part) =>
              part.label?.trim().isNotEmpty == true ||
              part.text?.trim().isNotEmpty == true ||
              part.actionIds.where((item) => item.trim().isNotEmpty).isNotEmpty,
        )
        .toList(growable: false);
  }

  List<AiSeminarRunCardRoleSummary> _seminarSnapshotRolePartials(
    AiSeminarRunCardSnapshot snapshot,
  ) {
    return snapshot.messageParts
        .where((part) => part.type.trim() == 'role_partial')
        .map(
          (part) => AiSeminarRunCardRoleSummary(
            roleId: part.roleId ?? '',
            label: part.label ?? '',
            summary: part.text ?? '',
            evidenceRefs: part.evidenceRefs,
          ),
        )
        .where((role) => !role.isEmpty)
        .toList(growable: false);
  }

  List<AiSeminarRunCardToolCallSnapshot> _seminarSnapshotToolCalls(
    AiSeminarRunCardSnapshot snapshot, {
    required int? bookId,
    required List<String> evidenceScopeIds,
  }) {
    final partToolCalls = snapshot.messageParts
        .where((part) => part.type.trim() == 'tool_call')
        .where(
          (part) => _seminarSnapshotMessagePartVisibleInContext(
            part,
            bookId: bookId,
            evidenceScopeIds: evidenceScopeIds,
          ),
        )
        .map(
          (part) => AiSeminarRunCardToolCallSnapshot(
            id: part.id,
            agentRunId: part.agentRunId,
            parentRunId: part.parentRunId,
            toolId: part.toolId ?? '',
            status: part.status,
            label: part.label,
            text: part.text,
            query: part.query ?? '',
            resultCount: part.resultCount,
            startedAt: part.startedAt,
            completedAt: part.completedAt,
            roleIds: part.roleIds,
            actionIds: part.actionIds,
            evidenceRefs: part.evidenceRefs,
          ),
        )
        .where((toolCall) => !toolCall.isEmpty)
        .toList(growable: false);
    if (partToolCalls.isNotEmpty) return partToolCalls;
    return snapshot.toolCalls
        .where(
          (toolCall) => _seminarToolCallVisibleInContext(
            toolId: toolCall.toolId,
            agentRunId: toolCall.agentRunId,
            bookId: bookId,
            evidenceScopeIds: evidenceScopeIds,
          ),
        )
        .where((toolCall) => !toolCall.isEmpty)
        .toList(growable: false);
  }

  String? _seminarSnapshotSynthesisSummary(
    AiSeminarRunCardSnapshot snapshot,
  ) {
    final partSynthesis = snapshot.messageParts
        .where((part) => part.type.trim() == 'synthesis')
        .map((part) => part.text?.trim() ?? '')
        .firstWhere((text) => text.isNotEmpty, orElse: () => '');
    if (partSynthesis.isNotEmpty) return partSynthesis;
    final legacy = snapshot.synthesisSummary?.trim();
    if (legacy == null || legacy.isEmpty) return null;
    return legacy;
  }

  List<AiSeminarRunCardEvidenceSnapshot> _seminarSnapshotSynthesisEvidenceRefs(
    AiSeminarRunCardSnapshot snapshot,
  ) {
    for (final part in snapshot.messageParts) {
      if (part.type.trim() != 'synthesis') continue;
      final evidenceRefs = part.evidenceRefs
          .where((item) => !item.isEmpty)
          .toList(growable: false);
      if (evidenceRefs.isNotEmpty) return evidenceRefs;
    }
    return const <AiSeminarRunCardEvidenceSnapshot>[];
  }

  List<AiSeminarRunCardDisagreementDetail>
      _seminarSnapshotDisagreementDetailsFromParts(
    AiSeminarRunCardSnapshot snapshot,
  ) {
    final partDisagreements = snapshot.messageParts
        .where((part) => part.type.trim() == 'disagreement')
        .map(
          (part) => AiSeminarRunCardDisagreementDetail(
            text: part.text ?? '',
            agentRunId: part.agentRunId,
            parentRunId: part.parentRunId,
            roleIds: part.roleIds,
            evidenceRefs: part.evidenceRefs,
          ),
        )
        .where((detail) => !detail.isEmpty)
        .toList(growable: false);
    if (partDisagreements.isNotEmpty) return partDisagreements;
    return snapshot.disagreementDetails
        .where((detail) => !detail.isEmpty)
        .toList(growable: false);
  }

  List<AiSeminarRunCardMessagePart> _seminarSnapshotDisagreementRebuttals(
    AiSeminarRunCardSnapshot snapshot,
  ) {
    return snapshot.messageParts
        .where((part) => part.type.trim() == 'disagreement_rebuttal')
        .where(
          (part) =>
              part.text?.trim().isNotEmpty == true ||
              part.label?.trim().isNotEmpty == true,
        )
        .toList(growable: false);
  }

  List<AiSeminarRunCardMessagePart> _seminarSnapshotContradictionScans(
    AiSeminarRunCardSnapshot snapshot,
  ) {
    final parts = snapshot.messageParts
        .where((part) => part.type.trim() == 'contradiction_scan')
        .where(
          (part) =>
              part.text?.trim().isNotEmpty == true ||
              part.label?.trim().isNotEmpty == true,
        )
        .toList(growable: false);
    return _seminarPrioritizedContradictionScanParts(parts);
  }

  List<AiSeminarRunCardMessagePart> _seminarPrioritizedContradictionScanParts(
    List<AiSeminarRunCardMessagePart> parts,
  ) {
    final indexedParts = <MapEntry<int, AiSeminarRunCardMessagePart>>[];
    for (var index = 0; index < parts.length; index += 1) {
      indexedParts.add(MapEntry(index, parts[index]));
    }
    indexedParts.sort((left, right) {
      final priority = _seminarContradictionScanPriority(
        left.value,
      ).compareTo(_seminarContradictionScanPriority(right.value));
      if (priority != 0) return priority;
      return left.key.compareTo(right.key);
    });
    return indexedParts.map((entry) => entry.value).toList(growable: false);
  }

  int _seminarContradictionScanPriority(
    AiSeminarRunCardMessagePart part,
  ) {
    return part.label?.trim() == 'evidence-gap' ? 0 : 1;
  }

  List<_SeminarRunSnapshotSubview> _seminarSnapshotAvailableSubviews({
    required List<AiSeminarRunCardToolCallSnapshot> toolCalls,
    required List<AiSeminarRunCardEvidenceSnapshot> evidence,
    required List<AiSeminarRunCardRoleSummary> roles,
    required bool hasLiveRole,
    required String? synthesis,
    required bool hasStatus,
    required bool hasThinking,
    required bool hasControls,
    required bool hasReviewTriage,
    required bool hasArtifactActions,
    required List<String> disagreements,
    required bool hasContradictionScans,
    required bool hasDisagreementRebuttals,
    required List<String> openQuestions,
  }) {
    return [
      _SeminarRunSnapshotSubview.overview,
      if (hasStatus) _SeminarRunSnapshotSubview.status,
      if (hasThinking) _SeminarRunSnapshotSubview.thinking,
      if (hasControls) _SeminarRunSnapshotSubview.controls,
      if (toolCalls.isNotEmpty) _SeminarRunSnapshotSubview.tools,
      if (evidence.isNotEmpty) _SeminarRunSnapshotSubview.evidence,
      if (roles.isNotEmpty || hasLiveRole) _SeminarRunSnapshotSubview.roles,
      if (disagreements.isNotEmpty ||
          hasContradictionScans ||
          hasDisagreementRebuttals)
        _SeminarRunSnapshotSubview.disagreements,
      if (disagreements.isNotEmpty || openQuestions.isNotEmpty)
        _SeminarRunSnapshotSubview.whiteboard,
      if (synthesis != null && synthesis.isNotEmpty)
        _SeminarRunSnapshotSubview.summary,
      if (hasArtifactActions) _SeminarRunSnapshotSubview.artifacts,
      if ((synthesis != null && synthesis.isNotEmpty) ||
          evidence.isNotEmpty ||
          hasReviewTriage)
        _SeminarRunSnapshotSubview.review,
    ];
  }

  _SeminarRunSnapshotSubview _seminarSnapshotSelectedSubview(
    String? sessionId,
    List<_SeminarRunSnapshotSubview> available,
  ) {
    final selected =
        sessionId == null ? null : _seminarCardSnapshotSubviews[sessionId];
    if (selected != null && available.contains(selected)) return selected;
    return _SeminarRunSnapshotSubview.overview;
  }

  Widget _seminarSnapshotSubviewTabs({
    required String sessionId,
    required List<_SeminarRunSnapshotSubview> subviews,
    required _SeminarRunSnapshotSubview selected,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final subview in subviews) ...[
            ChoiceChip(
              key: ValueKey(
                'seminar-chat-card-snapshot-tab-${subview.id}-$sessionId',
              ),
              label: Text(_seminarSnapshotSubviewLabel(subview)),
              selected: selected == subview,
              onSelected: (_) {
                setState(() {
                  _seminarCardSnapshotSubviews[sessionId] = subview;
                });
              },
            ),
            if (subview != subviews.last) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  String _seminarSnapshotSubviewLabel(_SeminarRunSnapshotSubview subview) {
    switch (subview) {
      case _SeminarRunSnapshotSubview.overview:
        return _localizedSeminarCardText(zh: '全部', en: 'All');
      case _SeminarRunSnapshotSubview.status:
        return _localizedSeminarCardText(zh: '状态', en: 'Status');
      case _SeminarRunSnapshotSubview.thinking:
        return _localizedSeminarCardText(zh: '思考', en: 'Thinking');
      case _SeminarRunSnapshotSubview.controls:
        return _localizedSeminarCardText(zh: '控制', en: 'Controls');
      case _SeminarRunSnapshotSubview.tools:
        return _localizedSeminarCardText(zh: '调用', en: 'Calls');
      case _SeminarRunSnapshotSubview.evidence:
        return _localizedSeminarCardText(zh: '证据', en: 'Evidence');
      case _SeminarRunSnapshotSubview.roles:
        return _localizedSeminarCardText(zh: '角色', en: 'Roles');
      case _SeminarRunSnapshotSubview.disagreements:
        return _localizedSeminarCardText(zh: '分歧', en: 'Disputes');
      case _SeminarRunSnapshotSubview.whiteboard:
        return _localizedSeminarCardText(zh: '白板', en: 'Whiteboard');
      case _SeminarRunSnapshotSubview.summary:
        return _localizedSeminarCardText(zh: '总结', en: 'Summary');
      case _SeminarRunSnapshotSubview.artifacts:
        return _localizedSeminarCardText(zh: '沉淀', en: 'Assets');
      case _SeminarRunSnapshotSubview.review:
        return _localizedSeminarCardText(zh: '异常', en: 'Triage');
    }
  }

  List<AiSeminarRunCardMessagePart> _seminarSnapshotNativeTimelineParts(
    AiSeminarRunCardSnapshot snapshot, {
    required int? bookId,
    required List<String> evidenceScopeIds,
  }) {
    final explicitParts = [
      ...snapshot.messageParts.where((part) => part.type.trim() != 'thinking'),
      ..._seminarSnapshotThinkingParts(snapshot),
    ]
        .where(_seminarSnapshotNativeTimelinePartHasContent)
        .where(
          (part) => _seminarSnapshotMessagePartVisibleInContext(
            part,
            bookId: bookId,
            evidenceScopeIds: evidenceScopeIds,
          ),
        )
        .toList(growable: false);
    final legacyParts = _seminarSnapshotNativeTimelinePartsFromLegacy(snapshot)
        .where(_seminarSnapshotNativeTimelinePartHasContent)
        .where(
          (part) => _seminarSnapshotMessagePartVisibleInContext(
            part,
            bookId: bookId,
            evidenceScopeIds: evidenceScopeIds,
          ),
        )
        .toList(growable: false);
    if (explicitParts.isEmpty) return legacyParts;
    if (legacyParts.isEmpty) return explicitParts;
    return _mergeSeminarNativeTimelineParts(explicitParts, legacyParts);
  }

  List<AiSeminarRunCardMessagePart> _mergeSeminarNativeTimelineParts(
    List<AiSeminarRunCardMessagePart> explicitParts,
    List<AiSeminarRunCardMessagePart> legacyParts,
  ) {
    final out = explicitParts.toList(growable: true);
    final seen =
        explicitParts.map(_seminarNativeTimelinePartContentKey).toSet();
    for (final part in legacyParts) {
      if (!seen.add(_seminarNativeTimelinePartContentKey(part))) continue;
      out.add(part);
    }
    return out.toList(growable: false);
  }

  String _seminarNativeTimelinePartContentKey(
    AiSeminarRunCardMessagePart part,
  ) {
    final evidenceKey = part.evidenceRefs
        .map(
          (ref) => [
            ref.id?.trim() ?? '',
            ref.title.trim(),
            ref.snippet.trim(),
            ref.sourceRef?.jumpLink?.trim() ?? '',
          ].join(':'),
        )
        .join('|');
    return [
      part.type.trim(),
      part.roleId?.trim() ?? '',
      part.toolId?.trim() ?? '',
      part.query?.trim() ?? '',
      part.text?.trim() ?? '',
      evidenceKey,
    ].join('\u0001');
  }

  List<AiSeminarRunCardMessagePart>
      _seminarSnapshotNativeTimelinePartsFromLegacy(
    AiSeminarRunCardSnapshot snapshot,
  ) {
    final parts = <AiSeminarRunCardMessagePart>[];
    for (final toolCall
        in snapshot.toolCalls.where((toolCall) => !toolCall.isEmpty)) {
      parts.add(
        AiSeminarRunCardMessagePart(
          type: 'tool_call',
          id: toolCall.id,
          agentRunId: toolCall.agentRunId,
          parentRunId: toolCall.parentRunId,
          toolId: toolCall.toolId,
          status: toolCall.status,
          label: toolCall.label,
          text: toolCall.text,
          query: toolCall.query,
          resultCount: toolCall.resultCount,
          roleIds: toolCall.roleIds,
          actionIds: toolCall.actionIds,
          evidenceRefs: toolCall.evidenceRefs,
        ),
      );
    }
    final evidence = snapshot.evidence
        .where((item) => !item.isEmpty)
        .toList(growable: false);
    if (evidence.isNotEmpty) {
      parts.add(
        AiSeminarRunCardMessagePart(
          type: 'evidence',
          id: 'legacy-evidence',
          label: _localizedSeminarCardText(
            zh: '证据快照',
            en: 'Evidence snapshot',
          ),
          evidenceRefs: evidence,
        ),
      );
    }
    for (final role in snapshot.roleSummaries.where((role) => !role.isEmpty)) {
      parts.add(
        AiSeminarRunCardMessagePart(
          type: 'role_turn',
          roleId: role.roleId,
          label: role.label,
          text: role.summary,
          evidenceRefs: role.evidenceRefs,
        ),
      );
    }
    final synthesis = snapshot.synthesisSummary?.trim();
    if (synthesis != null && synthesis.isNotEmpty) {
      parts.add(
        AiSeminarRunCardMessagePart(
          type: 'synthesis',
          id: 'legacy-synthesis',
          text: synthesis,
          evidenceRefs: evidence,
        ),
      );
    }
    final seenDisagreements = <String>{};
    var disagreementIndex = 0;
    for (final detail
        in snapshot.disagreementDetails.where((detail) => !detail.isEmpty)) {
      final text = detail.text.trim();
      final key = text.toLowerCase();
      if (text.isEmpty || !seenDisagreements.add(key)) continue;
      disagreementIndex += 1;
      parts.add(
        AiSeminarRunCardMessagePart(
          type: 'disagreement',
          id: 'legacy-disagreement-$disagreementIndex',
          text: text,
          roleIds: detail.roleIds,
          evidenceRefs: detail.evidenceRefs,
        ),
      );
    }
    for (final rawDisagreement in snapshot.disagreements) {
      final text = rawDisagreement.trim();
      final key = text.toLowerCase();
      if (text.isEmpty || !seenDisagreements.add(key)) continue;
      disagreementIndex += 1;
      parts.add(
        AiSeminarRunCardMessagePart(
          type: 'disagreement',
          id: 'legacy-disagreement-$disagreementIndex',
          text: text,
        ),
      );
    }
    var questionIndex = 0;
    for (final rawQuestion in snapshot.openQuestions) {
      final question = rawQuestion.trim();
      if (question.isEmpty) continue;
      questionIndex += 1;
      parts.add(
        AiSeminarRunCardMessagePart(
          type: 'director_state',
          id: 'legacy-open-question-$questionIndex',
          label: 'ask-user',
          text: question,
        ),
      );
    }
    return parts;
  }

  List<AiSeminarRunCardMessagePart> _seminarSnapshotCompactNativeTimelineParts(
    List<AiSeminarRunCardMessagePart> parts,
  ) {
    final visibleTypes = parts
        .map((part) => part.type.trim())
        .where((type) => type.isNotEmpty)
        .toSet();
    final nonSetupContentTypes = visibleTypes
        .where((type) => type != 'seminar_run_setup' && type != 'thinking')
        .toSet();
    if (nonSetupContentTypes.length <= 1) {
      return parts.take(12).toList(growable: false);
    }
    final selectedIndexes = <int>{};

    void addType(String type, {int count = 1}) {
      var added = 0;
      for (var index = 0; index < parts.length && added < count; index += 1) {
        final partType = parts[index].type.trim();
        if (type == 'evidence') {
          if (!_isSeminarEvidenceBundlePartType(partType)) continue;
        } else if (partType != type) {
          continue;
        }
        selectedIndexes.add(index);
        added += 1;
      }
    }

    void addLastType(String type) {
      for (var index = parts.length - 1; index >= 0; index -= 1) {
        if (parts[index].type.trim() != type) continue;
        selectedIndexes.add(index);
        return;
      }
    }

    final hasReaderTurn =
        parts.any((part) => part.type.trim() == 'reader_turn');
    final hasReaderComposer =
        parts.any((part) => part.type.trim() == 'reader_composer');
    final hasArtifactActions =
        parts.any((part) => part.type.trim() == 'artifact_actions');

    addType('seminar_run_setup');
    addType('tool_call');
    addLastType('thinking');
    if (!hasReaderTurn) addType('evidence');
    if (!hasReaderComposer) addType('director_state');
    addType('agent_status');
    addType('role_turn');
    addType('role_partial');
    if (hasReaderTurn) addType('reader_turn');
    addLastType('role_turn');
    addType('synthesis');
    addType('artifact_actions');
    if (!hasArtifactActions) addType('review_triage');
    if (selectedIndexes.length < 5) addType('evidence');
    if (!hasReaderComposer && selectedIndexes.length < 5) {
      addType('director_state');
    }
    if (selectedIndexes.length < 5) addType('agent_status');
    if (selectedIndexes.length < 5) addType('disagreement');
    if (selectedIndexes.length < 5) addType('contradiction_scan');
    if (selectedIndexes.length < 5) addType('review_triage');

    int? firstSelectedIndexOfType(String type) {
      for (var index = 0; index < parts.length; index += 1) {
        if (!selectedIndexes.contains(index)) continue;
        if (parts[index].type.trim() == type) return index;
      }
      return null;
    }

    int? lastSelectedIndexOfType(String type) {
      for (var index = parts.length - 1; index >= 0; index -= 1) {
        if (!selectedIndexes.contains(index)) continue;
        if (parts[index].type.trim() == type) return index;
      }
      return null;
    }

    final protectedIndexes = <int>{};
    void protectType(String type) {
      final index = firstSelectedIndexOfType(type);
      if (index != null) protectedIndexes.add(index);
    }

    void protectLastType(String type) {
      final index = lastSelectedIndexOfType(type);
      if (index != null) protectedIndexes.add(index);
    }

    protectType('seminar_run_setup');
    protectType('tool_call');
    protectLastType('thinking');
    protectType('agent_status');
    final hasSelectedRoleTurn = firstSelectedIndexOfType('role_turn') != null;
    final hasSelectedSynthesis = firstSelectedIndexOfType('synthesis') != null;
    if (hasReaderTurn) {
      protectedIndexes.removeWhere(
        (index) => parts[index].type.trim() == 'seminar_run_setup',
      );
      protectType('reader_turn');
      protectLastType('role_turn');
    } else if (hasReaderComposer &&
        !hasSelectedRoleTurn &&
        !hasSelectedSynthesis) {
      protectType('reader_composer');
    } else {
      protectType('role_turn');
      if (!protectedIndexes
          .any((index) => parts[index].type.trim() == 'role_turn')) {
        protectType('role_partial');
      }
    }
    protectType('synthesis');
    protectType('artifact_actions');
    if (!hasArtifactActions) protectType('review_triage');
    if (firstSelectedIndexOfType('artifact_actions') != null ||
        (!hasArtifactActions &&
            firstSelectedIndexOfType('review_triage') != null)) {
      protectedIndexes.removeWhere(
        (index) => parts[index].type.trim() == 'seminar_run_setup',
      );
    }

    while (selectedIndexes.length > 5) {
      final removableIndex = selectedIndexes.toList().reversed.firstWhere(
            (index) => !protectedIndexes.contains(index),
            orElse: () => -1,
          );
      if (removableIndex < 0) break;
      selectedIndexes.remove(removableIndex);
    }

    final indexes = selectedIndexes.toList()..sort();
    return indexes.map((index) => parts[index]).take(5).toList(growable: false);
  }

  List<AiSeminarRunCardMessagePart>
      _seminarSnapshotCollapsedNativeTimelineParts(
    List<AiSeminarRunCardMessagePart> parts,
  ) {
    if (parts.length <= 12) return parts.toList(growable: false);
    final collapsed = parts.take(12).toList(growable: true);
    final protectedLateParts = <AiSeminarRunCardMessagePart>[];

    void addProtectedLateParts(
      bool Function(AiSeminarRunCardMessagePart part) matches, {
      int count = 1,
    }) {
      var added = 0;
      for (final part in parts.skip(12)) {
        if (!matches(part)) continue;
        final key = _seminarNativeTimelinePartContentKey(part);
        final alreadyVisible = collapsed.any(
                (item) => _seminarNativeTimelinePartContentKey(item) == key) ||
            protectedLateParts.any(
                (item) => _seminarNativeTimelinePartContentKey(item) == key);
        if (alreadyVisible) continue;
        protectedLateParts.add(part);
        added += 1;
        if (added >= count) return;
      }
    }

    if (!collapsed.any((part) => part.type.trim() == 'artifact_actions')) {
      addProtectedLateParts(
        (part) => part.type.trim() == 'artifact_actions',
      );
    }
    if (!collapsed.any((part) => part.type.trim() == 'thinking')) {
      addProtectedLateParts(
        (part) => part.type.trim() == 'thinking',
      );
    }
    if (!collapsed.any((part) => part.type.trim() == 'review_triage')) {
      addProtectedLateParts(
        (part) {
          if (part.type.trim() != 'review_triage') return false;
          final label = part.label?.trim();
          return label == 'risk' || label == 'suggested-action';
        },
        count: 2,
      );
      if (!protectedLateParts.any(
        (part) => part.type.trim() == 'review_triage',
      )) {
        addProtectedLateParts(
          (part) => part.type.trim() == 'review_triage',
        );
      }
    }

    if (protectedLateParts.isNotEmpty) {
      final replaceCount = protectedLateParts.length.clamp(0, collapsed.length);
      final start = collapsed.length - replaceCount;
      for (var index = 0; index < replaceCount; index += 1) {
        collapsed[start + index] = protectedLateParts[index];
      }
    }
    return collapsed.toList(growable: false);
  }

  bool _seminarSnapshotShouldUseNativeTimeline(
    AiSeminarRunCardSnapshot snapshot,
    List<AiSeminarRunCardMessagePart> parts, {
    bool allowLegacySnapshotContent = false,
  }) {
    if (parts.isEmpty) return false;
    final hasLegacySnapshotContent =
        _seminarSnapshotHasLegacySnapshotContent(snapshot);
    if (!hasLegacySnapshotContent) return true;
    if (_seminarSnapshotHasExplicitLifecycleControlParts(snapshot)) {
      return false;
    }
    return allowLegacySnapshotContent &&
        _seminarSnapshotNativeTimelineCoversLegacyContent(snapshot, parts);
  }

  bool _seminarSnapshotHasExplicitLifecycleControlParts(
    AiSeminarRunCardSnapshot snapshot,
  ) {
    final legacyOpenQuestions = snapshot.openQuestions
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    return snapshot.messageParts.any((part) {
      switch (part.type.trim()) {
        case 'agent_status':
          return true;
        case 'reader_turn':
          return !_seminarSnapshotIsNativeToolControlReaderTurn(part);
        case 'reader_composer':
        case 'director_state':
          return !_seminarSnapshotIsLegacyOpenQuestionPromptPart(
            part,
            legacyOpenQuestions,
          );
        default:
          return false;
      }
    });
  }

  bool _seminarSnapshotIsNativeToolControlReaderTurn(
    AiSeminarRunCardMessagePart part,
  ) {
    if (part.type.trim() != 'reader_turn') return false;
    final label = part.label?.trim();
    if (label != 'wait-tool-call' && label != 'cancel-tool-call') {
      return false;
    }
    return part.toolId?.trim().isNotEmpty == true ||
        part.query?.trim().isNotEmpty == true;
  }

  bool _seminarSnapshotIsLegacyOpenQuestionPromptPart(
    AiSeminarRunCardMessagePart part,
    Set<String> legacyOpenQuestions,
  ) {
    if (legacyOpenQuestions.isEmpty) return false;
    final type = part.type.trim();
    if (type != 'director_state' && type != 'reader_composer') return false;
    if (part.label?.trim() != 'ask-user') return false;
    final text = part.text?.trim();
    return text != null && legacyOpenQuestions.contains(text);
  }

  bool _seminarSnapshotHasLegacySnapshotContent(
    AiSeminarRunCardSnapshot snapshot,
  ) {
    return snapshot.evidence.where((item) => !item.isEmpty).isNotEmpty ||
        snapshot.toolCalls.where((item) => !item.isEmpty).isNotEmpty ||
        snapshot.roleSummaries.where((item) => !item.isEmpty).isNotEmpty ||
        snapshot.synthesisSummary?.trim().isNotEmpty == true ||
        snapshot.disagreements
            .where((item) => item.trim().isNotEmpty)
            .isNotEmpty ||
        snapshot.disagreementDetails
            .where((item) => !item.isEmpty)
            .isNotEmpty ||
        snapshot.openQuestions
            .where((item) => item.trim().isNotEmpty)
            .isNotEmpty;
  }

  bool _seminarSnapshotNativeTimelineCoversLegacyContent(
    AiSeminarRunCardSnapshot snapshot,
    List<AiSeminarRunCardMessagePart> parts,
  ) {
    final types = parts
        .map((part) => part.type.trim())
        .where((type) => type.isNotEmpty)
        .toSet();
    final hasLegacyToolCalls =
        snapshot.toolCalls.where((item) => !item.isEmpty).isNotEmpty;
    final hasLegacyEvidence =
        snapshot.evidence.where((item) => !item.isEmpty).isNotEmpty;
    final hasLegacyRoles =
        snapshot.roleSummaries.where((item) => !item.isEmpty).isNotEmpty;
    final hasLegacySynthesis =
        snapshot.synthesisSummary?.trim().isNotEmpty == true;
    final hasLegacyDisagreements = snapshot.disagreements
            .where((item) => item.trim().isNotEmpty)
            .isNotEmpty ||
        snapshot.disagreementDetails.where((item) => !item.isEmpty).isNotEmpty;
    final hasLegacyOpenQuestions = snapshot.openQuestions
        .where((item) => item.trim().isNotEmpty)
        .isNotEmpty;
    if (hasLegacyToolCalls && !types.contains('tool_call')) return false;
    if (hasLegacyEvidence && !types.contains('evidence')) return false;
    if (hasLegacyRoles && !types.contains('role_turn')) return false;
    if (hasLegacySynthesis && !types.contains('synthesis')) return false;
    if (hasLegacyDisagreements &&
        !types.contains('disagreement') &&
        !types.contains('contradiction_scan')) {
      return false;
    }
    if (hasLegacyOpenQuestions &&
        !types.contains('director_state') &&
        !types.contains('reader_composer')) {
      return false;
    }
    return true;
  }

  bool _seminarSnapshotNativeTimelinePartHasContent(
    AiSeminarRunCardMessagePart part,
  ) {
    switch (part.type.trim()) {
      case 'tool_call':
        return !_seminarSnapshotToolCallFromPart(part).isEmpty;
      case 'evidence':
      case 'evidence_bundle':
        return part.evidenceRefs.where((item) => !item.isEmpty).isNotEmpty;
      case 'seminar_run_setup':
        return part.text?.trim().isNotEmpty == true ||
            part.label?.trim().isNotEmpty == true ||
            part.roleIds.where((item) => item.trim().isNotEmpty).isNotEmpty;
      case 'role_turn':
      case 'role_partial':
        return !_seminarSnapshotRoleFromPart(part).isEmpty;
      case 'agent_status':
      case 'director_state':
        return part.label?.trim().isNotEmpty == true ||
            part.text?.trim().isNotEmpty == true ||
            part.actionIds.where((item) => item.trim().isNotEmpty).isNotEmpty;
      case 'thinking':
      case 'reader_turn':
      case 'reader_composer':
      case 'synthesis':
      case 'disagreement':
      case 'contradiction_scan':
      case 'disagreement_rebuttal':
      case 'review_triage':
      case 'artifact_actions':
        return part.text?.trim().isNotEmpty == true ||
            part.label?.trim().isNotEmpty == true ||
            part.evidenceRefs.where((item) => !item.isEmpty).isNotEmpty ||
            part.roleIds.where((item) => item.trim().isNotEmpty).isNotEmpty ||
            part.actionIds.where((item) => item.trim().isNotEmpty).isNotEmpty;
      default:
        return false;
    }
  }

  bool _isSeminarEvidenceBundlePartType(String? rawType) {
    switch (rawType?.trim()) {
      case 'evidence':
      case 'evidence_bundle':
        return true;
      default:
        return false;
    }
  }

  bool _seminarSnapshotMessagePartVisibleInContext(
    AiSeminarRunCardMessagePart part, {
    required int? bookId,
    List<String> evidenceScopeIds = const <String>[],
  }) {
    final type = part.type.trim();
    if (type != 'tool_call' && !_isSeminarEvidenceBundlePartType(type)) {
      return true;
    }
    if (type != 'tool_call' && (part.toolId?.trim().isEmpty ?? true)) {
      return true;
    }
    return _seminarToolCallVisibleInContext(
      toolId: part.toolId,
      agentRunId: part.agentRunId,
      bookId: bookId,
      evidenceScopeIds: evidenceScopeIds,
    );
  }

  bool _seminarToolCallVisibleInContext({
    required String? toolId,
    required String? agentRunId,
    required int? bookId,
    List<String> evidenceScopeIds = const <String>[],
  }) {
    final normalizedToolId = toolId?.trim() ?? '';
    if (normalizedToolId.isEmpty) return true;
    final normalizedAgentRunId = agentRunId?.trim() ?? '';
    if (!normalizedAgentRunId.contains(':role-')) {
      return _seminarEvidenceToolCallVisibleForScopeIds(
        normalizedToolId,
        evidenceScopeIds,
      );
    }
    return _effectiveSeminarStatusAllowedToolIds(
      [normalizedToolId],
      bookId: bookId,
    ).isNotEmpty;
  }

  bool _seminarEvidenceToolCallVisibleForScopeIds(
    String toolId,
    List<String> evidenceScopeIds,
  ) {
    final scope = _seminarToolIdEvidenceScope(toolId);
    if (scope == null || evidenceScopeIds.isEmpty) return true;
    final scopes = evidenceScopeIds
        .map(AiSeminarEvidenceScope.fromString)
        .whereType<AiSeminarEvidenceScope>()
        .toSet();
    if (scopes.isEmpty || scopes.contains(scope)) return true;
    if (scope == AiSeminarEvidenceScope.currentBook) {
      return scopes.contains(AiSeminarEvidenceScope.currentChapter);
    }
    if (scope == AiSeminarEvidenceScope.currentChapter) {
      return scopes.contains(AiSeminarEvidenceScope.currentBook);
    }
    return false;
  }

  AiSeminarEvidenceScope? _seminarToolIdEvidenceScope(String toolId) {
    switch (toolId.trim()) {
      case 'semantic_search_current_book':
        return AiSeminarEvidenceScope.currentBook;
      case 'semantic_search_library':
        return AiSeminarEvidenceScope.library;
      case 'notes_search':
        return AiSeminarEvidenceScope.notes;
      case 'memory_search':
        return AiSeminarEvidenceScope.memory;
      case 'concept_graph_search':
        return AiSeminarEvidenceScope.conceptGraph;
      default:
        return null;
    }
  }

  Widget _seminarSnapshotNativeTimeline(
    List<AiSeminarRunCardMessagePart> parts, {
    required String? sessionId,
    required int? bookId,
    required int hiddenPartCount,
    required bool canToggleExpansion,
    required bool isExpanded,
    required bool showInlineEvidence,
    required bool showTraceDetails,
  }) {
    var roleTurnNumber = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SeminarSnapshotHeading(
          Icons.timeline_outlined,
          _localizedSeminarCardText(zh: '研讨流', en: 'Seminar stream'),
        ),
        const SizedBox(height: 6),
        for (final part in parts)
          _seminarSnapshotNativeTimelinePart(
            part,
            sessionId: sessionId,
            bookId: bookId,
            showInlineEvidence: showInlineEvidence,
            showTraceDetails: showTraceDetails,
            roleTurnNumber:
                part.type.trim() == 'role_turn' ? ++roleTurnNumber : null,
          ),
        if (hiddenPartCount > 0 ||
            (canToggleExpansion && sessionId != null && isExpanded))
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (hiddenPartCount > 0)
                Text(
                  _localizedSeminarCardText(
                    zh: '还有 $hiddenPartCount 个研讨片段可在分类视图中查看。',
                    en: '$hiddenPartCount more Seminar parts are available in tabs.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ClaudePalette.secondary(context),
                      ),
                ),
              if (canToggleExpansion && sessionId != null)
                TextButton.icon(
                  key: ValueKey(
                    'seminar-chat-card-native-timeline-toggle-$sessionId',
                  ),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    setState(() {
                      if (isExpanded) {
                        _seminarCardTimelineExpandedSessionIds
                            .remove(sessionId);
                      } else {
                        _seminarCardTimelineExpandedSessionIds.add(sessionId);
                      }
                    });
                  },
                  icon: Icon(
                    isExpanded
                        ? Icons.unfold_less_outlined
                        : Icons.unfold_more_outlined,
                    size: 16,
                  ),
                  label: Text(
                    _localizedSeminarCardText(
                      zh: isExpanded ? '收起研讨流' : '展开全部研讨流',
                      en: isExpanded
                          ? 'Collapse Seminar stream'
                          : 'Expand full Seminar stream',
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _seminarSnapshotNativeTimelinePart(
    AiSeminarRunCardMessagePart part, {
    required String? sessionId,
    required int? bookId,
    required bool showInlineEvidence,
    required bool showTraceDetails,
    required int? roleTurnNumber,
  }) {
    switch (part.type.trim()) {
      case 'seminar_run_setup':
        return _seminarSnapshotRunSetupPartTile(part);
      case 'tool_call':
        final toolCall = _seminarSnapshotToolCallFromPart(part);
        return SeminarSnapshotToolCallTile(
          toolCall: toolCall,
          label: _seminarToolCallLabel(toolCall),
          statusLabel: _seminarToolCallStatusLabel(toolCall),
          startedAtLabel: _seminarToolCallStartedAtLabel(toolCall),
          completedAtLabel: _seminarToolCallCompletedAtLabel(toolCall),
          durationLabel: _seminarToolCallDurationLabel(toolCall),
          visibleRoleLabels: _seminarToolCallVisibleRoleLabel(toolCall),
          outputLabel: _seminarToolCallOutputLabel(toolCall),
          zh: _isChineseLocale,
          actionLabelBuilder: _seminarToolCallActionLabel,
          actionIconBuilder: _seminarToolCallActionIcon,
          actionEnabledBuilder: (actionId) =>
              _seminarToolCallActionIsExecutable(
            toolCall,
            actionId: actionId,
            sessionId: sessionId,
          ),
          actionPressedBuilder: (actionId) => _seminarToolCallActionPressed(
            toolCall,
            actionId: actionId,
            sessionId: sessionId,
          ),
          isSubmitting: _seminarCardSubmittingSessionIds.contains(
            sessionId?.trim(),
          ),
          evidenceTileBuilder: (evidence) => SeminarSnapshotEvidenceTile(
            evidence,
            zh: _isChineseLocale,
            missingSourceLabel: _seminarMissingSourceLabel,
            sourceAction: _seminarSnapshotEvidenceSourceAction(
              evidence.sourceRef,
            ),
          ),
        );
      case 'evidence':
      case 'evidence_bundle':
        final evidenceRefs = part.evidenceRefs
            .where((item) => !item.isEmpty)
            .toList(growable: false);
        final label = part.label?.trim().isNotEmpty == true
            ? part.label!.trim()
            : _localizedSeminarCardText(
                zh: '证据快照',
                en: 'Evidence snapshot',
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SeminarSnapshotHeading(Icons.fact_check_outlined, label),
            const SizedBox(height: 6),
            for (final evidence in evidenceRefs)
              SeminarSnapshotEvidenceTile(
                evidence,
                zh: _isChineseLocale,
                missingSourceLabel: _seminarMissingSourceLabel,
                sourceAction: _seminarSnapshotEvidenceSourceAction(
                  evidence.sourceRef,
                ),
              ),
          ],
        );
      case 'role_turn':
        return _seminarSnapshotTimelineTurn(
          _seminarSnapshotRoleFromPart(part),
          roleTurnNumber ?? 1,
          agentRunId: showTraceDetails ? part.agentRunId : null,
          parentRunId: showTraceDetails ? part.parentRunId : null,
        );
      case 'role_partial':
        return _seminarSnapshotRolePartialTile(
          _seminarSnapshotRoleFromPart(part),
        );
      case 'director_state':
        return _seminarSnapshotDirectorCueTile(part, sessionId: sessionId);
      case 'agent_status':
        return _seminarSnapshotAgentStatusTile(
          part,
          sessionId: sessionId,
          bookId: bookId,
        );
      case 'thinking':
        final thinkingRoleId = part.roleId?.trim() ?? '';
        final thinkingContextLabel =
            thinkingRoleId.isEmpty || thinkingRoleId == 'director'
                ? null
                : (part.label?.trim().isNotEmpty ?? false)
                    ? part.label!.trim()
                    : _seminarRoleFallbackLabel(thinkingRoleId);
        return _seminarSnapshotNativeTextPartTile(
          icon: Icons.psychology_outlined,
          label: _localizedSeminarCardText(
            zh: '思考',
            en: 'Thinking',
          ),
          contextLabel: thinkingContextLabel,
          text: part.text?.trim() ?? part.label?.trim() ?? '',
          detailChipLabel: _seminarThinkingCompletedAtLabel(part.completedAt),
          agentRunId: showTraceDetails ? part.agentRunId : null,
          parentRunId: showTraceDetails ? part.parentRunId : null,
        );
      case 'reader_turn':
        return _seminarSnapshotReaderTurnTile(part);
      case 'reader_composer':
        return _seminarSnapshotReaderComposerTile(part);
      case 'synthesis':
        return _seminarSnapshotNativeTextPartTile(
          icon: Icons.auto_awesome_outlined,
          label: _localizedSeminarCardText(
            zh: '研讨总结',
            en: 'Seminar summary',
          ),
          text: part.text?.trim() ?? '',
          agentRunId: showTraceDetails ? part.agentRunId : null,
          parentRunId: showTraceDetails ? part.parentRunId : null,
          evidenceRefs: showInlineEvidence
              ? part.evidenceRefs
              : const <AiSeminarRunCardEvidenceSnapshot>[],
        );
      case 'disagreement':
        return _seminarSnapshotDisagreementDetails([
          AiSeminarRunCardDisagreementDetail(
            text: part.text ?? '',
            agentRunId: part.agentRunId,
            parentRunId: part.parentRunId,
            roleIds: part.roleIds,
            evidenceRefs: part.evidenceRefs,
          ),
        ]);
      case 'contradiction_scan':
        return _seminarSnapshotContradictionScanTiles(
          [part],
          sessionId: sessionId,
        );
      case 'disagreement_rebuttal':
        return _seminarSnapshotDisagreementRebuttalTiles([part]);
      case 'review_triage':
        return _seminarSnapshotReviewTriagePartTile(
          part,
          agentRunId: showTraceDetails ? part.agentRunId : null,
          parentRunId: showTraceDetails ? part.parentRunId : null,
          evidenceRefs: showInlineEvidence
              ? part.evidenceRefs
              : const <AiSeminarRunCardEvidenceSnapshot>[],
        );
      case 'artifact_actions':
        return _seminarSnapshotArtifactActionsPartTile(part);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _seminarSnapshotReviewTriagePartTile(
    AiSeminarRunCardMessagePart part, {
    required String? agentRunId,
    required String? parentRunId,
    required List<AiSeminarRunCardEvidenceSnapshot> evidenceRefs,
  }) {
    final label = _seminarReviewTriageTimelineLabel(part.label);
    final text = _seminarReviewTriageTimelineText(part);
    return _seminarSnapshotNativeTextPartTile(
      icon: Icons.rule_folder_outlined,
      label: label,
      text: text,
      agentRunId: agentRunId,
      parentRunId: parentRunId,
      evidenceRefs: evidenceRefs,
    );
  }

  String _seminarReviewTriageTimelineLabel(String? label) {
    switch (label?.trim()) {
      case 'reason':
        return _localizedSeminarCardText(
          zh: '异常原因',
          en: 'Review reason',
        );
      case 'ai-suggestion':
        return _localizedSeminarCardText(
          zh: 'AI 预审建议',
          en: 'AI triage suggestion',
        );
      case 'risk':
        return _localizedSeminarCardText(
          zh: 'AI 风险等级',
          en: 'AI risk level',
        );
      case 'suggested-action':
        return _localizedSeminarCardText(
          zh: '建议动作',
          en: 'Suggested action',
        );
      case 'knowledge-card':
        return _localizedSeminarCardText(
          zh: '知识卡候选',
          en: 'KnowledgeCard candidate',
        );
      case 'spaced-review':
        return _localizedSeminarCardText(
          zh: '复习候选',
          en: 'Spaced Review candidate',
        );
      default:
        return _localizedSeminarCardText(
          zh: '异常预审',
          en: 'Triage preview',
        );
    }
  }

  String _seminarReviewTriageTimelineText(
    AiSeminarRunCardMessagePart part,
  ) {
    final label = part.label?.trim();
    final text = part.text?.trim() ?? '';
    switch (label) {
      case 'risk':
        return _seminarReviewRiskLabel(text);
      case 'suggested-action':
        return _seminarReviewSuggestedActionLabel(text);
      default:
        return text.isNotEmpty ? text : label ?? '';
    }
  }

  Widget _seminarSnapshotArtifactActionsPartTile(
    AiSeminarRunCardMessagePart part,
  ) {
    final actionLabels = part.actionIds
        .map(_seminarArtifactActionChipLabel)
        .where((label) => label.isNotEmpty)
        .toList(growable: false);
    final text = _seminarArtifactActionDisplayText(part.text?.trim() ?? '');
    final statusLabel = _seminarArtifactActionStatusLabel(part.status);
    final completedAtLabel = _seminarArtifactActionCompletedAtLabel(
      part.status,
      part.completedAt,
    );
    final detailLabel = _seminarArtifactActionDetailLabel(part.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ClaudePalette.accentTint(context).withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ClaudePalette.divider(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 18,
                color: ClaudePalette.accent(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _localizedSeminarCardText(
                              zh: '沉淀动作',
                              en: 'Artifact actions',
                            ),
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: ClaudePalette.fg(context),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                    if (statusLabel != null || completedAtLabel != null) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (statusLabel != null)
                            SeminarSnapshotTinyChip(statusLabel),
                          if (completedAtLabel != null)
                            SeminarSnapshotTinyChip(completedAtLabel),
                        ],
                      ),
                    ],
                    SeminarSnapshotAgentTraceRows(
                      part.agentRunId,
                      parentRunId: part.parentRunId,
                      zh: _isChineseLocale,
                    ),
                    SeminarSnapshotCompactEvidenceRows(
                      evidenceRefs: part.evidenceRefs,
                      linkedEvidenceLabel: _seminarLinkedEvidenceLabel,
                      missingSourceLabel: _seminarMissingSourceLabel,
                      sourceActionBuilder: (evidence) =>
                          _seminarSnapshotEvidenceSourceAction(
                        evidence.sourceRef,
                      ),
                    ),
                    if (text.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        detailLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        text,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.3,
                            ),
                      ),
                    ],
                    if (actionLabels.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final label in actionLabels)
                            SeminarSnapshotTinyChip(label),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _seminarArtifactActionDisplayText(String rawText) {
    final normalized = rawText.trim();
    if (normalized.isEmpty) return '';
    if (normalized
        .toLowerCase()
        .contains('missing traceable source evidence')) {
      return _localizedSeminarCardText(
        zh: '缺少可追溯来源，不能直接保存为知识资产；请先送入异常处理。',
        en: 'Traceable source evidence is missing, so this cannot be saved as a knowledge asset yet. Send it to exception triage first.',
      );
    }
    return normalized;
  }

  String _seminarArtifactActionDetailLabel(String? status) {
    switch (status?.trim()) {
      case 'errored':
        return _localizedSeminarCardText(
          zh: '失败原因',
          en: 'Failure reason',
        );
      case 'interrupted':
        return _localizedSeminarCardText(
          zh: '中断原因',
          en: 'Interruption reason',
        );
      case 'shutdown':
        return _localizedSeminarCardText(
          zh: '停止原因',
          en: 'Stopped reason',
        );
      case 'cancelled':
      case 'canceled':
        return _localizedSeminarCardText(
          zh: '取消原因',
          en: 'Cancellation reason',
        );
      case 'notFound':
      case 'not_found':
      case 'not-found':
        return _localizedSeminarCardText(
          zh: '未找到原因',
          en: 'Missing action reason',
        );
      case 'running':
      case 'pending':
      case 'pendingInit':
      case 'pending_init':
      case 'pending-init':
        return _localizedSeminarCardText(
          zh: '处理说明',
          en: 'Processing note',
        );
      default:
        return _localizedSeminarCardText(
          zh: '执行结果',
          en: 'Execution result',
        );
    }
  }

  String? _seminarArtifactActionStatusLabel(String? status) {
    switch (status?.trim()) {
      case 'completed':
        return _localizedSeminarCardText(
          zh: '已处理',
          en: 'Processed',
        );
      case 'running':
      case 'pending':
      case 'pendingInit':
      case 'pending_init':
      case 'pending-init':
        return _localizedSeminarCardText(
          zh: '处理中',
          en: 'Processing',
        );
      case 'errored':
        return _localizedSeminarCardText(
          zh: '处理失败',
          en: 'Failed',
        );
      case 'interrupted':
        return _localizedSeminarCardText(
          zh: '已中断',
          en: 'Interrupted',
        );
      case 'shutdown':
        return _localizedSeminarCardText(
          zh: '已停止',
          en: 'Stopped',
        );
      case 'cancelled':
      case 'canceled':
        return _localizedSeminarCardText(
          zh: '已取消',
          en: 'Cancelled',
        );
      case 'notFound':
      case 'not_found':
      case 'not-found':
        return _localizedSeminarCardText(
          zh: '操作未找到',
          en: 'Action not found',
        );
      default:
        return null;
    }
  }

  String? _seminarArtifactActionCompletedAtLabel(
    String? status,
    int? completedAt,
  ) {
    if (_seminarArtifactActionHasActiveStatus(status)) return null;
    if (completedAt == null || completedAt <= 0) return null;
    final formatted = _formatTimestamp(completedAt);
    switch (status?.trim()) {
      case 'errored':
        return _localizedSeminarCardText(
          zh: '失败时间 $formatted',
          en: 'Failed at $formatted',
        );
      case 'interrupted':
        return _localizedSeminarCardText(
          zh: '中断时间 $formatted',
          en: 'Interrupted at $formatted',
        );
      case 'shutdown':
        return _localizedSeminarCardText(
          zh: '停止时间 $formatted',
          en: 'Stopped at $formatted',
        );
      case 'cancelled':
      case 'canceled':
        return _localizedSeminarCardText(
          zh: '取消时间 $formatted',
          en: 'Cancelled at $formatted',
        );
      case 'notFound':
      case 'not_found':
      case 'not-found':
        return _localizedSeminarCardText(
          zh: '未找到时间 $formatted',
          en: 'Not found at $formatted',
        );
      default:
        return _localizedSeminarCardText(
          zh: '执行时间 $formatted',
          en: 'Executed at $formatted',
        );
    }
  }

  bool _seminarArtifactActionHasActiveStatus(String? rawStatus) {
    switch (rawStatus?.trim()) {
      case 'running':
      case 'pending':
      case 'pendingInit':
      case 'pending_init':
      case 'pending-init':
        return true;
      default:
        return false;
    }
  }

  String _seminarArtifactActionChipLabel(String actionId) {
    switch (actionId.trim()) {
      case 'save-knowledge-card':
        return _localizedSeminarCardText(
          zh: '保存知识卡',
          en: 'Save card',
        );
      case 'edit-knowledge-card':
        return _localizedSeminarCardText(
          zh: '编辑知识卡',
          en: 'Edit card',
        );
      case 'knowledge-card-saved':
        return _localizedSeminarCardText(zh: '已保存知识卡', en: 'Card saved');
      case 'undo-knowledge-card':
        return _localizedSeminarCardText(
          zh: '撤销知识卡',
          en: 'Undo card',
        );
      case 'add-spaced-review':
        return _localizedSeminarCardText(
          zh: '加入复习',
          en: 'Add review',
        );
      case 'spaced-review-added':
        return _localizedSeminarCardText(zh: '复习已加入', en: 'Review added');
      case 'undo-spaced-review':
        return _localizedSeminarCardText(
          zh: '撤销复习',
          en: 'Undo review',
        );
      case 'add-concept-graph':
        return _localizedSeminarCardText(
          zh: '加入我的图谱',
          en: 'Add to graph',
        );
      case 'concept-graph-added':
        return _localizedSeminarCardText(zh: '图谱已加入', en: 'Graph added');
      case 'undo-concept-graph':
        return _localizedSeminarCardText(
          zh: '撤销图谱',
          en: 'Undo graph',
        );
      case 'send-to-review':
        return _localizedSeminarCardText(
          zh: '异常送审',
          en: 'Send to triage',
        );
      case 'sent-to-review':
        return _localizedSeminarCardText(zh: '已送审', en: 'Sent');
      case 'ignore-artifact-actions':
        return _localizedSeminarCardText(
          zh: '忽略建议',
          en: 'Ignore suggestions',
        );
      case 'artifact-actions-ignored':
        return _localizedSeminarCardText(zh: '沉淀已忽略', en: 'Ignored');
      case 'restore-artifact-actions':
        return _localizedSeminarCardText(
          zh: '恢复沉淀动作',
          en: 'Restore actions',
        );
      default:
        return '';
    }
  }

  Widget _seminarSnapshotRunSetupPartTile(
    AiSeminarRunCardMessagePart part,
  ) {
    final lines = <String>[
      part.text?.trim() ?? '',
      part.label?.trim() ?? '',
    ].where((line) => line.isNotEmpty).toList(growable: false);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ClaudePalette.divider(context)),
        color: ClaudePalette.accentTint(context).withValues(alpha: 0.28),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.tune_outlined,
              size: 18,
              color: ClaudePalette.accent(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _localizedSeminarCardText(
                      zh: '本次设置',
                      en: 'Run setup',
                    ),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: ClaudePalette.fg(context),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  if (lines.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    for (final line in lines)
                      Text(
                        line,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.3,
                            ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  AiSeminarRunCardToolCallSnapshot _seminarSnapshotToolCallFromPart(
    AiSeminarRunCardMessagePart part,
  ) {
    return AiSeminarRunCardToolCallSnapshot(
      id: part.id,
      agentRunId: part.agentRunId,
      parentRunId: part.parentRunId,
      toolId: part.toolId ?? '',
      status: part.status,
      label: part.label,
      text: part.text,
      query: part.query ?? '',
      resultCount: part.resultCount,
      startedAt: part.startedAt,
      completedAt: part.completedAt,
      roleIds: part.roleIds,
      actionIds: part.actionIds,
      evidenceRefs: part.evidenceRefs,
    );
  }

  AiSeminarRunCardRoleSummary _seminarSnapshotRoleFromPart(
    AiSeminarRunCardMessagePart part,
  ) {
    return AiSeminarRunCardRoleSummary(
      roleId: part.roleId ?? '',
      label: part.label ?? '',
      summary: part.text ?? '',
      evidenceRefs: part.evidenceRefs,
    );
  }

  Widget _seminarSnapshotNativeTextPartTile({
    required IconData icon,
    required String label,
    String? contextLabel,
    required String text,
    String? detailChipLabel,
    String? agentRunId,
    String? parentRunId,
    List<AiSeminarRunCardEvidenceSnapshot> evidenceRefs = const [],
  }) {
    final normalizedText = text.trim();
    final normalizedContextLabel = contextLabel?.trim() ?? '';
    final normalizedDetailChipLabel = detailChipLabel?.trim() ?? '';
    if (normalizedText.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ClaudePalette.elevated(context).withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ClaudePalette.divider(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 17, color: ClaudePalette.accent(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: ClaudePalette.fg(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (normalizedContextLabel.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        normalizedContextLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                    const SizedBox(height: 3),
                    SeminarSnapshotExpandableText(
                      normalizedText,
                      collapsedMaxLines: 4,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: ClaudePalette.secondary(context),
                            height: 1.32,
                          ),
                    ),
                    if (normalizedDetailChipLabel.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          SeminarSnapshotTinyChip(
                            normalizedDetailChipLabel,
                          ),
                        ],
                      ),
                    ],
                    SeminarSnapshotAgentTraceRows(
                      agentRunId,
                      parentRunId: parentRunId,
                      zh: _isChineseLocale,
                    ),
                    SeminarSnapshotCompactEvidenceRows(
                      evidenceRefs: evidenceRefs,
                      linkedEvidenceLabel: _seminarLinkedEvidenceLabel,
                      missingSourceLabel: _seminarMissingSourceLabel,
                      sourceActionBuilder: (evidence) =>
                          _seminarSnapshotEvidenceSourceAction(
                        evidence.sourceRef,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _seminarThinkingCompletedAtLabel(int? completedAt) {
    if (completedAt == null || completedAt <= 0) return null;
    final formatted = _formatTimestamp(completedAt);
    return _localizedSeminarCardText(
      zh: '思考时间 $formatted',
      en: 'Thought at $formatted',
    );
  }

  String _seminarToolCallLabel(AiSeminarRunCardToolCallSnapshot toolCall) {
    final customLabel = toolCall.label?.trim();
    if (customLabel != null && customLabel.isNotEmpty) return customLabel;
    return _seminarToolDisplayLabel(toolCall.toolId);
  }

  String _seminarToolDisplayLabel(String toolId) {
    switch (toolId.trim()) {
      case 'semantic_search_current_book':
        return _localizedSeminarCardText(
          zh: '书内语义检索',
          en: 'Current-book semantic search',
        );
      case 'semantic_search_library':
        return _localizedSeminarCardText(
          zh: '书库语义检索',
          en: 'Library semantic search',
        );
      case 'notes_search':
        return _localizedSeminarCardText(
          zh: '笔记搜索',
          en: 'Notes search',
        );
      case 'memory_search':
        return _localizedSeminarCardText(
          zh: '记忆搜索',
          en: 'Memory search',
        );
      case 'concept_graph_search':
        return _localizedSeminarCardText(
          zh: '图谱检索',
          en: 'Concept graph search',
        );
      case 'resolve_cfi':
        return _localizedSeminarCardText(
          zh: '原文定位',
          en: 'Source resolver',
        );
      default:
        return toolId.trim().isNotEmpty
            ? toolId.trim()
            : _localizedSeminarCardText(
                zh: '只读工具',
                en: 'Read-only tool',
              );
    }
  }

  String? _seminarToolCallStatusLabel(
    AiSeminarRunCardToolCallSnapshot toolCall,
  ) {
    switch (toolCall.status?.trim()) {
      case 'running':
      case 'pending':
      case 'pendingInit':
      case 'pending_init':
      case 'pending-init':
        return _localizedSeminarCardText(
          zh: '调用中',
          en: 'Running',
        );
      case 'completed':
        return _localizedSeminarCardText(
          zh: '调用完成',
          en: 'Completed',
        );
      case 'errored':
        return _localizedSeminarCardText(
          zh: '调用失败',
          en: 'Failed',
        );
      case 'interrupted':
        return _localizedSeminarCardText(
          zh: '已中断',
          en: 'Interrupted',
        );
      case 'shutdown':
        return _localizedSeminarCardText(
          zh: '已停止',
          en: 'Stopped',
        );
      case 'cancelled':
      case 'canceled':
        return _localizedSeminarCardText(
          zh: '已取消',
          en: 'Cancelled',
        );
      case 'notFound':
      case 'not_found':
      case 'not-found':
        return _localizedSeminarCardText(
          zh: '调用未找到',
          en: 'Call not found',
        );
      default:
        return null;
    }
  }

  String? _seminarToolCallCompletedAtLabel(
    AiSeminarRunCardToolCallSnapshot toolCall,
  ) {
    if (!_seminarToolCallHasTerminalStatus(toolCall.status)) return null;
    final completedAt = toolCall.completedAt;
    if (completedAt == null || completedAt <= 0) return null;
    final formatted = _formatTimestamp(completedAt);
    switch (toolCall.status?.trim()) {
      case 'errored':
        return _localizedSeminarCardText(
          zh: '失败时间 $formatted',
          en: 'Failed at $formatted',
        );
      case 'interrupted':
        return _localizedSeminarCardText(
          zh: '中断时间 $formatted',
          en: 'Interrupted at $formatted',
        );
      case 'shutdown':
        return _localizedSeminarCardText(
          zh: '停止时间 $formatted',
          en: 'Stopped at $formatted',
        );
      case 'cancelled':
      case 'canceled':
        return _localizedSeminarCardText(
          zh: '取消时间 $formatted',
          en: 'Cancelled at $formatted',
        );
      case 'notFound':
      case 'not_found':
      case 'not-found':
        return _localizedSeminarCardText(
          zh: '未找到时间 $formatted',
          en: 'Not found at $formatted',
        );
      default:
        return _localizedSeminarCardText(
          zh: '执行时间 $formatted',
          en: 'Executed at $formatted',
        );
    }
  }

  String? _seminarToolCallStartedAtLabel(
    AiSeminarRunCardToolCallSnapshot toolCall,
  ) {
    if (!_seminarToolCallHasActiveStatus(toolCall.status)) return null;
    final startedAt = toolCall.startedAt;
    if (startedAt == null || startedAt <= 0) return null;
    final formatted = _formatTimestamp(startedAt);
    return _localizedSeminarCardText(
      zh: '开始时间 $formatted',
      en: 'Started at $formatted',
    );
  }

  String? _seminarToolCallDurationLabel(
    AiSeminarRunCardToolCallSnapshot toolCall,
  ) {
    if (!_seminarToolCallHasTerminalStatus(toolCall.status)) return null;
    final startedAt = toolCall.startedAt;
    final completedAt = toolCall.completedAt;
    if (startedAt == null ||
        startedAt <= 0 ||
        completedAt == null ||
        completedAt <= 0 ||
        completedAt < startedAt) {
      return null;
    }
    final formatted = _seminarToolCallDurationText(completedAt - startedAt);
    return _localizedSeminarCardText(
      zh: '耗时 $formatted',
      en: 'Duration $formatted',
    );
  }

  String _seminarToolCallDurationText(int durationMs) {
    if (durationMs < 1000) {
      return _localizedSeminarCardText(
        zh: '$durationMs毫秒',
        en: '${durationMs}ms',
      );
    }
    final totalSeconds = (durationMs / 1000).round();
    if (totalSeconds < 60) {
      return _localizedSeminarCardText(
        zh: '$totalSeconds秒',
        en: '${totalSeconds}s',
      );
    }
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (seconds == 0) {
      return _localizedSeminarCardText(
        zh: '$minutes分钟',
        en: '$minutes m',
      );
    }
    return _localizedSeminarCardText(
      zh: '$minutes分$seconds秒',
      en: '$minutes m ${seconds}s',
    );
  }

  bool _seminarToolCallHasActiveStatus(String? rawStatus) {
    switch (rawStatus?.trim()) {
      case 'running':
      case 'pending':
      case 'pendingInit':
      case 'pending_init':
      case 'pending-init':
        return true;
      default:
        return false;
    }
  }

  bool _seminarToolCallHasTerminalStatus(String? rawStatus) {
    switch (rawStatus?.trim()) {
      case 'completed':
      case 'errored':
      case 'interrupted':
      case 'shutdown':
      case 'cancelled':
      case 'canceled':
      case 'notFound':
      case 'not_found':
      case 'not-found':
        return true;
      default:
        return false;
    }
  }

  String _seminarToolCallOutputLabel(
    AiSeminarRunCardToolCallSnapshot toolCall,
  ) {
    switch (toolCall.status?.trim()) {
      case 'errored':
        return _localizedSeminarCardText(
          zh: '失败原因',
          en: 'Failure reason',
        );
      case 'interrupted':
        return _localizedSeminarCardText(
          zh: '中断原因',
          en: 'Interruption reason',
        );
      case 'shutdown':
        return _localizedSeminarCardText(
          zh: '停止原因',
          en: 'Stopped reason',
        );
      case 'cancelled':
      case 'canceled':
        return _localizedSeminarCardText(
          zh: '取消原因',
          en: 'Cancellation reason',
        );
      case 'notFound':
      case 'not_found':
      case 'not-found':
        return _localizedSeminarCardText(
          zh: '未找到原因',
          en: 'Missing call reason',
        );
      default:
        return _localizedSeminarCardText(
          zh: '工具输出',
          en: 'Tool output',
        );
    }
  }

  String _seminarToolCallActionLabel(String? action) {
    switch (action?.trim()) {
      case 'wait-tool-call':
        return _localizedSeminarCardText(
          zh: '证据检索中…',
          en: 'Retrieving evidence...',
        );
      case 'cancel-tool-call':
        return _localizedSeminarCardText(
          zh: '取消工具调用',
          en: 'Cancel tool call',
        );
      default:
        return '';
    }
  }

  VoidCallback? _seminarToolCallActionPressed(
    AiSeminarRunCardToolCallSnapshot toolCall, {
    required String actionId,
    required String? sessionId,
  }) {
    final normalizedSessionId = sessionId?.trim();
    final agentRunId = toolCall.agentRunId?.trim();
    final toolCallId = toolCall.id?.trim();
    if (normalizedSessionId?.isNotEmpty != true ||
        agentRunId?.isNotEmpty != true ||
        toolCallId?.isNotEmpty != true) {
      return null;
    }
    return () {
      if (actionId == 'wait-tool-call') {
        unawaited(_waitSeminarToolCallControl(
          sessionId: normalizedSessionId!,
          agentRunId: agentRunId!,
          toolCallId: toolCallId!,
        ));
      } else if (actionId == 'cancel-tool-call') {
        unawaited(_cancelSeminarToolCallControl(
          sessionId: normalizedSessionId!,
          agentRunId: agentRunId!,
          toolCallId: toolCallId!,
        ));
      }
    };
  }

  bool _seminarToolCallActionIsExecutable(
    AiSeminarRunCardToolCallSnapshot toolCall, {
    required String actionId,
    required String? sessionId,
  }) {
    final normalizedSessionId = sessionId?.trim();
    if (normalizedSessionId?.isNotEmpty != true) return false;
    if (!_seminarToolCallHasActiveStatus(toolCall.status)) return false;
    final agentRunId = toolCall.agentRunId?.trim();
    final toolCallId = toolCall.id?.trim();
    switch (actionId) {
      case 'wait-tool-call':
        return agentRunId?.isNotEmpty == true && toolCallId?.isNotEmpty == true;
      case 'cancel-tool-call':
        return agentRunId?.isNotEmpty == true && toolCallId?.isNotEmpty == true;
      default:
        return false;
    }
  }

  IconData _seminarToolCallActionIcon(String actionId) {
    switch (actionId.trim()) {
      case 'wait-tool-call':
        return Icons.hourglass_empty_outlined;
      case 'cancel-tool-call':
        return Icons.cancel_outlined;
      default:
        return Icons.tune_outlined;
    }
  }

  String _seminarToolCallSummaryText(int resultCount) {
    if (resultCount <= 0) return '';
    if (_isChineseLocale) return '返回 $resultCount 条可追踪证据。';
    return resultCount == 1
        ? 'Returned 1 traceable evidence chunk.'
        : 'Returned $resultCount traceable evidence chunks.';
  }

  String _seminarToolCallVisibleRoleLabel(
    AiSeminarRunCardToolCallSnapshot toolCall,
  ) {
    final labels = <String>[];
    final seen = <String>{};
    for (final rawRoleId in toolCall.roleIds) {
      final roleId = rawRoleId.trim();
      if (roleId.isEmpty || !seen.add(roleId)) continue;
      labels.add(_seminarRoleFallbackLabel(roleId));
    }
    return labels.join(_isChineseLocale ? '、' : ', ');
  }

  Widget? _seminarSnapshotEvidenceSourceAction(SourceRef? sourceRef) {
    if (sourceRef == null || !sourceRef.hasEvidence) return null;
    final sourceIntent = PaperReaderReaderIntent.fromSourceRef(sourceRef);
    return TextButton.icon(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: const Size(0, 26),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      icon: Icon(
        sourceIntent == null ? Icons.info_outline : Icons.open_in_new_outlined,
        size: 14,
      ),
      label: Text(
        sourceIntent == null
            ? _localizedSeminarCardText(
                zh: '来源不可用',
                en: 'Source unavailable',
              )
            : _localizedSeminarCardText(
                zh: '打开来源',
                en: 'Open source',
              ),
      ),
      onPressed: sourceIntent == null
          ? () => showPaperReaderSourceUnavailable(
                context,
                [sourceRef],
                _localizedSeminarCardText(
                  zh: '没有可跳转的来源。',
                  en: 'No jumpable source available.',
                ),
              )
          : () => _sourceOpener(ref, sourceIntent.toUri()),
    );
  }

  void _openSeminarEvidenceSource(SourceRef sourceRef) {
    final sourceIntent = PaperReaderReaderIntent.fromSourceRef(sourceRef);
    if (sourceIntent == null) {
      showPaperReaderSourceUnavailable(
        context,
        [sourceRef],
        _localizedSeminarCardText(
          zh: '没有可跳转的来源。',
          en: 'No jumpable source available.',
        ),
      );
      return;
    }
    _sourceOpener(ref, sourceIntent.toUri());
  }

  Widget _seminarSnapshotRoleTile(AiSeminarRunCardRoleSummary role) {
    final label = role.label.trim().isNotEmpty
        ? role.label.trim()
        : _seminarRoleFallbackLabel(role.roleId);
    final summary = role.summary.trim();
    final evidenceRefs = role.evidenceRefs
        .where((item) => !item.isEmpty)
        .toList(growable: false);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _seminarRoleIconById(role.roleId),
            size: 16,
            color: ClaudePalette.accent(context),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: ClaudePalette.fg(context),
                      ),
                ),
                if (summary.isNotEmpty)
                  SeminarSnapshotExpandableText(
                    summary,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ClaudePalette.secondary(context),
                          height: 1.32,
                        ),
                  ),
                if (evidenceRefs.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  SeminarEvidenceReferenceChips(
                    evidenceRefs: evidenceRefs,
                    zh: _isChineseLocale,
                    onEvidencePressed: _jumpToSeminarEvidenceRow,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _seminarSnapshotDiscussionTimeline(
    List<AiSeminarRunCardRoleSummary> roles, {
    List<AiSeminarRunCardRoleSummary> rolePartials =
        const <AiSeminarRunCardRoleSummary>[],
    AiSeminarRole? liveRole,
    String liveRoleText = '',
  }) {
    final turns = roles.where((role) => !role.isEmpty).toList();
    final partials = rolePartials.where((role) => !role.isEmpty).toList();
    final normalizedLiveText = liveRoleText.trim();
    final hasLiveRole = liveRole != null && normalizedLiveText.isNotEmpty;
    if (turns.isEmpty && partials.isEmpty && !hasLiveRole) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SeminarSnapshotHeading(
          Icons.chat_bubble_outline,
          _localizedSeminarCardText(
            zh: '研讨时间线',
            en: 'Discussion timeline',
          ),
        ),
        const SizedBox(height: 6),
        for (var index = 0; index < turns.length; index += 1)
          _seminarSnapshotTimelineTurn(turns[index], index + 1),
        for (final partial in partials)
          _seminarSnapshotRolePartialTile(partial),
        if (hasLiveRole)
          _seminarSnapshotLiveRoleTile(
            liveRole,
            normalizedLiveText,
          ),
      ],
    );
  }

  Widget _seminarSnapshotRolePartialTile(AiSeminarRunCardRoleSummary partial) {
    final roleId = partial.roleId.trim();
    final label = partial.label.trim().isNotEmpty
        ? partial.label.trim()
        : _seminarRoleFallbackLabel(roleId);
    final partialText = partial.summary.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ClaudePalette.elevated(context).withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ClaudePalette.divider(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _seminarRoleIconById(roleId),
                size: 17,
                color: ClaudePalette.accent(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _localizedSeminarCardText(
                        zh: '角色发言生成中',
                        en: 'Role turn streaming',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: ClaudePalette.secondary(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: ClaudePalette.fg(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (partialText.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      SeminarSnapshotExpandableText(
                        partialText,
                        collapsedMaxLines: 4,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.32,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seminarSnapshotLiveRoleTile(
    AiSeminarRole role,
    String partialText,
  ) {
    final label = _seminarRoleFallbackLabel(role.asString);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ClaudePalette.elevated(context).withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ClaudePalette.divider(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _seminarRoleIconById(role.asString),
                size: 17,
                color: ClaudePalette.accent(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _localizedSeminarCardText(
                        zh: '角色发言生成中',
                        en: 'Role turn streaming',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: ClaudePalette.secondary(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: ClaudePalette.fg(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (partialText.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      SeminarSnapshotExpandableText(
                        partialText.trim(),
                        collapsedMaxLines: 4,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.32,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seminarSnapshotReaderTurnTile(AiSeminarRunCardMessagePart part) {
    final targetRole = part.roleId?.trim();
    final action = part.label?.trim();
    final targetLabel = targetRole == null || targetRole.isEmpty
        ? ''
        : _seminarRoleFallbackLabel(targetRole);
    final actionLabel = _seminarReaderTurnActionLabel(action);
    final statusLabel = _seminarReaderTurnStatusLabel(part.status);
    final completedAtLabel = _seminarReaderTurnCompletedAtLabel(
      part.status,
      part.completedAt,
    );
    final toolId = part.toolId?.trim() ?? '';
    final toolLabel =
        toolId.isEmpty ? '' : _seminarToolDisplayLabel(toolId).trim();
    final query = part.query?.trim() ?? '';
    final meta = [
      if (actionLabel.isNotEmpty) actionLabel,
      if (targetLabel.isNotEmpty) targetLabel,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ClaudePalette.elevated(context).withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ClaudePalette.divider(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.person_outline,
                size: 17,
                color: ClaudePalette.accent(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (meta.isNotEmpty)
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: ClaudePalette.fg(context),
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                    if (part.text?.trim().isNotEmpty == true) ...[
                      if (meta.isNotEmpty) const SizedBox(height: 3),
                      SeminarSnapshotExpandableText(
                        part.text!.trim(),
                        collapsedMaxLines: 4,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.32,
                            ),
                      ),
                    ],
                    if (toolLabel.isNotEmpty || query.isNotEmpty) ...[
                      if (meta.isNotEmpty ||
                          part.text?.trim().isNotEmpty == true)
                        const SizedBox(height: 5),
                      if (toolLabel.isNotEmpty)
                        Text(
                          _localizedSeminarCardText(
                            zh: '工具：$toolLabel',
                            en: 'Tool: $toolLabel',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: ClaudePalette.secondary(context),
                                    height: 1.32,
                                  ),
                        ),
                      if (query.isNotEmpty)
                        Text(
                          _localizedSeminarCardText(
                            zh: '查询：$query',
                            en: 'Query: $query',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: ClaudePalette.secondary(context),
                                    height: 1.32,
                                  ),
                        ),
                    ],
                    if (statusLabel != null || completedAtLabel != null) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (statusLabel != null)
                            SeminarSnapshotTinyChip(statusLabel),
                          if (completedAtLabel != null)
                            SeminarSnapshotTinyChip(completedAtLabel),
                        ],
                      ),
                    ],
                    SeminarSnapshotAgentTraceRows(
                      part.agentRunId,
                      parentRunId: part.parentRunId,
                      zh: _isChineseLocale,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _seminarReaderTurnStatusLabel(String? status) {
    switch (status?.trim()) {
      case 'completed':
        return _localizedSeminarCardText(
          zh: '已处理',
          en: 'Processed',
        );
      case 'pendingInit':
      case 'pending_init':
      case 'pending-init':
      case 'running':
        return _localizedSeminarCardText(
          zh: '处理中',
          en: 'Processing',
        );
      case 'pending':
        return _localizedSeminarCardText(
          zh: '待处理',
          en: 'Pending',
        );
      case 'cancelled':
      case 'canceled':
        return _localizedSeminarCardText(
          zh: '已取消',
          en: 'Cancelled',
        );
      default:
        return null;
    }
  }

  String? _seminarReaderTurnCompletedAtLabel(
    String? status,
    int? completedAt,
  ) {
    if (completedAt == null || completedAt <= 0) return null;
    final formatted = _formatTimestamp(completedAt);
    final normalizedStatus = status?.trim();
    if (normalizedStatus == 'cancelled' || normalizedStatus == 'canceled') {
      return _localizedSeminarCardText(
        zh: '取消时间 $formatted',
        en: 'Cancelled at $formatted',
      );
    }
    return _localizedSeminarCardText(
      zh: '处理时间 $formatted',
      en: 'Processed at $formatted',
    );
  }

  Widget _seminarSnapshotReaderComposerTile(AiSeminarRunCardMessagePart part) {
    final prompt = part.text?.trim();
    final actionLabels = part.actionIds
        .map(_seminarReaderTurnActionLabel)
        .where((label) => label.trim().isNotEmpty)
        .toList(growable: false);
    final roleLabels = part.roleIds
        .map((roleId) => _seminarRoleFallbackLabel(roleId.trim()))
        .where((label) => label.trim().isNotEmpty)
        .toList(growable: false);
    final defaultActionLabel = part.defaultActionId?.trim().isNotEmpty == true
        ? _seminarReaderTurnActionLabel(part.defaultActionId!.trim())
        : null;
    final defaultRoleLabel = part.defaultRoleId?.trim().isNotEmpty == true
        ? _seminarRoleFallbackLabel(part.defaultRoleId!.trim())
        : null;
    final selectedActionLabel = part.selectedActionId?.trim().isNotEmpty == true
        ? _seminarReaderTurnActionLabel(part.selectedActionId!.trim())
        : null;
    final selectedRoleLabel = part.selectedRoleId?.trim().isNotEmpty == true
        ? _seminarRoleFallbackLabel(part.selectedRoleId!.trim())
        : null;
    final draftText = part.draftText?.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ClaudePalette.accentTint(context).withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ClaudePalette.divider(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _localizedSeminarCardText(
                  zh: '这场研讨可继续由读者参与',
                  en: 'This Seminar can continue with a reader turn',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: ClaudePalette.fg(context),
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (prompt != null && prompt.isNotEmpty) ...[
                const SizedBox(height: 4),
                SeminarSnapshotExpandableText(
                  prompt,
                  collapsedMaxLines: 3,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ClaudePalette.secondary(context),
                        height: 1.32,
                      ),
                ),
              ],
              SeminarSnapshotAgentTraceRows(
                part.agentRunId,
                parentRunId: part.parentRunId,
                zh: _isChineseLocale,
              ),
              if (defaultActionLabel != null || defaultRoleLabel != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (defaultActionLabel != null)
                      SeminarSnapshotLabeledTinyChip(
                        label: _localizedSeminarCardText(
                          zh: '默认动作',
                          en: 'Default action',
                        ),
                        value: defaultActionLabel,
                      ),
                    if (defaultRoleLabel != null)
                      SeminarSnapshotLabeledTinyChip(
                        label: _localizedSeminarCardText(
                          zh: '默认角色',
                          en: 'Default role',
                        ),
                        value: defaultRoleLabel,
                      ),
                  ],
                ),
              ],
              if (selectedActionLabel != null || selectedRoleLabel != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (selectedActionLabel != null)
                      SeminarSnapshotLabeledTinyChip(
                        label: _localizedSeminarCardText(
                          zh: '当前动作',
                          en: 'Current action',
                        ),
                        value: selectedActionLabel,
                      ),
                    if (selectedRoleLabel != null)
                      SeminarSnapshotLabeledTinyChip(
                        label: _localizedSeminarCardText(
                          zh: '当前角色',
                          en: 'Current role',
                        ),
                        value: selectedRoleLabel,
                      ),
                  ],
                ),
              ],
              if (draftText != null && draftText.isNotEmpty) ...[
                const SizedBox(height: 8),
                SeminarSnapshotLabelText(
                  _localizedSeminarCardText(
                    zh: '草稿回复',
                    en: 'Draft reply',
                  ),
                ),
                const SizedBox(height: 4),
                SeminarSnapshotExpandableText(
                  draftText,
                  collapsedMaxLines: 4,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ClaudePalette.secondary(context),
                        height: 1.32,
                      ),
                ),
              ],
              if (actionLabels.isNotEmpty) ...[
                const SizedBox(height: 8),
                SeminarSnapshotLabelText(
                  _localizedSeminarCardText(
                    zh: '可用动作',
                    en: 'Available actions',
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final label in actionLabels)
                      SeminarSnapshotTinyChip(label),
                  ],
                ),
              ],
              if (roleLabels.isNotEmpty) ...[
                const SizedBox(height: 8),
                SeminarSnapshotLabelText(
                  _localizedSeminarCardText(
                    zh: '可用角色',
                    en: 'Available roles',
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final label in roleLabels)
                      SeminarSnapshotTinyChip(label),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _seminarSnapshotDirectorCueTile(
    AiSeminarRunCardMessagePart part, {
    required String? sessionId,
  }) {
    final intent = part.label?.trim();
    final cueText = part.text?.trim();
    final controlActionIds = part.actionIds
        .map((actionId) => actionId.trim())
        .where(
            (actionId) => _seminarAgentControlActionLabel(actionId).isNotEmpty)
        .toList(growable: false);
    final inlineControlActionIds = controlActionIds
        .where((actionId) => !_seminarAgentControlActionIsExecutable(
              part,
              actionId: actionId,
              sessionId: sessionId,
            ))
        .toList(growable: false);
    final agentRunId = _seminarAgentRunIdFromStatusPart(part);
    final normalizedSessionId = sessionId?.trim();
    final showAgentInput = agentRunId != null &&
        normalizedSessionId?.isNotEmpty == true &&
        controlActionIds.contains('send-input') &&
        _seminarAgentInputExpandedRunIds.contains(agentRunId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ClaudePalette.accentTint(context).withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ClaudePalette.divider(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.psychology_outlined,
                size: 17,
                color: ClaudePalette.accent(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _seminarDirectorCueLabel(intent),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: ClaudePalette.fg(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (cueText != null && cueText.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      SeminarSnapshotExpandableText(
                        cueText,
                        collapsedMaxLines: 3,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.32,
                            ),
                      ),
                    ],
                    SeminarSnapshotAgentTraceRows(
                      part.agentRunId,
                      parentRunId: part.parentRunId,
                      zh: _isChineseLocale,
                    ),
                    if (inlineControlActionIds.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SeminarSnapshotLabelText(
                        _localizedSeminarCardText(
                          zh: '历史控制',
                          en: 'Recorded controls',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final actionId in inlineControlActionIds)
                            _seminarAgentControlAction(
                              part,
                              actionId: actionId,
                              sessionId: sessionId,
                            ),
                        ],
                      ),
                    ],
                    if (showAgentInput) ...[
                      const SizedBox(height: 8),
                      _seminarAgentInputComposer(
                        sessionId: normalizedSessionId!,
                        agentRunId: agentRunId,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seminarSnapshotAgentStatusTile(
    AiSeminarRunCardMessagePart part, {
    required String? sessionId,
    required int? bookId,
  }) {
    final status = part.label?.trim();
    final statusText = part.text?.trim();
    final roleId = part.roleId?.trim();
    final controlActionIds = part.actionIds
        .map((actionId) => actionId.trim())
        .where(
            (actionId) => _seminarAgentControlActionLabel(actionId).isNotEmpty)
        .toList(growable: false);
    final inlineControlActionIds = controlActionIds
        .where((actionId) => !_seminarAgentControlActionIsExecutable(
              part,
              actionId: actionId,
              sessionId: sessionId,
            ))
        .toList(growable: false);
    final allowedToolIds = _effectiveSeminarStatusAllowedToolIds(
      part.allowedToolIds,
      bookId: bookId,
    );
    final agentRunId = _seminarAgentRunIdFromStatusPart(part);
    final normalizedSessionId = sessionId?.trim();
    final showAgentInput = agentRunId != null &&
        normalizedSessionId?.isNotEmpty == true &&
        controlActionIds.contains('send-input') &&
        _seminarAgentInputExpandedRunIds.contains(agentRunId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ClaudePalette.accentTint(context).withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ClaudePalette.divider(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.support_agent_outlined,
                size: 17,
                color: ClaudePalette.accent(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SeminarSnapshotLabelText(
                      _localizedSeminarCardText(
                        zh: '角色状态',
                        en: 'Role status',
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          _seminarAgentStatusLabel(status),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: ClaudePalette.fg(context),
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        if (roleId != null && roleId.isNotEmpty)
                          SeminarSnapshotTinyChip(
                            _seminarRoleFallbackLabel(roleId),
                          ),
                      ],
                    ),
                    if (statusText != null && statusText.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      SeminarSnapshotExpandableText(
                        statusText,
                        collapsedMaxLines: 3,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.32,
                            ),
                      ),
                    ],
                    SeminarSnapshotAgentTraceRows(
                      part.agentRunId,
                      parentRunId: part.parentRunId,
                      zh: _isChineseLocale,
                    ),
                    if (allowedToolIds.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SeminarSnapshotLabelText(
                        _localizedSeminarCardText(
                          zh: '允许工具',
                          en: 'Allowed tools',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final toolId in allowedToolIds)
                            SeminarSnapshotTinyChip(
                              _seminarToolDisplayLabel(toolId),
                            ),
                        ],
                      ),
                    ],
                    if (inlineControlActionIds.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SeminarSnapshotLabelText(
                        _localizedSeminarCardText(
                          zh: '历史控制',
                          en: 'Recorded controls',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final actionId in inlineControlActionIds)
                            _seminarAgentControlAction(
                              part,
                              actionId: actionId,
                              sessionId: sessionId,
                            ),
                        ],
                      ),
                    ],
                    if (showAgentInput) ...[
                      const SizedBox(height: 8),
                      _seminarAgentInputComposer(
                        sessionId: normalizedSessionId!,
                        agentRunId: agentRunId,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _effectiveSeminarStatusAllowedToolIds(
    List<String> toolIds, {
    required int? bookId,
  }) {
    final matrix = bookId == null
        ? AiToolPermissionMatrix.seminarLibraryFallbackMatrix
        : AiToolPermissionMatrix.defaultMatrix;
    final out = <String>[];
    for (final rawToolId in toolIds) {
      final toolId = rawToolId.trim();
      if (toolId.isEmpty || out.contains(toolId)) continue;
      final rule = matrix.ruleFor(toolId);
      if (rule == null ||
          !rule.readOnly ||
          rule.requiresApproval ||
          rule.allowsExternalNetwork ||
          !matrix.isAllowed(scene: AiAgentScene.seminar, toolId: toolId)) {
        continue;
      }
      out.add(toolId);
    }
    return List.unmodifiable(out);
  }

  Widget _seminarAgentControlAction(
    AiSeminarRunCardMessagePart part, {
    required String actionId,
    required String? sessionId,
  }) {
    final label = _seminarAgentControlActionLabel(actionId);
    if (label.isEmpty) return const SizedBox.shrink();
    final agentRunId = _seminarAgentRunIdFromStatusPart(part);
    final normalizedSessionId = sessionId?.trim();
    if (!_seminarAgentControlActionIsExecutable(
      part,
      actionId: actionId,
      sessionId: sessionId,
    )) {
      return SeminarSnapshotTinyChip(label);
    }
    final executableAgentRunId = agentRunId!;
    final isSubmitting =
        _seminarCardSubmittingSessionIds.contains(normalizedSessionId);
    return ActionChip(
      key: ValueKey(
        'seminar-chat-card-agent-action-$actionId-$executableAgentRunId',
      ),
      avatar: Icon(
        _seminarAgentControlActionIcon(actionId),
        size: 16,
        color: isSubmitting
            ? ClaudePalette.secondary(context)
            : ClaudePalette.accent(context),
      ),
      label: Text(label),
      onPressed: isSubmitting
          ? null
          : () {
              if (actionId == 'close-agent') {
                unawaited(_closeSeminarAgentControl(
                  sessionId: normalizedSessionId!,
                  agentRunId: executableAgentRunId,
                ));
              } else if (actionId == 'wait-agent') {
                unawaited(_waitSeminarAgentControl(
                  sessionId: normalizedSessionId!,
                  agentRunId: executableAgentRunId,
                ));
              } else if (actionId == 'send-input') {
                setState(() {
                  if (_seminarAgentInputExpandedRunIds
                      .contains(executableAgentRunId)) {
                    _seminarAgentInputExpandedRunIds
                        .remove(executableAgentRunId);
                  } else {
                    _seminarAgentInputExpandedRunIds.add(executableAgentRunId);
                  }
                });
              } else if (actionId == 'resume-agent') {
                unawaited(_resumeSeminarAgentControl(
                  sessionId: normalizedSessionId!,
                  agentRunId: executableAgentRunId,
                ));
              } else if (actionId == 'retry-agent-control') {
                unawaited(_retrySeminarAgentControl(
                  sessionId: normalizedSessionId!,
                  agentRunId: executableAgentRunId,
                ));
              }
            },
      labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: ClaudePalette.fg(context),
            fontWeight: FontWeight.w700,
          ),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      visualDensity: VisualDensity.compact,
      backgroundColor:
          Theme.of(context).colorScheme.secondaryContainer.withValues(
                alpha: 0.72,
              ),
      side: BorderSide(color: ClaudePalette.divider(context)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  bool _seminarAgentControlActionIsExecutable(
    AiSeminarRunCardMessagePart part, {
    required String actionId,
    required String? sessionId,
  }) {
    final normalizedSessionId = sessionId?.trim();
    if (normalizedSessionId?.isNotEmpty != true) return false;
    final agentRunId = _seminarAgentRunIdFromStatusPart(part);
    if (agentRunId == null) return false;
    switch (actionId.trim()) {
      case 'wait-agent':
        return _isSeminarAgentStatusOneOf(
          part,
          const ['role-pending', 'role-running'],
        );
      case 'close-agent':
        return _isSeminarAgentStatusOneOf(
          part,
          const [
            'role-pending',
            'role-running',
            'role-waiting-input',
            'role-interrupted',
          ],
        );
      case 'send-input':
        return _isSeminarAgentStatusOneOf(part, const ['role-waiting-input']);
      case 'resume-agent':
        return _isSeminarAgentStatusOneOf(part, const ['role-interrupted']);
      case 'retry-agent-control':
        return _isSeminarAgentStatusOneOf(part, const ['role-error', 'failed']);
      default:
        return false;
    }
  }

  bool _isSeminarAgentStatusOneOf(
    AiSeminarRunCardMessagePart part,
    List<String> statuses,
  ) {
    final status = part.label?.trim();
    return status != null && statuses.contains(status);
  }

  IconData _seminarAgentControlActionIcon(String actionId) {
    switch (actionId.trim()) {
      case 'close-agent':
        return Icons.stop_circle_outlined;
      case 'wait-agent':
        return Icons.hourglass_empty_outlined;
      case 'send-input':
        return Icons.send_outlined;
      case 'resume-agent':
        return Icons.restart_alt_outlined;
      case 'retry-agent-control':
        return Icons.replay_outlined;
      default:
        return Icons.tune_outlined;
    }
  }

  TextEditingController _seminarAgentInputController(String agentRunId) {
    return _seminarAgentInputControllers.putIfAbsent(
      agentRunId,
      () => TextEditingController(),
    );
  }

  Widget _seminarAgentInputComposer({
    required String sessionId,
    required String agentRunId,
  }) {
    final controller = _seminarAgentInputController(agentRunId);
    final isSubmitting = _seminarCardSubmittingSessionIds.contains(sessionId);
    final hasText = controller.text.trim().isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            key: ValueKey('seminar-chat-card-agent-input-$agentRunId'),
            controller: controller,
            minLines: 1,
            maxLines: 3,
            enabled: !isSubmitting,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              labelText: _localizedSeminarCardText(
                zh: '输入给角色',
                en: 'Input for role',
              ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 6),
        IconButton.filledTonal(
          key: ValueKey('seminar-chat-card-agent-input-submit-$agentRunId'),
          tooltip: _localizedSeminarCardText(
            zh: '发送输入',
            en: 'Send input',
          ),
          onPressed: isSubmitting || !hasText
              ? null
              : () => unawaited(_sendSeminarAgentInputControl(
                    sessionId: sessionId,
                    agentRunId: agentRunId,
                  )),
          icon: const Icon(Icons.send_outlined, size: 18),
        ),
      ],
    );
  }

  Future<void> _sendSeminarAgentInputControl({
    required String sessionId,
    required String agentRunId,
  }) async {
    final normalizedSessionId = sessionId.trim();
    final normalizedRunId = agentRunId.trim();
    final controller = _seminarAgentInputController(normalizedRunId);
    final text = controller.text.trim();
    if (normalizedSessionId.isEmpty ||
        normalizedRunId.isEmpty ||
        text.isEmpty ||
        _seminarCardSubmittingSessionIds.contains(normalizedSessionId)) {
      return;
    }
    setState(() => _seminarCardSubmittingSessionIds.add(normalizedSessionId));
    final sent =
        await ref.read(aiChatProvider.notifier).sendSeminarRunCardAgentInput(
              seminarSessionId: normalizedSessionId,
              agentRunId: normalizedRunId,
              inputText: text,
            );
    if (sent) {
      try {
        await _readSeminarRuntimeNotifier(normalizedSessionId)
            .runPendingAgentControl(childRunId: normalizedRunId);
        await _syncSeminarRunCardSnapshotNow(
          normalizedSessionId,
          _readSeminarRuntimeState(normalizedSessionId),
        );
        await ref.read(aiChatProvider.notifier).refreshSeminarRunCardAgentGraph(
              seminarSessionId: normalizedSessionId,
            );
      } catch (_) {
        // Historical cards can record the control event without an active
        // scoped runtime to consume it immediately.
      }
    }
    if (!mounted) return;
    setState(() {
      _seminarCardSubmittingSessionIds.remove(normalizedSessionId);
      if (sent) {
        controller.clear();
        _seminarAgentInputExpandedRunIds.remove(normalizedRunId);
      }
    });
    if (!sent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localizedSeminarCardText(
              zh: '未能发送输入',
              en: 'Could not send input',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _resumeSeminarAgentControl({
    required String sessionId,
    required String agentRunId,
  }) async {
    final normalizedSessionId = sessionId.trim();
    final normalizedRunId = agentRunId.trim();
    if (normalizedSessionId.isEmpty ||
        normalizedRunId.isEmpty ||
        _seminarCardSubmittingSessionIds.contains(normalizedSessionId)) {
      return;
    }
    setState(() => _seminarCardSubmittingSessionIds.add(normalizedSessionId));
    final resumed =
        await ref.read(aiChatProvider.notifier).resumeSeminarRunCardAgent(
              seminarSessionId: normalizedSessionId,
              agentRunId: normalizedRunId,
            );
    if (resumed) {
      try {
        await _readSeminarRuntimeNotifier(normalizedSessionId)
            .runPendingAgentControl(childRunId: normalizedRunId);
        await _syncSeminarRunCardSnapshotNow(
          normalizedSessionId,
          _readSeminarRuntimeState(normalizedSessionId),
        );
        await ref.read(aiChatProvider.notifier).refreshSeminarRunCardAgentGraph(
              seminarSessionId: normalizedSessionId,
            );
      } catch (_) {
        // Historical cards can record the resume request without an active
        // scoped runtime to consume it immediately.
      }
    }
    if (!mounted) return;
    setState(
        () => _seminarCardSubmittingSessionIds.remove(normalizedSessionId));
    if (!resumed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localizedSeminarCardText(
              zh: '未能继续角色',
              en: 'Could not resume role',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _retrySeminarAgentControl({
    required String sessionId,
    String? agentRunId,
  }) async {
    final normalizedSessionId = sessionId.trim();
    final normalizedRunId = agentRunId?.trim();
    if (normalizedSessionId.isEmpty ||
        _seminarCardSubmittingSessionIds.contains(normalizedSessionId)) {
      return;
    }
    setState(() => _seminarCardSubmittingSessionIds.add(normalizedSessionId));
    try {
      if (normalizedRunId != null &&
          normalizedRunId.isNotEmpty &&
          normalizedRunId != normalizedSessionId) {
        final retried =
            await ref.read(aiChatProvider.notifier).retrySeminarRunCardAgent(
                  seminarSessionId: normalizedSessionId,
                  agentRunId: normalizedRunId,
                );
        if (!retried) {
          throw StateError('Could not record Seminar child retry request.');
        }
        try {
          await _readSeminarRuntimeNotifier(normalizedSessionId)
              .runPendingAgentControl(childRunId: normalizedRunId);
          await _syncSeminarRunCardSnapshotNow(
            normalizedSessionId,
            _readSeminarRuntimeState(normalizedSessionId),
          );
          await ref
              .read(aiChatProvider.notifier)
              .refreshSeminarRunCardAgentGraph(
                seminarSessionId: normalizedSessionId,
              );
        } catch (_) {
          // Historical cards can record the retry request without an active
          // scoped runtime to consume it immediately.
        }
      } else {
        await _readSeminarRuntimeNotifier(normalizedSessionId).retry();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localizedSeminarCardText(
              zh: '未能重新生成角色',
              en: 'Could not regenerate role',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(
          () => _seminarCardSubmittingSessionIds.remove(normalizedSessionId),
        );
      }
    }
  }

  Future<void> _closeSeminarAgentControl({
    required String sessionId,
    required String agentRunId,
  }) async {
    final normalizedSessionId = sessionId.trim();
    final normalizedRunId = agentRunId.trim();
    if (normalizedSessionId.isEmpty ||
        normalizedRunId.isEmpty ||
        _seminarCardSubmittingSessionIds.contains(normalizedSessionId)) {
      return;
    }
    setState(() => _seminarCardSubmittingSessionIds.add(normalizedSessionId));
    var cancelledActiveRuntime = false;
    final runtimeState = _readSeminarRuntimeState(normalizedSessionId);
    if (_isActiveSeminarRuntimeRoleRun(
      runtimeState,
      sessionId: normalizedSessionId,
      agentRunId: normalizedRunId,
    )) {
      _readSeminarRuntimeNotifier(normalizedSessionId).cancel();
      cancelledActiveRuntime = true;
    }
    final closed =
        await ref.read(aiChatProvider.notifier).closeSeminarRunCardAgent(
              seminarSessionId: normalizedSessionId,
              agentRunId: normalizedRunId,
            );
    if (!mounted) return;
    setState(
        () => _seminarCardSubmittingSessionIds.remove(normalizedSessionId));
    if (!closed && !cancelledActiveRuntime) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localizedSeminarCardText(
              zh: '未能停止角色',
              en: 'Could not stop role',
            ),
          ),
        ),
      );
    }
  }

  bool _isActiveSeminarRuntimeRoleRun(
    AiSeminarRuntimeState runtimeState, {
    required String sessionId,
    required String agentRunId,
  }) {
    if (runtimeState.status != AiSeminarRunStatus.running ||
        runtimeState.session?.id != sessionId) {
      return false;
    }
    final activeControlRunId = runtimeState.activeAgentControlRunId?.trim();
    if (activeControlRunId != null &&
        activeControlRunId.isNotEmpty &&
        activeControlRunId == agentRunId) {
      return true;
    }
    final activeRole = runtimeState.activeRole;
    if (activeRole == null) return false;
    final activeRoleRunId =
        '$sessionId:role-${activeRole.asString}-${runtimeState.turns.length}';
    return activeRoleRunId == agentRunId;
  }

  Future<void> _waitSeminarAgentControl({
    required String sessionId,
    required String agentRunId,
  }) async {
    final normalizedSessionId = sessionId.trim();
    final normalizedRunId = agentRunId.trim();
    if (normalizedSessionId.isEmpty ||
        normalizedRunId.isEmpty ||
        _seminarCardSubmittingSessionIds.contains(normalizedSessionId)) {
      return;
    }
    setState(() => _seminarCardSubmittingSessionIds.add(normalizedSessionId));
    final refreshed =
        await ref.read(aiChatProvider.notifier).waitSeminarRunCardAgent(
              seminarSessionId: normalizedSessionId,
              agentRunId: normalizedRunId,
            );
    if (!mounted) return;
    setState(
        () => _seminarCardSubmittingSessionIds.remove(normalizedSessionId));
    if (!refreshed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localizedSeminarCardText(
              zh: '未能等待角色',
              en: 'Could not wait for role',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _waitSeminarToolCallControl({
    required String sessionId,
    required String agentRunId,
    required String toolCallId,
  }) async {
    final normalizedSessionId = sessionId.trim();
    final normalizedRunId = agentRunId.trim();
    final normalizedToolCallId = toolCallId.trim();
    if (normalizedSessionId.isEmpty ||
        normalizedRunId.isEmpty ||
        normalizedToolCallId.isEmpty ||
        _seminarCardSubmittingSessionIds.contains(normalizedSessionId)) {
      return;
    }
    setState(() => _seminarCardSubmittingSessionIds.add(normalizedSessionId));
    final refreshed =
        await ref.read(aiChatProvider.notifier).waitSeminarRunCardToolCall(
              seminarSessionId: normalizedSessionId,
              agentRunId: normalizedRunId,
              toolCallId: normalizedToolCallId,
            );
    if (!mounted) return;
    setState(
        () => _seminarCardSubmittingSessionIds.remove(normalizedSessionId));
    if (!refreshed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localizedSeminarCardText(
              zh: '未能等待证据检索',
              en: 'Could not wait for evidence retrieval',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _cancelSeminarToolCallControl({
    required String sessionId,
    required String agentRunId,
    required String toolCallId,
  }) async {
    final normalizedSessionId = sessionId.trim();
    final normalizedRunId = agentRunId.trim();
    final normalizedToolCallId = toolCallId.trim();
    if (normalizedSessionId.isEmpty ||
        normalizedRunId.isEmpty ||
        normalizedToolCallId.isEmpty ||
        _seminarCardSubmittingSessionIds.contains(normalizedSessionId)) {
      return;
    }
    setState(() => _seminarCardSubmittingSessionIds.add(normalizedSessionId));
    var cancelledActiveRuntime = false;
    final runtimeState = _readSeminarRuntimeState(normalizedSessionId);
    if (_isActiveSeminarRuntimeRoleRun(
      runtimeState,
      sessionId: normalizedSessionId,
      agentRunId: normalizedRunId,
    )) {
      _readSeminarRuntimeNotifier(normalizedSessionId).cancel();
      cancelledActiveRuntime = true;
    }
    final cancelled =
        await ref.read(aiChatProvider.notifier).cancelSeminarRunCardToolCall(
              seminarSessionId: normalizedSessionId,
              agentRunId: normalizedRunId,
              toolCallId: normalizedToolCallId,
            );
    if (!mounted) return;
    setState(
        () => _seminarCardSubmittingSessionIds.remove(normalizedSessionId));
    if (!cancelled && !cancelledActiveRuntime) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localizedSeminarCardText(
              zh: '未能取消工具调用',
              en: 'Could not cancel tool call',
            ),
          ),
        ),
      );
    }
  }

  String? _seminarAgentRunIdFromStatusPart(
    AiSeminarRunCardMessagePart part,
  ) {
    final type = part.type.trim();
    if (type != 'director_state' && type != 'agent_status') return null;
    final agentRunId = part.agentRunId?.trim();
    if (agentRunId != null && agentRunId.isNotEmpty) return agentRunId;
    final id = part.id?.trim();
    if (id == null || id.isEmpty) return null;
    const marker = ':status:';
    final markerIndex = id.lastIndexOf(marker);
    if (markerIndex <= 0) return null;
    return id.substring(0, markerIndex);
  }

  String _seminarDirectorCueLabel(String? intent) {
    switch (intent?.trim()) {
      case 'ask-user':
        return _localizedSeminarCardText(
          zh: '主持人正在等待你的回应',
          en: 'The Director is waiting for your reply',
        );
      case 'refresh-evidence':
        return _localizedSeminarCardText(
          zh: '正在补充证据,已有发言保留',
          en: 'Adding evidence while keeping existing turns',
        );
      case 'synthesize':
        return _localizedSeminarCardText(
          zh: '正在整理总结…',
          en: 'Preparing summary...',
        );
      case 'pending':
        return _localizedSeminarCardText(
          zh: '研讨等待启动',
          en: 'Seminar is queued',
        );
      case 'running':
        return _localizedSeminarCardText(
          zh: '研讨正在运行',
          en: 'Seminar is running',
        );
      case 'end':
        return _localizedSeminarCardText(
          zh: '主持人已完成本轮研讨',
          en: 'The Director has completed this run',
        );
      case 'failed':
        return _localizedSeminarCardText(
          zh: '研讨运行失败',
          en: 'Seminar run failed',
        );
      case 'interrupted':
        return _localizedSeminarCardText(
          zh: '研讨已中断',
          en: 'Seminar was interrupted',
        );
      case 'stopped':
        return _localizedSeminarCardText(
          zh: '研讨已停止',
          en: 'Seminar was stopped',
        );
      case 'not-found':
        return _localizedSeminarCardText(
          zh: '研讨运行未找到',
          en: 'Seminar run was not found',
        );
      case 'role-pending':
        return _localizedSeminarCardText(
          zh: '角色等待生成',
          en: 'Role is queued',
        );
      case 'role-running':
        return _localizedSeminarCardText(
          zh: '角色正在生成',
          en: 'Role is running',
        );
      case 'role-completed':
        return _localizedSeminarCardText(
          zh: '角色已完成',
          en: 'Role completed',
        );
      case 'role-interrupted':
        return _localizedSeminarCardText(
          zh: '角色生成已中断',
          en: 'Role was interrupted',
        );
      case 'role-error':
        return _localizedSeminarCardText(
          zh: '角色生成失败',
          en: 'Role failed',
        );
      case 'role-shutdown':
        return _localizedSeminarCardText(
          zh: '角色生成已停止',
          en: 'Role was stopped',
        );
      case 'role-not-found':
        return _localizedSeminarCardText(
          zh: '角色运行未找到',
          en: 'Role run was not found',
        );
      default:
        return _localizedSeminarCardText(
          zh: '主持人正在安排下一步',
          en: 'The Director is planning the next step',
        );
    }
  }

  String _seminarAgentStatusLabel(String? status) {
    switch (status?.trim()) {
      case 'role-pending':
        return _localizedSeminarCardText(
          zh: '角色等待生成',
          en: 'Role is queued',
        );
      case 'role-running':
        return _localizedSeminarCardText(
          zh: '角色正在生成',
          en: 'Role is running',
        );
      case 'role-waiting-input':
        return _localizedSeminarCardText(
          zh: '角色等待输入',
          en: 'Role is waiting for input',
        );
      case 'role-completed':
        return _localizedSeminarCardText(
          zh: '角色已完成',
          en: 'Role completed',
        );
      case 'role-interrupted':
        return _localizedSeminarCardText(
          zh: '角色生成已中断',
          en: 'Role was interrupted',
        );
      case 'role-error':
        return _localizedSeminarCardText(
          zh: '角色生成失败',
          en: 'Role failed',
        );
      case 'role-shutdown':
        return _localizedSeminarCardText(
          zh: '角色生成已停止',
          en: 'Role was stopped',
        );
      case 'role-not-found':
        return _localizedSeminarCardText(
          zh: '角色运行未找到',
          en: 'Role run was not found',
        );
      default:
        return _localizedSeminarCardText(
          zh: '角色状态更新',
          en: 'Role status update',
        );
    }
  }

  String _seminarAgentControlActionLabel(String? action) {
    switch (action?.trim()) {
      case 'wait-agent':
        return _localizedSeminarCardText(
          zh: '等待角色',
          en: 'Wait for role',
        );
      case 'wait-tool-call':
        return _localizedSeminarCardText(
          zh: '证据检索中…',
          en: 'Retrieving evidence...',
        );
      case 'cancel-tool-call':
        return _localizedSeminarCardText(
          zh: '取消工具调用',
          en: 'Cancel tool call',
        );
      case 'send-input':
        return _localizedSeminarCardText(
          zh: '发送输入',
          en: 'Send input',
        );
      case 'resume-agent':
        return _localizedSeminarCardText(
          zh: '继续角色',
          en: 'Resume role',
        );
      case 'close-agent':
        return _localizedSeminarCardText(
          zh: '停止角色',
          en: 'Stop role',
        );
      case 'retry-agent-control':
        return _localizedSeminarCardText(
          zh: '重新生成角色',
          en: 'Regenerate role',
        );
      default:
        return '';
    }
  }

  String _seminarReaderTurnActionLabel(String? action) {
    final l10n = L10n.of(context);
    switch (action?.trim()) {
      case 'ask-role':
        return l10n.aiSeminarReaderActionAskRole;
      case 'refresh-evidence':
        return l10n.aiSeminarReaderActionRefreshEvidence;
      case 'synthesize':
        return l10n.aiSeminarReaderActionSynthesize;
      case 'wait-agent':
        return _localizedSeminarCardText(
          zh: '等待角色',
          en: 'Wait for role',
        );
      case 'wait-tool-call':
        return _localizedSeminarCardText(
          zh: '证据检索中…',
          en: 'Retrieving evidence...',
        );
      case 'cancel-tool-call':
        return _localizedSeminarCardText(
          zh: '取消工具调用',
          en: 'Cancel tool call',
        );
      case 'send-input':
        return _localizedSeminarCardText(
          zh: '发送输入',
          en: 'Send input',
        );
      case 'resume-agent':
        return _localizedSeminarCardText(
          zh: '继续角色',
          en: 'Resume role',
        );
      case 'close-agent':
        return _localizedSeminarCardText(
          zh: '停止角色',
          en: 'Stop role',
        );
      case 'retry-agent-control':
        return _localizedSeminarCardText(
          zh: '重新生成角色',
          en: 'Regenerate role',
        );
      case 'clarify':
        return l10n.aiSeminarReaderActionSendReply;
      default:
        return '';
    }
  }

  Widget _seminarSnapshotTimelineTurn(
    AiSeminarRunCardRoleSummary role,
    int turnNumber, {
    String? agentRunId,
    String? parentRunId,
  }) {
    final label = role.label.trim().isNotEmpty
        ? role.label.trim()
        : _seminarRoleFallbackLabel(role.roleId);
    final evidenceRefs = role.evidenceRefs
        .where((item) => !item.isEmpty)
        .toList(growable: false);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ClaudePalette.elevated(context).withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ClaudePalette.divider(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _seminarRoleIconById(role.roleId),
                size: 17,
                color: ClaudePalette.accent(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$turnNumber · $label',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: ClaudePalette.fg(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (role.summary.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      SeminarSnapshotExpandableText(
                        role.summary.trim(),
                        collapsedMaxLines: 4,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.32,
                            ),
                      ),
                    ],
                    SeminarSnapshotAgentTraceRows(
                      agentRunId,
                      parentRunId: parentRunId,
                      zh: _isChineseLocale,
                    ),
                    if (evidenceRefs.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      SeminarEvidenceReferenceChips(
                        evidenceRefs: evidenceRefs,
                        zh: _isChineseLocale,
                        onEvidencePressed: _jumpToSeminarEvidenceRow,
                      ),
                      const SizedBox(height: 7),
                      SeminarSnapshotDetailLabel(
                        _localizedSeminarCardText(
                          zh: '本轮证据',
                          en: 'Evidence used by this turn',
                        ),
                      ),
                      const SizedBox(height: 5),
                      for (var index = 0; index < evidenceRefs.length; index++)
                        SeminarSnapshotEvidenceTile(
                          evidenceRefs[index],
                          zh: _isChineseLocale,
                          missingSourceLabel: _seminarMissingSourceLabel,
                          sourceAction: _seminarSnapshotEvidenceSourceAction(
                            evidenceRefs[index].sourceRef,
                          ),
                          fallbackIndex: index + 1,
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seminarSnapshotDisagreementDetails(
    List<AiSeminarRunCardDisagreementDetail> details,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final detail in details)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ClaudePalette.divider(context)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SeminarSnapshotExpandableText(
                      detail.text.trim(),
                      collapsedMaxLines: 3,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: ClaudePalette.fg(context),
                            height: 1.32,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (detail.roleIds
                        .where((roleId) => roleId.trim().isNotEmpty)
                        .isNotEmpty) ...[
                      const SizedBox(height: 7),
                      SeminarSnapshotDetailLabel(
                        _localizedSeminarCardText(
                          zh: '关联角色',
                          en: 'Linked roles',
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _seminarRoleLabels(detail.roleIds),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.3,
                            ),
                      ),
                    ],
                    if (detail.evidenceRefs
                        .where((item) => !item.isEmpty)
                        .isNotEmpty) ...[
                      const SizedBox(height: 7),
                      SeminarSnapshotDetailLabel(
                        _localizedSeminarCardText(
                          zh: '关联证据',
                          en: 'Linked evidence',
                        ),
                      ),
                      const SizedBox(height: 5),
                      for (final evidence
                          in detail.evidenceRefs.where((item) => !item.isEmpty))
                        SeminarSnapshotEvidenceTile(
                          evidence,
                          zh: _isChineseLocale,
                          missingSourceLabel: _seminarMissingSourceLabel,
                          sourceAction: _seminarSnapshotEvidenceSourceAction(
                            evidence.sourceRef,
                          ),
                        ),
                    ],
                    SeminarSnapshotAgentTraceRows(
                      detail.agentRunId,
                      parentRunId: detail.parentRunId,
                      zh: _isChineseLocale,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _seminarSnapshotContradictionScanTiles(
    List<AiSeminarRunCardMessagePart> parts, {
    required String? sessionId,
  }) {
    final evidenceGapParts = parts
        .where(_seminarContradictionScanIsEvidenceGap)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _seminarSnapshotContradictionScanOverviewTile(
          parts,
          sessionId: sessionId,
        ),
        const SizedBox(height: 6),
        if (evidenceGapParts.length > 1) ...[
          _seminarSnapshotContradictionGapSummaryTile(evidenceGapParts),
          const SizedBox(height: 6),
        ],
        for (final part in parts)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer.withValues(
                      alpha: 0.24,
                    ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ClaudePalette.divider(context)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.radar_outlined,
                          size: 16,
                          color: ClaudePalette.accent(context),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _localizedSeminarCardText(
                              zh: '分歧扫描',
                              en: 'Contradiction scan',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: ClaudePalette.fg(context),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                    if (_seminarContradictionScanLabel(part.label) != null) ...[
                      const SizedBox(height: 7),
                      SeminarSnapshotDetailLabel(
                        _localizedSeminarCardText(
                          zh: '扫描结论',
                          en: 'Scan result',
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _seminarContradictionScanLabel(part.label)!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                    if (part.text?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 7),
                      SeminarSnapshotExpandableText(
                        part.text!.trim(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.fg(context),
                              height: 1.32,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                    if (part.roleIds
                        .where((roleId) => roleId.trim().isNotEmpty)
                        .isNotEmpty) ...[
                      const SizedBox(height: 7),
                      SeminarSnapshotDetailLabel(
                        _localizedSeminarCardText(
                          zh: '关联角色',
                          en: 'Linked roles',
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _seminarRoleLabels(part.roleIds),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.3,
                            ),
                      ),
                    ],
                    if (part.evidenceRefs
                        .where((item) => !item.isEmpty)
                        .isNotEmpty) ...[
                      const SizedBox(height: 7),
                      SeminarSnapshotDetailLabel(
                        _localizedSeminarCardText(
                          zh: '关联证据',
                          en: 'Linked evidence',
                        ),
                      ),
                      const SizedBox(height: 5),
                      for (final evidence
                          in part.evidenceRefs.where((item) => !item.isEmpty))
                        SeminarSnapshotEvidenceTile(
                          evidence,
                          zh: _isChineseLocale,
                          missingSourceLabel: _seminarMissingSourceLabel,
                          sourceAction: _seminarSnapshotEvidenceSourceAction(
                            evidence.sourceRef,
                          ),
                        ),
                    ],
                    SeminarSnapshotAgentTraceRows(
                      part.agentRunId,
                      parentRunId: part.parentRunId,
                      zh: _isChineseLocale,
                    ),
                    if (_seminarContradictionScanNeedsEvidence(part)) ...[
                      const SizedBox(height: 7),
                      SeminarSnapshotDetailLabel(
                        _localizedSeminarCardText(
                          zh: '缺少可追踪证据',
                          en: 'Traceable evidence missing',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _seminarSnapshotContradictionScanOverviewTile(
    List<AiSeminarRunCardMessagePart> parts, {
    required String? sessionId,
  }) {
    final evidenceGapCount =
        parts.where(_seminarContradictionScanIsEvidenceGap).length;
    final evidenceBackedCount = parts
        .where((part) =>
            !_seminarContradictionScanIsEvidenceGap(part) &&
            _seminarContradictionScanHasEvidence(part))
        .length;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ClaudePalette.accentTint(context).withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ClaudePalette.divider(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.query_stats_outlined,
                  size: 16,
                  color: ClaudePalette.accent(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _localizedSeminarCardText(
                      zh: '分歧扫描概览',
                      en: 'Contradiction scan overview',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: ClaudePalette.fg(context),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                SeminarSnapshotTinyChip(
                  _seminarCountLabel(
                    parts.length,
                    zhUnit: '条扫描',
                    enSingular: 'scan',
                    enPlural: 'scans',
                  ),
                ),
                SeminarSnapshotTinyChip(
                  _seminarCountLabel(
                    evidenceGapCount,
                    zhUnit: '条证据缺口',
                    enSingular: 'evidence gap',
                    enPlural: 'evidence gaps',
                  ),
                ),
                SeminarSnapshotTinyChip(
                  _seminarCountLabel(
                    evidenceBackedCount,
                    zhUnit: '条已有证据',
                    enSingular: 'evidence-backed scan',
                    enPlural: 'evidence-backed scans',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _seminarSnapshotContradictionGapSummaryTile(
    List<AiSeminarRunCardMessagePart> parts,
  ) {
    final previewTexts = parts
        .map((part) => part.text?.trim() ?? '')
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ClaudePalette.accentTint(context).withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ClaudePalette.divider(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.priority_high_outlined,
                  size: 16,
                  color: ClaudePalette.accent(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _localizedSeminarCardText(
                      zh: '证据缺口汇总',
                      en: 'Evidence gap summary',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: ClaudePalette.fg(context),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                SeminarSnapshotTinyChip(
                  _seminarCountLabel(
                    parts.length,
                    zhUnit: '条证据缺口',
                    enSingular: 'evidence gap',
                    enPlural: 'evidence gaps',
                  ),
                ),
              ],
            ),
            if (previewTexts.isNotEmpty) ...[
              const SizedBox(height: 7),
              for (final text in previewTexts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: SeminarSnapshotExpandableText(
                    text,
                    collapsedMaxLines: 2,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ClaudePalette.secondary(context),
                          height: 1.3,
                        ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String? _seminarContradictionScanLabel(String? label) {
    switch (label?.trim()) {
      case 'evidence-gap':
        return _localizedSeminarCardText(
          zh: '证据缺口',
          en: 'Evidence gap',
        );
      default:
        return null;
    }
  }

  bool _seminarContradictionScanNeedsEvidence(
    AiSeminarRunCardMessagePart part,
  ) {
    return _seminarContradictionScanIsEvidenceGap(part) &&
        !_seminarContradictionScanHasEvidence(part);
  }

  bool _seminarContradictionScanIsEvidenceGap(
    AiSeminarRunCardMessagePart part,
  ) {
    return part.label?.trim() == 'evidence-gap';
  }

  bool _seminarContradictionScanHasEvidence(
    AiSeminarRunCardMessagePart part,
  ) {
    return part.evidenceRefs.where((item) => !item.isEmpty).isNotEmpty;
  }

  Widget _seminarSnapshotDisagreementRebuttalTiles(
    List<AiSeminarRunCardMessagePart> parts,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final part in parts)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: ClaudePalette.accentTint(context).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ClaudePalette.divider(context)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.record_voice_over_outlined,
                          size: 16,
                          color: ClaudePalette.accent(context),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _localizedSeminarCardText(
                              zh: '分歧反驳回合',
                              en: 'Disagreement rebuttal turn',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: ClaudePalette.fg(context),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                    if (part.roleId?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 7),
                      SeminarSnapshotDetailLabel(
                        _localizedSeminarCardText(
                          zh: '角色',
                          en: 'Role',
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _seminarRoleFallbackLabel(part.roleId!.trim()),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.3,
                            ),
                      ),
                    ],
                    if (part.label?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 7),
                      SeminarSnapshotDetailLabel(
                        _localizedSeminarCardText(
                          zh: '目标分歧',
                          en: 'Target disagreement',
                        ),
                      ),
                      const SizedBox(height: 3),
                      SeminarSnapshotExpandableText(
                        part.label!.trim(),
                        collapsedMaxLines: 3,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.fg(context),
                              height: 1.32,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                    if (part.text?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 7),
                      SeminarSnapshotExpandableText(
                        part.text!.trim(),
                        collapsedMaxLines: 4,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                              height: 1.32,
                            ),
                      ),
                    ],
                    if (part.evidenceRefs
                        .where((item) => !item.isEmpty)
                        .isNotEmpty) ...[
                      const SizedBox(height: 7),
                      SeminarSnapshotDetailLabel(
                        _localizedSeminarCardText(
                          zh: '关联证据',
                          en: 'Linked evidence',
                        ),
                      ),
                      const SizedBox(height: 5),
                      for (final evidence
                          in part.evidenceRefs.where((item) => !item.isEmpty))
                        SeminarSnapshotEvidenceTile(
                          evidence,
                          zh: _isChineseLocale,
                          missingSourceLabel: _seminarMissingSourceLabel,
                          sourceAction: _seminarSnapshotEvidenceSourceAction(
                            evidence.sourceRef,
                          ),
                        ),
                    ],
                    SeminarSnapshotAgentTraceRows(
                      part.agentRunId,
                      parentRunId: part.parentRunId,
                      zh: _isChineseLocale,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _seminarRoleLabels(List<String> roleIds) {
    final seen = <String>{};
    final labels = <String>[];
    for (final raw in roleIds) {
      final roleId = raw.trim();
      if (roleId.isEmpty || !seen.add(roleId)) continue;
      labels.add(_seminarRoleFallbackLabel(roleId));
    }
    if (labels.isEmpty) {
      return _localizedSeminarCardText(zh: '未标明角色', en: 'Unlabeled role');
    }
    return labels.join(_isChineseLocale ? '、' : ', ');
  }

  Widget _seminarSnapshotWhiteboardSection({
    required List<String> disagreements,
    required List<String> openQuestions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SeminarSnapshotHeading(
          Icons.dashboard_customize_outlined,
          _localizedSeminarCardText(
            zh: '研讨白板',
            en: 'Shared whiteboard',
          ),
        ),
        const SizedBox(height: 6),
        if (disagreements.isNotEmpty)
          _seminarSnapshotWhiteboardGroup(
            icon: Icons.report_problem_outlined,
            label: _localizedSeminarCardText(
              zh: '分歧',
              en: 'Disagreements',
            ),
            items: disagreements,
          ),
        if (openQuestions.isNotEmpty)
          _seminarSnapshotWhiteboardGroup(
            icon: Icons.help_outline,
            label: _localizedSeminarCardText(
              zh: '开放问题',
              en: 'Open questions',
            ),
            items: openQuestions,
          ),
      ],
    );
  }

  Widget _seminarSnapshotReviewPreview({
    required String? synthesis,
    required int evidenceCount,
    AiSeminarSynthesis? activeSynthesis,
    List<AiSeminarRunCardMessagePart> reviewTriageParts =
        const <AiSeminarRunCardMessagePart>[],
  }) {
    final summary = synthesis?.trim() ?? '';
    final canPreviewHandoff = activeSynthesis != null &&
        activeSynthesis.readyForReview &&
        activeSynthesis.hasTraceableHandoff;
    final triageCandidateCardItems = _seminarReviewTriageItems(
      reviewTriageParts,
      label: 'knowledge-card',
    );
    final triageReviewQuestions = _seminarReviewTriageItems(
      reviewTriageParts,
      label: 'spaced-review',
    );
    final triageReasons = reviewTriageParts
        .where((part) => part.label?.trim() == 'reason')
        .map((part) => part.text?.trim() ?? '')
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
    final triageSuggestions = reviewTriageParts
        .where((part) => part.label?.trim() == 'ai-suggestion')
        .map((part) => part.text?.trim() ?? '')
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
    final triageRiskLevels = reviewTriageParts
        .where((part) => part.label?.trim() == 'risk')
        .map((part) => _seminarReviewRiskLabel(part.text))
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
    final triageSuggestedActions = reviewTriageParts
        .where((part) => part.label?.trim() == 'suggested-action')
        .map((part) => _seminarReviewSuggestedActionLabel(part.text))
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
    final candidateCardItems = canPreviewHandoff
        ? _seminarReviewCandidateCardItems(activeSynthesis)
        : triageCandidateCardItems;
    final reviewQuestions = canPreviewHandoff
        ? _seminarReviewQuestionItems(activeSynthesis)
        : triageReviewQuestions;
    final reviewReasons = canPreviewHandoff
        ? _seminarReviewReasonTexts(activeSynthesis)
        : triageReasons;
    final reviewSuggestions = canPreviewHandoff
        ? [
            if (_seminarReviewTriageSuggestionText(activeSynthesis)
                case final suggestion?)
              suggestion,
          ]
        : triageSuggestions;
    final reviewRiskLevels = canPreviewHandoff
        ? [_seminarReviewRiskLabel(_seminarReviewRiskLevel(activeSynthesis))]
        : triageRiskLevels;
    final reviewSuggestedActions = canPreviewHandoff
        ? [
            _seminarReviewSuggestedActionLabel(
              _seminarReviewSuggestedAction(activeSynthesis),
            ),
          ]
        : triageSuggestedActions;
    final candidateCardCount = canPreviewHandoff
        ? activeSynthesis.candidateCards.length
        : candidateCardItems.length;
    final flashcardCandidateCount = reviewQuestions.length;
    final hasPreviewPayload = canPreviewHandoff ||
        candidateCardItems.isNotEmpty ||
        reviewQuestions.isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ClaudePalette.divider(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SeminarSnapshotHeading(
              Icons.fact_check_outlined,
              _localizedSeminarCardText(
                zh: '异常处理预览',
                en: 'Exception triage preview',
              ),
            ),
            const SizedBox(height: 8),
            _seminarSnapshotReviewLine(
              Icons.outbox_outlined,
              _localizedSeminarCardText(
                zh: '只在低置信、冲突或来源异常时发送到 Review Inbox',
                en: 'Send to Review Inbox only for low-confidence, conflict, or broken-source cases',
              ),
            ),
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 8),
              SeminarSnapshotDetailLabel(
                _localizedSeminarCardText(
                  zh: '综合总结',
                  en: 'Synthesis',
                ),
              ),
              const SizedBox(height: 4),
              SeminarSnapshotExpandableText(
                summary,
                collapsedMaxLines: 5,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ClaudePalette.fg(context),
                      height: 1.35,
                    ),
              ),
            ],
            const SizedBox(height: 8),
            _seminarSnapshotReviewLine(
              Icons.link_outlined,
              _localizedSeminarCardText(
                zh: '可追踪证据：$evidenceCount 条',
                en: evidenceCount == 1
                    ? 'Traceable evidence: 1 source'
                    : 'Traceable evidence: $evidenceCount sources',
              ),
            ),
            if (reviewReasons.isNotEmpty) ...[
              const SizedBox(height: 8),
              SeminarSnapshotDetailLabel(
                _localizedSeminarCardText(
                  zh: '异常原因',
                  en: 'Review reasons',
                ),
              ),
              const SizedBox(height: 4),
              for (final reason in reviewReasons) ...[
                _seminarSnapshotReviewLine(
                  Icons.warning_amber_outlined,
                  reason,
                ),
                const SizedBox(height: 4),
              ],
            ],
            if (reviewSuggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              SeminarSnapshotDetailLabel(
                _localizedSeminarCardText(
                  zh: 'AI 预审建议',
                  en: 'AI triage suggestion',
                ),
              ),
              const SizedBox(height: 4),
              for (final suggestion in reviewSuggestions) ...[
                _seminarSnapshotReviewLine(
                  Icons.rule_outlined,
                  suggestion,
                ),
                const SizedBox(height: 4),
              ],
            ],
            if (reviewRiskLevels.isNotEmpty) ...[
              const SizedBox(height: 8),
              SeminarSnapshotDetailLabel(
                _localizedSeminarCardText(
                  zh: 'AI 风险等级',
                  en: 'AI risk level',
                ),
              ),
              const SizedBox(height: 4),
              for (final risk in reviewRiskLevels) ...[
                _seminarSnapshotReviewLine(
                  Icons.shield_outlined,
                  risk,
                ),
                const SizedBox(height: 4),
              ],
            ],
            if (reviewSuggestedActions.isNotEmpty) ...[
              const SizedBox(height: 8),
              SeminarSnapshotDetailLabel(
                _localizedSeminarCardText(
                  zh: '建议动作',
                  en: 'Suggested action',
                ),
              ),
              const SizedBox(height: 4),
              for (final action in reviewSuggestedActions) ...[
                _seminarSnapshotReviewLine(
                  Icons.task_alt_outlined,
                  action,
                ),
                const SizedBox(height: 4),
              ],
            ],
            if (hasPreviewPayload) ...[
              const SizedBox(height: 8),
              SeminarSnapshotDetailLabel(
                _localizedSeminarCardText(
                  zh: '异常送审内容',
                  en: 'Exception Review payload',
                ),
              ),
              const SizedBox(height: 4),
              _seminarSnapshotReviewLine(
                Icons.summarize_outlined,
                _localizedSeminarCardText(
                  zh: '综合总结：1 项',
                  en: 'Synthesis: 1 item',
                ),
              ),
              const SizedBox(height: 4),
              _seminarSnapshotReviewLine(
                Icons.style_outlined,
                _localizedSeminarCardText(
                  zh: '知识卡候选：$candidateCardCount 项',
                  en: candidateCardCount == 1
                      ? 'KnowledgeCard candidates: 1 item'
                      : 'KnowledgeCard candidates: $candidateCardCount items',
                ),
              ),
              if (candidateCardItems.isNotEmpty) ...[
                const SizedBox(height: 3),
                _seminarSnapshotReviewItems(
                  label: _localizedSeminarCardText(
                    zh: '知识卡候选明细',
                    en: 'KnowledgeCard candidate details',
                  ),
                  evidenceLabel: _localizedSeminarCardText(
                    zh: '候选证据',
                    en: 'Candidate evidence',
                  ),
                  items: candidateCardItems,
                ),
              ],
              const SizedBox(height: 4),
              _seminarSnapshotReviewLine(
                Icons.quiz_outlined,
                _localizedSeminarCardText(
                  zh: '复习候选：$flashcardCandidateCount 项',
                  en: flashcardCandidateCount == 1
                      ? 'Spaced Review candidates: 1 item'
                      : 'Spaced Review candidates: $flashcardCandidateCount items',
                ),
              ),
              if (reviewQuestions.isNotEmpty) ...[
                const SizedBox(height: 3),
                _seminarSnapshotReviewItems(
                  label: _localizedSeminarCardText(
                    zh: '复习候选明细',
                    en: 'Spaced Review candidate details',
                  ),
                  evidenceLabel: _localizedSeminarCardText(
                    zh: '综合证据',
                    en: 'Synthesis evidence',
                  ),
                  items: reviewQuestions,
                ),
              ],
            ],
            const SizedBox(height: 6),
            Text(
              _localizedSeminarCardText(
                zh: '普通学习保存请优先使用知识卡、复习或我的图谱。',
                en: 'For normal learning saves, use KnowledgeCard, Spaced Review, or My Graph first.',
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ClaudePalette.secondary(context),
                    height: 1.32,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _seminarReviewReasonTexts(AiSeminarSynthesis synthesis) {
    final disagreementCount = synthesis.disagreements
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .length;
    final cardCount = synthesis.candidateCards
        .map((item) => item.text.trim())
        .where((item) => item.isNotEmpty)
        .length;
    final reviewQuestionCount = synthesis.candidateReviewQuestions
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .length;

    return [
      if (disagreementCount > 0)
        _localizedSeminarCardText(
          zh: '存在未解决分歧：$disagreementCount 项',
          en: disagreementCount == 1
              ? 'Unresolved disagreements: 1 item'
              : 'Unresolved disagreements: $disagreementCount items',
        ),
      if (cardCount > 0)
        _localizedSeminarCardText(
          zh: '包含知识卡候选：$cardCount 项',
          en: cardCount == 1
              ? 'KnowledgeCard candidates included: 1 item'
              : 'KnowledgeCard candidates included: $cardCount items',
        ),
      if (reviewQuestionCount > 0)
        _localizedSeminarCardText(
          zh: '包含复习候选：$reviewQuestionCount 项',
          en: reviewQuestionCount == 1
              ? 'Spaced Review candidates included: 1 item'
              : 'Spaced Review candidates included: $reviewQuestionCount items',
        ),
    ];
  }

  String _seminarReviewRiskLevel(AiSeminarSynthesis synthesis) {
    final hasDisagreement = synthesis.disagreements
        .map((item) => item.trim())
        .any((item) => item.isNotEmpty);
    if (hasDisagreement) return 'medium';
    final hasReviewCandidates = synthesis.candidateCards
            .map((item) => item.text.trim())
            .any((item) => item.isNotEmpty) ||
        synthesis.candidateReviewQuestions
            .map((item) => item.trim())
            .any((item) => item.isNotEmpty);
    if (hasReviewCandidates) return 'low';
    return 'low';
  }

  String _seminarReviewSuggestedAction(AiSeminarSynthesis synthesis) {
    final hasDisagreement = synthesis.disagreements
        .map((item) => item.trim())
        .any((item) => item.isNotEmpty);
    if (hasDisagreement) return 'send-to-review';
    final hasReviewCandidates = synthesis.candidateCards
            .map((item) => item.text.trim())
            .any((item) => item.isNotEmpty) ||
        synthesis.candidateReviewQuestions
            .map((item) => item.trim())
            .any((item) => item.isNotEmpty);
    if (hasReviewCandidates) return 'preview-candidates';
    return 'send-to-review';
  }

  String _seminarReviewRiskLabel(String? risk) {
    switch (risk?.trim()) {
      case 'low':
        return _localizedSeminarCardText(zh: '低风险', en: 'Low risk');
      case 'medium':
        return _localizedSeminarCardText(zh: '中风险', en: 'Medium risk');
      case 'high':
        return _localizedSeminarCardText(zh: '高风险', en: 'High risk');
      case 'blocked':
        return _localizedSeminarCardText(zh: '已阻断', en: 'Blocked');
      default:
        return risk?.trim() ?? '';
    }
  }

  String _seminarReviewSuggestedActionLabel(String? action) {
    switch (action?.trim()) {
      case 'send-to-review':
        return _localizedSeminarCardText(
          zh: '送入异常中心',
          en: 'Send to exception center',
        );
      case 'preview-candidates':
        return _localizedSeminarCardText(
          zh: '先预览候选',
          en: 'Preview candidates first',
        );
      case 'save-inline':
        return _localizedSeminarCardText(
          zh: '当前页保存',
          en: 'Save inline',
        );
      case 'reject':
        return _localizedSeminarCardText(zh: '拒绝保存', en: 'Reject');
      default:
        return action?.trim() ?? '';
    }
  }

  String? _seminarReviewTriageSuggestionText(AiSeminarSynthesis synthesis) {
    final hasDisagreement = synthesis.disagreements
        .map((item) => item.trim())
        .any((item) => item.isNotEmpty);
    if (hasDisagreement) {
      return _localizedSeminarCardText(
        zh: '建议送审：未解决分歧需要人工确认。',
        en: 'Suggested review: unresolved disagreements need human confirmation.',
      );
    }
    final hasReviewCandidates = synthesis.candidateCards
            .map((item) => item.text.trim())
            .any((item) => item.isNotEmpty) ||
        synthesis.candidateReviewQuestions
            .map((item) => item.trim())
            .any((item) => item.isNotEmpty);
    if (hasReviewCandidates) {
      return _localizedSeminarCardText(
        zh: '建议先预览候选内容，确认无重复或来源异常后再送审。',
        en: 'Suggested review: inspect candidates for duplicates or source issues before sending.',
      );
    }
    return null;
  }

  List<_SeminarReviewPreviewItem> _seminarReviewCandidateCardItems(
    AiSeminarSynthesis synthesis,
  ) {
    final evidenceById = <String, AiSeminarEvidence>{
      for (final item in synthesis.evidence)
        if (item.id.trim().isNotEmpty) item.id.trim(): item,
    };
    return synthesis.candidateCards
        .map((card) {
          final title = card.text.trim();
          final evidenceRefs = card.evidenceRefIds
              .map((id) => evidenceById[id.trim()])
              .whereType<AiSeminarEvidence>()
              .where((item) => item.isTraceable)
              .map(
                (item) => AiSeminarRunCardEvidenceSnapshot(
                  id: item.id,
                  title: _seminarEvidenceSnapshotTitle(item),
                  snippet: _seminarEvidenceSnapshotSnippet(item),
                  sourceRef: item.sourceRef,
                ),
              )
              .where((item) => !item.isEmpty)
              .toList(growable: false);
          return _SeminarReviewPreviewItem(
            text: title,
            evidenceRefs: evidenceRefs,
          );
        })
        .where((item) => !item.isEmpty)
        .toList(growable: false);
  }

  List<_SeminarReviewPreviewItem> _seminarReviewTriageItems(
    List<AiSeminarRunCardMessagePart> parts, {
    required String label,
  }) {
    return parts
        .where((part) => part.label?.trim() == label)
        .map(
          (part) => _SeminarReviewPreviewItem(
            text: part.text?.trim() ?? '',
            evidenceRefs: part.evidenceRefs,
          ),
        )
        .where((item) => !item.isEmpty)
        .toList(growable: false);
  }

  List<_SeminarReviewPreviewItem> _seminarReviewQuestionItems(
    AiSeminarSynthesis synthesis,
  ) {
    final evidenceById = <String, AiSeminarEvidence>{
      for (final item in synthesis.evidence)
        if (item.id.trim().isNotEmpty) item.id.trim(): item,
    };
    final synthesisEvidenceRefs = synthesis.evidenceRefIds
        .map((id) => evidenceById[id.trim()])
        .whereType<AiSeminarEvidence>()
        .where((item) => item.isTraceable)
        .map(
          (item) => AiSeminarRunCardEvidenceSnapshot(
            id: item.id,
            title: _seminarEvidenceSnapshotTitle(item),
            snippet: _seminarEvidenceSnapshotSnippet(item),
            sourceRef: item.sourceRef,
          ),
        )
        .where((item) => !item.isEmpty)
        .toList(growable: false);
    final seen = <String>{};
    final items = <_SeminarReviewPreviewItem>[];
    for (final raw in synthesis.candidateReviewQuestions) {
      final question = raw.trim();
      if (question.isEmpty) continue;
      if (!seen.add(question.toLowerCase())) continue;
      items.add(
        _SeminarReviewPreviewItem(
          text: question,
          evidenceRefs: synthesisEvidenceRefs,
        ),
      );
    }
    return items;
  }

  Widget _seminarSnapshotReviewItems({
    required String label,
    required String evidenceLabel,
    required List<_SeminarReviewPreviewItem> items,
  }) {
    final visibleItems = items.toList(growable: false);
    final remainingCount = items.length - visibleItems.length;
    return Padding(
      padding: const EdgeInsets.only(left: 21),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SeminarSnapshotDetailLabel(label),
          const SizedBox(height: 3),
          for (final item in visibleItems)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '•',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                            ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SeminarSnapshotExpandableText(
                          item.text,
                          collapsedMaxLines: 2,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: ClaudePalette.secondary(context),
                                    height: 1.32,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  if (item.evidenceRefs.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SeminarSnapshotDetailLabel(
                            evidenceLabel,
                          ),
                          const SizedBox(height: 5),
                          for (final evidence in item.evidenceRefs)
                            SeminarSnapshotEvidenceTile(
                              evidence,
                              zh: _isChineseLocale,
                              missingSourceLabel: _seminarMissingSourceLabel,
                              sourceAction:
                                  _seminarSnapshotEvidenceSourceAction(
                                evidence.sourceRef,
                              ),
                              expandableSnippet: true,
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (remainingCount > 0)
            Text(
              _localizedSeminarCardText(
                zh: '还有 $remainingCount 项',
                en: remainingCount == 1
                    ? '1 more item'
                    : '$remainingCount more items',
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ClaudePalette.secondary(context),
                    height: 1.3,
                  ),
            ),
        ],
      ),
    );
  }

  Widget _seminarSnapshotReviewLine(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: ClaudePalette.accent(context)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ClaudePalette.secondary(context),
                  height: 1.32,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }

  Widget _seminarSnapshotWhiteboardGroup({
    required IconData icon,
    required String label,
    required List<String> items,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ClaudePalette.divider(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15, color: ClaudePalette.accent(context)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: ClaudePalette.fg(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '•',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                            ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SeminarSnapshotExpandableText(
                          item,
                          collapsedMaxLines: 3,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: ClaudePalette.secondary(context),
                                    height: 1.32,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _seminarRoleIconById(String roleId) {
    switch (roleId.trim()) {
      case 'critical':
        return Icons.report_problem_outlined;
      case 'supportive':
        return Icons.thumb_up_alt_outlined;
      case 'verifier':
        return Icons.verified_outlined;
      case 'synthesizer':
        return Icons.auto_awesome_outlined;
      default:
        return Icons.person_outline;
    }
  }

  String _seminarRoleFallbackLabel(String roleId) {
    switch (roleId.trim()) {
      case 'critical':
        return _localizedSeminarCardText(zh: '批判者', en: 'Critical');
      case 'supportive':
        return _localizedSeminarCardText(zh: '支持者', en: 'Supportive');
      case 'verifier':
        return _localizedSeminarCardText(zh: '核验者', en: 'Verifier');
      case 'synthesizer':
        return _localizedSeminarCardText(zh: '综合者', en: 'Synthesizer');
      default:
        return roleId.trim().isEmpty ? 'Role' : roleId.trim();
    }
  }

  String _seminarCountLabel(
    int count, {
    required String zhUnit,
    required String enSingular,
    required String enPlural,
  }) {
    if (_isChineseLocale) return '$count $zhUnit';
    return count == 1 ? '1 $enSingular' : '$count $enPlural';
  }

  String _seminarStatusLabel(String status, L10n l10n) {
    switch (status) {
      case 'draft':
        return l10n.seminarRunStatusDraft;
      case 'running':
        return l10n.seminarRunStatusRunning;
      case 'completed':
        return l10n.seminarRunStatusCompleted;
      case 'needs-evidence':
        return l10n.seminarRunStatusNeedsEvidence;
      case 'cancelled':
        return l10n.seminarRunStatusCancelled;
      case 'failed':
        return l10n.seminarRunStatusFailed;
      case 'ready':
      default:
        return _localizedSeminarCardText(
          zh: '待开始',
          en: 'Ready',
        );
    }
  }

  String _seminarRoleCountLabel(int count) {
    final safeCount = count <= 0 ? 3 : count;
    return _localizedSeminarCardText(
      zh: '$safeCount 个角色',
      en: '$safeCount roles',
    );
  }

  String _seminarEvidenceScopeSummary(
    List<String> scopeIds,
    L10n l10n,
  ) {
    final safeScopeIds =
        scopeIds.isEmpty ? const <String>['current-book'] : scopeIds;
    final separator = _isChineseLocale ? '、' : ', ';
    final labels = safeScopeIds
        .map((scopeId) => _seminarEvidenceScopeLabel(scopeId, l10n))
        .toList(growable: false)
        .join(separator);
    return _localizedSeminarCardText(
      zh: '证据：$labels',
      en: 'Evidence: $labels',
    );
  }

  String _seminarEvidenceScopeLabel(String scopeId, L10n l10n) {
    switch (scopeId) {
      case 'current-chapter':
        return l10n.seminarEvidenceScopeCurrentChapter;
      case 'current-book':
        return l10n.seminarEvidenceScopeCurrentBook;
      case 'library':
        return l10n.seminarEvidenceScopeLibrary;
      case 'notes':
        return l10n.seminarEvidenceScopeNotes;
      case 'memory':
        return l10n.seminarEvidenceScopeMemory;
      case 'concept-graph':
        return l10n.seminarEvidenceScopeConceptGraph;
      default:
        return scopeId;
    }
  }

  String _seminarSourceCountLabel(int count) {
    return _localizedSeminarCardText(
      zh: '$count 条来源',
      en: count == 1 ? '1 source' : '$count sources',
    );
  }

  String _localizedSeminarCardText({
    required String zh,
    required String en,
  }) {
    return _isChineseLocale ? zh : en;
  }

  String get _seminarLinkedEvidenceLabel => _localizedSeminarCardText(
        zh: '关联证据',
        en: 'Linked evidence',
      );

  String get _seminarMissingSourceLabel => _localizedSeminarCardText(
        zh: '来源缺失',
        en: 'Source missing',
      );

  bool get _isChineseLocale =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';

  Widget _buildUserMessageItem(_UserChatItem item) {
    final content = _extractUserTextFromHuman(item.message);
    final maxBubbleWidth = MediaQuery.sizeOf(context).width * 0.8;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 8.0, right: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: ClaudePalette.accentTint(context),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildScaledMessageContent(
                        _buildHumanMessageBody(item.message)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => _showEditUserMessageDialog(
                            item.index,
                            item.message,
                          ),
                          child: Text(L10n.of(context).commonEdit),
                        ),
                        TextButton(
                          onPressed: () => _copyPlainText(content),
                          child: Text(L10n.of(context).commonCopy),
                        ),
                        _buildMessageMemoryMenu(
                          text: content,
                          sourceType: 'chat',
                          messageNodeId: 'user:${item.index}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssistantGroupItem(
    _AssistantGroupChatItem item, {
    required int? lastHumanIndex,
    required ChatMessage? lastMessage,
  }) {
    var selected = _selectedVariantByUserIndex[item.groupKey] ??
        (item.variants.length - 1);
    if (selected < 0) selected = 0;
    if (selected >= item.variants.length) selected = item.variants.length - 1;

    final message = item.variants[selected];
    final content = message.contentAsString;
    final isStreaming =
        ref.watch(aiChatStreamingProvider) && identical(lastMessage, message);

    final canNavigateVariants =
        item.variants.length > 1 && !_isStreaming && !isStreaming;

    final isLastTurn =
        item.userIndex != null && item.userIndex == lastHumanIndex;
    final assistantReaderSourceRef = item.userIndex == null
        ? null
        : _readerSourceRefForUserIndex(item.userIndex!);
    final assistantSourceStatus = _knowledgeCardSourceStatus(
      readerSourceRef: assistantReaderSourceRef,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildScaledMessageContent(
            _buildAssistantSections(content, isStreaming),
          ),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              if (item.variants.length > 1)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 18),
                      onPressed: canNavigateVariants && selected > 0
                          ? () {
                              setState(() {
                                _selectedVariantByUserIndex[item.groupKey] =
                                    selected - 1;
                              });
                            }
                          : null,
                    ),
                    Text('${selected + 1}/${item.variants.length}'),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 18),
                      onPressed: canNavigateVariants &&
                              selected < item.variants.length - 1
                          ? () {
                              setState(() {
                                _selectedVariantByUserIndex[item.groupKey] =
                                    selected + 1;
                              });
                            }
                          : null,
                    ),
                  ],
                ),
              if (item.userIndex != null)
                TextButton(
                  onPressed: () => _confirmRegenerateFromUserIndex(
                    item.userIndex!,
                    isLastTurn: isLastTurn,
                  ),
                  child: Text(L10n.of(context).aiRegenerate),
                ),
              TextButton(
                onPressed: () => _copyMessageContent(content),
                child: Text(L10n.of(context).commonCopy),
              ),
              _buildKnowledgeCardSourceStatusChip(assistantSourceStatus),
              TextButton(
                onPressed: isStreaming
                    ? null
                    : () => _handleAssistantKnowledgeCardAction(
                          answer: _assistantMemoryText(content),
                          userPrompt: item.userIndex == null
                              ? null
                              : _humanTextAt(
                                  ref.read(aiChatProvider).asData?.value ??
                                      const <ChatMessage>[],
                                  item.userIndex!,
                                ),
                          messageNodeId:
                              'assistant-group:${item.groupKey}:$selected',
                          readerSourceRef: assistantReaderSourceRef,
                        ),
                child: Text(L10n.of(context).contextMenuKnowledgeCard),
              ),
              _buildMessageMemoryMenu(
                text: _assistantMemoryText(content),
                sourceType: 'chat',
                messageNodeId: 'assistant-group:${item.groupKey}:$selected',
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _buildCopyableText(ParsedReasoning parsed, String fallback) {
    final buffer = StringBuffer();
    var hasWrittenSection = false;

    void startSection() {
      if (hasWrittenSection) {
        buffer.writeln();
      } else {
        hasWrittenSection = true;
      }
    }

    // void appendField(String label, String? value) {
    //   final trimmed = value?.trim();
    //   if (trimmed != null && trimmed.isNotEmpty) {
    //     buffer.writeln('$label: $trimmed');
    //   }
    // }

    for (final entry in parsed.timeline) {
      switch (entry.type) {
        case ParsedReasoningEntryType.reply:
          final text = entry.text?.trim();
          if (text != null && text.isNotEmpty) {
            startSection();
            buffer.writeln(text);
          }
          break;
        case ParsedReasoningEntryType.tool:
          // final step = entry.toolStep;
          // if (step != null) {
          //   startSection();
          //   buffer.writeln('[${step.name} (${step.status})]');
          //   appendField('Input', step.input);
          //   appendField('Output', step.output);
          //   appendField('Error', step.error);
          // }
          break;
      }
    }

    final copyText = buffer.toString().trimRight();
    if (copyText.isEmpty) {
      return fallback;
    }
    return copyText;
  }

  /// Walk the raw assistant content top-to-bottom and produce a chronological
  /// list of inline parts (text / thinking / tool). Render-only; the original
  /// model content is never mutated.
  List<_AssistantPart> _splitIntoParts(String content) {
    final parts = <_AssistantPart>[];
    final thinkRegex = RegExp(r'<think>([\s\S]*?)<\/think>');

    void emitNonThink(String chunk) {
      if (chunk.isEmpty) return;
      // Reuse the existing reasoning parser for the non-think slice so that
      // `<tool-step .../>` tags are extracted in order alongside the
      // surrounding reply text.
      final parsed = parseReasoningContent(chunk);
      for (final entry in parsed.timeline) {
        if (entry.type == ParsedReasoningEntryType.reply) {
          final text = (entry.text ?? '').trim();
          if (text.isEmpty) continue;
          parts.add(_TextPart(entry.text!));
        } else {
          final step = entry.toolStep;
          if (step != null) parts.add(_ToolPart(step));
        }
      }
    }

    var cursor = 0;
    for (final match in thinkRegex.allMatches(content)) {
      if (match.start > cursor) {
        emitNonThink(content.substring(cursor, match.start));
      }
      final thinkText = (match.group(1) ?? '').trim();
      if (thinkText.isNotEmpty) {
        parts.add(_ThinkingPart(thinkText));
      }
      cursor = match.end;
    }
    if (cursor < content.length) {
      emitNonThink(content.substring(cursor));
    }
    return parts;
  }

  Widget _buildAssistantSections(String content, bool isStreaming) {
    final parts = _splitIntoParts(content);
    final children = <Widget>[];

    if (parts.isEmpty) {
      children.add(
        isStreaming
            ? Skeletonizer.zone(child: Bone.multiText())
            : const SizedBox.shrink(),
      );
    } else {
      for (final part in parts) {
        switch (part) {
          case _TextPart(:final md):
            children.add(StyledMarkdown(data: md, selectable: true));
          case _ThinkingPart(:final text):
            children.add(_buildInlineThinking(text));
          case _ToolPart(:final step):
            children.add(
              PTCollapsibleCard(
                icon: Icons.build_outlined,
                title: AiToolRegistry.displayNameForId(step.name,
                    l10n: L10n.of(context)),
                subtitle: step.name,
                iconTint: ToolTileBase.statusColorFor(step.status, context),
                body: _buildToolTile(step),
              ),
            );
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildInlineThinking(String text) {
    return PTCollapsibleCard(
      icon: Icons.psychology_outlined,
      title: L10n.of(context).aiSectionThinking,
      iconTint: ClaudePalette.tertiary(context),
      body: Text(
        text,
        style: TextStyle(
          fontStyle: FontStyle.italic,
          fontSize: 13,
          color: ClaudePalette.secondary(context),
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildToolTile(ParsedToolStep step) {
    if (step.name == 'bookshelf_organize') {
      return OrganizeBookshelfStepTile(step: step);
    }
    if (step.name == 'mindmap_draw') {
      return MindmapStepTile(step: step);
    }
    if (step.name == 'apply_book_tags') {
      return ApplyBookTagsStepTile(step: step);
    }
    return ToolStepTile(step: step, contentOnly: true);
  }

  void _showFontScaleSheet() {
    final l10n = L10n.of(context);
    const minScale = 0.8;
    const maxScale = 1.4;

    // Use a dialog instead of a bottom sheet.
    //
    // The AI chat itself can be hosted inside a bottom sheet (iPhone/iPad sheet
    // mode). Stacking a sheet-on-sheet may auto-dismiss on some platforms.
    double scale = Prefs().aiChatFontScale.clamp(minScale, maxScale);

    PTDialog.show<void>(
      context,
      title: l10n.font,
      content: SizedBox(
        width: 320,
        child: StatefulBuilder(
          builder: (context, setModalState) {
            void update(double next) {
              final clamped = next.clamp(minScale, maxScale).toDouble();
              setModalState(() {
                scale = clamped;
              });
              Prefs().aiChatFontScale = clamped;
              // Force rebuild to apply scale immediately.
              setState(() {});
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${(scale * 100).round()}%',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () => update(1.0),
                      child: Text(l10n.commonReset),
                    ),
                  ],
                ),
                Slider(
                  value: scale,
                  min: minScale,
                  max: maxScale,
                  divisions: 12,
                  label: '${(scale * 100).round()}%',
                  onChanged: update,
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        PTDialogAction(
          label: l10n.commonOk,
          isDefault: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  // --- Multimodal user message helpers ---

  static const String _textFileAttachmentPrefix = '[[file:';
  static const String _textFileAttachmentSuffix = ']]';

  String _extractUserTextFromHuman(HumanChatMessage message) {
    final content = message.content;
    if (content is ChatMessageContentText) {
      return content.text;
    }

    if (content is ChatMessageContentMultiModal) {
      final buffer = StringBuffer();
      for (final part in content.parts) {
        if (part is! ChatMessageContentText) continue;
        final text = part.text;
        if (text.startsWith(_textFileAttachmentPrefix)) {
          continue; // Hide file contents from chat bubble text.
        }
        final trimmed = text.trim();
        if (trimmed.isEmpty) continue;
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.write(trimmed);
      }
      return buffer.toString();
    }

    // Image-only message.
    return '';
  }

  String? _humanTextAt(List<ChatMessage> messages, int index) {
    if (index < 0 || index >= messages.length) return null;
    final message = messages[index];
    if (message is! HumanChatMessage) return null;
    final text = _extractUserTextFromHuman(message).trim();
    return text.isEmpty ? null : text;
  }

  List<_TextFileAttachmentInfo> _extractTextFilesFromHuman(
    HumanChatMessage message,
  ) {
    final content = message.content;
    if (content is! ChatMessageContentMultiModal) {
      return const [];
    }

    final out = <_TextFileAttachmentInfo>[];
    for (final part in content.parts) {
      if (part is! ChatMessageContentText) continue;
      final text = part.text;
      if (!text.startsWith(_textFileAttachmentPrefix)) continue;

      final suffixIndex = text.indexOf(_textFileAttachmentSuffix);
      if (suffixIndex <= _textFileAttachmentPrefix.length) continue;

      final filename =
          text.substring(_textFileAttachmentPrefix.length, suffixIndex).trim();
      final body =
          text.substring(suffixIndex + _textFileAttachmentSuffix.length);
      final normalizedBody = body.startsWith('\n') ? body.substring(1) : body;

      out.add(
        _TextFileAttachmentInfo(
          filename: filename.isEmpty ? 'text' : filename,
          text: normalizedBody,
        ),
      );
    }
    return out;
  }

  List<AttachmentItem> _extractAttachmentItemsFromHuman(
      HumanChatMessage message) {
    final items = <AttachmentItem>[];
    final files = _extractTextFilesFromHuman(message);
    for (final f in files) {
      items.add(
        AttachmentItem.textFile(
          filename: f.filename,
          bytes: Uint8List.fromList(utf8.encode(f.text)),
          text: f.text,
        ),
      );
    }

    final content = message.content;
    final images = <ChatMessageContentImage>[];
    if (content is ChatMessageContentImage) {
      images.add(content);
    } else if (content is ChatMessageContentMultiModal) {
      images.addAll(content.parts.whereType<ChatMessageContentImage>());
    }

    for (final imgPart in images) {
      try {
        final decoded = base64Decode(imgPart.data);
        items.add(AttachmentItem.image(bytes: decoded, base64: imgPart.data));
      } catch (_) {
        // ignore malformed image payloads
      }
    }

    return items;
  }

  List<Uint8List> _extractImagesFromHuman(HumanChatMessage message) {
    final content = message.content;
    final images = <ChatMessageContentImage>[];

    if (content is ChatMessageContentImage) {
      images.add(content);
    } else if (content is ChatMessageContentMultiModal) {
      images.addAll(content.parts.whereType<ChatMessageContentImage>());
    }

    final out = <Uint8List>[];
    for (final imgPart in images) {
      final key = imgPart.data;

      // LRU-ish: if present, move to the end.
      final cached = _decodedImageCache.remove(key);
      if (cached != null) {
        _decodedImageCache[key] = cached;
        out.add(cached);
        continue;
      }

      try {
        final decoded = base64Decode(key);
        _decodedImageCache[key] = decoded;
        out.add(decoded);

        while (_decodedImageCache.length > _decodedImageCacheMaxEntries) {
          _decodedImageCache.remove(_decodedImageCache.keys.first);
        }
      } catch (_) {
        // ignore
      }
    }
    return out;
  }

  Future<void> _showTextFileAttachmentActions(_TextFileAttachmentInfo f) async {
    final l10n = L10n.of(context);

    final choice = await PTDialog.show<String>(
      context,
      title: f.filename,
      content: SingleChildScrollView(
        child: Text(
          f.text.length > 2000 ? '${f.text.substring(0, 2000)}…' : f.text,
          style: TextStyle(
            fontSize: 14,
            color: ClaudePalette.secondary(context),
            height: 1.35,
          ),
        ),
      ),
      actions: [
        PTDialogAction(
          label: l10n.commonCancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        PTDialogAction(
          label: l10n.exportAndImportImport,
          isDefault: true,
          onPressed: () => Navigator.of(context).pop('import'),
        ),
      ],
    );

    if (choice == 'import') {
      await _importTextFileAttachmentToBookshelf(f);
    }
  }

  Future<void> _importTextFileAttachmentToBookshelf(
    _TextFileAttachmentInfo f,
  ) async {
    try {
      final cacheDir = await getAnxCacheDir();
      final dir = Directory(p.join(cacheDir.path, 'ai_text_import'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final safe = f.filename
          .replaceAll(RegExp(r'[\\/\n\r\t]'), '_')
          .replaceAll(':', '_');
      final base = safe.replaceAll(RegExp(r'\.[^.]+$'), '');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final outName = '${base.isEmpty ? 'text' : base}_$ts.txt';
      final outFile = File(p.join(dir.path, outName));

      await outFile.writeAsString(f.text, encoding: utf8);

      importBookList([outFile], context, ref);
      AnxToast.show(L10n.of(context).exportAndImportImport);
    } catch (e) {
      AnxToast.show(e.toString());
    }
  }

  void _showImageGallery(
    List<Uint8List> images, {
    int initialIndex = 0,
  }) {
    if (images.isEmpty) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (_) => _AiImageGalleryDialog(
        images: images,
        initialIndex: initialIndex,
      ),
    );
  }

  Widget _buildEditableAttachmentChip(
    AttachmentItem attachment, {
    required VoidCallback onRemove,
    VoidCallback? onPreview,
  }) {
    if (attachment.type == AttachmentType.image) {
      return Stack(
        children: [
          GestureDetector(
            onTap: onPreview,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                attachment.bytes,
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      );
    }

    return InputChip(
      avatar: const Icon(Icons.description, size: 18),
      label: Text(
        attachment.filename ?? 'text',
        overflow: TextOverflow.ellipsis,
      ),
      onDeleted: onRemove,
    );
  }

  Widget _buildHumanMessageBody(HumanChatMessage message) {
    final text = _extractUserTextFromHuman(message);
    final files = _extractTextFilesFromHuman(message);
    final images = _extractImagesFromHuman(message);

    final isLongMessage = text.length > 300;

    final children = <Widget>[];

    if (text.isNotEmpty) {
      children.add(_buildCollapsibleText(text, isLongMessage));
    }

    if (files.isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in files)
              Tooltip(
                message: f.text.length > 400
                    ? '${f.text.substring(0, 400)}…'
                    : f.text,
                child: ActionChip(
                  avatar: const Icon(Icons.description, size: 18),
                  label: Text(
                    f.filename,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () => _showTextFileAttachmentActions(f),
                ),
              ),
          ],
        ),
      );
    }

    if (images.isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '图片 ${images.length} 张',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
      );
      children.add(
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemBuilder: (context, index) {
              final bytes = images[index];
              return GestureDetector(
                onTap: () => _showImageGallery(images, initialIndex: index),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    children: [
                      Image.memory(
                        bytes,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.16),
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemCount: images.length,
          ),
        ),
      );
    }

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildCollapsibleText(String text, bool isLongMessage) {
    final style = _messageBodyTextStyle(context);
    if (!isLongMessage) {
      return SelectableText(
        text,
        style: style,
        selectionControls: MaterialTextSelectionControls(),
      );
    }
    return _CollapsibleText(text: text, style: style);
  }
}

sealed class _AssistantPart {
  const _AssistantPart();
}

class _TextPart extends _AssistantPart {
  const _TextPart(this.md);
  final String md;
}

class _ThinkingPart extends _AssistantPart {
  const _ThinkingPart(this.text);
  final String text;
}

class _ToolPart extends _AssistantPart {
  const _ToolPart(this.step);
  final ParsedToolStep step;
}

class _EditUserMessageResult {
  const _EditUserMessageResult({
    required this.text,
    required this.attachments,
  });

  final String text;
  final List<AttachmentItem> attachments;
}

class _TextFileAttachmentInfo {
  const _TextFileAttachmentInfo({
    required this.filename,
    required this.text,
  });

  final String filename;
  final String text;
}

class _AiImageGalleryDialog extends StatefulWidget {
  const _AiImageGalleryDialog({
    required this.images,
    this.initialIndex = 0,
  });

  final List<Uint8List> images;
  final int initialIndex;

  @override
  State<_AiImageGalleryDialog> createState() => _AiImageGalleryDialogState();
}

class _AiImageGalleryDialogState extends State<_AiImageGalleryDialog> {
  late final PageController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.images.length - 1);
    _controller = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          PhotoViewGallery.builder(
            pageController: _controller,
            itemCount: widget.images.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            builder: (context, index) {
              return PhotoViewGalleryPageOptions(
                imageProvider: MemoryImage(widget.images[index]),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3,
                heroAttributes:
                    PhotoViewHeroAttributes(tag: 'ai-chat-image-$index'),
              );
            },
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            loadingBuilder: (context, _) => const Center(
              child: CircularProgressIndicator(),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_currentIndex + 1}/${widget.images.length}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

sealed class _ChatItem {
  const _ChatItem();
}

class _UserChatItem extends _ChatItem {
  const _UserChatItem({
    required this.index,
    required this.message,
  });

  final int index;
  final HumanChatMessage message;
}

class _AssistantGroupChatItem extends _ChatItem {
  const _AssistantGroupChatItem({
    required this.groupKey,
    required this.userIndex,
    required this.variants,
  });

  /// Stable within the current in-memory message list.
  ///
  /// - For normal turns: equals [userIndex].
  /// - For orphan assistant groups: negative.
  final int groupKey;

  /// The index of the user message this assistant group belongs to.
  ///
  /// If null, this is an orphan assistant group.
  final int? userIndex;

  final List<AIChatMessage> variants;
}

class _SeminarReviewPreviewItem {
  const _SeminarReviewPreviewItem({
    required this.text,
    this.evidenceRefs = const <AiSeminarRunCardEvidenceSnapshot>[],
  });

  final String text;
  final List<AiSeminarRunCardEvidenceSnapshot> evidenceRefs;

  bool get isEmpty => text.trim().isEmpty && evidenceRefs.isEmpty;
}

class _AiChatKnowledgeSourceStatus {
  const _AiChatKnowledgeSourceStatus({
    required this.label,
    required this.tooltip,
    required this.traceable,
  });

  final String label;
  final String tooltip;
  final bool traceable;
}

class _CollapsibleText extends StatefulWidget {
  const _CollapsibleText({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_CollapsibleText> createState() => _CollapsibleTextState();
}

class _CollapsibleTextState extends State<_CollapsibleText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isExpanded)
          SelectableText(
            widget.text,
            style: widget.style,
            selectionControls: MaterialTextSelectionControls(),
          )
        else
          Stack(
            children: [
              SelectableText(
                widget.text.substring(0, 300),
                style: widget.style,
                selectionControls: MaterialTextSelectionControls(),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Theme.of(context)
                            .colorScheme
                            .surfaceContainer
                            .withValues(alpha: 0),
                        Theme.of(context).colorScheme.surfaceContainer,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        TextButton(
          onPressed: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          child: Text(_isExpanded
              ? L10n.of(context).aiHintCollapse
              : L10n.of(context).aiHintExpand),
        ),
      ],
    );
  }
}
