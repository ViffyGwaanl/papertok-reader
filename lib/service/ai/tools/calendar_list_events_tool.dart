import 'dart:async';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:device_calendar_plus/device_calendar_plus.dart';

import 'base_tool.dart';

class CalendarListEventsTool
    extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  CalendarListEventsTool()
      : super(
          name: 'calendar_list_events',
          description:
              'List upcoming calendar events within a date range. Returns a compact list including title, start/end, allDay, location, calendarId, instanceId.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'startIso': {
                'type': 'string',
                'description':
                    'Optional. ISO-8601 start datetime. Defaults to now.',
              },
              'endIso': {
                'type': 'string',
                'description':
                    'Optional. ISO-8601 end datetime. Defaults to start+7 days.',
              },
              'days': {
                'type': 'number',
                'description':
                    'Optional. When endIso is omitted, end = start + days. Defaults to 7. Range: 1..60.',
              },
              'calendarIds': {
                'type': 'array',
                'items': {'type': 'string'},
                'description':
                    'Optional. Restrict results to specific calendar ids.',
              },
              'maxResults': {
                'type': 'number',
                'description':
                    'Optional. Truncate results to this count. Defaults to 50. Max 200.',
              },
              'includeDescription': {
                'type': 'boolean',
                'description':
                    'Optional. Include event description/notes (may be long). Defaults to false.',
              },
            },
          },
          timeout: const Duration(seconds: 10),
        );

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

  int _parseInt(Object? raw, int fallback) {
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? fallback;
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

    final plugin = DeviceCalendar.instance;
    await _ensurePermissions(plugin);

    final start = _parseIso(input['startIso']) ?? DateTime.now();

    final days = _parseInt(input['days'], 7).clamp(1, 60);
    final end = _parseIso(input['endIso']) ?? start.add(Duration(days: days));

    final maxResults = _parseInt(input['maxResults'], 50).clamp(1, 200);
    final includeDescription = _parseBool(input['includeDescription'], false);

    final calendarIdsRaw = input['calendarIds'];
    final calendarIds = (calendarIdsRaw is List)
        ? calendarIdsRaw
            .map((e) => e?.toString().trim() ?? '')
            .where((e) => e.isNotEmpty)
            .toList(growable: false)
        : const <String>[];

    final events = await plugin.listEvents(
      start,
      end,
      calendarIds: calendarIds.isEmpty ? null : calendarIds,
    );

    final sorted = [...events]..sort((a, b) {
        final as = a.startDate?.millisecondsSinceEpoch ?? 0;
        final bs = b.startDate?.millisecondsSinceEpoch ?? 0;
        return as.compareTo(bs);
      });

    final truncated = sorted.take(maxResults).toList(growable: false);

    return {
      'startIso': start.toIso8601String(),
      'endIso': end.toIso8601String(),
      'count': truncated.length,
      'truncated': truncated.length != sorted.length,
      'events': truncated
          .map(
            (e) => {
              'title': e.title,
              'startIso': e.startDate?.toIso8601String(),
              'endIso': e.endDate?.toIso8601String(),
              'allDay': e.isAllDay,
              if (e.location != null && e.location!.trim().isNotEmpty)
                'location': e.location,
              if (includeDescription &&
                  e.description != null &&
                  e.description!.trim().isNotEmpty)
                'description': e.description,
              'calendarId': e.calendarId,
              'eventId': e.eventId,
              'instanceId': e.instanceId,
            },
          )
          .toList(growable: false),
    };
  }

  @override
  bool shouldLogError(Object error) {
    final msg = error.toString();
    return !(msg.contains('permissionDenied') || msg.contains('notSupported'));
  }
}

final AiToolDefinition calendarListEventsToolDefinition = AiToolDefinition(
  id: 'calendar_list_events',
  displayNameBuilder: (L10n l10n) => l10n.aiToolCalendarListEventsName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolCalendarListEventsDescription,
  build: (context) => CalendarListEventsTool().tool,
);
