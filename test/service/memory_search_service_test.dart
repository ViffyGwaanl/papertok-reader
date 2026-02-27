import 'dart:io';

import 'package:anx_reader/service/memory/markdown_memory_store.dart';
import 'package:anx_reader/service/memory/memory_index_database.dart';
import 'package:anx_reader/service/memory/memory_search_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MemorySearchService', () {
    test('FTS search returns snippets and handles tokens like GLM-5', () async {
      sqfliteFfiInit();

      final temp = await Directory.systemTemp.createTemp('anx_mem_search_');
      try {
        final store = MarkdownMemoryStore(rootDir: temp);
        await store.ensureInitialized(ensureToday: false);

        await store.replace(longTerm: true, text: 'About GLM-5 and methods');
        await store.replace(
          longTerm: false,
          date: DateTime(2026, 2, 24),
          text: 'Older note about papers',
        );

        final indexDb = MemoryIndexDatabase(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        );

        final service = MemorySearchService(store: store, indexDb: indexDb);

        // Ensure the derived index is built so this test exercises the FTS/BM25
        // path (search() is non-blocking and may fallback on first run).
        await service.syncIndex();

        final hits = await service.search('GLM-5 方法', limit: 10);
        expect(hits, isNotEmpty);
        expect(hits.first['file'], anyOf('MEMORY.md', '2026-02-24.md'));

        final hits2 = await service.search('Older', limit: 10);
        expect(hits2.any((h) => h['file'] == '2026-02-24.md'), isTrue);

        await indexDb.close();
      } finally {
        try {
          await temp.delete(recursive: true);
        } catch (_) {}
      }
    });
  });
}
