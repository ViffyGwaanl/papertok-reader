import 'dart:async';
import 'dart:convert';

import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/models/book.dart';
import 'package:papertok_reader/providers/book_toc.dart';
import 'package:papertok_reader/providers/chapter_content_bridge.dart';
import 'package:papertok_reader/providers/current_reading.dart';
import 'package:papertok_reader/service/rag/ai_contextual_chunker.dart';
import 'package:papertok_reader/service/rag/ai_embeddings_service.dart';
import 'package:papertok_reader/service/rag/ai_global_index_builder.dart';
import 'package:papertok_reader/service/rag/ai_index_chapter_plan.dart';
import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/ai_index_resume_policy.dart';
import 'package:papertok_reader/service/rag/ai_index_reuse_policy.dart';
import 'package:papertok_reader/service/rag/ai_text_chunker.dart';
import 'package:papertok_reader/service/rag/ai_vector_codec.dart';
import 'package:papertok_reader/service/rag/vector_math.dart';
import 'package:papertok_reader/utils/log/common.dart';
import 'package:papertok_reader/service/rag/library/ai_headless_reader_bridge_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

class AiBookIndexProgress {
  const AiBookIndexProgress({
    required this.phase,
    required this.doneChapters,
    required this.totalChapters,
    required this.doneChunks,
    required this.totalChunks,
    this.currentChapterDoneChunks = 0,
    this.currentChapterTotalChunks = 0,
    this.embeddingBatchIndex = 0,
    this.embeddingBatchTotal = 0,
    this.lastEmbeddingBatchSize = 0,
    this.lastEmbeddingDim = 0,
    this.currentChapterHref,
    this.currentChapterTitle,
  });

  final String phase;
  final int doneChapters;
  final int totalChapters;
  final int doneChunks;
  final int totalChunks;
  final int currentChapterDoneChunks;
  final int currentChapterTotalChunks;
  final int embeddingBatchIndex;
  final int embeddingBatchTotal;
  final int lastEmbeddingBatchSize;
  final int lastEmbeddingDim;
  final String? currentChapterHref;
  final String? currentChapterTitle;

  double get progress {
    if (totalChapters <= 0) return 0;
    final chapterFraction = currentChapterTotalChunks <= 0
        ? 0.0
        : (currentChapterDoneChunks / currentChapterTotalChunks)
            .clamp(0.0, 1.0)
            .toDouble();
    return ((doneChapters + chapterFraction) / totalChapters)
        .clamp(0.0, 1.0)
        .toDouble();
  }
}

typedef AiBookIndexProgressCallback = void Function(AiBookIndexProgress p);
typedef AiBookIndexCancellationCheck = bool Function();

class AiBookIndexCancelledException implements Exception {
  const AiBookIndexCancelledException();

  @override
  String toString() => 'AI book indexing was cancelled.';
}

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
  static const int indexAlgorithmVersion = 3;

  final AiTextChunker _chunker = const AiTextChunker();
  final AiContextualChunkBuilder _contextBuilder =
      const AiContextualChunkBuilder();
  late final AiGlobalIndexBuilder _globalIndexBuilder =
      AiGlobalIndexBuilder(database: _database);

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
    AiBookIndexCancellationCheck? shouldCancel,
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
    final chapters = AiIndexChapterPlan.flattenToc(toc);

    // Fallback: index current chapter only if TOC is missing.
    final fallbackHref = (reading.chapterHref ?? '').trim();
    final targetChapters = chapters.isNotEmpty
        ? chapters
        : (fallbackHref.isEmpty
            ? const <AiIndexChapter>[]
            : <AiIndexChapter>[
                AiIndexChapter(
                  href: fallbackHref,
                  title: reading.chapterTitle ?? '',
                  chapterOrder: 0,
                  tocLevel: 0,
                  tocPath: reading.chapterTitle ?? '',
                ),
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
      shouldCancel: shouldCancel,
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
    AiBookIndexCancellationCheck? shouldCancel,
  }) async {
    final bridgeService = ref.read(aiHeadlessReaderBridgeProvider);
    final bridge = await bridgeService.open(book.id);

    try {
      final toc = await bridge.getToc();
      final chapters = AiIndexChapterPlan.flattenToc(toc);
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
        shouldCancel: shouldCancel,
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
    required List<AiIndexChapter> chapters,
    required Future<String> Function(String href) fetchChapterByHref,
    AiBookIndexProgressCallback? onProgress,
    AiBookIndexCancellationCheck? shouldCancel,
  }) async {
    final bookId = book.id;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final providerId =
        (embeddingProviderId ?? Prefs().selectedAiService).trim();

    final existing = await _database.getBookIndexInfo(bookId);
    if (!rebuild &&
        existing != null &&
        AiIndexReusePolicy.canReuse(
          existing,
          bookMd5: book.md5 ?? '',
          providerId: providerId,
          embeddingModel: embeddingModel,
          indexVersion: indexAlgorithmVersion,
          chunkTargetChars: chunkTargetChars,
          chunkMaxChars: chunkMaxChars,
          chunkMinChars: chunkMinChars,
          chunkOverlapChars: chunkOverlapChars,
          maxChapterCharacters: maxChapterCharacters,
        )) {
      return existing;
    }

    final db = await _database.database;
    final canResume = !rebuild &&
        AiIndexResumePolicy.canResume(
          existing,
          bookMd5: book.md5 ?? '',
          providerId: providerId,
          embeddingModel: embeddingModel,
          indexVersion: indexAlgorithmVersion,
          chunkTargetChars: chunkTargetChars,
          chunkMaxChars: chunkMaxChars,
          chunkMinChars: chunkMinChars,
          chunkOverlapChars: chunkOverlapChars,
          maxChapterCharacters: maxChapterCharacters,
        );
    final shouldClearBeforeBuild = AiIndexResumePolicy.shouldClearBeforeBuild(
      rebuild: rebuild,
      existing: existing,
      bookMd5: book.md5 ?? '',
      providerId: providerId,
      embeddingModel: embeddingModel,
      indexVersion: indexAlgorithmVersion,
      chunkTargetChars: chunkTargetChars,
      chunkMaxChars: chunkMaxChars,
      chunkMinChars: chunkMinChars,
      chunkOverlapChars: chunkOverlapChars,
      maxChapterCharacters: maxChapterCharacters,
    );

    await db.transaction((txn) async {
      if (shouldClearBeforeBuild) {
        await _clearBookGeneratedIndex(txn, bookId);
      }

      await txn.insert(
        'ai_book_index',
        {
          'book_id': bookId,
          'created_at': nowMs,
          'updated_at': nowMs,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      final chunkCount =
          shouldClearBeforeBuild ? 0 : await _countBookChunks(txn, bookId);

      await txn.update(
        'ai_book_index',
        {
          'book_md5': book.md5 ?? '',
          'provider_id': providerId,
          'embedding_model': embeddingModel,
          'chunk_target_chars': chunkTargetChars,
          'chunk_max_chars': chunkMaxChars,
          'chunk_min_chars': chunkMinChars,
          'chunk_overlap_chars': chunkOverlapChars,
          'max_chapter_characters': maxChapterCharacters,
          'chunk_count': chunkCount,
          'done_chapters':
              shouldClearBeforeBuild ? 0 : (existing?.doneChapters ?? 0),
          'total_chapters': chapters.length,
          'updated_at': nowMs,
          // v2 columns
          'index_status': 'running',
          'failed_reason': null,
          'retry_count': 0,
          'index_version': indexAlgorithmVersion,
        },
        where: 'book_id = ?',
        whereArgs: [bookId],
      );
    });

    var doneChapters = 0;
    var doneChunks = 0;
    var totalChunks = 0;

    try {
      void throwIfCancelled() {
        if (shouldCancel?.call() == true) {
          throw const AiBookIndexCancelledException();
        }
      }

      for (final ch in chapters) {
        throwIfCancelled();

        final href = ch.href;
        final title = ch.title;

        onProgress?.call(
          AiBookIndexProgress(
            phase: 'fetch',
            doneChapters: doneChapters,
            totalChapters: chapters.length,
            doneChunks: doneChunks,
            totalChunks: totalChunks,
            currentChapterDoneChunks: 0,
            currentChapterTotalChunks: 0,
            currentChapterHref: href,
            currentChapterTitle: title,
          ),
        );

        String chapterText;
        try {
          throwIfCancelled();
          chapterText = await fetchChapterByHref(href);
          throwIfCancelled();
        } catch (e) {
          if (e is AiBookIndexCancelledException) rethrow;
          AnxLog.warning(
              'AiIndex: failed to fetch chapter href=$href error=$e');
          doneChapters++;
          await _updateBookIndexChapterProgress(
            db,
            bookId,
            doneChapters: doneChapters,
            totalChapters: chapters.length,
            doneChunks: doneChunks,
          );
          continue;
        }

        final rawText = chapterText.trim();
        if (rawText.isEmpty) {
          doneChapters++;
          await _updateBookIndexChapterProgress(
            db,
            bookId,
            doneChapters: doneChapters,
            totalChapters: chapters.length,
            doneChunks: doneChunks,
          );
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
          await _updateBookIndexChapterProgress(
            db,
            bookId,
            doneChapters: doneChapters,
            totalChapters: chapters.length,
            doneChunks: doneChunks,
          );
          continue;
        }

        totalChunks += chunks.length;
        onProgress?.call(
          AiBookIndexProgress(
            phase: AiContextualChunkBuilder.progressPhase,
            doneChapters: doneChapters,
            totalChapters: chapters.length,
            doneChunks: doneChunks,
            totalChunks: totalChunks,
            currentChapterDoneChunks: 0,
            currentChapterTotalChunks: chunks.length,
            currentChapterHref: href,
            currentChapterTitle: title,
          ),
        );
        final contextualChunks = [
          for (var i = 0; i < chunks.length; i++)
            (
              chunk: chunks[i],
              context: _contextBuilder.build(
                bookTitle: book.title,
                chapter: ch,
                chunkText: chunks[i].text,
                chunkIndex: i,
                totalChunks: chunks.length,
                embeddingModel: embeddingModel,
              ),
            ),
        ];

        final batchSize = embeddingBatchSize.clamp(1, 64);
        final resumeOffset = canResume
            ? (await _countChapterChunks(db, bookId, href))
                .clamp(0, contextualChunks.length)
                .toInt()
            : 0;
        if (resumeOffset > 0) {
          doneChunks += resumeOffset;
          onProgress?.call(
            AiBookIndexProgress(
              phase: 'embed',
              doneChapters: doneChapters,
              totalChapters: chapters.length,
              doneChunks: doneChunks,
              totalChunks: totalChunks,
              currentChapterDoneChunks: resumeOffset,
              currentChapterTotalChunks: chunks.length,
              currentChapterHref: href,
              currentChapterTitle: title,
            ),
          );
        }
        if (resumeOffset >= contextualChunks.length) {
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
          await _updateBookIndexChapterProgress(
            db,
            bookId,
            doneChapters: doneChapters,
            totalChapters: chapters.length,
            doneChunks: doneChunks,
          );
          continue;
        }

        final remainingChunks = contextualChunks.length - resumeOffset;
        final batchTotal =
            ((remainingChunks + batchSize - 1) / batchSize).floor();
        for (var offset = resumeOffset;
            offset < contextualChunks.length;
            offset += batchSize) {
          final batchIndex = ((offset - resumeOffset) ~/ batchSize) + 1;
          final batch = contextualChunks
              .skip(offset)
              .take(batchSize)
              .toList(growable: false);

          onProgress?.call(
            AiBookIndexProgress(
              phase: 'embed',
              doneChapters: doneChapters,
              totalChapters: chapters.length,
              doneChunks: doneChunks,
              totalChunks: totalChunks,
              currentChapterDoneChunks: offset,
              currentChapterTotalChunks: chunks.length,
              embeddingBatchIndex: batchIndex,
              embeddingBatchTotal: batchTotal,
              currentChapterHref: href,
              currentChapterTitle: title,
            ),
          );

          final texts = batch.map((c) => c.context.embeddingText).toList(
                growable: false,
              );
          throwIfCancelled();
          final vectors = await AiEmbeddingsService.embedDocuments(
            texts,
            model: embeddingModel,
            providerId: providerId,
            timeoutSeconds: embeddingsTimeoutSeconds,
          );
          throwIfCancelled();

          await db.transaction((txn) async {
            throwIfCancelled();
            for (var i = 0; i < batch.length; i++) {
              final c = batch[i].chunk;
              final context = batch[i].context;
              final v = vectors[i];
              final norm = VectorMath.l2Norm(v);
              await txn.insert('ai_chunks', {
                'book_id': bookId,
                'chapter_href': href,
                'chapter_title': title,
                'chunk_index': offset + i,
                'start_char': c.startChar,
                'end_char': c.endChar,
                'text': context.embeddingText,
                'raw_text': context.rawText,
                'context_text': context.contextText,
                'embedding_input_hash': context.embeddingInputHash,
                'context_model': AiContextualChunkBuilder.contextModel,
                'context_version': AiContextualChunkBuilder.contextVersion,
                'context_created_at': nowMs,
                'chapter_order': ch.chapterOrder,
                'toc_level': ch.tocLevel,
                'toc_path': ch.tocPath,
                'embedding_json': jsonEncode(v),
                'embedding_blob': AiVectorCodec.encodeFloat32(v),
                'embedding_dim': v.length,
                'embedding_norm': norm,
                'created_at': nowMs,
              });
            }
          });
          throwIfCancelled();

          doneChunks += batch.length;
          onProgress?.call(
            AiBookIndexProgress(
              phase: 'embed',
              doneChapters: doneChapters,
              totalChapters: chapters.length,
              doneChunks: doneChunks,
              totalChunks: totalChunks,
              currentChapterDoneChunks: offset + batch.length > chunks.length
                  ? chunks.length
                  : offset + batch.length,
              currentChapterTotalChunks: chunks.length,
              embeddingBatchIndex: batchIndex,
              embeddingBatchTotal: batchTotal,
              lastEmbeddingBatchSize: vectors.length,
              lastEmbeddingDim: vectors.isEmpty ? 0 : vectors.first.length,
              currentChapterHref: href,
              currentChapterTitle: title,
            ),
          );
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
        await _updateBookIndexChapterProgress(
          db,
          bookId,
          doneChapters: doneChapters,
          totalChapters: chapters.length,
          doneChunks: doneChunks,
        );
      }

      throwIfCancelled();
      if (doneChunks > 0) {
        onProgress?.call(
          AiBookIndexProgress(
            phase: 'global',
            doneChapters: doneChapters,
            totalChapters: chapters.length,
            doneChunks: doneChunks,
            totalChunks: totalChunks,
          ),
        );
        try {
          await _globalIndexBuilder.rebuildBook(bookId: bookId);
        } catch (e) {
          AnxLog.warning(
            'AiIndex: global layer build failed bookId=$bookId error=$e',
          );
        }
        throwIfCancelled();
      }

      final indexedAt = DateTime.now().millisecondsSinceEpoch;
      final actualChunkCount = await _countBookChunks(db, bookId);
      await db.update(
        'ai_book_index',
        {
          'chunk_count': actualChunkCount,
          'done_chapters': chapters.length,
          'total_chapters': chapters.length,
          'updated_at': indexedAt,
          'indexed_at': indexedAt,
          'index_status': 'succeeded',
          'failed_reason': null,
        },
        where: 'book_id = ?',
        whereArgs: [bookId],
      );

      final info = await _database.getBookIndexInfo(bookId);
      return info ??
          AiBookIndexInfo(bookId: bookId, chunkCount: actualChunkCount);
    } catch (e) {
      await _markBookIndexFailed(
        db,
        bookId,
        e,
        doneChapters: doneChapters,
        totalChapters: chapters.length,
      );
      rethrow;
    }
  }

  Future<void> _clearBookGeneratedIndex(
    DatabaseExecutor executor,
    int bookId,
  ) async {
    await executor.delete(
      'ai_graph_edges',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
    await executor.delete(
      'ai_graph_communities',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
    await executor.delete(
      'ai_graph_nodes',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
    await executor.delete(
      'ai_raptor_nodes',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
    await executor.delete(
      'ai_chunks',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }

  Future<int> _countBookChunks(DatabaseExecutor executor, int bookId) async {
    final rows = await executor.rawQuery(
      'SELECT COUNT(*) AS c FROM ai_chunks WHERE book_id = ?',
      [bookId],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<int> _countChapterChunks(
    DatabaseExecutor executor,
    int bookId,
    String chapterHref,
  ) async {
    final rows = await executor.rawQuery(
      'SELECT COUNT(*) AS c FROM ai_chunks WHERE book_id = ? AND chapter_href = ?',
      [bookId, chapterHref],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<void> _markBookIndexFailed(
    DatabaseExecutor executor,
    int bookId,
    Object error, {
    required int doneChapters,
    required int totalChapters,
  }) async {
    final failedAt = DateTime.now().millisecondsSinceEpoch;
    final chunkCount = await _countBookChunks(executor, bookId);
    await executor.update(
      'ai_book_index',
      {
        'chunk_count': chunkCount,
        'done_chapters': doneChapters,
        'total_chapters': totalChapters,
        'updated_at': failedAt,
        'index_status': 'failed',
        'failed_reason': error.toString(),
      },
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }

  Future<void> _updateBookIndexChapterProgress(
    DatabaseExecutor executor,
    int bookId, {
    required int doneChapters,
    required int totalChapters,
    required int doneChunks,
  }) async {
    await executor.update(
      'ai_book_index',
      {
        'done_chapters': doneChapters,
        'total_chapters': totalChapters,
        'chunk_count': doneChunks,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }
}
