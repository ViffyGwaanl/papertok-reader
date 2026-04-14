// test/service/memory/markdown_memory_store_tags_test.dart
import 'dart:io';
import 'package:anx_reader/service/memory/markdown_memory_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('mms_tags_');
  });

  tearDown(() async {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('reads tags from front matter', () async {
    final f = File(p.join(tempRoot.path, '2026-04-14.md'));
    f.writeAsStringSync('---\ntags: [insight, biology]\n---\n# Note\nbody\n');
    final store = MarkdownMemoryStore(rootDir: tempRoot);
    final tags = await store.readEntryTags(f.path);
    expect(tags, ['insight', 'biology']);
  });

  test('returns empty list when no front matter', () async {
    final f = File(p.join(tempRoot.path, 'plain.md'));
    f.writeAsStringSync('# Just a note\nbody\n');
    final store = MarkdownMemoryStore(rootDir: tempRoot);
    final tags = await store.readEntryTags(f.path);
    expect(tags, isEmpty);
  });

  test('returns empty list when file missing', () async {
    final store = MarkdownMemoryStore(rootDir: tempRoot);
    final tags = await store.readEntryTags(p.join(tempRoot.path, 'nope.md'));
    expect(tags, isEmpty);
  });

  test('write creates front matter and preserves body', () async {
    final f = File(p.join(tempRoot.path, 'plain.md'));
    f.writeAsStringSync('# Just a note\nbody\n');
    final store = MarkdownMemoryStore(rootDir: tempRoot);
    await store.writeEntryTags(f.path, ['new']);
    final content = f.readAsStringSync();
    expect(content, startsWith('---\ntags: [new]\n---\n'));
    expect(content, contains('# Just a note'));
    expect(content, contains('body'));
  });

  test('write replaces existing front matter', () async {
    final f = File(p.join(tempRoot.path, 'has.md'));
    f.writeAsStringSync('---\ntags: [old]\n---\n# Note\nbody\n');
    final store = MarkdownMemoryStore(rootDir: tempRoot);
    await store.writeEntryTags(f.path, ['updated', 'second']);
    final content = f.readAsStringSync();
    expect(content, startsWith('---\ntags: [updated, second]\n---\n'));
    expect(content.contains('tags: [old]'), isFalse);
    expect(content, contains('# Note'));
  });

  test('write empty tag list strips any existing front matter', () async {
    final f = File(p.join(tempRoot.path, 'has.md'));
    f.writeAsStringSync('---\ntags: [old]\n---\n# Note\nbody\n');
    final store = MarkdownMemoryStore(rootDir: tempRoot);
    await store.writeEntryTags(f.path, const <String>[]);
    final content = f.readAsStringSync();
    // No front matter when tags are empty — keeps the file clean.
    expect(content.startsWith('---\n'), isFalse);
    expect(content, contains('# Note'));
    expect(content, contains('body'));
  });
}
