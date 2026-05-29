import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';
import 'package:path/path.dart' as p;

enum SpacedReviewRating {
  again('again'),
  hard('hard'),
  good('good'),
  easy('easy');

  const SpacedReviewRating(this.asString);

  final String asString;
}

class SpacedReviewStore {
  SpacedReviewStore({Directory? rootDir})
      : rootDir = rootDir ?? MarkdownMemoryStore().rootDir;

  static String reviewIdForCard(String cardId) {
    return 'spaced-review:knowledge-card:$cardId';
  }

  static String reviewIdForFlashcard(String flashcardId) {
    return 'spaced-review:flashcard:$flashcardId';
  }

  final Directory rootDir;
  Future<void> _tail = Future<void>.value();

  Directory get knowledgeDir => Directory(p.join(rootDir.path, '.knowledge'));
  File get reviewFile =>
      File(p.join(knowledgeDir.path, 'spaced_review_items_v1.json'));

  Future<void> ensureInitialized() async {
    if (!await knowledgeDir.exists()) {
      await knowledgeDir.create(recursive: true);
    }
    if (!await reviewFile.exists()) {
      await reviewFile.writeAsString(_encode(const <SpacedReviewItem>[]));
    }
  }

  Future<List<SpacedReviewItem>> list({
    bool dueOnly = false,
    int? now,
  }) {
    return _enqueue(() async {
      final timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
      final items = await _readAllUnlocked();
      final filtered = dueOnly
          ? items.where((item) => item.isDue(timestamp)).toList()
          : items.toList();
      filtered.sort((a, b) => _sortTimestamp(a).compareTo(_sortTimestamp(b)));
      return filtered;
    });
  }

  Future<SpacedReviewItem?> getById(String id) {
    return _enqueue(() async {
      final items = await _readAllUnlocked();
      for (final item in items) {
        if (item.id == id) return item;
      }
      return null;
    });
  }

  Future<SpacedReviewItem> upsertFromKnowledgeCard(
    KnowledgeCard card, {
    int? now,
  }) {
    if (!card.isUserAsset) {
      throw StateError(
        'Only applied traceable KnowledgeCards can enter spaced review.',
      );
    }
    return _enqueue(() async {
      final items = await _readAllUnlocked();
      final id = reviewIdForCard(card.id);
      final dueAt = now ?? DateTime.now().millisecondsSinceEpoch;
      final candidate = KnowledgeCardReviewAdapter.toSpacedReviewItem(
        card,
        id: id,
        dueAt: dueAt,
      );
      final index = items.indexWhere((item) => item.id == id);
      final item =
          index >= 0 ? _mergeExisting(items[index], candidate) : candidate;
      if (index >= 0) {
        items[index] = item;
      } else {
        items.add(item);
      }
      await _writeAllUnlocked(items);
      return item;
    });
  }

  Future<SpacedReviewItem> upsertFromFlashcardReviewItem(
    ReviewItem item, {
    int? now,
  }) {
    if (item.sourceType != ReviewItemSourceType.flashcardCandidate ||
        item.status != ReviewItemStatus.applied) {
      throw StateError(
        'Only applied traceable flashcard candidates can enter spaced review.',
      );
    }
    return _enqueue(() async {
      final items = await _readAllUnlocked();
      final id = reviewIdForFlashcard(item.sourceId);
      final dueAt = now ?? DateTime.now().millisecondsSinceEpoch;
      final candidate = FlashcardReviewAdapter.toSpacedReviewItem(
        item,
        id: id,
        dueAt: dueAt,
      );
      final index = items.indexWhere((entry) => entry.id == id);
      final next =
          index >= 0 ? _mergeExisting(items[index], candidate) : candidate;
      if (index >= 0) {
        items[index] = next;
      } else {
        items.add(next);
      }
      await _writeAllUnlocked(items);
      return next;
    });
  }

  Future<SpacedReviewItem> recordReview(
    String id, {
    required SpacedReviewRating rating,
    int? now,
    String? note,
  }) {
    return _enqueue(() async {
      final items = await _readAllUnlocked();
      final index = items.indexWhere((item) => item.id == id);
      if (index < 0) {
        throw StateError('Spaced review item not found: $id');
      }
      final item = items[index];
      final timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
      final nextIntervalDays = _nextIntervalDays(
        rating,
        currentIntervalDays: item.intervalDays,
      );
      final updated = item.recordReview(
        reviewedAt: timestamp,
        rating: rating.asString,
        nextDueAt: timestamp + Duration.millisecondsPerDay * nextIntervalDays,
        nextIntervalDays: nextIntervalDays,
        note: note,
      );
      items[index] = updated;
      await _writeAllUnlocked(items);
      return updated;
    });
  }

  PaperReaderSourceJumpAudit sourceJumpAudit(SpacedReviewItem item) {
    return PaperReaderSourceJumpAudit.fromSourceRefs(item.sourceRefs);
  }

  Future<List<SpacedReviewItem>> _readAllUnlocked() async {
    await ensureInitialized();
    final raw = await reviewFile.readAsString();
    if (raw.trim().isEmpty) return <SpacedReviewItem>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final list = decoded['items'];
        if (list is List) {
          return list
              .whereType<Map>()
              .map((entry) => SpacedReviewItem.fromJson(
                    Map<String, dynamic>.from(entry.cast<String, dynamic>()),
                  ))
              .where((item) => item.id.trim().isNotEmpty)
              .where((item) => item.sourceRefs.any((ref) => ref.hasEvidence))
              .toList();
        }
      }
    } catch (_) {
      // Treat malformed local knowledge state as an empty review queue.
    }
    return <SpacedReviewItem>[];
  }

  Future<void> _writeAllUnlocked(List<SpacedReviewItem> items) async {
    await ensureInitialized();
    await reviewFile.writeAsString(_encode(items));
  }

  String _encode(List<SpacedReviewItem> items) {
    final payload = <String, dynamic>{
      'version': 1,
      'items': items.map((item) => item.toJson()).toList(growable: false),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  SpacedReviewItem _mergeExisting(
    SpacedReviewItem existing,
    SpacedReviewItem candidate,
  ) {
    return SpacedReviewItem(
      id: existing.id,
      cardId: candidate.cardId,
      prompt: candidate.prompt,
      answer: candidate.answer,
      sourceRefs: candidate.sourceRefs,
      lastReviewedAt: existing.lastReviewedAt,
      dueAt: existing.dueAt ?? candidate.dueAt,
      intervalDays: existing.intervalDays,
      lapses: existing.lapses,
      reviewHistory: existing.reviewHistory,
    );
  }

  int _nextIntervalDays(
    SpacedReviewRating rating, {
    required int currentIntervalDays,
  }) {
    return switch (rating) {
      SpacedReviewRating.again => 1,
      SpacedReviewRating.hard => currentIntervalDays <= 0
          ? 2
          : (currentIntervalDays + 1).clamp(2, 30).toInt(),
      SpacedReviewRating.good => currentIntervalDays <= 0
          ? 3
          : (currentIntervalDays * 2).clamp(3, 180).toInt(),
      SpacedReviewRating.easy => currentIntervalDays <= 0
          ? 7
          : (currentIntervalDays * 3).clamp(7, 365).toInt(),
    };
  }

  int _sortTimestamp(SpacedReviewItem item) {
    return item.dueAt ?? item.lastReviewedAt ?? 0;
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
