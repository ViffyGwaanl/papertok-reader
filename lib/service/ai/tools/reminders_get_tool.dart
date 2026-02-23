import 'dart:async';

import 'package:anx_reader/enums/ai_tool_risk_level.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:flutter/services.dart';

import 'base_tool.dart';

class RemindersGetTool extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  RemindersGetTool()
      : super(
          name: 'reminders_get',
          description:
              'Get a single iOS reminder by id using EventKit. Read-only. On non-iOS platforms, returns not supported.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'reminderId': {
                'type': 'string',
                'description':
                    'Required. Reminder identifier returned by reminders_list.',
              },
              'includeNotes': {
                'type': 'boolean',
                'description':
                    'Optional. Include notes/body field. Defaults to false.',
              },
              'notesMaxLen': {
                'type': 'number',
                'description':
                    'Optional. When includeNotes=true, truncate notes to this length. Defaults to 400. Max 8000.',
              },
            },
            'required': ['reminderId'],
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

    final reminderId = input['reminderId']?.toString().trim() ?? '';
    if (reminderId.isEmpty) {
      throw ArgumentError('reminderId is required');
    }

    final args = <String, dynamic>{
      'reminderId': reminderId,
      if (input['includeNotes'] is bool)
        'includeNotes': input['includeNotes'] as bool,
      if (input['notesMaxLen'] is num)
        'notesMaxLen': (input['notesMaxLen'] as num).toInt(),
    };

    final result = await _channel.invokeMethod<Map>('get', args);
    if (result == null) {
      throw StateError('Failed to get reminder');
    }

    return Map<String, dynamic>.from(result);
  }

  @override
  bool shouldLogError(Object error) {
    final msg = error.toString();
    return !(msg.contains('notSupported') || msg.contains('permissionDenied'));
  }
}

final AiToolDefinition remindersGetToolDefinition = AiToolDefinition(
  id: 'reminders_get',
  displayNameBuilder: (L10n l10n) => l10n.aiToolRemindersGetName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolRemindersGetDescription,
  riskLevel: AiToolRiskLevel.readOnly,
  build: (context) => RemindersGetTool().tool,
);
