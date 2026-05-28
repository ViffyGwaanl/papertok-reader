import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/service/review/review_inbox_controller.dart';

const Object _unset = Object();

final reviewInboxControllerProvider = Provider<ReviewInboxController>((ref) {
  return ReviewInboxController();
});

final reviewInboxProvider =
    StateNotifierProvider<ReviewInboxNotifier, ReviewInboxState>(
  (ref) => ReviewInboxNotifier(ref.watch(reviewInboxControllerProvider)),
);

class ReviewInboxState {
  const ReviewInboxState({
    required this.items,
    this.statusFilter = ReviewItemStatus.pending,
    this.sourceTypeFilter,
    this.busyItemIds = const <String>{},
    this.lastError,
  });

  factory ReviewInboxState.initial() {
    return const ReviewInboxState(
      items: AsyncValue<List<ReviewItem>>.data(<ReviewItem>[]),
    );
  }

  final AsyncValue<List<ReviewItem>> items;
  final ReviewItemStatus statusFilter;
  final ReviewItemSourceType? sourceTypeFilter;
  final Set<String> busyItemIds;
  final String? lastError;

  bool isBusy(String itemId) => busyItemIds.contains(itemId);

  ReviewInboxState copyWith({
    AsyncValue<List<ReviewItem>>? items,
    ReviewItemStatus? statusFilter,
    Object? sourceTypeFilter = _unset,
    Set<String>? busyItemIds,
    String? lastError,
    bool clearError = false,
  }) {
    return ReviewInboxState(
      items: items ?? this.items,
      statusFilter: statusFilter ?? this.statusFilter,
      sourceTypeFilter: identical(sourceTypeFilter, _unset)
          ? this.sourceTypeFilter
          : sourceTypeFilter as ReviewItemSourceType?,
      busyItemIds: busyItemIds ?? this.busyItemIds,
      lastError: clearError ? null : lastError ?? this.lastError,
    );
  }
}

class ReviewInboxNotifier extends StateNotifier<ReviewInboxState> {
  ReviewInboxNotifier(this._controller) : super(ReviewInboxState.initial());

  final ReviewInboxController _controller;

  Future<void> refresh() async {
    state = state.copyWith(
      items: const AsyncValue<List<ReviewItem>>.loading(),
      clearError: true,
    );
    try {
      final items = await _controller.list(
        status: state.statusFilter,
        sourceType: state.sourceTypeFilter,
      );
      state = state.copyWith(
        items: AsyncValue<List<ReviewItem>>.data(items),
        clearError: true,
      );
    } catch (error, stackTrace) {
      state = state.copyWith(
        items: AsyncValue<List<ReviewItem>>.error(error, stackTrace),
        lastError: error.toString(),
      );
    }
  }

  Future<void> setStatusFilter(ReviewItemStatus status) async {
    state = state.copyWith(statusFilter: status, clearError: true);
    await refresh();
  }

  Future<void> setSourceTypeFilter(ReviewItemSourceType? sourceType) async {
    state = state.copyWith(
      sourceTypeFilter: sourceType,
      clearError: true,
    );
    await refresh();
  }

  Future<void> approve(String id) {
    return _runAction(id, () => _controller.approve(id));
  }

  Future<void> dismiss(String id) {
    return _runAction(id, () => _controller.dismiss(id));
  }

  Future<void> apply(String id) {
    return _runAction(id, () => _controller.apply(id));
  }

  Future<void> _runAction(
    String id,
    Future<ReviewItem> Function() action,
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
        items: AsyncValue<List<ReviewItem>>.error(error, stackTrace),
        lastError: error.toString(),
      );
    } finally {
      state = state.copyWith(
        busyItemIds: {...state.busyItemIds}..remove(id),
      );
    }
  }
}
