import 'dart:async';

import 'package:anx_reader/enums/ai_tool_risk_level.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:flutter/services.dart';

import 'base_tool.dart';

class RemindersCompleteTool
    extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  RemindersCompleteTool()
      : super(
          name: 'reminders_complete',
          description:
              'Mark an iOS reminder as completed using EventKit. Requires explicit user approval. On non-iOS platforms, returns not supported.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'reminderId': {
                'type': 'string',
                'description': 'Required. Reminder identifier.',
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

    final result = await _channel.invokeMethod<Map>(
      'complete',
      <String, dynamic>{'reminderId': reminderId},
    );
    if (result == null) {
      throw StateError('Failed to complete reminder');
    }

    return Map<String, dynamic>.from(result);
  }

  @override
  bool shouldLogError(Object error) {
    final msg = error.toString();
    return !(msg.contains('notSupported') || msg.contains('permissionDenied'));
  }
}

final AiToolDefinition remindersCompleteToolDefinition = AiToolDefinition(
  id: 'reminders_complete',
  displayNameBuilder: (L10n l10n) => l10n.aiToolRemindersCompleteName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolRemindersCompleteDescription,
  riskLevel: AiToolRiskLevel.write,
  build: (context) => RemindersCompleteTool().tool,
);
