import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/service/rag/ai_vector_index.dart';
import 'package:papertok_reader/service/rag/ai_vector_recall_overlap.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  test('passes when candidate backend covers required exact topK overlap',
      () async {
    final candidate = _StaticVectorBackend([
      _row(1),
      _row(2),
      _row(3),
      _row(4),
      _row(99),
    ]);
    final exact = _StaticVectorBackend([
      _row(1),
      _row(2),
      _row(3),
      _row(4),
      _row(5),
    ]);
    final gate = AiVectorRecallOverlapGate(
      candidateBackend: candidate,
      exactBackend: exact,
      minOverlapRatio: 0.8,
    );

    final result = await gate.compare(
      _NoopDatabase(),
      queryVector: const [1, 0],
      providerId: 'provider-a',
      embeddingModel: 'model-a',
      limit: 5,
      maxScanRows: 100,
    );

    expect(result.candidateChunkIds, [1, 2, 3, 4, 99]);
    expect(result.exactChunkIds, [1, 2, 3, 4, 5]);
    expect(result.overlapChunkIds, [1, 2, 3, 4]);
    expect(result.missingExactChunkIds, [5]);
    expect(result.overlapRatio, 0.8);
    expect(result.meetsThreshold, true);
    expect(candidate.calls.single.limit, 5);
    expect(exact.calls.single.maxScanRows, 100);
  });

  test('fails when candidate backend misses too many exact topK rows',
      () async {
    final gate = AiVectorRecallOverlapGate(
      candidateBackend: _StaticVectorBackend([
        _row(1),
        _row(2),
        _row(98),
        _row(99),
      ]),
      exactBackend: _StaticVectorBackend([
        _row(1),
        _row(2),
        _row(3),
        _row(4),
      ]),
      minOverlapRatio: 0.75,
    );

    final result = await gate.compare(
      _NoopDatabase(),
      queryVector: const [1, 0],
      providerId: 'provider-a',
      embeddingModel: 'model-a',
      limit: 4,
    );

    expect(result.overlapChunkIds, [1, 2]);
    expect(result.missingExactChunkIds, [3, 4]);
    expect(result.overlapRatio, 0.5);
    expect(result.meetsThreshold, false);
  });
}

Map<String, Object?> _row(int chunkId) => {
      'chunk_id': chunkId,
      'book_id': 1,
      'chapter_href': 'chapter-$chunkId.xhtml',
      'local_vector_score': 1.0 / chunkId,
    };

class _StaticVectorBackend implements AiVectorSearchBackend {
  _StaticVectorBackend(this.rows);

  final List<Map<String, Object?>> rows;
  final calls = <_VectorBackendCall>[];

  @override
  Future<List<Map<String, Object?>>> searchRows(
    Database db, {
    required List<double> queryVector,
    required String providerId,
    required String embeddingModel,
    required int limit,
    bool onlyIndexed = true,
    int maxScanRows = 5000,
  }) async {
    calls.add(
      _VectorBackendCall(
        limit: limit,
        onlyIndexed: onlyIndexed,
        maxScanRows: maxScanRows,
      ),
    );
    return rows.take(limit).toList(growable: false);
  }
}

class _VectorBackendCall {
  const _VectorBackendCall({
    required this.limit,
    required this.onlyIndexed,
    required this.maxScanRows,
  });

  final int limit;
  final bool onlyIndexed;
  final int maxScanRows;
}

class _NoopDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
