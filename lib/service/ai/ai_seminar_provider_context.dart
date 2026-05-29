import 'package:flutter/foundation.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/models/ai_model_capability.dart';
import 'package:papertok_reader/models/ai_provider_meta.dart';

enum AiSeminarCostStatus {
  unknown('unknown'),
  estimated('estimated');

  const AiSeminarCostStatus(this.asString);

  final String asString;

  static AiSeminarCostStatus fromString(String? value) {
    for (final status in AiSeminarCostStatus.values) {
      if (status.asString == value) return status;
    }
    return AiSeminarCostStatus.unknown;
  }
}

@immutable
class AiSeminarProviderDiagnostics {
  const AiSeminarProviderDiagnostics({
    required this.providerId,
    required this.providerName,
    required this.providerType,
    required this.modelId,
    required this.hasProviderConfig,
    required this.hasCapabilityCache,
    required this.seminarReady,
    this.contextWindow,
    this.maxOutputTokens,
    this.supportsTools,
    this.supportsImages,
    this.supportsThinking,
    this.supportsStreaming,
    this.costStatus = AiSeminarCostStatus.unknown,
    this.costUnknownReason,
    this.estimatedCostUsd,
    this.inputCostPerMillionTokens,
    this.outputCostPerMillionTokens,
    this.cacheReadCostPerMillionTokens,
    this.cacheWriteCostPerMillionTokens,
    this.costPriceSource,
    this.warnings = const <String>[],
  });

  final String providerId;
  final String providerName;
  final String providerType;
  final String modelId;
  final bool hasProviderConfig;
  final bool hasCapabilityCache;
  final bool seminarReady;
  final int? contextWindow;
  final int? maxOutputTokens;
  final bool? supportsTools;
  final bool? supportsImages;
  final bool? supportsThinking;
  final bool? supportsStreaming;
  final AiSeminarCostStatus costStatus;
  final String? costUnknownReason;
  final double? estimatedCostUsd;
  final double? inputCostPerMillionTokens;
  final double? outputCostPerMillionTokens;
  final double? cacheReadCostPerMillionTokens;
  final double? cacheWriteCostPerMillionTokens;
  final String? costPriceSource;
  final List<String> warnings;

  bool get hasPricingMetadata =>
      inputCostPerMillionTokens != null &&
      inputCostPerMillionTokens! > 0 &&
      outputCostPerMillionTokens != null &&
      outputCostPerMillionTokens! > 0;

  Map<String, dynamic> toJson() => {
        'providerId': providerId,
        'providerName': providerName,
        'providerType': providerType,
        'modelId': modelId,
        'hasProviderConfig': hasProviderConfig,
        'hasCapabilityCache': hasCapabilityCache,
        'seminarReady': seminarReady,
        if (contextWindow != null) 'contextWindow': contextWindow,
        if (maxOutputTokens != null) 'maxOutputTokens': maxOutputTokens,
        if (supportsTools != null) 'supportsTools': supportsTools,
        if (supportsImages != null) 'supportsImages': supportsImages,
        if (supportsThinking != null) 'supportsThinking': supportsThinking,
        if (supportsStreaming != null) 'supportsStreaming': supportsStreaming,
        'costStatus': costStatus.asString,
        if (costUnknownReason != null) 'costUnknownReason': costUnknownReason,
        if (estimatedCostUsd != null) 'estimatedCostUsd': estimatedCostUsd,
        if (inputCostPerMillionTokens != null)
          'inputCostPerMillionTokens': inputCostPerMillionTokens,
        if (outputCostPerMillionTokens != null)
          'outputCostPerMillionTokens': outputCostPerMillionTokens,
        if (cacheReadCostPerMillionTokens != null)
          'cacheReadCostPerMillionTokens': cacheReadCostPerMillionTokens,
        if (cacheWriteCostPerMillionTokens != null)
          'cacheWriteCostPerMillionTokens': cacheWriteCostPerMillionTokens,
        if (costPriceSource != null) 'costPriceSource': costPriceSource,
        'warnings': warnings,
      };

  factory AiSeminarProviderDiagnostics.fromJson(Map<String, dynamic> json) {
    final estimatedCost = (json['estimatedCostUsd'] as num?)?.toDouble();
    final inputCost = (json['inputCostPerMillionTokens'] as num?)?.toDouble();
    final outputCost = (json['outputCostPerMillionTokens'] as num?)?.toDouble();
    final hasPricing = inputCost != null &&
        inputCost > 0 &&
        outputCost != null &&
        outputCost > 0;
    final rawCostStatus =
        AiSeminarCostStatus.fromString(json['costStatus']?.toString());
    final costStatus = rawCostStatus == AiSeminarCostStatus.estimated &&
            estimatedCost == null &&
            !hasPricing
        ? AiSeminarCostStatus.unknown
        : rawCostStatus;
    final costUnknownReason = json['costUnknownReason']?.toString() ??
        (costStatus == AiSeminarCostStatus.unknown
            ? 'Provider pricing or Seminar usage metadata is unavailable.'
            : null);

    return AiSeminarProviderDiagnostics(
      providerId: (json['providerId'] ?? '').toString(),
      providerName: (json['providerName'] ?? '').toString(),
      providerType: (json['providerType'] ?? '').toString(),
      modelId: (json['modelId'] ?? '').toString(),
      hasProviderConfig: json['hasProviderConfig'] == true,
      hasCapabilityCache: json['hasCapabilityCache'] == true,
      seminarReady: json['seminarReady'] == true,
      contextWindow: (json['contextWindow'] as num?)?.toInt(),
      maxOutputTokens: (json['maxOutputTokens'] as num?)?.toInt(),
      supportsTools: json['supportsTools'] as bool?,
      supportsImages: json['supportsImages'] as bool?,
      supportsThinking: json['supportsThinking'] as bool?,
      supportsStreaming: json['supportsStreaming'] is bool
          ? json['supportsStreaming'] as bool
          : null,
      costStatus: costStatus,
      costUnknownReason: costUnknownReason,
      estimatedCostUsd: estimatedCost,
      inputCostPerMillionTokens: inputCost,
      outputCostPerMillionTokens: outputCost,
      cacheReadCostPerMillionTokens:
          (json['cacheReadCostPerMillionTokens'] as num?)?.toDouble(),
      cacheWriteCostPerMillionTokens:
          (json['cacheWriteCostPerMillionTokens'] as num?)?.toDouble(),
      costPriceSource: json['costPriceSource']?.toString(),
      warnings: (json['warnings'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList(growable: false) ??
          const <String>[],
    );
  }
}

class AiSeminarProviderContextService {
  const AiSeminarProviderContextService();

  static const int minimumComfortableContextWindow = 16000;

  AiSeminarProviderDiagnostics resolve() {
    final prefs = Prefs();
    final providerId = prefs.selectedAiService.trim().isEmpty
        ? 'openai'
        : prefs.selectedAiService.trim();
    final meta = prefs.getAiProviderMeta(providerId);
    final config = prefs.getAiConfig(providerId);
    final modelId = (config['model'] ?? '').trim();
    final cache = prefs.getAiModelCapabilitiesCacheV1(providerId);
    final capability = _findCapability(cache?.models, modelId);

    final warnings = <String>[];
    final providerEnabled = meta?.enabled ?? true;
    if (!providerEnabled) {
      warnings.add('Selected provider is disabled.');
    }
    if (modelId.isEmpty) {
      warnings.add('Selected provider has no model configured.');
    }
    if (cache == null || capability == null) {
      warnings.add('Model capability cache is missing.');
    }
    final contextWindow = capability?.contextWindow;
    final contextTooSmall = contextWindow != null &&
        contextWindow < minimumComfortableContextWindow;
    if (contextTooSmall) {
      warnings.add(
        'Context window is below the recommended Seminar threshold.',
      );
    }

    final hasProviderConfig = config.isNotEmpty && modelId.isNotEmpty;
    final seminarReady =
        providerEnabled && hasProviderConfig && !contextTooSmall;
    final hasPricing = capability?.hasPricingMetadata == true;
    const costUnknownReason =
        'Provider pricing metadata is unavailable; Seminar token usage cannot estimate cost yet.';

    return AiSeminarProviderDiagnostics(
      providerId: providerId,
      providerName:
          meta?.name.trim().isNotEmpty == true ? meta!.name.trim() : providerId,
      providerType:
          meta == null ? 'unknown' : aiProviderTypeToString(meta.type),
      modelId: modelId,
      hasProviderConfig: hasProviderConfig,
      hasCapabilityCache: capability != null,
      seminarReady: seminarReady,
      contextWindow: capability?.contextWindow,
      maxOutputTokens: capability?.maxOutputTokens,
      supportsTools: capability?.supportsTools,
      supportsImages: capability?.supportsImages,
      supportsThinking: capability?.supportsThinking,
      costStatus: hasPricing
          ? AiSeminarCostStatus.estimated
          : AiSeminarCostStatus.unknown,
      costUnknownReason: hasPricing ? null : costUnknownReason,
      inputCostPerMillionTokens: capability?.inputCostPerMillionTokens,
      outputCostPerMillionTokens: capability?.outputCostPerMillionTokens,
      cacheReadCostPerMillionTokens: capability?.cacheReadCostPerMillionTokens,
      cacheWriteCostPerMillionTokens:
          capability?.cacheWriteCostPerMillionTokens,
      costPriceSource: capability?.pricingSource,
      warnings: List.unmodifiable(warnings),
    );
  }

  AiModelCapability? _findCapability(
    List<AiModelCapability>? models,
    String modelId,
  ) {
    if (models == null || modelId.trim().isEmpty) return null;
    for (final model in models) {
      if (model.id == modelId) return model;
    }
    return null;
  }
}
