import 'dart:convert';

import 'package:anx_reader/providers/tb_groups.dart';
import 'package:anx_reader/service/ai/tools/models/bookshelf_organize_plan.dart';
import 'package:anx_reader/service/ai/tools/models/bookshelf_organize_plan_group.dart';
import 'package:anx_reader/service/bookshelf/bookshelf_organize_service.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:anx_reader/widgets/common/container/outlined_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

typedef _GroupNameLookup = Map<int, String>;

class OrganizeBookshelfStepTile extends ConsumerStatefulWidget {
  const OrganizeBookshelfStepTile({
    super.key,
    required this.step,
  });

  final ParsedToolStep step;

  @override
  ConsumerState<OrganizeBookshelfStepTile> createState() =>
      _OrganizeBookshelfStepTileState();
}

class _OrganizeBookshelfStepTileState
    extends ConsumerState<OrganizeBookshelfStepTile> {
  bool _expanded = false;
  bool _isApplying = false;
  bool _applied = false;
  bool _requiresConfirmation = false;
  BookshelfOrganizePlan? _plan;
  String? _parseError;

  @override
  void initState() {
    super.initState();
    _syncFromStep(initial: true);
  }

  @override
  void didUpdateWidget(covariant OrganizeBookshelfStepTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.step.output != oldWidget.step.output) {
      _syncFromStep(initial: false, useSetState: true);
    }
  }

  void _syncFromStep({required bool initial, bool useSetState = false}) {
    final output = widget.step.output;
    BookshelfOrganizePlan? plan;
    String? parseError;
    var requiresConfirmation = false;

    if (output == null || output.trim().isEmpty) {
      parseError = 'Waiting for tool output...'; // TODO: l10n
    } else {
      try {
        final decoded = jsonDecode(output);
        if (decoded is! Map<String, dynamic>) {
          parseError = 'Unexpected tool output format.'; // TODO: l10n
        } else {
          final data = decoded['data'];
          if (data is! Map<String, dynamic>) {
            parseError = 'Missing plan payload.'; // TODO: l10n
          } else {
            requiresConfirmation = data['requiresConfirmation'] == true ||
                data['requires_confirmation'] == true;
            final planJson = data['plan'];
            if (planJson is! Map) {
              parseError = 'Plan details missing.'; // TODO: l10n
            } else {
              plan = BookshelfOrganizePlan.fromJson(
                Map<String, dynamic>.from(planJson),
              );
              parseError = null;
            }
          }
        }
      } catch (error) {
        parseError = 'Failed to parse plan: $error'; // TODO: l10n
      }
    }

    void assign() {
      _plan = plan;
      _parseError = parseError;
      _requiresConfirmation = requiresConfirmation;
      if (!initial) {
        _applied = false;
        _isApplying = false;
      }
    }

    if (useSetState) {
      setState(assign);
    } else {
      assign();
    }
  }

  Color _statusColor(String status, ThemeData theme) {
    switch (status) {
      case 'success':
        return Colors.green;
      case 'failed':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(widget.step.status, theme);

    return OutlinedContainer(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      radius: 14,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_mosaic, size: 12),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.step.name,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                child: _buildExpandedContent(theme),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedContent(ThemeData theme) {
    if (_parseError != null) {
      return Text(_parseError!, style: theme.textTheme.bodyMedium);
    }

    if (_plan == null) {
      return Text('No re-organization plan was generated.',
          style: theme.textTheme.bodyMedium); // TODO: l10n
    }

    final groupLookup = _resolveGroupNames();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_plan!.summary != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(_plan!.summary!, style: theme.textTheme.bodyMedium),
          ),
        ..._plan!.groups
            .map((group) => _buildGroupBlock(group, groupLookup, theme)),
        if (_plan!.groups.isNotEmpty) const SizedBox(height: 8),
        if (_plan!.ungroupedBooks.isNotEmpty) _buildUngroupedBlock(theme),
        if (_plan!.cleanupGroupIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: _buildCleanupSection(groupLookup, theme),
          ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: widget.step.output == null
                  ? null
                  : () {
                      Clipboard.setData(
                          ClipboardData(text: widget.step.output!));
                      AnxToast.show('Plan copied.'); // TODO: l10n
                    },
              icon: const Icon(Icons.copy, size: 14),
              label: const Text('Copy JSON'), // TODO: l10n
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _canApplyPlan ? _applyPlan : null,
              child: _isApplying
                  ? SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          theme.colorScheme.onPrimary,
                        ),
                      ),
                    )
                  : Text(
                      _applied ? 'Completed' : 'Apply to bookshelf',
                    ), // TODO: l10n
            ),
          ],
        ),
      ],
    );
  }

  bool get _canApplyPlan =>
      !_isApplying && !_applied && _plan != null && _requiresConfirmation;

  Widget _buildGroupBlock(
    BookshelfOrganizePlanGroup group,
    _GroupNameLookup groupLookup,
    ThemeData theme,
  ) {
    final title = group.proposedName ?? group.currentName;
    final chips = <Widget>[];
    if (group.createNew) {
      chips.add(_buildChip(theme, 'New group')); // TODO: l10n
    }
    if (group.willRename) {
      final current = group.currentName ??
          groupLookup[group.groupId] ??
          'Unnamed'; // TODO: l10n
      chips.add(_buildChip(theme, 'Rename from "$current"')); // TODO: l10n
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: FilledContainer(
        color: theme.colorScheme.surfaceContainer,
        padding: const EdgeInsets.all(8),
        radius: 10,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title ?? 'Group ${group.groupId}', // TODO: l10n
              style: theme.textTheme.titleSmall,
            ),
            if (chips.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: chips,
                ),
              ),
            if (group.books.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: group.books
                      .map(
                        (book) => Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: Text(
                            '• ${book.title}${book.author != null ? ' — ${book.author}' : ''}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            if (group.books.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: Text(
                  'No books assigned in this plan.', // TODO: l10n
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUngroupedBlock(ThemeData theme) {
    return FilledContainer(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.all(8),
      radius: 10,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Books to ungroup',
              style: theme.textTheme.titleSmall), // TODO: l10n
          const SizedBox(height: 4),
          ..._plan!.ungroupedBooks.map(
            (book) => Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Text(
                '• ${book.title}${book.author != null ? ' — ${book.author}' : ''}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCleanupSection(
    _GroupNameLookup lookup,
    ThemeData theme,
  ) {
    return FilledContainer(
      color: theme.colorScheme.surfaceContainer,
      padding: const EdgeInsets.all(8),
      radius: 10,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Groups to remove',
              style: theme.textTheme.titleSmall), // TODO: l10n
          const SizedBox(height: 4),
          ..._plan!.cleanupGroupIds.map((id) {
            final name = lookup[id];
            return Text(
              name != null
                  ? '• $name (ID $id)'
                  : '• Group ID $id', // TODO: l10n
              style: theme.textTheme.bodySmall,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildChip(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.secondaryContainer,
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall,
      ),
    );
  }

  Future<void> _applyPlan() async {
    if (_plan == null) {
      return;
    }
    setState(() {
      _isApplying = true;
    });

    try {
      await ref.read(bookshelfOrganizeServiceProvider).applyPlan(_plan!);
      if (!mounted) return;
      setState(() {
        _isApplying = false;
        _applied = true;
      });
      AnxToast.show('Bookshelf updated.'); // TODO: l10n
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isApplying = false;
      });
      AnxToast.show('Failed to apply plan: $error'); // TODO: l10n
    }
  }

  _GroupNameLookup _resolveGroupNames() {
    final groups = ref.watch(groupDaoProvider);
    return groups.maybeWhen(
      data: (items) => {
        for (final group in items) group.id: group.name,
      },
      orElse: () => const {},
    );
  }
}
