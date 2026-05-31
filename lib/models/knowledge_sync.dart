import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:papertok_reader/models/source_ref.dart';

enum KnowledgeSyncEntityType {
  knowledgeCard('knowledge-card'),
  reviewItem('review-item'),
  reviewHistory('review-history'),
  aiDraft('ai-draft'),
  derivedIndex('derived-index'),
  secret('secret'),
  unknown('unknown');

  const KnowledgeSyncEntityType(this.asString);

  final String asString;

  static KnowledgeSyncEntityType fromString(String? value) {
    for (final type in KnowledgeSyncEntityType.values) {
      if (type.asString == value) return type;
    }
    return KnowledgeSyncEntityType.unknown;
  }
}

enum KnowledgeSyncConflictStatus {
  none('none'),
  pendingReview('pending-review'),
  resolved('resolved');

  const KnowledgeSyncConflictStatus(this.asString);

  final String asString;

  static KnowledgeSyncConflictStatus fromString(String? value) {
    for (final status in KnowledgeSyncConflictStatus.values) {
      if (status.asString == value) return status;
    }
    return KnowledgeSyncConflictStatus.pendingReview;
  }
}

@immutable
class KnowledgeSyncEnvelope {
  const KnowledgeSyncEnvelope({
    required this.id,
    required this.entityType,
    required this.schemaVersion,
    required this.updatedAt,
    required this.payload,
    this.deletedAt,
    this.sourceRefs = const <SourceRef>[],
    this.conflictStatus = KnowledgeSyncConflictStatus.none,
    this.conflictReason,
  });

  final String id;
  final KnowledgeSyncEntityType entityType;
  final int schemaVersion;
  final int updatedAt;
  final int? deletedAt;
  final List<SourceRef> sourceRefs;
  final KnowledgeSyncConflictStatus conflictStatus;
  final String? conflictReason;
  final Map<String, dynamic> payload;

  bool get isTombstone => deletedAt != null;

  bool get shouldSyncByDefault =>
      entityType == KnowledgeSyncEntityType.knowledgeCard ||
      entityType == KnowledgeSyncEntityType.reviewItem ||
      entityType == KnowledgeSyncEntityType.reviewHistory;

  bool get requiresConflictReview =>
      conflictStatus == KnowledgeSyncConflictStatus.pendingReview;

  Map<String, dynamic> toJson() => {
        'id': id,
        'entityType': entityType.asString,
        'schemaVersion': schemaVersion,
        'updatedAt': updatedAt,
        if (deletedAt != null) 'deletedAt': deletedAt,
        'sourceRefs':
            sourceRefs.map((ref) => ref.toSafeJson()).toList(growable: false),
        'conflictStatus': conflictStatus.asString,
        if (conflictReason != null) 'conflictReason': conflictReason,
        'payload': payload,
      };

  factory KnowledgeSyncEnvelope.fromJson(Map<String, dynamic> json) {
    final missingRequiredFields = _missingRequiredFields(json);
    final hasMalformedRequiredFields = missingRequiredFields.isNotEmpty;
    final conflictStatus = hasMalformedRequiredFields
        ? KnowledgeSyncConflictStatus.pendingReview
        : json.containsKey('conflictStatus')
            ? KnowledgeSyncConflictStatus.fromString(
                json['conflictStatus']?.toString(),
              )
            : KnowledgeSyncConflictStatus.none;
    final rawPayload = json['payload'];
    return KnowledgeSyncEnvelope(
      id: (json['id'] ?? '').toString(),
      entityType:
          KnowledgeSyncEntityType.fromString(json['entityType']?.toString()),
      schemaVersion: _intValue(json['schemaVersion']) ?? 1,
      updatedAt: _intValue(json['updatedAt']) ?? 0,
      deletedAt: (json['deletedAt'] as num?)?.toInt(),
      sourceRefs: (json['sourceRefs'] as List?)
              ?.whereType<Map>()
              .map((e) => SourceRef.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false) ??
          const <SourceRef>[],
      conflictStatus: conflictStatus,
      conflictReason: hasMalformedRequiredFields
          ? 'missing-required-fields'
          : json['conflictReason']?.toString(),
      payload: Map<String, dynamic>.from(
        rawPayload is Map ? rawPayload : const <String, dynamic>{},
      ),
    );
  }

  static List<String> _missingRequiredFields(Map<String, dynamic> json) {
    return [
      if ((json['id']?.toString().trim() ?? '').isEmpty) 'id',
      if ((json['entityType']?.toString().trim() ?? '').isEmpty) 'entityType',
      if (_intValue(json['schemaVersion']) == null) 'schemaVersion',
      if (_intValue(json['updatedAt']) == null) 'updatedAt',
      if (json['payload'] is! Map) 'payload',
    ];
  }

  static int? _intValue(Object? value) {
    if (value is num) return value.toInt();
    return null;
  }
}

@immutable
class KnowledgeSyncPlan {
  const KnowledgeSyncPlan({
    required this.included,
    required this.excluded,
    required this.excludedReasons,
  });

  final List<KnowledgeSyncEnvelope> included;
  final List<KnowledgeSyncEnvelope> excluded;
  final Map<String, String> excludedReasons;

  String? excludedReasonFor(String id) => excludedReasons[id];
}

class KnowledgeSyncPolicy {
  const KnowledgeSyncPolicy._();

  static KnowledgeSyncPlan planDefaultSync(
    Iterable<KnowledgeSyncEnvelope> envelopes,
  ) {
    final included = <KnowledgeSyncEnvelope>[];
    final excluded = <KnowledgeSyncEnvelope>[];
    final excludedReasons = <String, String>{};

    for (final envelope in envelopes) {
      final reason = exclusionReason(envelope);
      if (reason == null) {
        included.add(envelope);
      } else {
        excluded.add(envelope);
        excludedReasons[envelope.id] = reason;
      }
    }

    return KnowledgeSyncPlan(
      included: included,
      excluded: excluded,
      excludedReasons: excludedReasons,
    );
  }

  static String? exclusionReason(KnowledgeSyncEnvelope envelope) {
    if (envelope.requiresConflictReview) {
      return 'pending-conflict-review';
    }
    if (!envelope.shouldSyncByDefault) {
      return 'not-default-sync-entity';
    }
    if (containsSecretPayload(envelope.payload)) {
      return 'contains-secret';
    }
    return null;
  }

  static bool containsSecretPayload(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (_isSecretKey(entry.key.toString())) return true;
        if (containsSecretPayload(entry.value)) return true;
      }
      return false;
    }
    if (value is Iterable) {
      return value.any(containsSecretPayload);
    }
    return false;
  }

  static bool _isSecretKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    if (normalized.isEmpty) return false;
    return normalized == 'token' ||
        normalized == 'secret' ||
        normalized == 'auth' ||
        normalized == 'bearer' ||
        normalized == 'xauth' ||
        normalized == 'authorization' ||
        normalized == 'password' ||
        normalized == 'passwd' ||
        normalized == 'credential' ||
        normalized.contains('apikey') ||
        normalized.contains('accesskey') ||
        normalized.contains('secretkey') ||
        normalized.contains('privatekey') ||
        normalized.contains('authtoken') ||
        normalized.contains('bearertoken') ||
        normalized.contains('token') ||
        normalized.contains('secret');
  }
}

class KnowledgeSyncConflictDetector {
  const KnowledgeSyncConflictDetector._();

  static KnowledgeSyncEnvelope reviewEnvelopeFor({
    required KnowledgeSyncEnvelope? local,
    required KnowledgeSyncEnvelope remote,
    required int currentSchemaVersion,
  }) {
    final conflictReason = _conflictReason(
      local: local,
      remote: remote,
      currentSchemaVersion: currentSchemaVersion,
    );
    if (conflictReason == null) return remote;

    return KnowledgeSyncEnvelope(
      id: remote.id,
      entityType: remote.entityType,
      schemaVersion: remote.schemaVersion,
      updatedAt: remote.updatedAt,
      deletedAt: remote.deletedAt,
      sourceRefs: remote.sourceRefs,
      conflictStatus: KnowledgeSyncConflictStatus.pendingReview,
      conflictReason: conflictReason,
      payload: remote.payload,
    );
  }

  static String? _conflictReason({
    required KnowledgeSyncEnvelope? local,
    required KnowledgeSyncEnvelope remote,
    required int currentSchemaVersion,
  }) {
    if (remote.requiresConflictReview) {
      return remote.conflictReason ?? 'remote-pending-review';
    }
    if (remote.schemaVersion > currentSchemaVersion) {
      return 'unknown-schema-version';
    }
    if (local == null) return null;
    if (remote.isTombstone && !local.isTombstone) {
      return 'delete-modify-conflict';
    }
    if (local.isTombstone && !remote.isTombstone) {
      return 'delete-modify-conflict';
    }
    if (local.updatedAt != remote.updatedAt &&
        local.payload.toString() != remote.payload.toString()) {
      return 'content-conflict';
    }
    return null;
  }
}

@immutable
class KnowledgeRemoteMergePlan {
  const KnowledgeRemoteMergePlan({
    required this.local,
    required this.remote,
    required this.base,
    required this.unchanged,
    required this.incoming,
    required this.outgoing,
    required this.conflicts,
  });

  final List<KnowledgeSyncEnvelope> local;
  final List<KnowledgeSyncEnvelope> remote;
  final List<KnowledgeSyncEnvelope> base;
  final List<KnowledgeSyncEnvelope> unchanged;
  final List<KnowledgeSyncEnvelope> incoming;
  final List<KnowledgeSyncEnvelope> outgoing;
  final List<KnowledgeSyncEnvelope> conflicts;

  bool get hasReviewBlockers => conflicts.isNotEmpty;
}

class KnowledgeRemoteMergePlanner {
  const KnowledgeRemoteMergePlanner._();

  static KnowledgeRemoteMergePlan plan({
    required Iterable<KnowledgeSyncEnvelope> local,
    required Iterable<KnowledgeSyncEnvelope> remote,
    Iterable<KnowledgeSyncEnvelope> base = const <KnowledgeSyncEnvelope>[],
    int currentSchemaVersion = 1,
  }) {
    final localList = local.toList(growable: false);
    final remoteList = remote.toList(growable: false);
    final baseList = base.toList(growable: false);
    final localById = _byId(localList);
    final remoteById = _byId(remoteList);
    final baseById = _byId(baseList);
    final duplicateReasons = <String, String>{
      for (final id in _duplicateIds(localList)) id: 'duplicate-local-id',
      for (final id in _duplicateIds(remoteList)) id: 'duplicate-remote-id',
      for (final id in _duplicateIds(baseList)) id: 'duplicate-base-id',
    };

    final unchanged = <KnowledgeSyncEnvelope>[];
    final incoming = <KnowledgeSyncEnvelope>[];
    final outgoing = <KnowledgeSyncEnvelope>[];
    final conflicts = <KnowledgeSyncEnvelope>[];
    final unsafeIds = <String>{};

    for (final envelope in [...localList, ...remoteList, ...baseList]) {
      final idConflictReason = _idConflictReason(envelope);
      if (idConflictReason != null) {
        unsafeIds.add(envelope.id.trim());
        conflicts.add(
          _reviewEnvelope(
            envelope,
            envelope.conflictReason ?? idConflictReason,
          ),
        );
      }
    }

    for (final id in _orderedIds(localList, remoteList, baseList)) {
      if (unsafeIds.contains(id)) {
        continue;
      }
      final localEnvelope = localById[id];
      final remoteEnvelope = remoteById[id];
      final baseEnvelope = baseById[id];
      final duplicateReason = duplicateReasons[id];
      if (duplicateReason != null) {
        conflicts.add(
          _reviewEnvelope(
            remoteEnvelope ?? localEnvelope ?? baseEnvelope!,
            duplicateReason,
          ),
        );
        continue;
      }

      final invalidLocal = localEnvelope == null
          ? null
          : _safetyConflictReason(
              localEnvelope,
              currentSchemaVersion: currentSchemaVersion,
            );
      final invalidRemote = remoteEnvelope == null
          ? null
          : _safetyConflictReason(
              remoteEnvelope,
              currentSchemaVersion: currentSchemaVersion,
            );
      final invalidBase = baseEnvelope == null
          ? null
          : _safetyConflictReason(
              baseEnvelope,
              currentSchemaVersion: currentSchemaVersion,
            );
      if (invalidLocal != null ||
          invalidRemote != null ||
          invalidBase != null) {
        conflicts.add(
          _reviewEnvelope(
            invalidRemote != null
                ? remoteEnvelope!
                : invalidLocal != null
                    ? localEnvelope!
                    : baseEnvelope!,
            invalidRemote ?? invalidLocal ?? invalidBase!,
          ),
        );
        continue;
      }

      if (localEnvelope == null && remoteEnvelope != null) {
        incoming.add(remoteEnvelope);
        continue;
      }
      if (remoteEnvelope == null && localEnvelope != null) {
        outgoing.add(localEnvelope);
        continue;
      }
      if (localEnvelope == null || remoteEnvelope == null) {
        continue;
      }

      if (_sameContent(localEnvelope, remoteEnvelope)) {
        unchanged.add(localEnvelope);
        continue;
      }

      if (baseEnvelope == null) {
        conflicts.add(
          _reviewEnvelope(
            remoteEnvelope,
            _contentConflictReason(localEnvelope, remoteEnvelope),
          ),
        );
        continue;
      }

      final localChanged = !_sameContent(localEnvelope, baseEnvelope);
      final remoteChanged = !_sameContent(remoteEnvelope, baseEnvelope);
      if (localChanged && !remoteChanged) {
        outgoing.add(localEnvelope);
        continue;
      }
      if (!localChanged && remoteChanged) {
        incoming.add(remoteEnvelope);
        continue;
      }
      if (!localChanged && !remoteChanged) {
        unchanged.add(localEnvelope);
        continue;
      }

      conflicts.add(
        _reviewEnvelope(
          remoteEnvelope,
          _contentConflictReason(localEnvelope, remoteEnvelope),
        ),
      );
    }

    return KnowledgeRemoteMergePlan(
      local: List.unmodifiable(localList),
      remote: List.unmodifiable(remoteList),
      base: List.unmodifiable(baseList),
      unchanged: List.unmodifiable(unchanged),
      incoming: List.unmodifiable(incoming),
      outgoing: List.unmodifiable(outgoing),
      conflicts: List.unmodifiable(conflicts),
    );
  }

  static Map<String, KnowledgeSyncEnvelope> _byId(
    Iterable<KnowledgeSyncEnvelope> envelopes,
  ) {
    return {
      for (final envelope in envelopes)
        if (envelope.id.trim().isNotEmpty) envelope.id.trim(): envelope,
    };
  }

  static String? _idConflictReason(KnowledgeSyncEnvelope envelope) {
    final trimmed = envelope.id.trim();
    if (trimmed.isEmpty) {
      return 'missing-required-fields';
    }
    if (trimmed != envelope.id) {
      return 'malformed-id';
    }
    return null;
  }

  static List<String> _duplicateIds(
    Iterable<KnowledgeSyncEnvelope> envelopes,
  ) {
    final seen = <String>{};
    final duplicates = <String>{};
    for (final envelope in envelopes) {
      final id = envelope.id.trim();
      if (id.isEmpty) continue;
      if (!seen.add(id)) {
        duplicates.add(id);
      }
    }
    return duplicates.toList(growable: false);
  }

  static List<String> _orderedIds(
    List<KnowledgeSyncEnvelope> local,
    List<KnowledgeSyncEnvelope> remote,
    List<KnowledgeSyncEnvelope> base,
  ) {
    final ids = <String>[];
    void add(KnowledgeSyncEnvelope envelope) {
      final id = envelope.id.trim();
      if (id.isNotEmpty && !ids.contains(id)) {
        ids.add(id);
      }
    }

    local.forEach(add);
    remote.forEach(add);
    base.forEach(add);
    return ids;
  }

  static String? _safetyConflictReason(
    KnowledgeSyncEnvelope envelope, {
    required int currentSchemaVersion,
  }) {
    if (envelope.requiresConflictReview) {
      return envelope.conflictReason ?? 'pending-conflict-review';
    }
    if (envelope.schemaVersion > currentSchemaVersion) {
      return 'unknown-schema-version';
    }
    if (KnowledgeSyncPolicy.containsSecretPayload(envelope.payload)) {
      return 'contains-secret';
    }
    if (!envelope.shouldSyncByDefault) {
      return 'not-default-sync-entity';
    }
    return null;
  }

  static bool _sameContent(
    KnowledgeSyncEnvelope left,
    KnowledgeSyncEnvelope right,
  ) {
    return _contentFingerprint(left) == _contentFingerprint(right);
  }

  static String _contentFingerprint(KnowledgeSyncEnvelope envelope) {
    return jsonEncode(
      _canonicalize({
        'id': envelope.id,
        'entityType': envelope.entityType.asString,
        'schemaVersion': envelope.schemaVersion,
        'deletedAt': envelope.deletedAt,
        'sourceRefs': envelope.sourceRefs
            .map((ref) => ref.toSafeJson())
            .toList(growable: false),
        'payload': envelope.payload,
      }),
    );
  }

  static Object? _canonicalize(Object? value) {
    if (value is Map) {
      final out = <String, Object?>{};
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      for (final key in keys) {
        out[key] = _canonicalize(value[key]);
      }
      return out;
    }
    if (value is Iterable) {
      return value.map(_canonicalize).toList(growable: false);
    }
    return value;
  }

  static String _contentConflictReason(
    KnowledgeSyncEnvelope local,
    KnowledgeSyncEnvelope remote,
  ) {
    if (local.isTombstone != remote.isTombstone) {
      return 'delete-modify-conflict';
    }
    return 'content-conflict';
  }

  static KnowledgeSyncEnvelope _reviewEnvelope(
    KnowledgeSyncEnvelope envelope,
    String reason,
  ) {
    return KnowledgeSyncEnvelope(
      id: envelope.id,
      entityType: envelope.entityType,
      schemaVersion: envelope.schemaVersion,
      updatedAt: envelope.updatedAt,
      deletedAt: envelope.deletedAt,
      sourceRefs: envelope.sourceRefs,
      conflictStatus: KnowledgeSyncConflictStatus.pendingReview,
      conflictReason: reason,
      payload: envelope.payload,
    );
  }
}

enum KnowledgeExportFormat {
  markdown('markdown'),
  html('html'),
  anki('anki'),
  sourceCitationManifest('source-citation-manifest');

  const KnowledgeExportFormat(this.asString);

  final String asString;
}

@immutable
class KnowledgeExportManifest {
  const KnowledgeExportManifest({
    required this.id,
    required this.createdAt,
    required this.formats,
    this.entityIds = const <String>[],
    this.includeDrafts = false,
    this.includeFullEvidenceText = false,
    this.sourceRefs = const <SourceRef>[],
  });

  final String id;
  final int createdAt;
  final List<KnowledgeExportFormat> formats;
  final List<String> entityIds;
  final bool includeDrafts;
  final bool includeFullEvidenceText;
  final List<SourceRef> sourceRefs;

  bool get safeByDefault => !includeDrafts && !includeFullEvidenceText;

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt,
        'formats':
            formats.map((format) => format.asString).toList(growable: false),
        'entityIds': entityIds,
        'includeDrafts': includeDrafts,
        'includeFullEvidenceText': includeFullEvidenceText,
        'sourceRefs':
            sourceRefs.map((ref) => ref.toSafeJson()).toList(growable: false),
      };
}
