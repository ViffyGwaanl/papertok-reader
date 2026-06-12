import 'dart:async';

import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/providers/ai_history.dart';
import 'package:papertok_reader/providers/current_reading.dart';
import 'package:papertok_reader/service/ai/ai_history.dart';
import 'package:papertok_reader/service/ai/agent_run_event_message_part_adapter.dart';
import 'package:papertok_reader/service/ai/agent_run_graph_store.dart';
import 'package:papertok_reader/service/ai/conversation_title_service.dart';
import 'package:papertok_reader/service/ai/index.dart';
import 'package:papertok_reader/service/ai/prompt_budgeting_service.dart';
import 'package:papertok_reader/service/ai/seminar_prompt_context.dart';
import 'package:papertok_reader/service/ai/sub_agent_runner.dart';
import 'package:papertok_reader/service/mcp/mcp_client_service.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/attachment_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/utils/get_path/get_base_path.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:langchain_core/chat_models.dart';

part 'ai_chat.g.dart';

@Riverpod(keepAlive: true)
class AiChatStreaming extends _$AiChatStreaming {
  @override
  bool build() => false;

  void setStreaming(bool value) {
    state = value;
  }
}

final aiChatContextNoticeProvider = StateProvider<String?>((ref) => null);

/// Token usage summary displayed after streaming completes.
final aiChatUsageSummaryProvider = StateProvider<String?>((ref) => null);

const _streamingUiFlushInterval = Duration(milliseconds: 160);
const _streamingHiddenUiFlushInterval = Duration(milliseconds: 1000);

/// Whether the chat surface for this provider scope is actively visible.
///
/// Reading-page hidden panels and inactive chat tabs keep generation alive, but
/// their UI flush rate is reduced to avoid rebuilding offscreen chat widgets
/// while the user is scrolling or paging the book.
final aiChatUiVisibleProvider = StateProvider<bool>((ref) => true);

typedef AiChatGenerateStreamFactory = Stream<String> Function(
  List<ChatMessage> messages, {
  AiRequestScope scope,
  String? identifier,
  Map<String, String>? config,
  bool regenerate,
  bool useAgent,
  String? conversationId,
  Ref? ref,
});

@visibleForTesting
AiChatGenerateStreamFactory? debugAiChatGenerateStreamOverride;

@Riverpod(keepAlive: true)
class AiChat extends _$AiChat {
  String? _currentSessionId;

  AiConversationTree _tree = AiConversationTree.empty();
  List<String> _activeNodeIds = const [];

  final ConversationTitleService _titleService =
      const ConversationTitleService();
  final PromptBudgetingService _promptBudgetingService =
      const PromptBudgetingService();

  StreamSubscription<String>? _generationSub;
  AiChatHistoryEntry? _draftEntry;
  String? _draftAssistantNodeId;
  String? _loadedHistoryEntryId;
  int? _loadedHistoryBookId;
  String? _loadedHistoryBookTitle;
  int _lastDraftProgressPersistMs = 0;
  String _lastDraftProgressContent = '';
  Future<void> _draftPersistChain = Future<void>.value();
  Timer? _streamingUiFlushTimer;
  String? _pendingStreamingContent;
  int _lastStreamingUiFlushMs = 0;
  bool _disposed = false;

  String _draftModel = '';
  int _draftTokenInSnapshot = 0;
  int _draftTokenOutSnapshot = 0;

  @override
  FutureOr<List<ChatMessage>> build() async {
    ref.onDispose(_disposeActiveStreamingScope);

    _disposed = false;
    _currentSessionId = null;
    _tree = AiConversationTree.empty();
    _activeNodeIds = const [];

    _generationSub?.cancel();
    _generationSub = null;
    _draftEntry = null;
    _draftAssistantNodeId = null;
    _loadedHistoryEntryId = null;
    _loadedHistoryBookId = null;
    _loadedHistoryBookTitle = null;
    _lastDraftProgressPersistMs = 0;
    _lastDraftProgressContent = '';
    _draftPersistChain = Future<void>.value();
    _cancelStreamingUiFlush();

    return List<ChatMessage>.empty();
  }

  void _disposeActiveStreamingScope() {
    _disposed = true;
    cancelActiveAiRequest();
    final generationSub = _generationSub;
    _generationSub = null;
    if (generationSub != null) {
      unawaited(generationSub.cancel());
    }
    _cancelStreamingUiFlush();
  }

  Future<void> sendMessage(String message) async {
    state = AsyncData([
      ...state.whenOrNull(data: (data) => data) ?? [],
      ChatMessage.humanText(message),
    ]);
  }

  void restore(List<ChatMessage> history, {String? sessionId}) {
    cancelActiveAiRequest();
    _generationSub?.cancel();
    _generationSub = null;
    ref.read(aiChatStreamingProvider.notifier).setStreaming(false);

    if (sessionId != null) {
      _currentSessionId = sessionId;
    }
    _loadedHistoryEntryId = null;
    _loadedHistoryBookId = null;
    _loadedHistoryBookTitle = null;
    _lastDraftProgressPersistMs = 0;
    _lastDraftProgressContent = '';
    _draftPersistChain = Future<void>.value();
    _cancelStreamingUiFlush();
    _tree = AiConversationTree.fromLinearMessages(history);
    _rebuildFromTree();
  }

  bool get isStreaming => _generationSub != null;

  /// Start a streaming generation session.
  ///
  /// This runs inside the provider (not the UI widget), so minimizing/closing
  /// the chat panel will not interrupt generation.
  void startStreaming(
    String message,
    bool isRegenerate, {
    int? regenerateFromUserIndex,
    bool replaceUserMessage = false,
    List<AttachmentItem>? attachments,
    SourceRef? userSourceRef,
  }) {
    if (_generationSub != null) {
      return;
    }

    final sessionId = _ensureSessionId();
    final serviceId = Prefs().selectedAiService;
    final config = Prefs().getAiConfig(serviceId);
    final model = (config['model'])?.trim() ?? '';

    final historyNotifier = ref.read(aiHistoryProvider.notifier);
    final initialHistoryState = ref
        .read(aiHistoryProvider)
        .maybeWhen(data: (value) => value, orElse: () => const []);
    AiChatHistoryEntry? entry;
    for (final item in initialHistoryState) {
      if (item.id == sessionId) {
        entry = item;
        break;
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final bookContext = _readCurrentBookContext(ref.read);
    final historyBookContext = _historyBookContextFor(
      existing: entry,
      current: bookContext,
    );

    if (_tree.nodes.isEmpty) {
      _tree = AiConversationTree.empty();
    }

    // 1) Mutate tree.
    var parentId = _activeNodeIds.isEmpty ? _tree.rootId : _activeNodeIds.last;

    // Build multimodal content if attachments provided
    ChatMessageContent messageContent;
    if (attachments != null && attachments.isNotEmpty) {
      final parts = <ChatMessageContent>[];

      // Add user input text if provided
      if (message.isNotEmpty) {
        parts.add(ChatMessageContent.text(message));
      }

      // Add text file content (as separate parts with filename header)
      final textAttachments =
          attachments.where((a) => a.type == AttachmentType.textFile);
      for (final attachment in textAttachments) {
        final filename = (attachment.filename ?? 'text').trim();
        final text = (attachment.text ?? '').trim();
        if (text.isEmpty) continue;
        parts.add(ChatMessageContent.text('[[file:$filename]]\\n$text'));
      }

      // Add images
      final imageAttachments =
          attachments.where((a) => a.type == AttachmentType.image);
      for (final image in imageAttachments) {
        if (image.base64 != null) {
          parts.add(ChatMessageContent.image(
            data: image.base64!,
            mimeType: 'image/jpeg',
          ));
        }
      }

      messageContent = ChatMessageContent.multiModal(parts);
    } else {
      // No attachments, use simple text content
      messageContent = ChatMessageContent.text(message);
    }

    if (!isRegenerate && !replaceUserMessage) {
      _tree = _tree.appendChild(
        parentId: parentId,
        message: ChatMessage.human(messageContent),
        sourceRef: userSourceRef,
      );
      parentId = _tree.nodes[parentId]!.activeChildId!;
    } else {
      final userIndex = regenerateFromUserIndex ?? _findLastHumanIndex();
      if (userIndex != null &&
          userIndex >= 0 &&
          userIndex < _activeNodeIds.length) {
        final userNodeId = _activeNodeIds[userIndex];
        final userNode = _tree.nodes[userNodeId];
        if (userNode != null) {
          final parentOfUser = userNode.parentId ?? _tree.rootId;

          if (replaceUserMessage) {
            if (attachments != null) {
              _tree = _tree.appendChild(
                parentId: parentOfUser,
                message: ChatMessage.human(messageContent),
              );
              parentId = _tree.nodes[parentOfUser]!.activeChildId!;
            } else {
              // Replace only the text parts for multimodal messages
              final existingMessage = userNode.toChatMessage();
              if (existingMessage is HumanChatMessage &&
                  existingMessage.content is ChatMessageContentMultiModal) {
                final multiModal =
                    existingMessage.content as ChatMessageContentMultiModal;
                // Replace the primary user text part, but preserve attachments.
                final preserved = <ChatMessageContent>[];
                for (final part in multiModal.parts) {
                  if (part is ChatMessageContentImage) {
                    preserved.add(part);
                  } else if (part is ChatMessageContentText &&
                      part.text.startsWith('[[file:')) {
                    preserved.add(part);
                  }
                }

                final newParts = <ChatMessageContent>[
                  ChatMessageContent.text(message),
                  ...preserved,
                ];

                _tree = _tree.appendChild(
                  parentId: parentOfUser,
                  message: ChatMessage.human(
                    ChatMessageContent.multiModal(newParts),
                  ),
                );
                parentId = _tree.nodes[parentOfUser]!.activeChildId!;
              } else {
                // Simple text message, replace directly
                _tree = _tree.appendChild(
                  parentId: parentOfUser,
                  message: ChatMessage.humanText(message),
                );
                parentId = _tree.nodes[parentOfUser]!.activeChildId!;
              }
            }
          } else {
            parentId = userNodeId;
          }
        }
      }
    }

    // 2) Assistant placeholder.
    _tree = _tree.appendChild(
      parentId: parentId,
      message: ChatMessage.ai(''),
    );
    _draftAssistantNodeId = _tree.nodes[parentId]!.activeChildId!;

    // 3) Update UI state + write draft entry.
    _rebuildFromTree();
    final updatedMessages = state.value ?? const <ChatMessage>[];

    final fallbackTitle = _titleService.deriveFallbackTitle(updatedMessages);
    _draftEntry = (entry ??
            AiChatHistoryEntry(
              id: sessionId,
              serviceId: serviceId,
              model: model,
              createdAt: entry?.createdAt ?? now,
              updatedAt: now,
              title: fallbackTitle,
              titleSource: 'heuristic',
              bookId: historyBookContext.bookId,
              bookTitle: historyBookContext.bookTitle,
              messages: List<ChatMessage>.from(updatedMessages),
              completed: false,
            ))
        .copyWith(
      serviceId: serviceId,
      messages: List<ChatMessage>.from(updatedMessages),
      updatedAt: now,
      completed: false,
      model: model,
      title: (entry?.title?.trim().isNotEmpty ?? false)
          ? entry!.title
          : fallbackTitle,
      titleSource: (entry?.titleSource?.trim().isNotEmpty ?? false)
          ? entry!.titleSource
          : 'heuristic',
      bookId: historyBookContext.bookId,
      bookTitle: historyBookContext.bookTitle,
      conversationV2: _tree.toJson(),
    );

    _lastDraftProgressPersistMs = now;
    _lastDraftProgressContent = '';
    _queueDraftHistoryUpsert(historyNotifier, _draftEntry!);

    // 4) Start generation.
    final promptMessages = _buildPromptMessagesForAssistantParent(parentId);
    final budgetResult = _promptBudgetingService.trimMessages(
      providerId: serviceId,
      config: config,
      messages: promptMessages,
    );
    if (budgetResult.trimmed && budgetResult.contextWindow != null) {
      ref.read(aiChatContextNoticeProvider.notifier).state =
          'Context trimmed for ${model.isEmpty ? serviceId : model} '
          '(${budgetResult.estimatedTokens}/${budgetResult.contextWindow}, '
          'reserve ${budgetResult.reservedOutputTokens})';
    } else {
      ref.read(aiChatContextNoticeProvider.notifier).state = null;
    }

    _draftModel = model;
    final startTracker = getUsageTracker(sessionId);
    _draftTokenInSnapshot = startTracker?.inputTokens ?? 0;
    _draftTokenOutSnapshot = startTracker?.outputTokens ?? 0;

    ref.read(aiChatStreamingProvider.notifier).setStreaming(true);

    final streamFactory = debugAiChatGenerateStreamOverride ?? aiGenerateStream;
    final stream = streamFactory(
      budgetResult.messages,
      regenerate: isRegenerate,
      useAgent: true,
      conversationId: sessionId,
      ref: ref,
    );

    _generationSub = stream.listen(
      (chunk) {
        _handleStreamingChunk(chunk, historyNotifier);
      },
      onError: (Object error, StackTrace stack) {
        _generationSub = null;
        _flushPendingStreamingChunk(historyNotifier);
        _finalizeStreaming(completed: false);
      },
      onDone: () {
        _generationSub = null;
        _flushPendingStreamingChunk(historyNotifier);
        _finalizeStreaming(completed: true);
      },
      cancelOnError: false,
    );
  }

  Future<void> cancelStreaming() async {
    if (_generationSub == null) {
      return;
    }

    cancelActiveAiRequest();

    // Best-effort: cancel any in-flight MCP tool calls.
    // This avoids long-running external tool calls after user presses Stop.
    try {
      await McpClientService.instance
          .cancelAllInFlight(reason: 'User pressed stop');
    } catch (_) {}

    try {
      await _generationSub?.cancel();
    } catch (_) {}

    _generationSub = null;
    final historyNotifier = ref.read(aiHistoryProvider.notifier);
    _flushPendingStreamingChunk(historyNotifier);
    _finalizeStreaming(completed: false);
  }

  void _finalizeStreaming({required bool completed}) {
    if (_generationSub != null) {
      return;
    }

    ref.read(aiChatStreamingProvider.notifier).setStreaming(false);
    _cancelStreamingUiFlush(clearPending: false);

    // Update token usage summary for UI display.
    final tracker = getUsageTracker(_currentSessionId);
    if (tracker != null && tracker.totalTokens > 0) {
      ref.read(aiChatUsageSummaryProvider.notifier).state =
          tracker.toShortSummary();
    }

    // Persist per-segment meta (model + this-turn token delta) on the
    // assistant node so it survives reload.
    final assistantId = _draftAssistantNodeId;
    if (assistantId != null && _tree.nodes.containsKey(assistantId)) {
      final node = _tree.nodes[assistantId]!;
      int? deltaIn;
      int? deltaOut;
      if (tracker != null) {
        final di = tracker.inputTokens - _draftTokenInSnapshot;
        final dout = tracker.outputTokens - _draftTokenOutSnapshot;
        deltaIn = di > 0 ? di : null;
        deltaOut = dout > 0 ? dout : null;
      }
      final meta = AiSegmentMeta(
        model: _draftModel.isEmpty ? null : _draftModel,
        inputTokens: deltaIn,
        outputTokens: deltaOut,
      );
      if (!meta.isEmpty) {
        _tree = _tree.copyWithNode(assistantId, node.copyWith(meta: meta));
      }
    }

    final historyNotifier = ref.read(aiHistoryProvider.notifier);
    final draftEntry = _draftEntry;
    if (draftEntry != null) {
      final finalEntry = draftEntry.copyWith(
        messages: List<ChatMessage>.from(state.value ?? const <ChatMessage>[]),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        completed: completed,
        conversationV2: _tree.toJson(),
      );
      final persisted = _queueDraftHistoryUpsert(historyNotifier, finalEntry);
      unawaited(
        persisted
            .then(
              (_) => _refreshGeneratedTitle(finalEntry, historyNotifier),
            )
            .catchError(
              (_) {},
            ),
      );
    }

    _draftEntry = null;
    _draftAssistantNodeId = null;
    _lastDraftProgressPersistMs = 0;
    _lastDraftProgressContent = '';
  }

  void _handleStreamingChunk(
    String chunk,
    AiHistoryNotifier historyNotifier,
  ) {
    _pendingStreamingContent = chunk;
    _scheduleOrFlushPendingStreamingChunk(historyNotifier);
  }

  void setStreamingUiVisible(bool visible) {
    ref.read(aiChatUiVisibleProvider.notifier).state = visible;
    if (visible) {
      flushPendingStreamingUi();
      return;
    }
    if (_pendingStreamingContent == null) {
      return;
    }
    final historyNotifier = ref.read(aiHistoryProvider.notifier);
    _scheduleOrFlushPendingStreamingChunk(
      historyNotifier,
      replaceTimer: true,
    );
  }

  void _scheduleOrFlushPendingStreamingChunk(
    AiHistoryNotifier historyNotifier, {
    bool replaceTimer = false,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = now - _lastStreamingUiFlushMs;
    final uiVisible = ref.read(aiChatUiVisibleProvider);
    final flushMs = uiVisible
        ? _streamingUiFlushInterval.inMilliseconds
        : _streamingHiddenUiFlushInterval.inMilliseconds;
    if (uiVisible && (_lastStreamingUiFlushMs == 0 || elapsed >= flushMs)) {
      _flushPendingStreamingChunk(historyNotifier);
      return;
    }
    if (!uiVisible && _lastStreamingUiFlushMs != 0 && elapsed >= flushMs) {
      _flushPendingStreamingChunk(historyNotifier);
      return;
    }

    final delayMs = _lastStreamingUiFlushMs == 0
        ? flushMs
        : (flushMs - elapsed).clamp(1, flushMs).toInt();
    if (replaceTimer) {
      _streamingUiFlushTimer?.cancel();
      _streamingUiFlushTimer = null;
    }
    _streamingUiFlushTimer ??= Timer(
      Duration(milliseconds: delayMs),
      () {
        _streamingUiFlushTimer = null;
        _flushPendingStreamingChunk(historyNotifier);
      },
    );
  }

  void flushPendingStreamingUi() {
    if (!ref.read(aiChatUiVisibleProvider)) {
      return;
    }
    if (_pendingStreamingContent == null) {
      return;
    }
    _streamingUiFlushTimer?.cancel();
    _streamingUiFlushTimer = null;
    final historyNotifier = ref.read(aiHistoryProvider.notifier);
    _flushPendingStreamingChunk(historyNotifier);
  }

  void _flushPendingStreamingChunk(
    AiHistoryNotifier historyNotifier,
  ) {
    final chunk = _pendingStreamingContent;
    if (chunk == null) {
      return;
    }
    _pendingStreamingContent = null;
    _lastStreamingUiFlushMs = DateTime.now().millisecondsSinceEpoch;

    final assistantId = _draftAssistantNodeId;
    if (assistantId == null) {
      return;
    }
    _tree = _tree.updateNodeMessage(assistantId, ChatMessage.ai(chunk));
    _rebuildFromTree();
    _persistDraftProgress(
      historyNotifier,
      completed: false,
      force: _lastDraftProgressContent.isEmpty && chunk.trim().isNotEmpty,
    );
  }

  void _cancelStreamingUiFlush({bool clearPending = true}) {
    try {
      _streamingUiFlushTimer?.cancel();
    } catch (_) {}
    _streamingUiFlushTimer = null;
    if (clearPending) {
      _pendingStreamingContent = null;
    }
    _lastStreamingUiFlushMs = 0;
  }

  void _persistDraftProgress(
    AiHistoryNotifier historyNotifier, {
    required bool completed,
    bool force = false,
  }) {
    final draftEntry = _draftEntry;
    if (draftEntry == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final assistantId = _draftAssistantNodeId;
    final assistantMessage =
        assistantId == null ? null : _tree.nodes[assistantId]?.toChatMessage();
    final assistantContent = assistantMessage?.contentAsString ?? '';

    if (!force) {
      if (assistantContent == _lastDraftProgressContent) return;
      if (now - _lastDraftProgressPersistMs < 1000) return;
    }

    _lastDraftProgressPersistMs = now;
    _lastDraftProgressContent = assistantContent;

    final updated = draftEntry.copyWith(
      messages: List<ChatMessage>.from(state.value ?? const <ChatMessage>[]),
      updatedAt: now,
      completed: completed,
      conversationV2: _tree.toJson(),
    );
    _draftEntry = updated;
    _queueDraftHistoryUpsert(historyNotifier, updated);
  }

  Future<void> _queueDraftHistoryUpsert(
    AiHistoryNotifier historyNotifier,
    AiChatHistoryEntry entry,
  ) {
    final next = _draftPersistChain
        .catchError((_) {})
        .then((_) => historyNotifier.upsert(entry))
        .catchError((_) {});
    _draftPersistChain = next;
    return next;
  }

  Future<void> _refreshGeneratedTitle(
    AiChatHistoryEntry entry,
    AiHistoryNotifier historyNotifier,
  ) async {
    if (_disposed) {
      return;
    }
    if (entry.titleSource == 'manual') {
      return;
    }

    final messages = entry.messages;
    final hasHuman = messages.any((message) => message is HumanChatMessage);
    final hasAssistant = messages.any((message) => message is AIChatMessage);
    if (!hasHuman || !hasAssistant) {
      return;
    }

    final generated = await _titleService.generateTitle(messages);
    if (_disposed) {
      return;
    }
    final normalized = generated.trim();
    if (normalized.isEmpty || normalized == entry.title) {
      return;
    }

    final updated = entry.copyWith(
      title: normalized,
      titleSource: Prefs().aiTitleGenerationEnabled ? 'model' : 'heuristic',
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await historyNotifier.upsert(updated);
  }

  void clear() {
    cancelActiveAiRequest();
    _generationSub?.cancel();
    _generationSub = null;
    ref.read(aiChatStreamingProvider.notifier).setStreaming(false);

    state = AsyncData(List<ChatMessage>.empty());
    _currentSessionId = null;
    _tree = AiConversationTree.empty();
    _activeNodeIds = const [];

    _draftEntry = null;
    _draftAssistantNodeId = null;
    _loadedHistoryEntryId = null;
    _loadedHistoryBookId = null;
    _loadedHistoryBookTitle = null;
    _lastDraftProgressPersistMs = 0;
    _lastDraftProgressContent = '';
    _draftPersistChain = Future<void>.value();
    _cancelStreamingUiFlush();
    ref.read(aiChatContextNoticeProvider.notifier).state = null;
    ref.read(aiChatUsageSummaryProvider.notifier).state = null;
  }

  void loadHistoryEntry(AiChatHistoryEntry entry) {
    cancelActiveAiRequest();
    _generationSub?.cancel();
    _generationSub = null;
    ref.read(aiChatStreamingProvider.notifier).setStreaming(false);
    ref.read(aiChatContextNoticeProvider.notifier).state = null;
    ref.read(aiChatUsageSummaryProvider.notifier).state = null;

    final providerMeta = Prefs().getAiProviderMeta(entry.serviceId);
    if (providerMeta != null && providerMeta.enabled) {
      Prefs().selectedAiService = entry.serviceId;
      final config = <String, String>{...Prefs().getAiConfig(entry.serviceId)};
      if (entry.model.trim().isNotEmpty) {
        config['model'] = entry.model.trim();
        Prefs().saveAiConfig(entry.serviceId, config);
      }
    }

    _currentSessionId = entry.id;
    _loadedHistoryEntryId = entry.id;
    _loadedHistoryBookId = entry.bookId;
    _loadedHistoryBookTitle = entry.bookTitle;
    _lastDraftProgressPersistMs = 0;
    _lastDraftProgressContent = '';
    _draftPersistChain = Future<void>.value();
    _cancelStreamingUiFlush();

    final rawTree = entry.conversationV2;
    if (rawTree != null) {
      _tree = AiConversationTree.fromJson(rawTree);
    } else {
      _tree = AiConversationTree.fromLinearMessages(entry.messages);
    }
    _normalizeLoadedSeminarRunCardSnapshots();

    _rebuildFromTree();
    unawaited(_hydrateSeminarRunCardGraphReplayForLoadedHistory(entry.id));
  }

  String? get currentSessionId => _currentSessionId;

  bool get isLoadedHistoryConversation =>
      _currentSessionId != null && _loadedHistoryEntryId == _currentSessionId;

  String _ensureSessionId() {
    return _currentSessionId ??= _generateSessionId();
  }

  int? _findLastHumanIndex() {
    final messages = state.value;
    if (messages == null) return null;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i] is HumanChatMessage) {
        return i;
      }
    }
    return null;
  }

  void _rebuildFromTree() {
    _activeNodeIds = _tree.activePathNodeIds();
    final messages = _tree.activePathMessages();
    state = AsyncData(messages);
  }

  void _normalizeLoadedSeminarRunCardSnapshots() {
    var tree = _tree;
    for (final entry in _tree.nodes.entries) {
      final node = entry.value;
      final meta = node.meta;
      final card = meta?.seminarRunCard;
      final snapshot = card?.snapshot;
      if (meta == null || card == null || snapshot == null) continue;
      final toolCallParts = _ensureSeminarToolCallPartsFromLegacySnapshot(
        snapshot.messageParts,
        snapshot.toolCalls,
      );
      final roleTurnParts = _ensureSeminarRoleTurnPartsFromLegacySnapshot(
        toolCallParts,
        parentRunId: card.sessionId,
        roleSummaries: snapshot.roleSummaries,
      );
      final synthesisParts = _ensureSeminarSynthesisPartFromLegacySnapshot(
        roleTurnParts,
        parentRunId: card.sessionId,
        synthesisSummary: snapshot.synthesisSummary,
        evidenceRefs: snapshot.evidence,
      );
      final disagreementParts =
          _ensureSeminarDisagreementPartsFromLegacySnapshot(
        synthesisParts,
        parentRunId: card.sessionId,
        disagreements: snapshot.disagreements,
        disagreementDetails: snapshot.disagreementDetails,
      );
      final openQuestionParts =
          _ensureSeminarOpenQuestionPartsFromLegacySnapshot(
        disagreementParts,
        parentRunId: card.sessionId,
        roleIds: card.roleIds,
        openQuestions: snapshot.openQuestions,
      );
      final normalizedParts = _ensureSeminarEvidencePartFromLegacySnapshot(
        _suppressPendingSeminarRuntimeControlActions(
          _ensureSeminarEvidencePartsFromToolCalls(openQuestionParts),
        ),
        parentRunId: card.sessionId,
        evidenceRefs: snapshot.evidence,
      );
      final normalizedSnapshot = AiSeminarRunCardSnapshot(
        evidence: snapshot.evidence,
        toolCalls: snapshot.toolCalls,
        roleSummaries: snapshot.roleSummaries,
        messageParts: normalizedParts,
        synthesisSummary: snapshot.synthesisSummary,
        disagreements: snapshot.disagreements,
        disagreementDetails: snapshot.disagreementDetails,
        openQuestions: snapshot.openQuestions,
      );
      if (!_seminarSnapshotChanged(snapshot, normalizedSnapshot)) continue;
      final normalizedCard = card.copyWith(snapshot: normalizedSnapshot);
      tree = tree.copyWithNode(
        entry.key,
        node.copyWith(
          message:
              ChatMessage.ai(seminarRunCardPromptText(normalizedCard)).toMap(),
          meta: AiSegmentMeta(
            model: meta.model,
            inputTokens: meta.inputTokens,
            outputTokens: meta.outputTokens,
            seminarRunCard: normalizedCard,
          ),
        ),
      );
    }
    _tree = tree;
  }

  /// Build prompt messages up to the human message node [humanNodeId].
  List<ChatMessage> _buildPromptMessagesForAssistantParent(String humanNodeId) {
    // Walk from the human node back to root using parent pointers.
    final ids = <String>[];
    var currentId = humanNodeId;
    while (currentId != _tree.rootId) {
      ids.add(currentId);
      final parentId = _tree.nodes[currentId]?.parentId;
      if (parentId == null) break;
      currentId = parentId;
    }

    final orderedIds = ids.reversed.toList(growable: false);

    final messages = <ChatMessage>[];
    for (final id in orderedIds) {
      final msg = _tree.nodes[id]?.toChatMessage();
      if (msg != null) messages.add(msg);
    }

    return _stripHistoryImagesFromPrompt(messages);
  }

  /// OpenAI-compatible servers may count base64 image payloads as text tokens.
  ///
  /// To avoid context explosion (and `context_length_exceeded`), we strip image
  /// parts from older turns and keep images only for the latest human message
  /// in the prompt.
  List<ChatMessage> _stripHistoryImagesFromPrompt(List<ChatMessage> messages) {
    final lastHumanIndex =
        messages.lastIndexWhere((m) => m is HumanChatMessage);
    if (lastHumanIndex <= 0) {
      return messages;
    }

    var changed = false;
    final out = <ChatMessage>[];

    for (var i = 0; i < messages.length; i++) {
      final msg = messages[i];
      if (i != lastHumanIndex &&
          msg is HumanChatMessage &&
          msg.content is ChatMessageContentMultiModal) {
        final mm = msg.content as ChatMessageContentMultiModal;

        var removedImages = 0;
        final newParts = <ChatMessageContent>[];
        for (final part in mm.parts) {
          if (part is ChatMessageContentImage) {
            removedImages += 1;
            continue;
          }
          newParts.add(part);
        }

        if (removedImages > 0) {
          changed = true;
          // Keep a short marker so the model knows a prior image existed.
          newParts
              .add(ChatMessageContent.text('[[image omitted from history]]'));
          out.add(ChatMessage.human(ChatMessageContent.multiModal(newParts)));
          continue;
        }
      }
      out.add(msg);
    }

    return changed ? out : messages;
  }

  /// Switches the active variant for the message at [messageIndex] by [delta]
  /// among its siblings.
  void switchVariantAtMessageIndex(
    int messageIndex,
    int delta,
  ) {
    if (messageIndex < 0 || messageIndex >= _activeNodeIds.length) {
      return;
    }
    final nodeId = _activeNodeIds[messageIndex];
    final node = _tree.nodes[nodeId];
    final parentId = node?.parentId;
    if (node == null || parentId == null) {
      return;
    }

    final siblings = _tree.siblingsOf(nodeId);
    final current = siblings.indexOf(nodeId);
    if (current < 0) return;

    final next = current + delta;
    if (next < 0 || next >= siblings.length) return;

    _tree = _tree.setActiveChild(parentId, siblings[next]);
    _rebuildFromTree();
  }

  void switchVariantAtMessageIndexAndPersist(
    int messageIndex,
    int delta,
    WidgetRef ref,
  ) {
    switchVariantAtMessageIndex(messageIndex, delta);
    persistCurrentConversation(ref);
  }

  int variantCountForMessageIndex(int messageIndex) {
    if (messageIndex < 0 || messageIndex >= _activeNodeIds.length) {
      return 1;
    }
    final nodeId = _activeNodeIds[messageIndex];
    final siblings = _tree.siblingsOf(nodeId);
    return siblings.isEmpty ? 1 : siblings.length;
  }

  int selectedVariantIndexForMessageIndex(int messageIndex) {
    if (messageIndex < 0 || messageIndex >= _activeNodeIds.length) {
      return 0;
    }
    final nodeId = _activeNodeIds[messageIndex];
    final siblings = _tree.siblingsOf(nodeId);
    if (siblings.isEmpty) return 0;
    final idx = siblings.indexOf(nodeId);
    return idx < 0 ? 0 : idx;
  }

  /// Returns the persisted per-segment meta for the message at [messageIndex]
  /// on the active path, or null if none.
  AiSegmentMeta? segmentMetaForMessageIndex(int messageIndex) {
    if (messageIndex < 0 || messageIndex >= _activeNodeIds.length) {
      return null;
    }
    return _tree.nodes[_activeNodeIds[messageIndex]]?.meta;
  }

  AiSeminarRunCardMeta? seminarRunCardForMessageIndex(int messageIndex) {
    return segmentMetaForMessageIndex(messageIndex)?.seminarRunCard;
  }

  /// Returns the persisted reader/source provenance for the active-path message
  /// at [messageIndex], or null for legacy entries without per-turn provenance.
  SourceRef? sourceRefForMessageIndex(int messageIndex) {
    if (messageIndex < 0 || messageIndex >= _activeNodeIds.length) {
      return null;
    }
    return _tree.nodes[_activeNodeIds[messageIndex]]?.sourceRef;
  }

  Future<void> appendSeminarRunCard({
    required String question,
    int? bookId,
    SourceRef? sourceRef,
    String? seminarSessionId,
    bool? includeVerifier,
    int? maxRounds,
    List<AiSeminarRoleProfile>? roleProfiles,
  }) async {
    final trimmedQuestion = question.trim();
    if (trimmedQuestion.isEmpty && sourceRef == null) {
      return;
    }

    final sessionId = _ensureSessionId();
    final serviceId = Prefs().selectedAiService;
    final config = Prefs().getAiConfig(serviceId);
    final model = (config['model'])?.trim() ?? '';
    final historyNotifier = ref.read(aiHistoryProvider.notifier);
    final existing = historyNotifier.findById(sessionId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final bookContext = _readCurrentBookContext(ref.read);
    final historyBookContext = _historyBookContextFor(
      existing: existing,
      current: bookContext,
    );
    final resolvedBookId = sourceRef?.bookId ?? bookId ?? bookContext.bookId;
    final effectiveRoleProfiles = _effectiveSeminarRoleProfiles(roleProfiles);
    final effectiveIncludeVerifier =
        includeVerifier ?? Prefs().aiSeminarIncludeVerifier;
    final selectedRoles = <AiSeminarRole>[
      AiSeminarRole.critical,
      AiSeminarRole.supportive,
      if (effectiveIncludeVerifier) AiSeminarRole.verifier,
      AiSeminarRole.synthesizer,
    ]
        .where((role) =>
            _roleProfileFor(effectiveRoleProfiles, role)?.enabled != false)
        .toList(growable: false);
    final roleIds = (selectedRoles.isEmpty
            ? const [AiSeminarRole.synthesizer]
            : selectedRoles)
        .map((role) => role.asString)
        .toList(growable: false);
    final evidenceScopeIds = _seminarEvidenceScopesFor(effectiveRoleProfiles)
        .map((scope) => scope.asString)
        .toList(growable: false);
    final effectiveMaxRounds = _seminarMaxRounds(maxRounds);
    final cardSessionId = _seminarSessionId(
      preferred: seminarSessionId,
      now: now,
    );

    if (_tree.nodes.isEmpty) {
      _tree = AiConversationTree.empty();
    }

    var parentId = _activeNodeIds.isEmpty ? _tree.rootId : _activeNodeIds.last;
    if (trimmedQuestion.isNotEmpty) {
      _tree = _tree.appendChild(
        parentId: parentId,
        message: ChatMessage.humanText(trimmedQuestion),
        sourceRef: sourceRef,
      );
      parentId = _tree.nodes[parentId]!.activeChildId!;
    }

    final initialCard = AiSeminarRunCardMeta(
      question: trimmedQuestion,
      sessionId: cardSessionId,
      bookId: resolvedBookId,
      sourceRef: sourceRef,
      status: 'ready',
      roleIds: roleIds,
      evidenceScopeIds: evidenceScopeIds,
      sourceRefCount: sourceRef == null ? 0 : 1,
      allowWeb: false,
      writeRequiresApproval: true,
      maxRounds: effectiveMaxRounds,
      roleProfiles: effectiveRoleProfiles,
      createdAt: now,
    );
    final card = initialCard.copyWith(
      snapshot: _seminarRunSetupSnapshotForCard(initialCard),
    );
    _tree = _tree.appendChild(
      parentId: parentId,
      message: ChatMessage.ai(_seminarRunCardFallbackText(card)),
    );
    final cardNodeId = _tree.nodes[parentId]!.activeChildId!;
    final cardNode = _tree.nodes[cardNodeId];
    if (cardNode != null) {
      _tree = _tree.copyWithNode(
        cardNodeId,
        cardNode.copyWith(
          meta: AiSegmentMeta(seminarRunCard: card),
        ),
      );
    }

    _rebuildFromTree();

    final currentMessages = List<ChatMessage>.from(state.value ?? const []);
    final fallbackTitle = _titleService.deriveFallbackTitle(currentMessages);
    final entry = (existing ??
            AiChatHistoryEntry(
              id: sessionId,
              serviceId: serviceId,
              model: model,
              createdAt: now,
              updatedAt: now,
              title: fallbackTitle,
              titleSource: 'heuristic',
              bookId: historyBookContext.bookId,
              bookTitle: historyBookContext.bookTitle,
              messages: currentMessages,
              completed: true,
            ))
        .copyWith(
      serviceId: serviceId,
      messages: currentMessages,
      updatedAt: now,
      completed: true,
      model: model,
      title: (existing?.title?.trim().isNotEmpty ?? false)
          ? existing!.title
          : fallbackTitle,
      titleSource: (existing?.titleSource?.trim().isNotEmpty ?? false)
          ? existing!.titleSource
          : 'heuristic',
      bookId: historyBookContext.bookId,
      bookTitle: historyBookContext.bookTitle,
      conversationV2: _tree.toJson(),
    );
    if (_draftEntry?.id == entry.id) {
      _draftEntry = entry;
    }
    await _queueDraftHistoryUpsert(historyNotifier, entry);
  }

  Future<bool> updateSeminarRunCardSnapshot({
    required String seminarSessionId,
    required String status,
    AiSeminarRunCardSnapshot? snapshot,
    int? sourceRefCount,
  }) async {
    final targetSessionId = seminarSessionId.trim();
    if (targetSessionId.isEmpty || _tree.nodes.isEmpty) return false;

    String? targetNodeId;
    AiConversationNode? targetNode;
    AiSeminarRunCardMeta? targetCard;
    for (final entry in _tree.nodes.entries) {
      final card = entry.value.meta?.seminarRunCard;
      if (card?.sessionId == targetSessionId) {
        targetNodeId = entry.key;
        targetNode = entry.value;
        targetCard = card;
        break;
      }
    }
    if (targetNodeId == null || targetNode == null || targetCard == null) {
      return false;
    }

    final existingSnapshot =
        targetCard.snapshot ?? _seminarRunSetupSnapshotForCard(targetCard);
    final hadPendingWaitRequest =
        _seminarSnapshotHasPendingWaitRequest(existingSnapshot);
    var mergedSnapshot = _mergeSeminarRunCardSnapshot(
          existing: existingSnapshot,
          next: snapshot,
        ) ??
        existingSnapshot;
    mergedSnapshot = await _snapshotWithSatisfiedSeminarWaitRequests(
      seminarSessionId: targetSessionId,
      snapshot: mergedSnapshot,
      forceCheck: hadPendingWaitRequest,
    );
    mergedSnapshot = _seminarSnapshotWithMessageParts(
      mergedSnapshot,
      _ensureSeminarEvidencePartFromLegacySnapshot(
        _ensureSeminarEvidencePartsFromToolCalls(
          _ensureSeminarOpenQuestionPartsFromLegacySnapshot(
            _ensureSeminarDisagreementPartsFromLegacySnapshot(
              _ensureSeminarSynthesisPartFromLegacySnapshot(
                _ensureSeminarRoleTurnPartsFromLegacySnapshot(
                  _ensureSeminarToolCallPartsFromLegacySnapshot(
                    mergedSnapshot.messageParts,
                    mergedSnapshot.toolCalls,
                  ),
                  parentRunId: targetSessionId,
                  roleSummaries: mergedSnapshot.roleSummaries,
                ),
                parentRunId: targetSessionId,
                synthesisSummary: mergedSnapshot.synthesisSummary,
                evidenceRefs: mergedSnapshot.evidence,
              ),
              parentRunId: targetSessionId,
              disagreements: mergedSnapshot.disagreements,
              disagreementDetails: mergedSnapshot.disagreementDetails,
            ),
            parentRunId: targetSessionId,
            roleIds: targetCard.roleIds,
            openQuestions: mergedSnapshot.openQuestions,
          ),
        ),
        parentRunId: targetSessionId,
        evidenceRefs: mergedSnapshot.evidence,
      ),
    );
    final meta = targetNode.meta ?? const AiSegmentMeta();
    final updatedCard = targetCard.copyWith(
      status: status.trim().isEmpty ? targetCard.status : status.trim(),
      sourceRefCount: sourceRefCount,
      snapshot: mergedSnapshot,
    );
    _tree = _tree.copyWithNode(
      targetNodeId,
      targetNode.copyWith(
        message: ChatMessage.ai(seminarRunCardPromptText(updatedCard)).toMap(),
        meta: AiSegmentMeta(
          model: meta.model,
          inputTokens: meta.inputTokens,
          outputTokens: meta.outputTokens,
          seminarRunCard: updatedCard,
        ),
      ),
    );
    _rebuildFromTree();
    await _recordSeminarTerminalArtifactActionEvents(
      seminarSessionId: targetSessionId,
      snapshot: mergedSnapshot,
    );

    final sessionId = _currentSessionId;
    if (sessionId == null) return true;
    final serviceId = Prefs().selectedAiService;
    final config = Prefs().getAiConfig(serviceId);
    final model = (config['model'])?.trim() ?? '';
    final historyNotifier = ref.read(aiHistoryProvider.notifier);
    final existing = historyNotifier.findById(sessionId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final bookContext = _readCurrentBookContext(ref.read);
    final historyBookContext = _historyBookContextFor(
      existing: existing,
      current: bookContext,
    );
    final currentMessages = List<ChatMessage>.from(state.value ?? const []);
    final fallbackTitle = _titleService.deriveFallbackTitle(currentMessages);
    final entry = (existing ??
            AiChatHistoryEntry(
              id: sessionId,
              serviceId: serviceId,
              model: model,
              createdAt: now,
              updatedAt: now,
              title: fallbackTitle,
              titleSource: 'heuristic',
              bookId: historyBookContext.bookId,
              bookTitle: historyBookContext.bookTitle,
              messages: currentMessages,
              completed: true,
            ))
        .copyWith(
      serviceId: serviceId,
      messages: currentMessages,
      updatedAt: now,
      completed: true,
      model: model,
      title: (existing?.title?.trim().isNotEmpty ?? false)
          ? existing!.title
          : fallbackTitle,
      titleSource: (existing?.titleSource?.trim().isNotEmpty ?? false)
          ? existing!.titleSource
          : 'heuristic',
      bookId: historyBookContext.bookId,
      bookTitle: historyBookContext.bookTitle,
      conversationV2: _tree.toJson(),
    );
    if (_draftEntry?.id == entry.id) {
      _draftEntry = entry;
    }
    await _queueDraftHistoryUpsert(historyNotifier, entry);
    return true;
  }

  Future<void> _recordSeminarTerminalArtifactActionEvents({
    required String seminarSessionId,
    AiSeminarRunCardSnapshot? snapshot,
  }) async {
    final sessionId = seminarSessionId.trim();
    if (sessionId.isEmpty || documentPath.trim().isEmpty) return;
    final parts =
        snapshot?.messageParts ?? const <AiSeminarRunCardMessagePart>[];
    if (parts.isEmpty) return;
    final terminalActions = <String>{};
    final evidenceByAction = <String, List<AiSeminarRunCardEvidenceSnapshot>>{};
    final textByAction = <String, String>{};
    for (final part in parts) {
      if (!_isSeminarArtifactActionsPart(part)) continue;
      for (final rawActionId in part.actionIds) {
        final actionId = rawActionId.trim();
        if (!_isRecordedSeminarArtifactActionId(actionId)) continue;
        if (!terminalActions.add(actionId)) continue;
        evidenceByAction[actionId] = part.evidenceRefs
            .where((evidence) => !evidence.isEmpty)
            .toList(growable: false);
        final text = part.text?.trim();
        if (text != null && text.isNotEmpty) {
          textByAction[actionId] = text;
        }
      }
    }
    if (terminalActions.isEmpty) return;
    try {
      final store = AgentRunGraphStore();
      for (final actionId in terminalActions) {
        await store.upsertEvent(AgentRunEvent(
          eventId: '$sessionId:artifact-action:$actionId',
          runId: sessionId,
          type: AgentRunEventType.artifactAction,
          createdAt: DateTime.now(),
          status: SubAgentRunStatus.completed,
          roleId: 'director',
          nickname: 'Director',
          actionIds: [actionId],
          result: textByAction[actionId],
          evidenceRefs: evidenceByAction[actionId] ??
              const <AiSeminarRunCardEvidenceSnapshot>[],
        ));
      }
    } catch (_) {
      // Snapshot persistence should not fail because optional graph replay did.
    }
  }

  Future<bool> closeSeminarRunCardAgent({
    required String seminarSessionId,
    required String agentRunId,
    DateTime? now,
  }) async {
    final targetSessionId = seminarSessionId.trim();
    final targetRunId = agentRunId.trim();
    if (targetSessionId.isEmpty || targetRunId.isEmpty) return false;
    final card = _seminarRunCardBySessionId(targetSessionId);
    if (card == null) return false;

    final graphStore = AgentRunGraphStore();
    try {
      final run = await graphStore.getRun(targetRunId);
      if (run == null || run.parentRunId != targetSessionId) return false;
      final closedAt = now ?? DateTime.now();
      await graphStore.upsertEvent(AgentRunEvent(
        eventId:
            '$targetRunId:close-request:${closedAt.microsecondsSinceEpoch}',
        runId: targetRunId,
        parentRunId: targetSessionId,
        type: AgentRunEventType.closeRequest,
        createdAt: closedAt,
        roleId: run.roleId,
        nickname: run.nickname,
        acknowledgedAt: closedAt,
      ));
      if (!_isTerminalSeminarAgentRunStatus(run.status)) {
        await graphStore.closeChildRun(
          parentRunId: targetSessionId,
          childRunId: targetRunId,
          now: closedAt,
        );
      }
      final replayParts = await seminarMessagePartsFromAgentRunGraphStore(
        graphStore,
        parentRunId: targetSessionId,
      );
      final snapshot = _appendSeminarMessageParts(
        card.snapshot,
        replayParts,
      );
      return updateSeminarRunCardSnapshot(
        seminarSessionId: targetSessionId,
        status: card.status,
        snapshot: snapshot,
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> waitSeminarRunCardAgent({
    required String seminarSessionId,
    required String agentRunId,
    DateTime? now,
  }) async {
    final targetSessionId = seminarSessionId.trim();
    final targetRunId = agentRunId.trim();
    if (targetSessionId.isEmpty || targetRunId.isEmpty) return false;
    final card = _seminarRunCardBySessionId(targetSessionId);
    if (card == null) return false;

    final graphStore = AgentRunGraphStore();
    try {
      final run = await graphStore.getRun(targetRunId);
      if (run?.parentRunId != targetSessionId) return false;
      final createdAt = now ?? DateTime.now();
      final waitSatisfied = _isSettledSeminarAgentRunStatusForWait(run!.status);
      final waitEvents = (await graphStore.listEvents(targetRunId))
          .where(
            (event) =>
                event.parentRunId == targetSessionId &&
                event.type == AgentRunEventType.waitRequest,
          )
          .toList(growable: false);
      final pendingWaitEvents = waitEvents
          .where((event) => event.acknowledgedAt == null)
          .toList(growable: false);
      if (waitSatisfied && pendingWaitEvents.isNotEmpty) {
        for (final event in pendingWaitEvents) {
          await graphStore.acknowledgeControlEvent(
            parentRunId: targetSessionId,
            childRunId: targetRunId,
            eventId: event.eventId,
            now: createdAt,
          );
        }
      } else if (waitEvents.isEmpty ||
          (!waitSatisfied && pendingWaitEvents.isEmpty)) {
        await graphStore.upsertEvent(AgentRunEvent(
          eventId:
              '$targetRunId:wait-request:${createdAt.microsecondsSinceEpoch}',
          runId: targetRunId,
          parentRunId: targetSessionId,
          type: AgentRunEventType.waitRequest,
          createdAt: createdAt,
          roleId: run.roleId,
          nickname: run.nickname,
          delta: 'Waiting for role to finish.',
          acknowledgedAt: waitSatisfied ? createdAt : null,
        ));
      }
      final replayParts = await seminarMessagePartsFromAgentRunGraphStore(
        graphStore,
        parentRunId: targetSessionId,
      );
      if (replayParts.isEmpty) return false;
      final snapshot = _appendSeminarMessageParts(
        card.snapshot,
        replayParts,
      );
      return updateSeminarRunCardSnapshot(
        seminarSessionId: targetSessionId,
        status: card.status,
        snapshot: snapshot,
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> refreshSeminarRunCardAgentGraph({
    required String seminarSessionId,
  }) async {
    final targetSessionId = seminarSessionId.trim();
    if (targetSessionId.isEmpty) return false;
    final card = _seminarRunCardBySessionId(targetSessionId);
    if (card == null) return false;

    final graphStore = AgentRunGraphStore();
    try {
      final replayParts = await seminarMessagePartsFromAgentRunGraphStore(
        graphStore,
        parentRunId: targetSessionId,
      );
      if (replayParts.isEmpty) return false;
      final snapshot = _appendSeminarMessageParts(
        card.snapshot,
        replayParts,
      );
      return updateSeminarRunCardSnapshot(
        seminarSessionId: targetSessionId,
        status: card.status,
        snapshot: snapshot,
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> waitSeminarRunCardToolCall({
    required String seminarSessionId,
    required String agentRunId,
    required String toolCallId,
    DateTime? now,
  }) async {
    final targetSessionId = seminarSessionId.trim();
    final targetRunId = agentRunId.trim();
    final targetToolCallId = toolCallId.trim();
    if (targetSessionId.isEmpty ||
        targetRunId.isEmpty ||
        targetToolCallId.isEmpty) {
      return false;
    }
    final card = _seminarRunCardBySessionId(targetSessionId);
    if (card == null) return false;

    final graphStore = AgentRunGraphStore();
    try {
      final events = await graphStore.listEvents(targetRunId);
      final toolEvents = events
          .where(
            (event) =>
                event.eventId == targetToolCallId &&
                event.parentRunId == targetSessionId &&
                event.type == AgentRunEventType.toolCall,
          )
          .toList(growable: false);
      if (toolEvents.isEmpty) return false;
      final toolEvent = toolEvents.last;
      final createdAt = now ?? DateTime.now();
      final waitSatisfied = _isTerminalSeminarToolCallStatus(toolEvent.status);
      final waitEvents = events
          .where(
            (event) =>
                event.parentRunId == targetSessionId &&
                event.type == AgentRunEventType.waitRequest &&
                _isSeminarToolWaitRequestForToolCall(
                  event,
                  toolCallId: targetToolCallId,
                  toolEvent: toolEvent,
                ),
          )
          .toList(growable: false);
      final pendingWaitEvents = waitEvents
          .where((event) => event.acknowledgedAt == null)
          .toList(growable: false);
      if (waitSatisfied && pendingWaitEvents.isNotEmpty) {
        for (final event in pendingWaitEvents) {
          await graphStore.acknowledgeControlEvent(
            parentRunId: targetSessionId,
            childRunId: targetRunId,
            eventId: event.eventId,
            now: createdAt,
          );
        }
      } else if (waitEvents.isEmpty ||
          (!waitSatisfied && pendingWaitEvents.isEmpty)) {
        await graphStore.upsertEvent(AgentRunEvent(
          eventId:
              '$targetRunId:wait-tool-call:$targetToolCallId:${createdAt.microsecondsSinceEpoch}',
          runId: targetRunId,
          parentRunId: targetSessionId,
          type: AgentRunEventType.waitRequest,
          createdAt: createdAt,
          roleId: toolEvent.roleId,
          nickname: toolEvent.nickname,
          toolId: toolEvent.toolId,
          query: toolEvent.query,
          delta: 'Waiting for tool call to finish.',
          result: targetToolCallId,
          acknowledgedAt: waitSatisfied ? createdAt : null,
        ));
      }
      final replayParts = await seminarMessagePartsFromAgentRunGraphStore(
        graphStore,
        parentRunId: targetSessionId,
      );
      if (replayParts.isEmpty) return false;
      final snapshot = _appendSeminarMessageParts(
        card.snapshot,
        replayParts,
      );
      return updateSeminarRunCardSnapshot(
        seminarSessionId: targetSessionId,
        status: card.status,
        snapshot: snapshot,
      );
    } catch (_) {
      return false;
    }
  }

  bool _isSeminarToolWaitRequestForToolCall(
    AgentRunEvent event, {
    required String toolCallId,
    required AgentRunEvent toolEvent,
  }) {
    if (event.result?.trim() == toolCallId) return true;
    if (event.eventId.trim().contains(':wait-tool-call:$toolCallId:')) {
      return true;
    }
    final toolId = event.toolId?.trim();
    if (toolId == null ||
        toolId.isEmpty ||
        toolId != toolEvent.toolId?.trim()) {
      return false;
    }
    final query = event.query?.trim();
    final toolQuery = toolEvent.query?.trim();
    return query == null ||
        query.isEmpty ||
        toolQuery == null ||
        toolQuery.isEmpty ||
        query == toolQuery;
  }

  AgentRunEvent? _terminalSeminarToolCallForWaitRequest(
    AgentRunEvent waitEvent,
    List<AgentRunEvent> events, {
    required String sessionId,
  }) {
    if (waitEvent.parentRunId != sessionId ||
        waitEvent.type != AgentRunEventType.waitRequest) {
      return null;
    }
    final terminalToolEvents = events
        .where(
          (event) =>
              event.parentRunId == sessionId &&
              event.runId == waitEvent.runId &&
              event.type == AgentRunEventType.toolCall &&
              _isTerminalSeminarToolCallStatus(event.status) &&
              _isSeminarToolWaitRequestForToolCall(
                waitEvent,
                toolCallId: event.eventId,
                toolEvent: event,
              ),
        )
        .toList(growable: false);
    if (terminalToolEvents.isEmpty) return null;
    terminalToolEvents.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return terminalToolEvents.last;
  }

  Future<bool> cancelSeminarRunCardToolCall({
    required String seminarSessionId,
    required String agentRunId,
    required String toolCallId,
    DateTime? now,
  }) async {
    final targetSessionId = seminarSessionId.trim();
    final targetRunId = agentRunId.trim();
    final targetToolCallId = toolCallId.trim();
    if (targetSessionId.isEmpty ||
        targetRunId.isEmpty ||
        targetToolCallId.isEmpty) {
      return false;
    }
    final card = _seminarRunCardBySessionId(targetSessionId);
    if (card == null) return false;

    final graphStore = AgentRunGraphStore();
    try {
      final events = await graphStore.listEvents(targetRunId);
      final toolEvents = events
          .where(
            (event) =>
                event.eventId == targetToolCallId &&
                event.parentRunId == targetSessionId &&
                event.type == AgentRunEventType.toolCall,
          )
          .toList(growable: false);
      if (toolEvents.isEmpty) return false;
      final toolEvent = toolEvents.last;
      final requestedAt = now ?? DateTime.now();
      final cancelledAt = requestedAt.isAfter(toolEvent.createdAt)
          ? requestedAt
          : toolEvent.createdAt.add(const Duration(microseconds: 1));
      await graphStore.upsertEvent(AgentRunEvent(
        eventId:
            '$targetRunId:cancel-tool-call:$targetToolCallId:${cancelledAt.millisecondsSinceEpoch}',
        runId: targetRunId,
        parentRunId: targetSessionId,
        type: AgentRunEventType.cancelRequest,
        createdAt: requestedAt,
        roleId: toolEvent.roleId,
        nickname: toolEvent.nickname,
        toolId: toolEvent.toolId,
        query: toolEvent.query,
        result: targetToolCallId,
        acknowledgedAt: requestedAt,
      ));
      if (!_isTerminalSeminarToolCallStatus(toolEvent.status)) {
        await graphStore.upsertEvent(AgentRunEvent(
          eventId: toolEvent.eventId,
          runId: toolEvent.runId,
          parentRunId: toolEvent.parentRunId,
          type: AgentRunEventType.toolCall,
          createdAt: cancelledAt,
          status: SubAgentRunStatus.shutdown,
          roleId: toolEvent.roleId,
          nickname: toolEvent.nickname,
          toolId: toolEvent.toolId,
          query: toolEvent.query,
          resultCount: toolEvent.resultCount,
          roleIds: toolEvent.roleIds,
          allowedToolIds: toolEvent.allowedToolIds,
          evidenceRefs: toolEvent.evidenceRefs,
          delta: toolEvent.delta,
          error: toolEvent.error ?? 'Tool call cancelled by reader.',
        ));
      }

      final run = await graphStore.getRun(targetRunId);
      if (run?.parentRunId == targetSessionId &&
          !_isTerminalSeminarAgentRunStatus(run!.status)) {
        await graphStore.closeChildRun(
          parentRunId: targetSessionId,
          childRunId: targetRunId,
          now: cancelledAt,
        );
      }
      final replayParts = await seminarMessagePartsFromAgentRunGraphStore(
        graphStore,
        parentRunId: targetSessionId,
      );
      if (replayParts.isEmpty) return false;
      final snapshot = _appendSeminarMessageParts(
        card.snapshot,
        replayParts,
      );
      return updateSeminarRunCardSnapshot(
        seminarSessionId: targetSessionId,
        status: card.status,
        snapshot: snapshot,
      );
    } catch (_) {
      return false;
    }
  }

  bool _isTerminalSeminarAgentRunStatus(SubAgentRunStatus status) {
    return status == SubAgentRunStatus.completed ||
        status == SubAgentRunStatus.errored ||
        status == SubAgentRunStatus.shutdown ||
        status == SubAgentRunStatus.notFound;
  }

  bool _isTerminalSeminarToolCallStatus(SubAgentRunStatus? status) {
    return status == SubAgentRunStatus.completed ||
        status == SubAgentRunStatus.errored ||
        status == SubAgentRunStatus.interrupted ||
        status == SubAgentRunStatus.shutdown ||
        status == SubAgentRunStatus.notFound;
  }

  bool _isSettledSeminarAgentRunStatusForWait(SubAgentRunStatus status) {
    return _isTerminalSeminarAgentRunStatus(status) ||
        status == SubAgentRunStatus.interrupted;
  }

  Future<bool> sendSeminarRunCardAgentInput({
    required String seminarSessionId,
    required String agentRunId,
    required String inputText,
    DateTime? now,
  }) async {
    final targetSessionId = seminarSessionId.trim();
    final targetRunId = agentRunId.trim();
    final text = inputText.trim();
    if (targetSessionId.isEmpty || targetRunId.isEmpty || text.isEmpty) {
      return false;
    }
    final card = _seminarRunCardBySessionId(targetSessionId);
    if (card == null) return false;

    final graphStore = AgentRunGraphStore();
    try {
      final run = await graphStore.getRun(targetRunId);
      if (run?.parentRunId != targetSessionId) return false;
      if (run!.status != SubAgentRunStatus.waitingInput) {
        if (!_isTerminalSeminarAgentRunStatus(run.status)) return false;
        final replayParts = await seminarMessagePartsFromAgentRunGraphStore(
          graphStore,
          parentRunId: targetSessionId,
        );
        if (replayParts.isEmpty) return false;
        final snapshot = _appendSeminarMessageParts(
          card.snapshot,
          replayParts,
        );
        return updateSeminarRunCardSnapshot(
          seminarSessionId: targetSessionId,
          status: card.status,
          snapshot: snapshot,
        );
      }
      final pendingControls = await graphStore.listPendingControlEvents(
        parentRunId: targetSessionId,
        childRunId: targetRunId,
      );
      final hasDuplicateInput = pendingControls.any(
        (event) =>
            event.type == AgentRunEventType.userInput &&
            (event.delta ?? '').trim() == text,
      );
      if (!hasDuplicateInput) {
        final createdAt = now ?? DateTime.now();
        await graphStore.upsertEvent(AgentRunEvent(
          eventId:
              '$targetRunId:user-input:${createdAt.microsecondsSinceEpoch}',
          runId: targetRunId,
          parentRunId: targetSessionId,
          type: AgentRunEventType.userInput,
          createdAt: createdAt,
          roleId: run.roleId,
          nickname: run.nickname,
          delta: text,
        ));
      }
      final replayParts = await seminarMessagePartsFromAgentRunGraphStore(
        graphStore,
        parentRunId: targetSessionId,
      );
      final snapshot = _appendSeminarMessageParts(
        card.snapshot,
        replayParts,
      );
      return updateSeminarRunCardSnapshot(
        seminarSessionId: targetSessionId,
        status: card.status,
        snapshot: snapshot,
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> resumeSeminarRunCardAgent({
    required String seminarSessionId,
    required String agentRunId,
    DateTime? now,
  }) async {
    final targetSessionId = seminarSessionId.trim();
    final targetRunId = agentRunId.trim();
    if (targetSessionId.isEmpty || targetRunId.isEmpty) return false;
    final card = _seminarRunCardBySessionId(targetSessionId);
    if (card == null) return false;

    final graphStore = AgentRunGraphStore();
    try {
      final run = await graphStore.getRun(targetRunId);
      if (run?.parentRunId != targetSessionId) return false;
      if (run!.status != SubAgentRunStatus.interrupted) {
        if (!_isTerminalSeminarAgentRunStatus(run.status)) return false;
        final replayParts = await seminarMessagePartsFromAgentRunGraphStore(
          graphStore,
          parentRunId: targetSessionId,
        );
        if (replayParts.isEmpty) return false;
        final snapshot = _appendSeminarMessageParts(
          card.snapshot,
          replayParts,
        );
        return updateSeminarRunCardSnapshot(
          seminarSessionId: targetSessionId,
          status: card.status,
          snapshot: snapshot,
        );
      }
      final createdAt = now ?? DateTime.now();
      final pendingControls = await graphStore.listPendingControlEvents(
        parentRunId: targetSessionId,
        childRunId: targetRunId,
      );
      final hasPendingResume = pendingControls.any(
        (event) => event.type == AgentRunEventType.resumeRequest,
      );
      if (!hasPendingResume) {
        await graphStore.upsertEvent(AgentRunEvent(
          eventId:
              '$targetRunId:resume-request:${createdAt.microsecondsSinceEpoch}',
          runId: targetRunId,
          parentRunId: targetSessionId,
          type: AgentRunEventType.resumeRequest,
          createdAt: createdAt,
          roleId: run.roleId,
          nickname: run.nickname,
        ));
      }
      final replayParts = await seminarMessagePartsFromAgentRunGraphStore(
        graphStore,
        parentRunId: targetSessionId,
      );
      final snapshot = _appendSeminarMessageParts(
        card.snapshot,
        replayParts,
      );
      return updateSeminarRunCardSnapshot(
        seminarSessionId: targetSessionId,
        status: card.status,
        snapshot: snapshot,
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> retrySeminarRunCardAgent({
    required String seminarSessionId,
    required String agentRunId,
    DateTime? now,
  }) async {
    final targetSessionId = seminarSessionId.trim();
    final targetRunId = agentRunId.trim();
    if (targetSessionId.isEmpty || targetRunId.isEmpty) return false;
    final card = _seminarRunCardBySessionId(targetSessionId);
    if (card == null) return false;

    final graphStore = AgentRunGraphStore();
    try {
      final run = await graphStore.getRun(targetRunId);
      if (run?.parentRunId != targetSessionId) return false;
      if (run!.status != SubAgentRunStatus.errored) {
        if (!_isTerminalSeminarAgentRunStatus(run.status)) return false;
        final replayParts = await seminarMessagePartsFromAgentRunGraphStore(
          graphStore,
          parentRunId: targetSessionId,
        );
        if (replayParts.isEmpty) return false;
        final snapshot = _appendSeminarMessageParts(
          card.snapshot,
          replayParts,
        );
        return updateSeminarRunCardSnapshot(
          seminarSessionId: targetSessionId,
          status: card.status,
          snapshot: snapshot,
        );
      }
      final createdAt = now ?? DateTime.now();
      final pendingControls = await graphStore.listPendingControlEvents(
        parentRunId: targetSessionId,
        childRunId: targetRunId,
      );
      final hasPendingRetry = pendingControls.any(
        (event) => event.type == AgentRunEventType.retryRequest,
      );
      if (!hasPendingRetry) {
        await graphStore.upsertEvent(AgentRunEvent(
          eventId:
              '$targetRunId:retry-request:${createdAt.microsecondsSinceEpoch}',
          runId: targetRunId,
          parentRunId: targetSessionId,
          type: AgentRunEventType.retryRequest,
          createdAt: createdAt,
          roleId: run.roleId,
          nickname: run.nickname,
        ));
      }
      final replayParts = await seminarMessagePartsFromAgentRunGraphStore(
        graphStore,
        parentRunId: targetSessionId,
      );
      final snapshot = _appendSeminarMessageParts(
        card.snapshot,
        replayParts,
      );
      return updateSeminarRunCardSnapshot(
        seminarSessionId: targetSessionId,
        status: card.status,
        snapshot: snapshot,
      );
    } catch (_) {
      return false;
    }
  }

  AiSeminarRunCardSnapshot? _mergeSeminarRunCardSnapshot({
    required AiSeminarRunCardSnapshot? existing,
    required AiSeminarRunCardSnapshot? next,
  }) {
    if (existing == null || next == null) return next;
    final protectedNext =
        _protectSeminarTerminalArtifactActions(existing: existing, next: next);
    final timedProtectedNext = _seminarSnapshotWithToolCalls(
      protectedNext,
      _mergeExistingSeminarToolCallSnapshotTiming(
        existing.toolCalls,
        protectedNext.toolCalls,
      ),
    );
    final protectedNextParts = _mergeExistingSeminarToolCallTiming(
      existing.messageParts,
      _protectTerminalSeminarReaderControlParts(
        existing.messageParts,
        _mergeExistingTerminalSeminarRuntimeControlParts(
          existing.messageParts,
          _mergeExistingSeminarRuntimeControlReaderTurns(
            existing.messageParts,
            _mergeExistingSeminarWaitReaderTurns(
              existing.messageParts,
              _protectUnreopenableSeminarStatusParts(
                existing.messageParts,
                timedProtectedNext.messageParts,
              ),
            ),
          ),
        ),
      ),
    );
    final shouldPreserveSetup = !protectedNextParts.any(_isSeminarRunSetupPart);
    final shouldPreserveContradictionScans =
        !protectedNextParts.any(_isSeminarContradictionScanPart);
    if (!shouldPreserveSetup && !shouldPreserveContradictionScans) {
      return _seminarSnapshotWithMessageParts(
        timedProtectedNext,
        _suppressPendingSeminarRuntimeControlActions(protectedNextParts),
      );
    }
    final preservedSetupParts = shouldPreserveSetup
        ? existing.messageParts
            .where(_isSeminarRunSetupPart)
            .toList(growable: false)
        : const <AiSeminarRunCardMessagePart>[];
    final preservedContradictionScans = shouldPreserveContradictionScans
        ? existing.messageParts
            .where(_isSeminarContradictionScanPart)
            .toList(growable: false)
        : const <AiSeminarRunCardMessagePart>[];
    if (preservedSetupParts.isEmpty && preservedContradictionScans.isEmpty) {
      return _seminarSnapshotWithMessageParts(
        timedProtectedNext,
        _suppressPendingSeminarRuntimeControlActions(protectedNextParts),
      );
    }
    return AiSeminarRunCardSnapshot(
      evidence: timedProtectedNext.evidence,
      toolCalls: timedProtectedNext.toolCalls,
      roleSummaries: timedProtectedNext.roleSummaries,
      messageParts: [
        ...preservedSetupParts,
        ..._suppressPendingSeminarRuntimeControlActions(protectedNextParts),
        ...preservedContradictionScans,
      ],
      synthesisSummary: timedProtectedNext.synthesisSummary,
      disagreements: timedProtectedNext.disagreements,
      disagreementDetails: timedProtectedNext.disagreementDetails,
      openQuestions: timedProtectedNext.openQuestions,
    );
  }

  AiSeminarRunCardSnapshot _seminarSnapshotWithToolCalls(
    AiSeminarRunCardSnapshot snapshot,
    List<AiSeminarRunCardToolCallSnapshot> toolCalls,
  ) {
    return AiSeminarRunCardSnapshot(
      evidence: snapshot.evidence,
      toolCalls: toolCalls,
      roleSummaries: snapshot.roleSummaries,
      messageParts: snapshot.messageParts,
      synthesisSummary: snapshot.synthesisSummary,
      disagreements: snapshot.disagreements,
      disagreementDetails: snapshot.disagreementDetails,
      openQuestions: snapshot.openQuestions,
    );
  }

  AiSeminarRunCardSnapshot _seminarSnapshotWithMessageParts(
    AiSeminarRunCardSnapshot snapshot,
    List<AiSeminarRunCardMessagePart> messageParts,
  ) {
    return AiSeminarRunCardSnapshot(
      evidence: snapshot.evidence,
      toolCalls: snapshot.toolCalls,
      roleSummaries: snapshot.roleSummaries,
      messageParts: messageParts,
      synthesisSummary: snapshot.synthesisSummary,
      disagreements: snapshot.disagreements,
      disagreementDetails: snapshot.disagreementDetails,
      openQuestions: snapshot.openQuestions,
    );
  }

  List<AiSeminarRunCardMessagePart> _mergeExistingSeminarToolCallTiming(
    List<AiSeminarRunCardMessagePart> existingParts,
    List<AiSeminarRunCardMessagePart> nextParts,
  ) {
    if (existingParts.isEmpty || nextParts.isEmpty) return nextParts;
    return nextParts.map((part) {
      if (part.type.trim() != 'tool_call') {
        return part;
      }
      final matchingExisting = existingParts
          .where((existing) => _isSameSeminarToolCallPart(existing, part))
          .toList(growable: false);
      if (matchingExisting.isEmpty) return part;
      final startedAt = existingParts
          .where(
            (existing) =>
                matchingExisting.contains(existing) &&
                existing.startedAt != null &&
                existing.startedAt! > 0,
          )
          .map((existing) => existing.startedAt!)
          .fold<int?>(null, (current, value) {
        if (current == null || value < current) return value;
        return current;
      });
      final mergedStartedAt = (part.startedAt != null && part.startedAt! > 0)
          ? part.startedAt
          : startedAt;
      final mergedRoleIds = part.roleIds.isNotEmpty
          ? part.roleIds
          : matchingExisting.map((existing) => existing.roleIds).firstWhere(
                (roleIds) => roleIds.isNotEmpty,
                orElse: () => part.roleIds,
              );
      final mergedEvidenceRefs = part.evidenceRefs.isNotEmpty
          ? part.evidenceRefs
          : matchingExisting
              .map((existing) => existing.evidenceRefs)
              .firstWhere(
                (evidenceRefs) => evidenceRefs.isNotEmpty,
                orElse: () => part.evidenceRefs,
              );
      final mergedQuery = _trimSeminarMessageValue(part.query).isNotEmpty
          ? part.query
          : matchingExisting.map((existing) => existing.query).firstWhere(
                (query) => _trimSeminarMessageValue(query).isNotEmpty,
                orElse: () => part.query,
              );
      if (mergedStartedAt == part.startedAt &&
          mergedRoleIds == part.roleIds &&
          mergedEvidenceRefs == part.evidenceRefs &&
          mergedQuery == part.query) {
        return part;
      }
      return AiSeminarRunCardMessagePart(
        type: part.type,
        id: part.id,
        agentRunId: part.agentRunId,
        parentRunId: part.parentRunId,
        roleId: part.roleId,
        roleIds: mergedRoleIds,
        actionIds: part.actionIds,
        allowedToolIds: part.allowedToolIds,
        defaultRoleId: part.defaultRoleId,
        defaultActionId: part.defaultActionId,
        selectedRoleId: part.selectedRoleId,
        selectedActionId: part.selectedActionId,
        draftText: part.draftText,
        toolId: part.toolId,
        status: part.status,
        label: part.label,
        text: part.text,
        query: mergedQuery,
        resultCount: part.resultCount,
        startedAt: mergedStartedAt,
        completedAt: part.completedAt,
        evidenceRefs: mergedEvidenceRefs,
      );
    }).toList(growable: false);
  }

  List<AiSeminarRunCardToolCallSnapshot>
      _mergeExistingSeminarToolCallSnapshotTiming(
    List<AiSeminarRunCardToolCallSnapshot> existingCalls,
    List<AiSeminarRunCardToolCallSnapshot> nextCalls,
  ) {
    if (existingCalls.isEmpty || nextCalls.isEmpty) return nextCalls;
    return nextCalls.map((call) {
      final matchingExisting = existingCalls
          .where((existing) => _isSameSeminarToolCallSnapshot(existing, call))
          .toList(growable: false);
      if (matchingExisting.isEmpty) return call;
      final startedAt = existingCalls
          .where(
            (existing) =>
                matchingExisting.contains(existing) &&
                existing.startedAt != null &&
                existing.startedAt! > 0,
          )
          .map((existing) => existing.startedAt!)
          .fold<int?>(null, (current, value) {
        if (current == null || value < current) return value;
        return current;
      });
      final mergedStartedAt = (call.startedAt != null && call.startedAt! > 0)
          ? call.startedAt
          : startedAt;
      final mergedRoleIds = call.roleIds.isNotEmpty
          ? call.roleIds
          : matchingExisting.map((existing) => existing.roleIds).firstWhere(
                (roleIds) => roleIds.isNotEmpty,
                orElse: () => call.roleIds,
              );
      final mergedEvidenceRefs = call.evidenceRefs.isNotEmpty
          ? call.evidenceRefs
          : matchingExisting
              .map((existing) => existing.evidenceRefs)
              .firstWhere(
                (evidenceRefs) => evidenceRefs.isNotEmpty,
                orElse: () => call.evidenceRefs,
              );
      final mergedActionIds = call.actionIds.isNotEmpty
          ? call.actionIds
          : matchingExisting.map((existing) => existing.actionIds).firstWhere(
                (actionIds) => actionIds.isNotEmpty,
                orElse: () => call.actionIds,
              );
      final mergedQuery = call.query.trim().isNotEmpty
          ? call.query
          : matchingExisting.map((existing) => existing.query).firstWhere(
                (query) => query.trim().isNotEmpty,
                orElse: () => call.query,
              );
      if (mergedStartedAt == call.startedAt &&
          mergedRoleIds == call.roleIds &&
          mergedEvidenceRefs == call.evidenceRefs &&
          mergedActionIds == call.actionIds &&
          mergedQuery == call.query) {
        return call;
      }
      return AiSeminarRunCardToolCallSnapshot(
        id: call.id,
        agentRunId: call.agentRunId,
        parentRunId: call.parentRunId,
        toolId: call.toolId,
        status: call.status,
        label: call.label,
        text: call.text,
        query: mergedQuery,
        resultCount: call.resultCount,
        startedAt: mergedStartedAt,
        completedAt: call.completedAt,
        roleIds: mergedRoleIds,
        actionIds: mergedActionIds,
        evidenceRefs: mergedEvidenceRefs,
      );
    }).toList(growable: false);
  }

  bool _isSameSeminarToolCallSnapshot(
    AiSeminarRunCardToolCallSnapshot existing,
    AiSeminarRunCardToolCallSnapshot incoming,
  ) {
    final existingId = _trimSeminarMessageValue(existing.id);
    final incomingId = _trimSeminarMessageValue(incoming.id);
    if (existingId.isNotEmpty &&
        incomingId.isNotEmpty &&
        existingId == incomingId) {
      return true;
    }
    final existingRunId = _trimSeminarMessageValue(existing.agentRunId);
    final incomingRunId = _trimSeminarMessageValue(incoming.agentRunId);
    if (existingRunId.isNotEmpty || incomingRunId.isNotEmpty) {
      if (existingRunId.isNotEmpty &&
          incomingRunId.isNotEmpty &&
          existingRunId != incomingRunId) {
        return false;
      }
      if ((existingRunId.isEmpty || incomingRunId.isEmpty) &&
          _trimSeminarMessageValue(existing.parentRunId) !=
              _trimSeminarMessageValue(incoming.parentRunId)) {
        return false;
      }
    } else if (_trimSeminarMessageValue(existing.parentRunId) !=
        _trimSeminarMessageValue(incoming.parentRunId)) {
      return false;
    }
    return _trimSeminarMessageValue(existing.toolId) ==
            _trimSeminarMessageValue(incoming.toolId) &&
        _trimSeminarMessageValue(existing.query) ==
            _trimSeminarMessageValue(incoming.query);
  }

  List<AiSeminarRunCardMessagePart> _mergeExistingSeminarWaitReaderTurns(
    List<AiSeminarRunCardMessagePart> existingParts,
    List<AiSeminarRunCardMessagePart> nextParts,
  ) {
    var merged = nextParts.toList(growable: true);
    for (final existing in existingParts) {
      if (!_isSeminarWaitReaderTurn(existing)) continue;
      final runId = _seminarMessagePartRunId(existing);
      if (runId == null || runId.isEmpty) continue;

      if (_isSeminarToolCallWaitReaderTurn(existing)) {
        final alreadyMerged = merged.any(
          (part) =>
              _isSeminarToolCallWaitReaderTurn(part) &&
              _seminarToolWaitMatchesToolCallReaderTurn(part, existing),
        );
        if (alreadyMerged) continue;

        final terminalIndex = merged.indexWhere(
          (part) =>
              _isTerminalSeminarToolCallPart(part) &&
              _seminarToolWaitMatchesToolCall(existing, part),
        );
        final terminalPart = terminalIndex >= 0 ? merged[terminalIndex] : null;
        final preserved = terminalPart == null
            ? existing
            : _completedSeminarWaitReaderTurn(
                existing,
                completedAt: terminalPart.completedAt,
              );
        if (terminalIndex >= 0) {
          merged.insert(terminalIndex, preserved);
        } else {
          merged.add(preserved);
        }
        continue;
      }

      final alreadyMerged = merged.any(
        (part) =>
            _isSeminarRoleWaitReaderTurn(part) &&
            _seminarMessagePartRunId(part) == runId,
      );
      if (alreadyMerged) continue;

      final terminalIndex = merged.indexWhere(
        (part) =>
            _isGraphTracedSeminarRoleWaitSettledPart(part) &&
            _seminarMessagePartRunId(part) == runId,
      );
      final preserved = terminalIndex >= 0
          ? _completedSeminarWaitReaderTurn(existing)
          : existing;
      if (terminalIndex >= 0) {
        merged.insert(terminalIndex, preserved);
      } else {
        merged.add(preserved);
      }
    }
    return merged;
  }

  List<AiSeminarRunCardMessagePart>
      _mergeExistingSeminarRuntimeControlReaderTurns(
    List<AiSeminarRunCardMessagePart> existingParts,
    List<AiSeminarRunCardMessagePart> nextParts,
  ) {
    var merged = nextParts.toList(growable: true);
    for (final existing in existingParts) {
      if (!_isSeminarRuntimeControlReaderTurn(existing) ||
          _trimSeminarMessageValue(existing.status) != 'pending') {
        continue;
      }
      final runId = _seminarMessagePartRunId(existing);
      if (runId == null || runId.isEmpty) continue;
      final label = _trimSeminarMessageValue(existing.label);
      final alreadyMerged = merged.any(
        (part) =>
            _isSeminarRuntimeControlReaderTurn(part) &&
            _trimSeminarMessageValue(part.label) == label &&
            _seminarMessagePartRunId(part) == runId,
      );
      if (alreadyMerged) continue;

      final terminalIndex = merged.indexWhere(
        (part) =>
            _isGraphTracedSeminarRoleTerminalPart(part) &&
            _seminarMessagePartRunId(part) == runId,
      );
      final preserved = terminalIndex >= 0
          ? _cancelledSeminarRuntimeControlReaderTurn(existing)
          : existing;
      if (terminalIndex >= 0) {
        merged.insert(terminalIndex, preserved);
      } else {
        merged.add(preserved);
      }
    }
    return merged;
  }

  List<AiSeminarRunCardMessagePart> _protectTerminalSeminarReaderControlParts(
    List<AiSeminarRunCardMessagePart> existingParts,
    List<AiSeminarRunCardMessagePart> nextParts,
  ) {
    if (existingParts.isEmpty || nextParts.isEmpty) return nextParts;
    final terminalPartsByKey = <String, AiSeminarRunCardMessagePart>{};
    final terminalRuntimePartsByRunId = <String, AiSeminarRunCardMessagePart>{};
    for (final existing in existingParts) {
      final key = _seminarReaderControlKey(existing);
      if (key == null || !_isTerminalSeminarReaderControlPart(existing)) {
        continue;
      }
      terminalPartsByKey[key] = existing;
      if (_isSeminarRuntimeControlReaderTurn(existing)) {
        final runId = _seminarMessagePartRunId(existing);
        if (runId != null && runId.isNotEmpty) {
          terminalRuntimePartsByRunId[runId] = existing;
        }
      }
    }
    if (terminalPartsByKey.isEmpty) return nextParts;
    final protectedParts = <AiSeminarRunCardMessagePart>[];
    final emittedTerminalKeys = <String>{};
    for (final part in nextParts) {
      final key = _seminarReaderControlKey(part);
      var protectedPart = part;
      if (key != null) {
        final terminal = terminalPartsByKey[key];
        if (terminal != null && !_isTerminalSeminarReaderControlPart(part)) {
          protectedPart = terminal;
        } else {
          final runId = _seminarMessagePartRunId(part);
          final terminalRuntime =
              runId == null ? null : terminalRuntimePartsByRunId[runId];
          if (terminalRuntime != null &&
              _isSeminarRuntimeControlReaderTurn(part) &&
              _trimSeminarMessageValue(part.status) == 'pending') {
            protectedPart = terminalRuntime;
          }
        }
      }
      final protectedKey = _seminarReaderControlKey(protectedPart);
      if (protectedKey != null &&
          _isTerminalSeminarReaderControlPart(protectedPart) &&
          !emittedTerminalKeys.add(protectedKey)) {
        continue;
      }
      protectedParts.add(protectedPart);
    }
    return protectedParts;
  }

  List<AiSeminarRunCardMessagePart>
      _mergeExistingTerminalSeminarRuntimeControlParts(
    List<AiSeminarRunCardMessagePart> existingParts,
    List<AiSeminarRunCardMessagePart> nextParts,
  ) {
    if (existingParts.isEmpty || nextParts.isEmpty) return nextParts;
    final terminalControls = existingParts
        .where(
          (part) =>
              _isSeminarRuntimeControlReaderTurn(part) &&
              _isTerminalSeminarReaderControlPart(part),
        )
        .toList(growable: false);
    if (terminalControls.isEmpty) return nextParts;

    final completedControlRunIds = terminalControls
        .where((part) => _trimSeminarMessageValue(part.status) == 'completed')
        .map(_seminarMessagePartRunId)
        .whereType<String>()
        .where((runId) => runId.isNotEmpty)
        .toSet();
    final completedContentByRunId =
        <String, List<AiSeminarRunCardMessagePart>>{};
    if (completedControlRunIds.isNotEmpty) {
      for (final existing in existingParts) {
        if (!_isGraphTracedSeminarContentPart(existing)) continue;
        final runId = _seminarMessagePartRunId(existing);
        if (runId == null || !completedControlRunIds.contains(runId)) {
          continue;
        }
        completedContentByRunId
            .putIfAbsent(runId, () => <AiSeminarRunCardMessagePart>[])
            .add(existing);
      }
    }

    final merged = nextParts.where((part) {
      final runId = _seminarMessagePartRunId(part);
      if (runId == null || !completedContentByRunId.containsKey(runId)) {
        return true;
      }
      if (part.type.trim() != 'agent_status') return true;
      return !_isTransientSeminarStatusPart(part) &&
          !_isFailedSeminarStatusPart(part);
    }).toList(growable: true);

    void appendIfMissing(AiSeminarRunCardMessagePart part) {
      if (part.isEmpty) return;
      final readerControlKey = _seminarReaderControlKey(part);
      final partRunId = _seminarMessagePartRunId(part);
      final alreadyMerged = merged.any((existing) {
        if (_seminarMessagePartKey(existing) == _seminarMessagePartKey(part)) {
          return true;
        }
        if (readerControlKey != null &&
            _seminarReaderControlKey(existing) == readerControlKey) {
          return true;
        }
        return partRunId != null &&
            partRunId.isNotEmpty &&
            existing.type.trim() == part.type.trim() &&
            _seminarMessagePartRunId(existing) == partRunId;
      });
      if (!alreadyMerged) merged.add(part);
    }

    for (final control in terminalControls) {
      appendIfMissing(control);
    }
    for (final parts in completedContentByRunId.values) {
      for (final part in parts) {
        appendIfMissing(part);
      }
    }
    return merged;
  }

  List<AiSeminarRunCardMessagePart> _protectUnreopenableSeminarStatusParts(
    List<AiSeminarRunCardMessagePart> existingParts,
    List<AiSeminarRunCardMessagePart> nextParts,
  ) {
    if (existingParts.isEmpty || nextParts.isEmpty) return nextParts;
    final terminalPartsByRunId = <String, AiSeminarRunCardMessagePart>{};
    for (final existing in existingParts) {
      if (!_isUnreopenableSeminarStatusPart(existing)) continue;
      final runId = _seminarStatusPartRunId(existing);
      if (runId == null || runId.isEmpty) continue;
      terminalPartsByRunId[runId] = existing;
    }
    if (terminalPartsByRunId.isEmpty) return nextParts;
    final replacedRunIds = <String>{};
    final protectedParts = <AiSeminarRunCardMessagePart>[];
    for (final part in nextParts) {
      final runId = _seminarStatusPartRunId(part);
      final terminal = runId == null ? null : terminalPartsByRunId[runId];
      if (terminal != null && _isTransientSeminarStatusPart(part)) {
        if (replacedRunIds.add(runId!)) {
          protectedParts.add(terminal);
        }
        continue;
      }
      protectedParts.add(part);
    }
    return protectedParts;
  }

  AiSeminarRunCardSnapshot _protectSeminarTerminalArtifactActions({
    required AiSeminarRunCardSnapshot existing,
    required AiSeminarRunCardSnapshot next,
  }) {
    final parts = next.messageParts
        .map(
          (part) => _protectSeminarTerminalArtifactActionPart(
            existing.messageParts,
            part,
          ),
        )
        .toList(growable: false);
    if (identical(parts, next.messageParts)) return next;
    return AiSeminarRunCardSnapshot(
      evidence: next.evidence,
      toolCalls: next.toolCalls,
      roleSummaries: next.roleSummaries,
      messageParts: parts,
      synthesisSummary: next.synthesisSummary,
      disagreements: next.disagreements,
      disagreementDetails: next.disagreementDetails,
      openQuestions: next.openQuestions,
    );
  }

  AiSeminarRunCardMessagePart _protectSeminarTerminalArtifactActionPart(
    List<AiSeminarRunCardMessagePart> existingParts,
    AiSeminarRunCardMessagePart nextPart,
  ) {
    if (!_isSeminarArtifactActionsPart(nextPart) ||
        !_seminarPartHasAction(nextPart, 'send-to-review')) {
      return nextPart;
    }
    final sentPart = _matchingSentReviewArtifactPart(existingParts, nextPart);
    if (sentPart == null) return nextPart;
    final actionIds = <String>[];
    for (final rawActionId in nextPart.actionIds) {
      final actionId = rawActionId.trim();
      if (actionId.isEmpty) continue;
      final protectedActionId =
          actionId == 'send-to-review' ? 'sent-to-review' : actionId;
      if (!actionIds.contains(protectedActionId)) {
        actionIds.add(protectedActionId);
      }
    }
    return AiSeminarRunCardMessagePart(
      type: nextPart.type,
      id: nextPart.id,
      agentRunId: nextPart.agentRunId,
      parentRunId: nextPart.parentRunId,
      roleId: nextPart.roleId,
      roleIds: nextPart.roleIds,
      actionIds: actionIds,
      allowedToolIds: nextPart.allowedToolIds,
      defaultRoleId: nextPart.defaultRoleId,
      defaultActionId: nextPart.defaultActionId,
      selectedRoleId: nextPart.selectedRoleId,
      selectedActionId: nextPart.selectedActionId,
      draftText: nextPart.draftText,
      toolId: nextPart.toolId,
      status: nextPart.status,
      label: nextPart.label,
      text: _nonEmptyOrFallback(sentPart.text, nextPart.text),
      query: nextPart.query,
      resultCount: nextPart.resultCount,
      completedAt: nextPart.completedAt,
      evidenceRefs: nextPart.evidenceRefs.isNotEmpty
          ? nextPart.evidenceRefs
          : sentPart.evidenceRefs,
    );
  }

  AiSeminarRunCardMessagePart? _matchingSentReviewArtifactPart(
    List<AiSeminarRunCardMessagePart> existingParts,
    AiSeminarRunCardMessagePart nextPart,
  ) {
    AiSeminarRunCardMessagePart? fallback;
    for (final existingPart in existingParts) {
      if (!_isSeminarArtifactActionsPart(existingPart) ||
          !_seminarPartHasAction(existingPart, 'sent-to-review')) {
        continue;
      }
      fallback ??= existingPart;
      if (_sameSeminarMessagePartIdentity(existingPart, nextPart)) {
        return existingPart;
      }
    }
    return fallback;
  }

  bool _sameSeminarMessagePartIdentity(
    AiSeminarRunCardMessagePart a,
    AiSeminarRunCardMessagePart b,
  ) {
    final aId = a.id?.trim();
    final bId = b.id?.trim();
    if (aId != null && aId.isNotEmpty && bId != null && bId.isNotEmpty) {
      return aId == bId;
    }
    final aRunId = a.agentRunId?.trim();
    final bRunId = b.agentRunId?.trim();
    if (aRunId != null &&
        aRunId.isNotEmpty &&
        bRunId != null &&
        bRunId.isNotEmpty) {
      return aRunId == bRunId;
    }
    return false;
  }

  bool _isSeminarArtifactActionsPart(AiSeminarRunCardMessagePart part) {
    return part.type.trim() == 'artifact_actions' && !part.isEmpty;
  }

  bool _seminarPartHasAction(
    AiSeminarRunCardMessagePart part,
    String actionId,
  ) {
    final target = actionId.trim();
    if (target.isEmpty) return false;
    return part.actionIds.any((item) => item.trim() == target);
  }

  String? _nonEmptyOrFallback(String? primary, String? fallback) {
    final trimmed = primary?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    final fallbackTrimmed = fallback?.trim();
    return fallbackTrimmed == null || fallbackTrimmed.isEmpty
        ? null
        : fallbackTrimmed;
  }

  bool _isRecordedSeminarArtifactActionId(String actionId) {
    switch (actionId.trim()) {
      case 'knowledge-card-saved':
      case 'spaced-review-added':
      case 'concept-graph-added':
      case 'artifact-actions-ignored':
      case 'sent-to-review':
        return true;
      default:
        return false;
    }
  }

  bool _isReplayableSeminarArtifactActionId(String actionId) {
    if (_isRecordedSeminarArtifactActionId(actionId)) return true;
    switch (actionId.trim()) {
      case 'undo-knowledge-card':
      case 'undo-spaced-review':
      case 'undo-concept-graph':
      case 'restore-artifact-actions':
        return true;
      default:
        return false;
    }
  }

  bool _isSeminarArtifactExecutionMarkerActionId(String actionId) {
    switch (actionId.trim()) {
      case 'undo-knowledge-card':
      case 'undo-spaced-review':
      case 'undo-concept-graph':
      case 'restore-artifact-actions':
        return true;
      default:
        return false;
    }
  }

  bool _isSeminarRunSetupPart(AiSeminarRunCardMessagePart part) {
    return part.type.trim() == 'seminar_run_setup' && !part.isEmpty;
  }

  bool _isSeminarContradictionScanPart(AiSeminarRunCardMessagePart part) {
    return part.type.trim() == 'contradiction_scan' && !part.isEmpty;
  }

  Future<void> _hydrateSeminarRunCardGraphReplayForLoadedHistory(
    String historyEntryId,
  ) async {
    if (_disposed ||
        _currentSessionId != historyEntryId ||
        _tree.nodes.isEmpty) {
      return;
    }

    var nextTree = _tree;
    var changed = false;
    for (final entry in _tree.nodes.entries) {
      if (_disposed || _currentSessionId != historyEntryId) return;
      final node = nextTree.nodes[entry.key];
      final meta = node?.meta;
      final card = meta?.seminarRunCard;
      if (node == null || meta == null || card == null) {
        continue;
      }
      final sessionId = (card.sessionId ?? '').trim();
      if (sessionId.isEmpty) {
        continue;
      }
      final snapshot = await _snapshotWithSeminarGraphReplayParts(
        seminarSessionId: sessionId,
        snapshot: card.snapshot,
      );
      if (!_seminarSnapshotChanged(card.snapshot, snapshot)) continue;
      final updatedCard = card.copyWith(snapshot: snapshot);
      nextTree = nextTree.copyWithNode(
        entry.key,
        node.copyWith(
          meta: AiSegmentMeta(
            model: meta.model,
            inputTokens: meta.inputTokens,
            outputTokens: meta.outputTokens,
            seminarRunCard: updatedCard,
          ),
        ),
      );
      changed = true;
    }

    if (!changed || _disposed || _currentSessionId != historyEntryId) {
      return;
    }
    _tree = nextTree;
    _rebuildFromTree();
  }

  Future<AiSeminarRunCardSnapshot?> _snapshotWithSeminarGraphReplayParts({
    required String seminarSessionId,
    required AiSeminarRunCardSnapshot? snapshot,
  }) async {
    final sessionId = seminarSessionId.trim();
    if (sessionId.isEmpty) return snapshot;
    List<AiSeminarRunCardMessagePart> replayParts;
    try {
      replayParts = await seminarMessagePartsFromAgentRunGraphStore(
        AgentRunGraphStore(),
        parentRunId: sessionId,
      );
    } catch (_) {
      return snapshot;
    }
    if (replayParts.isEmpty) return snapshot;
    return _appendSeminarMessageParts(
      snapshot,
      replayParts,
    );
  }

  Future<AiSeminarRunCardSnapshot> _snapshotWithSatisfiedSeminarWaitRequests({
    required String seminarSessionId,
    required AiSeminarRunCardSnapshot snapshot,
    bool forceCheck = false,
  }) async {
    final sessionId = seminarSessionId.trim();
    if (sessionId.isEmpty) return snapshot;
    final hasPendingWait = _seminarSnapshotHasPendingWaitRequest(snapshot);
    if (!forceCheck && !hasPendingWait) return snapshot;
    final graphStore = AgentRunGraphStore();
    var acknowledgedAny = false;
    try {
      final events = await graphStore.listChildEvents(sessionId);
      final pendingWaitEvents = events
          .where(
            (event) =>
                event.parentRunId == sessionId &&
                event.type == AgentRunEventType.waitRequest &&
                event.acknowledgedAt == null,
          )
          .toList(growable: false);
      for (final event in pendingWaitEvents) {
        final childRunId = event.runId.trim();
        if (childRunId.isEmpty) continue;
        final terminalToolEvent = _terminalSeminarToolCallForWaitRequest(
          event,
          events,
          sessionId: sessionId,
        );
        var acknowledgedAt = terminalToolEvent?.createdAt;
        if (terminalToolEvent == null) {
          final run = await graphStore.getRun(childRunId);
          if (run?.parentRunId != sessionId ||
              !_isSettledSeminarAgentRunStatusForWait(run!.status)) {
            continue;
          }
        }
        await graphStore.acknowledgeControlEvent(
          parentRunId: sessionId,
          childRunId: childRunId,
          eventId: event.eventId,
          now: acknowledgedAt,
        );
        acknowledgedAny = true;
      }
      if (!acknowledgedAny) return snapshot;
      final replayParts = await seminarMessagePartsFromAgentRunGraphStore(
        graphStore,
        parentRunId: sessionId,
      );
      if (replayParts.isEmpty) return snapshot;
      return _appendSeminarMessageParts(snapshot, replayParts);
    } catch (_) {
      return snapshot;
    }
  }

  bool _seminarSnapshotHasPendingWaitRequest(
    AiSeminarRunCardSnapshot snapshot,
  ) {
    return snapshot.messageParts.any(
      (part) =>
          (_isSeminarRoleWaitReaderTurn(part) ||
              _isSeminarToolCallWaitReaderTurn(part)) &&
          _trimSeminarMessageValue(part.status) == 'pending' &&
          _seminarMessagePartRunId(part) != null,
    );
  }

  AiSeminarRunCardSnapshot _appendSeminarMessageParts(
    AiSeminarRunCardSnapshot? snapshot,
    List<AiSeminarRunCardMessagePart> parts,
  ) {
    var mergedParts = snapshot?.messageParts
            .where((part) => !part.isEmpty)
            .toList(growable: false) ??
        const <AiSeminarRunCardMessagePart>[];
    for (final incomingPart in parts) {
      var part = incomingPart;
      if (part.isEmpty) continue;
      final incomingStatusRunId = _seminarStatusPartRunId(part);
      if (_isTransientSeminarStatusPart(part) &&
          incomingStatusRunId != null &&
          mergedParts.any(
            (existing) =>
                _isUnreopenableSeminarStatusPart(existing) &&
                _seminarStatusPartRunId(existing) == incomingStatusRunId,
          )) {
        continue;
      }
      final supersededStatusRunId = _seminarSupersededStatusRunId(part);
      final onlySupersedesTransientStatuses =
          _seminarOnlySupersedesTransientStatuses(part);
      var candidateParts = supersededStatusRunId == null
          ? mergedParts
          : mergedParts.where(
              (existing) {
                if (_seminarPartSupersedesRolePartial(part) &&
                    _seminarRolePartialPartRunId(existing) ==
                        supersededStatusRunId) {
                  return false;
                }
                if (_seminarStatusPartRunId(existing) !=
                    supersededStatusRunId) {
                  return true;
                }
                return _keepSeminarStatusPartAfterIncoming(
                  existing,
                  part,
                  onlySupersedesTransientStatuses:
                      onlySupersedesTransientStatuses,
                );
              },
            ).toList(growable: false);
      if (_isGraphTracedSeminarContentPart(part)) {
        candidateParts = candidateParts
            .where(
              (existing) =>
                  !_isLegacyDuplicateSeminarContentPart(existing, part),
            )
            .toList(growable: false);
      }
      if (_isTerminalSeminarArtifactActionsPart(part)) {
        final matchingArtifactParts = candidateParts
            .where(
              (existing) => _isSameSeminarArtifactActionsRun(existing, part),
            )
            .toList(growable: false);
        if (matchingArtifactParts.isNotEmpty) {
          candidateParts = candidateParts
              .where(
                (existing) => !_isSameSeminarArtifactActionsRun(existing, part),
              )
              .toList(growable: false);
          part = _mergeSeminarArtifactActionsParts(
            matchingArtifactParts,
            part,
          );
        }
      }
      if (_isCompletedSeminarRuntimeControlReaderTurn(part)) {
        candidateParts = candidateParts
            .where(
              (existing) => !_isStalePendingSeminarRuntimeControlReaderTurn(
                existing,
                part,
              ),
            )
            .toList(growable: false);
      }
      if (_isStreamedSeminarThinkingPart(part)) {
        final incomingRunId = _seminarMessagePartRunId(part);
        candidateParts = candidateParts
            .where(
              (existing) =>
                  !_isGenericSeminarRoleStartThinkingPart(existing) ||
                  _seminarMessagePartRunId(existing) != incomingRunId,
            )
            .toList(growable: false);
      } else if (_isGenericSeminarRoleStartThinkingPart(part)) {
        final incomingRunId = _seminarMessagePartRunId(part);
        final hasStreamedThinkingForRun = incomingRunId != null &&
            candidateParts.any(
              (existing) =>
                  _isStreamedSeminarThinkingPart(existing) &&
                  _seminarMessagePartRunId(existing) == incomingRunId,
            );
        if (hasStreamedThinkingForRun) {
          mergedParts = candidateParts;
          continue;
        }
      }
      final waitSettledRunId = _isGraphTracedSeminarRoleWaitSettledPart(part)
          ? _seminarMessagePartRunId(part)
          : null;
      final terminalRunId = _isGraphTracedSeminarRoleTerminalPart(part)
          ? _seminarMessagePartRunId(part)
          : null;
      final terminalToolCallPart =
          _isTerminalSeminarToolCallPart(part) ? part : null;
      if (waitSettledRunId != null ||
          terminalRunId != null ||
          terminalToolCallPart != null) {
        candidateParts = candidateParts.map(
          (existing) {
            if (waitSettledRunId != null &&
                _isPendingSeminarWaitReaderTurnForRun(
                  existing,
                  waitSettledRunId,
                )) {
              return _completedSeminarWaitReaderTurn(existing);
            }
            if (terminalRunId != null &&
                _isPendingSeminarRuntimeControlReaderTurnForRun(
                  existing,
                  terminalRunId,
                )) {
              return _cancelledSeminarRuntimeControlReaderTurn(existing);
            }
            if (terminalToolCallPart != null &&
                _isPendingSeminarToolCallWaitReaderTurn(existing) &&
                _seminarToolWaitMatchesToolCall(
                  existing,
                  terminalToolCallPart,
                )) {
              return _completedSeminarWaitReaderTurn(
                existing,
                completedAt: terminalToolCallPart.completedAt,
              );
            }
            return existing;
          },
        ).toList(growable: false);
      }
      final key = _seminarMessagePartKey(part);
      final existingIndex = candidateParts.indexWhere(
        (existing) =>
            _seminarMessagePartKey(existing) == key ||
            _isSameSeminarToolCallPart(existing, part),
      );
      if (existingIndex >= 0) {
        final existingPart = candidateParts[existingIndex];
        if (_shouldReplaceSeminarMessagePart(existingPart, part)) {
          final mergedPart = _mergeSeminarMessagePartForReplacement(
            existingPart,
            part,
          );
          mergedParts = [
            ...candidateParts.take(existingIndex),
            mergedPart,
            ...candidateParts.skip(existingIndex + 1),
          ];
        } else {
          mergedParts = candidateParts;
        }
      } else {
        mergedParts = [...candidateParts, part];
      }
    }
    final normalizedParts = _ensureSeminarEvidencePartsFromToolCalls(
      _suppressPendingSeminarRuntimeControlActions(mergedParts),
    );
    return AiSeminarRunCardSnapshot(
      evidence:
          snapshot?.evidence ?? const <AiSeminarRunCardEvidenceSnapshot>[],
      toolCalls:
          snapshot?.toolCalls ?? const <AiSeminarRunCardToolCallSnapshot>[],
      roleSummaries:
          snapshot?.roleSummaries ?? const <AiSeminarRunCardRoleSummary>[],
      messageParts: normalizedParts,
      synthesisSummary: snapshot?.synthesisSummary,
      disagreements: snapshot?.disagreements ?? const <String>[],
      disagreementDetails: snapshot?.disagreementDetails ??
          const <AiSeminarRunCardDisagreementDetail>[],
      openQuestions: snapshot?.openQuestions ?? const <String>[],
    );
  }

  List<AiSeminarRunCardMessagePart>
      _ensureSeminarToolCallPartsFromLegacySnapshot(
    List<AiSeminarRunCardMessagePart> parts,
    Iterable<AiSeminarRunCardToolCallSnapshot> toolCalls,
  ) {
    var normalizedParts = parts;
    for (final toolCall in toolCalls) {
      if (toolCall.isEmpty) continue;
      final part = AiSeminarRunCardMessagePart(
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
        startedAt: toolCall.startedAt,
        completedAt: toolCall.completedAt,
        roleIds: toolCall.roleIds,
        evidenceRefs: toolCall.evidenceRefs,
      );
      if (part.isEmpty) continue;
      final existingIndex = normalizedParts.indexWhere(
        (existing) =>
            _seminarMessagePartKey(existing) == _seminarMessagePartKey(part) ||
            _isSameSeminarToolCallPart(existing, part),
      );
      if (existingIndex >= 0) {
        final existingPart = normalizedParts[existingIndex];
        final mergedPart = _mergeSeminarMessagePartForReplacement(
          existingPart,
          part,
        );
        normalizedParts = [
          ...normalizedParts.take(existingIndex),
          mergedPart,
          ...normalizedParts.skip(existingIndex + 1),
        ];
      } else {
        normalizedParts = [...normalizedParts, part];
      }
    }
    return normalizedParts;
  }

  List<AiSeminarRunCardMessagePart>
      _ensureSeminarRoleTurnPartsFromLegacySnapshot(
    List<AiSeminarRunCardMessagePart> parts, {
    required String? parentRunId,
    required Iterable<AiSeminarRunCardRoleSummary> roleSummaries,
  }) {
    final runId = _trimSeminarMessageValue(parentRunId);
    if (runId.isEmpty) return parts;
    var normalizedParts = parts;
    final roleIndexById = <String, int>{};
    for (final role in roleSummaries) {
      if (role.isEmpty) continue;
      final roleId = role.roleId.trim();
      final roleKey = roleId.isEmpty ? 'role' : roleId;
      final roleIndex = roleIndexById.update(
        roleKey,
        (value) => value + 1,
        ifAbsent: () => 0,
      );
      final idSuffix = roleIndex == 0 ? roleKey : '$roleKey-$roleIndex';
      final part = AiSeminarRunCardMessagePart(
        type: 'role_turn',
        id: '$runId:role-turn:$idSuffix:legacy',
        parentRunId: runId,
        roleId: roleId.isEmpty ? null : roleId,
        label: role.label,
        text: role.summary,
        evidenceRefs: role.evidenceRefs,
      );
      if (part.isEmpty) continue;
      final existingIndex = normalizedParts.indexWhere(
        (existing) =>
            _seminarMessagePartKey(existing) == _seminarMessagePartKey(part) ||
            _isSameLegacySeminarRoleTurnPart(existing, part),
      );
      if (existingIndex >= 0) {
        final existingPart = normalizedParts[existingIndex];
        normalizedParts = [
          ...normalizedParts.take(existingIndex),
          _mergeLegacySeminarRoleTurnPart(existingPart, part),
          ...normalizedParts.skip(existingIndex + 1),
        ];
      } else {
        normalizedParts = [...normalizedParts, part];
      }
    }
    return normalizedParts;
  }

  bool _isSameLegacySeminarRoleTurnPart(
    AiSeminarRunCardMessagePart existing,
    AiSeminarRunCardMessagePart incoming,
  ) {
    if (existing.type.trim() != 'role_turn' ||
        incoming.type.trim() != 'role_turn') {
      return false;
    }
    return _trimSeminarMessageValue(existing.roleId) ==
            _trimSeminarMessageValue(incoming.roleId) &&
        _trimSeminarMessageValue(existing.text) ==
            _trimSeminarMessageValue(incoming.text);
  }

  AiSeminarRunCardMessagePart _mergeLegacySeminarRoleTurnPart(
    AiSeminarRunCardMessagePart existing,
    AiSeminarRunCardMessagePart incoming,
  ) {
    return AiSeminarRunCardMessagePart(
      type: existing.type,
      id: existing.id ?? incoming.id,
      agentRunId: existing.agentRunId,
      parentRunId: existing.parentRunId ?? incoming.parentRunId,
      roleId: existing.roleId ?? incoming.roleId,
      roleIds:
          existing.roleIds.isNotEmpty ? existing.roleIds : incoming.roleIds,
      actionIds: existing.actionIds.isNotEmpty
          ? existing.actionIds
          : incoming.actionIds,
      allowedToolIds: existing.allowedToolIds.isNotEmpty
          ? existing.allowedToolIds
          : incoming.allowedToolIds,
      defaultRoleId: existing.defaultRoleId ?? incoming.defaultRoleId,
      defaultActionId: existing.defaultActionId ?? incoming.defaultActionId,
      selectedRoleId: existing.selectedRoleId ?? incoming.selectedRoleId,
      selectedActionId: existing.selectedActionId ?? incoming.selectedActionId,
      draftText: existing.draftText ?? incoming.draftText,
      toolId: existing.toolId ?? incoming.toolId,
      status: existing.status ?? incoming.status,
      label: existing.label ?? incoming.label,
      text: existing.text ?? incoming.text,
      query: existing.query ?? incoming.query,
      resultCount: existing.resultCount > 0
          ? existing.resultCount
          : incoming.resultCount,
      startedAt: existing.startedAt ?? incoming.startedAt,
      completedAt: existing.completedAt ?? incoming.completedAt,
      evidenceRefs: _mergeSeminarEvidenceRefs([
        ...existing.evidenceRefs,
        ...incoming.evidenceRefs,
      ]),
    );
  }

  List<AiSeminarRunCardMessagePart>
      _ensureSeminarSynthesisPartFromLegacySnapshot(
    List<AiSeminarRunCardMessagePart> parts, {
    required String? parentRunId,
    required String? synthesisSummary,
    required Iterable<AiSeminarRunCardEvidenceSnapshot> evidenceRefs,
  }) {
    final runId = _trimSeminarMessageValue(parentRunId);
    final summary = _trimSeminarMessageValue(synthesisSummary);
    if (runId.isEmpty || summary.isEmpty) return parts;
    final part = AiSeminarRunCardMessagePart(
      type: 'synthesis',
      id: '$runId:synthesis:legacy',
      parentRunId: runId,
      text: summary,
      evidenceRefs: _mergeSeminarEvidenceRefs(evidenceRefs),
    );
    if (part.isEmpty) return parts;
    final existingIndex = parts.indexWhere(
      (existing) =>
          _seminarMessagePartKey(existing) == _seminarMessagePartKey(part) ||
          _isSameLegacySeminarSynthesisPart(existing, part),
    );
    if (existingIndex < 0) return [...parts, part];
    final existingPart = parts[existingIndex];
    return [
      ...parts.take(existingIndex),
      _mergeLegacySeminarSynthesisPart(existingPart, part),
      ...parts.skip(existingIndex + 1),
    ];
  }

  bool _isSameLegacySeminarSynthesisPart(
    AiSeminarRunCardMessagePart existing,
    AiSeminarRunCardMessagePart incoming,
  ) {
    if (existing.type.trim() != 'synthesis' ||
        incoming.type.trim() != 'synthesis') {
      return false;
    }
    final incomingParentRunId = _trimSeminarMessageValue(incoming.parentRunId);
    if (incomingParentRunId.isEmpty) return true;
    final existingParentRunId = _trimSeminarMessageValue(existing.parentRunId);
    if (existingParentRunId.isNotEmpty) {
      return existingParentRunId == incomingParentRunId;
    }
    final existingRunId = _seminarMessagePartRunId(existing);
    return existingRunId == null || existingRunId == incomingParentRunId;
  }

  AiSeminarRunCardMessagePart _mergeLegacySeminarSynthesisPart(
    AiSeminarRunCardMessagePart existing,
    AiSeminarRunCardMessagePart incoming,
  ) {
    return AiSeminarRunCardMessagePart(
      type: existing.type,
      id: existing.id ?? incoming.id,
      agentRunId: existing.agentRunId,
      parentRunId: existing.parentRunId ?? incoming.parentRunId,
      roleId: existing.roleId ?? incoming.roleId,
      roleIds:
          existing.roleIds.isNotEmpty ? existing.roleIds : incoming.roleIds,
      actionIds: existing.actionIds.isNotEmpty
          ? existing.actionIds
          : incoming.actionIds,
      allowedToolIds: existing.allowedToolIds.isNotEmpty
          ? existing.allowedToolIds
          : incoming.allowedToolIds,
      defaultRoleId: existing.defaultRoleId ?? incoming.defaultRoleId,
      defaultActionId: existing.defaultActionId ?? incoming.defaultActionId,
      selectedRoleId: existing.selectedRoleId ?? incoming.selectedRoleId,
      selectedActionId: existing.selectedActionId ?? incoming.selectedActionId,
      draftText: existing.draftText ?? incoming.draftText,
      toolId: existing.toolId ?? incoming.toolId,
      status: existing.status ?? incoming.status,
      label: existing.label ?? incoming.label,
      text: existing.text ?? incoming.text,
      query: existing.query ?? incoming.query,
      resultCount: existing.resultCount > 0
          ? existing.resultCount
          : incoming.resultCount,
      startedAt: existing.startedAt ?? incoming.startedAt,
      completedAt: existing.completedAt ?? incoming.completedAt,
      evidenceRefs: _mergeSeminarEvidenceRefs([
        ...existing.evidenceRefs,
        ...incoming.evidenceRefs,
      ]),
    );
  }

  List<AiSeminarRunCardMessagePart>
      _ensureSeminarDisagreementPartsFromLegacySnapshot(
    List<AiSeminarRunCardMessagePart> parts, {
    required String? parentRunId,
    required Iterable<String> disagreements,
    required Iterable<AiSeminarRunCardDisagreementDetail> disagreementDetails,
  }) {
    final fallbackRunId = _trimSeminarMessageValue(parentRunId);
    var normalizedParts = parts;
    var detailIndex = 0;
    for (final detail in disagreementDetails) {
      if (detail.isEmpty) continue;
      final text = _trimSeminarMessageValue(detail.text);
      if (text.isEmpty) continue;
      final detailParentRunId = _trimSeminarMessageValue(detail.parentRunId);
      final runId =
          detailParentRunId.isNotEmpty ? detailParentRunId : fallbackRunId;
      if (runId.isEmpty) continue;
      final id = '$runId:disagreement:$detailIndex:legacy';
      detailIndex += 1;
      final part = AiSeminarRunCardMessagePart(
        type: 'disagreement',
        id: id,
        agentRunId: _trimSeminarMessageValue(detail.agentRunId).isEmpty
            ? null
            : detail.agentRunId?.trim(),
        parentRunId: runId,
        text: text,
        roleIds: _mergeSeminarStringValues(detail.roleIds),
        evidenceRefs: _mergeSeminarEvidenceRefs(detail.evidenceRefs),
      );
      if (part.isEmpty) continue;
      final existingIndex = normalizedParts.indexWhere(
        (existing) =>
            _seminarMessagePartKey(existing) == _seminarMessagePartKey(part) ||
            _isSameLegacySeminarDisagreementPart(existing, part),
      );
      if (existingIndex >= 0) {
        final existingPart = normalizedParts[existingIndex];
        normalizedParts = [
          ...normalizedParts.take(existingIndex),
          _mergeLegacySeminarDisagreementPart(existingPart, part),
          ...normalizedParts.skip(existingIndex + 1),
        ];
      } else {
        normalizedParts = [...normalizedParts, part];
      }
    }
    var disagreementIndex = 0;
    for (final rawDisagreement in disagreements) {
      final text = _trimSeminarMessageValue(rawDisagreement);
      if (fallbackRunId.isEmpty || text.isEmpty) continue;
      final part = AiSeminarRunCardMessagePart(
        type: 'disagreement',
        id: '$fallbackRunId:disagreement:$disagreementIndex:legacy-bare',
        parentRunId: fallbackRunId,
        label: 'legacy-untraced',
        text: text,
      );
      disagreementIndex += 1;
      if (part.isEmpty) continue;
      final existingIndex = normalizedParts.indexWhere(
        (existing) =>
            _seminarMessagePartKey(existing) == _seminarMessagePartKey(part) ||
            _isSameLegacySeminarDisagreementPart(existing, part),
      );
      if (existingIndex >= 0) continue;
      normalizedParts = [...normalizedParts, part];
    }
    return normalizedParts;
  }

  bool _isSameLegacySeminarDisagreementPart(
    AiSeminarRunCardMessagePart existing,
    AiSeminarRunCardMessagePart incoming,
  ) {
    if (existing.type.trim() != 'disagreement' ||
        incoming.type.trim() != 'disagreement') {
      return false;
    }
    final incomingParentRunId = _trimSeminarMessageValue(incoming.parentRunId);
    if (incomingParentRunId.isEmpty) return true;
    final existingParentRunId = _trimSeminarMessageValue(existing.parentRunId);
    if (existingParentRunId.isNotEmpty) {
      return existingParentRunId == incomingParentRunId;
    }
    final existingRunId = _seminarMessagePartRunId(existing);
    return existingRunId == null || existingRunId == incomingParentRunId;
  }

  AiSeminarRunCardMessagePart _mergeLegacySeminarDisagreementPart(
    AiSeminarRunCardMessagePart existing,
    AiSeminarRunCardMessagePart incoming,
  ) {
    return AiSeminarRunCardMessagePart(
      type: existing.type,
      id: existing.id ?? incoming.id,
      agentRunId: existing.agentRunId ?? incoming.agentRunId,
      parentRunId: existing.parentRunId ?? incoming.parentRunId,
      roleId: existing.roleId ?? incoming.roleId,
      roleIds: _mergeSeminarStringValues([
        ...existing.roleIds,
        ...incoming.roleIds,
      ]),
      actionIds: existing.actionIds.isNotEmpty
          ? existing.actionIds
          : incoming.actionIds,
      allowedToolIds: existing.allowedToolIds.isNotEmpty
          ? existing.allowedToolIds
          : incoming.allowedToolIds,
      defaultRoleId: existing.defaultRoleId ?? incoming.defaultRoleId,
      defaultActionId: existing.defaultActionId ?? incoming.defaultActionId,
      selectedRoleId: existing.selectedRoleId ?? incoming.selectedRoleId,
      selectedActionId: existing.selectedActionId ?? incoming.selectedActionId,
      draftText: existing.draftText ?? incoming.draftText,
      toolId: existing.toolId ?? incoming.toolId,
      status: existing.status ?? incoming.status,
      label: existing.label ?? incoming.label,
      text: existing.text ?? incoming.text,
      query: existing.query ?? incoming.query,
      resultCount: existing.resultCount > 0
          ? existing.resultCount
          : incoming.resultCount,
      startedAt: existing.startedAt ?? incoming.startedAt,
      completedAt: existing.completedAt ?? incoming.completedAt,
      evidenceRefs: _mergeSeminarEvidenceRefs([
        ...existing.evidenceRefs,
        ...incoming.evidenceRefs,
      ]),
    );
  }

  List<AiSeminarRunCardMessagePart>
      _ensureSeminarOpenQuestionPartsFromLegacySnapshot(
    List<AiSeminarRunCardMessagePart> parts, {
    required String? parentRunId,
    required Iterable<String> roleIds,
    required Iterable<String> openQuestions,
  }) {
    final runId = _trimSeminarMessageValue(parentRunId);
    if (runId.isEmpty) return parts;
    var normalizedParts = parts;
    if (_hasHandledLegacySeminarOpenQuestionReaderTurn(
      normalizedParts,
      parentRunId: runId,
    )) {
      return _withoutHandledLegacySeminarOpenQuestionPromptParts(
        normalizedParts,
        parentRunId: runId,
      );
    }
    String? firstQuestion;
    var questionIndex = 0;
    for (final rawQuestion in openQuestions) {
      final question = _trimSeminarMessageValue(rawQuestion);
      if (question.isEmpty) continue;
      firstQuestion ??= question;
      final part = AiSeminarRunCardMessagePart(
        type: 'director_state',
        id: '$runId:open-question:$questionIndex:legacy',
        parentRunId: runId,
        roleId: 'director',
        label: 'ask-user',
        text: question,
      );
      questionIndex += 1;
      if (part.isEmpty) continue;
      final existingIndex = normalizedParts.indexWhere(
        (existing) =>
            _seminarMessagePartKey(existing) == _seminarMessagePartKey(part) ||
            _isSameLegacySeminarOpenQuestionPart(existing, part),
      );
      if (existingIndex >= 0) {
        final existingPart = normalizedParts[existingIndex];
        normalizedParts = [
          ...normalizedParts.take(existingIndex),
          _mergeLegacySeminarOpenQuestionPart(existingPart, part),
          ...normalizedParts.skip(existingIndex + 1),
        ];
      } else {
        normalizedParts = [...normalizedParts, part];
      }
    }
    if (firstQuestion != null) {
      final composerRoleIds = _seminarLegacyReaderComposerRoleIds(roleIds);
      final defaultRoleId =
          composerRoleIds.isEmpty ? null : composerRoleIds.first;
      final part = AiSeminarRunCardMessagePart(
        type: 'reader_composer',
        id: 'composer-$runId',
        parentRunId: runId,
        label: 'ask-user',
        text: firstQuestion,
        roleIds: composerRoleIds,
        actionIds: const ['ask-role', 'refresh-evidence', 'synthesize'],
        defaultRoleId: defaultRoleId,
        defaultActionId: 'ask-role',
        selectedRoleId: defaultRoleId,
        selectedActionId: 'ask-role',
      );
      if (!part.isEmpty) {
        final existingIndex = normalizedParts.indexWhere(
          (existing) =>
              _seminarMessagePartKey(existing) ==
                  _seminarMessagePartKey(part) ||
              _isSameLegacySeminarReaderComposerPart(existing, part),
        );
        if (existingIndex >= 0) {
          final existingPart = normalizedParts[existingIndex];
          normalizedParts = [
            ...normalizedParts.take(existingIndex),
            _mergeLegacySeminarReaderComposerPart(existingPart, part),
            ...normalizedParts.skip(existingIndex + 1),
          ];
        } else {
          normalizedParts = [...normalizedParts, part];
        }
      }
    }
    return normalizedParts;
  }

  bool _hasHandledLegacySeminarOpenQuestionReaderTurn(
    Iterable<AiSeminarRunCardMessagePart> parts, {
    required String parentRunId,
  }) {
    final runId = _trimSeminarMessageValue(parentRunId);
    if (runId.isEmpty) return false;
    return parts.any((part) {
      if (part.type.trim() != 'reader_turn') return false;
      if (!_seminarMessagePartBelongsToParentRun(part, runId)) return false;
      switch (_trimSeminarMessageValue(part.label)) {
        case 'ask-role':
        case 'refresh-evidence':
        case 'synthesize':
          final status = _trimSeminarMessageValue(part.status);
          return status != 'pending' && status != 'cancelled';
        default:
          return false;
      }
    });
  }

  List<AiSeminarRunCardMessagePart>
      _withoutHandledLegacySeminarOpenQuestionPromptParts(
    List<AiSeminarRunCardMessagePart> parts, {
    required String parentRunId,
  }) {
    final runId = _trimSeminarMessageValue(parentRunId);
    if (runId.isEmpty) return parts;
    return parts.where((part) {
      if (!_seminarMessagePartBelongsToParentRun(part, runId)) return true;
      final label = _trimSeminarMessageValue(part.label);
      if (label != 'ask-user') return true;
      final type = part.type.trim();
      return type != 'reader_composer' && type != 'director_state';
    }).toList(growable: false);
  }

  bool _seminarMessagePartBelongsToParentRun(
    AiSeminarRunCardMessagePart part,
    String parentRunId,
  ) {
    final runId = _trimSeminarMessageValue(parentRunId);
    if (runId.isEmpty) return false;
    final partParentRunId = _trimSeminarMessageValue(part.parentRunId);
    if (partParentRunId.isNotEmpty) return partParentRunId == runId;
    final partRunId = _seminarMessagePartRunId(part);
    return partRunId == runId;
  }

  List<String> _seminarLegacyReaderComposerRoleIds(Iterable<String> roleIds) {
    final normalized = _mergeSeminarStringValues(roleIds);
    final nonSynthesizer = normalized
        .where((roleId) => roleId.trim() != 'synthesizer')
        .toList(growable: false);
    return nonSynthesizer.isEmpty ? normalized : nonSynthesizer;
  }

  bool _isSameLegacySeminarOpenQuestionPart(
    AiSeminarRunCardMessagePart existing,
    AiSeminarRunCardMessagePart incoming,
  ) {
    if (existing.type.trim() != 'director_state' ||
        incoming.type.trim() != 'director_state') {
      return false;
    }
    if (_trimSeminarMessageValue(existing.label) != 'ask-user' ||
        _trimSeminarMessageValue(incoming.label) != 'ask-user') {
      return false;
    }
    if (_trimSeminarMessageValue(existing.text) !=
        _trimSeminarMessageValue(incoming.text)) {
      return false;
    }
    final incomingParentRunId = _trimSeminarMessageValue(incoming.parentRunId);
    if (incomingParentRunId.isEmpty) return true;
    final existingParentRunId = _trimSeminarMessageValue(existing.parentRunId);
    if (existingParentRunId.isNotEmpty) {
      return existingParentRunId == incomingParentRunId;
    }
    final existingRunId = _seminarMessagePartRunId(existing);
    return existingRunId == null || existingRunId == incomingParentRunId;
  }

  AiSeminarRunCardMessagePart _mergeLegacySeminarOpenQuestionPart(
    AiSeminarRunCardMessagePart existing,
    AiSeminarRunCardMessagePart incoming,
  ) {
    return AiSeminarRunCardMessagePart(
      type: existing.type,
      id: existing.id ?? incoming.id,
      agentRunId: existing.agentRunId ?? incoming.agentRunId,
      parentRunId: existing.parentRunId ?? incoming.parentRunId,
      roleId: existing.roleId ?? incoming.roleId,
      roleIds:
          existing.roleIds.isNotEmpty ? existing.roleIds : incoming.roleIds,
      actionIds: existing.actionIds.isNotEmpty
          ? existing.actionIds
          : incoming.actionIds,
      allowedToolIds: existing.allowedToolIds.isNotEmpty
          ? existing.allowedToolIds
          : incoming.allowedToolIds,
      defaultRoleId: existing.defaultRoleId ?? incoming.defaultRoleId,
      defaultActionId: existing.defaultActionId ?? incoming.defaultActionId,
      selectedRoleId: existing.selectedRoleId ?? incoming.selectedRoleId,
      selectedActionId: existing.selectedActionId ?? incoming.selectedActionId,
      draftText: existing.draftText ?? incoming.draftText,
      toolId: existing.toolId ?? incoming.toolId,
      status: existing.status ?? incoming.status,
      label: existing.label ?? incoming.label,
      text: existing.text ?? incoming.text,
      query: existing.query ?? incoming.query,
      resultCount: existing.resultCount > 0
          ? existing.resultCount
          : incoming.resultCount,
      startedAt: existing.startedAt ?? incoming.startedAt,
      completedAt: existing.completedAt ?? incoming.completedAt,
      evidenceRefs: existing.evidenceRefs.isNotEmpty
          ? existing.evidenceRefs
          : incoming.evidenceRefs,
    );
  }

  bool _isSameLegacySeminarReaderComposerPart(
    AiSeminarRunCardMessagePart existing,
    AiSeminarRunCardMessagePart incoming,
  ) {
    if (existing.type.trim() != 'reader_composer' ||
        incoming.type.trim() != 'reader_composer') {
      return false;
    }
    if (_trimSeminarMessageValue(existing.label) != 'ask-user' ||
        _trimSeminarMessageValue(incoming.label) != 'ask-user') {
      return false;
    }
    final incomingParentRunId = _trimSeminarMessageValue(incoming.parentRunId);
    if (incomingParentRunId.isEmpty) return true;
    final existingParentRunId = _trimSeminarMessageValue(existing.parentRunId);
    if (existingParentRunId.isNotEmpty) {
      return existingParentRunId == incomingParentRunId;
    }
    final existingRunId = _seminarMessagePartRunId(existing);
    return existingRunId == null || existingRunId == incomingParentRunId;
  }

  AiSeminarRunCardMessagePart _mergeLegacySeminarReaderComposerPart(
    AiSeminarRunCardMessagePart existing,
    AiSeminarRunCardMessagePart incoming,
  ) {
    return AiSeminarRunCardMessagePart(
      type: existing.type,
      id: existing.id ?? incoming.id,
      agentRunId: existing.agentRunId ?? incoming.agentRunId,
      parentRunId: existing.parentRunId ?? incoming.parentRunId,
      roleId: existing.roleId ?? incoming.roleId,
      roleIds:
          existing.roleIds.isNotEmpty ? existing.roleIds : incoming.roleIds,
      actionIds: existing.actionIds.isNotEmpty
          ? existing.actionIds
          : incoming.actionIds,
      allowedToolIds: existing.allowedToolIds.isNotEmpty
          ? existing.allowedToolIds
          : incoming.allowedToolIds,
      defaultRoleId: existing.defaultRoleId ?? incoming.defaultRoleId,
      defaultActionId: existing.defaultActionId ?? incoming.defaultActionId,
      selectedRoleId: existing.selectedRoleId ?? incoming.selectedRoleId,
      selectedActionId: existing.selectedActionId ?? incoming.selectedActionId,
      draftText: existing.draftText ?? incoming.draftText,
      toolId: existing.toolId ?? incoming.toolId,
      status: existing.status ?? incoming.status,
      label: existing.label ?? incoming.label,
      text: existing.text ?? incoming.text,
      query: existing.query ?? incoming.query,
      resultCount: existing.resultCount > 0
          ? existing.resultCount
          : incoming.resultCount,
      startedAt: existing.startedAt ?? incoming.startedAt,
      completedAt: existing.completedAt ?? incoming.completedAt,
      evidenceRefs: existing.evidenceRefs.isNotEmpty
          ? existing.evidenceRefs
          : incoming.evidenceRefs,
    );
  }

  List<AiSeminarRunCardMessagePart> _ensureSeminarEvidencePartsFromToolCalls(
    List<AiSeminarRunCardMessagePart> parts,
  ) {
    final evidenceByParentRunId =
        <String, Map<String, List<AiSeminarRunCardEvidenceSnapshot>>>{};
    final seenByParentRunId = <String, Map<String, Set<String>>>{};
    for (final part in parts) {
      if (part.type.trim() != 'tool_call') continue;
      final parentRunId = _trimSeminarMessageValue(part.parentRunId).isNotEmpty
          ? part.parentRunId!.trim()
          : _trimSeminarMessageValue(part.agentRunId);
      if (parentRunId.isEmpty) continue;
      final toolId = _trimSeminarMessageValue(part.toolId);
      for (final evidence in part.evidenceRefs) {
        if (evidence.isEmpty) continue;
        final key = _seminarEvidenceSnapshotKey(evidence);
        final seen = seenByParentRunId
            .putIfAbsent(parentRunId, () => <String, Set<String>>{})
            .putIfAbsent(toolId, () => <String>{});
        if (!seen.add(key)) continue;
        evidenceByParentRunId
            .putIfAbsent(
              parentRunId,
              () => <String, List<AiSeminarRunCardEvidenceSnapshot>>{},
            )
            .putIfAbsent(
              toolId,
              () => <AiSeminarRunCardEvidenceSnapshot>[],
            )
            .add(evidence);
      }
    }
    if (evidenceByParentRunId.isEmpty) return parts;

    var normalizedParts = parts;
    for (final parentEntry in evidenceByParentRunId.entries) {
      final groups = parentEntry.value.entries
          .where((entry) => entry.value.isNotEmpty)
          .toList(growable: false);
      final splitByTool = groups.length > 1;
      for (final group in groups) {
        final suffix = splitByTool
            ? 'tool-call-${_seminarToolEvidenceIdSuffix(group.key)}'
            : 'tool-call';
        normalizedParts = _ensureSeminarEvidencePartForParentRun(
          normalizedParts,
          parentRunId: parentEntry.key,
          toolId: group.key,
          evidenceRefs: group.value,
          idSuffix: suffix,
        );
      }
    }
    return normalizedParts;
  }

  String _seminarToolEvidenceIdSuffix(String toolId) {
    final normalized = toolId.trim();
    if (normalized.isEmpty) return 'unknown';
    return normalized.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '-');
  }

  List<AiSeminarRunCardMessagePart>
      _ensureSeminarEvidencePartFromLegacySnapshot(
    List<AiSeminarRunCardMessagePart> parts, {
    required String? parentRunId,
    required Iterable<AiSeminarRunCardEvidenceSnapshot> evidenceRefs,
  }) {
    return _ensureSeminarEvidencePartForParentRun(
      parts,
      parentRunId: parentRunId,
      toolId: null,
      evidenceRefs: evidenceRefs,
      idSuffix: 'legacy',
    );
  }

  List<AiSeminarRunCardMessagePart> _ensureSeminarEvidencePartForParentRun(
    List<AiSeminarRunCardMessagePart> parts, {
    required String? parentRunId,
    required String? toolId,
    required Iterable<AiSeminarRunCardEvidenceSnapshot> evidenceRefs,
    required String idSuffix,
  }) {
    final runId = _trimSeminarMessageValue(parentRunId);
    if (runId.isEmpty) return parts;
    final normalizedToolId = _trimSeminarMessageValue(toolId);
    final normalizedEvidenceRefs = _mergeSeminarEvidenceRefs(evidenceRefs);
    if (normalizedEvidenceRefs.isEmpty) return parts;
    final evidencePartIndex = parts.indexWhere(
      (part) {
        if (!_isSeminarEvidenceMessagePart(part)) return false;
        if (_trimSeminarMessageValue(part.parentRunId) != runId) return false;
        final partToolId = _trimSeminarMessageValue(part.toolId);
        if (partToolId == normalizedToolId) return true;
        return idSuffix == 'tool-call' &&
            normalizedToolId.isNotEmpty &&
            partToolId.isEmpty;
      },
    );
    if (evidencePartIndex >= 0) {
      final evidencePart = parts[evidencePartIndex];
      final mergedEvidenceRefs = _mergeSeminarEvidenceRefs([
        ...evidencePart.evidenceRefs,
        ...normalizedEvidenceRefs,
      ]);
      if (mergedEvidenceRefs.length == evidencePart.evidenceRefs.length) {
        return parts;
      }
      return [
        ...parts.take(evidencePartIndex),
        _copySeminarMessagePartWithEvidenceRefs(
          evidencePart,
          mergedEvidenceRefs,
          toolId: normalizedToolId.isEmpty ? null : normalizedToolId,
        ),
        ...parts.skip(evidencePartIndex + 1),
      ];
    }
    return [
      ...parts,
      AiSeminarRunCardMessagePart(
        type: 'evidence',
        id: '$runId:evidence:$idSuffix',
        parentRunId: runId,
        toolId: normalizedToolId.isEmpty ? null : normalizedToolId,
        label: 'Evidence snapshot',
        evidenceRefs: normalizedEvidenceRefs,
      ),
    ];
  }

  bool _isSeminarEvidenceMessagePart(AiSeminarRunCardMessagePart part) {
    final type = part.type.trim();
    return type == 'evidence' || type == 'evidence_bundle';
  }

  AiSeminarRunCardMessagePart _copySeminarMessagePartWithEvidenceRefs(
      AiSeminarRunCardMessagePart part,
      List<AiSeminarRunCardEvidenceSnapshot> evidenceRefs,
      {String? toolId}) {
    return AiSeminarRunCardMessagePart(
      type: part.type,
      id: part.id,
      agentRunId: part.agentRunId,
      parentRunId: part.parentRunId,
      roleId: part.roleId,
      roleIds: part.roleIds,
      actionIds: part.actionIds,
      allowedToolIds: part.allowedToolIds,
      defaultRoleId: part.defaultRoleId,
      defaultActionId: part.defaultActionId,
      selectedRoleId: part.selectedRoleId,
      selectedActionId: part.selectedActionId,
      draftText: part.draftText,
      toolId: toolId ?? part.toolId,
      status: part.status,
      label: part.label,
      text: part.text,
      query: part.query,
      resultCount: part.resultCount,
      startedAt: part.startedAt,
      completedAt: part.completedAt,
      evidenceRefs: evidenceRefs,
    );
  }

  List<AiSeminarRunCardMessagePart>
      _suppressPendingSeminarRuntimeControlActions(
    List<AiSeminarRunCardMessagePart> parts,
  ) {
    final actionsByRunId = <String, Set<String>>{};
    final pendingToolWaits = <AiSeminarRunCardMessagePart>[];
    for (final part in parts) {
      if (_isPendingSeminarToolCallWaitReaderTurn(part)) {
        pendingToolWaits.add(part);
        continue;
      }
      final actionId = _suppressedSeminarRuntimeControlActionId(part);
      if (actionId == null) continue;
      final runId = _seminarMessagePartRunId(part);
      if (runId == null || runId.isEmpty) continue;
      actionsByRunId.putIfAbsent(runId, () => <String>{}).add(actionId);
    }
    if (actionsByRunId.isEmpty && pendingToolWaits.isEmpty) return parts;
    return parts.map((part) {
      final type = part.type.trim();
      if (type == 'tool_call' && pendingToolWaits.isNotEmpty) {
        final shouldSuppressWait = pendingToolWaits.any(
          (wait) => _seminarToolWaitMatchesToolCall(wait, part),
        );
        if (!shouldSuppressWait) return part;
        final actionIds = part.actionIds
            .map((actionId) => actionId.trim())
            .where(
              (actionId) => actionId.isNotEmpty && actionId != 'wait-tool-call',
            )
            .toList(growable: false);
        if (actionIds.length == part.actionIds.length) return part;
        return AiSeminarRunCardMessagePart(
          type: part.type,
          id: part.id,
          agentRunId: part.agentRunId,
          parentRunId: part.parentRunId,
          roleId: part.roleId,
          roleIds: part.roleIds,
          actionIds: actionIds,
          allowedToolIds: part.allowedToolIds,
          defaultRoleId: part.defaultRoleId,
          defaultActionId: part.defaultActionId,
          selectedRoleId: part.selectedRoleId,
          selectedActionId: part.selectedActionId,
          draftText: part.draftText,
          toolId: part.toolId,
          status: part.status,
          label: part.label,
          text: part.text,
          query: part.query,
          resultCount: part.resultCount,
          startedAt: part.startedAt,
          completedAt: part.completedAt,
          evidenceRefs: part.evidenceRefs,
        );
      }
      if (type != 'agent_status' && type != 'director_state') return part;
      final runId = _seminarMessagePartRunId(part);
      if (runId == null || runId.isEmpty) return part;
      final suppressedActions = actionsByRunId[runId];
      if (suppressedActions == null || suppressedActions.isEmpty) {
        return part;
      }
      final actionIds = part.actionIds
          .map((actionId) => actionId.trim())
          .where(
            (actionId) =>
                actionId.isNotEmpty && !suppressedActions.contains(actionId),
          )
          .toList(growable: false);
      if (actionIds.length == part.actionIds.length) return part;
      return AiSeminarRunCardMessagePart(
        type: part.type,
        id: part.id,
        agentRunId: part.agentRunId,
        parentRunId: part.parentRunId,
        roleId: part.roleId,
        roleIds: part.roleIds,
        actionIds: actionIds,
        allowedToolIds: part.allowedToolIds,
        defaultRoleId: part.defaultRoleId,
        defaultActionId: part.defaultActionId,
        selectedRoleId: part.selectedRoleId,
        selectedActionId: part.selectedActionId,
        draftText: part.draftText,
        toolId: part.toolId,
        status: part.status,
        label: part.label,
        text: part.text,
        query: part.query,
        resultCount: part.resultCount,
        startedAt: part.startedAt,
        completedAt: part.completedAt,
        evidenceRefs: part.evidenceRefs,
      );
    }).toList(growable: false);
  }

  bool _isPendingSeminarToolCallWaitReaderTurn(
    AiSeminarRunCardMessagePart part,
  ) {
    return part.type.trim() == 'reader_turn' &&
        _trimSeminarMessageValue(part.label) == 'wait-tool-call' &&
        _trimSeminarMessageValue(part.status) == 'pending' &&
        _seminarMessagePartRunId(part) != null;
  }

  bool _seminarToolWaitMatchesToolCall(
    AiSeminarRunCardMessagePart wait,
    AiSeminarRunCardMessagePart toolCall,
  ) {
    if (toolCall.type.trim() != 'tool_call') return false;
    final waitRunId = _seminarMessagePartRunId(wait);
    final toolRunId = _seminarMessagePartRunId(toolCall);
    if (waitRunId == null || waitRunId != toolRunId) return false;
    final waitToolId = wait.toolId?.trim();
    final toolId = toolCall.toolId?.trim();
    if (waitToolId != null &&
        waitToolId.isNotEmpty &&
        toolId != null &&
        toolId.isNotEmpty &&
        waitToolId != toolId) {
      return false;
    }
    final waitQuery = wait.query?.trim();
    final toolQuery = toolCall.query?.trim();
    return waitQuery == null ||
        waitQuery.isEmpty ||
        toolQuery == null ||
        toolQuery.isEmpty ||
        waitQuery == toolQuery;
  }

  bool _seminarToolWaitMatchesToolCallReaderTurn(
    AiSeminarRunCardMessagePart existing,
    AiSeminarRunCardMessagePart incoming,
  ) {
    if (!_isSeminarToolCallWaitReaderTurn(existing) ||
        !_isSeminarToolCallWaitReaderTurn(incoming)) {
      return false;
    }
    final existingId = _trimSeminarMessageValue(existing.id);
    final incomingId = _trimSeminarMessageValue(incoming.id);
    if (existingId.isNotEmpty &&
        incomingId.isNotEmpty &&
        existingId == incomingId) {
      return true;
    }
    final existingRunId = _seminarMessagePartRunId(existing);
    final incomingRunId = _seminarMessagePartRunId(incoming);
    if (existingRunId == null ||
        incomingRunId == null ||
        existingRunId != incomingRunId) {
      return false;
    }
    final existingToolId = existing.toolId?.trim();
    final incomingToolId = incoming.toolId?.trim();
    if (existingToolId != null &&
        existingToolId.isNotEmpty &&
        incomingToolId != null &&
        incomingToolId.isNotEmpty &&
        existingToolId != incomingToolId) {
      return false;
    }
    final existingQuery = existing.query?.trim();
    final incomingQuery = incoming.query?.trim();
    if (existingQuery != null &&
        existingQuery.isNotEmpty &&
        incomingQuery != null &&
        incomingQuery.isNotEmpty &&
        existingQuery != incomingQuery) {
      return false;
    }
    return true;
  }

  String? _suppressedSeminarRuntimeControlActionId(
    AiSeminarRunCardMessagePart part,
  ) {
    final status = _trimSeminarMessageValue(part.status);
    final label = _trimSeminarMessageValue(part.label);
    if (status == 'pending' && label == 'wait-agent') {
      return _seminarMessagePartRunId(part) == null ? null : 'wait-agent';
    }
    if (!_isSeminarRuntimeControlReaderTurn(part)) return null;
    if (status != 'pending' && !_isTerminalSeminarReaderControlPart(part)) {
      return null;
    }
    return switch (label) {
      'send-input' => 'send-input',
      'resume-agent' => 'resume-agent',
      'retry-agent-control' => 'retry-agent-control',
      _ => null,
    };
  }

  AiSeminarRunCardMessagePart _mergeSeminarMessagePartForReplacement(
    AiSeminarRunCardMessagePart existing,
    AiSeminarRunCardMessagePart incoming,
  ) {
    final allowedToolIds = incoming.allowedToolIds.isNotEmpty
        ? incoming.allowedToolIds
        : existing.allowedToolIds;
    final roleIds =
        incoming.roleIds.isNotEmpty ? incoming.roleIds : existing.roleIds;
    final query = _trimSeminarMessageValue(incoming.query).isNotEmpty
        ? incoming.query
        : existing.query;
    final evidenceRefs = incoming.evidenceRefs.isNotEmpty
        ? incoming.evidenceRefs
        : existing.evidenceRefs;
    final text = _mergeSeminarToolCallText(
      existing: existing,
      incoming: incoming,
    );
    final resultCount = _mergeSeminarToolCallResultCount(
      existing: existing,
      incoming: incoming,
    );
    return AiSeminarRunCardMessagePart(
      type: incoming.type,
      id: incoming.id,
      agentRunId: incoming.agentRunId,
      parentRunId: incoming.parentRunId,
      roleId: incoming.roleId,
      roleIds: roleIds,
      actionIds: incoming.actionIds,
      allowedToolIds: allowedToolIds,
      defaultRoleId: incoming.defaultRoleId,
      defaultActionId: incoming.defaultActionId,
      selectedRoleId: incoming.selectedRoleId,
      selectedActionId: incoming.selectedActionId,
      draftText: incoming.draftText,
      toolId: incoming.toolId,
      status: incoming.status,
      label: incoming.label,
      text: text,
      query: query,
      resultCount: resultCount,
      startedAt: incoming.startedAt ?? existing.startedAt,
      completedAt: incoming.completedAt ?? existing.completedAt,
      evidenceRefs: evidenceRefs,
    );
  }

  String? _mergeSeminarToolCallText({
    required AiSeminarRunCardMessagePart existing,
    required AiSeminarRunCardMessagePart incoming,
  }) {
    if (incoming.type.trim() != 'tool_call' ||
        existing.type.trim() != 'tool_call') {
      return incoming.text;
    }
    final incomingText = _trimSeminarMessageValue(incoming.text);
    if (incomingText.isNotEmpty) return incoming.text;
    if (_trimSeminarMessageValue(incoming.status) != 'completed') {
      return incoming.text;
    }
    final existingText = _trimSeminarMessageValue(existing.text);
    return existingText.isEmpty ? incoming.text : existing.text;
  }

  int _mergeSeminarToolCallResultCount({
    required AiSeminarRunCardMessagePart existing,
    required AiSeminarRunCardMessagePart incoming,
  }) {
    if (incoming.type.trim() != 'tool_call' ||
        existing.type.trim() != 'tool_call') {
      return incoming.resultCount;
    }
    if (incoming.resultCount > 0 || existing.resultCount <= 0) {
      return incoming.resultCount;
    }
    if (_trimSeminarMessageValue(incoming.status) != 'completed') {
      return incoming.resultCount;
    }
    final text = _trimSeminarMessageValue(incoming.text).toLowerCase();
    if (text.contains('returned 0 ') || text.contains('0 traceable')) {
      return incoming.resultCount;
    }
    return existing.resultCount;
  }

  bool _seminarSnapshotChanged(
    AiSeminarRunCardSnapshot? before,
    AiSeminarRunCardSnapshot? after,
  ) {
    if (before == null && after == null) return false;
    if (before == null) return after != null && !after.isEmpty;
    if (after == null) return true;
    return before.toJson().toString() != after.toJson().toString();
  }

  String _seminarMessagePartKey(AiSeminarRunCardMessagePart part) {
    final id = part.id?.trim();
    if (id != null && id.isNotEmpty) return 'id:$id';
    return [
      part.type.trim(),
      part.roleId?.trim() ?? '',
      part.label?.trim() ?? '',
      part.text?.trim() ?? '',
      part.query?.trim() ?? '',
    ].join('|');
  }

  bool _isSameSeminarToolCallPart(
    AiSeminarRunCardMessagePart existing,
    AiSeminarRunCardMessagePart incoming,
  ) {
    if (existing.type.trim() != 'tool_call' ||
        incoming.type.trim() != 'tool_call') {
      return false;
    }
    final existingId = _trimSeminarMessageValue(existing.id);
    final incomingId = _trimSeminarMessageValue(incoming.id);
    if (existingId.isNotEmpty &&
        incomingId.isNotEmpty &&
        existingId == incomingId) {
      return true;
    }
    final existingRunId = _seminarMessagePartRunId(existing);
    final incomingRunId = _seminarMessagePartRunId(incoming);
    if (existingRunId != null || incomingRunId != null) {
      if (existingRunId != null &&
          incomingRunId != null &&
          existingRunId != incomingRunId) {
        return false;
      }
      if ((existingRunId == null || incomingRunId == null) &&
          _trimSeminarMessageValue(existing.parentRunId) !=
              _trimSeminarMessageValue(incoming.parentRunId)) {
        return false;
      }
    } else if (_trimSeminarMessageValue(existing.parentRunId) !=
        _trimSeminarMessageValue(incoming.parentRunId)) {
      return false;
    }
    return _trimSeminarMessageValue(existing.toolId) ==
            _trimSeminarMessageValue(incoming.toolId) &&
        _trimSeminarMessageValue(existing.query) ==
            _trimSeminarMessageValue(incoming.query);
  }

  bool _shouldReplaceSeminarMessagePart(
    AiSeminarRunCardMessagePart existing,
    AiSeminarRunCardMessagePart incoming,
  ) {
    if (existing.type.trim() == 'tool_call' &&
        incoming.type.trim() == 'tool_call' &&
        _isTerminalSeminarToolCallPart(existing) &&
        !_isTerminalSeminarToolCallPart(incoming)) {
      return false;
    }
    return true;
  }

  bool _isCompletedSeminarRuntimeControlReaderTurn(
    AiSeminarRunCardMessagePart part,
  ) {
    return _isSeminarRuntimeControlReaderTurn(part) &&
        _trimSeminarMessageValue(part.status) == 'completed';
  }

  bool _isStalePendingSeminarRuntimeControlReaderTurn(
    AiSeminarRunCardMessagePart existing,
    AiSeminarRunCardMessagePart incoming,
  ) {
    return _isSeminarRuntimeControlReaderTurn(existing) &&
        _trimSeminarMessageValue(existing.status) == 'pending' &&
        _seminarMessagePartRunId(existing) ==
            _seminarMessagePartRunId(incoming);
  }

  bool _isSeminarRuntimeControlReaderTurn(
    AiSeminarRunCardMessagePart part,
  ) {
    if (part.type.trim() != 'reader_turn') return false;
    switch (_trimSeminarMessageValue(part.label)) {
      case 'send-input':
      case 'resume-agent':
      case 'retry-agent-control':
        return _seminarMessagePartRunId(part) != null;
      default:
        return false;
    }
  }

  String? _seminarReaderControlKey(AiSeminarRunCardMessagePart part) {
    final runId = _seminarMessagePartRunId(part);
    if (runId == null || runId.isEmpty) return null;
    final label = _trimSeminarMessageValue(part.label);
    if (label == 'wait-agent') return '$runId|$label';
    if (!_isSeminarRuntimeControlReaderTurn(part)) return null;
    return '$runId|$label';
  }

  bool _isTerminalSeminarReaderControlPart(
    AiSeminarRunCardMessagePart part,
  ) {
    if (_seminarReaderControlKey(part) == null) return false;
    switch (_trimSeminarMessageValue(part.status)) {
      case 'completed':
      case 'cancelled':
        return true;
      default:
        return false;
    }
  }

  bool _isTerminalSeminarArtifactActionsPart(
    AiSeminarRunCardMessagePart part,
  ) {
    return _isSeminarArtifactActionsPart(part) &&
        part.actionIds.any(_isReplayableSeminarArtifactActionId);
  }

  bool _isSameSeminarArtifactActionsRun(
    AiSeminarRunCardMessagePart existing,
    AiSeminarRunCardMessagePart incoming,
  ) {
    if (!_isSeminarArtifactActionsPart(existing) ||
        !_isSeminarArtifactActionsPart(incoming)) {
      return false;
    }
    final existingRunId = _seminarMessagePartRunId(existing);
    final incomingRunId = _seminarMessagePartRunId(incoming);
    if (existingRunId == null || incomingRunId == null) return false;
    return existingRunId == incomingRunId;
  }

  AiSeminarRunCardMessagePart _mergeSeminarArtifactActionsParts(
    List<AiSeminarRunCardMessagePart> existingParts,
    AiSeminarRunCardMessagePart incoming,
  ) {
    final fallback = existingParts.isEmpty ? null : existingParts.first;
    final supersededActions =
        _supersededSeminarArtifactActionIdsForIncoming(incoming);
    final actionIds = <String>[];
    void addAction(String actionId) {
      final normalized = actionId.trim();
      if (normalized.isEmpty || actionIds.contains(normalized)) return;
      actionIds.add(normalized);
    }

    for (final existing in existingParts) {
      for (final actionId in existing.actionIds) {
        if (supersededActions.contains(actionId.trim())) continue;
        addAction(actionId);
      }
    }
    for (final actionId in incoming.actionIds) {
      if (_isIncomingSeminarArtifactExecutionMarker(actionId, incoming)) {
        continue;
      }
      addAction(actionId);
    }

    return AiSeminarRunCardMessagePart(
      type: incoming.type,
      id: incoming.id,
      agentRunId: incoming.agentRunId ?? fallback?.agentRunId,
      parentRunId: incoming.parentRunId ?? fallback?.parentRunId,
      roleId: incoming.roleId ?? fallback?.roleId,
      roleIds: incoming.roleIds.isNotEmpty
          ? incoming.roleIds
          : fallback?.roleIds ?? const <String>[],
      actionIds: actionIds,
      allowedToolIds: incoming.allowedToolIds.isNotEmpty
          ? incoming.allowedToolIds
          : fallback?.allowedToolIds ?? const <String>[],
      defaultRoleId: incoming.defaultRoleId ?? fallback?.defaultRoleId,
      defaultActionId: incoming.defaultActionId ?? fallback?.defaultActionId,
      selectedRoleId: incoming.selectedRoleId ?? fallback?.selectedRoleId,
      selectedActionId: incoming.selectedActionId ?? fallback?.selectedActionId,
      draftText: incoming.draftText ?? fallback?.draftText,
      toolId: incoming.toolId ?? fallback?.toolId,
      status: incoming.status ?? fallback?.status,
      label: incoming.label ?? fallback?.label,
      text: _nonEmptyOrFallback(
        incoming.text,
        existingParts
            .map((part) => part.text)
            .whereType<String>()
            .firstWhere((text) => text.trim().isNotEmpty, orElse: () => ''),
      ),
      query: incoming.query ?? fallback?.query,
      resultCount: incoming.resultCount,
      completedAt: incoming.completedAt ?? fallback?.completedAt,
      evidenceRefs: _mergeSeminarArtifactEvidenceRefs([
        for (final existing in existingParts) ...existing.evidenceRefs,
        ...incoming.evidenceRefs,
      ]),
    );
  }

  Set<String> _supersededSeminarArtifactActionIdsForIncoming(
    AiSeminarRunCardMessagePart incoming,
  ) {
    final primaryActionId = _primarySeminarArtifactActionId(incoming);
    if (primaryActionId == null) {
      return _supersededSeminarArtifactActionIds(incoming.actionIds);
    }
    if (_isSeminarArtifactExecutionMarkerActionId(primaryActionId)) {
      return _supersededSeminarArtifactActionIds([primaryActionId]);
    }
    return _supersededSeminarArtifactActionIds(
      incoming.actionIds.where(
        (actionId) => !_isSeminarArtifactExecutionMarkerActionId(actionId),
      ),
    );
  }

  bool _isIncomingSeminarArtifactExecutionMarker(
    String actionId,
    AiSeminarRunCardMessagePart incoming,
  ) {
    final normalized = actionId.trim();
    final primaryActionId = _primarySeminarArtifactActionId(incoming);
    return primaryActionId == normalized &&
        _isSeminarArtifactExecutionMarkerActionId(normalized);
  }

  String? _primarySeminarArtifactActionId(
    AiSeminarRunCardMessagePart part,
  ) {
    for (final actionId in part.actionIds) {
      final normalized = actionId.trim();
      if (normalized.isNotEmpty) return normalized;
    }
    return null;
  }

  Set<String> _supersededSeminarArtifactActionIds(Iterable<String> actionIds) {
    final superseded = <String>{};
    for (final rawActionId in actionIds) {
      switch (rawActionId.trim()) {
        case 'knowledge-card-saved':
          superseded.addAll({'save-knowledge-card', 'edit-knowledge-card'});
          break;
        case 'undo-knowledge-card':
          superseded.addAll({'knowledge-card-saved', 'undo-knowledge-card'});
          break;
        case 'spaced-review-added':
          superseded.add('add-spaced-review');
          break;
        case 'undo-spaced-review':
          superseded.addAll({'spaced-review-added', 'undo-spaced-review'});
          break;
        case 'concept-graph-added':
          superseded.add('add-concept-graph');
          break;
        case 'undo-concept-graph':
          superseded.addAll({'concept-graph-added', 'undo-concept-graph'});
          break;
        case 'artifact-actions-ignored':
          superseded.addAll({
            'save-knowledge-card',
            'edit-knowledge-card',
            'add-spaced-review',
            'add-concept-graph',
            'send-to-review',
            'ignore-artifact-actions',
          });
          break;
        case 'restore-artifact-actions':
          superseded.addAll({
            'artifact-actions-ignored',
            'restore-artifact-actions',
          });
          break;
        case 'sent-to-review':
          superseded.add('send-to-review');
          break;
      }
    }
    return superseded;
  }

  List<AiSeminarRunCardEvidenceSnapshot> _mergeSeminarArtifactEvidenceRefs(
    Iterable<AiSeminarRunCardEvidenceSnapshot> evidenceRefs,
  ) {
    return _mergeSeminarEvidenceRefs(evidenceRefs);
  }

  List<AiSeminarRunCardEvidenceSnapshot> _mergeSeminarEvidenceRefs(
    Iterable<AiSeminarRunCardEvidenceSnapshot> evidenceRefs,
  ) {
    final merged = <AiSeminarRunCardEvidenceSnapshot>[];
    final seen = <String>{};
    for (final evidence in evidenceRefs) {
      if (evidence.isEmpty) continue;
      final key = _seminarEvidenceSnapshotKey(evidence);
      if (!seen.add(key)) continue;
      merged.add(evidence);
    }
    return merged;
  }

  List<String> _mergeSeminarStringValues(Iterable<String> values) {
    final merged = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      merged.add(trimmed);
    }
    return merged;
  }

  String _seminarEvidenceSnapshotKey(
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

  bool _isTerminalSeminarToolCallPart(AiSeminarRunCardMessagePart part) {
    if (part.type.trim() != 'tool_call') return false;
    switch (_trimSeminarMessageValue(part.status)) {
      case 'completed':
      case 'errored':
      case 'interrupted':
      case 'shutdown':
      case 'notFound':
      case 'not_found':
      case 'not-found':
      case 'cancelled':
      case 'canceled':
        return true;
      default:
        return false;
    }
  }

  String _trimSeminarMessageValue(String? value) => value?.trim() ?? '';

  String? _seminarSupersededStatusRunId(
    AiSeminarRunCardMessagePart part,
  ) {
    final type = part.type.trim();
    if (type == 'director_state' ||
        type == 'agent_status' ||
        type == 'role_partial' ||
        type == 'role_turn' ||
        type == 'synthesis') {
      return _seminarMessagePartRunId(part);
    }
    return null;
  }

  bool _keepSeminarStatusPartAfterIncoming(
    AiSeminarRunCardMessagePart existing,
    AiSeminarRunCardMessagePart incoming, {
    required bool onlySupersedesTransientStatuses,
  }) {
    if (incoming.type.trim() == 'role_partial') {
      return _isTransientSeminarStatusPart(existing);
    }
    if (_isGraphTracedSeminarContentPart(incoming)) {
      return !_isFailedSeminarStatusPart(existing);
    }
    return onlySupersedesTransientStatuses &&
        !_isTransientSeminarStatusPart(existing);
  }

  bool _seminarOnlySupersedesTransientStatuses(
    AiSeminarRunCardMessagePart part,
  ) {
    final type = part.type.trim();
    return type == 'role_turn' || type == 'synthesis';
  }

  bool _seminarPartSupersedesRolePartial(
    AiSeminarRunCardMessagePart part,
  ) {
    if (_seminarOnlySupersedesTransientStatuses(part)) return true;
    final type = part.type.trim();
    if (type != 'agent_status' && type != 'director_state') return false;
    return !_isTransientSeminarStatusPart(part);
  }

  bool _isGraphTracedSeminarContentPart(
    AiSeminarRunCardMessagePart part,
  ) {
    final type = part.type.trim();
    if (type != 'role_turn' && type != 'synthesis') return false;
    return _seminarMessagePartRunId(part) != null;
  }

  bool _isGraphTracedSeminarRoleTerminalPart(
    AiSeminarRunCardMessagePart part,
  ) {
    final type = part.type.trim();
    if (type == 'role_turn') {
      return _seminarMessagePartRunId(part) != null;
    }
    if (type != 'agent_status') return false;
    return !_isTransientSeminarStatusPart(part) &&
        _seminarMessagePartRunId(part) != null;
  }

  bool _isGraphTracedSeminarRoleWaitSettledPart(
    AiSeminarRunCardMessagePart part,
  ) {
    if (_isGraphTracedSeminarRoleTerminalPart(part)) return true;
    if (part.type.trim() != 'agent_status') return false;
    return part.label?.trim() == 'role-interrupted' &&
        _seminarMessagePartRunId(part) != null;
  }

  bool _isPendingSeminarWaitReaderTurnForRun(
    AiSeminarRunCardMessagePart part,
    String? runId,
  ) {
    if (runId == null || runId.isEmpty) return false;
    return _isSeminarRoleWaitReaderTurn(part) &&
        _trimSeminarMessageValue(part.status) == 'pending' &&
        _seminarMessagePartRunId(part) == runId;
  }

  bool _isSeminarWaitReaderTurn(AiSeminarRunCardMessagePart part) {
    return _isSeminarRoleWaitReaderTurn(part) ||
        _isSeminarToolCallWaitReaderTurn(part);
  }

  bool _isSeminarRoleWaitReaderTurn(AiSeminarRunCardMessagePart part) {
    return part.type.trim() == 'reader_turn' &&
        _trimSeminarMessageValue(part.label) == 'wait-agent';
  }

  bool _isSeminarToolCallWaitReaderTurn(AiSeminarRunCardMessagePart part) {
    return part.type.trim() == 'reader_turn' &&
        _trimSeminarMessageValue(part.label) == 'wait-tool-call';
  }

  AiSeminarRunCardMessagePart _completedSeminarWaitReaderTurn(
    AiSeminarRunCardMessagePart part, {
    int? completedAt,
  }) {
    return AiSeminarRunCardMessagePart(
      type: part.type,
      id: part.id,
      agentRunId: part.agentRunId,
      parentRunId: part.parentRunId,
      roleId: part.roleId,
      roleIds: part.roleIds,
      actionIds: part.actionIds,
      allowedToolIds: part.allowedToolIds,
      defaultRoleId: part.defaultRoleId,
      defaultActionId: part.defaultActionId,
      selectedRoleId: part.selectedRoleId,
      selectedActionId: part.selectedActionId,
      draftText: part.draftText,
      toolId: part.toolId,
      status: 'completed',
      label: part.label,
      text: part.text,
      query: part.query,
      resultCount: part.resultCount,
      completedAt: part.completedAt ??
          completedAt ??
          DateTime.now().millisecondsSinceEpoch,
      evidenceRefs: part.evidenceRefs,
    );
  }

  bool _isPendingSeminarRuntimeControlReaderTurnForRun(
    AiSeminarRunCardMessagePart part,
    String? runId,
  ) {
    if (runId == null || runId.isEmpty) return false;
    return _isSeminarRuntimeControlReaderTurn(part) &&
        _trimSeminarMessageValue(part.status) == 'pending' &&
        _seminarMessagePartRunId(part) == runId;
  }

  AiSeminarRunCardMessagePart _cancelledSeminarRuntimeControlReaderTurn(
    AiSeminarRunCardMessagePart part,
  ) {
    return AiSeminarRunCardMessagePart(
      type: part.type,
      id: part.id,
      agentRunId: part.agentRunId,
      parentRunId: part.parentRunId,
      roleId: part.roleId,
      roleIds: part.roleIds,
      actionIds: part.actionIds,
      allowedToolIds: part.allowedToolIds,
      defaultRoleId: part.defaultRoleId,
      defaultActionId: part.defaultActionId,
      selectedRoleId: part.selectedRoleId,
      selectedActionId: part.selectedActionId,
      draftText: part.draftText,
      toolId: part.toolId,
      status: 'cancelled',
      label: part.label,
      text: part.text,
      query: part.query,
      resultCount: part.resultCount,
      completedAt: part.completedAt ?? DateTime.now().millisecondsSinceEpoch,
      evidenceRefs: part.evidenceRefs,
    );
  }

  bool _isLegacyDuplicateSeminarContentPart(
    AiSeminarRunCardMessagePart existing,
    AiSeminarRunCardMessagePart incoming,
  ) {
    final type = incoming.type.trim();
    if (existing.type.trim() != type) return false;
    final existingRunId = _seminarMessagePartRunId(existing);
    final incomingRunId = _seminarMessagePartRunId(incoming);
    if (existingRunId != null &&
        incomingRunId != null &&
        existingRunId == incomingRunId) {
      if (type == 'role_turn') {
        return (existing.roleId?.trim() ?? '') ==
            (incoming.roleId?.trim() ?? '');
      }
      return true;
    }
    if (existingRunId != null) return false;
    final incomingText = incoming.text?.trim();
    final existingText = existing.text?.trim();
    if (incomingText == null ||
        incomingText.isEmpty ||
        existingText == null ||
        existingText.isEmpty ||
        incomingText != existingText) {
      return false;
    }
    if (type == 'role_turn') {
      return (existing.roleId?.trim() ?? '') == (incoming.roleId?.trim() ?? '');
    }
    return true;
  }

  String? _seminarStatusPartRunId(AiSeminarRunCardMessagePart part) {
    final type = part.type.trim();
    if (type != 'director_state' && type != 'agent_status') return null;
    return _seminarMessagePartRunId(part);
  }

  String? _seminarRolePartialPartRunId(AiSeminarRunCardMessagePart part) {
    if (part.type.trim() != 'role_partial') return null;
    return _seminarMessagePartRunId(part);
  }

  bool _isGenericSeminarRoleStartThinkingPart(
    AiSeminarRunCardMessagePart part,
  ) {
    return part.type.trim() == 'thinking' &&
        (part.id?.trim().endsWith(':thinking:start') ?? false);
  }

  bool _isStreamedSeminarThinkingPart(AiSeminarRunCardMessagePart part) {
    return part.type.trim() == 'thinking' &&
        (part.id?.trim().contains(':thinking:stream:') ?? false);
  }

  String? _seminarMessagePartRunId(AiSeminarRunCardMessagePart part) {
    final agentRunId = part.agentRunId?.trim();
    if (agentRunId != null && agentRunId.isNotEmpty) return agentRunId;
    final id = part.id?.trim();
    if (id == null || id.isEmpty) return null;
    const marker = ':status:';
    final markerIndex = id.lastIndexOf(marker);
    if (markerIndex > 0) return id.substring(0, markerIndex);
    for (final controlMarker in const [
      ':user-input:',
      ':wait-request:',
      ':resume-request:',
      ':retry-request:',
      ':delta:',
      ':thinking:',
    ]) {
      final controlMarkerIndex = id.lastIndexOf(controlMarker);
      if (controlMarkerIndex > 0) {
        return id.substring(0, controlMarkerIndex);
      }
    }
    for (final suffix in const [':result', ':error']) {
      if (id.endsWith(suffix) && id.length > suffix.length) {
        return id.substring(0, id.length - suffix.length);
      }
    }
    return null;
  }

  bool _isTransientSeminarStatusPart(AiSeminarRunCardMessagePart part) {
    switch (part.label?.trim()) {
      case 'role-pending':
      case 'role-running':
      case 'role-waiting-input':
      case 'role-interrupted':
        return true;
      default:
        return false;
    }
  }

  bool _isUnreopenableSeminarStatusPart(AiSeminarRunCardMessagePart part) {
    switch (part.label?.trim()) {
      case 'role-shutdown':
      case 'role-not-found':
      case 'stopped':
      case 'not-found':
        return _seminarStatusPartRunId(part) != null;
      default:
        return false;
    }
  }

  bool _isFailedSeminarStatusPart(AiSeminarRunCardMessagePart part) {
    final label = part.label?.trim();
    final status = part.status?.trim();
    return label == 'role-error' ||
        label == 'failed' ||
        status == 'errored' ||
        status == 'failed';
  }

  AiSeminarRunCardMeta? _seminarRunCardBySessionId(String seminarSessionId) {
    final targetSessionId = seminarSessionId.trim();
    if (targetSessionId.isEmpty) return null;
    for (final node in _tree.nodes.values) {
      final card = node.meta?.seminarRunCard;
      if (card?.sessionId == targetSessionId) return card;
    }
    return null;
  }

  Future<bool> updateSeminarRunCardConfig({
    required String seminarSessionId,
    String? question,
    int? maxRounds,
    List<String>? roleIds,
    List<String>? evidenceScopeIds,
    List<AiSeminarRoleProfile>? roleProfiles,
  }) async {
    final targetSessionId = seminarSessionId.trim();
    if (targetSessionId.isEmpty || _tree.nodes.isEmpty) return false;

    String? targetNodeId;
    AiConversationNode? targetNode;
    AiSeminarRunCardMeta? targetCard;
    for (final entry in _tree.nodes.entries) {
      final card = entry.value.meta?.seminarRunCard;
      if (card?.sessionId == targetSessionId) {
        targetNodeId = entry.key;
        targetNode = entry.value;
        targetCard = card;
        break;
      }
    }
    if (targetNodeId == null || targetNode == null || targetCard == null) {
      return false;
    }

    final meta = targetNode.meta ?? const AiSegmentMeta();
    final nextQuestion = question?.trim();
    final updatedBaseCard = targetCard.copyWith(
      question: nextQuestion,
      maxRounds: maxRounds == null
          ? targetCard.maxRounds
          : _seminarMaxRounds(maxRounds),
      roleIds: roleIds,
      evidenceScopeIds: evidenceScopeIds,
      roleProfiles: roleProfiles,
    );
    final updatedCard = updatedBaseCard.copyWith(
      snapshot: _seminarRunSetupSnapshotForCard(
        updatedBaseCard,
        existing: updatedBaseCard.snapshot,
      ),
    );
    _tree = _tree.copyWithNode(
      targetNodeId,
      targetNode.copyWith(
        message: question == null
            ? null
            : ChatMessage.ai(_seminarRunCardFallbackText(updatedCard)).toMap(),
        meta: AiSegmentMeta(
          model: meta.model,
          inputTokens: meta.inputTokens,
          outputTokens: meta.outputTokens,
          seminarRunCard: updatedCard,
        ),
      ),
    );
    _rebuildFromTree();

    final sessionId = _currentSessionId;
    if (sessionId == null) return true;
    final serviceId = Prefs().selectedAiService;
    final config = Prefs().getAiConfig(serviceId);
    final model = (config['model'])?.trim() ?? '';
    final historyNotifier = ref.read(aiHistoryProvider.notifier);
    final existing = historyNotifier.findById(sessionId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final bookContext = _readCurrentBookContext(ref.read);
    final historyBookContext = _historyBookContextFor(
      existing: existing,
      current: bookContext,
    );
    final currentMessages = List<ChatMessage>.from(state.value ?? const []);
    final fallbackTitle = _titleService.deriveFallbackTitle(currentMessages);
    final entry = (existing ??
            AiChatHistoryEntry(
              id: sessionId,
              serviceId: serviceId,
              model: model,
              createdAt: now,
              updatedAt: now,
              title: fallbackTitle,
              titleSource: 'heuristic',
              bookId: historyBookContext.bookId,
              bookTitle: historyBookContext.bookTitle,
              messages: currentMessages,
              completed: true,
            ))
        .copyWith(
      serviceId: serviceId,
      messages: currentMessages,
      updatedAt: now,
      completed: true,
      model: model,
      title: (existing?.title?.trim().isNotEmpty ?? false)
          ? existing!.title
          : fallbackTitle,
      titleSource: (existing?.titleSource?.trim().isNotEmpty ?? false)
          ? existing!.titleSource
          : 'heuristic',
      bookId: historyBookContext.bookId,
      bookTitle: historyBookContext.bookTitle,
      conversationV2: _tree.toJson(),
    );
    if (_draftEntry?.id == entry.id) {
      _draftEntry = entry;
    }
    await _queueDraftHistoryUpsert(historyNotifier, entry);
    return true;
  }

  AiSeminarRunCardSnapshot _seminarRunSetupSnapshotForCard(
    AiSeminarRunCardMeta card, {
    AiSeminarRunCardSnapshot? existing,
  }) {
    final setupPart = _seminarRunSetupMessagePartForCard(card);
    final existingParts = existing?.messageParts
            .where((part) => !_isSeminarRunSetupPart(part))
            .toList(growable: false) ??
        const <AiSeminarRunCardMessagePart>[];
    return AiSeminarRunCardSnapshot(
      evidence:
          existing?.evidence ?? const <AiSeminarRunCardEvidenceSnapshot>[],
      toolCalls:
          existing?.toolCalls ?? const <AiSeminarRunCardToolCallSnapshot>[],
      roleSummaries:
          existing?.roleSummaries ?? const <AiSeminarRunCardRoleSummary>[],
      messageParts: [
        setupPart,
        ...existingParts,
      ],
      synthesisSummary: existing?.synthesisSummary,
      disagreements: existing?.disagreements ?? const <String>[],
      disagreementDetails: existing?.disagreementDetails ??
          const <AiSeminarRunCardDisagreementDetail>[],
      openQuestions: existing?.openQuestions ?? const <String>[],
    );
  }

  AiSeminarRunCardMessagePart _seminarRunSetupMessagePartForCard(
    AiSeminarRunCardMeta card,
  ) {
    final sessionId = card.sessionId?.trim();
    final roleIds = card.roleIds
        .map((roleId) => roleId.trim())
        .where((roleId) => roleId.isNotEmpty)
        .toList(growable: false);
    final roleLabels =
        roleIds.map(_seminarRoleDisplayLabel).toList(growable: false);
    final evidenceScopeIds = card.evidenceScopeIds
        .map((scopeId) => scopeId.trim())
        .where((scopeId) => scopeId.isNotEmpty)
        .toList(growable: false);
    final evidenceScopeLabels = evidenceScopeIds
        .map(_seminarEvidenceScopeDisplayLabel)
        .toList(growable: false);
    return AiSeminarRunCardMessagePart(
      type: 'seminar_run_setup',
      id: sessionId == null || sessionId.isEmpty ? null : 'setup-$sessionId',
      label: [
        if (roleLabels.isNotEmpty) '角色：${roleLabels.join('、')}',
        if (evidenceScopeLabels.isNotEmpty)
          '证据：${evidenceScopeLabels.join('、')}',
        '轮次：${card.maxRounds}',
      ].join(' · '),
      text: card.question.trim().isEmpty ? null : '问题：${card.question.trim()}',
      roleIds: roleIds,
    );
  }

  String _seminarRoleDisplayLabel(String roleId) {
    switch (roleId) {
      case 'critical':
        return '批判者';
      case 'supportive':
        return '支持者';
      case 'synthesizer':
        return '综合者';
      case 'verifier':
        return '核验者';
      default:
        return roleId;
    }
  }

  String _seminarEvidenceScopeDisplayLabel(String scopeId) {
    switch (scopeId) {
      case 'current-chapter':
        return '当前章节';
      case 'current-book':
        return '当前书籍';
      case 'library':
        return '书库';
      case 'notes':
        return '笔记';
      case 'memory':
        return '记忆';
      case 'concept-graph':
        return '概念图谱';
      default:
        return scopeId;
    }
  }

  String _seminarRunCardFallbackText(AiSeminarRunCardMeta card) {
    // P1 F19a: the card node's message text is the LLM-facing seminar digest.
    return seminarRunCardPromptText(card);
  }

  String _seminarSessionId({
    required String? preferred,
    required int now,
  }) {
    final trimmed = preferred?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    return 'seminar-chat-$now';
  }

  List<AiSeminarRoleProfile> _effectiveSeminarRoleProfiles(
    List<AiSeminarRoleProfile>? explicitProfiles,
  ) {
    final source = explicitProfiles ?? Prefs().aiSeminarRoleProfiles;
    final byRole = <AiSeminarRole, AiSeminarRoleProfile>{};
    for (final profile in source) {
      if (profile.hasOverrides) {
        byRole[profile.role] = profile;
      }
    }
    return List.unmodifiable(byRole.values);
  }

  AiSeminarRoleProfile? _roleProfileFor(
    List<AiSeminarRoleProfile> profiles,
    AiSeminarRole role,
  ) {
    for (final profile in profiles) {
      if (profile.role == role) return profile;
    }
    return null;
  }

  List<AiSeminarEvidenceScope> _seminarEvidenceScopesFor(
    List<AiSeminarRoleProfile> profiles,
  ) {
    final scopes = <AiSeminarEvidenceScope>[AiSeminarEvidenceScope.currentBook];
    for (final profile in profiles) {
      if (!profile.enabled) continue;
      for (final scope in profile.evidenceScopes) {
        if (!scopes.contains(scope)) scopes.add(scope);
      }
    }
    return List.unmodifiable(scopes);
  }

  int _seminarMaxRounds(int? value) {
    return (value ?? Prefs().aiSeminarDefaultMaxRounds).clamp(1, 10).toInt();
  }

  void persistCurrentConversation(WidgetRef ref) {
    _persistCurrentConversationWithReader(ref.read);
  }

  void persistCurrentConversationWithContainer(ProviderContainer container) {
    _persistCurrentConversationWithReader(container.read);
  }

  void beginFreshConversation(
    ProviderContainer container, {
    bool persistCurrent = true,
  }) {
    if (persistCurrent) {
      persistCurrentConversationWithContainer(container);
    }
    clear();
  }

  void _persistCurrentConversationWithReader(
    T Function<T>(ProviderListenable<T>) read,
  ) {
    final sessionId = _currentSessionId;
    if (sessionId == null) return;

    final serviceId = Prefs().selectedAiService;
    final config = Prefs().getAiConfig(serviceId);
    final model = (config['model'])?.trim() ?? '';

    final historyNotifier = read(aiHistoryProvider.notifier);
    final existing = historyNotifier.findById(sessionId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final bookContext = _readCurrentBookContext(read);
    final historyBookContext = _historyBookContextFor(
      existing: existing,
      current: bookContext,
    );

    final currentMessages = List<ChatMessage>.from(state.value ?? const []);
    final fallbackTitle = _titleService.deriveFallbackTitle(currentMessages);
    final entry = (existing ??
            AiChatHistoryEntry(
              id: sessionId,
              serviceId: serviceId,
              model: model,
              createdAt: now,
              updatedAt: now,
              title: fallbackTitle,
              titleSource: 'heuristic',
              bookId: historyBookContext.bookId,
              bookTitle: historyBookContext.bookTitle,
              messages: currentMessages,
              completed: true,
            ))
        .copyWith(
      serviceId: serviceId,
      messages: currentMessages,
      updatedAt: now,
      completed: true,
      model: model,
      title: (existing?.title?.trim().isNotEmpty ?? false)
          ? existing!.title
          : fallbackTitle,
      titleSource: (existing?.titleSource?.trim().isNotEmpty ?? false)
          ? existing!.titleSource
          : 'heuristic',
      bookId: historyBookContext.bookId,
      bookTitle: historyBookContext.bookTitle,
      conversationV2: _tree.toJson(),
    );

    historyNotifier.upsert(entry).catchError((_) {});
  }

  String _generateSessionId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  _AiCurrentBookContext _historyBookContextFor({
    required AiChatHistoryEntry? existing,
    required _AiCurrentBookContext current,
  }) {
    if (existing != null) {
      return _AiCurrentBookContext(
        bookId: existing.bookId,
        bookTitle: existing.bookTitle,
      );
    }

    if (_loadedHistoryEntryId == _currentSessionId) {
      return _AiCurrentBookContext(
        bookId: _loadedHistoryBookId,
        bookTitle: _loadedHistoryBookTitle,
      );
    }

    return current;
  }
}

_AiCurrentBookContext _readCurrentBookContext(
  T Function<T>(ProviderListenable<T>) read,
) {
  final reading = read(currentReadingProvider);
  if (!reading.isReading) {
    return const _AiCurrentBookContext();
  }

  final book = reading.book;
  if (book == null || book.id <= 0) {
    return const _AiCurrentBookContext();
  }

  final title = book.title.trim();
  return _AiCurrentBookContext(
    bookId: book.id,
    bookTitle: title.isEmpty ? null : title,
  );
}

class _AiCurrentBookContext {
  const _AiCurrentBookContext({
    this.bookId,
    this.bookTitle,
  });

  final int? bookId;
  final String? bookTitle;
}
