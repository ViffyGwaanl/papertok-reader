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

  test('ApiKeyRoundRobin picks keys in order per provider', () {
    final rr = ApiKeyRoundRobin();
    final keys = ['a', 'b', 'c'];

    expect(rr.pick(providerId: 'p1', keys: keys), 'a');
    expect(rr.pick(providerId: 'p1', keys: keys), 'b');
    expect(rr.pick(providerId: 'p1', keys: keys), 'c');
    expect(rr.pick(providerId: 'p1', keys: keys), 'a');

    // Different provider maintains separate index.
    expect(rr.pick(providerId: 'p2', keys: keys), 'a');
  });
}
