import 'dart:async';

import 'package:anx_reader/enums/ai_tool_risk_level.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:flutter/services.dart';

import 'base_tool.dart';

class RemindersListListsTool
    extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  RemindersListListsTool()
      : super(
          name: 'reminders_list_lists',
          description:
              'List iOS Reminders lists (calendars) using EventKit. Read-only. On non-iOS platforms, returns not supported.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {},
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

    final result = await _channel.invokeMethod<Map>('listLists');
    if (result == null) {
      throw StateError('Failed to list reminders lists');
    }

    return Map<String, dynamic>.from(result);
  }

  @override
  bool shouldLogError(Object error) {
    final msg = error.toString();
    return !(msg.contains('notSupported') || msg.contains('permissionDenied'));
  }
}

final AiToolDefinition remindersListListsToolDefinition = AiToolDefinition(
  id: 'reminders_list_lists',
  displayNameBuilder: (L10n l10n) => l10n.aiToolRemindersListListsName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolRemindersListListsDescription,
  riskLevel: AiToolRiskLevel.readOnly,
  build: (context) => RemindersListListsTool().tool,
);
