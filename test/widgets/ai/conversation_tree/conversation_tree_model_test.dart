import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/widgets/ai/conversation_tree/conversation_tree_model.dart';

void main() {
  test(
      'buildConversationTreeRenderModel returns no message nodes for empty tree',
      () {
    final model = buildConversationTreeRenderModel(
      AiConversationTree.empty(),
    );

    expect(model.nodes, isEmpty);
    expect(model.rootNodeIds, isEmpty);
    expect(model.activePathNodeIds, isEmpty);
    expect(model.isEmpty, isTrue);
  });

  test('buildConversationTreeRenderModel adapts a single user node', () {
    final tree = _tree(
      nodes: {
        'root': _root(children: const ['h1'], activeChildId: 'h1'),
        'h1': _node(
          id: 'h1',
          parentId: 'root',
          message: ChatMessage.humanText('How should I read this book?'),
        ),
      },
    );

    final model = buildConversationTreeRenderModel(tree);

    expect(model.rootNodeIds, ['h1']);
    expect(model.activePathNodeIds, ['h1']);
    expect(model.nodes, hasLength(1));
    expect(model.nodeById('h1')?.speaker, ConversationTreeSpeaker.user);
    expect(model.nodeById('h1')?.summary, 'How should I read this book?');
    expect(model.nodeById('h1')?.parentId, isNull);
    expect(model.nodeById('h1')?.depth, 0);
    expect(model.nodeById('h1')?.isOnActivePath, isTrue);
  });

  test('buildConversationTreeRenderModel preserves siblings and active branch',
      () {
    final tree = _tree(
      nodes: {
        'root': _root(children: const ['h1'], activeChildId: 'h1'),
        'h1': _node(
          id: 'h1',
          parentId: 'root',
          children: const ['a1', 'a2'],
          activeChildId: 'a2',
          message: ChatMessage.humanText('Question'),
        ),
        'a1': _node(
          id: 'a1',
          parentId: 'h1',
          message: ChatMessage.ai('First answer. Hidden by variant.'),
        ),
        'a2': _node(
          id: 'a2',
          parentId: 'h1',
          message: ChatMessage.ai('Second answer. Active variant.'),
        ),
      },
    );

    final model = buildConversationTreeRenderModel(tree);

    expect(model.nodes.map((node) => node.id), ['h1', 'a1', 'a2']);
    expect(model.nodeById('h1')?.childIds, ['a1', 'a2']);
    expect(model.nodeById('a1')?.speaker, ConversationTreeSpeaker.assistant);
    expect(model.nodeById('a1')?.isOnActivePath, isFalse);
    expect(model.nodeById('a2')?.isOnActivePath, isTrue);
    expect(model.activePathNodeIds, ['h1', 'a2']);
  });

  test('buildConversationTreeRenderModel marks a deep active path', () {
    final tree = _tree(
      nodes: {
        'root': _root(children: const ['h1'], activeChildId: 'h1'),
        'h1': _node(
          id: 'h1',
          parentId: 'root',
          children: const ['a1'],
          activeChildId: 'a1',
          message: ChatMessage.humanText('Line one\\nLine two'),
        ),
        'a1': _node(
          id: 'a1',
          parentId: 'h1',
          children: const ['h2'],
          activeChildId: 'h2',
          message: ChatMessage.ai('Answer one\nwith more detail.'),
        ),
        'h2': _node(
          id: 'h2',
          parentId: 'a1',
          children: const ['a2', 'a3'],
          activeChildId: 'a3',
          message: ChatMessage.humanText('Follow up: explain chapter 2.'),
        ),
        'a2': _node(
          id: 'a2',
          parentId: 'h2',
          message: ChatMessage.ai('Inactive branch.'),
        ),
        'a3': _node(
          id: 'a3',
          parentId: 'h2',
          message: ChatMessage.ai('Active branch final answer.'),
        ),
      },
    );

    final model = buildConversationTreeRenderModel(tree);

    expect(model.activePathNodeIds, ['h1', 'a1', 'h2', 'a3']);
    expect(model.nodeById('h1')?.summary, 'Line one Line two');
    expect(model.nodeById('a1')?.summary, 'Answer one with more detail.');
    expect(model.nodeById('a3')?.depth, 3);
    expect(
      model.nodes.where((node) => node.isOnActivePath).map((node) => node.id),
      ['h1', 'a1', 'h2', 'a3'],
    );
  });
}

AiConversationTree _tree({
  required Map<String, AiConversationNode> nodes,
}) {
  return AiConversationTree(rootId: 'root', nodes: nodes);
}

AiConversationNode _root({
  List<String> children = const <String>[],
  String? activeChildId,
}) {
  return AiConversationNode(
    id: 'root',
    parentId: null,
    children: children,
    activeChildId: activeChildId,
    message: null,
    createdAt: 1,
    updatedAt: 1,
  );
}

AiConversationNode _node({
  required String id,
  required String parentId,
  required ChatMessage message,
  List<String> children = const <String>[],
  String? activeChildId,
}) {
  return AiConversationNode(
    id: id,
    parentId: parentId,
    children: children,
    activeChildId: activeChildId,
    message: message.toMap(),
    createdAt: 1,
    updatedAt: 1,
  );
}
