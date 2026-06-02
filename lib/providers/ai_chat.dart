import 'dart:async';

import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/providers/ai_history.dart';
import 'package:papertok_reader/providers/current_reading.dart';
import 'package:papertok_reader/service/ai/ai_history.dart';
import 'package:papertok_reader/service/ai/conversation_title_service.dart';
import 'package:papertok_reader/service/ai/index.dart';
import 'package:papertok_reader/service/ai/prompt_budgeting_service.dart';
import 'package:papertok_reader/service/mcp/mcp_client_service.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/attachment_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
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

    _rebuildFromTree();
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
    state = AsyncData(_tree.activePathMessages());
  }

  /// Build prompt messages up to the human message node [humanNodeId].
  List<ChatMessage> _buildPromptMessagesForAssistantParent(String humanNodeId) {
    // Walk from the human node back to root using parent pointers.
    final ids = <String>[];
    var currentId = humanNodeId;
    while (currentId != _tree.rootId) {
      ids.add(currentId);
      final node = _tree.nodes[currentId];
      final parentId = node?.parentId;
      if (parentId == null) break;
      currentId = parentId;
    }

    final orderedIds = ids.reversed.toList(growable: false);

    final messages = <ChatMessage>[];
    for (final id in orderedIds) {
      final node = _tree.nodes[id];
      final msg = node?.toChatMessage();
      if (msg != null) {
        messages.add(msg);
      }
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
    final includeVerifier = Prefs().aiSeminarIncludeVerifier;
    final roleIds = <AiSeminarRole>[
      AiSeminarRole.critical,
      AiSeminarRole.supportive,
      if (includeVerifier) AiSeminarRole.verifier,
      AiSeminarRole.synthesizer,
    ].map((role) => role.asString).toList(growable: false);
    final evidenceScopeIds = const <AiSeminarEvidenceScope>[
      AiSeminarEvidenceScope.currentBook,
    ].map((scope) => scope.asString).toList(growable: false);
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

    final card = AiSeminarRunCardMeta(
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
      maxRounds: 2,
      createdAt: now,
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

  String _seminarRunCardFallbackText(AiSeminarRunCardMeta card) {
    final question = card.question.trim();
    if (question.isEmpty) {
      return 'AI Seminar';
    }
    return 'AI Seminar: $question';
  }

  String _seminarSessionId({
    required String? preferred,
    required int now,
  }) {
    final trimmed = preferred?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    return 'seminar-chat-$now';
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
