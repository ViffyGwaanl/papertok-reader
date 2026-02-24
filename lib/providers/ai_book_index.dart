import 'package:anx_reader/providers/current_reading.dart';
import 'package:anx_reader/service/rag/ai_book_indexer.dart';
import 'package:anx_reader/service/rag/ai_index_database.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AiBookIndexingStatus { idle, indexing, clearing, done, error }

class AiBookIndexingState {
  const AiBookIndexingState({
    required this.status,
    this.progress = 0,
    this.message,
    this.lastInfo,
  });

  final AiBookIndexingStatus status;
  final double progress;
  final String? message;
  final AiBookIndexInfo? lastInfo;

  bool get isBusy =>
      status == AiBookIndexingStatus.indexing ||
      status == AiBookIndexingStatus.clearing;

  AiBookIndexingState copyWith({
    AiBookIndexingStatus? status,
    double? progress,
    String? message,
    AiBookIndexInfo? lastInfo,
  }) {
    return AiBookIndexingState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      message: message,
      lastInfo: lastInfo ?? this.lastInfo,
    );
  }

  static const idle = AiBookIndexingState(status: AiBookIndexingStatus.idle);
}

final aiBookIndexingProvider =
    StateNotifierProvider<AiBookIndexingNotifier, AiBookIndexingState>((ref) {
      return AiBookIndexingNotifier(ref);
    });

class AiBookIndexingNotifier extends StateNotifier<AiBookIndexingState> {
  AiBookIndexingNotifier(this.ref) : super(AiBookIndexingState.idle);

  final Ref ref;

  Future<void> buildIndex({required bool rebuild}) async {
    final reading = ref.read(currentReadingProvider);
    if (!reading.isReading || reading.book == null) {
      state = state.copyWith(
        status: AiBookIndexingStatus.error,
        progress: 0,
        message: 'No active reading session.',
      );
      return;
    }

    state = state.copyWith(
      status: AiBookIndexingStatus.indexing,
      progress: 0,
      message: rebuild ? 'Rebuilding index…' : 'Building index…',
    );

    try {
      final indexer = AiBookIndexer(ref);
      final info = await indexer.buildCurrentBook(
        rebuild: rebuild,
        onProgress: (p) {
          state = state.copyWith(
            status: AiBookIndexingStatus.indexing,
            progress: p.progress,
            message:
                '${p.phase}: ${p.doneChapters}/${p.totalChapters} chapters, ${p.doneChunks}/${p.totalChunks} chunks',
          );
        },
      );

      state = state.copyWith(
        status: AiBookIndexingStatus.done,
        progress: 1,
        message: 'Index ready: ${info.chunkCount} chunks',
        lastInfo: info,
      );
    } catch (e, st) {
      AnxLog.severe('AiIndex: build failed: $e\n$st');
      state = state.copyWith(
        status: AiBookIndexingStatus.error,
        progress: 0,
        message: 'Indexing failed: $e',
      );
    }
  }

  Future<void> clearIndex() async {
    final reading = ref.read(currentReadingProvider);
    final book = reading.book;
    if (!reading.isReading || book == null) {
      state = state.copyWith(
        status: AiBookIndexingStatus.error,
        progress: 0,
        message: 'No active reading session.',
      );
      return;
    }

    state = state.copyWith(
      status: AiBookIndexingStatus.clearing,
      progress: 0,
      message: 'Clearing index…',
    );

    try {
      await AiIndexDatabase.instance.clearBook(book.id);
      state = state.copyWith(
        status: AiBookIndexingStatus.done,
        progress: 1,
        message: 'Index cleared.',
        lastInfo: null,
      );
    } catch (e, st) {
      AnxLog.severe('AiIndex: clear failed: $e\n$st');
      state = state.copyWith(
        status: AiBookIndexingStatus.error,
        progress: 0,
        message: 'Clear failed: $e',
      );
    }
  }
}

final currentBookAiIndexInfoProvider =
    FutureProvider.autoDispose<AiBookIndexInfo?>((ref) async {
      final reading = ref.watch(currentReadingProvider);
      final bookId = reading.book?.id;
      if (!reading.isReading || bookId == null) return null;
      return AiIndexDatabase.instance.getBookIndexInfo(bookId);
    });
