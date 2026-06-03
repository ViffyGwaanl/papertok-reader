import 'package:papertok_reader/service/rag/ai_global_index_builder.dart';
import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/ai_native_vector_index.dart';
import 'package:sqflite/sqflite.dart';

enum AiBookIndexLayerState {
  ready,
  missing,
  running,
  failed,
  unavailable,
  empty,
}

class AiBookIndexLayerReadiness {
  const AiBookIndexLayerReadiness({
    required this.state,
    this.count = 0,
    this.total = 0,
    this.reason,
    this.requiresBaseEmbeddingRepair = false,
  });

  final AiBookIndexLayerState state;
  final int count;
  final int total;
  final String? reason;
  final bool requiresBaseEmbeddingRepair;
}

class AiBookIndexReadiness {
  const AiBookIndexReadiness({
    required this.bookId,
    required this.baseIndex,
    required this.nativeVector,
    required this.annVector,
    required this.globalLayer,
    required this.graphLayer,
  });

  final int bookId;
  final AiBookIndexLayerReadiness baseIndex;
  final AiBookIndexLayerReadiness nativeVector;
  final AiBookIndexLayerReadiness annVector;
  final AiBookIndexLayerReadiness globalLayer;
  final AiBookIndexLayerReadiness graphLayer;

  bool get hasBaseIndex => baseIndex.state == AiBookIndexLayerState.ready;
  bool get canUpgradeNativeVector =>
      hasBaseIndex &&
      nativeVector.state == AiBookIndexLayerState.missing &&
      nativeVector.total > 0;
  bool get canBuildAnnVector =>
      hasBaseIndex &&
      nativeVector.state == AiBookIndexLayerState.ready &&
      annVector.state == AiBookIndexLayerState.missing &&
      annVector.total > 0;
  bool get canBuildGlobalLayer =>
      hasBaseIndex && globalLayer.state == AiBookIndexLayerState.missing;
  bool get canRepairBaseEmbeddings =>
      hasBaseIndex && nativeVector.requiresBaseEmbeddingRepair;
}

class AiBookIndexReadinessInspector {
  AiBookIndexReadinessInspector({
    AiIndexDatabase? database,
    AiVec1VectorIndexBuilder? annBuilder,
  })  : _database = database ?? AiIndexDatabase.instance,
        _annBuilder = annBuilder ?? const AiVec1VectorIndexBuilder();

  final AiIndexDatabase _database;
  final AiVec1VectorIndexBuilder _annBuilder;

  Future<AiBookIndexReadiness> inspectBook(int bookId) async {
    if (bookId <= 0) {
      return _missingBook(bookId);
    }

    final db = await _database.database;
    final row = await _loadBaseRow(db, bookId);
    if (row == null) {
      return _missingBook(bookId);
    }

    final metadataChunkCount = _readInt(row, 'chunk_count');
    final storedChunkCount = _readInt(row, 'stored_chunk_count');
    final status = (row['index_status']?.toString() ?? '').trim();
    final failedReason = (row['failed_reason']?.toString() ?? '').trim();
    final embeddingChunkCount = _readInt(row, 'embedding_chunk_count');
    final embeddingDimGroupCount = _readInt(row, 'embedding_dim_group_count');
    final embeddingMissingDimCount =
        _readInt(row, 'embedding_missing_dim_count');
    final nativeVectorRows = _readInt(row, 'native_vector_rows');

    final baseIndex = _baseReadiness(
      status: status,
      metadataChunkCount: metadataChunkCount,
      storedChunkCount: storedChunkCount,
      failedReason: failedReason,
    );
    final nativeVector = _nativeVectorReadiness(
      baseIndex: baseIndex,
      storedChunkCount: storedChunkCount,
      embeddingChunkCount: embeddingChunkCount,
      embeddingDimGroupCount: embeddingDimGroupCount,
      embeddingMissingDimCount: embeddingMissingDimCount,
      nativeVectorRows: nativeVectorRows,
    );
    final annVector = await _annVectorReadiness(
      db,
      bookId: bookId,
      nativeVector: nativeVector,
    );

    final globalStatus =
        await AiGlobalIndexBuilder(database: _database).getBookLayerStatus(
      bookId,
    );
    final globalLayer = _globalLayerReadiness(globalStatus);
    final graphLayer = _graphLayerReadiness(globalStatus, globalLayer);

    return AiBookIndexReadiness(
      bookId: bookId,
      baseIndex: baseIndex,
      nativeVector: nativeVector,
      annVector: annVector,
      globalLayer: globalLayer,
      graphLayer: graphLayer,
    );
  }

  Future<Map<String, Object?>?> _loadBaseRow(Database db, int bookId) async {
    final rows = await db.rawQuery(
      '''
SELECT
  b.book_id,
  COALESCE(b.chunk_count, 0) AS chunk_count,
  COALESCE(b.index_status, 'succeeded') AS index_status,
  b.failed_reason,
  COUNT(c.id) AS stored_chunk_count,
  COALESCE(SUM(CASE
    WHEN c.embedding_blob IS NOT NULL OR COALESCE(c.embedding_json, '') != ''
    THEN 1 ELSE 0
  END), 0) AS embedding_chunk_count,
  COUNT(DISTINCT CASE
    WHEN c.embedding_blob IS NOT NULL OR COALESCE(c.embedding_json, '') != ''
    THEN NULLIF(COALESCE(c.embedding_dim, 0), 0)
  END) AS embedding_dim_group_count,
  COALESCE(SUM(CASE
    WHEN (c.embedding_blob IS NOT NULL OR COALESCE(c.embedding_json, '') != '')
      AND COALESCE(c.embedding_dim, 0) <= 0
    THEN 1 ELSE 0
  END), 0) AS embedding_missing_dim_count,
  COALESCE(SUM(CASE
    WHEN v.chunk_id IS NOT NULL
      AND COALESCE(v.provider_id, '') = COALESCE(b.provider_id, '')
      AND COALESCE(v.embedding_model, '') = COALESCE(b.embedding_model, '')
      AND v.embedding_dim = COALESCE(c.embedding_dim, 0)
    THEN 1 ELSE 0
  END), 0) AS native_vector_rows
FROM ai_book_index b
LEFT JOIN ai_chunks c ON c.book_id = b.book_id
LEFT JOIN ai_vector_index_rows v ON v.chunk_id = c.id
WHERE b.book_id = ?
GROUP BY b.book_id
LIMIT 1
''',
      [bookId],
    );
    return rows.isEmpty ? null : rows.first;
  }

  AiBookIndexLayerReadiness _baseReadiness({
    required String status,
    required int metadataChunkCount,
    required int storedChunkCount,
    required String failedReason,
  }) {
    final normalized = status.isEmpty ? 'succeeded' : status;
    if (normalized == 'failed') {
      return AiBookIndexLayerReadiness(
        state: AiBookIndexLayerState.failed,
        count: storedChunkCount,
        reason: failedReason.isEmpty ? null : failedReason,
      );
    }
    if (normalized == 'running' ||
        normalized == 'queued' ||
        normalized == 'paused') {
      return AiBookIndexLayerReadiness(
        state: AiBookIndexLayerState.running,
        count: storedChunkCount,
        total: metadataChunkCount,
      );
    }
    if (storedChunkCount <= 0 || normalized == 'idle') {
      return AiBookIndexLayerReadiness(
        state: AiBookIndexLayerState.missing,
        count: storedChunkCount,
        total: metadataChunkCount,
        reason: metadataChunkCount > 0
            ? 'No indexed chunks are stored for this book.'
            : null,
      );
    }
    return AiBookIndexLayerReadiness(
      state: AiBookIndexLayerState.ready,
      count: storedChunkCount,
      total: metadataChunkCount,
    );
  }

  AiBookIndexLayerReadiness _nativeVectorReadiness({
    required AiBookIndexLayerReadiness baseIndex,
    required int storedChunkCount,
    required int embeddingChunkCount,
    required int embeddingDimGroupCount,
    required int embeddingMissingDimCount,
    required int nativeVectorRows,
  }) {
    if (baseIndex.state != AiBookIndexLayerState.ready) {
      return const AiBookIndexLayerReadiness(
        state: AiBookIndexLayerState.missing,
        reason: 'Base book index is not ready.',
      );
    }
    if (embeddingChunkCount <= 0) {
      return const AiBookIndexLayerReadiness(
        state: AiBookIndexLayerState.missing,
        reason: 'No chunk embeddings are available for vector upgrade.',
      );
    }
    if (embeddingChunkCount < storedChunkCount) {
      return AiBookIndexLayerReadiness(
        state: AiBookIndexLayerState.failed,
        count: nativeVectorRows,
        total: storedChunkCount,
        reason:
            '$embeddingChunkCount/$storedChunkCount chunk embeddings are available. Repair missing embeddings before vector upgrades.',
        requiresBaseEmbeddingRepair: true,
      );
    }
    if (embeddingMissingDimCount > 0) {
      return AiBookIndexLayerReadiness(
        state: AiBookIndexLayerState.failed,
        count: nativeVectorRows,
        total: embeddingChunkCount,
        reason:
            'Chunk embeddings are missing dimension metadata. Repair base embeddings before vector upgrades.',
        requiresBaseEmbeddingRepair: true,
      );
    }
    if (embeddingDimGroupCount > 1) {
      return AiBookIndexLayerReadiness(
        state: AiBookIndexLayerState.failed,
        count: nativeVectorRows,
        total: embeddingChunkCount,
        reason:
            'Mixed embedding dimensions require repairing base embeddings before vector upgrades.',
        requiresBaseEmbeddingRepair: true,
      );
    }
    if (nativeVectorRows >= embeddingChunkCount) {
      return AiBookIndexLayerReadiness(
        state: AiBookIndexLayerState.ready,
        count: nativeVectorRows,
        total: embeddingChunkCount,
      );
    }
    return AiBookIndexLayerReadiness(
      state: AiBookIndexLayerState.missing,
      count: nativeVectorRows,
      total: embeddingChunkCount,
      reason: '$nativeVectorRows/$embeddingChunkCount compact vectors ready.',
    );
  }

  Future<AiBookIndexLayerReadiness> _annVectorReadiness(
    Database db, {
    required int bookId,
    required AiBookIndexLayerReadiness nativeVector,
  }) async {
    if (nativeVector.state != AiBookIndexLayerState.ready) {
      return const AiBookIndexLayerReadiness(
        state: AiBookIndexLayerState.missing,
        reason: 'Native vector rows are required before ANN can be built.',
      );
    }

    final availability = await _annBuilder.inspectAvailability(db);
    if (!availability.available) {
      return AiBookIndexLayerReadiness(
        state: AiBookIndexLayerState.unavailable,
        reason: availability.lastError,
      );
    }

    final groups = await db.rawQuery(
      '''
SELECT provider_id, embedding_model, embedding_dim, COUNT(*) AS row_count
FROM ai_vector_index_rows
WHERE book_id = ?
GROUP BY provider_id, embedding_model, embedding_dim
ORDER BY provider_id, embedding_model, embedding_dim
''',
      [bookId],
    );
    if (groups.isEmpty) {
      return const AiBookIndexLayerReadiness(
        state: AiBookIndexLayerState.missing,
        reason: 'No book-scoped vector group can be used for ANN.',
      );
    }

    var readyTables = 0;
    var annRows = 0;
    var nativeRows = 0;
    String? lastError;
    for (final group in groups) {
      final providerId = group['provider_id']?.toString() ?? '';
      final embeddingModel = group['embedding_model']?.toString() ?? '';
      final embeddingDim = _readInt(group, 'embedding_dim');
      final rowCount = _readInt(group, 'row_count');
      nativeRows += rowCount;
      if (embeddingDim <= 0 || rowCount <= 0) continue;
      final tableName = AiVec1VectorIndexBuilder.tableNameForBook(
        providerId: providerId,
        embeddingModel: embeddingModel,
        embeddingDim: embeddingDim,
        bookId: bookId,
      );
      try {
        if (!await _tableExists(db, tableName)) continue;
        final tableRows = await db.rawQuery(
          'SELECT COUNT(*) AS row_count FROM $tableName',
        );
        final tableRowCount =
            tableRows.isEmpty ? 0 : _readInt(tableRows.first, 'row_count');
        annRows += tableRowCount;
        if (tableRowCount >= rowCount) {
          readyTables += 1;
        }
      } catch (e) {
        lastError = e.toString();
      }
    }

    if (readyTables >= groups.length && groups.isNotEmpty) {
      return AiBookIndexLayerReadiness(
        state: AiBookIndexLayerState.ready,
        count: annRows,
        total: nativeRows,
      );
    }
    return AiBookIndexLayerReadiness(
      state: AiBookIndexLayerState.missing,
      count: annRows,
      total: nativeRows,
      reason: lastError ?? '$readyTables/${groups.length} ANN sidecars ready.',
    );
  }

  AiBookIndexLayerReadiness _globalLayerReadiness(
    AiGlobalIndexBookLayerStatus? status,
  ) {
    if (status == null) {
      return const AiBookIndexLayerReadiness(
        state: AiBookIndexLayerState.missing,
      );
    }
    if (!status.hasGlobalLayer) {
      return AiBookIndexLayerReadiness(
        state: AiBookIndexLayerState.missing,
        count: status.raptorNodes,
        total: status.chunkCount,
      );
    }
    return AiBookIndexLayerReadiness(
      state: AiBookIndexLayerState.ready,
      count: status.raptorNodes,
      total: status.chunkCount,
    );
  }

  AiBookIndexLayerReadiness _graphLayerReadiness(
    AiGlobalIndexBookLayerStatus? status,
    AiBookIndexLayerReadiness globalLayer,
  ) {
    if (globalLayer.state != AiBookIndexLayerState.ready || status == null) {
      return const AiBookIndexLayerReadiness(
        state: AiBookIndexLayerState.missing,
        reason: 'Global summary layer is required before graph extraction.',
      );
    }
    if (status.graphNodes <= 0) {
      return AiBookIndexLayerReadiness(
        state: AiBookIndexLayerState.empty,
        count: 0,
        total: status.graphEdges,
        reason:
            'Global summary exists, but no displayable graph nodes were extracted.',
      );
    }
    return AiBookIndexLayerReadiness(
      state: AiBookIndexLayerState.ready,
      count: status.graphNodes,
      total: status.graphEdges,
    );
  }

  Future<bool> _tableExists(Database db, String tableName) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE name = ? LIMIT 1",
      [tableName],
    );
    return rows.isNotEmpty;
  }

  AiBookIndexReadiness _missingBook(int bookId) {
    const missing = AiBookIndexLayerReadiness(
      state: AiBookIndexLayerState.missing,
    );
    return AiBookIndexReadiness(
      bookId: bookId,
      baseIndex: missing,
      nativeVector: missing,
      annVector: missing,
      globalLayer: missing,
      graphLayer: missing,
    );
  }

  int _readInt(Map<String, Object?> row, String key) {
    return (row[key] as num?)?.toInt() ?? 0;
  }
}
