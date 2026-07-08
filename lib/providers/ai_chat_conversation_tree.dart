part of 'ai_chat.dart';

extension AiChatConversationTreeActions on AiChat {
  AiConversationTree get conversationTree => _tree;

  bool activatePathToNode(String rawNodeId) {
    final nodeId = rawNodeId.trim();
    if (nodeId.isEmpty || nodeId == _tree.rootId) return false;
    final path = <AiConversationNode>[];
    final seen = <String>{};
    for (var id = nodeId; id != _tree.rootId;) {
      if (!seen.add(id)) return false;
      final node = _tree.nodes[id];
      final parentId = node?.parentId;
      if (node == null || parentId == null) return false;
      path.add(node);
      id = parentId;
    }
    var nextTree = _tree;
    for (final node in path.reversed) {
      nextTree = nextTree.setActiveChild(node.parentId!, node.id);
    }
    _tree = nextTree;
    _rebuildFromTree();
    _persistCurrentConversationWithReader(ref.read);
    return true;
  }
}
