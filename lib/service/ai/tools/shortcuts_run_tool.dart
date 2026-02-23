import 'dart:async';
import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/ai_tool_risk_level.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/service/shortcuts/shortcuts_callback_service.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'base_tool.dart';

class ShortcutsRunTool extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  ShortcutsRunTool()
      : super(
          name: 'shortcuts_run',
          description:
              'Run an iOS Shortcut via x-callback-url. Requires explicit user approval. Supports returning to the app and optionally receiving a small callback result.',
          inputJsonSchema: const {
            'type': 'object',
            'properties': {
              'name': {
                'type': 'string',
                'description': 'Required. Shortcut name.',
              },
              'input': {
                'type': 'string',
                'enum': ['text', 'clipboard'],
                'description':
                    'Optional. Input source for the shortcut. Defaults to text.',
              },
              'text': {
                'type': 'string',
                'description':
                    'Optional. When input=text, this text will be passed to the shortcut (URL-encoded).',
              },
              'waitForCallback': {
                'type': 'boolean',
                'description':
                    'Optional. If true, wait for a paperreader://shortcuts/* callback and return it. Defaults to true.',
              },
              'callbackTimeoutSec': {
                'type': 'number',
                'description':
                    'Optional. Max seconds to wait for callback when waitForCallback=true. When omitted, uses Settings → AI Tools → Shortcuts callback timeout. Range: 3..300.',
              },
            },
            'required': ['name'],
          },
          timeout: const Duration(seconds: 40),
        );

  @override
  JsonMap parseInput(Map<String, dynamic> json) => json;

  bool _parseBool(Object? raw, bool fallback) {
    if (raw is bool) return raw;
    final s = raw?.toString().trim().toLowerCase();
    if (s == 'true') return true;
    if (s == 'false') return false;
    return fallback;
  }

  int _parseInt(Object? raw, int fallback) {
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  @override
  Future<Map<String, dynamic>> run(JsonMap input) async {
    if (!AnxPlatform.isIOS) {
      throw UnsupportedError('notSupported');
    }

    final name = input['name']?.toString().trim() ?? '';
    if (name.isEmpty) {
      throw ArgumentError('name is required');
    }

    final mode = (input['input']?.toString().trim().toLowerCase()).toString();
    final requestedInputMode = (mode == 'clipboard') ? 'clipboard' : 'text';

    final runId = const Uuid().v4();

    final waitForCallback = _parseBool(input['waitForCallback'], true);
    final defaultTimeout = Prefs().shortcutsCallbackTimeoutSecV1;
    final timeoutSec =
        _parseInt(input['callbackTimeoutSec'], defaultTimeout).clamp(3, 300);

    // To support callbacks reliably, the shortcut must be able to read runId.
    // That means we need to pass a JSON payload as Shortcut Input, therefore we
    // force input=text when waitForCallback=true.
    final effectiveInputMode = waitForCallback ? 'text' : requestedInputMode;

    final payload = <String, dynamic>{
      'runId': runId,
      'text': (input['text']?.toString() ?? ''),
      'inputModeRequested': requestedInputMode,
    };

    final inputText = jsonEncode(payload);

    final successUri = Uri(
      scheme: 'paperreader',
      host: 'shortcuts',
      path: '/success',
      queryParameters: {'runId': runId},
    );
    final cancelUri = Uri(
      scheme: 'paperreader',
      host: 'shortcuts',
      path: '/cancel',
      queryParameters: {'runId': runId},
    );
    final errorUri = Uri(
      scheme: 'paperreader',
      host: 'shortcuts',
      path: '/error',
      queryParameters: {'runId': runId},
    );

    final qp = <String, String>{
      'name': name,
      'input': effectiveInputMode,
      if (effectiveInputMode == 'text') 'text': inputText,
      'x-success': successUri.toString(),
      'x-cancel': cancelUri.toString(),
      'x-error': errorUri.toString(),
    };

    final uri = Uri(
      scheme: 'shortcuts',
      host: 'x-callback-url',
      path: '/run-shortcut',
      queryParameters: qp,
    );

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

    final base = {
      'launched': launched,
      'url': uri.toString(),
      'runId': runId,
      'callbackScheme': 'paperreader',
      'effectiveInputMode': effectiveInputMode,
      'note':
          'To return a result, add an "Open URL" action at the end of your shortcut to open: paperreader://shortcuts/result?runId=<runId>&data=<text> (or dataB64=<base64url>). When waitForCallback=true, the tool forces input=text and passes a JSON payload as Shortcut Input containing runId.',
    };

    if (!waitForCallback) {
      return base;
    }

    final callback = await ShortcutsCallbackService.instance.waitForCallback(
      runId,
      timeout: Duration(seconds: timeoutSec),
    );

    return {
      ...base,
      'callback': callback,
    };
  }

  @override
  bool shouldLogError(Object error) {
    final msg = error.toString();
    return !(msg.contains('notSupported'));
  }
}

final AiToolDefinition shortcutsRunToolDefinition = AiToolDefinition(
  id: 'shortcuts_run',
  displayNameBuilder: (L10n l10n) => l10n.aiToolShortcutsRunName,
  descriptionBuilder: (L10n l10n) => l10n.aiToolShortcutsRunDescription,
  riskLevel: AiToolRiskLevel.write,
  build: (context) => ShortcutsRunTool().tool,
);
