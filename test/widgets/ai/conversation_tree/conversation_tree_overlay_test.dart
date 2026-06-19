import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/widgets/ai/conversation_tree/conversation_tree_model.dart';
import 'package:papertok_reader/widgets/ai/conversation_tree/conversation_tree_overlay.dart';

void main() {
  testWidgets('ConversationTreeOverlay renders empty state and close action',
      (tester) async {
    var closed = false;
    await tester.pumpWidget(
      _Harness(
        child: ConversationTreeOverlay(
          model: buildConversationTreeRenderModel(AiConversationTree.empty()),
          onClose: () => closed = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Conversation tree'), findsOneWidget);
    expect(find.text('No conversation branches yet.'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();

    expect(closed, isTrue);
  });

  testWidgets('ConversationTreeOverlay renders nodes and active path',
      (tester) async {
    await tester.pumpWidget(
      _Harness(
        child: ConversationTreeOverlay(
          model: buildConversationTreeRenderModel(_branchingTree()),
          onClose: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('You'), findsOneWidget);
    expect(find.text('AI'), findsNWidgets(2));
    expect(find.text('Question'), findsOneWidget);
    expect(find.text('First answer.'), findsOneWidget);
    expect(find.text('Second answer.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('conversation-tree-active-node-h1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('conversation-tree-active-node-a2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('conversation-tree-node-a1')),
      findsOneWidget,
    );
  });

  testWidgets('ConversationTreeOverlay scrolls long conversations',
      (tester) async {
    await tester.pumpWidget(
      _Harness(
        child: SizedBox(
          height: 360,
          child: ConversationTreeOverlay(
            model: buildConversationTreeRenderModel(_longTree(24)),
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Scrollable), findsWidgets);
    expect(find.text('Message 23'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Message 23'),
      160,
      scrollable: find.byType(Scrollable).last,
    );

    expect(find.text('Message 23'), findsOneWidget);
  });
}

class _Harness extends StatelessWidget {
  const _Harness({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(body: child),
    );
  }
}

AiConversationTree _branchingTree() {
  return AiConversationTree(
    rootId: 'root',
    nodes: {
      'root': _node('root', null, null, children: const ['h1'], active: 'h1'),
      'h1': _node(
        'h1',
        'root',
        ChatMessage.humanText('Question'),
        children: const ['a1', 'a2'],
        active: 'a2',
      ),
      'a1': _node('a1', 'h1', ChatMessage.ai('First answer. Hidden.')),
      'a2': _node('a2', 'h1', ChatMessage.ai('Second answer. Active.')),
    },
  );
}

AiConversationTree _longTree(int count) {
  final nodes = <String, AiConversationNode>{
    'root': _node('root', null, null, children: const ['n0'], active: 'n0'),
  };
  for (var i = 0; i < count; i++) {
    nodes['n$i'] = _node(
      'n$i',
      i == 0 ? 'root' : 'n${i - 1}',
      i.isEven
          ? ChatMessage.humanText('Message $i')
          : ChatMessage.ai('Message $i'),
      children: i == count - 1 ? const [] : ['n${i + 1}'],
      active: i == count - 1 ? null : 'n${i + 1}',
    );
  }
  return AiConversationTree(rootId: 'root', nodes: nodes);
}

AiConversationNode _node(
  String id,
  String? parentId,
  ChatMessage? message, {
  List<String> children = const <String>[],
  String? active,
}) {
  return AiConversationNode(
    id: id,
    parentId: parentId,
    children: children,
    activeChildId: active,
    message: message?.toMap(),
    createdAt: 1,
    updatedAt: 1,
  );
}
