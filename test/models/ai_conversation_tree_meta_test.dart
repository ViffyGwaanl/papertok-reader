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
          snapshot: AiSeminarRunCardSnapshot(
            evidence: [
              AiSeminarRunCardEvidenceSnapshot(
                title: 'Chapter 2',
                snippet: 'The source passage grounds the disagreement.',
              ),
            ],
            toolCalls: [
              AiSeminarRunCardToolCallSnapshot(
                id: 'tool-call-1',
                toolId: 'semantic_search_current_book',
                status: 'running',
                query: 'How should I read this claim?',
                resultCount: 1,
                startedAt: 1717516800000,
                completedAt: 1717516801000,
                roleIds: ['critical', 'supportive'],
                actionIds: ['wait-tool-call', 'cancel-tool-call'],
                evidenceRefs: [
                  AiSeminarRunCardEvidenceSnapshot(
                    id: 'e1',
                    title: 'Chapter 2',
                    snippet: 'The source passage grounds the disagreement.',
                  ),
                ],
              ),
            ],
            roleSummaries: [
              AiSeminarRunCardRoleSummary(
                roleId: 'critical',
                label: 'Critical',
                summary: 'This claim needs a boundary condition.',
              ),
              AiSeminarRunCardRoleSummary(
                roleId: 'supportive',
                label: 'Supportive',
                summary: 'The surrounding paragraph supports it.',
              ),
            ],
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'tool_call',
                id: 'tool-call-1',
                toolId: 'semantic_search_current_book',
                status: 'running',
                label: 'Book semantic search',
                query: 'How should I read this claim?',
                resultCount: 1,
                startedAt: 1717516800000,
                completedAt: 1717516801000,
                roleIds: ['critical', 'supportive'],
                actionIds: ['wait-tool-call', 'cancel-tool-call'],
                evidenceRefs: [
                  AiSeminarRunCardEvidenceSnapshot(
                    id: 'e1',
                    title: 'Chapter 2',
                    snippet: 'The source passage grounds the disagreement.',
                  ),
                ],
              ),
              AiSeminarRunCardMessagePart(
                type: 'evidence',
                id: 'evidence-bundle-1',
                label: 'Evidence snapshot',
                evidenceRefs: [
                  AiSeminarRunCardEvidenceSnapshot(
                    id: 'e1',
                    title: 'Chapter 2',
                    snippet: 'The source passage grounds the disagreement.',
                  ),
                ],
              ),
              AiSeminarRunCardMessagePart(
                type: 'role_turn',
                roleId: 'critical',
                label: 'Critical',
                text: 'This claim needs a boundary condition.',
                evidenceRefs: [
                  AiSeminarRunCardEvidenceSnapshot(
                    id: 'e1',
                    title: 'Chapter 2',
                    snippet: 'The source passage grounds the disagreement.',
                  ),
                ],
              ),
              AiSeminarRunCardMessagePart(
                type: 'role_partial',
                roleId: 'supportive',
                label: 'Supportive',
                text: 'Streaming support response...',
              ),
              AiSeminarRunCardMessagePart(
                type: 'agent_status',
                id: 'status-critical-running',
                agentRunId: 'seminar-session-1:role-critical-0',
                parentRunId: 'seminar-session-1',
                roleId: 'critical',
                status: 'role-running',
                label: 'role-running',
                text: 'Critical is running.',
                allowedToolIds: [
                  'semantic_search_current_book',
                  'notes_search',
                ],
              ),
              AiSeminarRunCardMessagePart(
                type: 'reader_turn',
                id: 'user-1',
                roleId: 'critical',
                label: 'ask-role',
                text: 'Please let the critic respond to the scope dispute.',
                completedAt: 1717516802000,
              ),
              AiSeminarRunCardMessagePart(
                type: 'director_state',
                id: 'director-seminar-session-1',
                label: 'ask-user',
                text: 'Which chapter resolves the edge case?',
              ),
              AiSeminarRunCardMessagePart(
                type: 'reader_composer',
                id: 'composer-seminar-session-1',
                label: 'ask-user',
                text: 'Which chapter resolves the edge case?',
                defaultActionId: 'ask-role',
                defaultRoleId: 'critical',
                selectedActionId: 'ask-role',
                selectedRoleId: 'supportive',
                draftText: 'I want the supporter to test this question.',
                roleIds: ['critical', 'supportive'],
                actionIds: ['ask-role', 'refresh-evidence', 'synthesize'],
              ),
              AiSeminarRunCardMessagePart(
                type: 'synthesis',
                text: 'The group agrees on the mechanism but not the scope.',
                evidenceRefs: [
                  AiSeminarRunCardEvidenceSnapshot(
                    id: 'e1',
                    title: 'Chapter 2',
                    snippet: 'The source passage grounds the disagreement.',
                  ),
                ],
              ),
              AiSeminarRunCardMessagePart(
                type: 'disagreement',
                agentRunId: 'seminar-session-1:director:disagreement',
                parentRunId: 'seminar-session-1',
                text: 'Scope remains disputed.',
                roleIds: ['critical', 'supportive'],
                evidenceRefs: [
                  AiSeminarRunCardEvidenceSnapshot(
                    id: 'e1',
                    title: 'Chapter 2',
                    snippet: 'The source passage grounds the disagreement.',
                  ),
                ],
              ),
            ],
            synthesisSummary:
                'The group agrees on the mechanism but not the scope.',
            disagreements: ['Scope remains disputed.'],
            disagreementDetails: [
              AiSeminarRunCardDisagreementDetail(
                text: 'Scope remains disputed.',
                agentRunId: 'seminar-session-1:director:disagreement',
                parentRunId: 'seminar-session-1',
                roleIds: ['critical', 'supportive'],
                evidenceRefs: [
                  AiSeminarRunCardEvidenceSnapshot(
                    id: 'e1',
                    title: 'Chapter 2',
                    snippet: 'The source passage grounds the disagreement.',
                  ),
                ],
              ),
            ],
            openQuestions: ['Which chapter resolves the edge case?'],
          ),
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
      expect(restored.seminarRunCard?.snapshot?.evidence.single.title,
          'Chapter 2');
      expect(restored.seminarRunCard?.snapshot?.toolCalls.single.toolId,
          'semantic_search_current_book');
      expect(restored.seminarRunCard?.snapshot?.toolCalls.single.status,
          'running');
      expect(restored.seminarRunCard?.snapshot?.toolCalls.single.query,
          'How should I read this claim?');
      expect(
          restored.seminarRunCard?.snapshot?.toolCalls.single.resultCount, 1);
      expect(restored.seminarRunCard?.snapshot?.toolCalls.single.startedAt,
          1717516800000);
      expect(restored.seminarRunCard?.snapshot?.toolCalls.single.completedAt,
          1717516801000);
      expect(
          restored.seminarRunCard?.snapshot?.toolCalls.single.evidenceRefs
              .single.id,
          'e1');
      expect(restored.seminarRunCard?.snapshot?.toolCalls.single.roleIds,
          ['critical', 'supportive']);
      expect(restored.seminarRunCard?.snapshot?.roleSummaries.first.roleId,
          'critical');
      final messageParts =
          restored.seminarRunCard?.snapshot?.messageParts ?? const [];
      final toolPart =
          messageParts.singleWhere((part) => part.type == 'tool_call');
      expect(toolPart.id, 'tool-call-1');
      expect(toolPart.toolId, 'semantic_search_current_book');
      expect(toolPart.status, 'running');
      expect(toolPart.query, 'How should I read this claim?');
      expect(toolPart.resultCount, 1);
      expect(toolPart.startedAt, 1717516800000);
      expect(toolPart.completedAt, 1717516801000);
      expect(toolPart.roleIds, ['critical', 'supportive']);
      expect(toolPart.evidenceRefs.single.id, 'e1');
      final evidencePart =
          messageParts.singleWhere((part) => part.type == 'evidence');
      expect(evidencePart.id, 'evidence-bundle-1');
      expect(evidencePart.label, 'Evidence snapshot');
      expect(evidencePart.evidenceRefs.single.id, 'e1');
      final rolePart =
          messageParts.singleWhere((part) => part.type == 'role_turn');
      expect(rolePart.roleId, 'critical');
      expect(rolePart.text, 'This claim needs a boundary condition.');
      expect(rolePart.evidenceRefs.single.id, 'e1');
      final partialPart =
          messageParts.singleWhere((part) => part.type == 'role_partial');
      expect(partialPart.roleId, 'supportive');
      expect(partialPart.label, 'Supportive');
      expect(partialPart.text, 'Streaming support response...');
      final agentStatusPart =
          messageParts.singleWhere((part) => part.type == 'agent_status');
      expect(agentStatusPart.agentRunId, 'seminar-session-1:role-critical-0');
      expect(agentStatusPart.allowedToolIds, [
        'semantic_search_current_book',
        'notes_search',
      ]);
      final readerPart =
          messageParts.singleWhere((part) => part.type == 'reader_turn');
      expect(readerPart.id, 'user-1');
      expect(readerPart.roleId, 'critical');
      expect(readerPart.label, 'ask-role');
      expect(readerPart.text,
          'Please let the critic respond to the scope dispute.');
      final directorPart =
          messageParts.singleWhere((part) => part.type == 'director_state');
      expect(directorPart.id, 'director-seminar-session-1');
      expect(directorPart.label, 'ask-user');
      expect(directorPart.text, 'Which chapter resolves the edge case?');
      final composerPart =
          messageParts.singleWhere((part) => part.type == 'reader_composer');
      expect(composerPart.id, 'composer-seminar-session-1');
      expect(composerPart.label, 'ask-user');
      expect(composerPart.text, 'Which chapter resolves the edge case?');
      expect(composerPart.defaultActionId, 'ask-role');
      expect(composerPart.defaultRoleId, 'critical');
      expect(composerPart.selectedActionId, 'ask-role');
      expect(composerPart.selectedRoleId, 'supportive');
      expect(composerPart.draftText,
          'I want the supporter to test this question.');
      expect(composerPart.roleIds, ['critical', 'supportive']);
      expect(composerPart.actionIds,
          ['ask-role', 'refresh-evidence', 'synthesize']);
      final synthesisPart =
          messageParts.singleWhere((part) => part.type == 'synthesis');
      expect(synthesisPart.text,
          'The group agrees on the mechanism but not the scope.');
      expect(synthesisPart.evidenceRefs.single.id, 'e1');
      final disagreementPart =
          messageParts.singleWhere((part) => part.type == 'disagreement');
      expect(disagreementPart.text, 'Scope remains disputed.');
      expect(disagreementPart.agentRunId,
          'seminar-session-1:director:disagreement');
      expect(disagreementPart.parentRunId, 'seminar-session-1');
      expect(disagreementPart.roleIds, ['critical', 'supportive']);
      expect(disagreementPart.evidenceRefs.single.id, 'e1');
      expect(restored.seminarRunCard?.snapshot?.synthesisSummary,
          'The group agrees on the mechanism but not the scope.');
      expect(restored.seminarRunCard?.snapshot?.disagreements,
          ['Scope remains disputed.']);
      final restoredDisagreement =
          restored.seminarRunCard?.snapshot?.disagreementDetails.single;
      expect(restoredDisagreement?.text, 'Scope remains disputed.');
      expect(restoredDisagreement?.agentRunId,
          'seminar-session-1:director:disagreement');
      expect(restoredDisagreement?.parentRunId, 'seminar-session-1');
      expect(restoredDisagreement?.roleIds, ['critical', 'supportive']);
      expect(restoredDisagreement?.evidenceRefs.single.id, 'e1');
      expect(restoredDisagreement?.evidenceRefs.single.title, 'Chapter 2');
      expect(restored.seminarRunCard?.snapshot?.openQuestions,
          ['Which chapter resolves the edge case?']);
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

    test('seminar role summaries preserve cited evidence refs', () {
      final restored = AiSegmentMeta.fromJson(const {
        'seminarRunCard': {
          'question': 'Debate this passage.',
          'createdAt': 1234,
          'snapshot': {
            'roleSummaries': [
              {
                'roleId': 'critical',
                'label': 'Critical',
                'summary': 'This claim needs a boundary condition.',
                'evidenceRefs': [
                  {
                    'id': 'e1',
                    'title': 'Chapter 2',
                    'snippet': 'The source passage grounds the turn.',
                  },
                ],
              },
            ],
          },
        },
      });

      final encoded = restored.toJson();
      final seminarCard = encoded['seminarRunCard'] as Map;
      final snapshot = seminarCard['snapshot'] as Map;
      final roleSummaries = snapshot['roleSummaries'] as List;
      final critical = roleSummaries.single as Map;
      final evidenceRefs = critical['evidenceRefs'] as List? ?? const [];

      expect(evidenceRefs, hasLength(1));
      expect((evidenceRefs.single as Map)['id'], 'e1');
      expect(
        (evidenceRefs.single as Map)['snippet'],
        'The source passage grounds the turn.',
      );
    });

    test('seminar evidence snapshots preserve SourceRef through roundtrip', () {
      final meta = AiSeminarRunCardMeta.fromJson(const {
        'question': 'Debate this evidence.',
        'sessionId': 'seminar-source-snapshot',
        'bookId': 7,
        'status': 'ready',
        'createdAt': 1234,
        'snapshot': {
          'evidence': [
            {
              'id': 'e1',
              'title': 'Chapter 2',
              'snippet': 'The source passage.',
              'sourceRef': {
                'bookId': 7,
                'href': 'Text/ch2.xhtml',
                'cfi': 'epubcfi(/6/8)',
                'jumpLink':
                    'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
                'sourceTitle': 'Chapter 2',
                'locationLabel': 'Section 2.1',
                'sourceTextSnippet': 'The source passage.',
                'sourceKind': 'current-book-rag',
              },
            },
          ],
          'roleSummaries': [
            {
              'roleId': 'critical',
              'label': 'Critical',
              'summary': 'The claim needs a boundary.',
              'evidenceRefs': [
                {
                  'id': 'e1',
                  'title': 'Chapter 2',
                  'snippet': 'The source passage.',
                  'sourceRef': {
                    'bookId': 7,
                    'href': 'Text/ch2.xhtml',
                    'sourceTextSnippet': 'The source passage.',
                    'sourceKind': 'current-book-rag',
                  },
                },
              ],
            },
          ],
        },
      });

      final encoded = meta.toJson();
      final snapshot = encoded['snapshot'] as Map;
      final evidence = (snapshot['evidence'] as List).single as Map;
      final sourceRef = evidence['sourceRef'] as Map?;
      final roleSummaries = snapshot['roleSummaries'] as List;
      final roleEvidence =
          ((roleSummaries.single as Map)['evidenceRefs'] as List).single as Map;
      final roleSourceRef = roleEvidence['sourceRef'] as Map?;

      expect(sourceRef?['bookId'], 7);
      expect(sourceRef?['jumpLink'],
          'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29');
      expect(roleSourceRef?['href'], 'Text/ch2.xhtml');
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

    test('seminar run card clamps restored maxRounds to supported range', () {
      final restoredHigh = AiSeminarRunCardMeta.fromJson(const {
        'question': 'Debate this passage.',
        'maxRounds': 99,
      });
      final restoredLow = AiSeminarRunCardMeta.fromJson(const {
        'question': 'Debate this passage.',
        'maxRounds': 0,
      });

      expect(restoredHigh.maxRounds, 10);
      expect(restoredLow.maxRounds, 2);
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
