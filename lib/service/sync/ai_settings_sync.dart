import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/ai_dock_side.dart';
import 'package:anx_reader/enums/ai_pad_panel_mode.dart';
import 'package:anx_reader/enums/ai_panel_position.dart';
import 'package:anx_reader/enums/ai_prompts.dart';
import 'package:anx_reader/enums/ai_tool_approval_policy.dart';
import 'package:anx_reader/models/ai_input_quick_prompt.dart';
import 'package:anx_reader/models/user_prompt.dart';
import 'package:anx_reader/models/mcp_server_meta.dart';
import 'package:anx_reader/service/ai/ai_services.dart';
import 'package:anx_reader/utils/log/common.dart';

const int aiSettingsSchemaVersion = 1;

/// Build a JSON-serializable AI settings snapshot for sync.
///
/// Security:
/// - MUST NOT include api keys.
Map<String, dynamic> buildLocalAiSettingsJson() {
  final prefs = Prefs();

  final services = <String, dynamic>{};
  for (final option in buildDefaultAiServices()) {
    final id = option.identifier;
    final stored = prefs.getAiConfig(id);
    if (stored.isEmpty) continue;

    // Remove secrets.
    final safe = Map<String, dynamic>.from(stored);
    safe.remove('api_key');
    safe.remove('api_keys');

    // Only keep non-empty values.
    safe.removeWhere((k, v) => v == null || v.toString().trim().isEmpty);
    if (safe.isEmpty) continue;

    services[id] = safe;
  }

  final prompts = <String, dynamic>{};
  for (final p in AiPrompts.values) {
    final current = prefs.getAiPrompt(p);
    final defaultPrompt = p.getPrompt();
    if (current != defaultPrompt) {
      prompts[p.name] = current;
    }
  }

  final ui = <String, dynamic>{
    'aiPadPanelMode': prefs.aiPadPanelMode.code,
    'aiDockSide': prefs.aiDockSide.code,
    'aiPanelPosition': prefs.aiPanelPosition.code,
    'aiPanelWidth': prefs.aiPanelWidth,
    'aiPanelHeight': prefs.aiPanelHeight,
    'aiSheetInitialSize': prefs.aiSheetInitialSize,
    'aiChatFontScale': prefs.aiChatFontScale,
    if (prefs.memorySemanticSearchEnabledOverride != null)
      'memorySemanticSearchEnabledV1':
          prefs.memorySemanticSearchEnabledOverride,

    // Memory search tuning (safe to sync).
    'memorySearchHybridEnabledV1': prefs.memorySearchHybridEnabled,
    'memorySearchHybridVectorWeightV1': prefs.memorySearchHybridVectorWeight,
    'memorySearchHybridTextWeightV1': prefs.memorySearchHybridTextWeight,
    'memorySearchHybridCandidateMultiplierV1':
        prefs.memorySearchHybridCandidateMultiplier,
    'memorySearchHybridMmrEnabledV1': prefs.memorySearchHybridMmrEnabled,
    'memorySearchHybridMmrLambdaV1': prefs.memorySearchHybridMmrLambda,
    'memorySearchHybridTemporalDecayEnabledV1':
        prefs.memorySearchTemporalDecayEnabled,
    'memorySearchHybridTemporalHalfLifeDaysV1':
        prefs.memorySearchTemporalDecayHalfLifeDays,
    'memoryEmbeddingCacheEnabledV1': prefs.memoryEmbeddingCacheEnabled,
    'memoryEmbeddingCacheMaxChunksV1': prefs.memoryEmbeddingCacheMaxChunks,
  };

  // Translation-only prefs (safe to sync; no secrets).
  final translate = <String, dynamic>{
    'aiTranslateProviderIdV1': prefs.aiTranslateProviderId,
    'aiTranslateModelV1': prefs.aiTranslateModel,
    'inlineFullTextTranslateConcurrency':
        prefs.inlineFullTextTranslateConcurrency,
  };

  final imageAnalysis = <String, dynamic>{
    'aiImageAnalysisProviderIdV1': prefs.aiImageAnalysisProviderId,
    'aiImageAnalysisModelV1': prefs.aiImageAnalysisModel,
    'aiImageAnalysisPromptV1': prefs.aiImageAnalysisPrompt,
  };

  // AI Indexing (library + current book) (non-secret, syncable)
  final libraryIndex = <String, dynamic>{
    'aiLibraryIndexFollowSelectedProviderV1':
        prefs.aiLibraryIndexFollowSelectedProvider,
    'aiLibraryIndexProviderIdV1': prefs.aiLibraryIndexProviderId,
    'aiLibraryIndexEmbeddingModelV1': prefs.aiLibraryIndexEmbeddingModel,
    'aiLibraryIndexChunkTargetCharsV1': prefs.aiLibraryIndexChunkTargetChars,
    'aiLibraryIndexChunkMaxCharsV1': prefs.aiLibraryIndexChunkMaxChars,
    'aiLibraryIndexChunkMinCharsV1': prefs.aiLibraryIndexChunkMinChars,
    'aiLibraryIndexChunkOverlapCharsV1': prefs.aiLibraryIndexChunkOverlapChars,
    'aiLibraryIndexMaxChapterCharsV1': prefs.aiLibraryIndexMaxChapterCharacters,
    'aiLibraryIndexEmbeddingBatchSizeV1':
        prefs.aiLibraryIndexEmbeddingBatchSize,
    'aiLibraryIndexEmbeddingsTimeoutSecV1':
        prefs.aiLibraryIndexEmbeddingsTimeoutSeconds,
  };

  final tools = <String, dynamic>{
    'enabledIds': prefs.enabledAiToolIds,
    'approvalPolicy': prefs.aiToolApprovalPolicy.code,
    'forceConfirmDestructive': prefs.aiToolForceConfirmDestructive,
    'shortcutsCallbackMaxCharsV1': prefs.shortcutsCallbackMaxCharsV1,
    'shortcutsCallbackTimeoutSecV1': prefs.shortcutsCallbackTimeoutSecV1,
    'shortcutsCallbackWaitModeV1': prefs.shortcutsCallbackWaitModeV1,
    'shortcutsResultKnownNamesV1': prefs.shortcutsResultKnownNamesV1,
  };

  final mcp = <String, dynamic>{
    'autoRefreshToolsV1': prefs.mcpAutoRefreshToolsV1,
    'servers':
        prefs.mcpServersV1.map((e) => e.toJson()).toList(growable: false),
  };

  return {
    'schemaVersion': aiSettingsSchemaVersion,
    'updatedAt': prefs.aiSettingsUpdatedAt,
    'selectedServiceId': prefs.selectedAiService,
    'services': services,
    'prompts': prompts,
    'userPrompts': prefs.userPrompts.map((e) => e.toJson()).toList(),
    'inputQuickPrompts':
        prefs.aiInputQuickPrompts.map((e) => e.toJson()).toList(),
    'tools': tools,
    'mcp': mcp,
    'ui': ui,
    'translate': translate,
    'imageAnalysis': imageAnalysis,
    'libraryIndex': libraryIndex,
  };
}

/// Apply an AI settings snapshot into local prefs.
///
/// Note: api keys are preserved from local storage.
void applyAiSettingsJson(Map<String, dynamic> json) {
  final prefs = Prefs();

  final schemaVersion = (json['schemaVersion'] as num?)?.toInt();
  if (schemaVersion != aiSettingsSchemaVersion) {
    AnxLog.info('ai_settings_sync: unsupported schemaVersion=$schemaVersion');
    return;
  }

  final updatedAt = (json['updatedAt'] as num?)?.toInt() ?? 0;

  try {
    final selectedServiceId = json['selectedServiceId'] as String?;
    if (selectedServiceId != null && selectedServiceId.trim().isNotEmpty) {
      prefs.selectedAiService = selectedServiceId;
    }

    final services = json['services'];
    if (services is Map) {
      for (final entry in services.entries) {
        final id = entry.key.toString();
        final remoteConfig = entry.value;
        if (remoteConfig is! Map) continue;

        final current = prefs.getAiConfig(id);
        final apiKey = current['api_key'];
        final apiKeys = current['api_keys'];

        final merged = <String, String>{};
        for (final e in remoteConfig.entries) {
          merged[e.key.toString()] = e.value?.toString() ?? '';
        }

        // Ensure api_key(s) remain local-only.
        if (apiKey != null && apiKey.trim().isNotEmpty) {
          merged['api_key'] = apiKey;
        }
        if (apiKeys != null && apiKeys.trim().isNotEmpty) {
          merged['api_keys'] = apiKeys;
        }

        prefs.saveAiConfig(id, merged);
      }
    }

    final prompts = json['prompts'];
    if (prompts is Map) {
      for (final entry in prompts.entries) {
        final key = entry.key.toString();
        final value = entry.value?.toString() ?? '';
        try {
          final p = AiPrompts.values.firstWhere((e) => e.name == key);
          if (value.trim().isNotEmpty) {
            prefs.saveAiPrompt(p, value);
          }
        } catch (_) {
          // ignore unknown prompt keys
        }
      }
    }

    final userPrompts = json['userPrompts'];
    if (userPrompts is List) {
      final list = <UserPrompt>[];
      for (final item in userPrompts) {
        if (item is Map<String, dynamic>) {
          list.add(UserPrompt.fromJson(item));
        } else if (item is Map) {
          list.add(UserPrompt.fromJson(item.cast<String, dynamic>()));
        }
      }
      prefs.userPrompts = list;
    }

    final quickPrompts = json['inputQuickPrompts'];
    if (quickPrompts is List) {
      final list = <AiInputQuickPrompt>[];
      for (final item in quickPrompts) {
        if (item is Map<String, dynamic>) {
          list.add(AiInputQuickPrompt.fromJson(item));
        } else if (item is Map) {
          list.add(AiInputQuickPrompt.fromJson(item.cast<String, dynamic>()));
        }
      }
      prefs.aiInputQuickPrompts = list;
    }

    final tools = json['tools'];
    if (tools is Map) {
      final enabled = tools['enabledIds'];
      if (enabled is List) {
        prefs.enabledAiToolIds =
            enabled.map((e) => e.toString()).toList(growable: false);
      }

      final policy = tools['approvalPolicy']?.toString();
      if (policy != null) {
        prefs.aiToolApprovalPolicy = AiToolApprovalPolicy.fromCode(policy);
      }

      final force = tools['forceConfirmDestructive'];
      if (force is bool) {
        prefs.aiToolForceConfirmDestructive = force;
      } else if (force is String) {
        final v = force.trim().toLowerCase();
        if (v == 'true' || v == 'false') {
          prefs.aiToolForceConfirmDestructive = v == 'true';
        }
      }

      final maxChars = tools['shortcutsCallbackMaxCharsV1'];
      if (maxChars is num) {
        prefs.shortcutsCallbackMaxCharsV1 = maxChars.toInt();
      } else if (maxChars is String) {
        final v = int.tryParse(maxChars.trim());
        if (v != null) {
          prefs.shortcutsCallbackMaxCharsV1 = v;
        }
      }

      final timeout = tools['shortcutsCallbackTimeoutSecV1'];
      if (timeout is num) {
        prefs.shortcutsCallbackTimeoutSecV1 = timeout.toInt();
      } else if (timeout is String) {
        final v = int.tryParse(timeout.trim());
        if (v != null) {
          prefs.shortcutsCallbackTimeoutSecV1 = v;
        }
      }

      final waitMode = tools['shortcutsCallbackWaitModeV1'];
      if (waitMode is String) {
        prefs.shortcutsCallbackWaitModeV1 = waitMode;
      }

      final known = tools['shortcutsResultKnownNamesV1'];
      if (known is List) {
        prefs.shortcutsResultKnownNamesV1 =
            known.map((e) => e.toString()).toList(growable: false);
      }
    }

    final mcp = json['mcp'];
    if (mcp is Map) {
      final autoRefresh = mcp['autoRefreshToolsV1'];
      if (autoRefresh is bool) {
        prefs.mcpAutoRefreshToolsV1 = autoRefresh;
      } else if (autoRefresh is String) {
        final v = autoRefresh.trim().toLowerCase();
        if (v == 'true' || v == 'false') {
          prefs.mcpAutoRefreshToolsV1 = v == 'true';
        }
      }

      final servers = mcp['servers'];
      if (servers is List) {
        final list = <McpServerMeta>[];
        for (final item in servers) {
          if (item is Map<String, dynamic>) {
            list.add(McpServerMeta.fromJson(item));
          } else if (item is Map) {
            list.add(McpServerMeta.fromJson(item.cast<String, dynamic>()));
          }
        }
        prefs.mcpServersV1 = list;
      }
    }

    final ui = json['ui'];
    if (ui is Map) {
      final memSemantic = ui['memorySemanticSearchEnabledV1'];
      if (memSemantic is bool) {
        prefs.memorySemanticSearchEnabledOverride = memSemantic;
      } else if (memSemantic is String) {
        final v = memSemantic.trim().toLowerCase();
        if (v == 'true' || v == 'false') {
          prefs.memorySemanticSearchEnabledOverride = v == 'true';
        }
      }

      final hybridEnabled = ui['memorySearchHybridEnabledV1'];
      if (hybridEnabled is bool) {
        prefs.memorySearchHybridEnabled = hybridEnabled;
      } else if (hybridEnabled is String) {
        final v = hybridEnabled.trim().toLowerCase();
        if (v == 'true' || v == 'false') {
          prefs.memorySearchHybridEnabled = v == 'true';
        }
      }

      final vW = (ui['memorySearchHybridVectorWeightV1'] as num?)?.toDouble();
      if (vW != null) {
        prefs.memorySearchHybridVectorWeight = vW;
      }

      final tW = (ui['memorySearchHybridTextWeightV1'] as num?)?.toDouble();
      if (tW != null) {
        prefs.memorySearchHybridTextWeight = tW;
      }

      final mult =
          (ui['memorySearchHybridCandidateMultiplierV1'] as num?)?.toInt();
      if (mult != null) {
        prefs.memorySearchHybridCandidateMultiplier = mult;
      }

      final mmrEnabled = ui['memorySearchHybridMmrEnabledV1'];
      if (mmrEnabled is bool) {
        prefs.memorySearchHybridMmrEnabled = mmrEnabled;
      } else if (mmrEnabled is String) {
        final v = mmrEnabled.trim().toLowerCase();
        if (v == 'true' || v == 'false') {
          prefs.memorySearchHybridMmrEnabled = v == 'true';
        }
      }

      final mmrLambda =
          (ui['memorySearchHybridMmrLambdaV1'] as num?)?.toDouble();
      if (mmrLambda != null) {
        prefs.memorySearchHybridMmrLambda = mmrLambda;
      }

      final decayEnabled = ui['memorySearchHybridTemporalDecayEnabledV1'];
      if (decayEnabled is bool) {
        prefs.memorySearchTemporalDecayEnabled = decayEnabled;
      } else if (decayEnabled is String) {
        final v = decayEnabled.trim().toLowerCase();
        if (v == 'true' || v == 'false') {
          prefs.memorySearchTemporalDecayEnabled = v == 'true';
        }
      }

      final halfLife =
          (ui['memorySearchHybridTemporalHalfLifeDaysV1'] as num?)?.toInt();
      if (halfLife != null) {
        prefs.memorySearchTemporalDecayHalfLifeDays = halfLife;
      }

      final cacheEnabled = ui['memoryEmbeddingCacheEnabledV1'];
      if (cacheEnabled is bool) {
        prefs.memoryEmbeddingCacheEnabled = cacheEnabled;
      } else if (cacheEnabled is String) {
        final v = cacheEnabled.trim().toLowerCase();
        if (v == 'true' || v == 'false') {
          prefs.memoryEmbeddingCacheEnabled = v == 'true';
        }
      }

      final cacheMax = (ui['memoryEmbeddingCacheMaxChunksV1'] as num?)?.toInt();
      if (cacheMax != null) {
        prefs.memoryEmbeddingCacheMaxChunks = cacheMax;
      }

      final mode = ui['aiPadPanelMode']?.toString();
      if (mode != null) {
        prefs.aiPadPanelMode = AiPadPanelModeEnum.fromCode(mode);
      }
      final side = ui['aiDockSide']?.toString();
      if (side != null) {
        prefs.aiDockSide = AiDockSideEnum.fromCode(side);
      }
      final position = ui['aiPanelPosition']?.toString();
      if (position != null) {
        prefs.aiPanelPosition = AiPanelPositionEnum.fromCode(position);
      }

      final w = (ui['aiPanelWidth'] as num?)?.toDouble();
      if (w != null) prefs.aiPanelWidth = w;
      final h = (ui['aiPanelHeight'] as num?)?.toDouble();
      if (h != null) prefs.aiPanelHeight = h;
      final sheet = (ui['aiSheetInitialSize'] as num?)?.toDouble();
      if (sheet != null) prefs.aiSheetInitialSize = sheet;
      final scale = (ui['aiChatFontScale'] as num?)?.toDouble();
      if (scale != null) prefs.aiChatFontScale = scale;
    }

    final translate = json['translate'];
    if (translate is Map) {
      final providerId = translate['aiTranslateProviderIdV1']?.toString();
      if (providerId != null) {
        prefs.aiTranslateProviderId = providerId;
      }

      final model = translate['aiTranslateModelV1']?.toString();
      if (model != null) {
        prefs.aiTranslateModel = model;
      }

      final concurrency =
          (translate['inlineFullTextTranslateConcurrency'] as num?)?.toInt();
      if (concurrency != null) {
        prefs.inlineFullTextTranslateConcurrency = concurrency;
      }
    }

    final imageAnalysis = json['imageAnalysis'];
    if (imageAnalysis is Map) {
      final providerId =
          imageAnalysis['aiImageAnalysisProviderIdV1']?.toString();
      if (providerId != null) {
        prefs.aiImageAnalysisProviderId = providerId;
      }

      final model = imageAnalysis['aiImageAnalysisModelV1']?.toString();
      if (model != null) {
        prefs.aiImageAnalysisModel = model;
      }

      final prompt = imageAnalysis['aiImageAnalysisPromptV1']?.toString();
      if (prompt != null) {
        prefs.aiImageAnalysisPrompt = prompt;
      }
    }

    final libraryIndex = json['libraryIndex'];
    if (libraryIndex is Map) {
      final follow = libraryIndex['aiLibraryIndexFollowSelectedProviderV1'];
      if (follow is bool) {
        prefs.aiLibraryIndexFollowSelectedProvider = follow;
      } else if (follow is String) {
        final v = follow.trim().toLowerCase();
        if (v == 'true' || v == 'false') {
          prefs.aiLibraryIndexFollowSelectedProvider = v == 'true';
        }
      }

      final providerId = libraryIndex['aiLibraryIndexProviderIdV1']?.toString();
      if (providerId != null) {
        prefs.aiLibraryIndexProviderId = providerId;
      }

      final model = libraryIndex['aiLibraryIndexEmbeddingModelV1']?.toString();
      if (model != null) {
        prefs.aiLibraryIndexEmbeddingModel = model;
      }

      final target =
          (libraryIndex['aiLibraryIndexChunkTargetCharsV1'] as num?)?.toInt();
      if (target != null) {
        prefs.aiLibraryIndexChunkTargetChars = target;
      }

      final maxChars =
          (libraryIndex['aiLibraryIndexChunkMaxCharsV1'] as num?)?.toInt();
      if (maxChars != null) {
        prefs.aiLibraryIndexChunkMaxChars = maxChars;
      }

      final minChars =
          (libraryIndex['aiLibraryIndexChunkMinCharsV1'] as num?)?.toInt();
      if (minChars != null) {
        prefs.aiLibraryIndexChunkMinChars = minChars;
      }

      final overlap =
          (libraryIndex['aiLibraryIndexChunkOverlapCharsV1'] as num?)?.toInt();
      if (overlap != null) {
        prefs.aiLibraryIndexChunkOverlapChars = overlap;
      }

      final maxChapter =
          (libraryIndex['aiLibraryIndexMaxChapterCharsV1'] as num?)?.toInt();
      if (maxChapter != null) {
        prefs.aiLibraryIndexMaxChapterCharacters = maxChapter;
      }

      final batch =
          (libraryIndex['aiLibraryIndexEmbeddingBatchSizeV1'] as num?)?.toInt();
      if (batch != null) {
        prefs.aiLibraryIndexEmbeddingBatchSize = batch;
      }

      final timeout =
          (libraryIndex['aiLibraryIndexEmbeddingsTimeoutSecV1'] as num?)
              ?.toInt();
      if (timeout != null) {
        prefs.aiLibraryIndexEmbeddingsTimeoutSeconds = timeout;
      }
    }
  } catch (e) {
    AnxLog.severe('ai_settings_sync: failed to apply: $e');
  } finally {
    // Ensure local timestamp matches remote snapshot (Phase 1 semantics).
    if (updatedAt > 0) {
      prefs.aiSettingsUpdatedAt = updatedAt;
    }
  }
}

Map<String, dynamic>? parseAiSettingsJsonString(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
  } catch (e) {
    AnxLog.info('ai_settings_sync: invalid json: $e');
  }
  return null;
}

String encodeAiSettingsJson(Map<String, dynamic> json) {
  return const JsonEncoder.withIndent('  ').convert(json);
}
