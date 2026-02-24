import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/mcp_server_meta.dart';
import 'package:anx_reader/models/mcp_server_meta.dart' show McpServerSecret;
import 'package:anx_reader/utils/toast/common.dart';
import 'package:flutter/material.dart';

enum McpAuthMode {
  none,
  bearer,
  apiKey,
  basic,
  custom,
}

class McpAuthEditor {
  static McpAuthMode _detectMode(Map<String, String> headers) {
    final auth = headers.entries
        .firstWhere(
          (e) => e.key.toLowerCase() == 'authorization',
          orElse: () => const MapEntry('', ''),
        )
        .value
        .trim();
    if (auth.toLowerCase().startsWith('bearer ')) {
      return McpAuthMode.bearer;
    }
    if (auth.toLowerCase().startsWith('basic ')) {
      return McpAuthMode.basic;
    }
    if (headers.keys.any((k) => k.toLowerCase() == 'x-api-key')) {
      return McpAuthMode.apiKey;
    }
    if (headers.isEmpty) return McpAuthMode.none;
    return McpAuthMode.custom;
  }

  static String _mask(String s) {
    if (s.isEmpty) return '';
    if (s.length <= 8) return '********';
    return '${s.substring(0, 4)}…${s.substring(s.length - 4)}';
  }

  static Future<void> show(
    BuildContext context, {
    required McpServerMeta server,
    required VoidCallback onSaved,
  }) async {
    final l10n = L10n.of(context);

    final secret = Prefs().getMcpServerSecret(server.id);
    final headers = Map<String, String>.from(secret.headers);

    var mode = _detectMode(headers);

    String bearerToken = '';
    String apiKeyHeader = 'x-api-key';
    String apiKeyValue = '';
    String username = '';
    String password = '';
    String customJson = const JsonEncoder.withIndent('  ').convert(headers);

    final auth = headers.entries
        .firstWhere(
          (e) => e.key.toLowerCase() == 'authorization',
          orElse: () => const MapEntry('', ''),
        )
        .value
        .trim();

    if (auth.toLowerCase().startsWith('bearer ')) {
      bearerToken = auth.substring('bearer '.length).trim();
    }

    if (headers.containsKey('x-api-key')) {
      apiKeyHeader = 'x-api-key';
      apiKeyValue = headers['x-api-key'] ?? '';
    }

    final tokenController = TextEditingController(text: bearerToken);
    final apiKeyHeaderController = TextEditingController(text: apiKeyHeader);
    final apiKeyController = TextEditingController(text: apiKeyValue);
    final userController = TextEditingController(text: username);
    final passController = TextEditingController(text: password);
    final customController = TextEditingController(text: customJson);

    Future<void> save() async {
      try {
        final nextHeaders = Map<String, String>.from(headers);

        // Remove common auth headers first.
        nextHeaders.removeWhere((k, _) => k.toLowerCase() == 'authorization');
        nextHeaders.removeWhere((k, _) => k.toLowerCase() == 'x-api-key');

        switch (mode) {
          case McpAuthMode.none:
            // nothing
            break;
          case McpAuthMode.bearer:
            final t = tokenController.text.trim();
            if (t.isEmpty) throw const FormatException('token empty');
            nextHeaders['Authorization'] = 'Bearer $t';
            break;
          case McpAuthMode.apiKey:
            final hn = apiKeyHeaderController.text.trim();
            final kv = apiKeyController.text.trim();
            if (hn.isEmpty || kv.isEmpty) {
              throw const FormatException('api key empty');
            }
            nextHeaders[hn] = kv;
            break;
          case McpAuthMode.basic:
            final u = userController.text;
            final p = passController.text;
            if (u.trim().isEmpty || p.isEmpty) {
              throw const FormatException('basic empty');
            }
            final raw = base64Encode(utf8.encode('$u:$p'));
            nextHeaders['Authorization'] = 'Basic $raw';
            break;
          case McpAuthMode.custom:
            final decoded = jsonDecode(customController.text);
            if (decoded is! Map) throw const FormatException('invalid json');
            nextHeaders.clear();
            for (final e in decoded.entries) {
              final k = e.key.toString().trim();
              final v = e.value?.toString().trim() ?? '';
              if (k.isNotEmpty && v.isNotEmpty) {
                nextHeaders[k] = v;
              }
            }
            break;
        }

        Prefs().saveMcpServerSecret(
            server.id, McpServerSecret(headers: nextHeaders));
        AnxToast.show(l10n.settingsMcpAuthSaved);
        onSaved();
        Navigator.pop(context);
      } catch (_) {
        AnxToast.show(l10n.commonInvalid);
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        Widget modeTile(McpAuthMode m, String title) {
          return RadioListTile<McpAuthMode>(
            value: m,
            groupValue: mode,
            title: Text(title),
            onChanged: (v) {
              if (v == null) return;
              mode = v;
              (context as Element).markNeedsBuild();
            },
          );
        }

        Widget bearerEditor() {
          final masked = _mask(tokenController.text.trim());
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: tokenController,
                decoration: InputDecoration(
                  labelText: l10n.settingsMcpAuthToken,
                  hintText: masked.isEmpty ? '' : masked,
                  border: const OutlineInputBorder(),
                ),
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
              ),
            ],
          );
        }

        Widget apiKeyEditor() {
          return Column(
            children: [
              TextField(
                controller: apiKeyHeaderController,
                decoration: InputDecoration(
                  labelText: l10n.settingsMcpAuthHeaderName,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: apiKeyController,
                decoration: InputDecoration(
                  labelText: l10n.settingsMcpAuthApiKey,
                  border: const OutlineInputBorder(),
                ),
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
              ),
            ],
          );
        }

        Widget basicEditor() {
          return Column(
            children: [
              TextField(
                controller: userController,
                decoration: InputDecoration(
                  labelText: l10n.settingsMcpAuthUsername,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passController,
                decoration: InputDecoration(
                  labelText: l10n.settingsMcpAuthPassword,
                  border: const OutlineInputBorder(),
                ),
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
              ),
            ],
          );
        }

        Widget customEditor() {
          return TextField(
            controller: customController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
            maxLines: 10,
            minLines: 6,
          );
        }

        Widget editor() {
          return switch (mode) {
            McpAuthMode.bearer => bearerEditor(),
            McpAuthMode.apiKey => apiKeyEditor(),
            McpAuthMode.basic => basicEditor(),
            McpAuthMode.custom => customEditor(),
            _ => const SizedBox.shrink(),
          };
        }

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  l10n.settingsMcpAuth,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.settingsMcpAuthDesc,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                modeTile(McpAuthMode.none, l10n.settingsMcpAuthModeNone),
                modeTile(McpAuthMode.bearer, l10n.settingsMcpAuthModeBearer),
                modeTile(McpAuthMode.apiKey, l10n.settingsMcpAuthModeApiKey),
                modeTile(McpAuthMode.basic, l10n.settingsMcpAuthModeBasic),
                modeTile(McpAuthMode.custom, l10n.settingsMcpAuthModeCustom),
                const SizedBox(height: 12),
                editor(),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(l10n.commonCancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: save,
                      child: Text(l10n.commonSave),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    tokenController.dispose();
    apiKeyHeaderController.dispose();
    apiKeyController.dispose();
    userController.dispose();
    passController.dispose();
    customController.dispose();
  }
}
