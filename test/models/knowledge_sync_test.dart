import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/knowledge_sync.dart';
import 'package:papertok_reader/models/source_ref.dart';

void main() {
  SourceRef ref() => SourceRef(
        bookId: 1,
        href: 'Text/ch.xhtml',
        sourceTextSnippet: List.filled(700, 'x').join(),
        sourceKind: SourceRefKind.reader,
      );

  test('per-entity sync envelope supports tombstones and conflict review', () {
    final envelope = KnowledgeSyncEnvelope(
      id: 'card1',
      entityType: KnowledgeSyncEntityType.knowledgeCard,
      schemaVersion: 1,
      updatedAt: 100,
      deletedAt: 120,
      conflictStatus: KnowledgeSyncConflictStatus.pendingReview,
      conflictReason: 'remote modified after local delete',
      sourceRefs: [ref()],
      payload: const {'title': 'Card'},
    );

    expect(envelope.isTombstone, true);
    expect(envelope.shouldSyncByDefault, true);
    expect(envelope.requiresConflictReview, true);

    final restored = KnowledgeSyncEnvelope.fromJson(envelope.toJson());
    expect(restored.deletedAt, 120);
    expect(restored.sourceRefs.single.sourceTextSnippet!.length,
        lessThanOrEqualTo(SourceRef.maxSnippetChars));
  });

  test('AI drafts do not sync by default', () {
    const draft = KnowledgeSyncEnvelope(
      id: 'draft1',
      entityType: KnowledgeSyncEntityType.aiDraft,
      schemaVersion: 1,
      updatedAt: 100,
      payload: {'text': 'draft'},
    );

    expect(draft.shouldSyncByDefault, false);
  });

  test('export manifest is safe by default', () {
    final manifest = KnowledgeExportManifest(
      id: 'export1',
      createdAt: 100,
      formats: const [
        KnowledgeExportFormat.markdown,
        KnowledgeExportFormat.sourceCitationManifest,
      ],
      entityIds: const ['card1'],
      sourceRefs: [ref()],
    );

    expect(manifest.safeByDefault, true);
    final json = manifest.toJson();
    expect(json['includeDrafts'], false);
    expect(json['includeFullEvidenceText'], false);
    expect(json['formats'], contains('source-citation-manifest'));
  });

  test('default sync set excludes drafts derived cache and secret payloads',
      () {
    final card = KnowledgeSyncEnvelope(
      id: 'card1',
      entityType: KnowledgeSyncEntityType.knowledgeCard,
      schemaVersion: 1,
      updatedAt: 100,
      sourceRefs: [ref()],
      payload: const {'title': 'Card'},
    );
    const draft = KnowledgeSyncEnvelope(
      id: 'draft1',
      entityType: KnowledgeSyncEntityType.aiDraft,
      schemaVersion: 1,
      updatedAt: 100,
      payload: {'title': 'Draft'},
    );
    const derivedIndex = KnowledgeSyncEnvelope(
      id: 'index1',
      entityType: KnowledgeSyncEntityType.derivedIndex,
      schemaVersion: 1,
      updatedAt: 100,
      payload: {'path': 'ai_index.db'},
    );
    const secretLike = KnowledgeSyncEnvelope(
      id: 'bad1',
      entityType: KnowledgeSyncEntityType.knowledgeCard,
      schemaVersion: 1,
      updatedAt: 100,
      payload: {
        'title': 'Bad',
        'provider': {'apiKey': 'must-not-sync'}
      },
    );
    const nestedSecrets = KnowledgeSyncEnvelope(
      id: 'bad2',
      entityType: KnowledgeSyncEntityType.knowledgeCard,
      schemaVersion: 1,
      updatedAt: 100,
      payload: {
        'providers': [
          {'openaiApiKey': 'must-not-sync'},
          {'authToken': 'must-not-sync'},
          {'bearerToken': 'must-not-sync'},
          {'authorization': 'must-not-sync'},
          {'xApiKey': 'must-not-sync'},
        ]
      },
    );

    final plan = KnowledgeSyncPolicy.planDefaultSync([
      card,
      draft,
      derivedIndex,
      secretLike,
      nestedSecrets,
    ]);

    expect(plan.included.map((e) => e.id), ['card1']);
    expect(
      plan.excluded.map((e) => e.id),
      ['draft1', 'index1', 'bad1', 'bad2'],
    );
    expect(plan.excludedReasonFor('bad1'), 'contains-secret');
    expect(plan.excludedReasonFor('bad2'), 'contains-secret');
    expect(plan.excludedReasonFor('index1'), 'not-default-sync-entity');
  });

  test('secret payload detector rejects exact auth and bearer aliases', () {
    for (final key in const ['auth', 'bearer', 'x-auth']) {
      final envelope = KnowledgeSyncEnvelope(
        id: 'secret-$key',
        entityType: KnowledgeSyncEntityType.knowledgeCard,
        schemaVersion: 1,
        updatedAt: 100,
        payload: {
          'provider': {key: 'must-not-sync'},
        },
      );

      final plan = KnowledgeSyncPolicy.planDefaultSync([envelope]);

      expect(plan.included, isEmpty, reason: key);
      expect(plan.excluded.single.id, 'secret-$key', reason: key);
      expect(plan.excludedReasonFor('secret-$key'), 'contains-secret');
    }
  });

  test('default sync set holds conflict envelopes for review', () {
    const conflict = KnowledgeSyncEnvelope(
      id: 'conflict1',
      entityType: KnowledgeSyncEntityType.knowledgeCard,
      schemaVersion: 1,
      updatedAt: 100,
      conflictStatus: KnowledgeSyncConflictStatus.pendingReview,
      conflictReason: 'content-conflict',
      payload: {'title': 'Conflicting Card'},
    );

    final plan = KnowledgeSyncPolicy.planDefaultSync([conflict]);

    expect(plan.included, isEmpty);
    expect(plan.excluded.single.id, 'conflict1');
    expect(plan.excludedReasonFor('conflict1'), 'pending-conflict-review');
  });

  test('incoming schema and delete-modify conflicts enter review', () {
    const local = KnowledgeSyncEnvelope(
      id: 'card1',
      entityType: KnowledgeSyncEntityType.knowledgeCard,
      schemaVersion: 1,
      updatedAt: 200,
      payload: {'title': 'Local edit'},
    );
    const remoteDeleted = KnowledgeSyncEnvelope(
      id: 'card1',
      entityType: KnowledgeSyncEntityType.knowledgeCard,
      schemaVersion: 1,
      updatedAt: 210,
      deletedAt: 210,
      payload: {},
    );
    const futureSchema = KnowledgeSyncEnvelope(
      id: 'card2',
      entityType: KnowledgeSyncEntityType.knowledgeCard,
      schemaVersion: 99,
      updatedAt: 100,
      payload: {'title': 'Future'},
    );

    final deleteModify = KnowledgeSyncConflictDetector.reviewEnvelopeFor(
      local: local,
      remote: remoteDeleted,
      currentSchemaVersion: 1,
    );
    final unknownSchema = KnowledgeSyncConflictDetector.reviewEnvelopeFor(
      local: null,
      remote: futureSchema,
      currentSchemaVersion: 1,
    );

    expect(deleteModify.requiresConflictReview, true);
    expect(deleteModify.conflictReason, 'delete-modify-conflict');
    expect(unknownSchema.requiresConflictReview, true);
    expect(unknownSchema.conflictReason, 'unknown-schema-version');
  });

  test('missing required sync envelope fields enter conflict review', () {
    final missingFields = KnowledgeSyncEnvelope.fromJson(const {
      'id': 'card-missing',
      'entityType': 'knowledge-card',
    });

    expect(missingFields.requiresConflictReview, true);
    expect(missingFields.conflictReason, 'missing-required-fields');

    final reviewed = KnowledgeSyncConflictDetector.reviewEnvelopeFor(
      local: null,
      remote: missingFields,
      currentSchemaVersion: 1,
    );
    expect(reviewed.requiresConflictReview, true);
    expect(reviewed.conflictReason, 'missing-required-fields');
  });

  test('missing conflictStatus alone does not force conflict review', () {
    final restored = KnowledgeSyncEnvelope.fromJson(const {
      'id': 'card-ok',
      'entityType': 'knowledge-card',
      'schemaVersion': 1,
      'updatedAt': 100,
      'payload': {'title': 'Card'},
    });

    expect(restored.requiresConflictReview, false);
    expect(restored.conflictReason, isNull);
  });
}
