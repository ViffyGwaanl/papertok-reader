import 'package:anx_reader/service/memory/memory_rule_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('isEnabled defaults to true when unset', () async {
    await MemoryRulePrefs.init();
    expect(MemoryRulePrefs.isEnabled('session_digest'), isTrue);
    expect(MemoryRulePrefs.isEnabled('provider_switch'), isTrue);
    expect(MemoryRulePrefs.isEnabled('anything_else'), isTrue);
  });

  test('setEnabled false persists and readback', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await MemoryRulePrefs.init();
    await MemoryRulePrefs.setEnabled('session_digest', false);
    expect(MemoryRulePrefs.isEnabled('session_digest'), isFalse);
  });

  test('setEnabled true persists and readback', () async {
    SharedPreferences.setMockInitialValues(
      <String, Object>{'memoryRule.session_digest': false},
    );
    await MemoryRulePrefs.init();
    expect(MemoryRulePrefs.isEnabled('session_digest'), isFalse);
    await MemoryRulePrefs.setEnabled('session_digest', true);
    expect(MemoryRulePrefs.isEnabled('session_digest'), isTrue);
  });

  test('multiple rules are independent', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await MemoryRulePrefs.init();
    await MemoryRulePrefs.setEnabled('rule_a', false);
    await MemoryRulePrefs.setEnabled('rule_b', true);
    expect(MemoryRulePrefs.isEnabled('rule_a'), isFalse);
    expect(MemoryRulePrefs.isEnabled('rule_b'), isTrue);
  });
}
