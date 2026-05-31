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
  File get stagedRemoteSyncConflictsFile =>
      File(p.join(knowledgeDir.path, 'remote_sync_conflicts_v1.json'));

  Future<void> ensureInitialized() async {
    if (!await knowledgeDir.exists()) {
      await knowledgeDir.create(recursive: true);
    }
    if (!await cardsFile.exists()) {
      await cardsFile.writeAsString(_encode(const <KnowledgeCard>[]));
    }
    if (!await stagedRemoteSyncConflictsFile.exists()) {
      await stagedRemoteSyncConflictsFile.writeAsString(
        _encodeStagedRemoteSyncConflicts(const <KnowledgeSyncEnvelope>[]),
      );
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

  Future<List<KnowledgeSyncEnvelope>> listStagedRemoteSyncConflicts() {
    return _enqueue(_readStagedRemoteSyncConflictsUnlocked);
  }

  Future<KnowledgeSyncEnvelope?> getStagedRemoteSyncConflictById(String id) {
    return _enqueue(() async {
      final entries = await _readStagedRemoteSyncConflictsUnlocked();
      for (final entry in entries) {
        if (entry.id == id) return entry;
      }
      return null;
    });
  }

  Future<bool> removeStagedRemoteSyncConflict(String id) {
    return _enqueue(() async {
      final entries = await _readStagedRemoteSyncConflictsUnlocked();
      final before = entries.length;
      entries.removeWhere((entry) => entry.id == id);
      if (entries.length == before) return false;
      await _writeStagedRemoteSyncConflictsUnlocked(entries);
      return true;
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

  Future<KnowledgeSyncEnvelope> stageRemoteSyncConflict(
    KnowledgeSyncEnvelope remote,
  ) {
    return _enqueue(() async {
      final staged = _validatedRemoteSyncConflictEnvelope(remote);
      final entries = await _readStagedRemoteSyncConflictsUnlocked();
      final index = entries.indexWhere((entry) => entry.id == staged.id);
      if (index >= 0) {
        entries[index] = staged;
      } else {
        entries.add(staged);
      }
      await _writeStagedRemoteSyncConflictsUnlocked(entries);
      return staged;
    });
  }

  Future<KnowledgeCard> resolveSyncConflict(
    String id, {
    String? stagedConflictId,
    int? now,
  }) {
    return _enqueue(() async {
      if (stagedConflictId != null) {
        return _resolveStagedRemoteSyncConflictUnlocked(
          id,
          stagedConflictId: stagedConflictId,
          now: now,
        );
      }
      final entries = await _readStoredEntriesUnlocked();
      final index = entries.indexWhere((entry) {
        final envelope = _envelopeFromStoredEntry(entry);
        return envelope?.id == id;
      });
      if (index < 0) {
        throw StateError('KnowledgeCard sync conflict not found: $id');
      }

      final envelope = _envelopeFromStoredEntry(entries[index]);
      final resolved = _resolvedCardFromConflictEnvelope(
        envelope,
        expectedId: id,
        now: now,
      );

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

  Future<List<KnowledgeSyncEnvelope>>
      _readStagedRemoteSyncConflictsUnlocked() async {
    await ensureInitialized();
    final raw = await stagedRemoteSyncConflictsFile.readAsString();
    if (raw.trim().isEmpty) return <KnowledgeSyncEnvelope>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final list = decoded['conflicts'];
        if (list is List) {
          return list
              .whereType<Map>()
              .map((entry) =>
                  KnowledgeSyncEnvelope.fromJson(Map<String, dynamic>.from(
                    entry,
                  )))
              .toList();
        }
      }
    } catch (_) {
      // Treat malformed staged remote conflicts as empty; remote can be
      // previewed and staged again.
    }
    return <KnowledgeSyncEnvelope>[];
  }

  Future<void> _writeStagedRemoteSyncConflictsUnlocked(
    List<KnowledgeSyncEnvelope> entries,
  ) async {
    await ensureInitialized();
    await stagedRemoteSyncConflictsFile.writeAsString(
      _encodeStagedRemoteSyncConflicts(entries),
    );
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

  String _encodeStagedRemoteSyncConflicts(
    List<KnowledgeSyncEnvelope> entries,
  ) {
    final payload = <String, dynamic>{
      'version': 1,
      'conflicts': entries.map((entry) => entry.toJson()).toList(),
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

  KnowledgeSyncEnvelope _validatedRemoteSyncConflictEnvelope(
    KnowledgeSyncEnvelope remote,
  ) {
    if (!remote.requiresConflictReview) {
      throw StateError('Remote sync conflict is not pending review.');
    }
    if (remote.entityType != KnowledgeSyncEntityType.knowledgeCard) {
      throw StateError(
        'Remote sync conflict is not a KnowledgeCard: '
        '${remote.entityType.asString}',
      );
    }
    if (remote.schemaVersion != 1) {
      throw StateError(
        'Unsupported remote KnowledgeCard sync schema: ${remote.schemaVersion}',
      );
    }
    if (KnowledgeSyncPolicy.containsSecretPayload(remote.payload)) {
      throw StateError(
          'Remote KnowledgeCard conflict contains secret payload.');
    }

    final card = KnowledgeCard.fromJson(remote.payload);
    final sourceRefs =
        card.sourceRefs.isNotEmpty ? card.sourceRefs : remote.sourceRefs;
    if (!_hasTraceableSyncSource(sourceRefs)) {
      throw StateError(
        'Remote KnowledgeCard conflict cannot be staged without source refs.',
      );
    }
    final safeSourceRefs = sourceRefs
        .map((ref) => SourceRef.fromJson(ref.toSafeJson()))
        .toList(growable: false);
    final safeCard = card.copyWith(
      id: remote.id,
      sourceRefs: safeSourceRefs,
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
      updatedAt: remote.updatedAt,
    );
    return KnowledgeSyncEnvelope(
      id: remote.id,
      entityType: KnowledgeSyncEntityType.knowledgeCard,
      schemaVersion: 1,
      updatedAt: remote.updatedAt,
      deletedAt: remote.deletedAt,
      sourceRefs: safeSourceRefs,
      conflictStatus: KnowledgeSyncConflictStatus.pendingReview,
      conflictReason: remote.conflictReason ?? 'remote-content-conflict',
      payload: safeCard.toJson(),
    );
  }

  KnowledgeCard _resolvedCardFromConflictEnvelope(
    KnowledgeSyncEnvelope? envelope, {
    required String expectedId,
    int? now,
  }) {
    if (envelope == null || !envelope.requiresConflictReview) {
      throw StateError(
        'KnowledgeCard sync conflict is not pending: $expectedId',
      );
    }
    if (envelope.id != expectedId) {
      throw StateError(
        'KnowledgeCard sync conflict id mismatch: ${envelope.id}',
      );
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
      throw StateError('KnowledgeCard sync conflict contains secret payload.');
    }

    final card = KnowledgeCard.fromJson(envelope.payload);
    final sourceRefs =
        card.sourceRefs.isNotEmpty ? card.sourceRefs : envelope.sourceRefs;
    if (!_hasTraceableSyncSource(sourceRefs)) {
      throw StateError(
        'KnowledgeCard sync conflict cannot be resolved without source refs.',
      );
    }

    final safeSourceRefs = sourceRefs
        .map((ref) => SourceRef.fromJson(ref.toSafeJson()))
        .toList(growable: false);
    final resolved = card.copyWith(
      id: envelope.id,
      sourceRefs: safeSourceRefs,
      reviewState: KnowledgeCardReviewState.applied,
      ownership: AiOutputOwnership.aiGeneratedApproved,
      updatedAt: now ?? envelope.updatedAt,
    );
    if (!resolved.isUserAsset) {
      throw StateError('Resolved KnowledgeCard is not a user asset.');
    }
    return resolved;
  }

  Future<KnowledgeCard> _resolveStagedRemoteSyncConflictUnlocked(
    String id, {
    required String stagedConflictId,
    int? now,
  }) async {
    final stagedEntries = await _readStagedRemoteSyncConflictsUnlocked();
    final stagedIndex =
        stagedEntries.indexWhere((entry) => entry.id == stagedConflictId);
    if (stagedIndex < 0) {
      throw StateError(
        'Staged remote KnowledgeCard sync conflict not found: '
        '$stagedConflictId',
      );
    }
    final staged = stagedEntries[stagedIndex];
    final resolved = _resolvedCardFromConflictEnvelope(
      staged,
      expectedId: id,
      now: now,
    );

    final entries = await _readStoredEntriesUnlocked();
    final index = entries.indexWhere((entry) {
      final envelope = _envelopeFromStoredEntry(entry);
      return envelope?.id == id;
    });
    if (index >= 0) {
      entries[index] = _envelopeForCard(resolved).toJson();
    } else {
      entries.add(_envelopeForCard(resolved).toJson());
    }
    stagedEntries.removeAt(stagedIndex);
    await _writeStoredEntriesUnlocked(entries);
    await _writeStagedRemoteSyncConflictsUnlocked(stagedEntries);
    return resolved;
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
