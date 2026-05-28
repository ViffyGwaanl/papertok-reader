import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/service/rag/ai_book_indexer.dart';
import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/ai_index_resume_policy.dart';

void main() {
  test('allows resume for failed index with matching parameters', () {
    const existing = AiBookIndexInfo(
      bookId: 1,
      chunkCount: 12,
      bookMd5: 'book-md5',
      providerId: 'provider',
      embeddingModel: 'embedding-model',
      indexStatus: 'failed',
      indexVersion: AiBookIndexer.indexAlgorithmVersion,
      chunkTargetChars: 900,
      chunkMaxChars: 1200,
      chunkMinChars: 250,
      chunkOverlapChars: 120,
      maxChapterCharacters: 80000,
    );

    expect(
      AiIndexResumePolicy.canResume(
        existing,
        bookMd5: 'book-md5',
        providerId: 'provider',
        embeddingModel: 'embedding-model',
        indexVersion: AiBookIndexer.indexAlgorithmVersion,
        chunkTargetChars: 900,
        chunkMaxChars: 1200,
        chunkMinChars: 250,
        chunkOverlapChars: 120,
        maxChapterCharacters: 80000,
      ),
      isTrue,
    );
  });

  test('does not resume when rebuild is explicit or parameters differ', () {
    const existing = AiBookIndexInfo(
      bookId: 1,
      chunkCount: 12,
      bookMd5: 'book-md5',
      providerId: 'provider',
      embeddingModel: 'embedding-model',
      indexStatus: 'failed',
      indexVersion: AiBookIndexer.indexAlgorithmVersion,
      chunkTargetChars: 900,
      chunkMaxChars: 1200,
      chunkMinChars: 250,
      chunkOverlapChars: 120,
      maxChapterCharacters: 80000,
    );

    expect(
      AiIndexResumePolicy.shouldClearBeforeBuild(
        rebuild: true,
        existing: existing,
        bookMd5: 'book-md5',
        providerId: 'provider',
        embeddingModel: 'embedding-model',
        indexVersion: AiBookIndexer.indexAlgorithmVersion,
        chunkTargetChars: 900,
        chunkMaxChars: 1200,
        chunkMinChars: 250,
        chunkOverlapChars: 120,
        maxChapterCharacters: 80000,
      ),
      isTrue,
    );

    expect(
      AiIndexResumePolicy.canResume(
        existing,
        bookMd5: 'book-md5',
        providerId: 'provider',
        embeddingModel: 'other-model',
        indexVersion: AiBookIndexer.indexAlgorithmVersion,
        chunkTargetChars: 900,
        chunkMaxChars: 1200,
        chunkMinChars: 250,
        chunkOverlapChars: 120,
        maxChapterCharacters: 80000,
      ),
      isFalse,
    );
  });
}
