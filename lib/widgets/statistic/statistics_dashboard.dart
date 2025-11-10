import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/statistics_dashboard_tile.dart';
import 'package:anx_reader/providers/statistic_data.dart';
import 'package:anx_reader/providers/total_reading_time.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/library_totals_tile.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/period_summary_tile.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/top_book_tile.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/total_time_tile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:staggered_reorderable/staggered_reorderable.dart';

final Map<StatisticsDashboardTileType, StatisticsDashboardTileBase>
    _tileRegistry = {
  StatisticsDashboardTileType.totalTime: const TotalTimeTile(),
  StatisticsDashboardTileType.libraryTotals: const LibraryTotalsTile(),
  StatisticsDashboardTileType.periodSummary: const PeriodSummaryTile(),
  StatisticsDashboardTileType.topBook: const TopBookTile(),
};

class StatisticsDashboard extends ConsumerStatefulWidget {
  const StatisticsDashboard({super.key, required this.snapshot});

  final StatisticsDashboardSnapshot snapshot;

  @override
  ConsumerState<StatisticsDashboard> createState() =>
      _StatisticsDashboardState();
}

class _StatisticsDashboardState extends ConsumerState<StatisticsDashboard> {
  final Prefs _prefs = Prefs();
  bool _ignorePrefsEvent = false;
  late List<StatisticsDashboardTileType> _persistedTiles;
  late List<StatisticsDashboardTileType> _workingTiles;
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _persistedTiles = _safeTiles(_prefs.statisticsDashboardTiles);
    _workingTiles = List.of(_persistedTiles);
    _prefs.addListener(_handlePrefsChange);
  }

  List<StatisticsDashboardTileType> _safeTiles(
    List<StatisticsDashboardTileType> source,
  ) {
    final available = source
        .where((type) => _tileRegistry.containsKey(type))
        .toList(growable: false);
    if (available.isEmpty) {
      return List.of(defaultStatisticsDashboardTiles);
    }
    return available;
  }

  void _handlePrefsChange() {
    if (_ignorePrefsEvent) return;
    setState(() {
      _persistedTiles = _safeTiles(_prefs.statisticsDashboardTiles);
      if (!_hasUnsavedChanges) {
        _workingTiles = List.of(_persistedTiles);
      }
    });
  }

  @override
  void dispose() {
    _prefs.removeListener(_handlePrefsChange);
    super.dispose();
  }

  void _persistTiles() {
    _ignorePrefsEvent = true;
    try {
      _prefs.statisticsDashboardTiles = _persistedTiles;
    } finally {
      _ignorePrefsEvent = false;
    }
  }

  void _setUnsavedFlag() {
    _hasUnsavedChanges = !listEquals(_workingTiles, _persistedTiles);
  }

  void _handleReorder(List<int> trackingOrder) {
    final mapping = {
      for (final type in _workingTiles) type.index: type,
    };
    final newOrder = <StatisticsDashboardTileType>[];
    for (final tracking in trackingOrder) {
      final type = mapping[tracking];
      if (type != null && !newOrder.contains(type)) {
        newOrder.add(type);
      }
    }
    for (final type in _workingTiles) {
      if (!newOrder.contains(type)) {
        newOrder.add(type);
      }
    }
    setState(() {
      _workingTiles = newOrder;
      _setUnsavedFlag();
    });
  }

  void _handleAddTile(StatisticsDashboardTileType type) {
    if (_workingTiles.contains(type)) return;
    setState(() {
      _workingTiles = List.of(_workingTiles)..add(type);
      _setUnsavedFlag();
    });
  }

  void _handleRemoveTile(StatisticsDashboardTileType type) {
    if (_workingTiles.length <= 1) return;
    setState(() {
      _workingTiles = List.of(_workingTiles)..remove(type);
      _setUnsavedFlag();
    });
  }

  void _saveLayout() {
    if (!_hasUnsavedChanges) return;
    setState(() {
      _persistedTiles = List.of(_workingTiles);
      _hasUnsavedChanges = false;
    });
    _persistTiles();
  }

  void _discardChanges() {
    setState(() {
      _workingTiles = List.of(_persistedTiles);
      _hasUnsavedChanges = false;
    });
  }

  List<StatisticsDashboardTileType> get _availableTiles =>
      StatisticsDashboardTileType.values
          .where((type) => !_workingTiles.contains(type))
          .where((type) => _tileRegistry.containsKey(type))
          .toList(growable: false);

  void _showAddTileSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final items = _availableTiles;
        return SafeArea(
          child: items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('All tiles are already added.'), // TODO(l10n)
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final type = items[index];
                    final metadata = _tileRegistry[type]!.metadata;
                    return ListTile(
                      leading: Icon(metadata.icon),
                      title: Text(metadata.title),
                      subtitle: Text(metadata.description),
                      onTap: () {
                        Navigator.pop(context);
                        _handleAddTile(type);
                      },
                    );
                  },
                ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalReadingSnapshot = ref.watch(totalReadingTimeProvider);
    final statisticDataSnapshot = ref.watch(statisticDataProvider);
    final viewKey = ValueKey(Object.hashAll([
      _workingTiles,
      totalReadingSnapshot.hashCode,
      statisticDataSnapshot.hashCode,
    ]));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Dashboard', // TODO(l10n)
                style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            if (_hasUnsavedChanges)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: _discardChanges,
                    child: const Text('Discard'), // TODO(l10n)
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saveLayout,
                    icon: const Icon(Icons.save),
                    label: const Text('Save layout'), // TODO(l10n)
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('Long press a card to rearrange.', // TODO(l10n)
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey[600])),
            const Spacer(),
            TextButton.icon(
              onPressed: _availableTiles.isEmpty ? null : _showAddTileSheet,
              icon: const Icon(Icons.add),
              label: const Text('Add card'), // TODO(l10n)
            ),
          ],
        ),
        const SizedBox(height: 12),
        _workingTiles.isEmpty
            ? _EmptyDashboardState(onAddPressed: _showAddTileSheet)
            : LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisUnits =
                      _calculateColumnUnits(constraints.maxWidth);
                  return StaggeredReorderableView.customer(
                    key: viewKey,
                    columnNum: crossAxisUnits,
                    spacing: 10,
                    canDrag: true,
                    children: _buildReorderableItems(
                      context,
                      crossAxisUnits,
                    ),
                    onReorder: _handleReorder,
                    fixedCellHeight: 90,
                  );
                },
              ),
      ],
    );
  }

  List<ReorderableItem> _buildReorderableItems(
    BuildContext context,
    int columnUnits,
  ) {
    final snapshot = widget.snapshot;
    final canRemove = _workingTiles.length > 1;
    return _workingTiles.map((type) {
      final tile = _tileRegistry[type]!;
      return tile.buildReorderableItem(
        context: context,
        snapshot: snapshot,
        canRemove: canRemove,
        onRemove: canRemove ? () => _handleRemoveTile(type) : null,
        columnUnits: columnUnits,
      );
    }).toList(growable: false);
  }

  int _calculateColumnUnits(double width) {
    return (width ~/ 600) * 2 + 4;
  }
}

class _EmptyDashboardState extends StatelessWidget {
  const _EmptyDashboardState({this.onAddPressed});

  final VoidCallback? onAddPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
            'No cards yet. Tap “Add card” to get started.'), // TODO(l10n)
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onAddPressed,
          icon: const Icon(Icons.add),
          label: const Text('Add card'), // TODO(l10n)
        ),
      ],
    );
  }
}
