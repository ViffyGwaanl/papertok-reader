import 'package:papertok_reader/service/rag/ai_native_vector_index.dart';
import 'package:papertok_reader/service/rag/ai_vector_index.dart';
import 'package:sqflite/sqflite.dart';

class AiLocalVectorIndex {
  const AiLocalVectorIndex({
    AiVectorSearchBackend backend =
        const AiAnnThenNativeThenExactVectorSearchBackend(),
  }) : _backend = backend;

  final AiVectorSearchBackend _backend;

  Future<List<Map<String, Object?>>> searchRows(
    Database db, {
    required List<double> queryVector,
    required String providerId,
    required String embeddingModel,
    required int limit,
    bool onlyIndexed = true,
    int maxScanRows = 5000,
  }) async {
    return _backend.searchRows(
      db,
      queryVector: queryVector,
      providerId: providerId,
      embeddingModel: embeddingModel,
      limit: limit,
      onlyIndexed: onlyIndexed,
      maxScanRows: maxScanRows,
    );
  }
}
