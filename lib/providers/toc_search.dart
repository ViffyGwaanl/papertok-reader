import 'package:papertok_reader/models/search_result_model.dart';
import 'package:papertok_reader/service/rag/semantic_search_current_book.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'toc_search.g.dart';

@immutable
class TocSearchState {
  const TocSearchState({
    this.query,
    this.progress = 0.0,
    this.results = const [],
    this.isSearching = false,
    this.scrollOffset = 0.0,
    this.semanticResults = const [],
    this.isSemanticSearching = false,
    this.hasAiIndex = false,
  });

  final String? query;
  final double progress;
  final List<SearchResultModel> results;
  final bool isSearching;
  final double scrollOffset;

  /// Semantic search results from AI vector index.
  final List<AiSemanticSearchEvidence> semanticResults;

  /// Whether a semantic search is currently running.
  final bool isSemanticSearching;

  /// Whether the current book has an AI semantic index available.
  final bool hasAiIndex;

  bool get isActive => query != null && query!.isNotEmpty;

  /// Total results across both exact and semantic search.
  int get totalResultCount {
    int exact = 0;
    for (final r in results) {
      exact += r.subitems.length;
    }
    return exact + semanticResults.length;
  }

  TocSearchState copyWith({
    Object? query = _noValue,
    double? progress,
    List<SearchResultModel>? results,
    bool? isSearching,
    double? scrollOffset,
    List<AiSemanticSearchEvidence>? semanticResults,
    bool? isSemanticSearching,
    bool? hasAiIndex,
  }) {
    return TocSearchState(
      query: identical(query, _noValue) ? this.query : query as String?,
      progress: progress ?? this.progress,
      results: results ?? this.results,
      isSearching: isSearching ?? this.isSearching,
      scrollOffset: scrollOffset ?? this.scrollOffset,
      semanticResults: semanticResults ?? this.semanticResults,
      isSemanticSearching: isSemanticSearching ?? this.isSemanticSearching,
      hasAiIndex: hasAiIndex ?? this.hasAiIndex,
    );
  }
}

const _noValue = Object();

@Riverpod(keepAlive: true)
class TocSearch extends _$TocSearch {
  @override
  TocSearchState build() => const TocSearchState();

  void start(String query) {
    final sanitized = query.trim();
    state = TocSearchState(
      query: sanitized,
      progress: 0.0,
      results: const [],
      isSearching: true,
      hasAiIndex: state.hasAiIndex,
    );
  }

  void updateProgress(double progress) {
    state = state.copyWith(
      progress: progress,
      isSearching: progress < 1.0,
    );
  }

  void addResult(SearchResultModel result) {
    final updated = List<SearchResultModel>.from(state.results)..add(result);
    state = state.copyWith(
      results: List<SearchResultModel>.unmodifiable(updated),
    );
  }

  void updateScrollOffset(double offset) {
    state = state.copyWith(scrollOffset: offset);
  }

  /// Set whether the current book has an AI semantic index.
  void setHasAiIndex(bool value) {
    state = state.copyWith(hasAiIndex: value);
  }

  /// Mark semantic search as in progress.
  void startSemanticSearch() {
    state = state.copyWith(
      isSemanticSearching: true,
      semanticResults: const [],
    );
  }

  /// Add semantic search results.
  void setSemanticResults(List<AiSemanticSearchEvidence> results) {
    state = state.copyWith(
      semanticResults: List<AiSemanticSearchEvidence>.unmodifiable(results),
      isSemanticSearching: false,
    );
  }

  /// Mark semantic search as failed/skipped.
  void finishSemanticSearch() {
    state = state.copyWith(isSemanticSearching: false);
  }

  void clear() {
    state = TocSearchState(hasAiIndex: state.hasAiIndex);
  }
}

