import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/review/spaced_review_store.dart';

final spacedReviewStoreProvider = Provider<SpacedReviewStore>((ref) {
  return SpacedReviewStore();
});

final spacedReviewKnowledgeCardStoreProvider =
    Provider<KnowledgeCardStore>((ref) {
  return KnowledgeCardStore();
});

final spacedReviewProvider =
    StateNotifierProvider<SpacedReviewNotifier, SpacedReviewState>(
  (ref) => SpacedReviewNotifier(
    ref.watch(spacedReviewStoreProvider),
    ref.watch(spacedReviewKnowledgeCardStoreProvider),
  ),
);

class SpacedReviewState {
  const SpacedReviewState({
    required this.items,
    this.dueOnly = true,
    this.busyItemIds = const <String>{},
    this.lastError,
  });

  factory SpacedReviewState.initial() {
    return const SpacedReviewState(
      items: AsyncValue<List<SpacedReviewItem>>.data(<SpacedReviewItem>[]),
    );
  }

  final AsyncValue<List<SpacedReviewItem>> items;
  final bool dueOnly;
  final Set<String> busyItemIds;
  final String? lastError;

  bool isBusy(String itemId) => busyItemIds.contains(itemId);

  SpacedReviewState copyWith({
    AsyncValue<List<SpacedReviewItem>>? items,
    bool? dueOnly,
    Set<String>? busyItemIds,
    String? lastError,
    bool clearError = false,
  }) {
    return SpacedReviewState(
      items: items ?? this.items,
      dueOnly: dueOnly ?? this.dueOnly,
      busyItemIds: busyItemIds ?? this.busyItemIds,
      lastError: clearError ? null : lastError ?? this.lastError,
    );
  }
}

class SpacedReviewNotifier extends StateNotifier<SpacedReviewState> {
  SpacedReviewNotifier(this._store, this._knowledgeCardStore)
      : super(SpacedReviewState.initial());

  final SpacedReviewStore _store;
  final KnowledgeCardStore _knowledgeCardStore;

  Future<void> refresh() async {
    state = state.copyWith(
      items: const AsyncValue<List<SpacedReviewItem>>.loading(),
      clearError: true,
    );
    try {
      await _reconcileAppliedKnowledgeCards();
      final items = await _store.list(dueOnly: state.dueOnly);
      state = state.copyWith(
        items: AsyncValue<List<SpacedReviewItem>>.data(items),
        clearError: true,
      );
    } catch (error, stackTrace) {
      state = state.copyWith(
        items: AsyncValue<List<SpacedReviewItem>>.error(error, stackTrace),
        lastError: error.toString(),
      );
    }
  }

  Future<void> _reconcileAppliedKnowledgeCards() async {
    final appliedCards = await _knowledgeCardStore.list(
      reviewState: KnowledgeCardReviewState.applied,
    );
    for (final card in appliedCards) {
      if (!card.isUserAsset) continue;
      await _store.upsertFromKnowledgeCard(card);
    }
  }

  Future<void> setDueOnly(bool dueOnly) async {
    state = state.copyWith(dueOnly: dueOnly, clearError: true);
    await refresh();
  }

  Future<void> record(
    String id,
    SpacedReviewRating rating, {
    String? note,
  }) {
    return _runAction(
      id,
      () => _store.recordReview(id, rating: rating, note: note),
    );
  }

  Future<void> _runAction(
    String id,
    Future<SpacedReviewItem> Function() action,
  ) async {
    state = state.copyWith(
      busyItemIds: {...state.busyItemIds, id},
      clearError: true,
    );

    try {
      await action();
      await refresh();
    } catch (error, stackTrace) {
      state = state.copyWith(
        items: AsyncValue<List<SpacedReviewItem>>.error(error, stackTrace),
        lastError: error.toString(),
      );
    } finally {
      state = state.copyWith(
        busyItemIds: {...state.busyItemIds}..remove(id),
      );
    }
  }
}
