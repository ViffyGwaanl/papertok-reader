import 'package:flutter/foundation.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';

enum ConversationTreeSpeaker {
  user,
  assistant,
  system,
  tool,
  custom,
  unknown,
}

@immutable
class ConversationTreeRenderModel {
  const ConversationTreeRenderModel({
    required this.nodes,
    required this.rootNodeIds,
    required this.activePathNodeIds,
  });

  final List<ConversationTreeRenderNode> nodes;
  final List<String> rootNodeIds;
  final List<String> activePathNodeIds;

  bool get isEmpty => nodes.isEmpty;

  ConversationTreeRenderNode? nodeById(String id) {
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }
}

@immutable
class ConversationTreeRenderNode {
  const ConversationTreeRenderNode({
    required this.id,
    required this.parentId,
    required this.childIds,
    required this.speaker,
    required this.summary,
    required this.depth,
    required this.isOnActivePath,
  });

  final String id;
  final String? parentId;
  final List<String> childIds;
  final ConversationTreeSpeaker speaker;
  final String summary;
  final int depth;
  final bool isOnActivePath;
}

ConversationTreeRenderModel buildConversationTreeRenderModel(
  AiConversationTree tree, {
  int summaryMaxLength = 72,
}) {
  final root = tree.nodes[tree.rootId];
  if (root == null) {
    return const ConversationTreeRenderModel(
      nodes: <ConversationTreeRenderNode>[],
      rootNodeIds: <String>[],
      activePathNodeIds: <String>[],
    );
  }

  final activePathNodeIds = tree.activePathNodeIds();
  final activePathNodeIdSet = activePathNodeIds.toSet();
  final nodes = <ConversationTreeRenderNode>[];

  List<String> renderableChildIds(AiConversationNode node) {
    return node.children
        .where((childId) => tree.nodes[childId]?.message != null)
        .toList(growable: false);
  }

  void visit({
    required String nodeId,
    required String? renderParentId,
    required int depth,
  }) {
    final node = tree.nodes[nodeId];
    final message = node?.toChatMessage();
    if (node == null || message == null) return;
    final childIds = renderableChildIds(node);
    nodes.add(
      ConversationTreeRenderNode(
        id: node.id,
        parentId: renderParentId,
        childIds: childIds,
        speaker: _speakerForMessage(message),
        summary: _summaryForMessage(message, maxLength: summaryMaxLength),
        depth: depth,
        isOnActivePath: activePathNodeIdSet.contains(node.id),
      ),
    );
    for (final childId in childIds) {
      visit(nodeId: childId, renderParentId: node.id, depth: depth + 1);
    }
  }

  final rootNodeIds = renderableChildIds(root);
  for (final childId in rootNodeIds) {
    visit(nodeId: childId, renderParentId: null, depth: 0);
  }

  return ConversationTreeRenderModel(
    nodes: List.unmodifiable(nodes),
    rootNodeIds: List.unmodifiable(rootNodeIds),
    activePathNodeIds: List.unmodifiable(
      activePathNodeIds.where((id) => tree.nodes[id]?.message != null),
    ),
  );
}

ConversationTreeSpeaker _speakerForMessage(ChatMessage message) {
  if (message is HumanChatMessage) return ConversationTreeSpeaker.user;
  if (message is AIChatMessage) return ConversationTreeSpeaker.assistant;
  if (message is SystemChatMessage) return ConversationTreeSpeaker.system;
  if (message is ToolChatMessage) return ConversationTreeSpeaker.tool;
  if (message is CustomChatMessage) return ConversationTreeSpeaker.custom;
  return ConversationTreeSpeaker.unknown;
}

String _summaryForMessage(ChatMessage message, {required int maxLength}) {
  final text = _messageText(message)
      .replaceAll(r'\n', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (text.isEmpty) return '';
  final firstSentence = RegExp(r'^(.+?[。！？!?\.])(?:\s|$)').firstMatch(text);
  final summary = firstSentence?.group(1)?.trim() ?? text;
  if (summary.length <= maxLength) return summary;
  if (maxLength <= 3) return summary.substring(0, maxLength);
  return '${summary.substring(0, maxLength - 3).trimRight()}...';
}

String _messageText(ChatMessage message) {
  if (message is HumanChatMessage) {
    final content = message.content;
    if (content is ChatMessageContentText) return content.text;
    if (content is ChatMessageContentMultiModal) {
      return content.parts
          .whereType<ChatMessageContentText>()
          .map((part) => part.text)
          .join(' ');
    }
    return '';
  }
  return message.contentAsString;
}
