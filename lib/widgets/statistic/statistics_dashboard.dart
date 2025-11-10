import 'dart:math' as math;

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/statistics_dashboard_tile.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/library_totals_tile.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/period_summary_tile.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/top_book_tile.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/total_time_tile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:staggered_reorderable/staggered_reorderable.dart';

const double _baseTileHeight = 90.0;

final Map<StatisticsDashboardTileType, StatisticsDashboardTileMetadata>
    _tileMetadata = {
  StatisticsDashboardTileType.totalTime: StatisticsDashboardTileMetadata(
    type: StatisticsDashboardTileType.totalTime,
    title: 'Lifetime reading', // TODO(l10n)
    description: 'Hours and minutes logged in Anx Reader.', // TODO(l10n)
    columnSpan: 4,
    rowSpan: 2,
    icon: Icons.timer_outlined,
  ),
  StatisticsDashboardTileType.libraryTotals: StatisticsDashboardTileMetadata(
    type: StatisticsDashboardTileType.libraryTotals,
    title: 'Library totals', // TODO(l10n)
    description: 'Books, reading days, and notes overview.', // TODO(l10n)
    columnSpan: 4,
    rowSpan: 2,
    icon: Icons.menu_book_outlined,
  ),
  StatisticsDashboardTileType.periodSummary: StatisticsDashboardTileMetadata(
    type: StatisticsDashboardTileType.periodSummary,
    title: 'Current period', // TODO(l10n)
    description: 'Highlights for the selected period below.', // TODO(l10n)
    columnSpan: 4,
    rowSpan: 2,
    icon: Icons.bar_chart_rounded,
  ),
  StatisticsDashboardTileType.topBook: StatisticsDashboardTileMetadata(
    type: StatisticsDashboardTileType.topBook,
    title: 'Top book', // TODO(l10n)
    description: 'Most read title in the current period.', // TODO(l10n)
    columnSpan: 2,
    rowSpan: 2,
    icon: Icons.bookmark_added_outlined,
  ),
};

class StatisticsDashboard extends StatefulWidget {
  const StatisticsDashboard({super.key, required this.snapshot});

  final StatisticsDashboardSnapshot snapshot;

  @override
  State<StatisticsDashboard> createState() => _StatisticsDashboardState();
}

class _StatisticsDashboardState extends State<StatisticsDashboard> {
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
      List<StatisticsDashboardTileType> source) {
    return source
        .where((type) => _tileMetadata.containsKey(type))
        .toList(growable: false);
  }

  void _handlePrefsChange() {
    if (_ignorePrefsEvent) return;
    final latest = _safeTiles(_prefs.statisticsDashboardTiles);
    setState(() {
      _persistedTiles =
          latest.isEmpty ? List.of(defaultStatisticsDashboardTiles) : latest;
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
                    final metadata = _tileMetadata[type]!;
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
    final tiles = _workingTiles;

    return Column(
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
        if (tiles.isEmpty)
          _EmptyDashboardState(onAddPressed: _showAddTileSheet)
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisUnits =
                  _calculateColumnUnits(constraints.maxWidth);
              final spacing = 12.0;
              return StaggeredReorderableView.customer(
                columnNum: crossAxisUnits,
                spacing: spacing,
                children: _buildReorderableItems(crossAxisUnits),
                canDrag: true,
                scrollDirection: Axis.vertical,
                onReorder: _handleReorder,
              );
            },
          ),
      ],
    );
  }

  List<ReorderableItem> _buildReorderableItems(int columnUnits) {
    return _workingTiles.map((type) {
      final metadata = _tileMetadata[type]!;
      final span = math.min(columnUnits, metadata.columnSpan);
      final tileHeight = _baseTileHeight * metadata.rowSpan;
      final tile = SizedBox.expand(
        child: _DashboardTileShell(
          height: tileHeight,
          child: _buildTileContent(metadata),
          showRemoveButton: _workingTiles.length > 1,
          onRemove:
              _workingTiles.length > 1 ? () => _handleRemoveTile(type) : null,
        ),
      );
      return ReorderableItem(
        trackingNumber: type.index,
        id: type.name,
        crossAxisCellCount: span,
        mainAxisCellCount: metadata.rowSpan,
        child: tile,
        placeholder: Opacity(opacity: 0.2, child: tile),
      );
    }).toList(growable: false);
  }

  Widget _buildTileContent(StatisticsDashboardTileMetadata metadata) {
    switch (metadata.type) {
      case StatisticsDashboardTileType.totalTime:
        return TotalTimeTile(snapshot: widget.snapshot, metadata: metadata);
      case StatisticsDashboardTileType.libraryTotals:
        return LibraryTotalsTile(snapshot: widget.snapshot, metadata: metadata);
      case StatisticsDashboardTileType.periodSummary:
        return PeriodSummaryTile(snapshot: widget.snapshot, metadata: metadata);
      case StatisticsDashboardTileType.topBook:
        return TopBookTile(snapshot: widget.snapshot, metadata: metadata);
    }
  }
}

int _calculateColumnUnits(double width) {
  print('width: $width, units: ${(width ~/ 300) * 2 + 2}');
  return (width ~/ 300) * 2 + 2;
}

class _DashboardTileShell extends StatelessWidget {
  const _DashboardTileShell({
    required this.height,
    required this.child,
    required this.showRemoveButton,
    this.onRemove,
  });

  final double height;
  final Widget child;
  final bool showRemoveButton;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: BoxConstraints.tightFor(height: height),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (showRemoveButton && onRemove != null)
            Positioned(
              top: -8,
              right: -8,
              child: IconButton.filledTonal(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: 'Remove card', // TODO(l10n)
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyDashboardState extends StatelessWidget {
  const _EmptyDashboardState({this.onAddPressed});

  final VoidCallback? onAddPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 24),
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
