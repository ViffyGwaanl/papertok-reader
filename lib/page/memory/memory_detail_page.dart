import 'dart:io';

import 'package:anx_reader/page/memory/widgets/tag_editor.dart';
import 'package:anx_reader/service/memory/markdown_memory_store.dart';
import 'package:anx_reader/theme/claude_palette.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown.dart';
import 'package:flutter/material.dart';

/// Detail view for a single Memory entry (either a MEMORY.md section or
/// a daily note). Renders the markdown body via `StyledMarkdown`, shows
/// an inline `TagEditor` at the top that reads/writes YAML front-matter
/// tags on the underlying file.
class MemoryDetailPage extends StatefulWidget {
  final MemoryEntryRef entry;
  final MarkdownMemoryStore store;
  final List<String> allKnownTags;

  const MemoryDetailPage({
    super.key,
    required this.entry,
    required this.store,
    required this.allKnownTags,
  });

  @override
  State<MemoryDetailPage> createState() => _MemoryDetailPageState();
}

class _MemoryDetailPageState extends State<MemoryDetailPage> {
  late Future<_DetailState> _loader;

  @override
  void initState() {
    super.initState();
    _loader = _load();
  }

  Future<_DetailState> _load() async {
    final file = File(widget.entry.path);
    final raw = file.existsSync() ? await file.readAsString() : '';
    final body = _stripFrontMatter(raw);
    final tags = await widget.store.readEntryTags(widget.entry.path);
    return _DetailState(body: body, tags: tags);
  }

  String _stripFrontMatter(String content) {
    if (!content.startsWith('---\n')) return content;
    final endIdx = content.indexOf('\n---\n', 4);
    if (endIdx == -1) return content;
    return content.substring(endIdx + 5);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.entry.title)),
      body: FutureBuilder<_DetailState>(
        future: _loader,
        builder: (context, snap) {
          if (!snap.hasData) {
            return Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ClaudePalette.tertiary(context),
                ),
              ),
            );
          }
          final data = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TagEditor(
                  initial: data.tags,
                  suggestions: widget.allKnownTags,
                  onChanged: (updated) async {
                    await widget.store.writeEntryTags(
                      widget.entry.path,
                      updated,
                    );
                  },
                ),
              ),
              Divider(
                color: ClaudePalette.divider(context),
                thickness: 0.5,
                height: 24,
              ),
              StyledMarkdown(data: data.body),
            ],
          );
        },
      ),
    );
  }
}

class _DetailState {
  final String body;
  final List<String> tags;
  const _DetailState({required this.body, required this.tags});
}
