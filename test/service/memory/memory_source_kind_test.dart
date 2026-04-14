import 'package:papertok_reader/service/memory/memory_source_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MemorySourceKind', () {
    test('round-trip via string', () {
      for (final v in MemorySourceKind.values) {
        expect(MemorySourceKind.fromString(v.asString), equals(v));
      }
    });

    test('unknown string defaults to chat', () {
      expect(MemorySourceKind.fromString('wtf'), equals(MemorySourceKind.chat));
      expect(MemorySourceKind.fromString(null), equals(MemorySourceKind.chat));
    });
  });
}
