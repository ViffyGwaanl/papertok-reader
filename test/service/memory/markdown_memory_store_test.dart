// test/service/memory/markdown_memory_store_test.dart
import 'dart:io';

import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('mms_browse_');
  });

  tearDown(() async {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('listLongTermEntries splits MEMORY.md by top-level headings', () async {
    final f = File(p.join(tempRoot.path, 'MEMORY.md'));
    await f.writeAsString('# Alpha\n\nbody a\nmore body a\n\n# Beta\n\nbody b\n');
    final store = MarkdownMemoryStore(rootDir: tempRoot);
    final list = await store.listLongTermEntries();
    expect(list.length, 2);
    expect(list.first.title, 'Alpha');
    expect(list.first.preview, contains('body a'));
    expect(list.last.title, 'Beta');
    expect(list.last.preview, contains('body b'));
  });

  test('listLongTermEntries returns empty list when MEMORY.md is absent', () async {
    final store = MarkdownMemoryStore(rootDir: tempRoot);
    final list = await store.listLongTermEntries();
    expect(list, isEmpty);
  });

  test('listLongTermEntries returns empty list when MEMORY.md has no H1 headings', () async {
    final f = File(p.join(tempRoot.path, 'MEMORY.md'));
    await f.writeAsString('Just a plain body\nwith no heading\n');
    final store = MarkdownMemoryStore(rootDir: tempRoot);
    final list = await store.listLongTermEntries();
    expect(list, isEmpty);
  });

  test('listRecentDailyNotes returns files sorted newest first and caps to count', () async {
    for (final date in [
      '2026-04-10',
      '2026-04-11',
      '2026-04-12',
      '2026-04-13',
      '2026-04-14',
    ]) {
      File(p.join(tempRoot.path, '$date.md'))
          .writeAsStringSync('content for $date');
    }
    final store = MarkdownMemoryStore(rootDir: tempRoot);
    final list = await store.listRecentDailyNotes(count: 3);
    expect(list.length, 3);
    expect(list[0].title, '2026-04-14');
    expect(list[1].title, '2026-04-13');
    expect(list[2].title, '2026-04-12');
  });

  test('listRecentDailyNotes ignores files that are not daily-format', () async {
    File(p.join(tempRoot.path, 'MEMORY.md')).writeAsStringSync('long term');
    File(p.join(tempRoot.path, 'notes.md')).writeAsStringSync('random');
    File(p.join(tempRoot.path, '2026-04-14.md'))
        .writeAsStringSync('valid daily');
    final store = MarkdownMemoryStore(rootDir: tempRoot);
    final list = await store.listRecentDailyNotes(count: 10);
    expect(list.length, 1);
    expect(list.first.title, '2026-04-14');
  });
}
