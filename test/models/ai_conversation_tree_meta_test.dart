import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';

void main() {
  group('AiSegmentMeta', () {
    test('toJson/fromJson roundtrip preserves all fields', () {
      const meta = AiSegmentMeta(
        model: 'gpt-4o',
        inputTokens: 320,
        outputTokens: 880,
      );
      final restored = AiSegmentMeta.fromJson(meta.toJson());
      expect(restored.model, 'gpt-4o');
      expect(restored.inputTokens, 320);
      expect(restored.outputTokens, 880);
    });

    test('fromJson tolerates missing fields', () {
      final restored = AiSegmentMeta.fromJson(const {'model': 'claude'});
      expect(restored.model, 'claude');
      expect(restored.inputTokens, isNull);
      expect(restored.outputTokens, isNull);
    });

    test('footerText formats model and tokens, omitting null parts', () {
      const full = AiSegmentMeta(
        model: 'gpt-4o',
        inputTokens: 320,
        outputTokens: 880,
      );
      expect(full.footerText(), 'gpt-4o · 1.2K tok (320 in / 880 out)');

      const modelOnly = AiSegmentMeta(model: 'claude');
      expect(modelOnly.footerText(), 'claude');

      const empty = AiSegmentMeta();
      expect(empty.footerText(), '');
    });
  });

  group('AiConversationNode meta serialization', () {
    test('meta survives toJson/fromJson', () {
      const node = AiConversationNode(
        id: 'n1',
        parentId: 'root',
        children: <String>[],
        activeChildId: null,
        message: {'type': 'ai', 'content': 'hi', 'toolCalls': <dynamic>[]},
        createdAt: 1,
        updatedAt: 1,
        meta: AiSegmentMeta(model: 'm', inputTokens: 5, outputTokens: 7),
      );
      final restored = AiConversationNode.fromJson('n1', node.toJson());
      expect(restored.meta?.model, 'm');
      expect(restored.meta?.inputTokens, 5);
      expect(restored.meta?.outputTokens, 7);
    });

    test('node without meta deserializes meta as null (backward compatible)',
        () {
      final restored = AiConversationNode.fromJson('n1', const {
        'parentId': 'root',
        'children': <dynamic>[],
        'activeChildId': null,
        'message': {'type': 'ai', 'content': 'hi', 'toolCalls': <dynamic>[]},
        'createdAt': 1,
        'updatedAt': 1,
      });
      expect(restored.meta, isNull);
    });
  });
}
