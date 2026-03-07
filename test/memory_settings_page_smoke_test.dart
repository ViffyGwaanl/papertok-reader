import 'dart:io';

import 'package:anx_reader/page/settings_page/memory.dart';
import 'package:anx_reader/service/memory/markdown_memory_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Memory settings widgets compile', () async {
    final temp =
        await Directory.systemTemp.createTemp('anx_memory_widget_test_');
    addTearDown(() async {
      try {
        await temp.delete(recursive: true);
      } catch (_) {
        // Ignore temp cleanup failures.
      }
    });

    expect(const MemorySettingsPage(), isA<MemorySettingsPage>());
    expect(
      MemoryEditorPage(
        store: MarkdownMemoryStore(rootDir: temp),
        longTerm: true,
      ),
      isA<MemoryEditorPage>(),
    );
  });
}
