import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:papertok_reader/app/app_globals.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/providers/ai_chat.dart';
import 'package:papertok_reader/providers/ai_draft_input.dart';
import 'package:papertok_reader/providers/ai_history.dart';
import 'package:papertok_reader/providers/current_reading.dart';
import 'package:papertok_reader/service/ai/ai_services.dart';
import 'package:papertok_reader/service/ai/ai_history.dart';
import 'package:papertok_reader/models/ai_provider_meta.dart';
import 'package:papertok_reader/enums/ai_thinking_mode.dart';
import 'package:papertok_reader/service/memory/memory_candidate.dart';
import 'package:papertok_reader/service/memory/memory_workflow_policy.dart';
import 'package:papertok_reader/service/memory/memory_workflow_service.dart';
import 'package:papertok_reader/utils/toast/common.dart';
import 'package:papertok_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:papertok_reader/utils/ai_reasoning_parser.dart';
import 'package:papertok_reader/widgets/ai/tool_step_tile.dart';
import 'package:papertok_reader/widgets/ai/tool_tiles/apply_book_tags_step_tile.dart';
import 'package:papertok_reader/widgets/ai/tool_tiles/mindmap_step_tile.dart';
import 'package:papertok_reader/widgets/ai/tool_tiles/organize_bookshelf_step_tile.dart';
import 'package:papertok_reader/widgets/ai/tool_tiles/tool_tile_base.dart';
import 'package:papertok_reader/widgets/delete_confirm.dart';
import 'package:papertok_reader/widgets/markdown/styled_markdown.dart';
import 'package:papertok_reader/widgets/ai/attachment_picker_dialog.dart';
import 'package:papertok_reader/widgets/common/pt_bottom_sheet.dart';
import 'package:papertok_reader/widgets/common/pt_dialog.dart';
import 'package:papertok_reader/service/ai/skills/ai_skill.dart';
import 'package:papertok_reader/service/ai/skills/ai_skill_registry.dart';
import 'package:papertok_reader/service/knowledge/ai_chat_knowledge_card_producer.dart';
import 'package:papertok_reader/models/attachment_item.dart';
import 'package:papertok_reader/models/book_import_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/book.dart';
import 'package:papertok_reader/service/receive_file/share_inbox_cleanup_service.dart';
import 'package:papertok_reader/service/receive_file/share_inbox_paths.dart';
import 'package:papertok_reader/service/receive_file/share_safe_import.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/common/pt_collapsible_card.dart';
import 'package:papertok_reader/widgets/common/anx_segmented_button.dart';
import 'package:papertok_reader/utils/get_path/get_cache_dir.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:path/path.dart' as p;
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import 'package:papertok_reader/models/ai_quick_prompt_chip.dart';

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
    this.initialSourceRef,
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
  final SourceRef? initialSourceRef;

  @override
  ConsumerState<AiChatStream> createState() => AiChatStreamState();
}

enum _MessageMemoryAction {
  saveToDaily,
  saveToLongTerm,
  addToReviewInbox,
}

class AiChatStreamState extends ConsumerState<AiChatStream> {
  final TextEditingController inputController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final MemoryWorkflowService _memoryWorkflow = MemoryWorkflowService();
  late final AiChatKnowledgeCardProducer _chatKnowledgeCards =
      widget.chatKnowledgeCardProducer ?? AiChatKnowledgeCardProducer();

  bool _suppressDraftSync = false;

  void _onDraftInputChanged() {
    if (_suppressDraftSync) return;
    if (inputController.text.trim().isEmpty) {
      _draftSourceRef = null;
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

  // Auto-scroll behavior:
  // - Do NOT jump to bottom when opening the panel.
  // - While streaming, only keep scrolling if the user is already near bottom.
  bool _pinnedToBottom = false;

  // For each user turn, the assistant may have multiple generated variants.
  // We keep a lightweight UI-only selection index per turn.
  final Map<int, int> _selectedVariantByUserIndex = {};
  final Map<int, SourceRef> _sourceRefByUserIndex = {};
  SourceRef? _draftSourceRef;
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
      final max = _scrollController.position.maxScrollExtent;
      final offset = _scrollController.offset;
      // Within 120px counts as "at bottom".
      _pinnedToBottom = (max - offset) < 120;
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
    try {
      _scrollController.removeListener(_handleScroll);
    } catch (_) {}
    if (_ownsScrollController) {
      _scrollController.dispose();
    }
    super.dispose();
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
      case 'seminar_mode':
        return l.aiSkillSeminarModeName;
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
      case 'seminar_mode':
        return l.aiSkillSeminarModeDesc;
      default:
        return skill.description;
    }
  }

  static const String _noSkillSentinel = '__none__';

  Widget _buildSkillButton(BuildContext context) {
    final activeId = Prefs().activeAiSkillId;
    final active = AiSkillRegistry.byId(activeId);
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
        final skills = AiSkillRegistry.allSkills();
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

  void _scrollToBottom({bool force = false}) {
    if (!force && !_pinnedToBottom) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (_scrollController.hasClients) {
          final target = _scrollController.position.maxScrollExtent;
          // Use jumpTo during streaming to reduce jank.
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
    final draftSourceRef = _draftSourceRef;

    inputController.clear();
    _draftSourceRef = null;

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
    final activeSkill = AiSkillRegistry.byId(Prefs().activeAiSkillId);

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

    await PTBottomSheet.show<void>(
      context,
      title: 'Add to Chat',
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            final provider = _currentProvider;
            final thinkingMode = _thinkingModeForProvider(provider.id);
            final thinkingOn = thinkingMode != AiThinkingMode.off;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    bigCard(
                      icon: Icons.photo_camera_outlined,
                      label: 'Camera',
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _showAttachmentPicker();
                      },
                    ),
                    const SizedBox(width: 10),
                    bigCard(
                      icon: Icons.photo_library_outlined,
                      label: 'Photos',
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _showAttachmentPicker();
                      },
                    ),
                    const SizedBox(width: 10),
                    bigCard(
                      icon: Icons.folder_outlined,
                      label: 'Files',
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
                  title: 'Web search',
                  value: _webSearchEnabled,
                  onChanged: (v) {
                    setLocalState(() => _webSearchEnabled = v);
                    setState(() {});
                  },
                ),
                toggleRow(
                  icon: Icons.psychology_outlined,
                  title: 'Extended thinking',
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
                navRow(
                  icon: Icons.style_outlined,
                  title: 'Choose style',
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
                  title: 'Add to project',
                  onTap: () {
                    Navigator.of(ctx).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showSkillPickerSheet() async {
    final l10n = L10n.of(context);
    final activeId = Prefs().activeAiSkillId;
    await PTBottomSheet.show<void>(
      context,
      title: 'Choose style',
      builder: (ctx) {
        final skills = AiSkillRegistry.allSkills();
        return Column(
          mainAxisSize: MainAxisSize.min,
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
              PTPickerRow<String>(
                value: skill.id,
                groupValue: activeId ?? '',
                title: _localizedSkillName(context, skill),
                subtitle: _localizedSkillDesc(context, skill),
                leading: Icons.auto_fix_high,
                onChanged: (v) {
                  Prefs().activeAiSkillId = v;
                  setState(() {});
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        );
      },
    );
  }

  void prefillDraft({
    String? message,
    List<AttachmentItem>? attachments,
    bool replaceAttachments = false,
    SourceRef? sourceRef,
  }) {
    if (message != null) {
      _draftSourceRef = sourceRef;
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
        : dailyStrategy == MemoryWorkflowDailyStrategy.autoDaily
            ? l10n.aiChatEndSessionBodyAutoDaily
            : l10n.aiChatEndSessionBodyReviewInbox;
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
        } else if (result.writesDailyDirectly) {
          AnxToast.show(
            l10n.memorySessionDigestSavedToDaily(result.candidates.length),
          );
        } else {
          AnxToast.show(
            l10n.memorySessionDigestAddedToInbox(result.candidates.length),
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

    try {
      switch (action) {
        case _MessageMemoryAction.saveToDaily:
          await _memoryWorkflow.saveToDaily(
            text: normalized,
            sourceType: sourceType,
            conversationId: conversationId,
            messageNodeId: messageNodeId,
            displayText: normalized,
            sourcePointer: conversationId == null
                ? messageNodeId
                : messageNodeId == null
                    ? conversationId
                    : '$conversationId#$messageNodeId',
            rawContextRef:
                conversationId == null ? null : 'conversation:$conversationId',
            triggerKind: 'manual_save',
          );
          if (!mounted) return;
          AnxToast.show(l10n.memorySavedToDaily);
          break;
        case _MessageMemoryAction.saveToLongTerm:
          final confirmed = await _confirmLongTermWrite(normalized);
          if (!confirmed) {
            return;
          }
          await _memoryWorkflow.saveToLongTerm(
            text: normalized,
            sourceType: sourceType,
            conversationId: conversationId,
            messageNodeId: messageNodeId,
            displayText: normalized,
            sourcePointer: conversationId == null
                ? messageNodeId
                : messageNodeId == null
                    ? conversationId
                    : '$conversationId#$messageNodeId',
            rawContextRef:
                conversationId == null ? null : 'conversation:$conversationId',
            triggerKind: 'manual_save',
          );
          if (!mounted) return;
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
            sourcePointer: conversationId == null
                ? messageNodeId
                : messageNodeId == null
                    ? conversationId
                    : '$conversationId#$messageNodeId',
            rawContextRef:
                conversationId == null ? null : 'conversation:$conversationId',
            triggerKind: 'manual_save',
          );
          if (!mounted) return;
          AnxToast.show(l10n.memoryAddedToReviewInbox);
          break;
      }
    } catch (e) {
      if (!mounted) return;
      AnxToast.show('${l10n.memoryWorkflowActionFailed}: $e');
    }
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
    final useCurrentReaderFallback =
        readerSourceRef != null || !chatNotifier.isLoadedHistoryConversation;
    chatNotifier.persistCurrentConversation(ref);
    final reading = ref.read(currentReadingProvider);
    final book =
        useCurrentReaderFallback && reading.isReading ? reading.book : null;

    try {
      final result = await _chatKnowledgeCards.createFromAssistantAnswer(
        assistantAnswer: normalizedAnswer,
        userPrompt: userPrompt,
        conversationId: conversationId,
        messageNodeId: messageNodeId,
        modelId: _modelLabel(_selectedProviderId),
        bookId: book?.id,
        bookTitle: book?.title,
        cfi: useCurrentReaderFallback && reading.isReading ? reading.cfi : null,
        chapterTitle: useCurrentReaderFallback && reading.isReading
            ? reading.chapterTitle
            : null,
        readerSourceRef: readerSourceRef,
      );
      if (!mounted) return;
      final message = result.addedToReviewInbox
          ? (result.inserted
              ? l10n.knowledgeCardAddedToReviewInbox
              : l10n.knowledgeCardAlreadyInReviewInbox)
          : l10n.knowledgeCardAlreadySaved;
      AnxToast.show(message);
    } catch (_) {
      if (!mounted) return;
      AnxToast.show(l10n.knowledgeCardAddFailed);
    }
  }

  SourceRef? _readerSourceRefForUserIndex(int userIndex) {
    return _sourceRefByUserIndex[userIndex] ??
        ref.read(aiChatProvider.notifier).sourceRefForMessageIndex(userIndex);
  }

  Widget _buildMessageMemoryMenu({
    required String text,
    required String sourceType,
    String? messageNodeId,
  }) {
    final l10n = L10n.of(context);
    final enabled = text.trim().isNotEmpty;

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
        PopupMenuItem(
          value: _MessageMemoryAction.saveToDaily,
          child: Text(l10n.memorySaveToDailyAction),
        ),
        PopupMenuItem(
          value: _MessageMemoryAction.saveToLongTerm,
          child: Text(l10n.memorySaveToLongTermAction),
        ),
        PopupMenuItem(
          value: _MessageMemoryAction.addToReviewInbox,
          child: Text(l10n.memoryAddToReviewInboxAction),
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

  Widget _buildMessageList(List<ChatMessage> messages) {
    final lastHumanIndex = _findLastHumanIndex(messages);
    final isStreaming = ref.watch(aiChatStreamingProvider);

    return ListView.builder(
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
  }

  List<_ChatItem> _buildChatItems(List<ChatMessage> messages) {
    final items = <_ChatItem>[];
    var i = 0;
    while (i < messages.length) {
      final message = messages[i];
      if (message is HumanChatMessage) {
        items.add(_UserChatItem(index: i, message: message));

        final variants = <AIChatMessage>[];
        var j = i + 1;
        while (j < messages.length && messages[j] is AIChatMessage) {
          variants.add(messages[j] as AIChatMessage);
          j++;
        }
        if (variants.isNotEmpty) {
          items.add(
            _AssistantGroupChatItem(
              groupKey: i,
              userIndex: i,
              variants: variants,
            ),
          );
        }
        i = j;
        continue;
      }

      if (message is AIChatMessage) {
        // Orphan assistant messages (should be rare). Group them to keep the UI
        // consistent.
        final variants = <AIChatMessage>[];
        var j = i;
        while (j < messages.length && messages[j] is AIChatMessage) {
          variants.add(messages[j] as AIChatMessage);
          j++;
        }
        items.add(
          _AssistantGroupChatItem(
            groupKey: -(i + 1),
            userIndex: null,
            variants: variants,
          ),
        );
        i = j;
        continue;
      }

      i++;
    }

    return items;
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

    final maxBubbleWidth = MediaQuery.sizeOf(context).width * 0.8;

    Widget? footer;
    if (!isUser) {
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
                          : _buildAssistantSections(content, isStreaming),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _buildVariantSwitcher(index, isStreaming),
                        const SizedBox(width: 4),
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
                        ] else ...[
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
                                      readerSourceRef: prevHumanIndex == null
                                          ? null
                                          : _readerSourceRefForUserIndex(
                                              prevHumanIndex,
                                            ),
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildScaledMessageContent(
            _buildAssistantSections(content, isStreaming),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
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
                    const SizedBox(width: 4),
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
                          readerSourceRef: item.userIndex == null
                              ? null
                              : _readerSourceRefForUserIndex(item.userIndex!),
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
