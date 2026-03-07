import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/app/app_globals.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/ai_chat.dart';
import 'package:anx_reader/providers/ai_draft_input.dart';
import 'package:anx_reader/providers/ai_history.dart';
import 'package:anx_reader/service/ai/ai_services.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/models/ai_provider_meta.dart';
import 'package:anx_reader/enums/ai_thinking_mode.dart';
import 'package:anx_reader/service/memory/memory_candidate.dart';
import 'package:anx_reader/service/memory/memory_workflow_policy.dart';
import 'package:anx_reader/service/memory/memory_workflow_service.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/widgets/ai/ai_collapsible_section.dart';
import 'package:anx_reader/widgets/ai/tool_step_tile.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/apply_book_tags_step_tile.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/mindmap_step_tile.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/organize_bookshelf_step_tile.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:anx_reader/widgets/delete_confirm.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown.dart';
import 'package:anx_reader/widgets/ai/attachment_picker_dialog.dart';
import 'package:anx_reader/models/attachment_item.dart';
import 'package:anx_reader/models/book_import_item.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/service/receive_file/share_inbox_cleanup_service.dart';
import 'package:anx_reader/service/receive_file/share_inbox_paths.dart';
import 'package:anx_reader/service/receive_file/share_safe_import.dart';
import 'package:anx_reader/utils/get_path/get_cache_dir.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:path/path.dart' as p;

import 'package:anx_reader/models/ai_quick_prompt_chip.dart';

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

  bool _suppressDraftSync = false;

  void _onDraftInputChanged() {
    if (_suppressDraftSync) return;
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

  void _onProviderSelected(String providerId) {
    if (_isStreaming || providerId == _selectedProviderId) return;
    if (!_isProviderSelectable(providerId)) return;

    Prefs().selectedAiService = providerId;
    setState(() {
      _selectedProviderId = providerId;
    });
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

  Future<void> _editThinkingMode() async {
    if (_isStreaming) return;

    final l10n = L10n.of(context);
    final provider = _currentProvider;
    final supported = _supportedThinkingModes(provider);

    final current = _thinkingModeForProvider(provider.id);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(12),
            children: [
              ListTile(
                title: Text(l10n.aiThinkingTitle),
                subtitle: Text(provider.name),
              ),
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
                  },
                ),
              for (final mode in AiThinkingMode.values)
                RadioListTile<AiThinkingMode>(
                  value: mode,
                  groupValue: current,
                  title: Text(_thinkingModeLabel(mode, l10n)),
                  secondary: Icon(_thinkingIcon(mode)),
                  onChanged: supported.contains(mode)
                      ? (v) {
                          if (v == null) return;
                          final next = Map<String, String>.from(
                            Prefs().getAiConfig(provider.id),
                          );
                          next['thinking_mode'] = aiThinkingModeToString(v);
                          Prefs().saveAiConfig(provider.id, next);
                          setState(() {});
                          Navigator.of(context).pop();
                        }
                      : null,
                ),
            ],
          ),
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

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) {
          final cached = Prefs().getAiModelsCacheV1(provider.id)?.models ??
              const <String>[];

          return AlertDialog(
            title: Text(l10n.aiChatEditModelTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (cached.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: cached.contains(controller.text.trim())
                        ? controller.text.trim()
                        : null,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: l10n.aiChatModelLabel,
                    ),
                    items: cached
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(m, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (v) {
                      if (v == null) return;
                      controller.text = v;
                    },
                  )
                else
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: l10n.aiChatModelLabel,
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.commonSave),
              ),
            ],
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
    return SafeArea(
      child: Column(
        children: [
          ListTile(
            title: Text(L10n.of(context).conversationHistory),
            trailing: DeleteConfirm(
              delete: () => _confirmClearHistory(context),
              deleteIcon: Icon(Icons.delete_sweep),
            ),
          ),
          Expanded(
            child: historyState.when(
              data: (items) {
                if (items.isEmpty) {
                  return Center(
                    child: Text(L10n.of(context).noConversationTip),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final entry = items[index];
                    return _buildHistoryTile(context, entry);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(
                child: Text(L10n.of(context).failedToLoadHistoryTip),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTile(BuildContext context, AiChatHistoryEntry entry) {
    final provider = _providerByIdFromPrefs(entry.serviceId) ??
        _providerById(entry.serviceId);
    final statusColor =
        entry.completed ? Colors.green : Theme.of(context).colorScheme.tertiary;
    final title = _deriveTitle(entry);
    final subtitle = _buildHistorySubtitle(provider, entry);

    return FilledContainer(
      margin: EdgeInsets.symmetric(horizontal: 8),
      padding: EdgeInsets.all(8),
      radius: 15,
      child: GestureDetector(
        onTap: () => _handleHistoryTap(context, entry),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    Text(
                      _formatTimestamp(entry.updatedAt),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                Spacer(),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.circle, size: 10, color: statusColor),
                    DeleteConfirm(
                        delete: () => _confirmDeleteHistory(context, entry)),
                  ],
                ),
              ],
            ),
          ],
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
    for (final message in entry.messages) {
      if (message is HumanChatMessage) {
        final content = _extractUserTextFromHuman(message).trim();
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

    Navigator.of(context).pop();
    _pinnedToBottom = true;
    _scrollToBottom(force: true);
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
  }

  // Streaming lifecycle is managed by [aiChatProvider] so UI minimize/close
  // does not interrupt generation.

  void _sendMessage() {
    if (_isStreaming) {
      return;
    }

    final message = inputController.text.trim();
    if (message.isEmpty && _attachments.isEmpty) return;

    inputController.clear();

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
        );
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

  void _editUserMessageAndRegenerate(int userIndex, String newText) {
    if (_isStreaming) {
      return;
    }

    _pinnedToBottom = true;
    ref.read(aiChatProvider.notifier).startStreaming(
          newText,
          true,
          regenerateFromUserIndex: userIndex,
          replaceUserMessage: true,
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
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(L10n.of(context).aiChatRegenerateFromHereConfirmTitle),
            content: Text(L10n.of(context).aiChatRegenerateFromHereConfirmBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(L10n.of(context).commonCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(L10n.of(context).commonConfirm),
              ),
            ],
          );
        },
      );
      if (confirmed != true) {
        return;
      }
    }

    _regenerateFromUserIndex(userIndex);
  }

  Future<void> _showEditUserMessageDialog(
    int userIndex,
    String currentText,
  ) async {
    if (_isStreaming) {
      return;
    }

    final controller = TextEditingController(text: currentText);
    try {
      final edited = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(L10n.of(context).aiChatEditUserMessageTitle),
            content: TextField(
              controller: controller,
              maxLength: 20000,
              maxLines: 6,
              minLines: 1,
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(L10n.of(context).commonCancel),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(controller.text.trim());
                },
                child: Text(L10n.of(context).commonSave),
              ),
            ],
          );
        },
      );

      if (edited == null) {
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(L10n.of(context).aiChatRegenerateFromHereConfirmTitle),
            content: Text(L10n.of(context).aiChatRegenerateFromHereConfirmBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(L10n.of(context).commonCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(L10n.of(context).commonConfirm),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        return;
      }

      _editUserMessageAndRegenerate(userIndex, edited);
    } finally {
      controller.dispose();
    }
  }

  void _useQuickPrompt(String prompt) {
    inputController.text = '$prompt ${inputController.text}';
    _sendMessage();
  }

  void _clearMessage() {
    if (_isStreaming) {
      return;
    }

    unawaited(_endCurrentSession());
  }

  Future<void> _showAttachmentPicker() async {
    if (_isStreaming) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return AttachmentPickerDialog(
          onPicked: (items) {
            _addAttachments(items);
          },
        );
      },
    );
  }

  void prefillDraft({
    String? message,
    List<AttachmentItem>? attachments,
    bool replaceAttachments = false,
  }) {
    if (message != null) {
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

    var imageCount =
        _attachments.where((a) => a.type == AttachmentType.image).length;

    final accepted = <AttachmentItem>[];
    var exceeded = false;

    for (final attachment in items) {
      if (attachment.type == AttachmentType.image) {
        if (imageCount >= 4) {
          exceeded = true;
          continue;
        }
        imageCount += 1;
      }
      accepted.add(attachment);
    }

    if (exceeded) {
      AnxToast.show(L10n.of(context).attachmentMaxImages);
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = L10n.of(context);
        return AlertDialog(
          title: Text(l10n.memoryLongTermConfirmDialogTitle),
          content: Text(
            l10n.memoryLongTermConfirmDialogBody(
              previewText.trim().replaceAll(RegExp(r'\s+'), ' '),
            ),
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.commonConfirm),
            ),
          ],
        );
      },
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final body = !prefs.memorySessionDigestEnabled
            ? l10n.aiChatEndSessionBodyNoDigest
            : dailyStrategy == MemoryWorkflowDailyStrategy.autoDaily
                ? l10n.aiChatEndSessionBodyAutoDaily
                : l10n.aiChatEndSessionBodyReviewInbox;
        return AlertDialog(
          title: Text(l10n.aiChatEndSessionTitle),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.aiChatEndSessionAction),
            ),
          ],
        );
      },
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
    Widget inputBox = FilledContainer(
      padding: const EdgeInsets.all(4),
      radius: 15,
      child: SafeArea(
        top: false,
        bottom: widget.inputSafeAreaBottom,
        child: Padding(
          padding: EdgeInsets.only(bottom: widget.bottomPadding),
          child: Column(
            children: [
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
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        spacing: 8,
                        children: quickPrompts.map((prompt) {
                          return ActionChip(
                            // labelPadding: EdgeInsets.all(0),
                            label: Text(prompt['label']!),
                            onPressed: () => _useQuickPrompt(prompt['prompt']!),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4),
              TextField(
                controller: inputController,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: L10n.of(context).aiHintInputPlaceholder,
                  border: InputBorder.none,
                ),
                maxLines: 5,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
              ),
              SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.attach_file, size: 18),
                          onPressed: _showAttachmentPicker,
                        ),
                        const SizedBox(width: 6),
                        Flexible(child: aiService),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: Icon(
                            _thinkingIcon(
                              _thinkingModeForProvider(_selectedProviderId),
                            ),
                            size: 18,
                          ),
                          tooltip: L10n.of(context).aiThinkingTitle,
                          onPressed: _editThinkingMode,
                        ),
                        IconButton(
                          icon: const Icon(Icons.tune, size: 18),
                          tooltip: L10n.of(context).aiChatEditModelTitle,
                          onPressed: _editCurrentModel,
                        ),
                      ],
                    ),
                  ),
                  if (widget.onRequestMinimize != null)
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                      onPressed: widget.onRequestMinimize,
                    ),
                  IconButton(
                    icon: Icon(
                      chatIsStreaming ? Icons.stop : Icons.send,
                      size: 18,
                    ),
                    onPressed:
                        chatIsStreaming ? _cancelStreaming : _sendMessage,
                  ),
                ],
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

    final fontScale = Prefs().aiChatFontScale.clamp(0.8, 1.4).toDouble();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
      appBar: AppBar(
        title: Text(L10n.of(context).aiChat),
        leading: IconButton(
          icon: const Icon(Icons.insert_drive_file),
          tooltip: L10n.of(context).history,
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.text_fields),
            tooltip: L10n.of(context).font,
            onPressed: _showFontScaleSheet,
          ),
          IconButton(
            icon: const Icon(Icons.edit_document),
            tooltip: L10n.of(context).aiChatEndSessionAction,
            onPressed: _clearMessage,
          ),
          if (widget.trailing != null) ...widget.trailing!,
        ],
      ),
      drawer: Drawer(
        child: _buildHistoryDrawer(context),
      ),
      body: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(fontScale),
        ),
        child: Column(
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
                    error: (error, stack) =>
                        Center(child: Text('error: $error')),
                  ),
            ),
            inputBox,
          ],
        ),
      ),
    );
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
    final content = isUser
        ? _extractUserTextFromHuman(message as HumanChatMessage)
        : message.contentAsString;
    final isLongMessage = content.length > 300;

    final prevHumanIndex =
        isUser ? index : _findPrevHumanIndex(allMessages, index);
    final isLastTurn =
        prevHumanIndex != null && prevHumanIndex == lastHumanIndex;

    return Padding(
      padding: EdgeInsets.only(
        bottom: 8.0,
        left: isUser ? 8.0 : 0,
        right: isUser ? 0 : 8.0,
      ),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser
                    ? Theme.of(context).colorScheme.surfaceContainer
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.only(
                  topLeft: isUser ? const Radius.circular(12) : Radius.zero,
                  topRight: isUser ? Radius.zero : const Radius.circular(12),
                  bottomLeft: isUser ? Radius.zero : const Radius.circular(12),
                  bottomRight: isUser ? const Radius.circular(12) : Radius.zero,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  isUser
                      ? _buildHumanMessageBody(message as HumanChatMessage)
                      : _buildAssistantSections(content, isStreaming),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildVariantSwitcher(index, isStreaming),
                      const SizedBox(width: 4),
                      if (isUser) ...[
                        TextButton(
                          onPressed: () => _showEditUserMessageDialog(
                            index,
                            content,
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
                        _buildMessageMemoryMenu(
                          text: _assistantMemoryText(content),
                          sourceType: 'chat',
                          messageNodeId: 'assistant:$index',
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildUserMessageItem(_UserChatItem item) {
    final content = _extractUserTextFromHuman(item.message);
    final isLongMessage = content.length > 300;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.zero,
                  bottomLeft: Radius.zero,
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHumanMessageBody(item.message),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _showEditUserMessageDialog(
                          item.index,
                          content,
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
          const SizedBox(width: 8),
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
      padding: const EdgeInsets.only(bottom: 8.0, right: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAssistantSections(content, isStreaming),
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
                                        _selectedVariantByUserIndex[
                                            item.groupKey] = selected - 1;
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
                                        _selectedVariantByUserIndex[
                                            item.groupKey] = selected + 1;
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
                      _buildMessageMemoryMenu(
                        text: _assistantMemoryText(content),
                        sourceType: 'chat',
                        messageNodeId:
                            'assistant-group:${item.groupKey}:$selected',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
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

  Widget _buildAssistantSections(String content, bool isStreaming) {
    // Extract the <think>...</think> summary (if any), then parse the rest for
    // answer text + tool steps.
    final thinkRegex = RegExp(r'<think>([\s\S]*?)<\/think>');
    final matches = thinkRegex.allMatches(content).toList(growable: false);

    final thinking = matches
        .map((m) => m.group(1))
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join('\n')
        .trim();

    final remaining = content.replaceAll(thinkRegex, '').trim();
    final parsed = parseReasoningContent(remaining);

    final answerText = parsed.timeline
        .where((e) => e.type == ParsedReasoningEntryType.reply)
        .map((e) => e.text ?? '')
        .join('')
        .trim();

    final toolSteps = parsed.toolSteps;

    final l10n = L10n.of(context);

    final children = <Widget>[];

    if (answerText.isEmpty) {
      children.add(
        isStreaming
            ? Skeletonizer.zone(child: Bone.multiText())
            : const SizedBox.shrink(),
      );
    } else {
      children.add(
        StyledMarkdown(
          data: answerText,
          selectable: true,
        ),
      );
    }

    if (thinking.isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(
        AiCollapsibleSection(
          title: l10n.aiSectionThinking,
          leading: const Icon(Icons.lightbulb_outline),
          preview: thinking.split('\n').first.trim(),
          copyText: thinking,
          child: StyledMarkdown(
            data: thinking,
            selectable: true,
          ),
        ),
      );
    }

    if (toolSteps.isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(
        AiCollapsibleSection(
          title: l10n.aiSectionTools,
          subtitle: '${toolSteps.length}',
          leading: const Icon(Icons.build_outlined),
          child: Column(
            children: [
              for (var i = 0; i < toolSteps.length; i++) ...[
                _buildToolTile(toolSteps[i]),
                if (i != toolSteps.length - 1) const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
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
    return ToolStepTile(step: step);
  }

  void _showFontScaleSheet() {
    final l10n = L10n.of(context);
    const minScale = 0.8;
    const maxScale = 1.4;

    // Use a dialog instead of a bottom sheet.
    //
    // The AI chat itself can be hosted inside a bottom sheet (iPhone/iPad sheet
    // mode). Stacking a sheet-on-sheet may auto-dismiss on some platforms.
    showDialog<void>(
      context: context,
      builder: (ctx) {
        double scale = Prefs().aiChatFontScale.clamp(minScale, maxScale);

        return AlertDialog(
          title: Text(l10n.font),
          content: StatefulBuilder(
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

              return SizedBox(
                width: 320,
                child: Column(
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
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.commonOk),
            ),
          ],
        );
      },
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

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(f.filename),
          content: SingleChildScrollView(
            child: Text(
              f.text.length > 2000 ? '${f.text.substring(0, 2000)}…' : f.text,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('import'),
              child: Text(l10n.exportAndImportImport),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.commonCancel),
            ),
          ],
        );
      },
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
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemBuilder: (context, index) {
              final bytes = images[index];
              return ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(
                  bytes,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
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
    if (!isLongMessage) {
      return SelectableText(
        text,
        selectionControls: MaterialTextSelectionControls(),
      );
    }
    return _CollapsibleText(text: text);
  }
}

class _TextFileAttachmentInfo {
  const _TextFileAttachmentInfo({
    required this.filename,
    required this.text,
  });

  final String filename;
  final String text;
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
  const _CollapsibleText({required this.text});

  final String text;

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
            selectionControls: MaterialTextSelectionControls(),
          )
        else
          Stack(
            children: [
              SelectableText(
                widget.text.substring(0, 300),
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
