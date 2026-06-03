import 'package:crypto/crypto.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/rag/semantic_search_library.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';

class RagEvidenceKnowledgeCardProducerResult {
  const RagEvidenceKnowledgeCardProducerResult({
    required this.card,
    required this.inserted,
    required this.addedToReviewInbox,
    this.duplicateOfId,
    this.reviewItem,
  });

  final KnowledgeCard card;
  final bool inserted;
  final bool addedToReviewInbox;
  final String? duplicateOfId;
  final ReviewItem? reviewItem;
}

class RagEvidenceKnowledgeCardProducer {
  RagEvidenceKnowledgeCardProducer({
    KnowledgeCardStore? cardStore,
    ReviewItemStore? reviewStore,
  })  : cardStore = cardStore ?? KnowledgeCardStore(),
        reviewStore = reviewStore ?? ReviewItemStore();

  static const int maxExplanationChars = 1200;

  final KnowledgeCardStore cardStore;
  final ReviewItemStore reviewStore;

  Future<RagEvidenceKnowledgeCardProducerResult> createFromLibrarySearchResult(
    AiSemanticSearchLibraryResult result, {
    bool createReviewItem = false,
    int? now,
  }) async {
    final query = _normalize(result.query);
    if (!result.ok || query.isEmpty) {
      throw ArgumentError.value(
        result.query,
        'result.query',
        'RAG result must be successful and have a non-blank query.',
      );
    }

    final evidence =
        result.evidence.where(_isTraceableRagEvidence).toList(growable: false);
    if (evidence.isEmpty) {
      throw ArgumentError.value(
        result.evidence.length,
        'result.evidence',
        'RAG result must include traceable chunk SourceRef evidence.',
      );
    }

    final timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
    final sourceRefs = evidence
        .map((item) => item.sourceRef)
        .whereType<SourceRef>()
        .toList(growable: false);
    final quote = _quoteFromEvidence(evidence);
    final explanation = _explanationFromEvidence(
      result,
      evidence,
      createReviewItem: createReviewItem,
    );
    final candidate = KnowledgeCard(
      id: _cardId(query: query, sourceRefs: sourceRefs),
      title: _titleFromQuery(query),
      quote: quote,
      explanation: explanation,
      sourceRefs: sourceRefs,
      tags: const ['rag-evidence'],
      reviewState: createReviewItem
          ? KnowledgeCardReviewState.pending
          : KnowledgeCardReviewState.draft,
      origin: KnowledgeCardOrigin.ragEvidence,
      ownership: AiOutputOwnership.aiGeneratedDraft,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    final upsert = await cardStore.upsertCandidate(candidate);
    if (!createReviewItem) {
      return RagEvidenceKnowledgeCardProducerResult(
        card: upsert.card,
        inserted: upsert.inserted,
        duplicateOfId: upsert.duplicateOfId,
        addedToReviewInbox: false,
      );
    }

    final reviewItem = KnowledgeCardReviewAdapter.fromKnowledgeCard(
      upsert.card,
      now: timestamp,
    );

    try {
      final storedReviewItem = await reviewStore.upsert(reviewItem);
      return RagEvidenceKnowledgeCardProducerResult(
        card: upsert.card,
        inserted: upsert.inserted,
        duplicateOfId: upsert.duplicateOfId,
        addedToReviewInbox: true,
        reviewItem: storedReviewItem,
      );
    } on ArgumentError {
      return RagEvidenceKnowledgeCardProducerResult(
        card: upsert.card,
        inserted: upsert.inserted,
        duplicateOfId: upsert.duplicateOfId,
        addedToReviewInbox: false,
      );
    }
  }

  static bool _isTraceableRagEvidence(AiSemanticSearchLibraryEvidence item) {
    final ref = item.sourceRef;
    if (ref == null) return false;
    if (!ref.hasEvidence) return false;
    if (!ref.hasDerivedChunkHint) return false;
    return _normalize(ref.sourceTextSnippet ?? item.snippet).isNotEmpty;
  }

  static String _quoteFromEvidence(
    List<AiSemanticSearchLibraryEvidence> evidence,
  ) {
    for (final item in evidence) {
      final snippet = _normalize(
        item.sourceRef?.sourceTextSnippet ?? item.snippet,
      );
      if (snippet.isNotEmpty) return _clip(snippet, SourceRef.maxSnippetChars);
    }
    return 'Traceable RAG evidence saved for review.';
  }

  static String _explanationFromEvidence(
    AiSemanticSearchLibraryResult result,
    List<AiSemanticSearchLibraryEvidence> evidence, {
    required bool createReviewItem,
  }) {
    final summary = evidence
        .map((item) => item.derivedSummary ?? '')
        .map(_normalize)
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (summary.isNotEmpty) {
      return _clip(summary, maxExplanationChars);
    }
    final books = evidence
        .map((item) => item.bookTitle.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .take(3)
        .join(', ');
    final suffix = books.isEmpty ? '' : ' from $books';
    final action = createReviewItem ? 'saved for review' : 'saved as draft';
    return _clip(
      'RAG evidence $action$suffix.',
      maxExplanationChars,
    );
  }

  static String _cardId({
    required String query,
    required List<SourceRef> sourceRefs,
  }) {
    final seed = [
      query,
      ...sourceRefs.map((ref) => ref.sourceHash ?? ''),
    ].where((value) => value.trim().isNotEmpty).join('\n');
    final digest = sha256.convert(seed.codeUnits).toString();
    return 'rag-evidence:${digest.substring(0, 24)}';
  }

  static String _titleFromQuery(String query) {
    final normalized = _normalize(query);
    final title = 'RAG: $normalized';
    if (title.length <= 80) return title;
    return '${title.substring(0, 77)}...';
  }

  static String _normalize(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _clip(String value, int maxChars) {
    final normalized = _normalize(value);
    if (normalized.length <= maxChars) return normalized;
    return '${normalized.substring(0, maxChars - 3)}...';
  }
}
