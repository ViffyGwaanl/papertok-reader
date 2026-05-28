import 'package:papertok_reader/service/rag/ai_index_database.dart';

class AiIndexReusePolicy {
  const AiIndexReusePolicy._();

  static bool canReuse(
    AiBookIndexInfo? existing, {
    required String bookMd5,
    required String providerId,
    required String embeddingModel,
    required int indexVersion,
    required int chunkTargetChars,
    required int chunkMaxChars,
    required int chunkMinChars,
    required int chunkOverlapChars,
    required int maxChapterCharacters,
  }) {
    if (existing == null || existing.chunkCount <= 0) return false;
    if (existing.indexStatus != null && existing.indexStatus != 'succeeded') {
      return false;
    }
    if ((existing.bookMd5 ?? '') != bookMd5) return false;
    if ((existing.providerId ?? '') != providerId) return false;
    if ((existing.embeddingModel ?? '') != embeddingModel) return false;
    if ((existing.indexVersion ?? 0) != indexVersion) return false;
    if ((existing.chunkTargetChars ?? 0) != chunkTargetChars) return false;
    if ((existing.chunkMaxChars ?? 0) != chunkMaxChars) return false;
    if ((existing.chunkMinChars ?? 0) != chunkMinChars) return false;
    if ((existing.chunkOverlapChars ?? 0) != chunkOverlapChars) return false;
    if ((existing.maxChapterCharacters ?? 0) != maxChapterCharacters) {
      return false;
    }
    return true;
  }
}
