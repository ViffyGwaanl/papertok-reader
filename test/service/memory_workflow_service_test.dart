import 'dart:io';

import 'package:anx_reader/service/memory/markdown_memory_store.dart';
import 'package:anx_reader/service/memory/memory_candidate.dart';
import 'package:anx_reader/service/memory/memory_candidate_store.dart';
import 'package:anx_reader/service/memory/memory_workflow_service.dart';
import 'package:anx_reader/service/memory/memory_write_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MemoryWorkflowService', () {
    late Directory temp;
    late MarkdownMemoryStore store;
    late MemoryCandidateStore candidateStore;
    late MemoryWorkflowService workflow;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('anx_mem_workflow_test_');
      store = MarkdownMemoryStore(rootDir: temp);
      candidateStore = MemoryCandidateStore(rootDir: temp);
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

    test('review inbox stays separate until candidate is applied', () async {
      final pending = await workflow.addToReviewInbox(
        text: 'Promote this later',
        targetDoc: MemoryDocTarget.daily,
        sourceType: 'chat',
      );

      final pendingList = await workflow.listPendingCandidates();
      expect(pendingList.map((c) => c.id), contains(pending.id));

      final workflowFile = File('${temp.path}/.workflow/review_inbox_v1.json');
      expect(await workflowFile.exists(), isTrue);

      await workflow.applyCandidate(
        pending.id,
        targetDoc: MemoryDocTarget.longTerm,
      );

      final longTerm = await store.read(longTerm: true);
      final allCandidates = await candidateStore.list();

      expect(longTerm, contains('Promote this later'));
      expect(await workflow.listPendingCandidates(), isEmpty);
      expect(allCandidates.single.status, MemoryCandidateStatus.applied);
      expect(allCandidates.single.targetDoc, MemoryDocTarget.longTerm);
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
  });
}
