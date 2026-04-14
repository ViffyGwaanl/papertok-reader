import 'dart:io';

import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:path/path.dart' as p;

/// A lightweight reference to a memory entry for browse-list UIs.
class MemoryEntryRef {
  final String title;
  final String path;
  final String preview;
  final DateTime? modified;

  const MemoryEntryRef({
    required this.title,
    required this.path,
    required this.preview,
    required this.modified,
  });
}

/// A lightweight local Markdown memory store.
///
/// Files live under `<documents>/memory/`:
/// - `MEMORY.md` (long-term memory)
/// - `YYYY-MM-DD.md` (daily notes; local timezone)
class MarkdownMemoryStore {
  MarkdownMemoryStore({Directory? rootDir})
      : rootDir = rootDir ?? Directory(getBasePath('memory'));

  final Directory rootDir;

  static const String longTermFileName = 'MEMORY.md';

  String dailyFileName(DateTime date) {
    final local = date.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d.md';
  }

  String dateString(DateTime date) {
    final local = date.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> ensureInitialized({bool ensureToday = true}) async {
    if (!await rootDir.exists()) {
      await rootDir.create(recursive: true);
    }

    final longTerm = File(p.join(rootDir.path, longTermFileName));
    if (!await longTerm.exists()) {
      await longTerm.writeAsString('');
    }

    if (ensureToday) {
      final today = File(p.join(rootDir.path, dailyFileName(DateTime.now())));
      if (!await today.exists()) {
        await today.writeAsString('');
      }
    }
  }

  File _fileFor({required bool longTerm, DateTime? date}) {
    if (longTerm) {
      return File(p.join(rootDir.path, longTermFileName));
    }
    final d = date ?? DateTime.now();
    return File(p.join(rootDir.path, dailyFileName(d)));
  }

  /// Read a memory document.
  Future<String> read({required bool longTerm, DateTime? date}) async {
    await ensureInitialized();
    final f = _fileFor(longTerm: longTerm, date: date);
    if (!await f.exists()) {
      await f.create(recursive: true);
      await f.writeAsString('');
    }
    return f.readAsString();
  }

  /// Replace a memory document.
  Future<void> replace({
    required bool longTerm,
    DateTime? date,
    required String text,
  }) async {
    await ensureInitialized();
    final f = _fileFor(longTerm: longTerm, date: date);
    await f.writeAsString(text);
  }

  /// Append to a memory document.
  Future<void> append({
    required bool longTerm,
    DateTime? date,
    required String text,
    bool ensureNewlineBefore = true,
  }) async {
    await ensureInitialized();
    final f = _fileFor(longTerm: longTerm, date: date);

    if (!await f.exists()) {
      await f.create(recursive: true);
      await f.writeAsString('');
    }

    final trimmed = text;
    if (trimmed.isEmpty) return;

    final existing = await f.readAsString();
    final needsLeadingNewline =
        ensureNewlineBefore && existing.isNotEmpty && !existing.endsWith('\n');

    final buffer = StringBuffer();
    if (needsLeadingNewline) buffer.write('\n');
    buffer.write(trimmed);
    if (!trimmed.endsWith('\n')) buffer.write('\n');

    await f.writeAsString(buffer.toString(), mode: FileMode.append);
  }

  /// List daily memory files (YYYY-MM-DD.md), newest first.
  Future<List<String>> listDailyFileNames({int limit = 366}) async {
    await ensureInitialized();
    if (!await rootDir.exists()) return const [];

    final files =
        await rootDir.list().where((e) => e is File).cast<File>().where((f) {
      final name = p.basename(f.path);
      return RegExp(r'^\d{4}-\d{2}-\d{2}\.md$').hasMatch(name);
    }).toList();

    files.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));

    final names = files.map((f) => p.basename(f.path)).toList(growable: false);
    if (names.length <= limit) return names;
    return names.sublist(0, limit);
  }

  /// Search all memory markdown files for a query substring (case-insensitive).
  Future<List<Map<String, dynamic>>> search(
    String query, {
    int limit = 20,
    bool includeLongTerm = true,
    bool includeDaily = true,
  }) async {
    await ensureInitialized();

    final q = query.trim();
    if (q.isEmpty) return const [];

    final lower = q.toLowerCase();
    final hits = <Map<String, dynamic>>[];

    final targets = <File>[];
    if (includeLongTerm) {
      targets.add(_fileFor(longTerm: true));
    }
    if (includeDaily) {
      final dailyNames = await listDailyFileNames(limit: 5000);
      for (final name in dailyNames) {
        targets.add(File(p.join(rootDir.path, name)));
      }
    }

    for (final file in targets) {
      if (hits.length >= limit) break;
      if (!await file.exists()) continue;

      final name = p.basename(file.path);
      List<String> lines;
      try {
        lines = await file.readAsLines();
      } catch (_) {
        // Best-effort fallback for weird encodings.
        final raw = await file.readAsString();
        lines = raw.split('\n');
      }

      for (var i = 0; i < lines.length; i++) {
        if (hits.length >= limit) break;
        final line = lines[i];
        if (line.toLowerCase().contains(lower)) {
          hits.add({
            'file': name,
            'line': i + 1,
            'text': line,
          });
        }
      }
    }

    return hits;
  }
}

extension MarkdownMemoryStoreBrowse on MarkdownMemoryStore {
  /// Splits `MEMORY.md` by top-level `#` headings and returns one entry per
  /// section, in document order. Returns an empty list if the file is
  /// missing or has no H1 headings.
  Future<List<MemoryEntryRef>> listLongTermEntries() async {
    final file = File(p.join(rootDir.path, MarkdownMemoryStore.longTermFileName));
    if (!file.existsSync()) return const <MemoryEntryRef>[];
    final raw = await file.readAsString();
    final modified = file.lastModifiedSync();

    final entries = <MemoryEntryRef>[];
    final lines = raw.split('\n');
    String? currentTitle;
    final buf = StringBuffer();

    void flush() {
      if (currentTitle == null) return;
      entries.add(MemoryEntryRef(
        title: currentTitle!,
        path: file.path,
        preview: _browsePreview(buf.toString()),
        modified: modified,
      ));
      buf.clear();
    }

    for (final line in lines) {
      if (line.startsWith('# ')) {
        flush();
        currentTitle = line.substring(2).trim();
      } else if (currentTitle != null) {
        buf.writeln(line);
      }
    }
    flush();

    return entries;
  }

  /// Returns the most recent daily-note files (filenames matching
  /// `YYYY-MM-DD.md`) sorted newest-first, capped at [count].
  Future<List<MemoryEntryRef>> listRecentDailyNotes({int count = 14}) async {
    if (!rootDir.existsSync()) return const <MemoryEntryRef>[];
    final dailyPattern = RegExp(r'^(\d{4}-\d{2}-\d{2})\.md$');
    final files = rootDir
        .listSync()
        .whereType<File>()
        .where((f) => dailyPattern.hasMatch(p.basename(f.path)))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));

    final result = <MemoryEntryRef>[];
    for (final f in files.take(count)) {
      final body = await f.readAsString();
      result.add(MemoryEntryRef(
        title: p.basenameWithoutExtension(f.path),
        path: f.path,
        preview: _browsePreview(body),
        modified: f.lastModifiedSync(),
      ));
    }
    return result;
  }

  String _browsePreview(String body) {
    final trimmed = body.trim();
    if (trimmed.length <= 160) return trimmed;
    return '${trimmed.substring(0, 160)}…';
  }
}
