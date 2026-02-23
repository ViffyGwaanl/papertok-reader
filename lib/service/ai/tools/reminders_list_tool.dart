import 'dart:async';

import 'package:anx_reader/enums/ai_tool_risk_level.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:flutter/services.dart';

import 'base_tool.dart';

class RemindersListTool extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  RemindersListTool()
      : super(
          name: 'reminders_list',
          description:
              'List iOS reminders within a time window using EventKit. Read-only. Defaults to now..now+7days. On non-iOS platforms, returns not supported.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'listIds': {
                'type': 'array',
                'items': {'type': 'string'},
                'description':
                    'Required. Array of reminders list identifiers. Use reminders_list_lists first.',
              },
              'startIso': {
                'type': 'string',
                'description':
                    'Optional. Start datetime (ISO-8601). Defaults to now.',
              },
              'endIso': {
                'type': 'string',
                'description':
                    'Optional. End datetime (ISO-8601). Defaults to start+7 days.',
              },
              'days': {
                'type': 'number',
                'description':
                    'Optional. When endIso is omitted, end = start + days. Defaults to 7. Range: 1..60.',
              },
              'includeCompleted': {
                'type': 'boolean',
                'description':
                    'Optional. Include completed reminders. Default false.',
              },
              'includeUndated': {
                'type': 'boolean',
                'description':
                    'Optional. Include reminders without due date. Default false.',
              },
              'includeNotes': {
                'type': 'boolean',
                'description':
                    'Optional. Include notes/body field. Default false.',
              },
              'notesMaxLen': {
                'type': 'number',
                'description':
                    'Optional. When includeNotes=true, truncate notes to this length. Defaults to 400. Max 8000.',
              },
              'limit': {
                'type': 'number',
                'description':
                    'Optional. Max reminders to return. Default 200. Max 1000.',
              },
            },
            'required': ['listIds'],
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

    final listIds = input['listIds'];
    if (listIds is! List || listIds.isEmpty) {
      throw ArgumentError('listIds is required');
    }

    final startIso = input['startIso']?.toString().trim() ?? '';
    final endIso = input['endIso']?.toString().trim() ?? '';

    final args = <String, dynamic>{
      'listIds': listIds.map((e) => e.toString()).toList(growable: false),
      if (startIso.isNotEmpty) 'startIso': startIso,
      if (endIso.isNotEmpty) 'endIso': endIso,
      if (input['days'] is num) 'days': (input['days'] as num).toInt(),
      if (input['includeCompleted'] is bool)
        'includeCompleted': input['includeCompleted'] as bool,
      if (input['includeUndated'] is bool)
        'includeUndated': input['includeUndated'] as bool,
      if (input['includeNotes'] is bool)
        'includeNotes': input['includeNotes'] as bool,
      if (input['notesMaxLen'] is num)
        'notesMaxLen': (input['notesMaxLen'] as num).toInt(),
      if (input['limit'] is num) 'limit': (input['limit'] as num).toInt(),
    };

    final result = await _channel.invokeMethod<Map>('list', args);
    if (result == null) {
      throw StateError('Failed to list reminders');
    }

    return Map<String, dynamic>.from(result);
  }

  @override
  bool shouldLogError(Object error) {
    final msg = error.toString();
    return !(msg.contains('notSupported') || msg.contains('permissionDenied'));
  }
}

final AiToolDefinition remindersListToolDefinition = AiToolDefinition(
  id: 'reminders_list',
  displayNameBuilder: (L10n l10n) => l10n.aiToolRemindersListName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolRemindersListDescription,
  riskLevel: AiToolRiskLevel.readOnly,
  build: (context) => RemindersListTool().tool,
);
