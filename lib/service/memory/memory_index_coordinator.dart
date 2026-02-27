import 'dart:async';

import 'package:anx_reader/service/memory/markdown_memory_store.dart';
import 'package:anx_reader/service/memory/memory_index_database.dart';
import 'package:anx_reader/service/memory/memory_search_service.dart';
import 'package:anx_reader/utils/log/common.dart';

/// Coordinates background refresh of the derived memory index.
///
/// Mobile platforms are not reliable for file watchers. Instead, we trigger
/// refresh on app-level events (editor save, tool writes, imports) and debounce
/// rebuilds.
class MemoryIndexCoordinator {
  MemoryIndexCoordinator._();

  static final MemoryIndexCoordinator instance = MemoryIndexCoordinator._();

  static const Duration defaultDebounce = Duration(milliseconds: 1500);

  Timer? _timer;
  bool _dirty = false;
  bool _running = false;

  bool get isDirty => _dirty;

  void markDirty({Duration debounce = defaultDebounce}) {
    _dirty = true;
    _timer?.cancel();
    _timer = Timer(debounce, _run);
  }

  /// Triggers a background refresh if the index is marked dirty.
  void ensureFreshInBackground() {
    if (_dirty) {
      markDirty(debounce: const Duration(milliseconds: 50));
    }
  }

  Future<void> _run() async {
    if (_running) return;
    if (!_dirty) return;

    _running = true;
    _dirty = false;

    try {
      final store = MarkdownMemoryStore();
      final db = MemoryIndexDatabase();
      final service = MemorySearchService(
        store: store,
        indexDb: db,
        // Index refresh does not depend on semantic settings.
        semanticEnabled: false,
      );

      await service.syncIndex();
    } catch (e) {
      AnxLog.warning('MemoryIndexCoordinator: refresh failed: $e');
      // Retry later.
      _dirty = true;
    } finally {
      _running = false;

      // If new changes arrived while running, schedule another pass.
      if (_dirty) {
        markDirty();
      }
    }
  }
}
