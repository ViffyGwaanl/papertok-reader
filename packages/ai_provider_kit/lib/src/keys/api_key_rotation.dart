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
      .split(RegExp(r'[\n,;，；]+'))
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
    final t = multi.trim();

    // Prefer structured JSON.
    if (t.startsWith('{') || t.startsWith('[')) {
      try {
        final decoded = jsonDecode(t);

        // 1) JSON array: either ["k1","k2"] or [{key,enabled}, ...]
        if (decoded is List) {
          final keys = <String>[];
          for (final item in decoded) {
            if (item is String) {
              final k = item.trim();
              if (k.isNotEmpty) keys.add(k);
              continue;
            }
            if (item is Map) {
              final map = item.cast<String, dynamic>();
              final enabled = map['enabled'];
              if (enabled == false) continue;
              final k = map['key']?.toString().trim() ?? '';
              if (k.isNotEmpty) keys.add(k);
            }
          }
          final uniq = keys.toSet().toList(growable: false);
          if (uniq.isNotEmpty) return uniq;
        }

        // 2) Wrapper object: { keys: [...] }
        if (decoded is Map) {
          final map = decoded.cast<String, dynamic>();
          final list = map['keys'];
          if (list is List) {
            final keys = <String>[];
            for (final item in list) {
              if (item is String) {
                final k = item.trim();
                if (k.isNotEmpty) keys.add(k);
                continue;
              }
              if (item is Map) {
                final m = item.cast<String, dynamic>();
                final enabled = m['enabled'];
                if (enabled == false) continue;
                final k = m['key']?.toString().trim() ?? '';
                if (k.isNotEmpty) keys.add(k);
              }
            }
            final uniq = keys.toSet().toList(growable: false);
            if (uniq.isNotEmpty) return uniq;
          }
        }
      } catch (_) {
        // Fall back.
      }
    }

    // Legacy delimiter-separated string.
    return parseApiKeysFromString(t);
  }
  return parseApiKeysFromString(raw['api_key'] ?? '');
}

/// In-memory round-robin selector (no secrets stored).
class ApiKeyRoundRobin {
  final Map<String, int> _nextIndexByProvider = <String, int>{};

  int startIndex(String providerId) {
    return _nextIndexByProvider[providerId] ?? 0;
  }

  void advance(String providerId, int nextIndex) {
    _nextIndexByProvider[providerId] = nextIndex;
  }
}

final apiKeyRoundRobin = ApiKeyRoundRobin();
