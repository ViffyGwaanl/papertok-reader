import 'package:papertok_reader/service/rag/ai_book_indexer.dart';
import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/ai_index_reuse_policy.dart';
import 'package:papertok_reader/service/rag/ai_text_chunker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reuse policy rejects stale algorithm versions and chunk settings', () {
    const matching = AiBookIndexInfo(
      bookId: 1,
      chunkCount: 10,
      bookMd5: 'md5',
      providerId: 'provider',
      embeddingModel: 'model',
      indexStatus: 'succeeded',
      indexVersion: AiBookIndexer.indexAlgorithmVersion,
      chunkTargetChars: AiTextChunker.defaultTargetChars,
      chunkMaxChars: AiTextChunker.defaultMaxChars,
      chunkMinChars: AiTextChunker.defaultMinChars,
      chunkOverlapChars: AiTextChunker.defaultOverlapChars,
      maxChapterCharacters: AiBookIndexer.defaultMaxChapterCharacters,
    );

    expect(
      AiIndexReusePolicy.canReuse(
        matching,
        bookMd5: 'md5',
        providerId: 'provider',
        embeddingModel: 'model',
        indexVersion: AiBookIndexer.indexAlgorithmVersion,
        chunkTargetChars: AiTextChunker.defaultTargetChars,
        chunkMaxChars: AiTextChunker.defaultMaxChars,
        chunkMinChars: AiTextChunker.defaultMinChars,
        chunkOverlapChars: AiTextChunker.defaultOverlapChars,
        maxChapterCharacters: AiBookIndexer.defaultMaxChapterCharacters,
      ),
      true,
    );

    expect(
      AiIndexReusePolicy.canReuse(
        const AiBookIndexInfo(
          bookId: 1,
          chunkCount: 10,
          bookMd5: 'md5',
          providerId: 'provider',
          embeddingModel: 'model',
          indexStatus: 'succeeded',
          indexVersion: AiBookIndexer.indexAlgorithmVersion - 1,
        ),
        bookMd5: 'md5',
        providerId: 'provider',
        embeddingModel: 'model',
        indexVersion: AiBookIndexer.indexAlgorithmVersion,
        chunkTargetChars: AiTextChunker.defaultTargetChars,
        chunkMaxChars: AiTextChunker.defaultMaxChars,
        chunkMinChars: AiTextChunker.defaultMinChars,
        chunkOverlapChars: AiTextChunker.defaultOverlapChars,
        maxChapterCharacters: AiBookIndexer.defaultMaxChapterCharacters,
      ),
      false,
    );

    expect(
      AiIndexReusePolicy.canReuse(
        matching,
        bookMd5: 'md5',
        providerId: 'provider',
        embeddingModel: 'model',
        indexVersion: AiBookIndexer.indexAlgorithmVersion,
        chunkTargetChars: AiTextChunker.defaultTargetChars + 1,
        chunkMaxChars: AiTextChunker.defaultMaxChars,
        chunkMinChars: AiTextChunker.defaultMinChars,
        chunkOverlapChars: AiTextChunker.defaultOverlapChars,
        maxChapterCharacters: AiBookIndexer.defaultMaxChapterCharacters,
      ),
      false,
    );
  });
}
