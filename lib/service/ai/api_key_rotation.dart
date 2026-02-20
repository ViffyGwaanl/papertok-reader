import 'dart:convert';

/// Parse API keys from a single string.
///
/// Supported formats:
/// - JSON array: ["key1","key2"]
/// - Delimiters: comma `,`, semicolon `;`, newline `\n`
///
/// Returns trimmed, non-empty keys.
List<String> parseApiKeysFromString(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return const [];

  // JSON array support.
  if (t.startsWith('[')) {
    try {
      final decoded = jsonDecode(t);
      if (decoded is List) {
        final keys = decoded
            .map((e) => e?.toString().trim() ?? '')
            .where((e) => e.isNotEmpty)
            .toList(growable: false);
        if (keys.isNotEmpty) return keys;
      }
    } catch (_) {
      // Fall through to delimiter parsing.
    }
  }

  final parts = t
      .replaceAll('\r', '\n')
      .split(RegExp(r'[\n,;]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);

  return parts;
}

/// Parse API keys from the provider raw config.
///
/// - Prefer `api_keys` if present.
/// - Fall back to `api_key`.
List<String> parseApiKeysFromConfig(Map<String, String> raw) {
  final multi = raw['api_keys'];
  if (multi != null && multi.trim().isNotEmpty) {
    return parseApiKeysFromString(multi);
  }
  return parseApiKeysFromString(raw['api_key'] ?? '');
}

/// In-memory round-robin selector (no secrets stored).
class ApiKeyRoundRobin {
  final Map<String, int> _nextIndexByProvider = <String, int>{};

  String pick({required String providerId, required List<String> keys}) {
    if (keys.isEmpty) return '';
    if (keys.length == 1) return keys.first;

    final current = _nextIndexByProvider[providerId] ?? 0;
    final idx = current % keys.length;
    _nextIndexByProvider[providerId] = current + 1;
    return keys[idx];
  }
}

final apiKeyRoundRobin = ApiKeyRoundRobin();
