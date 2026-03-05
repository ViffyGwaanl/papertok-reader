import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:anx_reader/service/receive_file/share_inbox_cleanup_service.dart';
import 'package:anx_reader/service/receive_file/share_inbox_diagnostics.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:flutter/material.dart';

class ShareInboxDiagnosticsPage extends StatefulWidget {
  const ShareInboxDiagnosticsPage({super.key});

  static const String routeName = '/settings/share_inbox_diagnostics';

  @override
  State<ShareInboxDiagnosticsPage> createState() =>
      _ShareInboxDiagnosticsPageState();
}

class _ShareInboxDiagnosticsPageState extends State<ShareInboxDiagnosticsPage> {
  List<ShareInboundEvent> _events = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _events =
          ShareInboxDiagnosticsStore.read().reversed.toList(growable: false);
    });
  }

  Future<void> _cleanupNow() async {
    final l10n = L10n.of(context);
    await ShareInboxCleanupService.cleanupNow();
    AnxToast.show(l10n.commonOk);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return SettingsSubpageScaffold(
      title: l10n.settingsShareInboxDiagnosticsTitle,
      child: Column(
        children: [
          ListTile(
            title: Text(l10n.settingsShareInboxCleanupNowTitle),
            subtitle: Text(
              '${l10n.settingsSharePanelTtlTitle}: ${Prefs().sharePanelTtlDaysV1 == 0 ? l10n.settingsSharePanelTtlNever : l10n.settingsSharePanelTtlDays(Prefs().sharePanelTtlDaysV1)}\n'
              '${l10n.settingsSharePanelCleanupAfterUse}: ${Prefs().sharePanelCleanupAfterUseV1 ? l10n.settingsCommonEnabled : l10n.settingsCommonDisabled}',
            ),
            trailing: FilledButton(
              onPressed: _cleanupNow,
              child: Text(l10n.settingsShareInboxCleanupNowCta),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _events.isEmpty
                ? Center(child: Text(l10n.settingsShareInboxDiagnosticsEmpty))
                : ListView.separated(
                    itemCount: _events.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final e = _events[index];
                      final at = DateTime.fromMillisecondsSinceEpoch(e.atMs);
                      final when =
                          '${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')} '
                          '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

                      final summary =
                          'text=${e.textLen}, img=${e.images}, files=${e.files} '
                          '(txt=${e.textFiles}, docx=${e.docxFiles}, book=${e.bookshelfFiles}, other=${e.otherFiles})';

                      return ListTile(
                        title: Text(
                            '$when • ${e.destination} • ${e.cleanupStatus}'),
                        subtitle: Text(
                          '${e.mode} / ${e.source}\n$summary\n${e.eventIds.isEmpty ? '' : 'eventId: ${e.eventIds.join(', ')}'}',
                        ),
                        isThreeLine: true,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
