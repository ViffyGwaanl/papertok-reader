import 'dart:io';

import 'package:anx_reader/service/ai/tools/memory_tools.dart';
import 'package:anx_reader/service/memory/markdown_memory_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('memory tools', () {
    test('memory_append supports date=YYYY-MM-DD for daily docs', () async {
      final temp = await Directory.systemTemp.createTemp('anx_mem_tools_test_');
      try {
        final store = MarkdownMemoryStore(rootDir: temp);
        final tool = MemoryAppendTool(store);

        await tool.run({
          'doc': 'daily',
          'date': '2026-02-25',
          'text': 'Hello',
        });

        final content = await store.read(
          longTerm: false,
          date: DateTime(2026, 2, 25),
        );

        expect(content, contains('Hello'));
      } finally {
        try {
          await temp.delete(recursive: true);
        } catch (_) {}
      }
    });
  });
}
