import 'package:papertok_reader/service/memory/memory_candidate.dart';
import 'package:papertok_reader/service/memory/memory_workflow_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Emits the number of memory candidates currently in the pending state.
/// UI surfaces (the bottom-nav Memory tab badge, the inbox summary card)
/// use this to show unread counts.
///
/// Uses a FutureProvider (not StreamProvider) because the candidate store
/// has no change-notification API — consumers `ref.invalidate` this provider
/// after apply/dismiss actions to refresh the count.
final memoryPendingCountProvider = FutureProvider<int>((ref) async {
  final workflow = MemoryWorkflowService();
  final pending =
      await workflow.listCandidates(status: MemoryCandidateStatus.pending);
  return pending.length;
});
