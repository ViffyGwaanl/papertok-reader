import 'dart:async';

import 'package:anx_reader/enums/ai_tool_risk_level.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:flutter/services.dart';

import 'base_tool.dart';

class RemindersUpdateTool
    extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  RemindersUpdateTool()
      : super(
          name: 'reminders_update',
          description:
              'Update an iOS reminder using EventKit. Requires explicit user approval. On non-iOS platforms, returns not supported.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'reminderId': {
                'type': 'string',
                'description': 'Required. Reminder identifier.',
              },
              'title': {
                'type': 'string',
                'description': 'Optional. New title. Empty string clears.',
              },
              'notes': {
                'type': 'string',
                'description': 'Optional. New notes. Empty string clears.',
              },
              'dueIso': {
                'type': 'string',
                'description':
                    'Optional. New due datetime in ISO-8601. Empty string clears.',
              },
              'clearDue': {
                'type': 'boolean',
                'description': 'Optional. Clear due date. Default false.',
              },
              'listId': {
                'type': 'string',
                'description':
                    'Optional. Move reminder to another list/calendar id.',
              },
              'priority': {
                'type': 'number',
                'description':
                    'Optional. 0..9. 0 clears priority. 1=highest, 9=lowest.',
              },
              'url': {
                'type': 'string',
                'description':
                    'Optional. URL attached to reminder. Empty string clears.',
              },
              'alarmMinutes': {
                'description':
                    'Optional. Single number or array. Adds absolute alarms at dueDate - N minutes. Requires due date (or existing due date).',
                'oneOf': [
                  {'type': 'number'},
                  {
                    'type': 'array',
                    'items': {'type': 'number'}
                  },
                ],
              },
              'clearAlarms': {
                'type': 'boolean',
                'description': 'Optional. Clear alarms. Default false.',
              },
            },
            'required': ['reminderId'],
          },
          timeout: const Duration(seconds: 12),
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

    final reminderId = input['reminderId']?.toString().trim() ?? '';
    if (reminderId.isEmpty) {
      throw ArgumentError('reminderId is required');
    }

    final args = <String, dynamic>{
      'reminderId': reminderId,
      if (input.containsKey('title')) 'title': input['title']?.toString() ?? '',
      if (input.containsKey('notes')) 'notes': input['notes']?.toString() ?? '',
      if (input.containsKey('dueIso'))
        'dueIso': input['dueIso']?.toString() ?? '',
      if (input['clearDue'] is bool) 'clearDue': input['clearDue'] as bool,
      if ((input['listId']?.toString().trim() ?? '').isNotEmpty)
        'listId': input['listId']?.toString(),
      if (input['priority'] is num)
        'priority': (input['priority'] as num).toInt(),
      if (input.containsKey('url')) 'url': input['url']?.toString() ?? '',
      if (input.containsKey('alarmMinutes'))
        'alarmMinutes': input['alarmMinutes'],
      if (input['clearAlarms'] is bool)
        'clearAlarms': input['clearAlarms'] as bool,
    };

    final result = await _channel.invokeMethod<Map>('update', args);
    if (result == null) {
      throw StateError('Failed to update reminder');
    }

    return Map<String, dynamic>.from(result);
  }

  @override
  bool shouldLogError(Object error) {
    final msg = error.toString();
    return !(msg.contains('notSupported') || msg.contains('permissionDenied'));
  }
}

final AiToolDefinition remindersUpdateToolDefinition = AiToolDefinition(
  id: 'reminders_update',
  displayNameBuilder: (L10n l10n) => l10n.aiToolRemindersUpdateName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolRemindersUpdateDescription,
  riskLevel: AiToolRiskLevel.write,
  build: (context) => RemindersUpdateTool().tool,
);
