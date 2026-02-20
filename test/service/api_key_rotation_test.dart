import 'package:anx_reader/service/ai/api_key_rotation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseApiKeysFromString supports delimiters', () {
    expect(parseApiKeysFromString(''), isEmpty);
    expect(parseApiKeysFromString('  key1  '), ['key1']);
    expect(parseApiKeysFromString('key1,key2'), ['key1', 'key2']);
    expect(
        parseApiKeysFromString('key1; key2\nkey3'), ['key1', 'key2', 'key3']);
  });

  test('parseApiKeysFromString supports JSON array', () {
    expect(parseApiKeysFromString('["k1","k2"]'), ['k1', 'k2']);
  });

  test('ApiKeyRoundRobin stores per-provider indices', () {
    final rr = ApiKeyRoundRobin();

    expect(rr.startIndex('p1'), 0);
    rr.advance('p1', 2);
    expect(rr.startIndex('p1'), 2);

    // Different provider maintains separate index.
    expect(rr.startIndex('p2'), 0);
  });
}
