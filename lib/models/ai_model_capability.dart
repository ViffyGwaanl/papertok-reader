import 'dart:convert';

class AiModelCapability {
  const AiModelCapability({
    required this.id,
    this.contextWindow,
    this.maxOutputTokens,
    this.supportsTools,
    this.supportsImages,
    this.supportsThinking,
  });

  final String id;
  final int? contextWindow;
  final int? maxOutputTokens;
  final bool? supportsTools;
  final bool? supportsImages;
  final bool? supportsThinking;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'contextWindow': contextWindow,
      'maxOutputTokens': maxOutputTokens,
      'supportsTools': supportsTools,
      'supportsImages': supportsImages,
      'supportsThinking': supportsThinking,
    };
  }

  factory AiModelCapability.fromJson(Map<String, dynamic> json) {
    return AiModelCapability(
      id: (json['id'] ?? '').toString().trim(),
      contextWindow: (json['contextWindow'] as num?)?.toInt(),
      maxOutputTokens: (json['maxOutputTokens'] as num?)?.toInt(),
      supportsTools: json['supportsTools'] as bool?,
      supportsImages: json['supportsImages'] as bool?,
      supportsThinking: json['supportsThinking'] as bool?,
    );
  }

  AiModelCapability copyWith({
    String? id,
    int? contextWindow,
    int? maxOutputTokens,
    bool? supportsTools,
    bool? supportsImages,
    bool? supportsThinking,
  }) {
    return AiModelCapability(
      id: id ?? this.id,
      contextWindow: contextWindow ?? this.contextWindow,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      supportsTools: supportsTools ?? this.supportsTools,
      supportsImages: supportsImages ?? this.supportsImages,
      supportsThinking: supportsThinking ?? this.supportsThinking,
    );
  }

  static List<AiModelCapability> decodeList(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }

    return decoded
        .whereType<Map>()
        .map((e) => AiModelCapability.fromJson(
              e.map((key, value) => MapEntry(key.toString(), value)),
            ))
        .where((e) => e.id.isNotEmpty)
        .toList(growable: false);
  }

  static String encodeList(List<AiModelCapability> models) {
    return jsonEncode(models.map((e) => e.toJson()).toList(growable: false));
  }
}
