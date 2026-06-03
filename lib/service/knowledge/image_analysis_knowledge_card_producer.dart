import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';

class ImageAnalysisKnowledgeCardProducerResult {
  const ImageAnalysisKnowledgeCardProducerResult({
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

class ImageAnalysisKnowledgeCardProducer {
  ImageAnalysisKnowledgeCardProducer({
    KnowledgeCardStore? cardStore,
    ReviewItemStore? reviewStore,
  })  : cardStore = cardStore ?? KnowledgeCardStore(),
        reviewStore = reviewStore ?? ReviewItemStore();

  final KnowledgeCardStore cardStore;
  final ReviewItemStore reviewStore;

  Future<ImageAnalysisKnowledgeCardProducerResult> createFromImageAnalysis({
    required int bookId,
    required String analysisText,
    String? cfi,
    String? href,
    String? imageTitle,
    String? imageAlt,
    String? contextText,
    String? chapterTitle,
    String? bookTitle,
    bool createReviewItem = false,
    int? now,
  }) async {
    final normalizedAnalysis = _normalize(analysisText);
    if (normalizedAnalysis.isEmpty) {
      throw ArgumentError.value(
        analysisText,
        'analysisText',
        'Image analysis text cannot be blank.',
      );
    }

    final timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
    final normalizedCfi = _blankToNull(cfi);
    final normalizedHref = _blankToNull(href);
    final intent = PaperReaderReaderIntent(
      bookId: bookId,
      cfi: normalizedCfi,
      href: normalizedHref,
    );
    final sourceSnippet = _sourceSnippet(
      contextText: contextText,
      imageAlt: imageAlt,
      imageTitle: imageTitle,
      bookTitle: bookTitle,
    );
    final sourceRef = SourceRef(
      bookId: bookId,
      cfi: normalizedCfi,
      href: normalizedHref,
      jumpLink: intent.hasTarget ? intent.toUri().toString() : null,
      sourceTitle: bookTitle,
      locationLabel: _locationLabel(
        chapterTitle: chapterTitle,
        imageTitle: imageTitle,
      ),
      sourceTextSnippet: sourceSnippet,
      sourceTextForHash: [
        imageTitle,
        imageAlt,
        contextText,
        normalizedAnalysis,
      ].map((value) => value?.trim() ?? '').join('\n'),
      sourceKind: SourceRefKind.reader,
      createdAt: timestamp,
    );

    final candidate = KnowledgeCard(
      id: _cardIdFromSourceRef(bookId: bookId, sourceRef: sourceRef),
      title: _title(
        analysisText: normalizedAnalysis,
        imageTitle: imageTitle,
      ),
      quote: sourceSnippet,
      explanation: normalizedAnalysis,
      sourceRefs: [sourceRef],
      reviewState: createReviewItem
          ? KnowledgeCardReviewState.pending
          : KnowledgeCardReviewState.draft,
      origin: KnowledgeCardOrigin.imageAnalysis,
      ownership: AiOutputOwnership.aiGeneratedDraft,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    final upsert = await cardStore.upsertCandidate(candidate);
    if (!createReviewItem) {
      return ImageAnalysisKnowledgeCardProducerResult(
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
      return ImageAnalysisKnowledgeCardProducerResult(
        card: upsert.card,
        inserted: upsert.inserted,
        duplicateOfId: upsert.duplicateOfId,
        addedToReviewInbox: true,
        reviewItem: storedReviewItem,
      );
    } on ArgumentError {
      return ImageAnalysisKnowledgeCardProducerResult(
        card: upsert.card,
        inserted: upsert.inserted,
        duplicateOfId: upsert.duplicateOfId,
        addedToReviewInbox: false,
      );
    }
  }

  static String _cardIdFromSourceRef({
    required int bookId,
    required SourceRef sourceRef,
  }) {
    final hash = (sourceRef.sourceHash ?? '').replaceFirst('sha256:', '');
    final suffix = hash.length >= 24 ? hash.substring(0, 24) : hash;
    if (suffix.isNotEmpty) return 'image-analysis:$bookId:$suffix';
    return 'image-analysis:$bookId:${DateTime.now().microsecondsSinceEpoch}';
  }

  static String _title({
    required String analysisText,
    String? imageTitle,
  }) {
    final explicit = _blankToNull(imageTitle);
    if (explicit != null) {
      return explicit.length <= 80
          ? explicit
          : '${explicit.substring(0, 77)}...';
    }
    final firstSentence =
        analysisText.split(RegExp(r'(?<=[.!?。！？])\s+')).first.trim();
    final title = firstSentence.isEmpty ? analysisText : firstSentence;
    if (title.length <= 80) return title;
    return '${title.substring(0, 77)}...';
  }

  static String _sourceSnippet({
    String? contextText,
    String? imageAlt,
    String? imageTitle,
    String? bookTitle,
  }) {
    final parts = [
      contextText,
      imageAlt == null ? null : 'Alt: $imageAlt',
      imageTitle == null ? null : 'Title: $imageTitle',
      bookTitle == null ? null : 'Book image from $bookTitle',
    ]
        .map((value) => _normalize(value ?? ''))
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return 'Image saved as draft knowledge card.';
    return _clipSnippet(parts.join('\n'));
  }

  static String? _locationLabel({
    String? chapterTitle,
    String? imageTitle,
  }) {
    final parts = [
      _blankToNull(chapterTitle),
      _blankToNull(imageTitle),
    ].whereType<String>().toList(growable: false);
    if (parts.isEmpty) return null;
    return parts.join(' / ');
  }

  static String _normalize(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _clipSnippet(String value) {
    final normalized = _normalize(value);
    if (normalized.length <= SourceRef.maxSnippetChars) return normalized;
    return '${normalized.substring(0, SourceRef.maxSnippetChars - 3)}...';
  }

  static String? _blankToNull(String? value) {
    final normalized = _normalize(value ?? '');
    return normalized.isEmpty ? null : normalized;
  }
}
