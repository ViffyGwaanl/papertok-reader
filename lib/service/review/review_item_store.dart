import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:path/path.dart' as p;

class ReviewItemStore {
  ReviewItemStore({Directory? rootDir})
      : rootDir = rootDir ?? MarkdownMemoryStore().rootDir;

  static const _sourceTypesWithApplyAdapters = {
    ReviewItemSourceType.knowledgeCard,
    ReviewItemSourceType.conceptGraphRelation,
    ReviewItemSourceType.flashcardCandidate,
  };

  final Directory rootDir;
  Future<void> _tail = Future<void>.value();

  Directory get workflowDir => Directory(p.join(rootDir.path, '.workflow'));
  File get inboxFile => File(p.join(workflowDir.path, 'review_items_v1.json'));

  Future<void> ensureInitialized() async {
    if (!await workflowDir.exists()) {
      await workflowDir.create(recursive: true);
    }
    if (!await inboxFile.exists()) {
      await inboxFile.writeAsString(_encode(const <ReviewItem>[]));
    }
  }

  Future<List<ReviewItem>> list({
    ReviewItemStatus? status,
    ReviewItemSourceType? sourceType,
  }) {
    return _enqueue(() async {
      final items = await _readAllUnlocked();
      final filtered = items.where((item) {
        if (status != null && item.status != status) return false;
        if (sourceType != null && item.sourceType != sourceType) return false;
        return true;
      }).toList();
      filtered.sort((a, b) => _sortTimestamp(b).compareTo(_sortTimestamp(a)));
      return filtered;
    });
  }

  Future<ReviewItem?> getById(String id) {
    return _enqueue(() async {
      final items = await _readAllUnlocked();
      for (final item in items) {
        if (item.id == id) return item;
      }
      return null;
    });
  }

  Future<ReviewItem> upsert(ReviewItem item) {
    if (item.status != ReviewItemStatus.draft &&
        item.status != ReviewItemStatus.pending) {
      throw ArgumentError(
        'ReviewItemStore.upsert only accepts draft/pending items; '
        'use approve/dismiss/apply for review decisions.',
      );
    }
    return _enqueue(() async {
      final items = await _readAllUnlocked();
      final index = items.indexWhere((i) => i.id == item.id);
      if (index >= 0) {
        items[index] = item;
      } else {
        items.add(item);
      }
      await _writeAllUnlocked(items);
      return item;
    });
  }

  Future<ReviewItem> submit(String id, {int? now}) {
    return _transition(
      id,
      ReviewItemStatus.pending,
      now: now,
      decisionSource: null,
    );
  }

  Future<ReviewItem> approve(
    String id, {
    int? now,
    String decisionSource = 'user_approve',
  }) {
    return _transition(
      id,
      ReviewItemStatus.approved,
      now: now,
      decisionSource: decisionSource,
    );
  }

  Future<ReviewItem> dismiss(
    String id, {
    int? now,
    String decisionSource = 'user_dismiss',
  }) {
    return _transition(
      id,
      ReviewItemStatus.dismissed,
      now: now,
      decisionSource: decisionSource,
    );
  }

  Future<ReviewItem> apply(
    String id, {
    int? now,
    String decisionSource = 'user_apply',
  }) {
    return _transition(
      id,
      ReviewItemStatus.applied,
      now: now,
      decisionSource: decisionSource,
    );
  }

  Future<ReviewItem> applyResolvedSyncConflict(
    String id, {
    int? now,
    String decisionSource = 'user_apply',
  }) {
    return _transition(
      id,
      ReviewItemStatus.applied,
      now: now,
      decisionSource: decisionSource,
      allowResolvedSyncConflict: true,
    );
  }

  Future<ReviewItem> applyResolvedMemoryCandidate(
    String id, {
    int? now,
    String decisionSource = 'user_apply',
  }) {
    return _transition(
      id,
      ReviewItemStatus.applied,
      now: now,
      decisionSource: decisionSource,
      allowResolvedMemoryCandidate: true,
    );
  }

  Future<ReviewItem> _transition(
    String id,
    ReviewItemStatus next, {
    int? now,
    required String? decisionSource,
    bool allowResolvedSyncConflict = false,
    bool allowResolvedMemoryCandidate = false,
  }) {
    return _enqueue(() async {
      final items = await _readAllUnlocked();
      final index = items.indexWhere((item) => item.id == id);
      if (index < 0) {
        throw StateError('Review item not found: $id');
      }
      if (next == ReviewItemStatus.applied &&
          !_canApplySource(
            items[index],
            allowResolvedSyncConflict: allowResolvedSyncConflict,
            allowResolvedMemoryCandidate: allowResolvedMemoryCandidate,
          )) {
        throw UnsupportedError(
          'Review item source ${items[index].sourceType.asString} cannot be '
          'applied without a source-specific adapter.',
        );
      }
      final timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
      final updated = items[index].transitionTo(
        next,
        now: timestamp,
        decisionSource: decisionSource,
      );
      items[index] = updated;
      await _writeAllUnlocked(items);
      return updated;
    });
  }

  Future<List<ReviewItem>> _readAllUnlocked() async {
    await ensureInitialized();
    final raw = await inboxFile.readAsString();
    if (raw.trim().isEmpty) return <ReviewItem>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final list = decoded['items'];
        if (list is List) {
          return list
              .whereType<Map>()
              .map((item) => ReviewItem.fromJson(
                    Map<String, dynamic>.from(item.cast<String, dynamic>()),
                  ))
              .toList();
        }
      }
    } catch (_) {
      // Treat malformed local workflow state as an empty inbox.
    }
    return <ReviewItem>[];
  }

  Future<void> _writeAllUnlocked(List<ReviewItem> items) async {
    await ensureInitialized();
    await inboxFile.writeAsString(_encode(items));
  }

  String _encode(List<ReviewItem> items) {
    final payload = <String, dynamic>{
      'version': 1,
      'items': items.map((item) => item.toJson()).toList(growable: false),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  int _sortTimestamp(ReviewItem item) {
    return item.createdAt ?? item.updatedAt ?? 0;
  }

  bool _canApplySource(
    ReviewItem item, {
    required bool allowResolvedSyncConflict,
    required bool allowResolvedMemoryCandidate,
  }) {
    if (item.sourceType == ReviewItemSourceType.syncConflict) {
      return allowResolvedSyncConflict && item.payload['canApply'] == true;
    }
    if (item.sourceType == ReviewItemSourceType.memoryCandidate) {
      return allowResolvedMemoryCandidate;
    }
    return _sourceTypesWithApplyAdapters.contains(item.sourceType);
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
