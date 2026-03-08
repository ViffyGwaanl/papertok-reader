import 'package:anx_reader/service/memory/markdown_memory_store.dart';
import 'package:anx_reader/service/memory/memory_candidate.dart';
import 'package:anx_reader/service/memory/memory_candidate_store.dart';
import 'package:anx_reader/service/memory/memory_session_digest_service.dart';
import 'package:anx_reader/service/memory/memory_workflow_policy.dart';
import 'package:anx_reader/service/memory/memory_write_coordinator.dart';
import 'package:uuid/uuid.dart';
import 'package:langchain_core/chat_models.dart';

class MemoryWorkflowService {
  MemoryWorkflowService({
    MarkdownMemoryStore? store,
    MemoryCandidateStore? candidateStore,
    MemoryWriteCoordinator? writeCoordinator,
    MemorySessionDigestService? sessionDigestService,
  })  : _candidateStore =
            candidateStore ?? MemoryCandidateStore(rootDir: store?.rootDir),
        _writeCoordinator =
            writeCoordinator ?? MemoryWriteCoordinator(store: store),
        _sessionDigestService =
            sessionDigestService ?? const MemorySessionDigestService();

  static const Uuid _uuid = Uuid();

  final MemoryCandidateStore _candidateStore;
  final MemoryWriteCoordinator _writeCoordinator;
  final MemorySessionDigestService _sessionDigestService;

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
    );
    return _candidateStore.upsert(candidate);
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
  }) async {
    final drafts = _sessionDigestService.buildCandidates(
      messages,
      maxCandidates: maxCandidates,
    );

    final created = <MemoryCandidate>[];
    for (final draft in drafts) {
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
