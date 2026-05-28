import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';

void main() {
  SourceRef ref() => SourceRef(
        bookId: 1,
        href: 'Text/ch.xhtml',
        sourceTextSnippet: 'evidence',
        sourceKind: SourceRefKind.currentBookRag,
      );

  group('ReviewItem', () {
    test('status flow tracks approve and apply decisions', () {
      final draft = ReviewItem(
        id: 'r1',
        sourceType: ReviewItemSourceType.knowledgeCard,
        sourceId: 'card1',
        title: 'Review card',
        body: 'Candidate body',
        sourceRefs: [ref()],
        createdAt: 100,
      );

      final pending = draft.transitionTo(
        ReviewItemStatus.pending,
        now: 110,
      );
      final approved = pending.transitionTo(
        ReviewItemStatus.approved,
        now: 120,
        decisionSource: 'user_approve',
      );
      final applied = approved.transitionTo(
        ReviewItemStatus.applied,
        now: 130,
      );

      expect(applied.status, ReviewItemStatus.applied);
      expect(applied.decidedAt, 120);
      expect(applied.appliedAt, 130);
      expect(applied.decisionSource, 'user_approve');
      expect(applied.hasTraceableSource, true);

      final restored = ReviewItem.fromJson(applied.toJson());
      expect(restored.sourceRefs.single.jumpLink, isNull);
      expect(restored.status, ReviewItemStatus.applied);
    });

    test('invalid transitions are rejected', () {
      final pending = ReviewItem(
        id: 'r1',
        sourceType: ReviewItemSourceType.seminarSynthesis,
        sourceId: 's1',
        title: 'Seminar',
        body: 'Candidate',
        status: ReviewItemStatus.pending,
      );

      expect(
        () => pending.transitionTo(ReviewItemStatus.applied, now: 1),
        throwsStateError,
      );
    });

    test('approved item without traceable source cannot be applied', () {
      final approved = ReviewItem(
        id: 'r2',
        sourceType: ReviewItemSourceType.flashcardCandidate,
        sourceId: 'f1',
        title: 'Question',
        body: 'Answer',
        status: ReviewItemStatus.approved,
      );

      expect(approved.canApply, isFalse);
      expect(
        () => approved.transitionTo(ReviewItemStatus.applied, now: 2),
        throwsStateError,
      );
    });

    test('applied item without source refs is rejected or downgraded', () {
      final direct = ReviewItem(
        id: 'r3',
        sourceType: ReviewItemSourceType.knowledgeCard,
        sourceId: 'card1',
        title: 'Card',
        body: 'Body',
        status: ReviewItemStatus.applied,
      );
      expect(direct.status, ReviewItemStatus.approved);

      final restored = ReviewItem.fromJson(const {
        'id': 'r3',
        'sourceType': 'knowledge-card',
        'sourceId': 'card1',
        'title': 'Card',
        'body': 'Body',
        'status': 'applied',
        'sourceRefs': [],
      });

      expect(restored.status, ReviewItemStatus.approved);
      expect(restored.canApply, isFalse);
    });

    test('applied item with hash-only source ref is downgraded', () {
      final item = ReviewItem(
        id: 'r4',
        sourceType: ReviewItemSourceType.knowledgeCard,
        sourceId: 'card1',
        title: 'Card',
        body: 'Body',
        status: ReviewItemStatus.applied,
        sourceRefs: [
          SourceRef(
            sourceTextSnippet: 'detached text',
            sourceKind: SourceRefKind.external,
          ),
        ],
        appliedAt: 200,
      );

      expect(item.sourceRefs.single.sourceHash, isNotNull);
      expect(item.sourceRefs.single.hasEvidence, isFalse);
      expect(item.status, ReviewItemStatus.approved);
      expect(item.appliedAt, isNull);
    });
  });

  group('SpacedReviewItem', () {
    test('review item records traceable history without binding an algorithm',
        () {
      final item = SpacedReviewItem(
        id: 'sr1',
        cardId: 'card1',
        prompt: 'What is the hidden premise?',
        answer: 'The premise.',
        sourceRefs: [ref()],
        dueAt: 100,
      );

      expect(item.isDue(101), true);

      final reviewed = item.recordReview(
        reviewedAt: 120,
        rating: 'again',
        nextDueAt: 180,
        nextIntervalDays: 1,
        note: 'Still unclear.',
      );

      expect(reviewed.lastReviewedAt, 120);
      expect(reviewed.dueAt, 180);
      expect(reviewed.lapses, 1);
      expect(reviewed.reviewHistory.single.rating, 'again');

      final restored = SpacedReviewItem.fromJson(reviewed.toJson());
      expect(restored.cardId, 'card1');
      expect(restored.sourceRefs.single.bookId, 1);
      expect(restored.reviewHistory.single.note, 'Still unclear.');
    });
  });
}
