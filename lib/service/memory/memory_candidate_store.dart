import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/service/memory/memory_candidate.dart';
import 'package:anx_reader/service/memory/markdown_memory_store.dart';
import 'package:path/path.dart' as p;

class MemoryCandidateStore {
  MemoryCandidateStore({Directory? rootDir})
      : rootDir = rootDir ?? MarkdownMemoryStore().rootDir;

  final Directory rootDir;
  Future<void> _tail = Future<void>.value();

  Directory get workflowDir => Directory(p.join(rootDir.path, '.workflow'));
  File get _v2File => File(p.join(workflowDir.path, 'review_inbox_v2.json'));
  File get _v1File => File(p.join(workflowDir.path, 'review_inbox_v1.json'));
  // inboxFile always points at v2 — kept for backward-compat with any external
  // callers and used by _writeAllUnlocked.
  File get inboxFile => _v2File;

  Future<void> ensureInitialized() async {
    if (!await workflowDir.exists()) {
      await workflowDir.create(recursive: true);
    }
    // Only seed an empty v2 file when neither version exists yet.
    if (!await _v2File.exists() && !await _v1File.exists()) {
      await _v2File.writeAsString(_encode(const <MemoryCandidate>[]));
    }
  }

  Future<List<MemoryCandidate>> list({MemoryCandidateStatus? status}) {
    return _enqueue(() async {
      final candidates = await _readAllUnlocked(allowV1Fallback: true);
      final filtered = status == null
          ? candidates
          : candidates.where((c) => c.status == status).toList();
      filtered.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
      return filtered;
    });
  }

  Future<MemoryCandidate?> getById(String id) {
    return _enqueue(() async {
      final candidates = await _readAllUnlocked(allowV1Fallback: true);
      for (final candidate in candidates) {
        if (candidate.id == id) {
          return candidate;
        }
      }
      return null;
    });
  }

  Future<MemoryCandidate> upsert(MemoryCandidate candidate) {
    return _enqueue(() async {
      final candidates = await _readAllUnlocked();
      final index = candidates.indexWhere((c) => c.id == candidate.id);
      if (index >= 0) {
        candidates[index] = candidate;
      } else {
        candidates.add(candidate);
      }
      await _writeAllUnlocked(candidates);
      return candidate;
    });
  }

  Future<MemoryCandidate> markApplied(
    String id, {
    required MemoryDocTarget targetDoc,
    int? appliedAtMs,
  }) {
    return _updateExisting(id, (candidate) {
      final now = appliedAtMs ?? DateTime.now().millisecondsSinceEpoch;
      return candidate.copyWith(
        appliedTargetDoc: targetDoc,
        status: MemoryCandidateStatus.applied,
        appliedAtMs: now,
        reviewedAtMs: now,
        decisionSource: 'user_apply',
      );
    });
  }

  Future<MemoryCandidate> dismiss(String id) {
    return _updateExisting(id, (candidate) {
      final now = DateTime.now().millisecondsSinceEpoch;
      return candidate.copyWith(
        status: MemoryCandidateStatus.dismissed,
        reviewedAtMs: now,
        dismissedAtMs: now,
        decisionSource: 'user_dismiss',
      );
    });
  }

  Future<MemoryCandidate> _updateExisting(
    String id,
    MemoryCandidate Function(MemoryCandidate current) update,
  ) {
    return _enqueue(() async {
      // Write path: only read v2 so we don't accidentally migrate v1 data.
      final candidates = await _readAllUnlocked();
      final index = candidates.indexWhere((c) => c.id == id);
      if (index < 0) {
        throw StateError('Memory candidate not found: $id');
      }
      final next = update(candidates[index]);
      candidates[index] = next;
      await _writeAllUnlocked(candidates);
      return next;
    });
  }

  /// Reads all candidates from disk.
  ///
  /// When [allowV1Fallback] is true (the default is false), falls back to the
  /// legacy v1 file if v2 does not yet exist — used by read-only operations
  /// (`list`, `getById`) so existing users see their data before any write has
  /// upgraded the store.  Write paths leave [allowV1Fallback] false so the
  /// first mutation starts v2 from a clean slate (no implicit migration).
  Future<List<MemoryCandidate>> _readAllUnlocked({
    bool allowV1Fallback = false,
  }) async {
    await ensureInitialized();

    // Prefer v2; optionally fall back to v1 for read-only display operations.
    final File source;
    if (await _v2File.exists()) {
      source = _v2File;
    } else if (allowV1Fallback && await _v1File.exists()) {
      source = _v1File;
    } else {
      return <MemoryCandidate>[];
    }

    final raw = await source.readAsString();
    if (raw.trim().isEmpty) return <MemoryCandidate>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final list = decoded['candidates'];
        if (list is List) {
          return list
              .whereType<Map>()
              .map((item) => MemoryCandidate.fromJson(
                    Map<String, dynamic>.from(item.cast<String, dynamic>()),
                  ))
              .toList();
        }
      }
    } catch (_) {
      // Fall through to a clean empty state if the workflow file is malformed.
    }
    return <MemoryCandidate>[];
  }

  Future<void> _writeAllUnlocked(List<MemoryCandidate> candidates) async {
    await ensureInitialized();
    await inboxFile.writeAsString(_encode(candidates));
  }

  String _encode(List<MemoryCandidate> candidates) {
    final payload = <String, dynamic>{
      'version': 2,
      'candidates': candidates.map((c) => c.toJson()).toList(growable: false),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
