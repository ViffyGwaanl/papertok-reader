import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/mcp_server_meta.dart';
import 'package:anx_reader/models/mcp_tool_meta.dart';
import 'package:anx_reader/service/mcp/mcp_client_service.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:flutter/material.dart';

class McpServerDetailPage extends StatefulWidget {
  const McpServerDetailPage({
    super.key,
    required this.serverId,
  });

  final String serverId;

  @override
  State<McpServerDetailPage> createState() => _McpServerDetailPageState();
}

class _McpServerDetailPageState extends State<McpServerDetailPage> {
  McpServerMeta? get _server {
    for (final s in Prefs().mcpServersV1) {
      if (s.id == widget.serverId) return s;
    }
    return null;
  }

  String _formatEpochMs(int epochMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epochMs).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }

  String _cacheStatusText(L10n l10n, McpServerMeta server) {
    final cache = Prefs().getMcpToolsCacheV1(server.id);
    if (cache == null) {
      return l10n.settingsMcpToolsCacheEmpty;
    }

    final count = cache.tools.length;
    final time = _formatEpochMs(cache.updatedAt);
    return l10n.settingsMcpToolsCacheInfo(count, time);
  }

  Future<void> _editServer(McpServerMeta server) async {
    final l10n = L10n.of(context);

    final nameController = TextEditingController(text: server.name);
    final endpointController = TextEditingController(text: server.endpoint);

    final result = await showDialog<McpServerMeta>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.settingsMcpEditServer),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: l10n.settingsMcpServerName,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: endpointController,
                decoration: InputDecoration(
                  labelText: l10n.settingsMcpServerEndpoint,
                  hintText: 'https://example.com/mcp',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final endpoint = endpointController.text.trim();
                if (name.isEmpty || endpoint.isEmpty) {
                  AnxToast.show(l10n.commonInvalid);
                  return;
                }

                final next = server.copyWith(
                  name: name,
                  endpoint: endpoint,
                );
                Navigator.pop(context, next);
              },
              child: Text(l10n.commonConfirm),
            ),
          ],
        );
      },
    );

    nameController.dispose();
    endpointController.dispose();

    if (!mounted || result == null) return;
    Prefs().upsertMcpServer(result);
    setState(() {});
  }

  Future<void> _editHeaders(McpServerMeta server) async {
    final l10n = L10n.of(context);
    final current = Prefs().getMcpServerSecret(server.id).headers;

    final controller = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(current),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.settingsMcpServerHeaders),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.settingsMcpServerHeadersDesc,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
                maxLines: 10,
                minLines: 6,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.commonConfirm),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      controller.dispose();
      return;
    }

    if (ok != true) {
      controller.dispose();
      return;
    }

    try {
      final decoded = jsonDecode(controller.text);
      final headers = <String, String>{};
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          final k = entry.key.toString().trim();
          final v = entry.value?.toString().trim() ?? '';
          if (k.isNotEmpty && v.isNotEmpty) {
            headers[k] = v;
          }
        }
      }

      Prefs().saveMcpServerSecret(server.id, McpServerSecret(headers: headers));
      AnxToast.show(l10n.commonSuccess);
    } catch (_) {
      AnxToast.show(l10n.commonInvalid);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _refreshTools(McpServerMeta server) async {
    final l10n = L10n.of(context);

    try {
      final tools = await McpClientService.instance
          .listTools(server)
          .timeout(const Duration(seconds: 15));
      Prefs().saveMcpToolsCacheV1(server.id, tools);
      if (!mounted) return;
      setState(() {});
      AnxToast.show(l10n.commonSuccess);
    } catch (_) {
      AnxToast.show(l10n.commonFailed);
    }
  }

  Future<void> _clearToolsCache(McpServerMeta server) async {
    final l10n = L10n.of(context);

    final ok = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text(l10n.settingsMcpClearToolsCache),
              content:
                  Text(l10n.settingsMcpClearToolsCacheConfirm(server.name)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l10n.commonCancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(l10n.commonConfirm),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!ok) return;

    Prefs().clearMcpToolsCacheV1(server.id);
    setState(() {});
    AnxToast.show(l10n.commonSuccess);
  }

  Future<void> _showToolDetail(McpToolMeta tool) async {
    final l10n = L10n.of(context);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final schema = tool.inputSchema;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                (tool.title?.trim().isNotEmpty == true)
                    ? tool.title!
                    : tool.name,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              if ((tool.description ?? '').trim().isNotEmpty)
                Text(tool.description!.trim()),
              if ((tool.description ?? '').trim().isNotEmpty)
                const SizedBox(height: 12),
              Text(
                l10n.settingsMcpToolSchema,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SelectableText(
                const JsonEncoder.withIndent('  ').convert(schema ?? const {}),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final server = _server;

    if (server == null) {
      return settingsSections(
        sections: [
          SettingsSection(
            title: Text(l10n.settingsMcpServers),
            tiles: [
              CustomSettingsTile(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l10n.settingsMcpServerNotFound,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    final cache = Prefs().getMcpToolsCacheV1(server.id);
    final tools = (cache?.tools ?? const <McpToolMeta>[])
        .toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));

    return settingsSections(
      sections: [
        SettingsSection(
          title: Text(l10n.settingsMcpServer),
          tiles: [
            CustomSettingsTile(
              child: ListTile(
                title: Text(server.name),
                subtitle: Text(server.endpoint),
                trailing: Switch.adaptive(
                  value: server.enabled,
                  onChanged: (v) {
                    Prefs().upsertMcpServer(server.copyWith(enabled: v));
                    setState(() {});
                  },
                ),
              ),
            ),
            SettingsTile.navigation(
              title: Text(l10n.commonEdit),
              description: Text(l10n.settingsMcpEditServerDesc),
              onPressed: (_) => _editServer(server),
            ),
            SettingsTile.navigation(
              title: Text(l10n.settingsMcpServerHeaders),
              description: Text(l10n.settingsMcpServerHeadersDesc),
              onPressed: (_) => _editHeaders(server),
            ),
          ],
        ),
        SettingsSection(
          title: Text(l10n.settingsMcpToolsTitle(server.name)),
          tiles: [
            CustomSettingsTile(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _cacheStatusText(l10n, server),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            SettingsTile.navigation(
              title: Text(l10n.settingsMcpRefreshTools),
              description: Text(l10n.settingsMcpRefreshToolsDesc),
              onPressed: (_) => _refreshTools(server),
            ),
            SettingsTile.navigation(
              title: Text(l10n.settingsMcpClearToolsCache),
              description: Text(l10n.settingsMcpClearToolsCacheDesc),
              onPressed: (_) => _clearToolsCache(server),
            ),
            if (tools.isEmpty)
              CustomSettingsTile(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l10n.settingsMcpToolsListEmpty,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              )
            else
              for (final t in tools)
                CustomSettingsTile(
                  child: ListTile(
                    title: Text(
                      t.title?.trim().isNotEmpty == true ? t.title! : t.name,
                    ),
                    subtitle: Text(
                      (t.description ?? '').trim().isNotEmpty
                          ? t.description!.trim()
                          : t.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _showToolDetail(t),
                  ),
                ),
          ],
        ),
      ],
    );
  }
}
