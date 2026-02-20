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
  });

  final String id;
  final String name;
  final String key;
  final bool enabled;
  final int createdAt;
  final int updatedAt;

  final int? lastTestAt;
  final bool? lastTestOk;
  final String? lastTestMessage;

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
            if (item is Map) {
              final entry = AiApiKeyEntry.fromJson(
                item.cast<String, dynamic>(),
              );
              if (entry.id.isNotEmpty && entry.key.trim().isNotEmpty) {
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
