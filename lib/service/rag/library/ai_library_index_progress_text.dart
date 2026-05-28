import 'package:papertok_reader/service/rag/library/ai_library_index_job.dart';

class AiLibraryIndexProgressText {
  const AiLibraryIndexProgressText._();

  static String compact({
    required AiLibraryIndexJob job,
    required String languageCode,
  }) {
    final zh = languageCode == 'zh';
    final parts = <String>[
      zh ? '索引 #${job.bookId}' : 'Indexing #${job.bookId}',
      formatPercent(job.progress),
    ];

    final phase = phaseLabel(job.phase, languageCode: languageCode);
    if (phase.isNotEmpty) parts.add(phase);

    if (job.totalChapters > 0) {
      parts.add(zh
          ? '章节 ${job.doneChapters}/${job.totalChapters}'
          : 'chapters ${job.doneChapters}/${job.totalChapters}');
    }

    if (job.currentChapterDoneChunks > 0 || job.currentChapterTotalChunks > 0) {
      final total = job.currentChapterTotalChunks > 0
          ? job.currentChapterTotalChunks.toString()
          : '?';
      parts.add(zh
          ? '当前 chunks ${job.currentChapterDoneChunks}/$total'
          : 'current chunks ${job.currentChapterDoneChunks}/$total');
    } else if (job.doneChunks > 0 || job.totalChunks > 0) {
      final total = job.totalChunks > 0 ? job.totalChunks.toString() : '?';
      parts.add(zh
          ? '向量 ${job.doneChunks}/$total'
          : 'vectors ${job.doneChunks}/$total');
    }

    if (job.embeddingBatchIndex > 0 || job.embeddingBatchTotal > 0) {
      final total = job.embeddingBatchTotal > 0
          ? job.embeddingBatchTotal.toString()
          : '?';
      parts.add(zh
          ? 'Embedding ${job.embeddingBatchIndex}/$total'
          : 'embedding batch ${job.embeddingBatchIndex}/$total');
    }

    if (job.lastEmbeddingBatchSize > 0 || job.lastEmbeddingDim > 0) {
      parts.add(zh
          ? '输出 ${job.lastEmbeddingBatchSize}x${job.lastEmbeddingDim}'
          : 'output ${job.lastEmbeddingBatchSize}x${job.lastEmbeddingDim}');
    }

    return parts.join(' · ');
  }

  static String detail({
    required AiLibraryIndexJob job,
    required String languageCode,
  }) {
    final zh = languageCode == 'zh';
    final parts = <String>[];

    final phase = phaseLabel(job.phase, languageCode: languageCode);
    if (phase.isNotEmpty) parts.add(phase);

    if (job.totalChapters > 0) {
      parts.add(zh
          ? '章节 ${job.doneChapters}/${job.totalChapters}'
          : 'chapters ${job.doneChapters}/${job.totalChapters}');
    }

    if (job.doneChunks > 0 || job.totalChunks > 0) {
      final total = job.totalChunks > 0 ? job.totalChunks.toString() : '?';
      parts.add(zh
          ? '已生成向量 ${job.doneChunks}/$total'
          : 'embedded chunks ${job.doneChunks}/$total');
    }

    if (job.currentChapterDoneChunks > 0 || job.currentChapterTotalChunks > 0) {
      final total = job.currentChapterTotalChunks > 0
          ? job.currentChapterTotalChunks.toString()
          : '?';
      parts.add(zh
          ? '当前章节 chunks ${job.currentChapterDoneChunks}/$total'
          : 'current chapter chunks ${job.currentChapterDoneChunks}/$total');
    }

    if (job.embeddingBatchIndex > 0 || job.embeddingBatchTotal > 0) {
      final total = job.embeddingBatchTotal > 0
          ? job.embeddingBatchTotal.toString()
          : '?';
      parts.add(zh
          ? 'Embedding 批次 ${job.embeddingBatchIndex}/$total'
          : 'embedding batch ${job.embeddingBatchIndex}/$total');
    }

    if (job.lastEmbeddingBatchSize > 0 || job.lastEmbeddingDim > 0) {
      parts.add(zh
          ? '输出 ${job.lastEmbeddingBatchSize} 个向量 x ${job.lastEmbeddingDim} 维'
          : 'output ${job.lastEmbeddingBatchSize} vectors x ${job.lastEmbeddingDim} dims');
    }

    final current = ((job.currentChapterTitle ?? '').trim().isNotEmpty
            ? job.currentChapterTitle
            : job.currentChapterHref)
        ?.trim();
    if (current != null && current.isNotEmpty) {
      parts.add(zh ? '当前 $current' : 'current $current');
    }

    return parts.join(' · ');
  }

  static String phaseLabel(String? phase, {required String languageCode}) {
    final zh = languageCode == 'zh';
    return switch ((phase ?? '').trim()) {
      'fetch' => zh ? '读取章节' : 'fetching chapter',
      'contextualize' => zh ? '构建上下文' : 'contextualizing',
      'embed' => zh ? '生成向量' : 'embedding',
      'chapter_done' => zh ? '章节完成' : 'chapter done',
      'global' => zh ? '构建全局索引' : 'building global index',
      _ => '',
    };
  }

  static String formatPercent(double value) {
    final percent = (value.clamp(0.0, 1.0) * 100).round();
    return '$percent%';
  }
}
