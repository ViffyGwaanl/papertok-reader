import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/utils/get_path/log_file.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/save_file_to_download.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

class LogPage extends StatefulWidget {
  const LogPage({super.key});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  final TextEditingController _queryController = TextEditingController();

  List<_LogEntry> _entries = const [];
  String _level = 'all';
  String _source = 'all';
  bool _onlyErrors = false;

  @override
  void initState() {
    super.initState();
    initData();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> initData() async {
    final logFile = await getLogFile();
    final lines = logFile.existsSync() ? logFile.readAsLinesSync() : <String>[];
    setState(() {
      _entries = lines.reversed.map(_LogEntry.fromRaw).toList(growable: false);
    });
  }

  List<_LogEntry> _filteredEntries() {
    final query = _queryController.text.trim().toLowerCase();
    return _entries.where((entry) {
      if (_onlyErrors && !_isErrorLevel(entry.log.level)) {
        return false;
      }
      if (_level != 'all' && entry.levelKey != _level) {
        return false;
      }
      if (_source != 'all' && entry.source != _source) {
        return false;
      }
      if (query.isNotEmpty && !entry.searchText.contains(query)) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final filtered = _filteredEntries();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsAdvancedLog),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: initData,
          ),
          IconButton(
            onPressed: () => showMoreAction(context),
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _queryController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.settingsAdvancedLogSearchHint,
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
                  label: l10n.settingsAdvancedLogFilterLevel,
                  value: _level,
                  values: const [
                    'all',
                    'info',
                    'warning',
                    'severe',
                  ],
                  onChanged: (v) => setState(() => _level = v),
                  labelFor: (v) => _levelLabel(l10n, v),
                ),
                _dropdownChip(
                  label: l10n.settingsAdvancedLogFilterSource,
                  value: _source,
                  values: const [
                    'all',
                    'share',
                    'ai',
                    'memory',
                    'sync',
                    'webview',
                    'shortcuts',
                    'reader',
                    'other',
                  ],
                  onChanged: (v) => setState(() => _source = v),
                  labelFor: (v) => _sourceLabel(l10n, v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? Center(child: Text(l10n.settingsAdvancedLogEmpty))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final entry = filtered[index];
                      return _logItem(entry, context);
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

  String _levelLabel(L10n l10n, String value) {
    return switch (value) {
      'all' => l10n.settingsShareInboxFilterAll,
      'info' => l10n.settingsAdvancedLogLevelInfo,
      'warning' => l10n.settingsAdvancedLogLevelWarning,
      'severe' => l10n.settingsAdvancedLogLevelError,
      _ => value,
    };
  }

  String _sourceLabel(L10n l10n, String value) {
    return switch (value) {
      'all' => l10n.settingsShareInboxFilterAll,
      'share' => l10n.settingsAdvancedLogSourceShare,
      'ai' => l10n.settingsAdvancedLogSourceAi,
      'memory' => l10n.settingsAdvancedLogSourceMemory,
      'sync' => l10n.settingsAdvancedLogSourceSync,
      'webview' => l10n.settingsAdvancedLogSourceWebview,
      'shortcuts' => l10n.settingsAdvancedLogSourceShortcuts,
      'reader' => l10n.settingsAdvancedLogSourceReader,
      'other' => l10n.settingsAdvancedLogSourceOther,
      _ => value,
    };
  }

  void showMoreAction(BuildContext context) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.of(context).size.width,
        MediaQuery.of(context).padding.top + kToolbarHeight,
        0.0,
        0.0,
      ),
      items: [
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.delete),
            title: Text(L10n.of(context).settingsAdvancedLogClearLog),
            onTap: clearLog,
          ),
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: Text(L10n.of(context).settingsAdvancedLogExportLog),
            onTap: exportLog,
          ),
        ),
      ],
    );
  }

  Future<void> clearLog() async {
    Navigator.pop(context);
    AnxLog.clear();
    initData();
  }

  Future<void> exportLog() async {
    Navigator.pop(context);
    final logFile = await getLogFile();
    final fileName =
        'PaperReader-Log-${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}.txt';
    final filePath = await saveFileToDownload(
      bytes: await logFile.readAsBytes(),
      fileName: fileName,
      mimeType: 'text/plain',
    );

    AnxToast.show('saved $filePath');
  }
}

class _LogEntry {
  const _LogEntry({
    required this.raw,
    required this.log,
    required this.levelKey,
    required this.source,
    required this.searchText,
  });

  final String raw;
  final AnxLog log;
  final String levelKey;
  final String source;
  final String searchText;

  factory _LogEntry.fromRaw(String raw) {
    final log = AnxLog.parse(raw);
    final normalizedMessage = log.message.toLowerCase();
    final source = _sourceFor(normalizedMessage);
    return _LogEntry(
      raw: raw,
      log: log,
      levelKey: _levelKeyFor(log.level),
      source: source,
      searchText: [
        log.level.name,
        source,
        log.time.toIso8601String(),
        log.message,
        raw,
      ].join(' ').toLowerCase(),
    );
  }

  static String _levelKeyFor(Level level) {
    if (level == Level.WARNING) return 'warning';
    if (level == Level.SEVERE) return 'severe';
    return 'info';
  }

  static String _sourceFor(String message) {
    if (message.contains('share:')) return 'share';
    if (message.contains('shortcuts:')) return 'shortcuts';
    if (message.contains('memory') || message.contains('review inbox')) {
      return 'memory';
    }
    if (message.contains('webdav') ||
        message.contains('sync:') ||
        message.contains('databasesync:') ||
        message.contains('database sync')) {
      return 'sync';
    }
    if (message.contains('webview')) return 'webview';
    if (message.contains('reader') ||
        message.contains('translation') ||
        message.contains('book')) {
      return 'reader';
    }
    if (message.contains('ai') ||
        message.contains('langchain') ||
        message.contains('provider') ||
        message.contains('openai') ||
        message.contains('gemini') ||
        message.contains('anthropic')) {
      return 'ai';
    }
    return 'other';
  }
}

bool _isErrorLevel(Level level) =>
    level == Level.WARNING || level == Level.SEVERE;

Widget _logItem(_LogEntry entry, BuildContext context) {
  final log = entry.log;
  return SelectionArea(
    child: Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(8, 1, 8, 1),
                decoration: BoxDecoration(
                  color: log.color,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  log.level.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(8, 1, 8, 1),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade100,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(entry.source),
              ),
            ],
          ),
          Text(log.time.toString()),
          const SizedBox(height: 5),
          Text(log.message),
          Row(
            children: [
              const Spacer(),
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: entry.raw));
                },
                child: Text(L10n.of(context).commonCopy),
              ),
            ],
          ),
          const Divider(),
        ],
      ),
    ),
  );
}
