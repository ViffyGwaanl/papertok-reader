import 'package:papertok_reader/dao/book.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/book.dart';
import 'package:papertok_reader/service/book.dart' as book_service;
import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:papertok_reader/service/memory/memory_rule_prefs.dart';
import 'package:papertok_reader/service/memory/memory_candidate.dart';
import 'package:papertok_reader/service/memory/memory_candidate_store.dart';
import 'package:papertok_reader/service/memory/memory_session_digest_service.dart';
import 'package:papertok_reader/service/memory/memory_source_kind.dart';
import 'package:papertok_reader/service/memory/memory_workflow_policy.dart';
import 'package:papertok_reader/service/memory/memory_write_coordinator.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';
import 'package:papertok_reader/service/shortcuts/papertok_ai_chat_navigator.dart';
import 'package:papertok_reader/utils/toast/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:langchain_core/chat_models.dart';

class MemoryWorkflowService {
  MemoryWorkflowService({
    MarkdownMemoryStore? store,
    MemoryCandidateStore? candidateStore,
    MemoryWriteCoordinator? writeCoordinator,
    MemorySessionDigestService? sessionDigestService,
    ReviewItemStore? reviewItemStore,
  })  : _candidateStore =
            candidateStore ?? MemoryCandidateStore(rootDir: store?.rootDir),
        _writeCoordinator =
            writeCoordinator ?? MemoryWriteCoordinator(store: store),
        _sessionDigestService =
            sessionDigestService ?? const MemorySessionDigestService(),
        _reviewItemStore =
            reviewItemStore ?? ReviewItemStore(rootDir: store?.rootDir);

  static const Uuid _uuid = Uuid();

  final MemoryCandidateStore _candidateStore;
  final MemoryWriteCoordinator _writeCoordinator;
  final MemorySessionDigestService _sessionDigestService;
  final ReviewItemStore _reviewItemStore;

  Future<List<MemoryCandidate>> listCandidates({
    MemoryCandidateStatus? status,
  }) {
    return _candidateStore.list(status: status);
  }

  Future<List<MemoryCandidate>> listPendingCandidates() {
    return listCandidates(status: MemoryCandidateStatus.pending);
  }

  Future<MemoryCandidate> addToReviewInbox({
    required String text,
    required MemoryDocTarget targetDoc,
    String sourceType = 'manual',
    String? conversationId,
    String? messageNodeId,
    String? summary,
    String sensitivity = 'normal',
    double? confidence,
    String? displayText,
    String? sourcePointer,
    String? rawContextRef,
    String? triggerKind,
    int? bookId,
    String? cfi,
    String? chapter,
    MemorySourceKind sourceKind = MemorySourceKind.chat,
    String? rationale,
  }) async {
    final normalized = _normalizeText(text);
    final now = DateTime.now().millisecondsSinceEpoch;
    final candidate = MemoryCandidate(
      id: _uuid.v4(),
      sourceType: sourceType,
      conversationId: conversationId,
      messageNodeId: messageNodeId,
      targetDoc: targetDoc,
      text: normalized,
      summary: summary ?? _defaultSummary(normalized),
      sensitivity: sensitivity,
      confidence: confidence,
      status: MemoryCandidateStatus.pending,
      createdAtMs: now,
      displayText: (displayText ?? normalized).trim(),
      sourcePointer:
          sourcePointer ?? _buildSourcePointer(conversationId, messageNodeId),
      rawContextRef: rawContextRef,
      triggerKind: triggerKind,
      bookId: bookId,
      cfi: cfi,
      chapter: chapter,
      sourceKind: sourceKind,
      rationale: rationale,
    );
    final stored = await _candidateStore.upsert(candidate);
    await _reviewItemStore.upsert(
      MemoryCandidateReviewAdapter.fromMemoryCandidate(stored),
    );
    return stored;
  }

  Future<MemoryCandidate> saveToDaily({
    required String text,
    DateTime? date,
    String sourceType = 'manual',
    String? conversationId,
    String? messageNodeId,
    String? summary,
    String sensitivity = 'normal',
    double? confidence,
    String? displayText,
    String? sourcePointer,
    String? rawContextRef,
    String? triggerKind,
    int? bookId,
    String? cfi,
    String? chapter,
    MemorySourceKind sourceKind = MemorySourceKind.chat,
    String? rationale,
  }) {
    return _saveDirect(
      text: text,
      targetDoc: MemoryDocTarget.daily,
      date: date,
      sourceType: sourceType,
      conversationId: conversationId,
      messageNodeId: messageNodeId,
      summary: summary,
      sensitivity: sensitivity,
      confidence: confidence,
      displayText: displayText,
      sourcePointer: sourcePointer,
      rawContextRef: rawContextRef,
      triggerKind: triggerKind,
      bookId: bookId,
      cfi: cfi,
      chapter: chapter,
      sourceKind: sourceKind,
      rationale: rationale,
    );
  }

  Future<MemoryCandidate> saveToLongTerm({
    required String text,
    String sourceType = 'manual',
    String? conversationId,
    String? messageNodeId,
    String? summary,
    String sensitivity = 'normal',
    double? confidence,
    String? displayText,
    String? sourcePointer,
    String? rawContextRef,
    String? triggerKind,
    int? bookId,
    String? cfi,
    String? chapter,
    MemorySourceKind sourceKind = MemorySourceKind.chat,
    String? rationale,
  }) {
    return _saveDirect(
      text: text,
      targetDoc: MemoryDocTarget.longTerm,
      sourceType: sourceType,
      conversationId: conversationId,
      messageNodeId: messageNodeId,
      summary: summary,
      sensitivity: sensitivity,
      confidence: confidence,
      displayText: displayText,
      sourcePointer: sourcePointer,
      rawContextRef: rawContextRef,
      triggerKind: triggerKind,
      bookId: bookId,
      cfi: cfi,
      chapter: chapter,
      sourceKind: sourceKind,
      rationale: rationale,
    );
  }

  Future<MemorySessionDigestResult> captureSessionDigest({
    required List<ChatMessage> messages,
    MemoryWorkflowDailyStrategy dailyStrategy =
        MemoryWorkflowDailyStrategy.reviewInbox,
    String sourceType = 'session_digest',
    String triggerKind = 'session_digest',
    String? conversationId,
    int maxCandidates = MemorySessionDigestService.defaultMaxCandidates,
    int? bookId,
    String? cfi,
    String? chapter,
    MemorySourceKind sourceKind = MemorySourceKind.chat,
  }) async {
    if (!MemoryRulePrefs.isEnabled(triggerKind)) {
      return MemorySessionDigestResult(
        candidates: const <MemoryCandidate>[],
        dailyStrategy: dailyStrategy,
      );
    }

    final drafts = _sessionDigestService.buildCandidates(
      messages,
      maxCandidates: maxCandidates,
    );

    final created = <MemoryCandidate>[];
    for (final draft in drafts) {
      final rationale = MemorySessionDigestService.buildRationale(
        messageCount: messages.length,
        triggerKind: triggerKind,
        confidence: draft.confidence,
      );
      final candidate = dailyStrategy.writesDailyDirectly
          ? await saveToDaily(
              text: draft.text,
              sourceType: sourceType,
              conversationId: conversationId,
              confidence: draft.confidence,
              displayText: draft.text,
              sourcePointer: _buildSourcePointer(conversationId, null),
              rawContextRef: conversationId == null
                  ? null
                  : 'conversation:$conversationId',
              triggerKind: triggerKind,
              bookId: bookId,
              cfi: cfi,
              chapter: chapter,
              sourceKind: sourceKind,
              rationale: rationale,
            )
          : await addToReviewInbox(
              text: draft.text,
              targetDoc: MemoryDocTarget.daily,
              sourceType: sourceType,
              conversationId: conversationId,
              confidence: draft.confidence,
              displayText: draft.text,
              sourcePointer: _buildSourcePointer(conversationId, null),
              rawContextRef: conversationId == null
                  ? null
                  : 'conversation:$conversationId',
              triggerKind: triggerKind,
              bookId: bookId,
              cfi: cfi,
              chapter: chapter,
              sourceKind: sourceKind,
              rationale: rationale,
            );
      created.add(candidate);
    }

    return MemorySessionDigestResult(
      candidates: created,
      dailyStrategy: dailyStrategy,
    );
  }

  Future<MemoryCandidate> applyCandidate(
    String candidateId, {
    required MemoryDocTarget targetDoc,
    DateTime? date,
  }) async {
    final candidate = await _candidateStore.getById(candidateId);
    if (candidate == null) {
      throw StateError('Memory candidate not found: $candidateId');
    }

    await _appendToTarget(
      targetDoc: targetDoc,
      date: date,
      text: candidate.text,
    );
    return _candidateStore.markApplied(candidateId, targetDoc: targetDoc);
  }

  Future<MemoryCandidate> dismissCandidate(String candidateId) {
    return _candidateStore.dismiss(candidateId);
  }

  Future<MemoryCandidate> _saveDirect({
    required String text,
    required MemoryDocTarget targetDoc,
    DateTime? date,
    required String sourceType,
    String? conversationId,
    String? messageNodeId,
    String? summary,
    required String sensitivity,
    double? confidence,
    String? displayText,
    String? sourcePointer,
    String? rawContextRef,
    String? triggerKind,
    int? bookId,
    String? cfi,
    String? chapter,
    MemorySourceKind sourceKind = MemorySourceKind.chat,
    String? rationale,
  }) async {
    final normalized = _normalizeText(text);
    final now = DateTime.now().millisecondsSinceEpoch;

    await _appendToTarget(targetDoc: targetDoc, date: date, text: normalized);

    final candidate = MemoryCandidate(
      id: _uuid.v4(),
      sourceType: sourceType,
      conversationId: conversationId,
      messageNodeId: messageNodeId,
      targetDoc: targetDoc,
      text: normalized,
      summary: summary ?? _defaultSummary(normalized),
      sensitivity: sensitivity,
      confidence: confidence,
      status: MemoryCandidateStatus.applied,
      createdAtMs: now,
      appliedAtMs: now,
      reviewedAtMs: now,
      appliedTargetDoc: targetDoc,
      decisionSource: 'direct_save',
      displayText: (displayText ?? normalized).trim(),
      sourcePointer:
          sourcePointer ?? _buildSourcePointer(conversationId, messageNodeId),
      rawContextRef: rawContextRef,
      triggerKind: triggerKind,
      bookId: bookId,
      cfi: cfi,
      chapter: chapter,
      sourceKind: sourceKind,
      rationale: rationale,
    );
    return _candidateStore.upsert(candidate);
  }

  Future<void> _appendToTarget({
    required MemoryDocTarget targetDoc,
    DateTime? date,
    required String text,
  }) {
    return _writeCoordinator.append(
      longTerm: targetDoc == MemoryDocTarget.longTerm,
      date:
          targetDoc == MemoryDocTarget.daily ? (date ?? DateTime.now()) : null,
      text: text,
    );
  }

  String _normalizeText(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('text is required');
    }
    return normalized;
  }

  String _buildSourcePointer(String? conversationId, String? messageNodeId) {
    final conversation = (conversationId ?? '').trim();
    final message = (messageNodeId ?? '').trim();
    if (conversation.isEmpty && message.isEmpty) {
      return '';
    }
    if (conversation.isNotEmpty && message.isNotEmpty) {
      return '$conversation#$message';
    }
    return conversation.isNotEmpty ? conversation : message;
  }

  String _defaultSummary(String text) {
    final collapsed = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (collapsed.length <= 80) {
      return collapsed;
    }
    return '${collapsed.substring(0, 77)}...';
  }

  /// Navigate into the reader at the position where [candidate] was captured.
  /// No-op if the candidate has no bookId. Shows a toast if the book is not
  /// found or is deleted.
  Future<void> openInReader(
    BuildContext context,
    MemoryCandidate candidate,
  ) async {
    final bookId = candidate.bookId;
    if (bookId == null) return;

    late final Book book;
    try {
      book = await bookDao.selectBookById(bookId);
    } catch (_) {
      if (context.mounted) {
        AnxToast.show(L10n.of(context).bookDeleted);
      }
      return;
    }

    if (!context.mounted) return;
    await book_service.pushToReadingPageWithContainer(
      ProviderScope.containerOf(context),
      context,
      book,
      cfi: candidate.cfi,
    );
  }

  /// Navigate to the AI chat at the conversation where [candidate] was
  /// captured. If [candidate.conversationId] is null, this is a no-op.
  ///
  /// TODO: wire a proper deep-link when AiChatPage accepts an initial
  /// conversationId parameter so the exact conversation can be restored.
  /// For now we route to the generic AI chat page.
  Future<void> openInConversation(
    BuildContext context,
    MemoryCandidate candidate,
  ) async {
    if (candidate.conversationId == null) return;
    await PapertokAiChatNavigator.show();
  }
}

class MemorySessionDigestResult {
  const MemorySessionDigestResult({
    required this.candidates,
    required this.dailyStrategy,
  });

  final List<MemoryCandidate> candidates;
  final MemoryWorkflowDailyStrategy dailyStrategy;

  bool get writesDailyDirectly => dailyStrategy.writesDailyDirectly;
}
