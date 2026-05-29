import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:papertok_reader/service/memory/memory_candidate.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';
import 'package:path/path.dart' as p;

class MemoryEntrySourceRefAdapter {
  const MemoryEntrySourceRefAdapter._();

  static List<SourceRef> sourceRefsForEntry({
    required MemoryEntryRef entry,
    required String body,
    required Iterable<MemoryCandidate> candidates,
  }) {
    final targetDoc = _targetDocForEntry(entry);
    final refs = <SourceRef>[];
    final seen = <String>{};

    for (final candidate in candidates) {
      if (!candidate.isApplied) continue;
      if (candidate.effectiveTargetDoc != targetDoc) continue;
      if (!_candidateAppearsInBody(candidate, body)) continue;

      final reviewItem =
          MemoryCandidateReviewAdapter.fromMemoryCandidate(candidate);
      for (final ref in reviewItem.sourceRefs) {
        if (!ref.hasEvidence) continue;
        if (seen.add(_dedupeKey(ref))) {
          refs.add(ref);
        }
      }
    }

    return refs;
  }

  static MemoryDocTarget _targetDocForEntry(MemoryEntryRef entry) {
    final fileName = p.basename(entry.path);
    if (fileName == MarkdownMemoryStore.longTermFileName) {
      return MemoryDocTarget.longTerm;
    }
    return MemoryDocTarget.daily;
  }

  static bool _candidateAppearsInBody(
    MemoryCandidate candidate,
    String body,
  ) {
    final normalizedBody = _normalize(body);
    if (normalizedBody.isEmpty) return false;

    final texts = <String>{
      candidate.text,
      candidate.effectiveDisplayText,
    };
    for (final text in texts) {
      final normalizedText = _normalize(text);
      if (normalizedText.isEmpty) continue;
      if (normalizedBody.contains(normalizedText)) return true;
    }
    return false;
  }

  static String _normalize(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  }

  static String _dedupeKey(SourceRef ref) {
    return [
      ref.jumpLink ?? '',
      ref.sourceHash ?? '',
      ref.unavailableReason ?? '',
      ref.sourceTextSnippet ?? '',
      ref.sourceKind.asString,
      ref.sourceTitle ?? '',
      ref.locationLabel ?? '',
    ].join('|');
  }
}
