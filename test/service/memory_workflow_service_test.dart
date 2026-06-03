import 'dart:io';

import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:papertok_reader/service/memory/memory_candidate.dart';
import 'package:papertok_reader/service/memory/memory_candidate_store.dart';
import 'package:papertok_reader/service/memory/memory_workflow_policy.dart';
import 'package:papertok_reader/service/memory/memory_workflow_service.dart';
import 'package:papertok_reader/service/memory/memory_write_coordinator.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';

void main() {
  group('MemoryWorkflowService', () {
    late Directory temp;
    late MarkdownMemoryStore store;
    late MemoryCandidateStore candidateStore;
    late ReviewItemStore reviewStore;
    late MemoryWorkflowService workflow;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('anx_mem_workflow_test_');
      store = MarkdownMemoryStore(rootDir: temp);
      candidateStore = MemoryCandidateStore(rootDir: temp);
      reviewStore = ReviewItemStore(rootDir: temp);
      workflow = MemoryWorkflowService(
        store: store,
        candidateStore: candidateStore,
        writeCoordinator: MemoryWriteCoordinator(store: store),
      );
    });

    tearDown(() async {
      try {
        await temp.delete(recursive: true);
      } catch (_) {
        // Ignore temp cleanup failures.
      }
    });

    test('saveToDaily writes markdown and records applied candidate', () async {
      final candidate = await workflow.saveToDaily(
        text: 'Remember this daily note',
        date: DateTime(2026, 3, 7),
        sourceType: 'chat',
      );

      final daily = await store.read(
        longTerm: false,
        date: DateTime(2026, 3, 7),
      );
      final allCandidates = await candidateStore.list();

      expect(daily, contains('Remember this daily note'));
      expect(candidate.status, MemoryCandidateStatus.applied);
      expect(allCandidates.single.status, MemoryCandidateStatus.applied);
      expect(await workflow.listPendingCandidates(), isEmpty);
    });

    test('undoDirectSave removes direct daily text and dismisses candidate',
        () async {
      final candidate = await workflow.saveToDaily(
        text: 'Undo this directly saved note',
        date: DateTime(2026, 3, 7),
        sourceType: 'chat',
      );

      final undone = await workflow.undoDirectSave(
        candidate.id,
        date: DateTime(2026, 3, 7),
      );

      final daily = await store.read(
        longTerm: false,
        date: DateTime(2026, 3, 7),
      );
      final allCandidates = await candidateStore.list();

      expect(daily, isNot(contains('Undo this directly saved note')));
      expect(undone.status, MemoryCandidateStatus.dismissed);
      expect(undone.decisionSource, 'user_undo_direct_save');
      expect(allCandidates.single.status, MemoryCandidateStatus.dismissed);
    });

    test('review inbox stays separate until candidate is applied', () async {
      final pending = await workflow.addToReviewInbox(
        text: 'Promote this later',
        targetDoc: MemoryDocTarget.daily,
        sourceType: 'chat',
        bookId: 7,
        cfi: 'epubcfi(/6/8!/4/2/12:5)',
        chapter: 'Memory source chapter',
      );

      final pendingList = await workflow.listPendingCandidates();
      expect(pendingList.map((c) => c.id), contains(pending.id));

      final workflowFile = File('${temp.path}/.workflow/review_inbox_v1.json');
      expect(await workflowFile.exists(), isFalse);
      expect(await candidateStore.inboxFile.exists(), isTrue);
      final reviewItem =
          await reviewStore.getById('memory-candidate:${pending.id}');
      expect(reviewItem, isNotNull);
      expect(reviewItem!.sourceId, pending.id);
      expect(reviewItem.sourceRefs.single.hasEvidence, isTrue);

      await workflow.applyCandidate(
        pending.id,
        targetDoc: MemoryDocTarget.longTerm,
      );

      final longTerm = await store.read(longTerm: true);
      final allCandidates = await candidateStore.list();

      expect(longTerm, contains('Promote this later'));
      expect(await workflow.listPendingCandidates(), isEmpty);
      expect(allCandidates.single.status, MemoryCandidateStatus.applied);
      expect(allCandidates.single.targetDoc, MemoryDocTarget.daily);
      expect(allCandidates.single.appliedTargetDoc, MemoryDocTarget.longTerm);
    });

    test('dismissCandidate removes item from pending inbox', () async {
      final pending = await workflow.addToReviewInbox(
        text: 'Discard me',
        targetDoc: MemoryDocTarget.daily,
      );

      await workflow.dismissCandidate(pending.id);

      final allCandidates = await candidateStore.list();
      expect(await workflow.listPendingCandidates(), isEmpty);
      expect(allCandidates.single.status, MemoryCandidateStatus.dismissed);
    });

    test(
        'captureSessionDigest smart-saves high-confidence candidates by default',
        () async {
      final result = await workflow.captureSessionDigest(
        messages: <ChatMessage>[
          HumanChatMessage(
            content: ChatMessageContent.text('以后默认用中文回复，并且结论简短一点'),
          ),
          AIChatMessage(content: '好的，我之后默认用中文，并优先给简洁结论。'),
        ],
        conversationId: 'session-1',
      );

      expect(result.dailyStrategy, MemoryWorkflowDailyStrategy.smartDaily);
      expect(result.writesDailyDirectly, isTrue);
      expect(result.directSaveCount, result.candidates.length);
      expect(result.reviewInboxCount, 0);
      expect(result.candidates, isNotEmpty);
      expect(result.candidates.every((c) => c.isApplied), isTrue);
      expect(
          result.candidates.every((c) => c.targetDoc == MemoryDocTarget.daily),
          isTrue);
      expect(result.candidates.every((c) => c.sourceType == 'session_digest'),
          isTrue);
      expect(result.candidates.every((c) => c.conversationId == 'session-1'),
          isTrue);
      expect(await workflow.listPendingCandidates(), isEmpty);

      final daily = await store.read(longTerm: false, date: DateTime.now());
      expect(daily, contains('中文'));
    });

    test('captureSessionDigest keeps low-confidence smart candidates in review',
        () async {
      final result = await workflow.captureSessionDigest(
        messages: <ChatMessage>[
          HumanChatMessage(content: ChatMessageContent.text('谢谢')),
          AIChatMessage(content: '好的。'),
        ],
        dailyStrategy: MemoryWorkflowDailyStrategy.smartDaily,
        conversationId: 'session-low-confidence',
      );

      expect(result.dailyStrategy, MemoryWorkflowDailyStrategy.smartDaily);
      expect(result.writesDailyDirectly, isFalse);
      expect(result.directSaveCount, 0);
      expect(result.reviewInboxCount, result.candidates.length);
      expect(result.candidates, isNotEmpty);
      expect(result.candidates.every((c) => c.isPending), isTrue);
      expect(await workflow.listPendingCandidates(),
          hasLength(result.candidates.length));

      final daily = await store.read(longTerm: false, date: DateTime.now());
      expect(daily.trim(), isEmpty);
    });

    test('captureSessionDigest can auto-save daily without touching long-term',
        () async {
      final result = await workflow.captureSessionDigest(
        messages: <ChatMessage>[
          HumanChatMessage(
            content: ChatMessageContent.text('今天决定下周先做 Memory M2 收口'),
          ),
          AIChatMessage(content: '已记录：下周优先做 Memory M2 收口。'),
        ],
        dailyStrategy: MemoryWorkflowDailyStrategy.autoDaily,
      );

      expect(result.writesDailyDirectly, isTrue);
      expect(result.candidates, isNotEmpty);
      expect(
          result.candidates
              .every((c) => c.status == MemoryCandidateStatus.applied),
          isTrue);
      expect(await workflow.listPendingCandidates(), isEmpty);

      final daily = await store.read(longTerm: false, date: DateTime.now());
      final longTerm = await store.read(longTerm: true);
      expect(daily, contains('Memory M2'));
      expect(longTerm.trim(), isEmpty);
    });
  });
}
