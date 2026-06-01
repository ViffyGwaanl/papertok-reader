import 'package:crypto/crypto.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/review/knowledge_review_adapter.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';

class AiChatKnowledgeCardProducerResult {
  const AiChatKnowledgeCardProducerResult({
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

class AiChatKnowledgeCardProducer {
  AiChatKnowledgeCardProducer({
    KnowledgeCardStore? cardStore,
    ReviewItemStore? reviewStore,
  })  : cardStore = cardStore ?? KnowledgeCardStore(),
        reviewStore = reviewStore ?? ReviewItemStore();

  static const int maxAnswerChars = 2000;

  final KnowledgeCardStore cardStore;
  final ReviewItemStore reviewStore;

  Future<AiChatKnowledgeCardProducerResult> createFromAssistantAnswer({
    required String assistantAnswer,
    String? userPrompt,
    String? conversationId,
    String? messageNodeId,
    String? modelId,
    int? bookId,
    String? bookTitle,
    String? cfi,
    String? chapterTitle,
    SourceRef? readerSourceRef,
    int? now,
  }) async {
    final answer = _normalize(assistantAnswer);
    if (answer.isEmpty) {
      throw ArgumentError.value(
        assistantAnswer,
        'assistantAnswer',
        'AI chat assistant answer cannot be blank.',
      );
    }

    final timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
    final prompt = _normalize(userPrompt ?? '');
    final sourceRefs = _sourceRefs(
      answer: answer,
      prompt: prompt,
      conversationId: conversationId,
      messageNodeId: messageNodeId,
      modelId: modelId,
      bookId: bookId,
      bookTitle: bookTitle,
      cfi: cfi,
      chapterTitle: chapterTitle,
      readerSourceRef: readerSourceRef,
      now: timestamp,
    );
    final conceptRefs = _hasReaderGrounding(sourceRefs)
        ? _conceptRefs(prompt: prompt, answer: answer)
        : const <String>[];

    final candidate = KnowledgeCard(
      id: _cardId(
        answer: answer,
        prompt: prompt,
        conversationId: conversationId,
        messageNodeId: messageNodeId,
      ),
      title: _title(answer),
      quote: prompt.isEmpty ? 'AI chat answer saved for review.' : prompt,
      explanation: _clip(answer, maxAnswerChars),
      sourceRefs: sourceRefs,
      conceptRefs: conceptRefs,
      tags: const ['ai-chat'],
      reviewState: KnowledgeCardReviewState.pending,
      origin: KnowledgeCardOrigin.aiChat,
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
      return AiChatKnowledgeCardProducerResult(
        card: upsert.card,
        inserted: upsert.inserted,
        duplicateOfId: upsert.duplicateOfId,
        addedToReviewInbox: true,
        reviewItem: storedReviewItem,
      );
    } on ArgumentError {
      return AiChatKnowledgeCardProducerResult(
        card: upsert.card,
        inserted: upsert.inserted,
        duplicateOfId: upsert.duplicateOfId,
        addedToReviewInbox: false,
      );
    }
  }

  static List<SourceRef> _sourceRefs({
    required String answer,
    required String prompt,
    String? conversationId,
    String? messageNodeId,
    String? modelId,
    int? bookId,
    String? bookTitle,
    String? cfi,
    String? chapterTitle,
    SourceRef? readerSourceRef,
    required int now,
  }) {
    final refs = <SourceRef>[
      SourceRef(
        sourceTitle: 'AI Chat',
        locationLabel: _conversationLabel(
          conversationId: conversationId,
          messageNodeId: messageNodeId,
        ),
        sourceTextSnippet: _clip(answer, SourceRef.maxSnippetChars),
        sourceTextForHash: [prompt, answer].join('\n'),
        sourceKind: SourceRefKind.conversation,
        modelId: _blankToNull(modelId),
        createdAt: now,
        unavailableReason: 'ai-chat-no-reader-deep-link',
      ),
    ];

    if (readerSourceRef != null && readerSourceRef.hasEvidence) {
      refs.add(readerSourceRef);
      return refs;
    }

    final normalizedCfi = _blankToNull(cfi);
    if (bookId != null && bookId > 0 && normalizedCfi != null) {
      final intent =
          PaperReaderReaderIntent(bookId: bookId, cfi: normalizedCfi);
      refs.add(
        SourceRef(
          bookId: bookId,
          cfi: normalizedCfi,
          jumpLink: intent.hasTarget ? intent.toUri().toString() : null,
          sourceTitle: _blankToNull(bookTitle),
          locationLabel: _blankToNull(chapterTitle),
          sourceTextSnippet: _clip(
            prompt.isEmpty ? answer : prompt,
            SourceRef.maxSnippetChars,
          ),
          sourceTextForHash: [bookId, normalizedCfi, prompt, answer].join('\n'),
          sourceKind: SourceRefKind.reader,
          createdAt: now,
        ),
      );
    }

    return refs;
  }

  static bool _hasReaderGrounding(List<SourceRef> sourceRefs) {
    return sourceRefs.any((ref) {
      if (ref.sourceKind == SourceRefKind.conversation) return false;
      return ref.hasBookAnchor || ref.canJumpBack;
    });
  }

  static String _conversationLabel({
    String? conversationId,
    String? messageNodeId,
  }) {
    final parts = [
      _blankToNull(conversationId),
      _blankToNull(messageNodeId),
    ].whereType<String>().toList(growable: false);
    if (parts.isEmpty) return 'AI chat message';
    return parts.join('#');
  }

  static String _cardId({
    required String answer,
    required String prompt,
    String? conversationId,
    String? messageNodeId,
  }) {
    final seed = [
      _blankToNull(conversationId) ?? '',
      _blankToNull(messageNodeId) ?? '',
      prompt,
      answer,
    ].join('\n');
    final digest = sha256.convert(seed.codeUnits).toString();
    return 'ai-chat:${digest.substring(0, 24)}';
  }

  static String _title(String answer) {
    final firstSentence =
        answer.split(RegExp(r'(?<=[.!?。！？])\s+')).first.trim();
    final title = firstSentence.isEmpty ? answer : firstSentence;
    if (title.length <= 80) return title;
    return '${title.substring(0, 77)}...';
  }

  static List<String> _conceptRefs({
    required String prompt,
    required String answer,
  }) {
    final labels = <String>[];
    final seen = <String>{};

    void add(String raw) {
      final label = _normalizeConcept(raw);
      if (label == null) return;
      final key = label.toLowerCase();
      if (!seen.add(key)) return;
      labels.add(label);
    }

    for (final text in [prompt, answer]) {
      for (final match in RegExp(r'`([^`]{2,40})`').allMatches(text)) {
        add(match.group(1) ?? '');
        if (labels.length >= 3) return labels;
      }
    }

    for (final match in RegExp(
      r'^\s*([A-Z][A-Za-z0-9 /-]{1,40}|[\u4e00-\u9fff][\u4e00-\u9fffA-Za-z0-9]{1,15})\s+(?:is|are|means|refers to|can be|是|指|表示)\b',
      multiLine: true,
    ).allMatches(answer)) {
      add(match.group(1) ?? '');
      if (labels.length >= 3) return labels;
    }

    for (final text in [prompt, answer]) {
      for (final match in RegExp(
        r'\b(?:[A-Z]{2,}(?:/[A-Z0-9-]+)*|[A-Za-z]+(?:[A-Z][a-z0-9]+)+)\b',
      ).allMatches(text)) {
        add(match.group(0) ?? '');
        if (labels.length >= 3) return labels;
      }
    }

    for (final match in RegExp(
      r'\b([A-Z][a-zA-Z0-9-]{2,24})\b',
    ).allMatches(answer)) {
      add(match.group(1) ?? '');
      if (labels.length >= 3) return labels;
    }

    for (final match in RegExp(
      r'(?:explain|summarize|analyse|analyze|compare|what is|什么是|解释|总结|分析)\s+([^?.!。！？,，;；]{2,40})',
      caseSensitive: false,
    ).allMatches(prompt)) {
      add(_titleCaseConcept(match.group(1) ?? ''));
      if (labels.length >= 3) return labels;
    }

    return labels;
  }

  static String? _normalizeConcept(String value) {
    var label = value
        .replaceAll(RegExp(r'^[\s\p{P}]+|[\s\p{P}]+$', unicode: true), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (label.isEmpty) return null;
    if (label.length < 2 || label.length > 40) return null;
    if (RegExp(r'^\d+$').hasMatch(label)) return null;
    final lower = label.toLowerCase();
    if (_conceptStopWords.contains(lower)) return null;
    if (lower.startsWith('explain ') ||
        lower.startsWith('summarize ') ||
        lower.startsWith('analyse ') ||
        lower.startsWith('analyze ')) {
      return null;
    }
    return label;
  }

  static String _titleCaseConcept(String value) {
    final normalized = _normalize(value);
    if (normalized.isEmpty) return normalized;
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(normalized)) return normalized;
    return normalized
        .split(' ')
        .where((part) => part.trim().isNotEmpty)
        .map((part) {
      final word = part.trim();
      if (word.toUpperCase() == word && word.length <= 8) return word;
      if (word.length <= 1) return word.toUpperCase();
      return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
    }).join(' ');
  }

  static const Set<String> _conceptStopWords = {
    'a',
    'an',
    'and',
    'answer',
    'ai',
    'chat',
    'context',
    'explain',
    'it',
    'mechanism',
    'question',
    'summary',
    'the',
    'this',
    'what',
    'why',
  };

  static String _normalize(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _clip(String value, int maxChars) {
    final normalized = _normalize(value);
    if (normalized.length <= maxChars) return normalized;
    return '${normalized.substring(0, maxChars - 3)}...';
  }

  static String? _blankToNull(String? value) {
    final normalized = _normalize(value ?? '');
    return normalized.isEmpty ? null : normalized;
  }
}
