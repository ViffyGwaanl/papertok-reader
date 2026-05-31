import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/knowledge_sync.dart';

void main() {
  KnowledgeSyncEnvelope envelope(
    String id, {
    required int updatedAt,
    Map<String, dynamic> payload = const {'title': 'Card'},
    int schemaVersion = 1,
    int? deletedAt,
  }) {
    return KnowledgeSyncEnvelope(
      id: id,
      entityType: KnowledgeSyncEntityType.knowledgeCard,
      schemaVersion: schemaVersion,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      payload: payload,
    );
  }

  test('same id with same content hash is unchanged', () {
    final local = envelope('card-1', updatedAt: 200);
    final remote = envelope('card-1', updatedAt: 300);

    final plan = KnowledgeRemoteMergePlanner.plan(
      local: [local],
      remote: [remote],
      base: [envelope('card-1', updatedAt: 100)],
    );

    expect(plan.unchanged.map((e) => e.id), ['card-1']);
    expect(plan.incoming, isEmpty);
    expect(plan.outgoing, isEmpty);
    expect(plan.conflicts, isEmpty);
  });

  test('local newer than base becomes outgoing without remote blocker', () {
    final plan = KnowledgeRemoteMergePlanner.plan(
      local: [
        envelope('card-1', updatedAt: 300, payload: const {'title': 'Local'}),
      ],
      remote: [envelope('card-1', updatedAt: 100)],
      base: [envelope('card-1', updatedAt: 100)],
    );

    expect(plan.outgoing.map((e) => e.id), ['card-1']);
    expect(plan.incoming, isEmpty);
    expect(plan.conflicts, isEmpty);
  });

  test('remote newer than base becomes incoming without local blocker', () {
    final plan = KnowledgeRemoteMergePlanner.plan(
      local: [envelope('card-1', updatedAt: 100)],
      remote: [
        envelope('card-1', updatedAt: 300, payload: const {'title': 'Remote'}),
      ],
      base: [envelope('card-1', updatedAt: 100)],
    );

    expect(plan.incoming.map((e) => e.id), ['card-1']);
    expect(plan.outgoing, isEmpty);
    expect(plan.conflicts, isEmpty);
  });

  test('delete modify conflict enters review', () {
    final plan = KnowledgeRemoteMergePlanner.plan(
      local: [
        envelope('card-1', updatedAt: 300, deletedAt: 300, payload: const {}),
      ],
      remote: [
        envelope('card-1', updatedAt: 250, payload: const {'title': 'Remote'}),
      ],
      base: [envelope('card-1', updatedAt: 100)],
    );

    expect(plan.conflicts, hasLength(1));
    expect(plan.conflicts.single.requiresConflictReview, true);
    expect(plan.conflicts.single.conflictReason, 'delete-modify-conflict');
    expect(plan.incoming, isEmpty);
    expect(plan.outgoing, isEmpty);
  });

  test('unknown schema and secret payload enter review', () {
    final plan = KnowledgeRemoteMergePlanner.plan(
      local: const [],
      remote: [
        envelope(
          'future-card',
          updatedAt: 100,
          schemaVersion: 99,
          payload: const {'title': 'Future'},
        ),
        envelope(
          'secret-card',
          updatedAt: 100,
          payload: const {
            'title': 'Secret',
            'provider': {'apiKey': 'must-not-sync'},
          },
        ),
      ],
      currentSchemaVersion: 1,
    );

    expect(plan.incoming, isEmpty);
    expect(plan.conflicts.map((e) => e.id), ['future-card', 'secret-card']);
    expect(
      plan.conflicts.map((e) => e.conflictReason),
      ['unknown-schema-version', 'contains-secret'],
    );
    expect(plan.conflicts.every((e) => e.requiresConflictReview), true);
  });

  test('does not whole-file newer-wins when both sides changed', () {
    final plan = KnowledgeRemoteMergePlanner.plan(
      local: [
        envelope(
          'card-1',
          updatedAt: 200,
          payload: const {'title': 'Local'},
        ),
      ],
      remote: [
        envelope(
          'card-1',
          updatedAt: 300,
          payload: const {'title': 'Remote'},
        ),
      ],
      base: [envelope('card-1', updatedAt: 100)],
    );

    expect(plan.incoming, isEmpty);
    expect(plan.outgoing, isEmpty);
    expect(plan.conflicts, hasLength(1));
    expect(plan.conflicts.single.conflictReason, 'content-conflict');
    expect(plan.hasReviewBlockers, true);
  });

  test('different content without base is conservative conflict', () {
    final plan = KnowledgeRemoteMergePlanner.plan(
      local: [
        envelope('card-1', updatedAt: 200, payload: const {'title': 'Local'}),
      ],
      remote: [
        envelope('card-1', updatedAt: 300, payload: const {'title': 'Remote'}),
      ],
    );

    expect(plan.incoming, isEmpty);
    expect(plan.outgoing, isEmpty);
    expect(plan.conflicts.single.conflictReason, 'content-conflict');
  });

  test('duplicate ids enter review instead of last-wins', () {
    final plan = KnowledgeRemoteMergePlanner.plan(
      local: [envelope('card-1', updatedAt: 100)],
      remote: [
        envelope('card-2', updatedAt: 200, payload: const {'title': 'A'}),
        envelope('card-2', updatedAt: 300, payload: const {'title': 'B'}),
      ],
    );

    expect(plan.incoming.map((e) => e.id), isNot(contains('card-2')));
    expect(plan.conflicts.map((e) => e.id), contains('card-2'));
    expect(plan.conflicts.last.conflictReason, 'duplicate-remote-id');
  });

  test('malformed envelope without id enters review instead of disappearing',
      () {
    final malformed = KnowledgeSyncEnvelope.fromJson({
      'entityType': 'knowledge-card',
      'schemaVersion': 1,
      'updatedAt': 100,
      'payload': {'title': 'Remote'},
    });

    final plan = KnowledgeRemoteMergePlanner.plan(
      local: const [],
      remote: [malformed, envelope('card-1', updatedAt: 100)],
    );

    expect(plan.incoming.map((e) => e.id), ['card-1']);
    expect(plan.conflicts, hasLength(1));
    expect(plan.conflicts.single.id, isEmpty);
    expect(plan.conflicts.single.requiresConflictReview, true);
    expect(plan.conflicts.single.conflictReason, 'missing-required-fields');
  });

  test('whitespace padded id enters review instead of disappearing', () {
    final plan = KnowledgeRemoteMergePlanner.plan(
      local: const [],
      remote: [envelope(' card-1 ', updatedAt: 100)],
    );

    expect(plan.incoming, isEmpty);
    expect(plan.outgoing, isEmpty);
    expect(plan.conflicts, hasLength(1));
    expect(plan.conflicts.single.id, ' card-1 ');
    expect(plan.conflicts.single.conflictReason, 'malformed-id');
  });

  test('unsafe base envelope enters review before diff decisions', () {
    final plan = KnowledgeRemoteMergePlanner.plan(
      local: [envelope('future-card', updatedAt: 200)],
      remote: [envelope('future-card', updatedAt: 300)],
      base: [
        envelope(
          'future-card',
          updatedAt: 100,
          schemaVersion: 99,
        ),
        envelope(
          'secret-base',
          updatedAt: 100,
          payload: const {
            'title': 'Base',
            'provider': {'apiKey': 'must-not-sync'},
          },
        ),
      ],
      currentSchemaVersion: 1,
    );

    expect(plan.incoming, isEmpty);
    expect(plan.outgoing, isEmpty);
    expect(plan.conflicts.map((e) => e.id), ['future-card', 'secret-base']);
    expect(
      plan.conflicts.map((e) => e.conflictReason),
      ['unknown-schema-version', 'contains-secret'],
    );
  });
}
