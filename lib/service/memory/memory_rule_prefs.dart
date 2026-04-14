import 'package:shared_preferences/shared_preferences.dart';

/// Per-rule enabled flags for auto-capture rules in the Memory workflow.
///
/// Each rule id (`session_digest`, `provider_switch`, ...) maps to a
/// boolean pref at `memoryRule.<ruleId>`. Defaults to true when unset.
///
/// Static access so UI rows and the workflow service can read/write
/// without plumbing a DI container.
class MemoryRulePrefs {
  MemoryRulePrefs._();

  static late SharedPreferences _prefs;
  static bool _initialized = false;
  static const String _prefix = 'memoryRule.';

  /// Must be called once at app startup before any read/write.
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
  }

  /// Returns the enabled flag for [ruleId], defaulting to `true` when
  /// the key is missing (new rules ship on by default).
  static bool isEnabled(String ruleId) {
    if (!_initialized) return true;
    return _prefs.getBool('$_prefix$ruleId') ?? true;
  }

  /// Persists the enabled flag for [ruleId].
  static Future<void> setEnabled(String ruleId, bool value) async {
    if (!_initialized) return;
    await _prefs.setBool('$_prefix$ruleId', value);
  }
}
