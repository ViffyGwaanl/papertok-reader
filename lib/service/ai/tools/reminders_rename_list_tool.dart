import 'dart:async';

import 'package:anx_reader/enums/ai_tool_risk_level.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:flutter/services.dart';

import 'base_tool.dart';

class RemindersRenameListTool
    extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  RemindersRenameListTool()
      : super(
          name: 'reminders_list_rename',
          description:
              'Rename an iOS Reminders list (calendar) using EventKit. Requires explicit user approval. On non-iOS platforms, returns not supported.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'listId': {
                'type': 'string',
                'description': 'Required. List/calendar identifier.',
              },
              'title': {
                'type': 'string',
                'description': 'Required. New title.',
              },
            },
            'required': ['listId', 'title'],
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
    final title = input['title']?.toString().trim() ?? '';
    if (listId.isEmpty || title.isEmpty) {
      throw ArgumentError('listId and title are required');
    }

    final result = await _channel.invokeMethod<Map>(
      'renameList',
      <String, dynamic>{
        'listId': listId,
        'title': title,
      },
    );
    if (result == null) {
      throw StateError('Failed to rename reminders list');
    }

    return Map<String, dynamic>.from(result);
  }

  @override
  bool shouldLogError(Object error) {
    final msg = error.toString();
    return !(msg.contains('notSupported') || msg.contains('permissionDenied'));
  }
}

final AiToolDefinition remindersRenameListToolDefinition = AiToolDefinition(
  id: 'reminders_list_rename',
  displayNameBuilder: (L10n l10n) => l10n.aiToolRemindersListRenameName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolRemindersListRenameDescription,
  riskLevel: AiToolRiskLevel.write,
  build: (context) => RemindersRenameListTool().tool,
);
