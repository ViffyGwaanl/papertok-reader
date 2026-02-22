import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/mcp_server_meta.dart';
import 'package:anx_reader/service/mcp/mcp_client_service.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

class McpServersSettingsPage extends StatefulWidget {
  const McpServersSettingsPage({super.key});

  @override
  State<McpServersSettingsPage> createState() => _McpServersSettingsPageState();
}

class _McpServersSettingsPageState extends State<McpServersSettingsPage> {
  List<McpServerMeta> get _servers => Prefs().mcpServersV1;

  Future<void> _editServer({McpServerMeta? existing}) async {
    final l10n = L10n.of(context);

    final nameController = TextEditingController(text: existing?.name ?? '');
    final endpointController =
        TextEditingController(text: existing?.endpoint ?? '');

    final result = await showDialog<McpServerMeta>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(existing == null
              ? l10n.settingsMcpAddServer
              : l10n.settingsMcpEditServer),
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

                final next = McpServerMeta(
                  id: existing?.id ?? const Uuid().v4(),
                  name: name,
                  endpoint: endpoint,
                  enabled: existing?.enabled ?? true,
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
      final tools = await McpClientService.instance.listTools(server);
      Prefs().saveMcpToolsCacheV1(server.id, tools);

      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        builder: (context) {
          return SafeArea(
            child: ListView(
              children: [
                ListTile(
                  title: Text(l10n.settingsMcpToolsTitle(server.name)),
                  subtitle: Text(server.endpoint),
                ),
                const Divider(height: 1),
                for (final t in tools)
                  ListTile(
                    title: Text(
                        t.title?.trim().isNotEmpty == true ? t.title! : t.name),
                    subtitle: Text(t.description ?? ''),
                  ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      AnxToast.show(l10n.commonFailed);
    }
  }

  Future<void> _deleteServer(McpServerMeta server) async {
    final l10n = L10n.of(context);

    final ok = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text(l10n.settingsMcpDeleteServer),
              content: Text(l10n.settingsMcpDeleteConfirm(server.name)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l10n.commonCancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(l10n.commonDelete),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!ok) return;

    Prefs().deleteMcpServer(server.id);
    await McpClientService.instance.closeServer(server.id);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final servers = _servers;

    final listTile = CustomSettingsTile(
      child: Column(
        children: [
          SettingsTile.navigation(
            title: Text(l10n.settingsMcpAddServer),
            description: Text(l10n.settingsMcpAddServerDesc),
            onPressed: (_) => _editServer(),
          ),
          const Divider(height: 1),
          if (servers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.settingsMcpEmpty,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            for (final s in servers) ...[
              ListTile(
                title: Text(s.name),
                subtitle: Text(s.endpoint),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch.adaptive(
                      value: s.enabled,
                      onChanged: (v) {
                        Prefs().upsertMcpServer(s.copyWith(enabled: v));
                        setState(() {});
                      },
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            _editServer(existing: s);
                            break;
                          case 'headers':
                            _editHeaders(s);
                            break;
                          case 'tools':
                            _refreshTools(s);
                            break;
                          case 'delete':
                            _deleteServer(s);
                            break;
                        }
                      },
                      itemBuilder: (context) {
                        return [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text(l10n.commonEdit),
                          ),
                          PopupMenuItem(
                            value: 'headers',
                            child: Text(l10n.settingsMcpServerHeaders),
                          ),
                          PopupMenuItem(
                            value: 'tools',
                            child: Text(l10n.settingsMcpRefreshTools),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(l10n.commonDelete),
                          ),
                        ];
                      },
                    ),
                  ],
                ),
                onTap: () => _editServer(existing: s),
              ),
              const Divider(height: 1),
            ],
        ],
      ),
    );

    return settingsSections(
      sections: [
        SettingsSection(
          title: Text(l10n.settingsMcpServers),
          tiles: [
            listTile,
          ],
        ),
      ],
    );
  }
}
