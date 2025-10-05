import 'dart:async';

import 'base_tool.dart';

class _CurrentTimeInput {
  const _CurrentTimeInput({this.includeTimezone = true});

  final bool includeTimezone;

  factory _CurrentTimeInput.fromJson(Map<String, dynamic> json) {
    final raw = json['include_timezone'] ?? json['includeTimezone'];
    final include = switch (raw) {
      bool value => value,
      String value => value.toLowerCase() == 'true',
      num value => value != 0,
      _ => true,
    };
    return _CurrentTimeInput(includeTimezone: include);
  }
}

class CurrentTimeTool
    extends RepositoryTool<_CurrentTimeInput, Map<String, dynamic>> {
  CurrentTimeTool()
      : super(
          name: 'current_time',
          description:
              'Return the current system time. Optional parameter include_timezone (default true).',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'include_timezone': {
                'type': 'boolean',
                'description':
                    'Whether to include timezone offset information (default true).',
              },
            },
          },
          timeout: const Duration(seconds: 1),
        );

  @override
  _CurrentTimeInput parseInput(Map<String, dynamic> json) {
    return _CurrentTimeInput.fromJson(json);
  }

  @override
  Future<Map<String, dynamic>> run(_CurrentTimeInput input) async {
    final now = DateTime.now();
    final utc = now.toUtc();
    final offset = now.timeZoneOffset;

    return {
      'localIso': now.toIso8601String(),
      'utcIso': utc.toIso8601String(),
      'timestampMs': now.millisecondsSinceEpoch,
      if (input.includeTimezone)
        'timezone': {
          'name': now.timeZoneName,
          'offsetMinutes': offset.inMinutes,
        },
    };
  }
}

final currentTimeTool = CurrentTimeTool().tool;
