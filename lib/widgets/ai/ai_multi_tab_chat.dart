import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/ai_quick_prompt_chip.dart';
import 'package:papertok_reader/models/attachment_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/providers/ai_chat.dart';
import 'package:papertok_reader/providers/ai_draft_input.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/ai/ai_chat_stream.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Manages N independent AI chat sessions rendered as tabs.
///
/// Each tab runs in its own [ProviderScope] so conversations, streaming state,
/// draft input, and context notices are fully isolated. All tabs remain alive in
/// the widget tree (IndexedStack) so background streaming continues while the
/// user browses other tabs.
class AiMultiTabChat extends StatefulWidget {
  const AiMultiTabChat({
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
    this.onTapTabBar,
    this.initialSourceRef,
    this.uiVisible = true,
  });

  final String? initialMessage;
  final bool sendImmediate;
  final List<AiQuickPromptChip> quickPromptChips;
  final List<Widget>? trailing;
  final ScrollController? scrollController;
  final VoidCallback? onRequestMinimize;
  final double bottomPadding;
  final bool inputSafeAreaBottom;
  final bool resizeToAvoidBottomInset;
  final Widget Function(BuildContext, void Function(String))? emptyStateBuilder;
  final SourceRef? initialSourceRef;
  final bool uiVisible;

  /// Called when the user taps the empty background of the tab bar strip.
  /// In lock mode (reading page bottom sheet) this should close the sheet;
  /// in normal mode it minimizes it.
  final VoidCallback? onTapTabBar;

  @override
  AiMultiTabChatState createState() => AiMultiTabChatState();
}

class AiMultiTabChatState extends State<AiMultiTabChat> {
  int _activeTab = 0;
  final List<_TabSlot> _tabs = [];
  _PendingSeminarOpen? _pendingSeminarOpen;
  bool _pendingSeminarFlushScheduled = false;

  @override
  void initState() {
    super.initState();
    _tabs.add(_TabSlot());
  }

  // ── External interface (used by ReadingPage / ExcerptMenu) ────────────────

  TextEditingController? get inputController => _tabs.isEmpty
      ? null
      : _tabs[_activeTab].chatKey.currentState?.inputController;

  void prefillDraft({
    String? message,
    List<AttachmentItem>? attachments,
    bool replaceAttachments = false,
    SourceRef? sourceRef,
  }) {
    if (_tabs.isEmpty) return;
    _tabs[_activeTab].chatKey.currentState?.prefillDraft(
          message: message,
          attachments: attachments,
          replaceAttachments: replaceAttachments,
          sourceRef: sourceRef,
        );
  }

  void sendDraft() {
    if (_tabs.isEmpty) return;
    _tabs[_activeTab].chatKey.currentState?.sendCurrentDraft();
  }

  void openSeminar({
    String? question,
    String? sessionId,
    int? bookId,
    SourceRef? sourceRef,
  }) {
    if (_tabs.isEmpty) return;
    final tab = _tabs[_activeTab];
    final chatState = tab.chatKey.currentState;
    if (chatState != null) {
      chatState.openNativeSeminarCard(
        question: question,
        sessionId: sessionId,
        bookId: bookId,
        sourceRef: sourceRef,
      );
      return;
    }
    _pendingSeminarOpen = _PendingSeminarOpen(
      tabId: tab.id,
      question: question,
      sessionId: sessionId,
      bookId: bookId,
      sourceRef: sourceRef,
    );
    _schedulePendingSeminarFlush();
  }

  void _schedulePendingSeminarFlush() {
    if (_pendingSeminarFlushScheduled) return;
    _pendingSeminarFlushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingSeminarFlushScheduled = false;
      if (!mounted) return;
      final pending = _pendingSeminarOpen;
      if (pending == null) return;
      _TabSlot? targetTab;
      for (final tab in _tabs) {
        if (tab.id == pending.tabId) {
          targetTab = tab;
          break;
        }
      }
      if (targetTab == null) {
        _pendingSeminarOpen = null;
        return;
      }
      final chatState = targetTab.chatKey.currentState;
      if (chatState == null) {
        _schedulePendingSeminarFlush();
        return;
      }
      _pendingSeminarOpen = null;
      chatState.openNativeSeminarCard(
        question: pending.question,
        sessionId: pending.sessionId,
        bookId: pending.bookId,
        sourceRef: pending.sourceRef,
      );
    });
  }

  @visibleForTesting
  int get debugTabCount => _tabs.length;

  @visibleForTesting
  void debugAddTab() => _addTab();

  @visibleForTesting
  void debugSwitchTab(int index) => _switchTab(index);

  @visibleForTesting
  void debugCloseTab(int index) => _closeTab(index);

  // ── Tab management ─────────────────────────────────────────────────────────

  void _addTab() {
    setState(() {
      _tabs.add(_TabSlot());
      _activeTab = _tabs.length - 1;
    });
  }

  void _closeTab(int index) {
    if (_tabs.length <= 1) return;
    setState(() {
      _tabs.removeAt(index);
      if (_activeTab >= _tabs.length) _activeTab = _tabs.length - 1;
    });
  }

  void _switchTab(int index) {
    if (index == _activeTab) return;
    setState(() => _activeTab = index);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Column(
      children: [
        SizedBox(height: topPadding),
        _buildTabBar(context),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: IndexedStack(
              index: _activeTab,
              children: [
                for (int i = 0; i < _tabs.length; i++)
                  ProviderScope(
                    key: ValueKey(_tabs[i].id),
                    overrides: _tabs[i].overrides,
                    child: AiChatStream(
                      key: _tabs[i].chatKey,
                      // Only the first tab receives initialMessage; new tabs
                      // always start fresh. AiChatStream only consumes
                      // initialMessage in initState so subsequent rebuilds with
                      // the same parameter are safe.
                      initialMessage: i == 0 ? widget.initialMessage : null,
                      initialSourceRef: i == 0 ? widget.initialSourceRef : null,
                      sendImmediate: i == 0 ? widget.sendImmediate : false,
                      quickPromptChips: widget.quickPromptChips,
                      // Only the active tab gets the shared scroll controller
                      // (e.g. from DraggableScrollableSheet). Others use their
                      // own internal controllers.
                      scrollController:
                          i == _activeTab ? widget.scrollController : null,
                      trailing: widget.trailing,
                      onRequestMinimize: widget.onRequestMinimize,
                      bottomPadding: widget.bottomPadding,
                      inputSafeAreaBottom: widget.inputSafeAreaBottom,
                      resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
                      emptyStateBuilder: widget.emptyStateBuilder,
                      uiVisible: widget.uiVisible && i == _activeTab,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar(BuildContext context) {
    final l10n = L10n.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final fg = ClaudePalette.fg(context);

    // GestureDetector wraps the whole strip so tapping empty space (outside
    // chips / buttons) fires onTapTabBar. Child interactive widgets absorb
    // their own taps first, so only truly empty areas reach this handler.
    return GestureDetector(
      onTap: widget.onTapTabBar,
      behavior: HitTestBehavior.translucent,
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            Expanded(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                itemCount: _tabs.length,
                itemBuilder: (context, i) {
                  final isActive = i == _activeTab;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _TabChip(
                      label: '${l10n.aiTabNewChat} ${i + 1}',
                      isActive: isActive,
                      canClose: _tabs.length > 1,
                      activeColor: colorScheme.primaryContainer,
                      activeFg: colorScheme.onPrimaryContainer,
                      inactiveFg: fg.withValues(alpha: 0.6),
                      closeTooltip: l10n.aiTabClose,
                      onTap: () => _switchTab(i),
                      onClose: () => _closeTab(i),
                    ),
                  );
                },
              ),
            ),
            IconButton(
              icon: Icon(Icons.add, size: 18, color: fg.withValues(alpha: 0.7)),
              tooltip: l10n.aiTabNew,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
              onPressed: _addTab,
            ),
          ],
        ),
      ), // SizedBox
    ); // GestureDetector
  }
}

/// Holds per-tab state: a stable unique id, provider overrides, and a key to
/// reach the underlying [AiChatStreamState].
class _TabSlot {
  static int _nextId = 0;

  final int id = _nextId++;
  final GlobalKey<AiChatStreamState> chatKey = GlobalKey<AiChatStreamState>();

  late final List<Override> overrides;

  _TabSlot() {
    overrides = [
      aiChatProvider.overrideWith(AiChat.new),
      aiChatStreamingProvider.overrideWith(AiChatStreaming.new),
      aiChatContextNoticeProvider.overrideWith((ref) => null),
      aiChatUsageSummaryProvider.overrideWith((ref) => null),
      aiChatUiVisibleProvider.overrideWith((ref) => true),
      aiChatDraftInputProvider
          .overrideWith((ref) => AiChatDraftInputNotifier()),
    ];
  }
}

class _PendingSeminarOpen {
  const _PendingSeminarOpen({
    required this.tabId,
    required this.question,
    required this.sessionId,
    required this.bookId,
    required this.sourceRef,
  });

  final int tabId;
  final String? question;
  final String? sessionId;
  final int? bookId;
  final SourceRef? sourceRef;
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.isActive,
    required this.canClose,
    required this.activeColor,
    required this.activeFg,
    required this.inactiveFg,
    required this.closeTooltip,
    required this.onTap,
    required this.onClose,
  });

  final String label;
  final bool isActive;
  final bool canClose;
  final Color activeColor;
  final Color activeFg;
  final Color inactiveFg;
  final String closeTooltip;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(
          left: 10,
          right: canClose ? 2 : 10,
          top: 2,
          bottom: 2,
        ),
        decoration: BoxDecoration(
          color: isActive ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? activeFg : inactiveFg,
              ),
            ),
            if (canClose) ...[
              const SizedBox(width: 2),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onClose,
                child: Tooltip(
                  message: closeTooltip,
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: isActive
                        ? activeFg.withValues(alpha: 0.7)
                        : inactiveFg.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
