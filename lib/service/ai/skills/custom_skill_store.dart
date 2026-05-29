import 'dart:convert';

import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/models/ai_agent_governance.dart';
import 'package:papertok_reader/service/ai/skills/ai_skill.dart';

class CustomSkillImportResult {
  const CustomSkillImportResult({
    required this.accepted,
    this.contract,
    this.errors = const <String>[],
  });

  final bool accepted;
  final CustomSkillContract? contract;
  final List<String> errors;
}

class CustomSkillStore {
  CustomSkillStore({Prefs? prefs}) : _prefs = prefs ?? Prefs();

  static const String _contractsKey = 'customAiSkillContractsV1';

  final Prefs _prefs;

  List<CustomSkillContract> contracts() {
    final stored = _prefs.prefs.getStringList(_contractsKey) ?? const [];
    final parsed = <CustomSkillContract>[];
    for (final raw in stored) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          parsed.add(CustomSkillContract.fromJson(decoded));
        } else if (decoded is Map) {
          parsed.add(CustomSkillContract.fromJson(
            Map<String, dynamic>.from(decoded),
          ));
        }
      } catch (_) {
        // Ignore corrupt legacy entries; importing again rewrites the list.
      }
    }
    return parsed;
  }

  List<AiSkill> runtimeSkills({
    AiToolPermissionMatrix matrix = AiToolPermissionMatrix.defaultMatrix,
  }) {
    return contracts()
        .where((contract) => contract.canInject(matrix))
        .map(_toAiSkill)
        .toList(growable: false);
  }

  Future<CustomSkillImportResult> importJson(
    String raw, {
    AiToolPermissionMatrix matrix = AiToolPermissionMatrix.defaultMatrix,
  }) async {
    final decoded = _decodeObject(raw);
    if (decoded.errors.isNotEmpty) {
      return CustomSkillImportResult(
        accepted: false,
        errors: decoded.errors,
      );
    }

    final contract = CustomSkillContract.fromJson(decoded.value!);
    final errors = contract.validate(matrix);
    if (errors.isNotEmpty) {
      return CustomSkillImportResult(
        accepted: false,
        contract: contract,
        errors: errors,
      );
    }

    final next = [
      for (final existing in contracts())
        if (existing.id != contract.id) existing,
      contract,
    ];
    await _write(next);
    return CustomSkillImportResult(
      accepted: true,
      contract: contract,
    );
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final next = [
      for (final contract in contracts())
        if (contract.id == id)
          _copyWithEnabled(contract, enabled)
        else
          contract,
    ];
    await _write(next);
  }

  Future<void> delete(String id) async {
    final next = [
      for (final contract in contracts())
        if (contract.id != id) contract,
    ];
    await _write(next);
    if (_prefs.activeAiSkillId == id) {
      _prefs.activeAiSkillId = null;
    }
  }

  Future<void> _write(List<CustomSkillContract> contracts) {
    final encoded = contracts
        .map((contract) => jsonEncode(contract.toJson()))
        .toList(growable: false);
    return _prefs.prefs.setStringList(_contractsKey, encoded);
  }

  static AiSkill _toAiSkill(CustomSkillContract contract) {
    return AiSkill(
      id: contract.id,
      name: contract.name,
      description: contract.description ?? '',
      systemPromptAppend: contract.systemPromptAppend,
      isBuiltIn: false,
      allowedToolIds: contract.allowedToolIds,
      sceneIds: contract.scenes
          .map((scene) => scene.asString)
          .toList(growable: false),
    );
  }

  static CustomSkillContract _copyWithEnabled(
    CustomSkillContract contract,
    bool enabled,
  ) {
    return CustomSkillContract(
      schemaVersion: contract.schemaVersion,
      id: contract.id,
      name: contract.name,
      description: contract.description,
      systemPromptAppend: contract.systemPromptAppend,
      allowedToolIds: contract.allowedToolIds,
      scenes: contract.scenes,
      enabled: enabled,
      unknownFields: contract.unknownFields,
      unknownSceneValues: contract.unknownSceneValues,
      schemaErrors: contract.schemaErrors,
    );
  }

  static _DecodedObject _decodeObject(String raw) {
    if (raw.trim().isEmpty) {
      return const _DecodedObject(errors: ['JSON is required']);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return _DecodedObject(value: decoded);
      }
      if (decoded is Map) {
        return _DecodedObject(value: Map<String, dynamic>.from(decoded));
      }
      return const _DecodedObject(errors: ['JSON root must be an object']);
    } catch (error) {
      return _DecodedObject(errors: ['Invalid JSON: $error']);
    }
  }
}

class _DecodedObject {
  const _DecodedObject({
    this.value,
    this.errors = const <String>[],
  });

  final Map<String, dynamic>? value;
  final List<String> errors;
}
