import 'dart:async';

import 'package:anx_reader/enums/ai_tool_risk_level.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:flutter/services.dart';

import 'base_tool.dart';

class RemindersDeleteTool
    extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  RemindersDeleteTool()
      : super(
          name: 'reminders_delete',
          description:
              'Delete an iOS reminder using EventKit. Requires explicit user approval. On non-iOS platforms, returns not supported.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'reminderId': {
                'type': 'string',
                'description': 'Required. Reminder id to delete.',
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

    final result = await _channel.invokeMethod<Map>('delete', {
      'reminderId': reminderId,
    });
    if (result == null) {
      throw StateError('Failed to delete reminder');
    }

    return Map<String, dynamic>.from(result);
  }

  @override
  bool shouldLogError(Object error) {
    final msg = error.toString();
    return !(msg.contains('notSupported') || msg.contains('permissionDenied'));
  }
}

final AiToolDefinition remindersDeleteToolDefinition = AiToolDefinition(
  id: 'reminders_delete',
  displayNameBuilder: (L10n l10n) => l10n.aiToolRemindersDeleteName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolRemindersDeleteDescription,
  riskLevel: AiToolRiskLevel.destructive,
  build: (context) => RemindersDeleteTool().tool,
);
