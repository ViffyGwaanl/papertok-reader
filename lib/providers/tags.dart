import 'package:anx_reader/dao/tag.dart';
import 'package:anx_reader/models/tag.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tags.g.dart';

@riverpod
class TagList extends _$TagList {
  @override
  Future<List<Tag>> build() async {
    return tagDao.fetchAllTags();
  }

  Future<int> createTag(String name, {int? color}) async {
    final id = await tagDao.insertTag(name, color: color);
    await _refresh();
    return id;
  }

  Future<void> updateTag(int id, {String? newName, int? color}) async {
    await tagDao.updateTag(id, newName: newName, color: color);
    await _refresh();
  }

  Future<void> deleteTag(int id) async {
    await tagDao.deleteTag(id);
    await _refresh();
  }

  Future<void> _refresh() async {
    state = const AsyncValue.loading();
    state = AsyncValue.data(await build());
  }
}

class BookTagState {
  final List<Tag> tags;
  final Set<int> attachedIds;

  const BookTagState({
    required this.tags,
    required this.attachedIds,
  });

  bool isAttached(int tagId) => attachedIds.contains(tagId);

  Tag resolveWithColor(Tag tag, int Function(String) fallback) {
    if (tag.color != null) return tag;
    return tag.copyWith(color: fallback(tag.name));
  }
}

@riverpod
class BookTagEditor extends _$BookTagEditor {
  @override
  Future<BookTagState> build(int bookId) async {
    final tags = await tagDao.fetchAllTags();
    final attachedIds = (await bookTagDao.fetchTagIdsForBook(bookId)).toSet();
    return BookTagState(tags: tags, attachedIds: attachedIds);
  }

  Future<void> attachExisting(Tag tag) async {
    await bookTagDao.addRelation(bookId: bookId, tagId: tag.id);
    ref.invalidate(tagListProvider);
    await _refresh();
  }

  Future<void> detach(Tag tag) async {
    await bookTagDao.removeRelation(bookId: bookId, tagId: tag.id);
    await _refresh();
  }

  Future<void> createAndAttach(String name, {required int color}) async {
    final tagId = await tagDao.insertTag(name, color: color);
    await bookTagDao.addRelation(bookId: bookId, tagId: tagId);
    ref.invalidate(tagListProvider);
    await _refresh();
  }

  Future<void> _refresh() async {
    state = const AsyncValue.loading();
    state = AsyncValue.data(await build(bookId));
  }
}

@riverpod
class TagSelection extends _$TagSelection {
  @override
  Set<int> build() => <int>{};

  void toggle(int tagId) {
    final next = {...state};
    if (next.contains(tagId)) {
      next.remove(tagId);
    } else {
      next.add(tagId);
    }
    state = next;
  }

  void setSelection(Set<int> tagIds) {
    state = {...tagIds};
  }

  void clear() {
    state = <int>{};
  }
}
