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
  File get inboxFile => File(p.join(workflowDir.path, 'review_inbox_v1.json'));

  Future<void> ensureInitialized() async {
    if (!await workflowDir.exists()) {
      await workflowDir.create(recursive: true);
    }
    if (!await inboxFile.exists()) {
      await inboxFile.writeAsString(_encode(const <MemoryCandidate>[]));
    }
  }

  Future<List<MemoryCandidate>> list({MemoryCandidateStatus? status}) {
    return _enqueue(() async {
      final candidates = await _readAllUnlocked();
      final filtered = status == null
          ? candidates
          : candidates.where((c) => c.status == status).toList();
      filtered.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
      return filtered;
    });
  }

  Future<MemoryCandidate?> getById(String id) {
    return _enqueue(() async {
      final candidates = await _readAllUnlocked();
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
      return candidate.copyWith(
        targetDoc: targetDoc,
        status: MemoryCandidateStatus.applied,
        appliedAtMs: appliedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      );
    });
  }

  Future<MemoryCandidate> dismiss(String id) {
    return _updateExisting(id, (candidate) {
      return candidate.copyWith(status: MemoryCandidateStatus.dismissed);
    });
  }

  Future<MemoryCandidate> _updateExisting(
    String id,
    MemoryCandidate Function(MemoryCandidate current) update,
  ) {
    return _enqueue(() async {
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

  Future<List<MemoryCandidate>> _readAllUnlocked() async {
    await ensureInitialized();
    final raw = await inboxFile.readAsString();
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
      'version': 1,
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
