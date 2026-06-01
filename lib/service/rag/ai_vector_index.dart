import 'package:papertok_reader/service/rag/ai_vector_codec.dart';
import 'package:papertok_reader/service/rag/vector_math.dart';
import 'package:sqflite/sqflite.dart';

abstract interface class AiVectorSearchBackend {
  Future<List<Map<String, Object?>>> searchRows(
    Database db, {
    required List<double> queryVector,
    required String providerId,
    required String embeddingModel,
    required int limit,
    bool onlyIndexed = true,
    int maxScanRows = 5000,
  });
}

class AiExactVectorSearchBackend implements AiVectorSearchBackend {
  const AiExactVectorSearchBackend();

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
    if (queryVector.isEmpty) return const [];
    final safeLimit = limit.clamp(1, 500);
    final safeScanRows = maxScanRows.clamp(safeLimit, 20000);
    final indexedFilter = onlyIndexed
        ? "b.chunk_count > 0 AND COALESCE(b.index_status, 'succeeded') = 'succeeded'"
        : '1=1';

    final rows = await db.rawQuery(
      '''
SELECT
  c.id AS chunk_id,
  c.book_id,
  c.chapter_href,
  c.chapter_title,
  c.chunk_index,
  c.start_char,
  c.end_char,
  c.embedding_input_hash,
  c.context_version,
  c.context_created_at,
  c.embedding_blob,
  c.embedding_norm,
  b.embedding_model,
  b.provider_id,
  b.index_version
FROM ai_chunks c
JOIN ai_book_index b ON b.book_id = c.book_id
WHERE ($indexedFilter)
  AND COALESCE(b.provider_id, '') = ?
  AND COALESCE(b.embedding_model, '') = ?
ORDER BY c.id DESC
LIMIT ?
''',
      [providerId, embeddingModel, safeScanRows],
    );

    final jsonFallbackById = await _loadJsonFallbacksForRows(db, rows);
    final queryNorm = VectorMath.l2Norm(queryVector);
    final scored = <_ScoredVectorRow>[];
    for (final row in rows) {
      final chunkId = (row['chunk_id'] as num?)?.toInt();
      final vector = AiVectorCodec.decodeVector(
        blob: row['embedding_blob'],
        jsonText: chunkId == null ? null : jsonFallbackById[chunkId],
      );
      if (vector == null || vector.isEmpty) continue;
      final score = VectorMath.cosineSimilarity(
        queryVector,
        vector,
        aNorm: queryNorm,
        bNorm: (row['embedding_norm'] as num?)?.toDouble(),
      );
      scored.add(
        _ScoredVectorRow(
          score: score,
          row: {
            ...row,
            'local_vector_score': score,
          },
        ),
      );
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final aId = (a.row['chunk_id'] as num?)?.toInt() ?? 0;
      final bId = (b.row['chunk_id'] as num?)?.toInt() ?? 0;
      return bId.compareTo(aId);
    });

    final winners = scored
        .take(safeLimit)
        .where((e) => e.row['chunk_id'] is num)
        .toList(growable: false);
    if (winners.isEmpty) return const [];

    final hydratedRows = await _hydrateWinnerRows(
      db,
      winners.map((e) => (e.row['chunk_id'] as num).toInt()).toList(),
    );
    final hydratedById = <int, Map<String, Object?>>{
      for (final row in hydratedRows)
        if (row['chunk_id'] is num)
          (row['chunk_id'] as num).toInt(): Map<String, Object?>.from(row),
    };

    return [
      for (final winner in winners)
        if (hydratedById[(winner.row['chunk_id'] as num).toInt()] != null)
          {
            ...hydratedById[(winner.row['chunk_id'] as num).toInt()]!,
            'local_vector_score': winner.score,
          }
    ];
  }

  Future<Map<int, String>> _loadJsonFallbacksForRows(
    Database db,
    List<Map<String, Object?>> rows,
  ) async {
    final missingBlobIds = rows
        .where((row) => row['embedding_blob'] == null && row['chunk_id'] is num)
        .map((row) => (row['chunk_id'] as num).toInt())
        .toSet()
        .toList(growable: false);
    if (missingBlobIds.isEmpty) return const {};

    final placeholders = List.filled(missingBlobIds.length, '?').join(',');
    final fallbackRows = await db.rawQuery(
      '''
SELECT id AS chunk_id, embedding_json
FROM ai_chunks
WHERE id IN ($placeholders)
''',
      missingBlobIds,
    );
    return {
      for (final row in fallbackRows)
        if (row['chunk_id'] is num && row['embedding_json'] != null)
          (row['chunk_id'] as num).toInt(): row['embedding_json'].toString(),
    };
  }

  Future<List<Map<String, Object?>>> _hydrateWinnerRows(
    Database db,
    List<int> chunkIds,
  ) {
    final ids = chunkIds.toSet().toList(growable: false);
    final placeholders = List.filled(ids.length, '?').join(',');
    return db.rawQuery(
      '''
SELECT
  c.id AS chunk_id,
  c.book_id,
  c.chapter_href,
  c.chapter_title,
  c.chunk_index,
  c.start_char,
  c.end_char,
  c.text,
  c.raw_text,
  c.context_text,
  c.embedding_input_hash,
  c.context_version,
  c.context_created_at,
  c.embedding_blob,
  c.embedding_json,
  c.embedding_norm,
  b.embedding_model,
  b.provider_id,
  b.index_version
FROM ai_chunks c
JOIN ai_book_index b ON b.book_id = c.book_id
WHERE c.id IN ($placeholders)
''',
      ids,
    );
  }
}

class _ScoredVectorRow {
  const _ScoredVectorRow({required this.score, required this.row});

  final double score;
  final Map<String, Object?> row;
}
