import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/service/memory/memory_candidate.dart';
import 'package:anx_reader/service/memory/memory_candidate_store.dart';
import 'package:anx_reader/service/memory/memory_source_kind.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('mcs_migration_');
  });

  tearDown(() async {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('reads legacy v1 JSON and synthesizes v2 defaults', () async {
    final v1Payload = {
      'version': 1,
      'candidates': [
        {
          'id': 'old-one',
          'summary': 's',
          'text': 't',
          'targetDoc': 'daily',
          'createdAtMs': 1000,
          'status': 'pending',
          'sourceType': 'session',
        }
      ],
    };
    final v1File =
        File(p.join(tempRoot.path, '.workflow', 'review_inbox_v1.json'));
    v1File.createSync(recursive: true);
    v1File.writeAsStringSync(jsonEncode(v1Payload));

    final store = MemoryCandidateStore(rootDir: tempRoot);
    final items = await store.list();
    expect(items.length, 1);
    expect(items.first.id, 'old-one');
    expect(items.first.sourceKind, MemorySourceKind.chat);
    expect(items.first.tags, isEmpty);
    expect(items.first.bookId, isNull);
  });

  test('first write creates review_inbox_v2.json with version 2', () async {
    final store = MemoryCandidateStore(rootDir: tempRoot);
    await store.upsert(
      const MemoryCandidate(
        id: 'brand-new',
        summary: 's',
        text: 't',
        targetDoc: MemoryDocTarget.daily,
        createdAtMs: 1000,
        status: MemoryCandidateStatus.pending,
        sourceType: 'reading_session',
        bookId: 7,
        cfi: 'epubcfi(/6/4)',
        chapter: 'Ch1',
        sourceKind: MemorySourceKind.reading,
      ),
    );

    final v2File =
        File(p.join(tempRoot.path, '.workflow', 'review_inbox_v2.json'));
    expect(v2File.existsSync(), isTrue,
        reason: 'writes should land in v2 file');

    final decoded = jsonDecode(v2File.readAsStringSync())
        as Map<String, dynamic>;
    expect(decoded['version'], 2);
    final candidates = decoded['candidates'] as List;
    expect(candidates, hasLength(1));
    expect(
      (candidates.first as Map)['sourceKind'],
      'reading',
    );
  });

  test('v2 takes precedence when both files exist', () async {
    // Put a stale v1 row that should be ignored once v2 exists.
    final v1File =
        File(p.join(tempRoot.path, '.workflow', 'review_inbox_v1.json'));
    v1File.createSync(recursive: true);
    v1File.writeAsStringSync(jsonEncode({
      'version': 1,
      'candidates': [
        {
          'id': 'stale-v1',
          'summary': 's',
          'text': 't',
          'targetDoc': 'daily',
          'createdAtMs': 1,
          'status': 'pending',
          'sourceType': 'session',
        }
      ],
    }));

    // Write a fresh v2 via the store.
    final store = MemoryCandidateStore(rootDir: tempRoot);
    await store.upsert(
      const MemoryCandidate(
        id: 'fresh-v2',
        summary: 's',
        text: 't',
        targetDoc: MemoryDocTarget.daily,
        createdAtMs: 2,
        status: MemoryCandidateStatus.pending,
        sourceType: 'session',
      ),
    );

    final store2 = MemoryCandidateStore(rootDir: tempRoot);
    final items = await store2.list();
    expect(items.map((c) => c.id), ['fresh-v2']);
  });
}
