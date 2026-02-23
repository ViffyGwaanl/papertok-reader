import 'dart:async';

import 'package:anx_reader/enums/ai_tool_risk_level.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/services.dart';

import 'base_tool.dart';

class CalendarDeleteEventTool
    extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  CalendarDeleteEventTool()
      : super(
          name: 'calendar_delete_event',
          description:
              'Delete a calendar event from the device. Requires explicit user approval before running.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'eventId': {
                'type': 'string',
                'description':
                    'Required. Target event id. Use calendar_list_events output eventId (or instanceId for recurring events).',
              },
              'span': {
                'type': 'string',
                'description':
                    'Optional. iOS-only. For recurring events: thisEvent|futureEvents. Defaults to thisEvent.',
              },
            },
            'required': ['eventId'],
          },
          timeout: const Duration(seconds: 12),
        );

  static const MethodChannel _iosChannel =
      MethodChannel('ai.papertok.paperreader/calendar_eventkit');

  @override
  JsonMap parseInput(Map<String, dynamic> json) => json;

  Future<void> _ensurePermissions(DeviceCalendar plugin) async {
    var status = await plugin.hasPermissions();
    if (status != CalendarPermissionStatus.granted) {
      status = await plugin.requestPermissions();
    }
    if (status != CalendarPermissionStatus.granted) {
      throw StateError('permissionDenied');
    }
  }

  @override
  Future<Map<String, dynamic>> run(JsonMap input) async {
    if (!AnxPlatform.isIOS && !AnxPlatform.isAndroid) {
      throw UnsupportedError('notSupported');
    }

    final eventId = input['eventId']?.toString().trim() ?? '';
    if (eventId.isEmpty) {
      throw ArgumentError('eventId is required');
    }

    final span = input['span']?.toString().trim();

    if (AnxPlatform.isIOS) {
      final raw = await _iosChannel.invokeMethod<Map>(
        'deleteEvent',
        <String, dynamic>{
          'eventId': eventId,
          if (span != null && span.isNotEmpty) 'span': span,
        },
      );
      if (raw == null) {
        throw StateError('Failed to delete event');
      }
      return Map<String, dynamic>.from(raw);
    }

    final plugin = DeviceCalendar.instance;
    await _ensurePermissions(plugin);

    await plugin.deleteEvent(eventId: eventId);

    return {
      'ok': true,
      'eventId': eventId,
    };
  }

  @override
  bool shouldLogError(Object error) {
    final msg = error.toString();
    return !(msg.contains('permissionDenied') || msg.contains('notSupported'));
  }
}

final AiToolDefinition calendarDeleteEventToolDefinition = AiToolDefinition(
  id: 'calendar_delete_event',
  displayNameBuilder: (L10n l10n) => l10n.aiToolCalendarDeleteEventName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolCalendarDeleteEventDescription,
  riskLevel: AiToolRiskLevel.destructive,
  build: (context) => CalendarDeleteEventTool().tool,
);
