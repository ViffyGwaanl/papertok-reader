import 'package:papertok_reader/service/memory/memory_candidate.dart';
import 'package:papertok_reader/service/memory/memory_source_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v2 round-trip preserves all new fields', () {
    final c = MemoryCandidate(
      id: 'id1',
      summary: 's',
      text: 't',
      targetDoc: MemoryDocTarget.daily,
      createdAtMs: 1000,
      status: MemoryCandidateStatus.pending,
      sourceType: 'session',
      // v2 fields
      bookId: 42,
      cfi: 'epubcfi(/6/4!/4/2)',
      chapter: 'Chapter 1',
      sourceKind: MemorySourceKind.reading,
      tags: const ['insight', 'biology'],
      rationale: 'Captured because the same question was raised twice.',
    );
    final json = c.toJson();
    final back = MemoryCandidate.fromJson(json);
    expect(back.bookId, equals(42));
    expect(back.cfi, equals('epubcfi(/6/4!/4/2)'));
    expect(back.chapter, equals('Chapter 1'));
    expect(back.sourceKind, equals(MemorySourceKind.reading));
    expect(back.tags, equals(['insight', 'biology']));
    expect(back.rationale, isNotNull);
  });

  test('v1 json without new fields deserializes with safe defaults', () {
    final v1Json = {
      'id': 'old',
      'summary': 's',
      'text': 't',
      'targetDoc': 'daily',
      'createdAtMs': 1000,
      'status': 'pending',
      'sourceType': 'session',
    };
    final back = MemoryCandidate.fromJson(v1Json);
    expect(back.bookId, isNull);
    expect(back.cfi, isNull);
    expect(back.chapter, isNull);
    expect(back.sourceKind, equals(MemorySourceKind.chat));
    expect(back.tags, isEmpty);
    expect(back.rationale, isNull);
  });
}
