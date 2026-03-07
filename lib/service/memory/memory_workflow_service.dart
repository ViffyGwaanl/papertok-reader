import 'package:anx_reader/service/memory/markdown_memory_store.dart';
import 'package:anx_reader/service/memory/memory_candidate.dart';
import 'package:anx_reader/service/memory/memory_candidate_store.dart';
import 'package:anx_reader/service/memory/memory_write_coordinator.dart';
import 'package:uuid/uuid.dart';

class MemoryWorkflowService {
  MemoryWorkflowService({
    MarkdownMemoryStore? store,
    MemoryCandidateStore? candidateStore,
    MemoryWriteCoordinator? writeCoordinator,
  })  : _candidateStore =
            candidateStore ?? MemoryCandidateStore(rootDir: store?.rootDir),
        _writeCoordinator =
            writeCoordinator ?? MemoryWriteCoordinator(store: store);

  static const Uuid _uuid = Uuid();

  final MemoryCandidateStore _candidateStore;
  final MemoryWriteCoordinator _writeCoordinator;

  Future<List<MemoryCandidate>> listPendingCandidates() {
    return _candidateStore.list(status: MemoryCandidateStatus.pending);
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
        targetDoc: targetDoc, date: date, text: candidate.text);
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
