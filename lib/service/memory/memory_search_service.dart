import 'dart:io';

import 'package:anx_reader/service/memory/markdown_memory_store.dart';
import 'package:anx_reader/service/memory/memory_index_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class MemorySearchService {
  MemorySearchService(
      {MarkdownMemoryStore? store, MemoryIndexDatabase? indexDb})
      : _store = store ?? MarkdownMemoryStore(),
        _indexDb = indexDb ?? MemoryIndexDatabase();

  final MarkdownMemoryStore _store;
  final MemoryIndexDatabase _indexDb;

  static final RegExp _ftsSafeToken = RegExp(r'^[0-9A-Za-z_\u4e00-\u9fff]+$');

  String _escapeFtsToken(String token) {
    if (_ftsSafeToken.hasMatch(token)) return token;

    // Escape embedded quotes for FTS phrase syntax.
    final escaped = token.replaceAll('"', '""');
    return '"$escaped"';
  }

  List<String> _tokenize(String query) {
    final cleaned = query
        .replaceAll(RegExp(r'''["'\[\]\(\)\{\}:;]+'''), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return const [];

    final raw = cleaned.split(' ');
    final out = <String>[];
    for (final t in raw) {
      final s = t.trim();
      if (s.isEmpty) continue;
      if (s.length > 40) {
        out.add(s.substring(0, 40));
      } else {
        out.add(s);
      }
    }
    return out;
  }

  String _buildFtsQuery(String query) {
    final tokens = _tokenize(query);
    if (tokens.isEmpty) return '';
    return tokens.take(12).map(_escapeFtsToken).join(' OR ');
  }

  Future<void> _syncIndex() async {
    await _store.ensureInitialized();

    final db = await _indexDb.database;

    // Collect target files.
    final targets = <File>[];
    targets.add(File(
        p.join(_store.rootDir.path, MarkdownMemoryStore.longTermFileName)));

    final dailyNames = await _store.listDailyFileNames(limit: 5000);
    for (final name in dailyNames) {
      targets.add(File(p.join(_store.rootDir.path, name)));
    }

    final seen = <String>{};

    // Load existing doc metadata.
    final existingRows =
        await db.query('memory_docs', columns: ['doc_id', 'mtime', 'size']);
    final existing = <String, ({int mtime, int size})>{};
    for (final r in existingRows) {
      final id = (r['doc_id'] ?? '').toString();
      final mtime = (r['mtime'] as num?)?.toInt() ?? 0;
      final size = (r['size'] as num?)?.toInt() ?? 0;
      if (id.isNotEmpty) {
        existing[id] = (mtime: mtime, size: size);
      }
    }

    // Update changed/new files.
    for (final file in targets) {
      final name = p.basename(file.path);
      final docId = name;
      seen.add(docId);

      if (!await file.exists()) continue;
      final stat = await file.stat();
      final mtime = stat.modified.millisecondsSinceEpoch;
      final size = stat.size;

      final prev = existing[docId];
      if (prev != null && prev.mtime == mtime && prev.size == size) {
        continue;
      }

      // Rebuild chunks for this doc.
      await db.transaction((txn) async {
        await txn
            .delete('memory_chunks', where: 'doc_id = ?', whereArgs: [docId]);

        final lines = await file.readAsLines();
        final chunks = _chunkLines(lines);
        var idx = 0;
        for (final c in chunks) {
          await txn.insert('memory_chunks', {
            'doc_id': docId,
            'chunk_index': idx++,
            'start_line': c.startLine,
            'end_line': c.endLine,
            'text': c.text,
          });
        }

        final isLongTerm = name.toLowerCase() ==
            MarkdownMemoryStore.longTermFileName.toLowerCase();
        final date = isLongTerm ? null : name.replaceAll('.md', '');

        await txn.insert(
          'memory_docs',
          {
            'doc_id': docId,
            'file_name': name,
            'is_long_term': isLongTerm ? 1 : 0,
            'date': date,
            'mtime': mtime,
            'size': size,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
    }

    // Delete missing docs.
    final missing = existing.keys.where((k) => !seen.contains(k)).toList();
    if (missing.isNotEmpty) {
      await db.transaction((txn) async {
        for (final id in missing) {
          await txn
              .delete('memory_chunks', where: 'doc_id = ?', whereArgs: [id]);
          await txn.delete('memory_docs', where: 'doc_id = ?', whereArgs: [id]);
        }
      });
    }
  }

  Future<List<Map<String, dynamic>>> search(
    String query, {
    int limit = 20,
    bool includeLongTerm = true,
    bool includeDaily = true,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final capped = limit.clamp(1, 100);

    // Try FTS first.
    try {
      await _syncIndex();

      final db = await _indexDb.database;

      // Check FTS availability.
      final ftsTables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='memory_chunks_fts'",
      );
      if (ftsTables.isEmpty) {
        // No FTS: fallback.
        return _store.search(
          q,
          limit: capped,
          includeLongTerm: includeLongTerm,
          includeDaily: includeDaily,
        );
      }

      final ftsQuery = _buildFtsQuery(q);
      if (ftsQuery.isEmpty) {
        return const [];
      }

      final typeFilter = <String>[];
      final args = <Object?>[ftsQuery];

      if (!includeLongTerm) {
        typeFilter.add('d.is_long_term = 0');
      }
      if (!includeDaily) {
        typeFilter.add('d.is_long_term = 1');
      }

      final whereType =
          typeFilter.isEmpty ? '' : 'AND (${typeFilter.join(' AND ')})';

      final rows = await db.rawQuery(
        '''
SELECT
  d.file_name,
  c.start_line,
  c.end_line,
  bm25(memory_chunks_fts) AS bm25,
  snippet(memory_chunks_fts, 0, '', '', '…', 18) AS snippet
FROM memory_chunks_fts
JOIN memory_chunks c ON c.id = memory_chunks_fts.rowid
JOIN memory_docs d ON d.doc_id = c.doc_id
WHERE memory_chunks_fts MATCH ?
  $whereType
ORDER BY bm25
LIMIT ?
''',
        [...args, capped],
      );

      return rows
          .map((r) {
            final file = (r['file_name'] ?? '').toString();
            final start = (r['start_line'] as num?)?.toInt();
            final end = (r['end_line'] as num?)?.toInt();
            final snippet = (r['snippet'] ?? '').toString();
            return {
              'file': file,
              'line': start,
              if (end != null) 'endLine': end,
              'text': snippet,
            };
          })
          .where((h) => (h['file'] ?? '').toString().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      // Best-effort fallback.
      return _store.search(
        q,
        limit: capped,
        includeLongTerm: includeLongTerm,
        includeDaily: includeDaily,
      );
    }
  }

  List<_Chunk> _chunkLines(List<String> lines) {
    final out = <_Chunk>[];

    // Group by paragraphs (blank lines separate).
    final buffer = StringBuffer();
    var currentStartLine = 1;

    void flush(int endLine) {
      final text = buffer.toString().trim();
      buffer.clear();
      if (text.isEmpty) return;

      // Split very long blocks.
      const maxChars = 2200;
      const overlap = 200;
      if (text.length <= maxChars) {
        out.add(
            _Chunk(text: text, startLine: currentStartLine, endLine: endLine));
        return;
      }

      var offset = 0;
      var idx = 0;
      while (offset < text.length) {
        final end = (offset + maxChars).clamp(0, text.length);
        final part = text.substring(offset, end).trim();
        if (part.isNotEmpty) {
          out.add(_Chunk(
            text: part,
            startLine: currentStartLine,
            endLine: endLine,
          ));
          idx++;
        }
        if (end >= text.length) break;
        offset = (end - overlap).clamp(0, text.length);
      }
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineNo = i + 1;

      if (line.trim().isEmpty) {
        flush(lineNo);
        currentStartLine = lineNo + 1;
        continue;
      }

      if (buffer.isEmpty) {
        currentStartLine = lineNo;
      }
      buffer.writeln(line);
    }

    flush(lines.length);

    // Safety: ensure at least one chunk for non-empty files.
    if (out.isEmpty) {
      final joined = lines.join('\n').trim();
      if (joined.isNotEmpty) {
        out.add(_Chunk(text: joined, startLine: 1, endLine: lines.length));
      }
    }

    return out;
  }
}

class _Chunk {
  _Chunk({required this.text, required this.startLine, required this.endLine});

  final String text;
  final int startLine;
  final int endLine;
}
