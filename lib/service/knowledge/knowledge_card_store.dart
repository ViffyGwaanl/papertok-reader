import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/knowledge_sync.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';
import 'package:path/path.dart' as p;

class KnowledgeCardStoreUpsertResult {
  const KnowledgeCardStoreUpsertResult({
    required this.card,
    required this.inserted,
    this.duplicateOfId,
  });

  final KnowledgeCard card;
  final bool inserted;
  final String? duplicateOfId;

  bool get isDuplicate => duplicateOfId != null;
}

class KnowledgeCardStore {
  KnowledgeCardStore({Directory? rootDir})
      : rootDir = rootDir ?? MarkdownMemoryStore().rootDir;

  final Directory rootDir;
  Future<void> _tail = Future<void>.value();

  Directory get knowledgeDir => Directory(p.join(rootDir.path, '.knowledge'));
  File get cardsFile =>
      File(p.join(knowledgeDir.path, 'knowledge_cards_v1.json'));

  Future<void> ensureInitialized() async {
    if (!await knowledgeDir.exists()) {
      await knowledgeDir.create(recursive: true);
    }
    if (!await cardsFile.exists()) {
      await cardsFile.writeAsString(_encode(const <KnowledgeCard>[]));
    }
  }

  Future<List<KnowledgeCard>> list({
    KnowledgeCardReviewState? reviewState,
    KnowledgeCardOrigin? origin,
  }) {
    return _enqueue(() async {
      final cards = await _readAllUnlocked();
      final filtered = cards.where((card) {
        if (reviewState != null && card.reviewState != reviewState) {
          return false;
        }
        if (origin != null && card.origin != origin) return false;
        return true;
      }).toList();
      filtered.sort((a, b) => _sortTimestamp(b).compareTo(_sortTimestamp(a)));
      return filtered;
    });
  }

  Future<List<KnowledgeSyncEnvelope>> listSyncEnvelopes() {
    return _enqueue(() async {
      final entries = await _readStoredEntriesUnlocked();
      return entries
          .map(_envelopeFromStoredEntry)
          .whereType<KnowledgeSyncEnvelope>()
          .toList(growable: false);
    });
  }

  Future<KnowledgeCard?> getById(String id) {
    return _enqueue(() async {
      final cards = await _readAllUnlocked();
      for (final card in cards) {
        if (card.id == id) return card;
      }
      return null;
    });
  }

  Future<KnowledgeCard> upsert(KnowledgeCard card) {
    if (!_canStageViaRawUpsert(card)) {
      throw ArgumentError(
        'KnowledgeCardStore.upsert only accepts draft/pending AI candidates; '
        'use applyReviewDecision for approved/applied user assets.',
      );
    }
    return _enqueue(() async {
      final cards = await _readAllUnlocked();
      final staged = _reviewCandidate(card);
      _replaceOrAdd(cards, staged);
      await _writeAllUnlocked(cards);
      return staged;
    });
  }

  Future<KnowledgeCardStoreUpsertResult> upsertCandidate(
    KnowledgeCard candidate,
  ) {
    return _enqueue(() async {
      final cards = await _readAllUnlocked();
      final reviewCandidate = _reviewCandidate(candidate);
      final duplicate = _findDuplicate(cards, reviewCandidate);
      if (duplicate != null) {
        return KnowledgeCardStoreUpsertResult(
          card: duplicate,
          inserted: false,
          duplicateOfId: duplicate.id,
        );
      }

      _replaceOrAdd(cards, reviewCandidate);
      await _writeAllUnlocked(cards);
      return KnowledgeCardStoreUpsertResult(
        card: reviewCandidate,
        inserted: true,
      );
    });
  }

  Future<KnowledgeCard> applyReviewDecision(
    ReviewItem item, {
    int? now,
  }) {
    if (item.sourceType != ReviewItemSourceType.knowledgeCard) {
      throw ArgumentError(
        'Review item is not a KnowledgeCard source: ${item.sourceType.asString}',
      );
    }

    return _enqueue(() async {
      final cards = await _readAllUnlocked();
      final index = cards.indexWhere((card) => card.id == item.sourceId);
      if (index < 0) {
        throw StateError('KnowledgeCard not found: ${item.sourceId}');
      }
      final updated = KnowledgeCardReviewAdapter.applyReviewDecision(
        cards[index],
        item,
        now: now,
      );
      cards[index] = updated;
      await _writeAllUnlocked(cards);
      return updated;
    });
  }

  Future<KnowledgeCard> resolveSyncConflict(
    String id, {
    int? now,
  }) {
    return _enqueue(() async {
      final entries = await _readStoredEntriesUnlocked();
      final index = entries.indexWhere((entry) {
        final envelope = _envelopeFromStoredEntry(entry);
        return envelope?.id == id;
      });
      if (index < 0) {
        throw StateError('KnowledgeCard sync conflict not found: $id');
      }

      final envelope = _envelopeFromStoredEntry(entries[index]);
      if (envelope == null || !envelope.requiresConflictReview) {
        throw StateError('KnowledgeCard sync conflict is not pending: $id');
      }
      if (envelope.entityType != KnowledgeSyncEntityType.knowledgeCard) {
        throw StateError(
          'Sync conflict is not a KnowledgeCard: '
          '${envelope.entityType.asString}',
        );
      }
      if (envelope.schemaVersion != 1) {
        throw StateError(
          'Unsupported KnowledgeCard sync schema: ${envelope.schemaVersion}',
        );
      }
      if (KnowledgeSyncPolicy.containsSecretPayload(envelope.payload)) {
        throw StateError(
            'KnowledgeCard sync conflict contains secret payload.');
      }

      final card = KnowledgeCard.fromJson(envelope.payload);
      final sourceRefs =
          card.sourceRefs.isNotEmpty ? card.sourceRefs : envelope.sourceRefs;
      if (!_hasTraceableSyncSource(sourceRefs)) {
        throw StateError(
          'KnowledgeCard sync conflict cannot be resolved without source refs.',
        );
      }

      final resolved = card.copyWith(
        id: envelope.id,
        sourceRefs: sourceRefs,
        reviewState: KnowledgeCardReviewState.applied,
        ownership: AiOutputOwnership.aiGeneratedApproved,
        updatedAt: now ?? envelope.updatedAt,
      );
      if (!resolved.isUserAsset) {
        throw StateError('Resolved KnowledgeCard is not a user asset.');
      }

      entries[index] = _envelopeForCard(resolved).toJson();
      await _writeStoredEntriesUnlocked(entries);
      return resolved;
    });
  }

  Future<List<KnowledgeCard>> _readAllUnlocked() async {
    final entries = await _readStoredEntriesUnlocked();
    return entries
        .map(_cardFromStoredEntry)
        .whereType<KnowledgeCard>()
        .toList();
  }

  Future<List<Map<String, dynamic>>> _readStoredEntriesUnlocked() async {
    await ensureInitialized();
    final raw = await cardsFile.readAsString();
    if (raw.trim().isEmpty) return <Map<String, dynamic>>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final list = decoded['cards'];
        if (list is List) {
          return list
              .whereType<Map>()
              .map(
                (entry) =>
                    Map<String, dynamic>.from(entry.cast<String, dynamic>()),
              )
              .toList();
        }
      }
    } catch (_) {
      // Treat malformed local knowledge state as an empty card list.
    }
    return <Map<String, dynamic>>[];
  }

  Future<void> _writeAllUnlocked(List<KnowledgeCard> cards) async {
    await _writeStoredEntriesUnlocked(
      cards.map((card) => _envelopeForCard(card).toJson()).toList(),
    );
  }

  Future<void> _writeStoredEntriesUnlocked(
    List<Map<String, dynamic>> entries,
  ) async {
    await ensureInitialized();
    final payload = <String, dynamic>{
      'version': 1,
      'cards': entries.map(Map<String, dynamic>.from).toList(growable: false),
    };
    await cardsFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  String _encode(List<KnowledgeCard> cards) {
    final payload = <String, dynamic>{
      'version': 1,
      'cards': cards
          .map((card) => _envelopeForCard(card).toJson())
          .toList(growable: false),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  KnowledgeSyncEnvelope _envelopeForCard(KnowledgeCard card) {
    final updatedAt = card.updatedAt ??
        card.createdAt ??
        DateTime.now().millisecondsSinceEpoch;
    return KnowledgeSyncEnvelope(
      id: card.id,
      entityType: card.isUserAsset
          ? KnowledgeSyncEntityType.knowledgeCard
          : KnowledgeSyncEntityType.aiDraft,
      schemaVersion: 1,
      updatedAt: updatedAt,
      sourceRefs: card.sourceRefs,
      payload: card.toJson(),
    );
  }

  KnowledgeCard? _cardFromStoredEntry(Map<String, dynamic> entry) {
    final payload = entry['payload'];
    if (payload is Map) {
      return KnowledgeCard.fromJson(Map<String, dynamic>.from(payload));
    }
    return KnowledgeCard.fromJson(entry);
  }

  KnowledgeSyncEnvelope? _envelopeFromStoredEntry(Map<String, dynamic> entry) {
    final payload = entry['payload'];
    if (payload is Map) {
      final envelope = KnowledgeSyncEnvelope.fromJson(entry);
      if (envelope.requiresConflictReview) {
        return envelope;
      }
      final card = KnowledgeCard.fromJson(Map<String, dynamic>.from(payload));
      return _envelopeForCard(card);
    }

    final card = KnowledgeCard.fromJson(entry);
    return _envelopeForCard(card);
  }

  KnowledgeCard? _findDuplicate(
    List<KnowledgeCard> cards,
    KnowledgeCard candidate,
  ) {
    for (final card in cards) {
      if (card.id == candidate.id) {
        return card;
      }
      if (card.reviewState == KnowledgeCardReviewState.dismissed) {
        continue;
      }
      if (KnowledgeCardDedupe.isLikelyDuplicate(card, candidate)) {
        return card;
      }
    }
    return null;
  }

  KnowledgeCard _reviewCandidate(KnowledgeCard candidate) {
    final reviewState = switch (candidate.reviewState) {
      KnowledgeCardReviewState.draft => KnowledgeCardReviewState.draft,
      KnowledgeCardReviewState.pending => KnowledgeCardReviewState.pending,
      KnowledgeCardReviewState.approved ||
      KnowledgeCardReviewState.dismissed ||
      KnowledgeCardReviewState.applied =>
        KnowledgeCardReviewState.pending,
    };
    return candidate.copyWith(
      reviewState: reviewState,
      ownership: AiOutputOwnership.aiGeneratedDraft,
    );
  }

  bool _canStageViaRawUpsert(KnowledgeCard card) {
    final stageStatus = card.reviewState == KnowledgeCardReviewState.draft ||
        card.reviewState == KnowledgeCardReviewState.pending;
    return stageStatus && card.ownership == AiOutputOwnership.aiGeneratedDraft;
  }

  void _replaceOrAdd(List<KnowledgeCard> cards, KnowledgeCard card) {
    final index = cards.indexWhere((existing) => existing.id == card.id);
    if (index >= 0) {
      cards[index] = card;
    } else {
      cards.add(card);
    }
  }

  int _sortTimestamp(KnowledgeCard card) {
    return card.createdAt ?? card.updatedAt ?? 0;
  }

  bool _hasTraceableSyncSource(List<SourceRef> refs) {
    return refs.any((ref) => ref.hasBookAnchor || ref.canJumpBack);
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
