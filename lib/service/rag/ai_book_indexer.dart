import 'dart:async';
import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/toc_item.dart';
import 'package:anx_reader/providers/book_toc.dart';
import 'package:anx_reader/providers/chapter_content_bridge.dart';
import 'package:anx_reader/providers/current_reading.dart';
import 'package:anx_reader/service/rag/ai_embeddings_service.dart';
import 'package:anx_reader/service/rag/ai_index_database.dart';
import 'package:anx_reader/service/rag/ai_text_chunker.dart';
import 'package:anx_reader/service/rag/vector_math.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/service/rag/library/ai_headless_reader_bridge_service.dart';
import 'package:riverpod/riverpod.dart';
import 'package:sqflite/sqflite.dart';

class AiBookIndexProgress {
  const AiBookIndexProgress({
    required this.phase,
    required this.doneChapters,
    required this.totalChapters,
    required this.doneChunks,
    required this.totalChunks,
    this.currentChapterHref,
    this.currentChapterTitle,
  });

  final String phase;
  final int doneChapters;
  final int totalChapters;
  final int doneChunks;
  final int totalChunks;
  final String? currentChapterHref;
  final String? currentChapterTitle;

  double get progress {
    if (totalChapters <= 0) return 0;
    // Chapter-based progress is stable; chunk counters are best-effort.
    return (doneChapters / totalChapters).clamp(0.0, 1.0);
  }
}

typedef AiBookIndexProgressCallback = void Function(AiBookIndexProgress p);

class AiBookIndexer {
  AiBookIndexer(this.ref, {AiIndexDatabase? database})
      : _database = database ?? AiIndexDatabase.instance;

  final Ref ref;
  final AiIndexDatabase _database;

  /// Default maximum characters to fetch per chapter during indexing.
  ///
  /// This is a safety guard against very large chapters causing memory spikes.
  static const int defaultMaxChapterCharacters = 80000;

  static const int defaultEmbeddingBatchSize = 16;

  /// Bump this when the indexing algorithm changes in a way that makes
  /// previous book indexes incompatible.
  static const int indexAlgorithmVersion = 1;

  final AiTextChunker _chunker = const AiTextChunker();

  Future<AiBookIndexInfo> buildCurrentBook({
    required bool rebuild,
    AiBookIndexProgressCallback? onProgress,
    String embeddingModel = AiEmbeddingsService.defaultEmbeddingModel,
    String? embeddingProviderId,
    int embeddingBatchSize = defaultEmbeddingBatchSize,
    int embeddingsTimeoutSeconds = 60,
    int chunkTargetChars = AiTextChunker.defaultTargetChars,
    int chunkMaxChars = AiTextChunker.defaultMaxChars,
    int chunkMinChars = AiTextChunker.defaultMinChars,
    int chunkOverlapChars = AiTextChunker.defaultOverlapChars,
    int maxChapterCharacters = defaultMaxChapterCharacters,
  }) async {
    final reading = ref.read(currentReadingProvider);
    if (!reading.isReading || reading.book == null) {
      throw StateError('No active reading session.');
    }

    final handlers = ref.read(chapterContentBridgeProvider);
    if (handlers == null) {
      throw StateError('Reader bridge is not available.');
    }

    final book = reading.book!;

    final toc = ref.read(bookTocProvider);
    final chapters = _flattenToc(toc);

    // Fallback: index current chapter only if TOC is missing.
    final fallbackHref = (reading.chapterHref ?? '').trim();
    final targetChapters = chapters.isNotEmpty
        ? chapters
        : (fallbackHref.isEmpty
            ? const <({String href, String title})>[]
            : <({String href, String title})>[
                (href: fallbackHref, title: reading.chapterTitle ?? ''),
              ]);

    if (targetChapters.isEmpty) {
      throw StateError('No chapters available for indexing.');
    }

    return _build(
      book: book,
      rebuild: rebuild,
      embeddingModel: embeddingModel,
      embeddingProviderId: embeddingProviderId,
      embeddingBatchSize: embeddingBatchSize,
      embeddingsTimeoutSeconds: embeddingsTimeoutSeconds,
      chunkTargetChars: chunkTargetChars,
      chunkMaxChars: chunkMaxChars,
      chunkMinChars: chunkMinChars,
      chunkOverlapChars: chunkOverlapChars,
      maxChapterCharacters: maxChapterCharacters,
      onProgress: onProgress,
      chapters: targetChapters,
      fetchChapterByHref: (href) => handlers.fetchChapterByHref(
        href,
        maxCharacters: maxChapterCharacters,
      ),
    );
  }

  /// Build index for an arbitrary book (library indexing).
  ///
  /// Uses a headless foliate-js session (see [AiHeadlessReaderBridgeService]).
  Future<AiBookIndexInfo> buildBook({
    required Book book,
    required bool rebuild,
    AiBookIndexProgressCallback? onProgress,
    String embeddingModel = AiEmbeddingsService.defaultEmbeddingModel,
    String? embeddingProviderId,
    int embeddingBatchSize = defaultEmbeddingBatchSize,
    int embeddingsTimeoutSeconds = 60,
    int chunkTargetChars = AiTextChunker.defaultTargetChars,
    int chunkMaxChars = AiTextChunker.defaultMaxChars,
    int chunkMinChars = AiTextChunker.defaultMinChars,
    int chunkOverlapChars = AiTextChunker.defaultOverlapChars,
    int maxChapterCharacters = defaultMaxChapterCharacters,
  }) async {
    final bridgeService = ref.read(aiHeadlessReaderBridgeProvider);
    final bridge = await bridgeService.open(book.id);

    try {
      final toc = await bridge.getToc();
      final chapters = _flattenToc(toc);
      if (chapters.isEmpty) {
        throw StateError('No chapters available for indexing.');
      }

      return await _build(
        book: book,
        rebuild: rebuild,
        embeddingModel: embeddingModel,
        embeddingProviderId: embeddingProviderId,
        embeddingBatchSize: embeddingBatchSize,
        embeddingsTimeoutSeconds: embeddingsTimeoutSeconds,
        chunkTargetChars: chunkTargetChars,
        chunkMaxChars: chunkMaxChars,
        chunkMinChars: chunkMinChars,
        chunkOverlapChars: chunkOverlapChars,
        maxChapterCharacters: maxChapterCharacters,
        onProgress: onProgress,
        chapters: chapters,
        fetchChapterByHref: (href) => bridge.getChapterContentByHref(
          href,
          maxCharacters: maxChapterCharacters,
        ),
      );
    } finally {
      bridgeService.scheduleDispose();
    }
  }

  Future<AiBookIndexInfo> _build({
    required Book book,
    required bool rebuild,
    required String embeddingModel,
    String? embeddingProviderId,
    required int embeddingBatchSize,
    required int embeddingsTimeoutSeconds,
    required int chunkTargetChars,
    required int chunkMaxChars,
    required int chunkMinChars,
    required int chunkOverlapChars,
    required int maxChapterCharacters,
    required List<({String href, String title})> chapters,
    required Future<String> Function(String href) fetchChapterByHref,
    AiBookIndexProgressCallback? onProgress,
  }) async {
    final bookId = book.id;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final existing = await _database.getBookIndexInfo(bookId);
    if (!rebuild && existing != null && existing.chunkCount > 0) {
      return existing;
    }

    final providerId =
        (embeddingProviderId ?? Prefs().selectedAiService).trim();
    final db = await _database.database;

    await db.transaction((txn) async {
      await txn.delete('ai_chunks', where: 'book_id = ?', whereArgs: [bookId]);

      await txn.insert(
        'ai_book_index',
        {
          'book_id': bookId,
          'book_md5': book.md5,
          'provider_id': providerId,
          'embedding_model': embeddingModel,
          'chunk_target_chars': chunkTargetChars,
          'chunk_max_chars': chunkMaxChars,
          'chunk_min_chars': chunkMinChars,
          'chunk_overlap_chars': chunkOverlapChars,
          'max_chapter_characters': maxChapterCharacters,
          'chunk_count': 0,
          'created_at': nowMs,
          'updated_at': nowMs,
          // v2 columns
          'index_status': 'running',
          'failed_reason': null,
          'retry_count': 0,
          'index_version': indexAlgorithmVersion,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    var doneChapters = 0;
    var doneChunks = 0;
    var totalChunks = 0;

    for (final ch in chapters) {
      final href = ch.href;
      final title = ch.title;

      onProgress?.call(
        AiBookIndexProgress(
          phase: 'fetch',
          doneChapters: doneChapters,
          totalChapters: chapters.length,
          doneChunks: doneChunks,
          totalChunks: totalChunks,
          currentChapterHref: href,
          currentChapterTitle: title,
        ),
      );

      String chapterText;
      try {
        chapterText = await fetchChapterByHref(href);
      } catch (e) {
        AnxLog.warning('AiIndex: failed to fetch chapter href=$href error=$e');
        doneChapters++;
        continue;
      }

      final rawText = chapterText.trim();
      if (rawText.isEmpty) {
        doneChapters++;
        continue;
      }

      final chunks = _chunker.chunk(
        rawText,
        targetChars: chunkTargetChars,
        maxChars: chunkMaxChars,
        minChars: chunkMinChars,
        overlapChars: chunkOverlapChars,
      );
      if (chunks.isEmpty) {
        doneChapters++;
        continue;
      }

      totalChunks += chunks.length;

      final batchSize = embeddingBatchSize.clamp(1, 64);
      for (var offset = 0; offset < chunks.length; offset += batchSize) {
        final batch =
            chunks.skip(offset).take(batchSize).toList(growable: false);

        onProgress?.call(
          AiBookIndexProgress(
            phase: 'embed',
            doneChapters: doneChapters,
            totalChapters: chapters.length,
            doneChunks: doneChunks,
            totalChunks: totalChunks,
            currentChapterHref: href,
            currentChapterTitle: title,
          ),
        );

        final texts = batch.map((c) => c.text).toList(growable: false);
        final vectors = await AiEmbeddingsService.embedDocuments(
          texts,
          model: embeddingModel,
          providerId: providerId,
          timeoutSeconds: embeddingsTimeoutSeconds,
        );

        await db.transaction((txn) async {
          for (var i = 0; i < batch.length; i++) {
            final c = batch[i];
            final v = vectors[i];
            final norm = VectorMath.l2Norm(v);
            await txn.insert('ai_chunks', {
              'book_id': bookId,
              'chapter_href': href,
              'chapter_title': title,
              'chunk_index': offset + i,
              'start_char': c.startChar,
              'end_char': c.endChar,
              'text': c.text,
              'embedding_json': jsonEncode(v),
              'embedding_dim': v.length,
              'embedding_norm': norm,
              'created_at': nowMs,
            });
          }
        });

        doneChunks += batch.length;
      }

      doneChapters++;
      onProgress?.call(
        AiBookIndexProgress(
          phase: 'chapter_done',
          doneChapters: doneChapters,
          totalChapters: chapters.length,
          doneChunks: doneChunks,
          totalChunks: totalChunks,
          currentChapterHref: href,
          currentChapterTitle: title,
        ),
      );
    }

    await db.update(
      'ai_book_index',
      {
        'chunk_count': doneChunks,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'indexed_at': DateTime.now().millisecondsSinceEpoch,
        'index_status': 'succeeded',
        'failed_reason': null,
      },
      where: 'book_id = ?',
      whereArgs: [bookId],
    );

    final info = await _database.getBookIndexInfo(bookId);
    return info ?? AiBookIndexInfo(bookId: bookId, chunkCount: doneChunks);
  }

  List<({String href, String title})> _flattenToc(List<TocItem> toc) {
    final out = <({String href, String title})>[];

    void walk(TocItem item) {
      final href = item.href.trim();
      if (href.isNotEmpty) {
        out.add((href: href, title: item.label));
      }
      for (final sub in item.subitems) {
        walk(sub);
      }
    }

    for (final item in toc) {
      walk(item);
    }

    // Deduplicate hrefs.
    final seen = <String>{};
    return out.where((e) => seen.add(e.href)).toList(growable: false);
  }
}
