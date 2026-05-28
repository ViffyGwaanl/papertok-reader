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
  c.text,
  c.raw_text,
  c.context_text,
  c.embedding_blob,
  c.embedding_json,
  c.embedding_norm,
  b.embedding_model,
  b.provider_id
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

    final queryNorm = VectorMath.l2Norm(queryVector);
    final scored = <_ScoredVectorRow>[];
    for (final row in rows) {
      final vector = AiVectorCodec.decodeVector(
        blob: row['embedding_blob'],
        jsonText: row['embedding_json']?.toString(),
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

    return scored
        .take(safeLimit)
        .map((e) => Map<String, Object?>.from(e.row))
        .toList(growable: false);
  }
}

class _ScoredVectorRow {
  const _ScoredVectorRow({required this.score, required this.row});

  final double score;
  final Map<String, Object?> row;
}
