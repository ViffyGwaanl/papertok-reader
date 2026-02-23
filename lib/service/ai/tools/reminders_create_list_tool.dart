import 'dart:async';

import 'package:anx_reader/enums/ai_tool_risk_level.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:flutter/services.dart';

import 'base_tool.dart';

class RemindersCreateListTool
    extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  RemindersCreateListTool()
      : super(
          name: 'reminders_list_create',
          description:
              'Create a new iOS Reminders list (calendar) using EventKit. Requires explicit user approval. On non-iOS platforms, returns not supported.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'title': {
                'type': 'string',
                'description': 'Required. New list title.',
              },
            },
            'required': ['title'],
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

    final title = input['title']?.toString().trim() ?? '';
    if (title.isEmpty) {
      throw ArgumentError('title is required');
    }

    final result = await _channel.invokeMethod<Map>(
      'createList',
      <String, dynamic>{'title': title},
    );
    if (result == null) {
      throw StateError('Failed to create reminders list');
    }

    return Map<String, dynamic>.from(result);
  }

  @override
  bool shouldLogError(Object error) {
    final msg = error.toString();
    return !(msg.contains('notSupported') || msg.contains('permissionDenied'));
  }
}

final AiToolDefinition remindersCreateListToolDefinition = AiToolDefinition(
  id: 'reminders_list_create',
  displayNameBuilder: (L10n l10n) => l10n.aiToolRemindersListCreateName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolRemindersListCreateDescription,
  riskLevel: AiToolRiskLevel.write,
  build: (context) => RemindersCreateListTool().tool,
);
