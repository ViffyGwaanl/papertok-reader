import 'dart:async';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/services.dart';

import 'base_tool.dart';

class CalendarGetEventTool
    extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  CalendarGetEventTool()
      : super(
          name: 'calendar_get_event',
          description:
              'Get a single calendar event by eventId/instanceId. Read-only. On iOS uses EventKit (supports instanceId for recurring occurrences).',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'eventId': {
                'type': 'string',
                'description':
                    'Required. Event id or instance id from calendar_list_events.',
              },
              'includeDescription': {
                'type': 'boolean',
                'description':
                    'Optional. Include event description/notes. Defaults to true on iOS.',
              },
              'includeAlarms': {
                'type': 'boolean',
                'description':
                    'Optional. iOS-only. Include alarmMinutes[]. Defaults to true on iOS.',
              },
            },
            'required': ['eventId'],
          },
          timeout: const Duration(seconds: 10),
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

  bool _parseBool(Object? raw, bool fallback) {
    if (raw is bool) return raw;
    final s = raw?.toString().trim().toLowerCase();
    if (s == 'true') return true;
    if (s == 'false') return false;
    return fallback;
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

    final includeDescription = _parseBool(input['includeDescription'], true);
    final includeAlarms = _parseBool(input['includeAlarms'], true);

    if (AnxPlatform.isIOS) {
      final raw = await _iosChannel.invokeMethod<Map>(
        'getEvent',
        <String, dynamic>{
          'eventId': eventId,
          'includeDescription': includeDescription,
          'includeAlarms': includeAlarms,
        },
      );
      if (raw == null) {
        throw StateError('Failed to get event');
      }
      return Map<String, dynamic>.from(raw);
    }

    final plugin = DeviceCalendar.instance;
    await _ensurePermissions(plugin);

    final event = await plugin.getEvent(eventId);
    if (event == null) {
      throw StateError('not_found');
    }

    return {
      'event': {
        'eventId': event.eventId,
        'instanceId': event.instanceId,
        'calendarId': event.calendarId,
        'title': event.title,
        'startIso': event.startDate.toIso8601String(),
        'endIso': event.endDate.toIso8601String(),
        'allDay': event.isAllDay,
        if (event.location?.trim().isNotEmpty == true)
          'location': event.location,
        if (includeDescription &&
            (event.description?.trim().isNotEmpty == true))
          'description': event.description,
        'isRecurring': event.isRecurring,
        if (event.timeZone?.trim().isNotEmpty == true)
          'timeZone': event.timeZone,
      },
    };
  }

  @override
  bool shouldLogError(Object error) {
    final msg = error.toString();
    return !(msg.contains('permissionDenied') || msg.contains('notSupported'));
  }
}

final AiToolDefinition calendarGetEventToolDefinition = AiToolDefinition(
  id: 'calendar_get_event',
  displayNameBuilder: (L10n l10n) => l10n.aiToolCalendarGetEventName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolCalendarGetEventDescription,
  build: (context) => CalendarGetEventTool().tool,
);
