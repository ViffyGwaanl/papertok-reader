import 'dart:convert';

class SharePromptPreset {
  SharePromptPreset({
    required this.id,
    required this.title,
    required this.prompt,
    required this.enabled,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.isBuiltin = false,
  });

  final String id;
  final String title;
  final String prompt;
  final bool enabled;
  final int createdAtMs;
  final int updatedAtMs;
  final bool isBuiltin;

  SharePromptPreset copyWith({
    String? id,
    String? title,
    String? prompt,
    bool? enabled,
    int? createdAtMs,
    int? updatedAtMs,
    bool? isBuiltin,
  }) {
    return SharePromptPreset(
      id: id ?? this.id,
      title: title ?? this.title,
      prompt: prompt ?? this.prompt,
      enabled: enabled ?? this.enabled,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      isBuiltin: isBuiltin ?? this.isBuiltin,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'prompt': prompt,
        'enabled': enabled,
        'createdAtMs': createdAtMs,
        'updatedAtMs': updatedAtMs,
        'isBuiltin': isBuiltin,
      };

  static SharePromptPreset? fromJson(dynamic json) {
    if (json is! Map) return null;
    final map = json.cast<String, dynamic>();
    final id = (map['id'] ?? '').toString();
    if (id.trim().isEmpty) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
    return SharePromptPreset(
      id: id,
      title: (map['title'] ?? '').toString(),
      prompt: (map['prompt'] ?? '').toString(),
      enabled: (map['enabled'] is bool) ? map['enabled'] as bool : true,
      createdAtMs: (map['createdAtMs'] is num)
          ? (map['createdAtMs'] as num).toInt()
          : now,
      updatedAtMs: (map['updatedAtMs'] is num)
          ? (map['updatedAtMs'] as num).toInt()
          : now,
      isBuiltin: (map['isBuiltin'] is bool) ? map['isBuiltin'] as bool : false,
    );
  }
}

class SharePromptPresetsState {
  SharePromptPresetsState({
    required this.schemaVersion,
    required this.presets,
    required this.lastSelectedPresetId,
  });

  static const int currentSchemaVersion = 2;

  final int schemaVersion;
  final List<SharePromptPreset> presets;
  final String? lastSelectedPresetId;

  List<SharePromptPreset> get enabledPresets =>
      presets.where((p) => p.enabled).toList(growable: false);

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'lastSelectedPresetId': lastSelectedPresetId,
        'presets': presets.map((e) => e.toJson()).toList(),
      };

  String toJsonString() => jsonEncode(toJson());

  static SharePromptPresetsState empty() {
    return SharePromptPresetsState(
      schemaVersion: currentSchemaVersion,
      presets: const [],
      lastSelectedPresetId: null,
    );
  }

  static SharePromptPresetsState fromJsonString(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return empty();
      return fromJson(decoded);
    } catch (_) {
      return empty();
    }
  }

  static SharePromptPresetsState fromJson(Map json) {
    final map = json.cast<String, dynamic>();

    final schema = (map['schemaVersion'] is num)
        ? (map['schemaVersion'] as num).toInt()
        : 2;

    final presetsJson =
        (map['presets'] is List) ? map['presets'] as List : const [];

    final presets = <SharePromptPreset>[];
    for (final p in presetsJson) {
      final parsed = SharePromptPreset.fromJson(p);
      if (parsed != null) presets.add(parsed);
    }

    return SharePromptPresetsState(
      schemaVersion: schema,
      presets: presets,
      lastSelectedPresetId: map['lastSelectedPresetId']?.toString(),
    );
  }
}
