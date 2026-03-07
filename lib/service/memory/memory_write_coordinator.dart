import 'dart:async';

import 'package:anx_reader/service/memory/markdown_memory_store.dart';
import 'package:anx_reader/service/memory/memory_index_coordinator.dart';

class MemoryWriteCoordinator {
  MemoryWriteCoordinator({MarkdownMemoryStore? store})
      : _store = store ?? MarkdownMemoryStore();

  final MarkdownMemoryStore _store;
  Future<void> _tail = Future<void>.value();

  Future<void> append({
    required bool longTerm,
    DateTime? date,
    required String text,
    bool ensureNewlineBefore = true,
  }) {
    return _enqueue(() async {
      await _store.append(
        longTerm: longTerm,
        date: date,
        text: text,
        ensureNewlineBefore: ensureNewlineBefore,
      );
      MemoryIndexCoordinator.instance.markDirty();
    });
  }

  Future<void> replace({
    required bool longTerm,
    DateTime? date,
    required String text,
  }) {
    return _enqueue(() async {
      await _store.replace(longTerm: longTerm, date: date, text: text);
      MemoryIndexCoordinator.instance.markDirty();
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
