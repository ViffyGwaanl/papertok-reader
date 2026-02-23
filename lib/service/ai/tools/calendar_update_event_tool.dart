import 'dart:async';

import 'package:anx_reader/enums/ai_tool_risk_level.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/services.dart';

import 'base_tool.dart';

class CalendarUpdateEventTool
    extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  CalendarUpdateEventTool()
      : super(
          name: 'calendar_update_event',
          description:
              'Update an existing calendar event on the device. Requires explicit user approval before running.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'eventId': {
                'type': 'string',
                'description':
                    'Required. Target event id. Use calendar_list_events output eventId (or instanceId for recurring events).',
              },
              'title': {
                'type': 'string',
                'description': 'Optional. New title.',
              },
              'startIso': {
                'type': 'string',
                'description': 'Optional. New ISO-8601 start datetime.',
              },
              'endIso': {
                'type': 'string',
                'description': 'Optional. New ISO-8601 end datetime.',
              },
              'isAllDay': {
                'type': 'boolean',
                'description': 'Optional. New all-day flag.',
              },
              'location': {
                'type': 'string',
                'description': 'Optional. New location.',
              },
              'description': {
                'type': 'string',
                'description': 'Optional. New notes/description.',
              },
              'timeZone': {
                'type': 'string',
                'description': 'Optional. iOS-only. New timezone identifier.',
              },
              'calendarId': {
                'type': 'string',
                'description':
                    'Optional. iOS-only. Move event to another calendar.',
              },
              'span': {
                'type': 'string',
                'description':
                    'Optional. iOS-only. For recurring events: thisEvent|futureEvents. Defaults to thisEvent.',
              },
              'alarmMinutes': {
                'description':
                    'Optional. iOS-only. Single number or array. Set alarms at start - N minutes. Empty array clears.',
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
                'description':
                    'Optional. iOS-only. Clear alarms. Default false.',
              },
              'recurrence': {
                'type': 'object',
                'description':
                    'Optional. iOS-only. Simple recurrence rule. See calendar_create_event.',
              },
              'clearRecurrence': {
                'type': 'boolean',
                'description':
                    'Optional. iOS-only. Clear recurrence rules. Default false.',
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

  DateTime? _parseIso(Object? raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  bool? _parseBool(Object? raw) {
    if (raw is bool) return raw;
    final s = raw?.toString().trim().toLowerCase();
    if (s == 'true') return true;
    if (s == 'false') return false;
    return null;
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

    final title = input['title']?.toString().trim();
    final start = _parseIso(input['startIso']);
    final end = _parseIso(input['endIso']);
    final isAllDay = _parseBool(input['isAllDay']);
    final location = input['location']?.toString().trim();
    final description = input['description']?.toString().trim();
    final timeZone = input['timeZone']?.toString().trim();
    final calendarId = input['calendarId']?.toString().trim();
    final span = input['span']?.toString().trim();

    if ((title == null || title.isEmpty) &&
        start == null &&
        end == null &&
        isAllDay == null &&
        (location == null || location.isEmpty) &&
        (description == null || description.isEmpty) &&
        (timeZone == null || timeZone.isEmpty) &&
        (calendarId == null || calendarId.isEmpty) &&
        input['alarmMinutes'] == null &&
        input['clearAlarms'] == null &&
        input['recurrence'] == null &&
        input['clearRecurrence'] == null &&
        (span == null || span.isEmpty)) {
      throw ArgumentError('At least one field must be provided to update');
    }

    if (start != null && end != null && end.isBefore(start)) {
      throw ArgumentError('endIso must be after startIso');
    }

    if (AnxPlatform.isIOS) {
      final args = <String, dynamic>{
        'eventId': eventId,
        if (title != null) 'title': title,
        if (input.containsKey('startIso')) 'startIso': input['startIso'],
        if (input.containsKey('endIso')) 'endIso': input['endIso'],
        if (isAllDay != null) 'isAllDay': isAllDay,
        if (location != null) 'location': location,
        if (description != null) 'description': description,
        if (timeZone != null && timeZone.isNotEmpty) 'timeZone': timeZone,
        if (calendarId != null && calendarId.isNotEmpty)
          'calendarId': calendarId,
        if (span != null && span.isNotEmpty) 'span': span,
        if (input.containsKey('alarmMinutes'))
          'alarmMinutes': input['alarmMinutes'],
        if (input['clearAlarms'] is bool)
          'clearAlarms': input['clearAlarms'] as bool,
        if (input['recurrence'] is Map) 'recurrence': input['recurrence'],
        if (input['clearRecurrence'] is bool)
          'clearRecurrence': input['clearRecurrence'] as bool,
      };

      final raw = await _iosChannel.invokeMethod<Map>('updateEvent', args);
      if (raw == null) {
        throw StateError('Failed to update event');
      }
      return Map<String, dynamic>.from(raw);
    }

    final plugin = DeviceCalendar.instance;
    await _ensurePermissions(plugin);

    await plugin.updateEvent(
      eventId: eventId,
      title: (title != null && title.isNotEmpty) ? title : null,
      startDate: start,
      endDate: end,
      isAllDay: isAllDay,
      location: (location != null && location.isNotEmpty) ? location : null,
      description:
          (description != null && description.isNotEmpty) ? description : null,
      timeZone: (timeZone != null && timeZone.isNotEmpty) ? timeZone : null,
    );

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

final AiToolDefinition calendarUpdateEventToolDefinition = AiToolDefinition(
  id: 'calendar_update_event',
  displayNameBuilder: (L10n l10n) => l10n.aiToolCalendarUpdateEventName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolCalendarUpdateEventDescription,
  riskLevel: AiToolRiskLevel.write,
  build: (context) => CalendarUpdateEventTool().tool,
);
