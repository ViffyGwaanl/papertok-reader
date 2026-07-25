import 'dart:convert';

/// A single API key entry for an AI provider.
///
/// NOTE: This structure contains secrets and is LOCAL-ONLY:
/// - Must NOT be synced via WebDAV.
/// - Must NOT be included in plain backups.
class AiApiKeyEntry {
  const AiApiKeyEntry({
    required this.id,
    required this.name,
    required this.key,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
    this.lastTestAt,
    this.lastTestOk,
    this.lastTestMessage,
    this.lastUsedAt,
    this.lastSuccessAt,
    this.successCount,
    this.lastFailureAt,
    this.failureCount,
    this.consecutiveFailures,
    this.disabledUntil,
  });

  final String id;
  final String name;
  final String key;
  final bool enabled;
  final int createdAt;
  final int updatedAt;

  // Diagnostics
  final int? lastTestAt;
  final bool? lastTestOk;
  final String? lastTestMessage;

  // Runtime stats (local-only)
  final int? lastUsedAt;
  final int? lastSuccessAt;
  final int? successCount;

  final int? lastFailureAt;
  final int? failureCount;
  final int? consecutiveFailures;

  /// Cooldown timestamp (ms). When set and > now, this key is temporarily
  /// skipped by the rotation logic.
  final int? disabledUntil;

  String maskedKey() {
    final t = key.trim();
    if (t.isEmpty) return '';
    if (t.length <= 8) return '••••••••';
    return '${t.substring(0, 4)}••••${t.substring(t.length - 4)}';
  }

  AiApiKeyEntry copyWith({
    String? id,
    String? name,
    String? key,
    bool? enabled,
    int? createdAt,
    int? updatedAt,
    int? lastTestAt,
    bool? lastTestOk,
    String? lastTestMessage,
    int? lastUsedAt,
    int? lastSuccessAt,
    int? successCount,
    int? lastFailureAt,
    int? failureCount,
    int? consecutiveFailures,
    int? disabledUntil,
  }) {
    return AiApiKeyEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      key: key ?? this.key,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastTestAt: lastTestAt ?? this.lastTestAt,
      lastTestOk: lastTestOk ?? this.lastTestOk,
      lastTestMessage: lastTestMessage ?? this.lastTestMessage,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
      successCount: successCount ?? this.successCount,
      lastFailureAt: lastFailureAt ?? this.lastFailureAt,
      failureCount: failureCount ?? this.failureCount,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      disabledUntil: disabledUntil ?? this.disabledUntil,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'key': key,
      'enabled': enabled,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      if (lastTestAt != null) 'lastTestAt': lastTestAt,
      if (lastTestOk != null) 'lastTestOk': lastTestOk,
      if (lastTestMessage != null) 'lastTestMessage': lastTestMessage,
      if (lastUsedAt != null) 'lastUsedAt': lastUsedAt,
      if (lastSuccessAt != null) 'lastSuccessAt': lastSuccessAt,
      if (successCount != null) 'successCount': successCount,
      if (lastFailureAt != null) 'lastFailureAt': lastFailureAt,
      if (failureCount != null) 'failureCount': failureCount,
      if (consecutiveFailures != null)
        'consecutiveFailures': consecutiveFailures,
      if (disabledUntil != null) 'disabledUntil': disabledUntil,
    };
  }

  static AiApiKeyEntry fromJson(Map<String, dynamic> json) {
    return AiApiKeyEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      key: json['key']?.toString() ?? '',
      enabled: json['enabled'] == true,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      lastTestAt: (json['lastTestAt'] as num?)?.toInt(),
      lastTestOk: json['lastTestOk'] as bool?,
      lastTestMessage: json['lastTestMessage']?.toString(),
      lastUsedAt: (json['lastUsedAt'] as num?)?.toInt(),
      lastSuccessAt: (json['lastSuccessAt'] as num?)?.toInt(),
      successCount: (json['successCount'] as num?)?.toInt(),
      lastFailureAt: (json['lastFailureAt'] as num?)?.toInt(),
      failureCount: (json['failureCount'] as num?)?.toInt(),
      consecutiveFailures: (json['consecutiveFailures'] as num?)?.toInt(),
      disabledUntil: (json['disabledUntil'] as num?)?.toInt(),
    );
  }
}

/// Decode a list of [AiApiKeyEntry] from the raw aiConfig map.
///
/// Supports:
/// - `api_keys` as JSON array of entry objects
/// - `api_keys` as delimiter-separated string (legacy)
/// - fallback to `api_key`
List<AiApiKeyEntry> decodeAiApiKeyEntries(Map<String, String> raw) {
  final rawKeys = (raw['api_keys'] ?? '').trim();
  if (rawKeys.isNotEmpty) {
    // JSON array of entries.
    if (rawKeys.startsWith('[')) {
      try {
        final decoded = jsonDecode(rawKeys);
        if (decoded is List) {
          final entries = <AiApiKeyEntry>[];
          for (final item in decoded) {
            if (item is String) {
              final k = item.trim();
              if (k.isEmpty) continue;
              final now = DateTime.now().millisecondsSinceEpoch;
              entries.add(
                AiApiKeyEntry(
                  id: 'legacy_${entries.length}',
                  name: 'Key ${entries.length + 1}',
                  key: k,
                  enabled: true,
                  createdAt: now,
                  updatedAt: now,
                ),
              );
              continue;
            }
            if (item is Map) {
              final entry = AiApiKeyEntry.fromJson(
                item.cast<String, dynamic>(),
              );
              if (entry.key.trim().isNotEmpty) {
                entries.add(entry);
              }
            }
          }
          if (entries.isNotEmpty) return entries;
        }
      } catch (_) {
        // fallthrough
      }
    }

    // Legacy delimiter-separated string.
    final parts = rawKeys
        .replaceAll('\r', '\n')
        .split(RegExp(r'[\n,;，；]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (parts.isNotEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      return parts
          .toSet()
          .map(
            (k) => AiApiKeyEntry(
              id: 'legacy_$k',
              name: 'Key',
              key: k,
              enabled: true,
              createdAt: now,
              updatedAt: now,
            ),
          )
          .toList(growable: false);
    }
  }

  // Fallback: single api_key.
  final single = (raw['api_key'] ?? '').trim();
  if (single.isEmpty) return const [];

  final now = DateTime.now().millisecondsSinceEpoch;
  return [
    AiApiKeyEntry(
      id: 'legacy',
      name: 'Key 1',
      key: single,
      enabled: true,
      createdAt: now,
      updatedAt: now,
    ),
  ];
}

String encodeAiApiKeyEntries(List<AiApiKeyEntry> entries) {
  final list = entries.map((e) => e.toJson()).toList(growable: false);
  return jsonEncode(list);
}
