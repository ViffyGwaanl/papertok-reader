import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';

class SelectionKnowledgeCardProducerResult {
  const SelectionKnowledgeCardProducerResult({
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

class SelectionKnowledgeCardProducer {
  SelectionKnowledgeCardProducer({
    KnowledgeCardStore? cardStore,
    ReviewItemStore? reviewStore,
  })  : cardStore = cardStore ?? KnowledgeCardStore(),
        reviewStore = reviewStore ?? ReviewItemStore();

  final KnowledgeCardStore cardStore;
  final ReviewItemStore reviewStore;

  Future<SelectionKnowledgeCardProducerResult> createFromSelection({
    required int bookId,
    required String cfi,
    required String selectedText,
    String? chapterTitle,
    String? bookTitle,
    int? now,
  }) {
    final normalizedText = _normalizeSelectedText(selectedText);
    if (normalizedText.isEmpty) {
      throw ArgumentError.value(
        selectedText,
        'selectedText',
        'Selection text cannot be blank.',
      );
    }

    return _createFromNormalizedSelection(
      bookId: bookId,
      cfi: cfi,
      normalizedText: normalizedText,
      chapterTitle: chapterTitle,
      bookTitle: bookTitle,
      now: now,
    );
  }

  Future<SelectionKnowledgeCardProducerResult> _createFromNormalizedSelection({
    required int bookId,
    required String cfi,
    required String normalizedText,
    String? chapterTitle,
    String? bookTitle,
    int? now,
  }) async {
    final timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
    final intent = PaperReaderReaderIntent(bookId: bookId, cfi: cfi);
    final sourceRef = SourceRef(
      bookId: bookId,
      cfi: cfi,
      jumpLink: intent.hasTarget ? intent.toUri().toString() : null,
      sourceTitle: bookTitle,
      locationLabel: chapterTitle,
      sourceTextSnippet: normalizedText,
      sourceTextForHash: normalizedText,
      sourceKind: SourceRefKind.reader,
      createdAt: timestamp,
    );

    final candidate = KnowledgeCard(
      id: _cardIdFromSourceRef(bookId: bookId, sourceRef: sourceRef),
      title: _titleFromSelection(normalizedText),
      quote: normalizedText,
      explanation: _explanationFromSelection(
        chapterTitle: chapterTitle,
        bookTitle: bookTitle,
      ),
      sourceRefs: [sourceRef],
      reviewState: KnowledgeCardReviewState.pending,
      origin: KnowledgeCardOrigin.selection,
      ownership: AiOutputOwnership.aiGeneratedDraft,
      createdAt: timestamp,
      updatedAt: timestamp,
    );

    final upsert = await cardStore.upsertCandidate(candidate);
    final reviewItem = KnowledgeCardReviewAdapter.fromKnowledgeCard(
      upsert.card,
      now: timestamp,
    );

    try {
      final storedReviewItem = await reviewStore.upsert(reviewItem);
      return SelectionKnowledgeCardProducerResult(
        card: upsert.card,
        inserted: upsert.inserted,
        duplicateOfId: upsert.duplicateOfId,
        addedToReviewInbox: true,
        reviewItem: storedReviewItem,
      );
    } on ArgumentError {
      return SelectionKnowledgeCardProducerResult(
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
    if (suffix.isNotEmpty) {
      return 'selection:$bookId:$suffix';
    }
    return 'selection:$bookId:${DateTime.now().microsecondsSinceEpoch}';
  }

  static String _normalizeSelectedText(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _titleFromSelection(String value) {
    final firstSentence = value.split(RegExp(r'(?<=[.!?。！？])\s+')).first.trim();
    final title = firstSentence.isEmpty ? value : firstSentence;
    if (title.length <= 80) return title;
    return '${title.substring(0, 77)}...';
  }

  static String _explanationFromSelection({
    String? chapterTitle,
    String? bookTitle,
  }) {
    final location = [bookTitle, chapterTitle]
        .map((value) => value?.trim() ?? '')
        .where((value) => value.isNotEmpty)
        .join(' / ');
    if (location.isEmpty) {
      return 'Selected passage saved for review.';
    }
    return 'Selected passage saved for review from $location.';
  }
}
