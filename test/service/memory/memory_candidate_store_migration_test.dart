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

  test('first write migrates v1 data into v2 and both are visible', () async {
    final v1File =
        File(p.join(tempRoot.path, '.workflow', 'review_inbox_v1.json'));
    v1File.createSync(recursive: true);
    v1File.writeAsStringSync(jsonEncode({
      'version': 1,
      'candidates': [
        {
          'id': 'legacy',
          'summary': 's',
          'text': 't',
          'targetDoc': 'daily',
          'createdAtMs': 1,
          'status': 'pending',
          'sourceType': 'session',
        }
      ],
    }));

    final store = MemoryCandidateStore(rootDir: tempRoot);
    await store.upsert(
      const MemoryCandidate(
        id: 'fresh',
        summary: 's',
        text: 't',
        targetDoc: MemoryDocTarget.daily,
        createdAtMs: 2,
        status: MemoryCandidateStatus.pending,
        sourceType: 'session',
      ),
    );

    // Both candidates visible through a fresh store.
    final store2 = MemoryCandidateStore(rootDir: tempRoot);
    final items = await store2.list();
    expect(items.map((c) => c.id), containsAll(['legacy', 'fresh']));

    // v2 file exists and contains both rows.
    final v2File =
        File(p.join(tempRoot.path, '.workflow', 'review_inbox_v2.json'));
    expect(v2File.existsSync(), isTrue);
    final decoded =
        jsonDecode(v2File.readAsStringSync()) as Map<String, dynamic>;
    expect((decoded['candidates'] as List).length, 2);

    // v1 file left untouched on disk.
    expect(v1File.existsSync(), isTrue);
  });

  test('dismiss on a legacy v1 candidate migrates and updates status', () async {
    final v1File =
        File(p.join(tempRoot.path, '.workflow', 'review_inbox_v1.json'));
    v1File.createSync(recursive: true);
    v1File.writeAsStringSync(jsonEncode({
      'version': 1,
      'candidates': [
        {
          'id': 'legacy-1',
          'summary': 's',
          'text': 't',
          'targetDoc': 'daily',
          'createdAtMs': 1,
          'status': 'pending',
          'sourceType': 'session',
        },
        {
          'id': 'legacy-2',
          'summary': 's',
          'text': 't',
          'targetDoc': 'daily',
          'createdAtMs': 2,
          'status': 'pending',
          'sourceType': 'session',
        },
      ],
    }));

    final store = MemoryCandidateStore(rootDir: tempRoot);
    await store.dismiss('legacy-1');

    final items = await store.list();
    expect(items.length, 2);
    final dismissed = items.firstWhere((c) => c.id == 'legacy-1');
    expect(dismissed.status, MemoryCandidateStatus.dismissed);
    final stillPending = items.firstWhere((c) => c.id == 'legacy-2');
    expect(stillPending.status, MemoryCandidateStatus.pending);
  });
}
