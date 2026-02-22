import 'dart:async';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:url_launcher/url_launcher.dart';

import 'base_tool.dart';

class ShortcutsRunTool extends RepositoryTool<JsonMap, Map<String, dynamic>> {
  ShortcutsRunTool()
      : super(
          name: 'shortcuts_run',
          description:
              'Run an iOS Shortcut via URL scheme. Requires explicit user approval. Input can be text or clipboard.',
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
            },
            'required': ['name'],
          },
          timeout: const Duration(seconds: 8),
        );

  @override
  JsonMap parseInput(Map<String, dynamic> json) => json;

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
    final inputMode = (mode == 'clipboard') ? 'clipboard' : 'text';

    final qp = <String, String>{
      'name': name,
      'input': inputMode,
    };

    if (inputMode == 'text') {
      final text = input['text']?.toString() ?? '';
      qp['text'] = text;
    }

    final uri = Uri(
      scheme: 'shortcuts',
      host: 'run-shortcut',
      queryParameters: qp,
    );

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);

    return {
      'launched': ok,
      'url': uri.toString(),
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
  requiresApproval: true,
  build: (context) => ShortcutsRunTool().tool,
);
