import 'dart:convert';

class AiModelCapability {
  const AiModelCapability({
    required this.id,
    this.contextWindow,
    this.maxOutputTokens,
    this.supportsTools,
    this.supportsImages,
    this.supportsThinking,
    this.inputCostPerMillionTokens,
    this.outputCostPerMillionTokens,
    this.cacheReadCostPerMillionTokens,
    this.cacheWriteCostPerMillionTokens,
    this.pricingSource,
  });

  final String id;
  final int? contextWindow;
  final int? maxOutputTokens;
  final bool? supportsTools;
  final bool? supportsImages;
  final bool? supportsThinking;
  final double? inputCostPerMillionTokens;
  final double? outputCostPerMillionTokens;
  final double? cacheReadCostPerMillionTokens;
  final double? cacheWriteCostPerMillionTokens;
  final String? pricingSource;

  bool get hasPricingMetadata =>
      inputCostPerMillionTokens != null &&
      inputCostPerMillionTokens! > 0 &&
      outputCostPerMillionTokens != null &&
      outputCostPerMillionTokens! > 0;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'contextWindow': contextWindow,
      'maxOutputTokens': maxOutputTokens,
      'supportsTools': supportsTools,
      'supportsImages': supportsImages,
      'supportsThinking': supportsThinking,
      'inputCostPerMillionTokens': inputCostPerMillionTokens,
      'outputCostPerMillionTokens': outputCostPerMillionTokens,
      'cacheReadCostPerMillionTokens': cacheReadCostPerMillionTokens,
      'cacheWriteCostPerMillionTokens': cacheWriteCostPerMillionTokens,
      'pricingSource': pricingSource,
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
      inputCostPerMillionTokens:
          _positiveDouble(json['inputCostPerMillionTokens']),
      outputCostPerMillionTokens:
          _positiveDouble(json['outputCostPerMillionTokens']),
      cacheReadCostPerMillionTokens:
          _nonNegativeDouble(json['cacheReadCostPerMillionTokens']),
      cacheWriteCostPerMillionTokens:
          _nonNegativeDouble(json['cacheWriteCostPerMillionTokens']),
      pricingSource: _trimmedOrNull(json['pricingSource']),
    );
  }

  AiModelCapability copyWith({
    String? id,
    int? contextWindow,
    int? maxOutputTokens,
    bool? supportsTools,
    bool? supportsImages,
    bool? supportsThinking,
    double? inputCostPerMillionTokens,
    double? outputCostPerMillionTokens,
    double? cacheReadCostPerMillionTokens,
    double? cacheWriteCostPerMillionTokens,
    String? pricingSource,
  }) {
    return AiModelCapability(
      id: id ?? this.id,
      contextWindow: contextWindow ?? this.contextWindow,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      supportsTools: supportsTools ?? this.supportsTools,
      supportsImages: supportsImages ?? this.supportsImages,
      supportsThinking: supportsThinking ?? this.supportsThinking,
      inputCostPerMillionTokens:
          inputCostPerMillionTokens ?? this.inputCostPerMillionTokens,
      outputCostPerMillionTokens:
          outputCostPerMillionTokens ?? this.outputCostPerMillionTokens,
      cacheReadCostPerMillionTokens:
          cacheReadCostPerMillionTokens ?? this.cacheReadCostPerMillionTokens,
      cacheWriteCostPerMillionTokens:
          cacheWriteCostPerMillionTokens ?? this.cacheWriteCostPerMillionTokens,
      pricingSource: pricingSource ?? this.pricingSource,
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

  static double? _positiveDouble(Object? value) {
    final parsed = (value as num?)?.toDouble();
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  static double? _nonNegativeDouble(Object? value) {
    final parsed = (value as num?)?.toDouble();
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }

  static String? _trimmedOrNull(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }
}
