// lib/page/memory/memory_bulk_selection_controller.dart
import 'package:flutter/foundation.dart';

/// Small state holder for multi-select mode on the Memory browse / inbox
/// surfaces. A plain `ChangeNotifier` so the hosting widget owns lifecycle
/// without committing to Riverpod.
class MemoryBulkSelectionController extends ChangeNotifier {
  final Set<String> _selected = <String>{};
  bool _inSelectionMode = false;

  bool get inSelectionMode => _inSelectionMode;
  Set<String> get selected => Set<String>.unmodifiable(_selected);
  int get selectionCount => _selected.length;

  /// Enters selection mode. If [seedId] is provided, the first selected id
  /// comes from the long-press target.
  void enter({String? seedId}) {
    _inSelectionMode = true;
    if (seedId != null) {
      _selected.add(seedId);
    }
    notifyListeners();
  }

  /// Adds the id if absent, removes it if present. Stays in selection mode
  /// even when the set drops to zero — callers use `clear()` to exit.
  void toggle(String id) {
    if (_selected.contains(id)) {
      _selected.remove(id);
    } else {
      _selected.add(id);
    }
    notifyListeners();
  }

  /// Merges [ids] into the selection and enters selection mode.
  void selectAll(Iterable<String> ids) {
    _selected.addAll(ids);
    _inSelectionMode = true;
    notifyListeners();
  }

  /// Exits selection mode and clears the selection.
  void clear() {
    _selected.clear();
    _inSelectionMode = false;
    notifyListeners();
  }
}
