import 'dart:convert';

import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/mcp_server_meta.dart';
import 'package:papertok_reader/models/mcp_transport_mode.dart';
import 'package:papertok_reader/service/mcp/mcp_client_service.dart';
import 'package:papertok_reader/utils/page_transitions.dart';
import 'package:papertok_reader/utils/toast/common.dart';
import 'package:papertok_reader/widgets/common/pt_bottom_sheet.dart';
import 'package:papertok_reader/widgets/common/pt_dialog.dart';
import 'package:papertok_reader/widgets/settings/settings_section.dart';
import 'package:papertok_reader/widgets/settings/settings_tile.dart';
import 'package:papertok_reader/page/settings_page/mcp_server_detail_page.dart';
import 'package:papertok_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:papertok_reader/widgets/settings/settings_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

class McpServersSettingsPage extends StatefulWidget {
  const McpServersSettingsPage({super.key});

  @override
  State<McpServersSettingsPage> createState() => _McpServersSettingsPageState();
}

class _McpServersSettingsPageState extends State<McpServersSettingsPage> {
  List<McpServerMeta> get _servers => Prefs().mcpServersV1;

  Future<void> _importFromJson() async {
    final l10n = L10n.of(context);

    final controller = TextEditingController();

    final ok = await PTDialog.show<bool>(
          context,
          title: l10n.settingsMcpImportJson,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.settingsMcpImportJsonDesc,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                minLines: 6,
                maxLines: 12,
              ),
            ],
          ),
          actions: [
            PTDialogAction(
              label: l10n.commonCancel,
              onPressed: () => Navigator.pop(context, false),
            ),
            PTDialogAction(
              label: l10n.commonConfirm,
              isDefault: true,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ) ??
        false;

    if (!ok) {
      controller.dispose();
      return;
    }

    try {
      final decoded = jsonDecode(controller.text);
      int imported = 0;

      Map<String, dynamic>? servers;
      if (decoded is Map) {
        final mcpServers = decoded['mcpServers'];
        if (mcpServers is Map) {
          servers = mcpServers.cast<String, dynamic>();
        }
      }

      if (servers == null) {
        throw const FormatException('mcpServers missing');
      }

      for (final entry in servers.entries) {
        final name = entry.key.toString().trim();
        if (name.isEmpty) continue;

        final raw = entry.value;
        if (raw is! Map) continue;

        final url = raw['url']?.toString().trim() ?? '';
        if (url.isEmpty) continue;

        final type = raw['type']?.toString().trim();

        final id = const Uuid().v4();
        final meta = McpServerMeta(
          id: id,
          name: name,
          endpoint: url,
          enabled: true,
          transportModeV1: McpTransportMode.fromCode(type),
        );
        Prefs().upsertMcpServer(meta);

        final headersRaw = raw['headers'];
        if (headersRaw is Map) {
          final headers = <String, String>{};
          for (final e in headersRaw.entries) {
            final k = e.key.toString().trim();
            final v = e.value?.toString().trim() ?? '';
            if (k.isNotEmpty && v.isNotEmpty) {
              headers[k] = v;
            }
          }
          if (headers.isNotEmpty) {
            Prefs().saveMcpServerSecret(
              id,
              McpServerSecret(headers: headers),
            );
          }
        }

        imported++;
      }

      if (!mounted) return;
      setState(() {});
      AnxToast.show(l10n.settingsMcpImportJsonResult(imported));
    } catch (_) {
      AnxToast.show(l10n.commonInvalid);
    } finally {
      controller.dispose();
    }
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

  Future<void> _clearToolsCache(McpServerMeta server) async {
    final l10n = L10n.of(context);

    final ok = await PTDialog.show<bool>(
          context,
          title: l10n.settingsMcpClearToolsCache,
          message: l10n.settingsMcpClearToolsCacheConfirm(server.name),
          actions: [
            PTDialogAction(
              label: l10n.commonCancel,
              onPressed: () => Navigator.pop(context, false),
            ),
            PTDialogAction(
              label: l10n.commonConfirm,
              destructive: true,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ) ??
        false;

    if (!ok) return;

    Prefs().clearMcpToolsCacheV1(server.id);
    setState(() {});
    AnxToast.show(l10n.commonSuccess);
  }

  Future<void> _refreshAllTools() async {
    final l10n = L10n.of(context);
    final servers = _servers.where((s) => s.enabled).toList(growable: false);
    if (servers.isEmpty) {
      AnxToast.show(l10n.settingsMcpNoEnabledServers);
      return;
    }

    // Show a simple progress dialog. Best-effort; do not block forever.
    if (!mounted) return;
    PTDialog.show<void>(
      context,
      barrierDismissible: false,
      title: l10n.commonRefresh,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 16),
          Text(
            l10n.settingsMcpRefreshingAllTools,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );

    var okCount = 0;
    var failCount = 0;

    for (final s in servers) {
      try {
        final tools = await McpClientService.instance
            .listTools(s)
            .timeout(const Duration(seconds: 12));
        Prefs().saveMcpToolsCacheV1(s.id, tools);
        okCount++;
      } catch (_) {
        failCount++;
      }
    }

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    setState(() {});
    AnxToast.show(l10n.settingsMcpRefreshAllToolsResult(okCount, failCount));
  }

  Future<void> _editServer({McpServerMeta? existing}) async {
    final l10n = L10n.of(context);

    final nameController = TextEditingController(text: existing?.name ?? '');
    final endpointController =
        TextEditingController(text: existing?.endpoint ?? '');

    final result = await PTDialog.show<McpServerMeta>(
      context,
      title: existing == null
          ? l10n.settingsMcpAddServer
          : l10n.settingsMcpEditServer,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameController,
            decoration: InputDecoration(
              labelText: l10n.settingsMcpServerName,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: endpointController,
            decoration: InputDecoration(
              labelText: l10n.settingsMcpServerEndpoint,
              hintText: 'https://example.com/mcp',
            ),
          ),
        ],
      ),
      actions: [
        PTDialogAction(
          label: l10n.commonCancel,
          onPressed: () => Navigator.pop(context),
        ),
        PTDialogAction(
          label: l10n.commonConfirm,
          isDefault: true,
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
        ),
      ],
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

    final ok = await PTDialog.show<bool>(
      context,
      title: l10n.settingsMcpServerHeaders,
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
            maxLines: 10,
            minLines: 6,
          ),
        ],
      ),
      actions: [
        PTDialogAction(
          label: l10n.commonCancel,
          onPressed: () => Navigator.pop(context, false),
        ),
        PTDialogAction(
          label: l10n.commonConfirm,
          isDefault: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
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

      await PTBottomSheet.show<void>(
        context,
        title: l10n.settingsMcpToolsTitle(server.name),
        subtitle: server.endpoint,
        builder: (context) {
          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: ListView(
              children: [
                for (final t in tools)
                  PTPickerRow<String>(
                    value: t.name,
                    groupValue: null,
                    title: t.title?.trim().isNotEmpty == true
                        ? t.title!
                        : t.name,
                    subtitle: t.description ?? '',
                    onChanged: (_) {},
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

    final ok = await PTDialog.show<bool>(
          context,
          title: l10n.settingsMcpDeleteServer,
          message: l10n.settingsMcpDeleteConfirm(server.name),
          actions: [
            PTDialogAction(
              label: l10n.commonCancel,
              onPressed: () => Navigator.pop(context, false),
            ),
            PTDialogAction(
              label: l10n.commonDelete,
              destructive: true,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
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
            onPressed: (_) {
              HapticFeedback.lightImpact();
              _editServer();
            },
          ),
          const Divider(height: 1),
          SettingsTile.navigation(
            title: Text(l10n.settingsMcpRefreshAllTools),
            description: Text(l10n.settingsMcpRefreshAllToolsDesc),
            onPressed: (_) => _refreshAllTools(),
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
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.endpoint),
                    const SizedBox(height: 4),
                    Text(
                      _cacheStatusText(l10n, s),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
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
                          case 'clearToolsCache':
                            _clearToolsCache(s);
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
                          PopupMenuItem(
                            value: 'clearToolsCache',
                            child: Text(l10n.settingsMcpClearToolsCache),
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
                onTap: () {
                  Navigator.push(
                    context,
                    CupertinoStyleRoute(
                      page: SettingsSubpageScaffold(
                        title: s.name,
                        child: McpServerDetailPage(serverId: s.id),
                      ),
                    ),
                  );
                },
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
            SettingsTile.navigation(
              title: Text(l10n.settingsMcpImportJson),
              description: Text(l10n.settingsMcpImportJsonDesc),
              onPressed: (_) => _importFromJson(),
            ),
            const CustomSettingsTile(
              child: Divider(height: 1),
            ),
            listTile,
          ],
        ),
      ],
    );
  }
}
