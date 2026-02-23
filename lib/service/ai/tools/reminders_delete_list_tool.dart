import 'dart:async';

import 'package:anx_reader/enums/ai_tool_risk_level.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:flutter/services.dart';

import 'base_tool.dart';

class RemindersDeleteListTool
    extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  RemindersDeleteListTool()
      : super(
          name: 'reminders_list_delete',
          description:
              'Delete an iOS Reminders list (calendar) using EventKit. DESTRUCTIVE. Requires explicit user approval. On non-iOS platforms, returns not supported.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'listId': {
                'type': 'string',
                'description': 'Required. List/calendar identifier.',
              },
            },
            'required': ['listId'],
          },
          timeout: const Duration(seconds: 10),
        );

  static const MethodChannel _channel =
      MethodChannel('ai.papertok.paperreader/reminders');

  @override
  JsonMap parseInput(Map<String, dynamic> json) => json;

  @override
  Future<Map<String, dynamic>> run(JsonMap input) async {
    if (!AnxPlatform.isIOS) {
      throw UnsupportedError('notSupported');
    }

    final listId = input['listId']?.toString().trim() ?? '';
    if (listId.isEmpty) {
      throw ArgumentError('listId is required');
    }

    final result = await _channel.invokeMethod<Map>(
      'deleteList',
      <String, dynamic>{'listId': listId},
    );
    if (result == null) {
      throw StateError('Failed to delete reminders list');
    }

    return Map<String, dynamic>.from(result);
  }

  @override
  bool shouldLogError(Object error) {
    final msg = error.toString();
    return !(msg.contains('notSupported') || msg.contains('permissionDenied'));
  }
}

final AiToolDefinition remindersDeleteListToolDefinition = AiToolDefinition(
  id: 'reminders_list_delete',
  displayNameBuilder: (L10n l10n) => l10n.aiToolRemindersListDeleteName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolRemindersListDeleteDescription,
  riskLevel: AiToolRiskLevel.destructive,
  build: (context) => RemindersDeleteListTool().tool,
);
