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

  test('parseApiKeysFromConfig supports structured api_keys list objects', () {
    final keys = parseApiKeysFromConfig({
      'api_keys':
          '[{"key":"k1","enabled":true},{"key":"k2","enabled":false},{"key":"k3"}]',
    });
    expect(keys, containsAll(['k1', 'k3']));
    expect(keys, isNot(contains('k2')));
  });

  test('parseApiKeysFromConfig supports wrapper {keys:[...] }', () {
    final keys = parseApiKeysFromConfig(
        {'api_keys': '{"keys":["k1",{"key":"k2","enabled":true}]}'});
    expect(keys, containsAll(['k1', 'k2']));
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
