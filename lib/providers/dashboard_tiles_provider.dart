import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/statistics_dashboard_tile.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DashboardTilesState {
  const DashboardTilesState({
    required this.savedTiles,
    required this.workingTiles,
    required this.hasUnsavedChanges,
  });

  final List<StatisticsDashboardTileType> savedTiles;
  final List<StatisticsDashboardTileType> workingTiles;
  final bool hasUnsavedChanges;

  DashboardTilesState copyWith({
    List<StatisticsDashboardTileType>? savedTiles,
    List<StatisticsDashboardTileType>? workingTiles,
    bool? hasUnsavedChanges,
  }) {
    return DashboardTilesState(
      savedTiles: savedTiles ?? this.savedTiles,
      workingTiles: workingTiles ?? this.workingTiles,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
    );
  }
}

class DashboardTilesNotifier extends StateNotifier<DashboardTilesState> {
  DashboardTilesNotifier()
      : _prefs = Prefs(),
        super(_initialState()) {
    _prefs.addListener(_handlePrefsChange);
  }

  final Prefs _prefs;

  static DashboardTilesState _initialState() {
    final prefs = Prefs();
    final tiles = _sanitize(prefs.statisticsDashboardTiles);
    return DashboardTilesState(
      savedTiles: tiles,
      workingTiles: List.of(tiles),
      hasUnsavedChanges: false,
    );
  }

  static List<StatisticsDashboardTileType> _sanitize(
    List<StatisticsDashboardTileType> source,
  ) {
    final seen = <StatisticsDashboardTileType>{};
    final filtered = <StatisticsDashboardTileType>[];
    for (final type in source) {
      if (!dashboardTileRegistry.containsKey(type)) continue;
      if (seen.add(type)) {
        filtered.add(type);
      }
    }
    if (filtered.isEmpty) {
      return List.of(defaultStatisticsDashboardTiles);
    }
    return filtered;
  }

  void _handlePrefsChange() {
    final sanitized = _sanitize(_prefs.statisticsDashboardTiles);
    if (state.hasUnsavedChanges) {
      state = state.copyWith(savedTiles: sanitized);
    } else {
      state = DashboardTilesState(
        savedTiles: sanitized,
        workingTiles: List.of(sanitized),
        hasUnsavedChanges: false,
      );
    }
  }

  List<StatisticsDashboardTileType> get workingTiles => state.workingTiles;

  List<StatisticsDashboardTileType> get availableTiles {
    final list = List<StatisticsDashboardTileType>.from(
      dashboardTileRegistry.keys.where(
        (type) => !state.workingTiles.contains(type),
      ),
    );
    list.sort((a, b) => a.index.compareTo(b.index));
    return list;
  }

  void reorder(List<int> order) {
    final map = {
      for (final type in state.workingTiles) type.index: type,
    };
    final reordered = <StatisticsDashboardTileType>[];
    for (final index in order) {
      final type = map[index];
      if (type != null && !reordered.contains(type)) {
        reordered.add(type);
      }
    }
    for (final type in state.workingTiles) {
      if (!reordered.contains(type)) {
        reordered.add(type);
      }
    }
    _updateWorking(reordered);
  }

  void addTile(StatisticsDashboardTileType type) {
    if (state.workingTiles.contains(type)) return;
    _updateWorking(List.of(state.workingTiles)..add(type));
  }

  void removeTile(StatisticsDashboardTileType type) {
    if (state.workingTiles.length <= 1) return;
    final updated = List.of(state.workingTiles)..remove(type);
    _updateWorking(updated);
  }

  void saveLayout() {
    final sanitized = _sanitize(state.workingTiles);
    state = DashboardTilesState(
      savedTiles: sanitized,
      workingTiles: List.of(sanitized),
      hasUnsavedChanges: false,
    );
    _prefs.statisticsDashboardTiles = sanitized;
  }

  void discardChanges() {
    state = state.copyWith(
      workingTiles: List.of(state.savedTiles),
      hasUnsavedChanges: false,
    );
  }

  void _updateWorking(List<StatisticsDashboardTileType> next) {
    final sanitized = _sanitize(next);
    final dirty = !listEquals(sanitized, state.savedTiles);
    state = state.copyWith(
      workingTiles: sanitized,
      hasUnsavedChanges: dirty,
    );
  }

  @override
  void dispose() {
    _prefs.removeListener(_handlePrefsChange);
    super.dispose();
  }
}

final dashboardTilesProvider =
    StateNotifierProvider<DashboardTilesNotifier, DashboardTilesState>(
        (ref) => DashboardTilesNotifier());
