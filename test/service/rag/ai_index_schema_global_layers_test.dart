import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/ai_index_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  test('AiIndexDatabase creates RAPTOR and GraphRAG layer tables', () async {
    final db = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(db.close);

    final sqlite = await db.database;
    final tables = await sqlite.rawQuery(
      "SELECT name FROM sqlite_master WHERE type IN ('table', 'virtual')",
    );
    final names = tables.map((r) => r['name']).whereType<String>().toSet();

    expect(await sqlite.getVersion(), kAiIndexDbVersion);
    expect(names, contains('ai_raptor_nodes'));
    expect(names, contains('ai_raptor_node_chunks'));
    expect(names, contains('ai_graph_nodes'));
    expect(names, contains('ai_graph_edges'));
    expect(names, contains('ai_graph_node_chunks'));
    expect(names, contains('ai_graph_communities'));
    expect(names, contains('ai_graph_community_nodes'));

    final graphNodeIndexes =
        await sqlite.rawQuery("PRAGMA index_list('ai_graph_nodes')");
    final graphNodeIndexNames =
        graphNodeIndexes.map((r) => r['name']).whereType<String>().toSet();
    expect(graphNodeIndexNames, contains('idx_ai_graph_nodes_book_type_name'));

    final raptorIndexes =
        await sqlite.rawQuery("PRAGMA index_list('ai_raptor_nodes')");
    final raptorIndexNames =
        raptorIndexes.map((r) => r['name']).whereType<String>().toSet();
    expect(raptorIndexNames, contains('idx_ai_raptor_nodes_book_level'));
  });

  test('AiIndexDatabase creates native vector shadow index tables', () async {
    final db = AiIndexDatabase.forTesting(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(db.close);

    final sqlite = await db.database;
    final tables = await sqlite.rawQuery(
      "SELECT name FROM sqlite_master WHERE type IN ('table', 'virtual')",
    );
    final names = tables.map((r) => r['name']).whereType<String>().toSet();

    expect(await sqlite.getVersion(), kAiIndexDbVersion);
    expect(names, contains('ai_vector_index_rows'));
    expect(names, contains('ai_vector_index_meta'));

    final rowCols =
        await sqlite.rawQuery('PRAGMA table_info(ai_vector_index_rows)');
    final rowNames = rowCols.map((r) => r['name']).whereType<String>().toSet();
    expect(rowNames, contains('chunk_id'));
    expect(rowNames, contains('book_id'));
    expect(rowNames, contains('provider_id'));
    expect(rowNames, contains('embedding_model'));
    expect(rowNames, contains('embedding_dim'));
    expect(rowNames, contains('embedding_blob'));

    final rowIndexes =
        await sqlite.rawQuery("PRAGMA index_list('ai_vector_index_rows')");
    final rowIndexNames =
        rowIndexes.map((r) => r['name']).whereType<String>().toSet();
    expect(rowIndexNames, contains('idx_ai_vector_rows_model_dim'));
    expect(rowIndexNames, contains('idx_ai_vector_rows_book'));
  });
}
