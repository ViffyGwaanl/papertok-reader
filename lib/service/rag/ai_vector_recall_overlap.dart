import 'package:papertok_reader/service/rag/ai_vector_index.dart';
import 'package:sqflite/sqflite.dart';

class AiVectorRecallOverlapResult {
  const AiVectorRecallOverlapResult({
    required this.candidateChunkIds,
    required this.exactChunkIds,
    required this.overlapChunkIds,
    required this.missingExactChunkIds,
    required this.unexpectedCandidateChunkIds,
    required this.overlapRatio,
    required this.minOverlapRatio,
  });

  final List<int> candidateChunkIds;
  final List<int> exactChunkIds;
  final List<int> overlapChunkIds;
  final List<int> missingExactChunkIds;
  final List<int> unexpectedCandidateChunkIds;
  final double overlapRatio;
  final double minOverlapRatio;

  bool get isConclusive => exactChunkIds.isNotEmpty;
  bool get meetsThreshold => isConclusive && overlapRatio >= minOverlapRatio;
}

class AiVectorRecallOverlapGate {
  const AiVectorRecallOverlapGate({
    required AiVectorSearchBackend candidateBackend,
    AiVectorSearchBackend exactBackend = const AiExactVectorSearchBackend(),
    this.minOverlapRatio = 0.8,
  })  : _candidateBackend = candidateBackend,
        _exactBackend = exactBackend;

  final AiVectorSearchBackend _candidateBackend;
  final AiVectorSearchBackend _exactBackend;
  final double minOverlapRatio;

  Future<AiVectorRecallOverlapResult> compare(
    Database db, {
    required List<double> queryVector,
    required String providerId,
    required String embeddingModel,
    required int limit,
    bool onlyIndexed = true,
    int maxScanRows = 5000,
    int? bookId,
  }) async {
    final safeLimit = limit.clamp(1, 500);
    final candidateRows = await _candidateBackend.searchRows(
      db,
      queryVector: queryVector,
      providerId: providerId,
      embeddingModel: embeddingModel,
      limit: safeLimit,
      onlyIndexed: onlyIndexed,
      maxScanRows: maxScanRows,
      bookId: bookId,
    );
    final exactRows = await _exactBackend.searchRows(
      db,
      queryVector: queryVector,
      providerId: providerId,
      embeddingModel: embeddingModel,
      limit: safeLimit,
      onlyIndexed: onlyIndexed,
      maxScanRows: maxScanRows,
      bookId: bookId,
    );

    final candidateChunkIds = _chunkIds(candidateRows).take(safeLimit).toList();
    final exactChunkIds = _chunkIds(exactRows).take(safeLimit).toList();
    final candidateSet = candidateChunkIds.toSet();
    final exactSet = exactChunkIds.toSet();
    final overlapChunkIds =
        exactChunkIds.where(candidateSet.contains).toList(growable: false);
    final missingExactChunkIds = exactChunkIds
        .where((id) => !candidateSet.contains(id))
        .toList(growable: false);
    final unexpectedCandidateChunkIds = candidateChunkIds
        .where((id) => !exactSet.contains(id))
        .toList(growable: false);
    final overlapRatio = exactChunkIds.isEmpty
        ? 0.0
        : overlapChunkIds.length / exactChunkIds.length;

    return AiVectorRecallOverlapResult(
      candidateChunkIds: List.unmodifiable(candidateChunkIds),
      exactChunkIds: List.unmodifiable(exactChunkIds),
      overlapChunkIds: List.unmodifiable(overlapChunkIds),
      missingExactChunkIds: List.unmodifiable(missingExactChunkIds),
      unexpectedCandidateChunkIds:
          List.unmodifiable(unexpectedCandidateChunkIds),
      overlapRatio: overlapRatio,
      minOverlapRatio: minOverlapRatio,
    );
  }

  static Iterable<int> _chunkIds(List<Map<String, Object?>> rows) sync* {
    final seen = <int>{};
    for (final row in rows) {
      final chunkId = (row['chunk_id'] as num?)?.toInt();
      if (chunkId == null || !seen.add(chunkId)) continue;
      yield chunkId;
    }
  }
}
