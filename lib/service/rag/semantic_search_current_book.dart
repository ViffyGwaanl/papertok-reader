import 'dart:convert';

import 'package:anx_reader/service/rag/ai_embeddings_service.dart';
import 'package:anx_reader/service/rag/ai_index_database.dart';
import 'package:anx_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:anx_reader/service/rag/vector_math.dart';
import 'package:sqflite/sqflite.dart';

class AiSemanticSearchEvidence {
  const AiSemanticSearchEvidence({
    required this.text,
    required this.href,
    required this.anchor,
    required this.jumpLink,
    required this.score,
  });

  final String text;
  final String href;
  final String anchor;

  /// Best-effort navigation deep link.
  ///
  /// This uses Paper Reader's app URL scheme.
  final String jumpLink;

  final double score;

  Map<String, dynamic> toJson() => {
        'text': text,
        'href': href,
        'anchor': anchor,
        'jumpLink': jumpLink,
        'score': score,
      };
}

class AiSemanticSearchResult {
  const AiSemanticSearchResult({
    required this.ok,
    required this.bookId,
    required this.query,
    required this.evidence,
    this.message,
    this.indexInfo,
  });

  final bool ok;
  final int bookId;
  final String query;
  final List<AiSemanticSearchEvidence> evidence;
  final String? message;
  final AiBookIndexInfo? indexInfo;

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'bookId': bookId,
        'query': query,
        if (message != null) 'message': message,
        if (indexInfo != null)
          'index': {
            'chunkCount': indexInfo!.chunkCount,
            'embeddingModel': indexInfo!.embeddingModel,
            'updatedAt': indexInfo!.updatedAt,
          },
        'evidence': evidence.map((e) => e.toJson()).toList(growable: false),
      };
}

class SemanticSearchCurrentBook {
  SemanticSearchCurrentBook({AiIndexDatabase? database})
      : _db = database ?? AiIndexDatabase.instance;

  final AiIndexDatabase _db;

  Future<AiSemanticSearchResult> search({
    required int bookId,
    required String query,
    int maxResults = 6,
    String? embeddingModel,
    String? providerId,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return AiSemanticSearchResult(
        ok: false,
        bookId: bookId,
        query: query,
        evidence: const [],
        message: 'query must not be empty',
      );
    }

    final info = await _db.getBookIndexInfo(bookId);
    if (info == null || info.chunkCount <= 0) {
      return AiSemanticSearchResult(
        ok: false,
        bookId: bookId,
        query: query,
        evidence: const [],
        message:
            'No semantic index found for this book. Build the index from Reading → Settings → Other → AI Index.',
        indexInfo: info,
      );
    }

    final db = await _db.database;
    final rows = await db.query(
      'ai_chunks',
      columns: [
        'chapter_href',
        'chapter_title',
        'chunk_index',
        'text',
        'embedding_json',
        'embedding_norm',
      ],
      where: 'book_id = ?',
      whereArgs: [bookId],
    );

    if (rows.isEmpty) {
      return AiSemanticSearchResult(
        ok: false,
        bookId: bookId,
        query: query,
        evidence: const [],
        message:
            'Index metadata exists but chunk table is empty. Please rebuild the index.',
        indexInfo: info,
      );
    }

    final effectiveModelRaw = (embeddingModel ??
            info.embeddingModel ??
            AiEmbeddingsService.defaultEmbeddingModel)
        .trim();
    final effectiveModel = effectiveModelRaw.isEmpty
        ? AiEmbeddingsService.defaultEmbeddingModel
        : effectiveModelRaw;

    final effectiveProviderId = (providerId ?? info.providerId ?? '').trim();

    final qVec = await AiEmbeddingsService.embedQuery(
      trimmed,
      model: effectiveModel,
      providerId: effectiveProviderId.isEmpty ? null : effectiveProviderId,
    );
    final qNorm = VectorMath.l2Norm(qVec);

    final scored = <({Map<String, Object?> row, double score})>[];

    for (final r in rows) {
      final embJson = r['embedding_json']?.toString() ?? '[]';
      List<double> v;
      try {
        final decoded = jsonDecode(embJson);
        if (decoded is List) {
          v = decoded.map((x) => (x as num).toDouble()).toList(growable: false);
        } else {
          continue;
        }
      } catch (_) {
        continue;
      }

      final norm = (r['embedding_norm'] as num?)?.toDouble();
      final score = VectorMath.cosineSimilarity(
        qVec,
        v,
        aNorm: qNorm,
        bNorm: norm,
      );
      scored.add((row: r, score: score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));

    final k = maxResults.clamp(1, 10);
    final top = scored.take(k).toList(growable: false);

    final evidence = top.map((it) {
      final r = it.row;
      final href = r['chapter_href']?.toString() ?? '';
      final title = (r['chapter_title']?.toString() ?? '').trim();
      final anchor = title.isEmpty ? href : title;

      final rawText = r['text']?.toString() ?? '';
      final snippet =
          rawText.length <= 450 ? rawText : '${rawText.substring(0, 450)}…';

      // Best-effort: we currently only have href, not per-chunk CFI.
      final jumpLink = PaperReaderReaderIntent(
        bookId: bookId,
        href: href,
      ).toUri().toString();

      return AiSemanticSearchEvidence(
        text: snippet,
        href: href,
        anchor: anchor,
        jumpLink: jumpLink,
        score: it.score,
      );
    }).toList(growable: false);

    return AiSemanticSearchResult(
      ok: true,
      bookId: bookId,
      query: query,
      evidence: evidence,
      indexInfo: info,
    );
  }
}
