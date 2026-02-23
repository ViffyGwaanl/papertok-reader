import 'dart:async';

import 'package:anx_reader/enums/ai_tool_risk_level.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:flutter/services.dart';

import 'base_tool.dart';

class RemindersCreateTool
    extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  RemindersCreateTool()
      : super(
          name: 'reminders_create',
          description:
              'Create a native reminder on iOS using EventKit. Requires explicit user approval. On non-iOS platforms, returns not supported.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'title': {
                'type': 'string',
                'description': 'Required. Reminder title.',
              },
              'notes': {
                'type': 'string',
                'description': 'Optional. Notes/body for the reminder.',
              },
              'dueIso': {
                'type': 'string',
                'description':
                    'Optional. Due datetime in ISO-8601 (local or with timezone).',
              },
              'listId': {
                'type': 'string',
                'description':
                    'Optional. Target reminders list/calendar identifier. When omitted, uses the default reminders list.',
              },
              'calendarId': {
                'type': 'string',
                'description':
                    'Optional. Alias of listId for compatibility with other apps.',
              },
              'priority': {
                'type': 'number',
                'description':
                    'Optional. 0..9. 0 means no priority. 1=highest, 9=lowest.',
              },
              'url': {
                'type': 'string',
                'description': 'Optional. Attach a URL to the reminder.',
              },
              'alarmMinutes': {
                'description':
                    'Optional. Single number or array. Adds absolute alarms at dueDate - N minutes. Requires dueIso.',
                'oneOf': [
                  {'type': 'number'},
                  {
                    'type': 'array',
                    'items': {'type': 'number'}
                  },
                ],
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

    final listId = (input['listId']?.toString().trim() ?? '').isNotEmpty
        ? input['listId']?.toString()
        : (input['calendarId']?.toString().trim() ?? '').isNotEmpty
            ? input['calendarId']?.toString()
            : null;

    final args = <String, dynamic>{
      'title': title,
      if ((input['notes']?.toString().trim() ?? '').isNotEmpty)
        'notes': input['notes']?.toString(),
      if ((input['dueIso']?.toString().trim() ?? '').isNotEmpty)
        'dueIso': input['dueIso']?.toString(),
      if (listId != null) 'listId': listId,
      if (input['priority'] is num)
        'priority': (input['priority'] as num).toInt(),
      if ((input['url']?.toString().trim() ?? '').isNotEmpty)
        'url': input['url']?.toString(),
      if (input.containsKey('alarmMinutes'))
        'alarmMinutes': input['alarmMinutes'],
    };

    final result = await _channel.invokeMethod<Map>('create', args);
    if (result == null) {
      throw StateError('Failed to create reminder');
    }

    return Map<String, dynamic>.from(result);
  }

  @override
  bool shouldLogError(Object error) {
    final msg = error.toString();
    return !(msg.contains('notSupported') || msg.contains('permissionDenied'));
  }
}

final AiToolDefinition remindersCreateToolDefinition = AiToolDefinition(
  id: 'reminders_create',
  displayNameBuilder: (L10n l10n) => l10n.aiToolRemindersCreateName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolRemindersCreateDescription,
  riskLevel: AiToolRiskLevel.write,
  build: (context) => RemindersCreateTool().tool,
);
