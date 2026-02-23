import 'dart:async';

import 'package:anx_reader/enums/ai_tool_risk_level.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/services.dart';

import 'base_tool.dart';

class CalendarCreateEventTool
    extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  CalendarCreateEventTool()
      : super(
          name: 'calendar_create_event',
          description:
              'Create a new calendar event on the device. Requires explicit user approval before running.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'title': {
                'type': 'string',
                'description': 'Required. Event title.',
              },
              'startIso': {
                'type': 'string',
                'description': 'Required. ISO-8601 start datetime.',
              },
              'endIso': {
                'type': 'string',
                'description': 'Required. ISO-8601 end datetime.',
              },
              'isAllDay': {
                'type': 'boolean',
                'description': 'Optional. All-day event. Defaults to false.',
              },
              'location': {
                'type': 'string',
                'description': 'Optional. Event location.',
              },
              'description': {
                'type': 'string',
                'description': 'Optional. Event notes/description.',
              },
              'calendarId': {
                'type': 'string',
                'description':
                    'Optional. Target calendar id. When omitted, uses the first writable calendar.',
              },
              'timeZone': {
                'type': 'string',
                'description':
                    'Optional. Timezone identifier (e.g. Asia/Shanghai). iOS-only.',
              },
              'alarmMinutes': {
                'description':
                    'Optional. Single number or array. iOS-only. Add alarms at start - N minutes.',
                'oneOf': [
                  {'type': 'number'},
                  {
                    'type': 'array',
                    'items': {'type': 'number'}
                  },
                ],
              },
              'recurrence': {
                'type': 'object',
                'description':
                    'Optional. iOS-only. Simple recurrence rule. Example: {frequency:"weekly", interval:1, count:10} or {frequency:"daily", interval:1, untilIso:"2026-03-01T00:00:00Z"}.',
                'properties': {
                  'frequency': {
                    'type': 'string',
                    'description': 'daily|weekly|monthly|yearly',
                  },
                  'interval': {
                    'type': 'number',
                    'description': 'Optional. Defaults to 1.',
                  },
                  'count': {
                    'type': 'number',
                    'description':
                        'Optional. Occurrence count. Mutually exclusive with untilIso.',
                  },
                  'untilIso': {
                    'type': 'string',
                    'description':
                        'Optional. End date (ISO-8601). Mutually exclusive with count.',
                  },
                },
              },
            },
            'required': ['title', 'startIso', 'endIso'],
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

  DateTime _parseIsoRequired(Object? raw, String field) {
    final s = raw?.toString().trim() ?? '';
    final parsed = DateTime.tryParse(s);
    if (parsed == null) {
      throw ArgumentError('Invalid $field');
    }
    return parsed;
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

    final title = input['title']?.toString().trim() ?? '';
    if (title.isEmpty) {
      throw ArgumentError('title is required');
    }

    final start = _parseIsoRequired(input['startIso'], 'startIso');
    final end = _parseIsoRequired(input['endIso'], 'endIso');

    if (end.isBefore(start)) {
      throw ArgumentError('endIso must be after startIso');
    }

    final isAllDay = _parseBool(input['isAllDay'], false);

    final desiredCalendarId = input['calendarId']?.toString().trim() ?? '';

    if (AnxPlatform.isIOS) {
      final args = <String, dynamic>{
        'title': title,
        'startIso': start.toIso8601String(),
        'endIso': end.toIso8601String(),
        'isAllDay': isAllDay,
        if ((input['location']?.toString().trim() ?? '').isNotEmpty)
          'location': input['location']?.toString(),
        if ((input['description']?.toString().trim() ?? '').isNotEmpty)
          'description': input['description']?.toString(),
        if (desiredCalendarId.isNotEmpty) 'calendarId': desiredCalendarId,
        if ((input['timeZone']?.toString().trim() ?? '').isNotEmpty)
          'timeZone': input['timeZone']?.toString(),
        if (input.containsKey('alarmMinutes'))
          'alarmMinutes': input['alarmMinutes'],
        if (input['recurrence'] is Map) 'recurrence': input['recurrence'],
      };

      final raw = await _iosChannel.invokeMethod<Map>('createEvent', args);
      if (raw == null) {
        throw StateError('Failed to create event');
      }

      return Map<String, dynamic>.from(raw);
    }

    final plugin = DeviceCalendar.instance;
    await _ensurePermissions(plugin);

    String calendarId;
    if (desiredCalendarId.isNotEmpty) {
      calendarId = desiredCalendarId;
    } else {
      final calendars = await plugin.listCalendars();
      final writable = calendars.where((c) => c.readOnly != true).toList();
      final picked = writable.isNotEmpty ? writable.first : calendars.first;
      if (picked.id == null || picked.id!.trim().isEmpty) {
        throw StateError('No writable calendar found');
      }
      calendarId = picked.id!;
    }

    final eventId = await plugin.createEvent(
      calendarId: calendarId,
      title: title,
      startDate: start,
      endDate: end,
      isAllDay: isAllDay,
      location: input['location']?.toString(),
      description: input['description']?.toString(),
    );

    return {
      'calendarId': calendarId,
      'eventId': eventId,
      'title': title,
      'startIso': start.toIso8601String(),
      'endIso': end.toIso8601String(),
      'allDay': isAllDay,
    };
  }

  @override
  bool shouldLogError(Object error) {
    final msg = error.toString();
    return !(msg.contains('permissionDenied') || msg.contains('notSupported'));
  }
}

final AiToolDefinition calendarCreateEventToolDefinition = AiToolDefinition(
  id: 'calendar_create_event',
  displayNameBuilder: (L10n l10n) => l10n.aiToolCalendarCreateEventName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolCalendarCreateEventDescription,
  riskLevel: AiToolRiskLevel.write,
  build: (context) => CalendarCreateEventTool().tool,
);
