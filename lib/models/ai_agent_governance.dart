import 'package:flutter/foundation.dart';

enum AiAgentScene {
  reading('reading'),
  library('library'),
  global('global'),
  system('system'),
  seminar('seminar'),
  review('review');

  const AiAgentScene(this.asString);

  final String asString;

  static AiAgentScene fromString(String? value) {
    return tryParse(value) ?? AiAgentScene.global;
  }

  static AiAgentScene? tryParse(String? value) {
    for (final scene in AiAgentScene.values) {
      if (scene.asString == value) return scene;
    }
    return null;
  }
}

@immutable
class AiToolPermissionRule {
  const AiToolPermissionRule({
    required this.toolId,
    required this.scenes,
    this.requiresApproval = false,
    this.readOnly = true,
    this.allowsExternalNetwork = false,
    this.concurrencySafe = true,
  });

  final String toolId;
  final Set<AiAgentScene> scenes;
  final bool requiresApproval;
  final bool readOnly;
  final bool allowsExternalNetwork;
  final bool concurrencySafe;

  bool allows(AiAgentScene scene) => scenes.contains(scene);

  Map<String, dynamic> toJson() => {
        'toolId': toolId,
        'scenes': scenes.map((scene) => scene.asString).toList(growable: false),
        'requiresApproval': requiresApproval,
        'readOnly': readOnly,
        'allowsExternalNetwork': allowsExternalNetwork,
        'concurrencySafe': concurrencySafe,
      };
}

class AiToolPermissionMatrix {
  const AiToolPermissionMatrix(this.rules);

  final List<AiToolPermissionRule> rules;

  AiToolPermissionRule? ruleFor(String toolId) {
    for (final rule in rules) {
      if (rule.toolId == toolId) return rule;
    }
    return null;
  }

  bool isAllowed({
    required AiAgentScene scene,
    required String toolId,
  }) {
    return ruleFor(toolId)?.allows(scene) ?? false;
  }

  bool requiresApproval(String toolId) {
    return ruleFor(toolId)?.requiresApproval ?? true;
  }

  List<String> allowedTools(AiAgentScene scene) {
    return rules
        .where((rule) => rule.allows(scene))
        .map((rule) => rule.toolId)
        .toList(growable: false);
  }

  static const defaultMatrix = AiToolPermissionMatrix([
    AiToolPermissionRule(
      toolId: 'current_reading_metadata',
      scenes: {AiAgentScene.reading, AiAgentScene.seminar},
    ),
    AiToolPermissionRule(
      toolId: 'current_chapter_content',
      scenes: {AiAgentScene.reading, AiAgentScene.seminar},
    ),
    AiToolPermissionRule(
      toolId: 'current_book_toc',
      scenes: {AiAgentScene.reading, AiAgentScene.seminar},
    ),
    AiToolPermissionRule(
      toolId: 'chapter_content_by_href',
      scenes: {AiAgentScene.reading, AiAgentScene.seminar},
    ),
    AiToolPermissionRule(
      toolId: 'current_book_fulltext',
      scenes: {AiAgentScene.reading, AiAgentScene.seminar},
    ),
    AiToolPermissionRule(
      toolId: 'book_content_search',
      scenes: {AiAgentScene.reading, AiAgentScene.seminar},
    ),
    AiToolPermissionRule(
      toolId: 'resolve_cfi',
      scenes: {AiAgentScene.reading, AiAgentScene.review, AiAgentScene.seminar},
    ),
    AiToolPermissionRule(
      toolId: 'semantic_search_current_book',
      scenes: {AiAgentScene.reading, AiAgentScene.seminar},
    ),
    AiToolPermissionRule(
      toolId: 'semantic_search_library',
      scenes: {AiAgentScene.library},
    ),
    AiToolPermissionRule(
      toolId: 'notes_search',
      scenes: {AiAgentScene.reading, AiAgentScene.review, AiAgentScene.seminar},
    ),
    AiToolPermissionRule(
      toolId: 'create_note',
      scenes: {AiAgentScene.reading},
      requiresApproval: true,
      readOnly: false,
      concurrencySafe: false,
    ),
    AiToolPermissionRule(
      toolId: 'create_highlight',
      scenes: {AiAgentScene.reading},
      requiresApproval: true,
      readOnly: false,
      concurrencySafe: false,
    ),
    AiToolPermissionRule(
      toolId: 'spawn_sub_agent',
      scenes: {AiAgentScene.reading, AiAgentScene.seminar},
      requiresApproval: false,
      readOnly: true,
      concurrencySafe: false,
    ),
    AiToolPermissionRule(
      toolId: 'web_search',
      scenes: {AiAgentScene.global},
      allowsExternalNetwork: true,
    ),
  ]);

  static const seminarLibraryFallbackMatrix = AiToolPermissionMatrix([
    AiToolPermissionRule(
      toolId: 'semantic_search_library',
      scenes: {AiAgentScene.seminar},
    ),
    AiToolPermissionRule(
      toolId: 'notes_search',
      scenes: {AiAgentScene.seminar},
    ),
    AiToolPermissionRule(
      toolId: 'spawn_sub_agent',
      scenes: {AiAgentScene.seminar},
      readOnly: true,
      concurrencySafe: false,
    ),
  ]);
}

@immutable
class SubAgentGovernancePolicy {
  const SubAgentGovernancePolicy({
    this.allowRecursiveSpawn = false,
    this.defaultSerialExecution = true,
    this.readOnlyParallelAllowed = true,
    this.maxSteps = 8,
    this.timeoutSeconds = 180,
    this.costBudgetUsd,
  });

  final bool allowRecursiveSpawn;
  final bool defaultSerialExecution;
  final bool readOnlyParallelAllowed;
  final int maxSteps;
  final int timeoutSeconds;
  final double? costBudgetUsd;

  bool canUseToolInsideSubAgent(String toolId) {
    if (!allowRecursiveSpawn && toolId == 'spawn_sub_agent') return false;
    return true;
  }

  bool canRunInParallel(AiToolPermissionRule rule) {
    return readOnlyParallelAllowed && rule.readOnly && rule.concurrencySafe;
  }
}

@immutable
class CustomSkillContract {
  const CustomSkillContract({
    this.schemaVersion = 1,
    required this.id,
    required this.name,
    this.description,
    required this.systemPromptAppend,
    this.allowedToolIds = const <String>[],
    this.scenes = const <AiAgentScene>[AiAgentScene.reading],
    this.enabled = false,
    this.unknownFields = const <String>[],
    this.unknownSceneValues = const <String>[],
    this.schemaErrors = const <String>[],
  });

  static const _schemaVersion = 1;
  static const _knownJsonKeys = {
    'schemaVersion',
    'id',
    'name',
    'description',
    'systemPromptAppend',
    'allowedToolIds',
    'scenes',
    'enabled',
  };

  factory CustomSkillContract.fromJson(Map<String, dynamic> json) {
    final schemaErrors = <String>[];
    final sceneParse = _parseScenes(json['scenes'], schemaErrors);
    return CustomSkillContract(
      schemaVersion: _parseSchemaVersion(json, schemaErrors),
      id: _stringField(json, 'id', schemaErrors),
      name: _stringField(json, 'name', schemaErrors),
      description: _optionalStringField(json, 'description', schemaErrors),
      systemPromptAppend:
          _stringField(json, 'systemPromptAppend', schemaErrors),
      allowedToolIds: _stringListField(json, 'allowedToolIds', schemaErrors),
      scenes: sceneParse.scenes,
      enabled: _boolField(json, 'enabled', schemaErrors),
      unknownFields: json.keys
          .where((key) => !_knownJsonKeys.contains(key))
          .toList(growable: false)
        ..sort(),
      unknownSceneValues: sceneParse.unknownValues,
      schemaErrors: schemaErrors,
    );
  }

  final int schemaVersion;
  final String id;
  final String name;
  final String? description;
  final String systemPromptAppend;
  final List<String> allowedToolIds;
  final List<AiAgentScene> scenes;
  final bool enabled;
  final List<String> unknownFields;
  final List<String> unknownSceneValues;
  final List<String> schemaErrors;

  bool canInject(AiToolPermissionMatrix matrix) {
    return enabled && validate(matrix).isEmpty;
  }

  List<String> validate(AiToolPermissionMatrix matrix) {
    final errors = <String>[];
    errors.addAll(schemaErrors);
    if (schemaVersion != _schemaVersion) {
      errors.add('unsupported schemaVersion: $schemaVersion');
    }
    for (final field in unknownFields) {
      errors.add('unknown field: $field');
    }
    if (id.trim().isEmpty) errors.add('id is required');
    if (name.trim().isEmpty) errors.add('name is required');
    if (systemPromptAppend.trim().isEmpty) {
      errors.add('systemPromptAppend is required');
    }
    if (scenes.isEmpty) {
      errors.add('at least one scene is required');
    }
    if (scenes.contains(AiAgentScene.system)) {
      errors.add('custom skills cannot request system scene');
    }
    for (final scene in unknownSceneValues) {
      errors.add('unknown scene: $scene');
    }
    for (final toolId in allowedToolIds) {
      final normalizedToolId = toolId.trim();
      if (normalizedToolId.isEmpty) {
        errors.add('tool id is required');
        continue;
      }
      final rule = matrix.ruleFor(normalizedToolId);
      if (rule == null) {
        errors.add('unknown tool: $normalizedToolId');
        continue;
      }
      if (!scenes.any(rule.allows)) {
        errors.add('tool not allowed in requested scenes: $normalizedToolId');
      }
      if (!rule.readOnly) {
        errors
            .add('custom skills cannot request write tool: $normalizedToolId');
      }
      if (normalizedToolId == 'spawn_sub_agent') {
        errors.add('custom skills cannot request recursive sub-agent access');
      }
    }
    return errors;
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'name': name,
        if (description != null) 'description': description,
        'systemPromptAppend': systemPromptAppend,
        'allowedToolIds': allowedToolIds,
        'scenes': scenes.map((scene) => scene.asString).toList(growable: false),
        'enabled': enabled,
      };

  static int _parseSchemaVersion(
    Map<String, dynamic> json,
    List<String> errors,
  ) {
    if (!json.containsKey('schemaVersion')) {
      errors.add('schemaVersion is required');
      return _schemaVersion;
    }
    final value = json['schemaVersion'];
    if (value is int) return value;
    errors.add('schemaVersion must be an integer');
    return _schemaVersion;
  }

  static String _stringField(
    Map<String, dynamic> json,
    String key,
    List<String> errors,
  ) {
    final value = json[key];
    if (value == null) return '';
    if (value is String) return value;
    errors.add('$key must be a string');
    return '';
  }

  static String? _optionalStringField(
    Map<String, dynamic> json,
    String key,
    List<String> errors,
  ) {
    if (!json.containsKey(key) || json[key] == null) return null;
    final value = json[key];
    if (value is String) return value;
    errors.add('$key must be a string');
    return null;
  }

  static List<String> _stringListField(
    Map<String, dynamic> json,
    String key,
    List<String> errors,
  ) {
    final value = json[key];
    if (value == null) return const <String>[];
    if (value is! Iterable) {
      errors.add('$key must be a list');
      return const <String>[];
    }
    final entries = <String>[];
    var reportedEntryType = false;
    for (final entry in value) {
      if (entry is String) {
        entries.add(entry);
      } else if (!reportedEntryType) {
        errors.add('$key entries must be strings');
        reportedEntryType = true;
      }
    }
    return entries;
  }

  static bool _boolField(
    Map<String, dynamic> json,
    String key,
    List<String> errors,
  ) {
    if (!json.containsKey(key) || json[key] == null) return false;
    final value = json[key];
    if (value is bool) return value;
    errors.add('$key must be a boolean');
    return false;
  }

  static _SceneParse _parseScenes(Object? value, List<String> errors) {
    if (value == null) {
      return const _SceneParse(
        scenes: <AiAgentScene>[AiAgentScene.reading],
        unknownValues: <String>[],
      );
    }
    if (value is! Iterable) {
      errors.add('scenes must be a list');
      return const _SceneParse(
        scenes: <AiAgentScene>[],
        unknownValues: <String>[],
      );
    }
    final scenes = <AiAgentScene>[];
    final unknown = <String>[];
    var reportedEntryType = false;
    for (final entry in value) {
      if (entry is! String) {
        if (!reportedEntryType) {
          errors.add('scenes entries must be strings');
          reportedEntryType = true;
        }
        continue;
      }
      final raw = entry;
      final scene = AiAgentScene.tryParse(raw);
      if (scene == null) {
        unknown.add(raw);
        continue;
      }
      if (!scenes.contains(scene)) scenes.add(scene);
    }
    return _SceneParse(
      scenes: scenes,
      unknownValues: unknown,
    );
  }
}

@immutable
class _SceneParse {
  const _SceneParse({
    required this.scenes,
    required this.unknownValues,
  });

  final List<AiAgentScene> scenes;
  final List<String> unknownValues;
}

@immutable
class ProviderCapability {
  const ProviderCapability({
    required this.providerId,
    required this.modelId,
    this.contextWindow,
    this.supportsTools = false,
    this.supportsVision = false,
    this.responsesCompatible = false,
    this.supportsStreaming = true,
    this.inputCostPerMillion,
    this.outputCostPerMillion,
  });

  final String providerId;
  final String modelId;
  final int? contextWindow;
  final bool supportsTools;
  final bool supportsVision;
  final bool responsesCompatible;
  final bool supportsStreaming;
  final double? inputCostPerMillion;
  final double? outputCostPerMillion;

  bool get canRunSeminar => supportsTools && (contextWindow ?? 0) >= 16000;

  Map<String, dynamic> toJson() => {
        'providerId': providerId,
        'modelId': modelId,
        if (contextWindow != null) 'contextWindow': contextWindow,
        'supportsTools': supportsTools,
        'supportsVision': supportsVision,
        'responsesCompatible': responsesCompatible,
        'supportsStreaming': supportsStreaming,
        if (inputCostPerMillion != null)
          'inputCostPerMillion': inputCostPerMillion,
        if (outputCostPerMillion != null)
          'outputCostPerMillion': outputCostPerMillion,
      };
}
