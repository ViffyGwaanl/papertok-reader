import 'dart:io';

import 'package:anx_reader/service/memory/markdown_memory_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MarkdownMemoryStore', () {
    test('dailyFileName formats local YYYY-MM-DD.md', () {
      final store = MarkdownMemoryStore(rootDir: Directory.systemTemp);
      final name = store.dailyFileName(DateTime(2026, 2, 25));
      expect(name, '2026-02-25.md');
    });

    test('append + read + replace work for daily and long-term', () async {
      final temp = await Directory.systemTemp.createTemp('anx_mem_store_test_');
      try {
        final store = MarkdownMemoryStore(rootDir: temp);

        await store.ensureInitialized();

        // Long-term
        await store.replace(longTerm: true, text: '# Hello');
        final lt1 = await store.read(longTerm: true);
        expect(lt1, '# Hello');

        await store.append(longTerm: true, text: '\nWorld');
        final lt2 = await store.read(longTerm: true);
        expect(lt2, contains('Hello'));
        expect(lt2, contains('World'));

        // Daily (explicit date)
        final date = DateTime(2026, 2, 25);
        await store.replace(longTerm: false, date: date, text: 'A');
        await store.append(longTerm: false, date: date, text: 'B');
        final daily = await store.read(longTerm: false, date: date);
        expect(daily, contains('A'));
        expect(daily, contains('B'));

        // Search finds hits
        final hits = await store.search('Hello', limit: 10);
        expect(hits.where((h) => (h['file'] as String) == 'MEMORY.md').length,
            greaterThanOrEqualTo(1));
      } finally {
        try {
          await temp.delete(recursive: true);
        } catch (_) {
          // ignore
        }
      }
    });
  });
}
