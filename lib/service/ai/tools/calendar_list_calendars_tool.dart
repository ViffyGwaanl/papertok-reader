import 'dart:async';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:device_calendar_plus/device_calendar_plus.dart';

import 'base_tool.dart';

class CalendarListCalendarsTool
    extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  CalendarListCalendarsTool()
      : super(
          name: 'calendar_list_calendars',
          description:
              'List available device calendars with id/name/readOnly metadata. Use this tool before creating events to find a writable calendarId.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {},
          },
          timeout: const Duration(seconds: 8),
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

  @override
  Future<Map<String, dynamic>> run(JsonMap input) async {
    if (!AnxPlatform.isIOS && !AnxPlatform.isAndroid) {
      throw UnsupportedError('notSupported');
    }

    final plugin = DeviceCalendar.instance;
    await _ensurePermissions(plugin);

    final calendars = await plugin.listCalendars();

    return {
      'count': calendars.length,
      'calendars': calendars
          .map(
            (c) => {
              'id': c.id,
              'name': c.name,
              'readOnly': c.readOnly,
              if (c.isPrimary != null) 'isPrimary': c.isPrimary,
              if (c.colorHex != null) 'colorHex': c.colorHex,
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

final AiToolDefinition calendarListCalendarsToolDefinition = AiToolDefinition(
  id: 'calendar_list_calendars',
  displayNameBuilder: (L10n l10n) => l10n.aiToolCalendarListCalendarsName,
  descriptionBuilder: (L10n l10n) =>
      l10n.aiToolCalendarListCalendarsDescription,
  build: (context) => CalendarListCalendarsTool().tool,
);
