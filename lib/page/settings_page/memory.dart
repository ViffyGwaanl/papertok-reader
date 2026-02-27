import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:anx_reader/providers/ai_draft_input.dart';
import 'package:anx_reader/service/memory/markdown_memory_store.dart';
import 'package:anx_reader/service/memory/memory_search_service.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MemorySettingsPage extends StatelessWidget {
  const MemorySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSubpageScaffold(
      title: L10n.of(context).settingsMemory,
      child: const _MemorySettingsBody(),
    );
  }
}

class _MemorySettingsBody extends ConsumerStatefulWidget {
  const _MemorySettingsBody();

  @override
  ConsumerState<_MemorySettingsBody> createState() =>
      _MemorySettingsBodyState();
}

class _MemorySettingsBodyState extends ConsumerState<_MemorySettingsBody> {
  final _store = MarkdownMemoryStore();
  final TextEditingController _searchController = TextEditingController();

  bool _searching = false;
  List<Map<String, dynamic>> _hits = const [];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _hits = const [];
      });
      return;
    }

    setState(() {
      _searching = true;
    });

    try {
      final prefs = Prefs();
      final service = MemorySearchService(
        store: _store,
        semanticEnabled: prefs.memorySemanticSearchEnabledEffective,
        embeddingProviderId: prefs.aiLibraryIndexProviderIdEffective,
        embeddingModel: prefs.aiLibraryIndexEmbeddingModelEffective,
        embeddingsTimeoutSeconds: prefs.aiLibraryIndexEmbeddingsTimeoutSeconds,
        hybridEnabled: prefs.memorySearchHybridEnabled,
        vectorWeight: prefs.memorySearchHybridVectorWeight,
        textWeight: prefs.memorySearchHybridTextWeight,
        candidateMultiplier: prefs.memorySearchHybridCandidateMultiplier,
      );

      final hits = await service.search(query, limit: 50);
      if (!mounted) return;
      setState(() {
        _hits = hits;
      });
    } catch (e) {
      if (!mounted) return;
      AnxToast.show('${L10n.of(context).memorySearchFailed}: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        _searching = false;
      });
    }
  }

  void _openEditorForFileName(String fileName) {
    final lower = fileName.toLowerCase();
    final isLongTerm =
        lower == MarkdownMemoryStore.longTermFileName.toLowerCase();

    DateTime? date;
    if (!isLongTerm) {
      // Parse YYYY-MM-DD.md
      final base = fileName.replaceAll('.md', '');
      final parts = base.split('-');
      if (parts.length == 3) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final d = int.tryParse(parts[2]);
        if (y != null && m != null && d != null) {
          date = DateTime(y, m, d);
        }
      }
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemoryEditorPage(
          store: _store,
          longTerm: isLongTerm,
          date: date,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final todayLabel = _store.dailyFileName(DateTime.now());

    final prefs = Prefs();
    final semanticOverride = prefs.memorySemanticSearchEnabledOverride;
    final semanticEffective = prefs.memorySemanticSearchEnabledEffective;

    const candidateChoices = <int>[2, 3, 4, 6, 8, 12];
    final candidateMultiplier = candidateChoices.contains(
      prefs.memorySearchHybridCandidateMultiplier,
    )
        ? prefs.memorySearchHybridCandidateMultiplier
        : 4;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: l10n.memorySearchLabel,
              hintText: l10n.memorySearchHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: l10n.memorySearchAction,
                icon: _searching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward),
                onPressed: _searching ? null : _runSearch,
              ),
            ),
            onSubmitted: (_) => _runSearch(),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Text(l10n.memorySemanticSearchTitle),
          subtitle: Text(
            semanticOverride == null
                ? (semanticEffective
                    ? l10n.memorySemanticSearchAutoOn
                    : l10n.memorySemanticSearchAutoOff)
                : l10n.memorySemanticSearchManual,
          ),
          value: semanticEffective,
          onChanged: (v) {
            setState(() {
              prefs.memorySemanticSearchEnabledOverride = v;
            });
          },
          secondary: const Icon(Icons.auto_awesome),
        ),
        if (semanticOverride != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  setState(() {
                    prefs.memorySemanticSearchEnabledOverride = null;
                  });
                },
                child: Text(l10n.memorySemanticSearchResetAuto),
              ),
            ),
          ),
        ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Text(l10n.memorySearchAdvancedTitle),
          children: [
            SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: Text(l10n.memorySearchHybridEnabledTitle),
              subtitle: Text(l10n.memorySearchHybridEnabledDesc),
              value: prefs.memorySearchHybridEnabled,
              onChanged: (v) {
                setState(() {
                  prefs.memorySearchHybridEnabled = v;
                });
              },
            ),
            ListTile(
              title: Text(l10n.memorySearchVectorWeightTitle),
              subtitle: Text(
                l10n.memorySearchVectorWeightValue(
                  (prefs.memorySearchHybridVectorWeight * 100).round(),
                  (prefs.memorySearchHybridTextWeight * 100).round(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Slider(
                value: prefs.memorySearchHybridVectorWeight,
                min: 0,
                max: 1,
                divisions: 20,
                label: prefs.memorySearchHybridVectorWeight.toStringAsFixed(2),
                onChanged: (v) {
                  setState(() {
                    prefs.memorySearchHybridVectorWeight = v;
                    prefs.memorySearchHybridTextWeight = 1 - v;
                  });
                },
              ),
            ),
            ListTile(
              title: Text(l10n.memorySearchCandidateMultiplierTitle),
              trailing: DropdownButton<int>(
                value: candidateMultiplier,
                items: candidateChoices
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text('x$v'),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    prefs.memorySearchHybridCandidateMultiplier = v;
                  });
                },
              ),
            ),
          ],
        ),
        if (_hits.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              l10n.memorySearchResults,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ..._hits.map((hit) {
            final file = (hit['file'] ?? '').toString();
            final line = hit['line'];
            final text = (hit['text'] ?? '').toString();
            return ListTile(
              dense: true,
              leading: const Icon(Icons.find_in_page_outlined),
              title: Text(file),
              subtitle: Text(
                line == null ? text : 'L$line: $text',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _openEditorForFileName(file),
            );
          }),
          const Divider(),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            l10n.memoryFilesTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.bookmark_outline),
          title: Text(MarkdownMemoryStore.longTermFileName),
          subtitle: Text(l10n.memoryLongTermSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              _openEditorForFileName(MarkdownMemoryStore.longTermFileName),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.today_outlined),
          title: Text(todayLabel),
          subtitle: Text(l10n.memoryTodaySubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openEditorForFileName(todayLabel),
        ),
        const Divider(height: 1),
        FutureBuilder<List<String>>(
          future: _store.listDailyFileNames(limit: 60),
          builder: (context, snapshot) {
            final data = snapshot.data ?? const [];
            if (data.isEmpty) {
              return const SizedBox();
            }

            // Skip today if already shown.
            final files = data.where((f) => f != todayLabel).toList();

            return Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        l10n.memoryDailyTitle,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const Spacer(),
                      Text(
                        l10n.memoryDailyCount(files.length),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Theme.of(context).hintColor),
                      ),
                    ],
                  ),
                ),
                ...files.map((name) {
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.description_outlined, size: 20),
                    title: Text(name),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openEditorForFileName(name),
                  );
                }),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class MemoryEditorPage extends ConsumerStatefulWidget {
  const MemoryEditorPage({
    super.key,
    required this.store,
    required this.longTerm,
    this.date,
  });

  final MarkdownMemoryStore store;
  final bool longTerm;
  final DateTime? date;

  @override
  ConsumerState<MemoryEditorPage> createState() => _MemoryEditorPageState();
}

class _MemoryEditorPageState extends ConsumerState<MemoryEditorPage> {
  late final TextEditingController _controller = TextEditingController();
  bool _loading = true;
  bool _dirty = false;

  String get _fileName {
    return widget.longTerm
        ? MarkdownMemoryStore.longTermFileName
        : widget.store.dailyFileName(widget.date ?? DateTime.now());
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (!_dirty && !_loading) {
        setState(() {
          _dirty = true;
        });
      }
    });
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _dirty = false;
    });

    final text = await widget.store.read(
      longTerm: widget.longTerm,
      date: widget.date,
    );

    if (!mounted) return;
    _controller.text = text;

    setState(() {
      _loading = false;
      _dirty = false;
    });
  }

  Future<void> _save() async {
    await widget.store.replace(
      longTerm: widget.longTerm,
      date: widget.date,
      text: _controller.text,
    );

    if (!mounted) return;
    setState(() {
      _dirty = false;
    });

    AnxToast.show(L10n.of(context).memorySaved);
  }

  void _insertSelectedToAiInput() {
    final sel = _controller.selection;
    if (!sel.isValid || sel.isCollapsed) {
      AnxToast.show(L10n.of(context).memorySelectTextToInsert);
      return;
    }

    final start = sel.start < sel.end ? sel.start : sel.end;
    final end = sel.start < sel.end ? sel.end : sel.start;
    if (start < 0 || end > _controller.text.length) {
      AnxToast.show(L10n.of(context).memorySelectTextToInsert);
      return;
    }

    final selected = _controller.text.substring(start, end);
    ref.read(aiChatDraftInputProvider.notifier).append(selected);
    AnxToast.show(L10n.of(context).memoryInsertedToAiInput);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return WillPopScope(
      onWillPop: () async {
        if (!_dirty) return true;

        final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(l10n.memoryUnsavedTitle),
                content: Text(l10n.memoryUnsavedBody),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(l10n.commonCancel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Text(l10n.memoryDiscard),
                  ),
                ],
              ),
            ) ??
            false;

        return ok;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_fileName),
          actions: [
            IconButton(
              tooltip: l10n.memoryInsertToAiAction,
              icon: const Icon(Icons.input_outlined),
              onPressed: _insertSelectedToAiInput,
            ),
            IconButton(
              tooltip: l10n.commonSave,
              icon: const Icon(Icons.save_outlined),
              onPressed: _loading ? null : _save,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: widget.longTerm
                        ? l10n.memoryLongTermHint
                        : l10n.memoryDailyHint,
                  ),
                  keyboardType: TextInputType.multiline,
                ),
              ),
      ),
    );
  }
}
