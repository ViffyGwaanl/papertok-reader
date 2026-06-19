import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/ai/conversation_tree/conversation_tree_model.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

class ConversationTreeOverlay extends StatelessWidget {
  const ConversationTreeOverlay({
    required this.model,
    required this.onClose,
    this.onNodeSelected,
    super.key,
  });

  final ConversationTreeRenderModel model;
  final VoidCallback onClose;
  final ValueChanged<String>? onNodeSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final size = MediaQuery.sizeOf(context);
    return PointerInterceptor(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: size.height * 0.82,
          ),
          child: Material(
            color: ClaudePalette.card(context),
            elevation: 18,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ConversationTreeHeader(l10n: l10n, onClose: onClose),
                Divider(height: 1, color: ClaudePalette.divider(context)),
                Flexible(
                  child: model.isEmpty
                      ? _ConversationTreeEmptyState(l10n: l10n)
                      : Scrollbar(
                          child: ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.all(12),
                            itemCount: model.nodes.length,
                            itemBuilder: (context, index) {
                              return _ConversationTreeNodeTile(
                                node: model.nodes[index],
                                l10n: l10n,
                                onSelected: onNodeSelected == null
                                    ? null
                                    : () =>
                                        onNodeSelected!(model.nodes[index].id),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationTreeHeader extends StatelessWidget {
  const _ConversationTreeHeader({
    required this.l10n,
    required this.onClose,
  });

  final L10n l10n;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 8, 10),
      child: Row(
        children: [
          Icon(
            Icons.account_tree_outlined,
            size: 18,
            color: ClaudePalette.accent(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.conversationTreeTitle,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: ClaudePalette.fg(context),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          IconButton(
            tooltip: l10n.conversationTreeClose,
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
            icon: const Icon(Icons.close_outlined, size: 18),
          ),
        ],
      ),
    );
  }
}

class _ConversationTreeEmptyState extends StatelessWidget {
  const _ConversationTreeEmptyState({required this.l10n});

  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        l10n.conversationTreeEmpty,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: ClaudePalette.secondary(context),
            ),
      ),
    );
  }
}

class _ConversationTreeNodeTile extends StatelessWidget {
  const _ConversationTreeNodeTile({
    required this.node,
    required this.l10n,
    this.onSelected,
  });

  final ConversationTreeRenderNode node;
  final L10n l10n;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final active = node.isOnActivePath;
    final theme = Theme.of(context);
    final bgColor = active
        ? ClaudePalette.accentTint(context).withValues(alpha: 0.72)
        : ClaudePalette.bg(context).withValues(alpha: 0.52);
    final borderColor =
        active ? ClaudePalette.accent(context) : ClaudePalette.divider(context);
    final tile = DecoratedBox(
      key: ValueKey(
        active
            ? 'conversation-tree-active-node-${node.id}'
            : 'conversation-tree-node-${node.id}',
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? ClaudePalette.accent(context)
                    : ClaudePalette.secondary(context),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _speakerLabel(l10n, node.speaker),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: active
                          ? ClaudePalette.accent(context)
                          : ClaudePalette.secondary(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    node.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ClaudePalette.fg(context),
                      height: 1.28,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: math.min(node.depth * 22.0, 132.0),
        bottom: 8,
      ),
      child: onSelected == null
          ? tile
          : InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onSelected,
              child: tile,
            ),
    );
  }
}

String _speakerLabel(L10n l10n, ConversationTreeSpeaker speaker) {
  switch (speaker) {
    case ConversationTreeSpeaker.user:
      return l10n.conversationTreeSpeakerYou;
    case ConversationTreeSpeaker.assistant:
      return l10n.conversationTreeSpeakerAi;
    case ConversationTreeSpeaker.system:
      return l10n.conversationTreeSpeakerSystem;
    case ConversationTreeSpeaker.tool:
      return l10n.conversationTreeSpeakerTool;
    case ConversationTreeSpeaker.custom:
      return l10n.conversationTreeSpeakerCustom;
    case ConversationTreeSpeaker.unknown:
      return l10n.conversationTreeSpeakerUnknown;
  }
}
