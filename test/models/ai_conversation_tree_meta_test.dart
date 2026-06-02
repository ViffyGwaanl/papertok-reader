import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/models/source_ref.dart';

void main() {
  group('AiSegmentMeta', () {
    test('toJson/fromJson roundtrip preserves all fields', () {
      const meta = AiSegmentMeta(
        model: 'gpt-4o',
        inputTokens: 320,
        outputTokens: 880,
        seminarRunCard: AiSeminarRunCardMeta(
          question: 'How should I read this claim?',
          sessionId: 'seminar-session-1',
          bookId: 7,
          status: 'ready',
          roleIds: ['critical', 'supportive', 'verifier', 'synthesizer'],
          evidenceScopeIds: ['current-book'],
          sourceRefCount: 1,
          allowWeb: false,
          writeRequiresApproval: true,
          maxRounds: 2,
          createdAt: 1234,
        ),
      );
      final restored = AiSegmentMeta.fromJson(meta.toJson());
      expect(restored.model, 'gpt-4o');
      expect(restored.inputTokens, 320);
      expect(restored.outputTokens, 880);
      expect(
          restored.seminarRunCard?.question, 'How should I read this claim?');
      expect(restored.seminarRunCard?.sessionId, 'seminar-session-1');
      expect(restored.seminarRunCard?.bookId, 7);
      expect(restored.seminarRunCard?.status, 'ready');
      expect(restored.seminarRunCard?.roleIds,
          ['critical', 'supportive', 'verifier', 'synthesizer']);
      expect(restored.seminarRunCard?.evidenceScopeIds, ['current-book']);
      expect(restored.seminarRunCard?.sourceRefCount, 1);
      expect(restored.seminarRunCard?.allowWeb, false);
      expect(restored.seminarRunCard?.writeRequiresApproval, true);
      expect(restored.seminarRunCard?.maxRounds, 2);
      expect(restored.seminarRunCard?.createdAt, 1234);
    });

    test('seminar run card preserves reader SourceRef', () {
      final sourceRef = SourceRef(
        bookId: 7,
        cfi: 'epubcfi(/6/4[selection])',
        jumpLink:
            'paperreader://reader/open?bookId=7&cfi=epubcfi%28%2F6%2F4%5Bselection%5D%29',
        sourceTitle: 'Scoped Book',
        locationLabel: 'Chapter 1',
        sourceTextSnippet: 'Evidence-backed passage.',
        sourceTextForHash: 'Evidence-backed passage.',
        sourceKind: SourceRefKind.reader,
        createdAt: 1,
      );
      final meta = AiSegmentMeta(
        seminarRunCard: AiSeminarRunCardMeta(
          question: 'Debate this passage.',
          bookId: 7,
          sourceRef: sourceRef,
          status: 'ready',
          createdAt: 1234,
        ),
      );

      final restored = AiSegmentMeta.fromJson(meta.toJson());

      expect(restored.seminarRunCard?.sourceRef?.bookId, 7);
      expect(
          restored.seminarRunCard?.sourceRef?.cfi, 'epubcfi(/6/4[selection])');
      expect(restored.isEmpty, false);
    });

    test('seminar run card falls back to stable createdAt for malformed json',
        () {
      final restored = AiSeminarRunCardMeta.fromJson(const {
        'question': 'Debate this passage.',
        'createdAt': 'bad',
      });

      expect(restored.question, 'Debate this passage.');
      expect(restored.createdAt, 0);
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

    test('reader SourceRef survives conversation tree json roundtrip', () {
      final sourceRef = SourceRef(
        bookId: 7,
        cfi: 'epubcfi(/6/4[selection])',
        jumpLink:
            'paperreader://reader/open?bookId=7&cfi=epubcfi%28%2F6%2F4%5Bselection%5D%29',
        sourceTitle: 'Scoped Book',
        locationLabel: 'Chapter 1',
        sourceTextSnippet: 'Attention needs exact evidence.',
        sourceTextForHash: 'Attention needs exact evidence.',
        sourceKind: SourceRefKind.reader,
        createdAt: 1,
      );

      final tree = AiConversationTree.fromJson({
        'schemaVersion': 2,
        'rootId': 'root',
        'nodes': {
          'root': {
            'parentId': null,
            'children': ['user-1'],
            'activeChildId': 'user-1',
            'message': null,
            'createdAt': 0,
            'updatedAt': 0,
          },
          'user-1': {
            'parentId': 'root',
            'children': ['assistant-1'],
            'activeChildId': 'assistant-1',
            'message': ChatMessage.humanText(
              'Attention needs exact evidence.',
            ).toMap(),
            'sourceRef': sourceRef.toJson(),
            'createdAt': 1,
            'updatedAt': 1,
          },
          'assistant-1': {
            'parentId': 'user-1',
            'children': <String>[],
            'activeChildId': null,
            'message': ChatMessage.ai(
              'Attention weights context for the current passage.',
            ).toMap(),
            'createdAt': 2,
            'updatedAt': 2,
          },
        },
      });

      final json = tree.toJson();
      final nodes = json['nodes'] as Map<String, dynamic>;
      final userNode = nodes['user-1'] as Map<String, dynamic>;
      final restoredSourceRef = userNode['sourceRef'] as Map<String, dynamic>?;

      expect(restoredSourceRef, isNotNull);
      expect(restoredSourceRef!['bookId'], 7);
      expect(restoredSourceRef['cfi'], 'epubcfi(/6/4[selection])');
      expect(restoredSourceRef['sourceKind'], SourceRefKind.reader.asString);
    });
  });
}
