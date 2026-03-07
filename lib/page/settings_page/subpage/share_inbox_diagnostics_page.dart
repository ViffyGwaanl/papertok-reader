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
  final TextEditingController _queryController = TextEditingController();

  List<ShareInboundEvent> _events = const [];
  String _destination = 'all';
  String _status = 'all';
  String _kind = 'all';
  bool _onlyErrors = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
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

  List<ShareInboundEvent> _filtered() {
    return ShareInboxDiagnosticsStore.filter(
      _events,
      ShareInboxDiagnosticsFilter(
        query: _queryController.text,
        destination: _destination,
        status: _status,
        kind: _kind,
        onlyErrors: _onlyErrors,
      ),
    );
  }

  String _summary(ShareInboundEvent e) {
    return 'text=${e.textLen}, url=${e.urlCount}, img=${e.images}, '
        'files=${e.files} (txt=${e.textFiles}, docx=${e.docxFiles}, '
        'book=${e.bookshelfFiles}, other=${e.otherFiles})';
  }

  String _details(ShareInboundEvent e) {
    final parts = <String>[
      '${e.mode} / ${e.source} / ${e.sourceType}',
      'receive=${e.receiveStatus}, route=${e.routingStatus}, handoff=${e.handoffStatus}, cleanup=${e.cleanupStatus}',
      _summary(e),
      if (e.providerTypes.isNotEmpty)
        'providers: ${e.providerTypes.join(', ')}',
      if (e.urlHosts.isNotEmpty) 'hosts: ${e.urlHosts.join(', ')}',
      if (e.eventIds.isNotEmpty) 'eventId: ${e.eventIds.join(', ')}',
      if (e.failureReason.trim().isNotEmpty) 'error: ${e.failureReason}',
    ];
    return parts.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final filtered = _filtered();

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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _queryController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.settingsShareInboxDiagnosticsSearchHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: Text(l10n.settingsShareInboxFilterOnlyErrors),
                  selected: _onlyErrors,
                  onSelected: (v) => setState(() => _onlyErrors = v),
                ),
                _dropdownChip(
                  label: l10n.settingsShareInboxFilterDestination,
                  value: _destination,
                  values: const [
                    'all',
                    'aiChat',
                    'bookshelf',
                    'askUser',
                    'unknown'
                  ],
                  onChanged: (v) => setState(() => _destination = v),
                  labelFor: (v) => _destinationLabel(l10n, v),
                ),
                _dropdownChip(
                  label: l10n.settingsShareInboxFilterStatus,
                  value: _status,
                  values: const [
                    'all',
                    'pending',
                    'success',
                    'skipped',
                    'cancelled',
                    'error'
                  ],
                  onChanged: (v) => setState(() => _status = v),
                  labelFor: (v) => _statusLabel(l10n, v),
                ),
                _dropdownChip(
                  label: l10n.settingsShareInboxFilterKind,
                  value: _kind,
                  values: const [
                    'all',
                    'web',
                    'docx',
                    'text',
                    'book',
                    'image',
                    'other'
                  ],
                  onChanged: (v) => setState(() => _kind = v),
                  labelFor: (v) => _kindLabel(l10n, v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? Center(child: Text(l10n.settingsShareInboxDiagnosticsEmpty))
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final e = filtered[index];
                      final at = DateTime.fromMillisecondsSinceEpoch(e.atMs);
                      final when =
                          '${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')} '
                          '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

                      return ListTile(
                        title: Text(
                          '$when • ${_destinationLabel(l10n, e.destination)} • ${_statusLabel(l10n, e.overallStatus)}',
                        ),
                        subtitle: Text(_details(e)),
                        isThreeLine: true,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _dropdownChip({
    required String label,
    required String value,
    required List<String> values,
    required ValueChanged<String> onChanged,
    required String Function(String value) labelFor,
  }) {
    return InputChip(
      label: Text('$label: ${labelFor(value)}'),
      onPressed: () async {
        final picked = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (ctx) {
            return SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final item in values)
                    ListTile(
                      title: Text(labelFor(item)),
                      trailing: item == value ? const Icon(Icons.check) : null,
                      onTap: () => Navigator.of(ctx).pop(item),
                    ),
                ],
              ),
            );
          },
        );
        if (picked != null) onChanged(picked);
      },
    );
  }

  String _destinationLabel(L10n l10n, String value) {
    return switch (value) {
      'all' => l10n.settingsShareInboxFilterAll,
      'aiChat' => l10n.settingsShareInboxFilterDestinationAi,
      'bookshelf' => l10n.settingsShareInboxFilterDestinationBookshelf,
      'askUser' => l10n.settingsShareInboxFilterDestinationAsk,
      _ => value,
    };
  }

  String _statusLabel(L10n l10n, String value) {
    return switch (value) {
      'all' => l10n.settingsShareInboxFilterAll,
      'pending' => l10n.settingsShareInboxFilterStatusPending,
      'success' => l10n.settingsShareInboxFilterStatusSuccess,
      'skipped' => l10n.settingsShareInboxFilterStatusSkipped,
      'cancelled' => l10n.settingsShareInboxFilterStatusCancelled,
      'error' => l10n.settingsShareInboxFilterStatusError,
      _ => value,
    };
  }

  String _kindLabel(L10n l10n, String value) {
    return switch (value) {
      'all' => l10n.settingsShareInboxFilterAll,
      'web' => l10n.settingsShareInboxFilterKindWeb,
      'docx' => l10n.settingsShareInboxFilterKindDocx,
      'text' => l10n.settingsShareInboxFilterKindText,
      'book' => l10n.settingsShareInboxFilterKindBook,
      'image' => l10n.settingsShareInboxFilterKindImage,
      'other' => l10n.settingsShareInboxFilterKindOther,
      _ => value,
    };
  }
}
