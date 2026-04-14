import 'package:anx_reader/service/memory/memory_session_digest_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('session digest rationale mentions message count', () {
    final r = MemorySessionDigestService.buildRationale(
      messageCount: 8,
      triggerKind: 'session_digest',
      confidence: 0.7,
    );
    expect(r, contains('8'));
  });

  test('provider switch rationale mentions provider', () {
    final r = MemorySessionDigestService.buildRationale(
      messageCount: 2,
      triggerKind: 'provider_switch',
      confidence: 0.5,
    );
    expect(r.toLowerCase(), contains('provider'));
  });

  test('unknown trigger kind falls back to generic rationale', () {
    final r = MemorySessionDigestService.buildRationale(
      messageCount: 3,
      triggerKind: 'something_else',
      confidence: null,
    );
    expect(r.isNotEmpty, isTrue);
  });
}
