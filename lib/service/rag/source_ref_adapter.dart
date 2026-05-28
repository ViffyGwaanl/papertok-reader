import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/service/deeplink/paperreader_reader_intent.dart';

class RagSourceRefAdapter {
  const RagSourceRefAdapter._();

  static const String currentBookAlgorithm = 'current-book-rag-v1';
  static const String libraryAlgorithm = 'library-rag-v1';

  static SourceRef currentBook({
    required int bookId,
    required String href,
    required String text,
    String? anchor,
    String? jumpLink,
    int? chunkId,
    String? sourceHash,
    String? providerId,
    String? model,
    int? indexVersion,
    int? contextVersion,
    int? createdAt,
    double? confidence,
  }) {
    return SourceRef(
      bookId: bookId,
      href: href,
      chunkId: _positiveChunkId(chunkId),
      jumpLink: _jumpLink(
        bookId: bookId,
        href: href,
        supplied: jumpLink,
      ),
      sourceTitle: anchor,
      sourceTextSnippet: text,
      sourceTextForHash: text,
      sourceHash: _blankToNull(sourceHash),
      modelId: _modelId(providerId: providerId, model: model),
      algorithmVersion: _algorithmVersion(
        currentBookAlgorithm,
        indexVersion: indexVersion,
        contextVersion: contextVersion,
      ),
      createdAt: createdAt,
      sourceKind: SourceRefKind.currentBookRag,
      confidence: confidence,
    );
  }

  static SourceRef library({
    required int bookId,
    required String href,
    required String snippet,
    String? bookTitle,
    String? anchor,
    String? jumpLink,
    int? chunkId,
    String? sourceHash,
    String? providerId,
    String? model,
    int? indexVersion,
    int? contextVersion,
    int? createdAt,
    double? confidence,
  }) {
    return SourceRef(
      bookId: bookId,
      href: href,
      chunkId: _positiveChunkId(chunkId),
      jumpLink: _jumpLink(
        bookId: bookId,
        href: href,
        supplied: jumpLink,
      ),
      sourceTitle: _blankToNull(bookTitle) ?? anchor,
      locationLabel: anchor,
      sourceTextSnippet: snippet,
      sourceTextForHash: snippet,
      sourceHash: _blankToNull(sourceHash),
      modelId: _modelId(providerId: providerId, model: model),
      algorithmVersion: _algorithmVersion(
        libraryAlgorithm,
        indexVersion: indexVersion,
        contextVersion: contextVersion,
      ),
      createdAt: createdAt,
      sourceKind: SourceRefKind.libraryRag,
      confidence: confidence,
    );
  }

  static int? _positiveChunkId(int? value) {
    if (value == null || value <= 0) return null;
    return value;
  }

  static String? _jumpLink({
    required int bookId,
    required String href,
    required String? supplied,
  }) {
    final existing = _blankToNull(supplied);
    if (existing != null) return existing;
    final normalizedHref = _blankToNull(href);
    if (bookId <= 0 || normalizedHref == null) return null;
    return PaperReaderReaderIntent(
      bookId: bookId,
      href: normalizedHref,
    ).toUri().toString();
  }

  static String? _modelId({
    required String? providerId,
    required String? model,
  }) {
    final normalizedModel = _blankToNull(model);
    if (normalizedModel == null) return null;
    final normalizedProvider = _blankToNull(providerId);
    if (normalizedProvider == null) return normalizedModel;
    return '$normalizedProvider/$normalizedModel';
  }

  static String _algorithmVersion(
    String base, {
    required int? indexVersion,
    required int? contextVersion,
  }) {
    final parts = <String>[base];
    if (indexVersion != null) parts.add('index-v$indexVersion');
    if (contextVersion != null) parts.add('context-v$contextVersion');
    return parts.join('/');
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}
