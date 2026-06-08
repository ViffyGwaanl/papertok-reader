import 'dart:async';
import 'dart:io';

import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/models/ai_provider_meta.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/book.dart';
import 'package:papertok_reader/models/current_reading_state.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/providers/ai_chat.dart';
import 'package:papertok_reader/providers/ai_history.dart';
import 'package:papertok_reader/providers/current_reading.dart';
import 'package:papertok_reader/service/ai/ai_history.dart';
import 'package:papertok_reader/service/ai/agent_run_graph_store.dart';
import 'package:papertok_reader/service/ai/index.dart';
import 'package:papertok_reader/service/ai/sub_agent_runner.dart';
import 'package:papertok_reader/utils/get_path/get_base_path.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    Prefs().aiTitleGenerationEnabled = false;
    _configureAiProvider();
  });

  tearDown(() {
    debugAiChatGenerateStreamOverride = null;
  });

  test('beginFreshConversation clears current ai chat session state', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);

    container.read(aiChatProvider.notifier).restore(
      [
        ChatMessage.humanText('hello'),
        ChatMessage.ai('world'),
      ],
      sessionId: 'session-1',
    );

    expect(
        container.read(aiChatProvider.notifier).currentSessionId, 'session-1');
    expect(container.read(aiChatProvider).value, isNotEmpty);

    container
        .read(aiChatProvider.notifier)
        .beginFreshConversation(container, persistCurrent: false);

    expect(container.read(aiChatProvider.notifier).currentSessionId, isNull);
    expect(container.read(aiChatProvider).value, isEmpty);
  });

  test('persistCurrentConversation tags history with current reading book',
      () async {
    final tempDir = Directory.systemTemp.createTempSync('ai-chat-provider-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);

    final book = Book.mock().copyWith(id: 7, title: 'Scoped Book');
    container.read(currentReadingProvider.notifier).start(
          CurrentReadingState(book: book),
        );

    container.read(aiChatProvider.notifier).restore(
      [
        ChatMessage.humanText('hello'),
        ChatMessage.ai('world'),
      ],
      sessionId: 'session-1',
    );

    container
        .read(aiChatProvider.notifier)
        .persistCurrentConversationWithContainer(container);

    await Future<void>.delayed(const Duration(milliseconds: 50));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));
    expect(history.single.bookId, 7);
    expect(history.single.bookTitle, 'Scoped Book');
  });

  test('persistCurrentConversation does not backfill legacy history book scope',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-legacy-provider-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);

    final book = Book.mock().copyWith(id: 7, title: 'Scoped Book');
    container.read(currentReadingProvider.notifier).start(
          CurrentReadingState(book: book),
        );

    final legacyEntry = AiChatHistoryEntry(
      id: 'legacy-session',
      serviceId: 'openai',
      model: 'gpt-test',
      createdAt: 1,
      updatedAt: 2,
      messages: [
        ChatMessage.humanText('legacy question'),
        ChatMessage.ai('legacy answer'),
      ],
      completed: true,
    );
    await container.read(aiHistoryProvider.notifier).upsert(legacyEntry);

    container.read(aiChatProvider.notifier).loadHistoryEntry(legacyEntry);
    container
        .read(aiChatProvider.notifier)
        .persistCurrentConversationWithContainer(container);

    await Future<void>.delayed(const Duration(milliseconds: 50));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));
    expect(history.single.bookId, isNull);
    expect(history.single.bookTitle, isNull);
  });

  test('appendSeminarRunCard persists a reloadable chat seminar card',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-seminar-card-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);

    final book = Book.mock().copyWith(id: 7, title: 'Scoped Book');
    container.read(currentReadingProvider.notifier).start(
          CurrentReadingState(book: book),
        );
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-card',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
        );

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));
    final entry = history.single;
    final nodes = entry.conversationV2!['nodes'] as Map;
    final seminarCards = nodes.values.where((raw) {
      if (raw is! Map) return false;
      final meta = raw['meta'];
      return meta is Map && meta['seminarRunCard'] is Map;
    }).toList();
    expect(seminarCards, hasLength(1));
    final card = (seminarCards.single as Map)['meta']['seminarRunCard'] as Map;
    expect(card['question'], '这个概念怎么理解？');
    expect(card['sessionId'], startsWith('seminar-chat-'));
    expect(card['bookId'], 7);
    expect(card['status'], 'ready');
    expect(card['roleIds'], ['critical', 'supportive', 'synthesizer']);
    expect(card['evidenceScopeIds'], ['current-book']);
    expect(card['sourceRefCount'], 0);
    expect(card['allowWeb'], false);
    expect(card['writeRequiresApproval'], true);
    expect(card['maxRounds'], 2);

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(entry);

    final restoredMessages = container.read(aiChatProvider).value!;
    expect(restoredMessages.map((message) => message.contentAsString), [
      '已有会话',
      '这个概念怎么理解？',
      contains('AI Seminar'),
    ]);
    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    expect(restoredCard?.question, '这个概念怎么理解？');
    expect(restoredCard?.sessionId, startsWith('seminar-chat-'));
    expect(restoredCard?.bookId, 7);
    expect(restoredCard?.roleIds, ['critical', 'supportive', 'synthesizer']);
  });

  test('appendSeminarRunCard persists verifier and source evidence context',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-seminar-context-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

    Prefs().aiSeminarIncludeVerifier = true;
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-card-source',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这段话有哪些争议？',
          sourceRef: SourceRef(
            bookId: 7,
            href: 'Text/chapter.xhtml',
            cfi: 'epubcfi(/6/4)',
            sourceTextSnippet: 'Evidence-backed passage.',
            sourceKind: SourceRefKind.reader,
          ),
        );

    final history = await AiHistoryStore.readHistory();
    final nodes = history.single.conversationV2!['nodes'] as Map;
    final seminarCards = nodes.values.where((raw) {
      if (raw is! Map) return false;
      final meta = raw['meta'];
      return meta is Map && meta['seminarRunCard'] is Map;
    }).toList();
    final card = (seminarCards.single as Map)['meta']['seminarRunCard'] as Map;
    expect(
      card['roleIds'],
      ['critical', 'supportive', 'verifier', 'synthesizer'],
    );
    expect(card['sourceRefCount'], 1);
    expect(card['bookId'], 7);
  });

  test('appendSeminarRunCard preserves per-run role profiles', () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-seminar-run-profiles-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-run-profiles',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
      question: '请进行多角度讨论。',
      bookId: 7,
      maxRounds: 4,
      roleProfiles: [
        AiSeminarRoleProfile(
          role: AiSeminarRole.critical,
          name: '反方审稿人',
          customPrompt: '专门寻找论证漏洞，并要求补证据。',
          evidenceScopes: const [AiSeminarEvidenceScope.currentBook],
          allowedToolIds: const ['semantic_search_current_book'],
        ),
        AiSeminarRoleProfile(
          role: AiSeminarRole.verifier,
          enabled: false,
        ),
      ],
    );

    final history = await AiHistoryStore.readHistory();
    final nodes = history.single.conversationV2!['nodes'] as Map;
    final seminarCards = nodes.values.where((raw) {
      if (raw is! Map) return false;
      final meta = raw['meta'];
      return meta is Map && meta['seminarRunCard'] is Map;
    }).toList();
    final card = (seminarCards.single as Map)['meta']['seminarRunCard'] as Map;
    final roleProfiles = card['roleProfiles'] as Map;
    expect(card['maxRounds'], 4);
    expect(roleProfiles.keys, contains('critical'));
    expect(roleProfiles.keys, contains('verifier'));
    expect(roleProfiles['critical']['name'], '反方审稿人');
    expect(
      roleProfiles['critical']['customPrompt'],
      '专门寻找论证漏洞，并要求补证据。',
    );
    expect(roleProfiles['critical']['evidenceScopes'], ['current-book']);
    expect(
      roleProfiles['critical']['allowedToolIds'],
      ['semantic_search_current_book'],
    );
    expect(roleProfiles['verifier']['enabled'], false);

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    expect(restoredCard?.maxRounds, 4);
    expect(restoredCard?.roleProfiles, hasLength(2));
    expect(
      restoredCard?.roleProfiles
          .firstWhere((profile) => profile.role == AiSeminarRole.critical)
          .customPrompt,
      '专门寻找论证漏洞，并要求补证据。',
    );
  });

  test('updateSeminarRunCardSnapshot persists structured Seminar summary',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-seminar-snapshot-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-snapshot',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-snapshot',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-snapshot',
          status: 'completed',
          sourceRefCount: 1,
          snapshot: const AiSeminarRunCardSnapshot(
            evidence: [
              AiSeminarRunCardEvidenceSnapshot(
                title: 'Working memory',
                snippet: 'Working memory evidence.',
              ),
            ],
            roleSummaries: [
              AiSeminarRunCardRoleSummary(
                roleId: 'critical',
                label: 'Critical',
                summary: 'This claim needs a boundary condition.',
              ),
            ],
            synthesisSummary:
                'The group agrees on the mechanism but not the scope.',
            disagreements: ['Scope remains disputed.'],
          ),
        );

    final history = await AiHistoryStore.readHistory();
    final nodes = history.single.conversationV2!['nodes'] as Map;
    final seminarCards = nodes.values.where((raw) {
      if (raw is! Map) return false;
      final meta = raw['meta'];
      return meta is Map && meta['seminarRunCard'] is Map;
    }).toList();
    final card = (seminarCards.single as Map)['meta']['seminarRunCard'] as Map;
    final snapshot = card['snapshot'] as Map;
    expect(card['status'], 'completed');
    expect(card['sourceRefCount'], 1);
    expect((snapshot['evidence'] as List).single['snippet'],
        'Working memory evidence.');
    expect((snapshot['roleSummaries'] as List).single['roleId'], 'critical');
    expect(snapshot['synthesisSummary'],
        'The group agrees on the mechanism but not the scope.');

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    expect(restoredCard?.status, 'completed');
    expect(restoredCard?.snapshot?.evidence.single.snippet,
        'Working memory evidence.');
  });

  test(
      'loadHistoryEntry normalizes legacy Seminar snapshot evidence into evidence block',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-legacy-evidence-block-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-legacy-evidence-block',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-legacy-evidence-block',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-legacy-evidence-block',
          status: 'completed',
          snapshot: AiSeminarRunCardSnapshot(
            evidence: [
              AiSeminarRunCardEvidenceSnapshot(
                id: 'legacy-snapshot-evidence',
                title: 'Chapter 8',
                snippet: 'Legacy snapshot evidence should be native.',
                sourceRef: SourceRef(
                  bookId: 7,
                  cfi: 'epubcfi(/6/16)',
                  sourceKind: SourceRefKind.currentBookRag,
                  sourceTextSnippet:
                      'Legacy snapshot evidence should be native.',
                ),
              ),
            ],
          ),
        );

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final evidenceParts = restoredCard?.snapshot?.messageParts
        .where((part) => part.type == 'evidence')
        .toList(growable: false);

    expect(evidenceParts, hasLength(1));
    expect(evidenceParts?.single.id,
        'seminar-chat-legacy-evidence-block:evidence:legacy');
    expect(evidenceParts?.single.parentRunId,
        'seminar-chat-legacy-evidence-block');
    expect(evidenceParts?.single.evidenceRefs.single.id,
        'legacy-snapshot-evidence');
    expect(evidenceParts?.single.evidenceRefs.single.sourceRef?.bookId, 7);
  });

  test(
      'loadHistoryEntry normalizes legacy Seminar snapshot tool calls into tool call parts',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-legacy-tool-block-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-legacy-tool-block',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-legacy-tool-block',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-legacy-tool-block',
          status: 'completed',
          snapshot: AiSeminarRunCardSnapshot(
            toolCalls: [
              AiSeminarRunCardToolCallSnapshot(
                id: 'legacy-tool-call-current-book',
                agentRunId: 'seminar-chat-legacy-tool-block:tool:current-book',
                parentRunId: 'seminar-chat-legacy-tool-block',
                toolId: 'semantic_search_current_book',
                status: 'completed',
                label: 'Current book search',
                text: 'Returned 2 traceable evidence chunks.',
                query: 'agency trace',
                resultCount: 2,
                roleIds: const ['critical', 'supportive'],
                evidenceRefs: [
                  AiSeminarRunCardEvidenceSnapshot(
                    id: 'legacy-tool-evidence',
                    title: 'Chapter 9',
                    snippet: 'Legacy tool call evidence should be native.',
                    sourceRef: SourceRef(
                      bookId: 7,
                      cfi: 'epubcfi(/6/18)',
                      sourceKind: SourceRefKind.currentBookRag,
                      sourceTextSnippet:
                          'Legacy tool call evidence should be native.',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final toolCallParts = restoredCard?.snapshot?.messageParts
        .where((part) => part.type == 'tool_call')
        .toList(growable: false);

    expect(toolCallParts, hasLength(1));
    expect(toolCallParts?.single.id, 'legacy-tool-call-current-book');
    expect(toolCallParts?.single.agentRunId,
        'seminar-chat-legacy-tool-block:tool:current-book');
    expect(toolCallParts?.single.parentRunId, 'seminar-chat-legacy-tool-block');
    expect(toolCallParts?.single.toolId, 'semantic_search_current_book');
    expect(toolCallParts?.single.status, 'completed');
    expect(toolCallParts?.single.query, 'agency trace');
    expect(toolCallParts?.single.resultCount, 2);
    expect(toolCallParts?.single.roleIds, ['critical', 'supportive']);
    expect(
        toolCallParts?.single.evidenceRefs.single.id, 'legacy-tool-evidence');
  });

  test(
      'loadHistoryEntry normalizes legacy Seminar role summaries into role turn parts',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-legacy-role-block-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-legacy-role-block',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-legacy-role-block',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-legacy-role-block',
          status: 'completed',
          snapshot: AiSeminarRunCardSnapshot(
            roleSummaries: [
              AiSeminarRunCardRoleSummary(
                roleId: 'critical',
                label: 'Critical reader',
                summary: 'Legacy role response should be native.',
                evidenceRefs: [
                  AiSeminarRunCardEvidenceSnapshot(
                    id: 'legacy-role-evidence',
                    title: 'Chapter 10',
                    snippet: 'Legacy role evidence should stay linked.',
                    sourceRef: SourceRef(
                      bookId: 7,
                      cfi: 'epubcfi(/6/20)',
                      sourceKind: SourceRefKind.currentBookRag,
                      sourceTextSnippet:
                          'Legacy role evidence should stay linked.',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final roleTurnParts = restoredCard?.snapshot?.messageParts
        .where((part) => part.type == 'role_turn')
        .toList(growable: false);

    expect(roleTurnParts, hasLength(1));
    expect(roleTurnParts?.single.id,
        'seminar-chat-legacy-role-block:role-turn:critical:legacy');
    expect(roleTurnParts?.single.parentRunId, 'seminar-chat-legacy-role-block');
    expect(roleTurnParts?.single.roleId, 'critical');
    expect(roleTurnParts?.single.label, 'Critical reader');
    expect(
        roleTurnParts?.single.text, 'Legacy role response should be native.');
    expect(
        roleTurnParts?.single.evidenceRefs.single.id, 'legacy-role-evidence');
    expect(roleTurnParts?.single.evidenceRefs.single.sourceRef?.bookId, 7);
  });

  test(
      'loadHistoryEntry normalizes legacy Seminar synthesis summary into synthesis part',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-legacy-synthesis-block-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-legacy-synthesis-block',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-legacy-synthesis-block',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-legacy-synthesis-block',
          status: 'completed',
          snapshot: const AiSeminarRunCardSnapshot(
            synthesisSummary: 'Legacy synthesis should be native.',
          ),
        );

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final synthesisParts = restoredCard?.snapshot?.messageParts
        .where((part) => part.type == 'synthesis')
        .toList(growable: false);

    expect(synthesisParts, hasLength(1));
    expect(synthesisParts?.single.id,
        'seminar-chat-legacy-synthesis-block:synthesis:legacy');
    expect(synthesisParts?.single.parentRunId,
        'seminar-chat-legacy-synthesis-block');
    expect(synthesisParts?.single.text, 'Legacy synthesis should be native.');
  });

  test(
      'loadHistoryEntry normalizes legacy Seminar disagreement details into disagreement parts',
      () async {
    final tempDir = Directory.systemTemp
        .createTempSync('ai-chat-legacy-disagreement-block-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-legacy-disagreement-block',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-legacy-disagreement-block',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-legacy-disagreement-block',
          status: 'completed',
          snapshot: AiSeminarRunCardSnapshot(
            disagreementDetails: [
              AiSeminarRunCardDisagreementDetail(
                text: 'Legacy disagreement should be native.',
                roleIds: const ['critical', 'supportive'],
                evidenceRefs: [
                  AiSeminarRunCardEvidenceSnapshot(
                    id: 'legacy-disagreement-evidence',
                    title: 'Chapter 11',
                    snippet: 'Legacy disagreement evidence should stay linked.',
                    sourceRef: SourceRef(
                      bookId: 7,
                      cfi: 'epubcfi(/6/22)',
                      sourceKind: SourceRefKind.currentBookRag,
                      sourceTextSnippet:
                          'Legacy disagreement evidence should stay linked.',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final disagreementParts = restoredCard?.snapshot?.messageParts
        .where((part) => part.type == 'disagreement')
        .toList(growable: false);

    expect(disagreementParts, hasLength(1));
    expect(disagreementParts?.single.id,
        'seminar-chat-legacy-disagreement-block:disagreement:0:legacy');
    expect(disagreementParts?.single.parentRunId,
        'seminar-chat-legacy-disagreement-block');
    expect(disagreementParts?.single.text,
        'Legacy disagreement should be native.');
    expect(disagreementParts?.single.roleIds, ['critical', 'supportive']);
    expect(disagreementParts?.single.evidenceRefs.single.id,
        'legacy-disagreement-evidence');
    expect(disagreementParts?.single.evidenceRefs.single.sourceRef?.bookId, 7);
  });

  test(
      'loadHistoryEntry normalizes legacy Seminar disagreements into disagreement parts',
      () async {
    final tempDir = Directory.systemTemp
        .createTempSync('ai-chat-legacy-bare-disagreement-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-legacy-bare-disagreement',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-legacy-bare-disagreement',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-legacy-bare-disagreement',
          status: 'completed',
          snapshot: const AiSeminarRunCardSnapshot(
            disagreements: [
              'Legacy bare disagreement should be native.',
              ' Legacy bare disagreement should be native. ',
            ],
          ),
        );

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final disagreementParts = restoredCard?.snapshot?.messageParts
        .where((part) => part.type == 'disagreement')
        .toList(growable: false);

    expect(disagreementParts, hasLength(1));
    expect(disagreementParts?.single.id,
        'seminar-chat-legacy-bare-disagreement:disagreement:0:legacy-bare');
    expect(disagreementParts?.single.parentRunId,
        'seminar-chat-legacy-bare-disagreement');
    expect(disagreementParts?.single.label, 'legacy-untraced');
    expect(disagreementParts?.single.text,
        'Legacy bare disagreement should be native.');
    expect(disagreementParts?.single.roleIds, isEmpty);
    expect(disagreementParts?.single.evidenceRefs, isEmpty);
  });

  test(
      'loadHistoryEntry normalizes legacy Seminar open questions into director state and reader composer parts',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-legacy-open-question-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-legacy-open-question',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-legacy-open-question',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-legacy-open-question',
          status: 'completed',
          snapshot: const AiSeminarRunCardSnapshot(
            openQuestions: ['Which chapter resolves the edge case?'],
          ),
        );

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final directorParts = restoredCard?.snapshot?.messageParts
        .where((part) => part.type == 'director_state')
        .toList(growable: false);

    expect(directorParts, hasLength(1));
    expect(directorParts?.single.id,
        'seminar-chat-legacy-open-question:open-question:0:legacy');
    expect(
        directorParts?.single.parentRunId, 'seminar-chat-legacy-open-question');
    expect(directorParts?.single.roleId, 'director');
    expect(directorParts?.single.label, 'ask-user');
    expect(directorParts?.single.text, 'Which chapter resolves the edge case?');
    final composerParts = restoredCard?.snapshot?.messageParts
        .where((part) => part.type == 'reader_composer')
        .toList(growable: false);

    expect(composerParts, hasLength(1));
    expect(
        composerParts?.single.id, 'composer-seminar-chat-legacy-open-question');
    expect(
        composerParts?.single.parentRunId, 'seminar-chat-legacy-open-question');
    expect(composerParts?.single.label, 'ask-user');
    expect(composerParts?.single.text, 'Which chapter resolves the edge case?');
    expect(composerParts?.single.defaultActionId, 'ask-role');
    expect(composerParts?.single.defaultRoleId, 'critical');
    expect(composerParts?.single.selectedActionId, 'ask-role');
    expect(composerParts?.single.selectedRoleId, 'critical');
    expect(composerParts?.single.actionIds,
        ['ask-role', 'refresh-evidence', 'synthesize']);
    expect(composerParts?.single.roleIds, ['critical', 'supportive']);
  });

  test(
      'loadHistoryEntry keeps existing reader composer when legacy Seminar open questions are stale',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-stale-open-question-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-stale-open-question',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-stale-open-question',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-stale-open-question',
          status: 'completed',
          snapshot: const AiSeminarRunCardSnapshot(
            openQuestions: ['Legacy stale question should not duplicate.'],
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'reader_composer',
                id: 'composer-runtime-stale-open-question',
                parentRunId: 'seminar-chat-stale-open-question',
                label: 'ask-user',
                text: 'Runtime composer question should stay.',
                roleIds: ['critical', 'supportive'],
                actionIds: ['ask-role', 'refresh-evidence', 'synthesize'],
                defaultRoleId: 'critical',
                defaultActionId: 'ask-role',
                selectedRoleId: 'supportive',
                selectedActionId: 'refresh-evidence',
                draftText: 'Keep this draft reply.',
              ),
            ],
          ),
        );

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final composerParts = restoredCard?.snapshot?.messageParts
        .where((part) => part.type == 'reader_composer')
        .toList(growable: false);

    expect(composerParts, hasLength(1));
    expect(composerParts?.single.id, 'composer-runtime-stale-open-question');
    expect(
        composerParts?.single.parentRunId, 'seminar-chat-stale-open-question');
    expect(
        composerParts?.single.text, 'Runtime composer question should stay.');
    expect(composerParts?.single.selectedRoleId, 'supportive');
    expect(composerParts?.single.selectedActionId, 'refresh-evidence');
    expect(composerParts?.single.draftText, 'Keep this draft reply.');
  });

  test('updateSeminarRunCardSnapshot clears handled reader composer', () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-clear-reader-composer-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-clear-reader-composer',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-clear-reader-composer',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-clear-reader-composer',
          status: 'completed',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'reader_composer',
                id: 'composer-seminar-chat-clear-reader-composer',
                parentRunId: 'seminar-chat-clear-reader-composer',
                label: 'ask-user',
                text: 'Which interpretation should the reader test next?',
                roleIds: ['critical', 'supportive'],
                actionIds: ['ask-role', 'refresh-evidence', 'synthesize'],
                defaultRoleId: 'critical',
                defaultActionId: 'ask-role',
                selectedRoleId: 'supportive',
                selectedActionId: 'ask-role',
                draftText: '请支持者回应这个开放问题。',
              ),
            ],
          ),
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-clear-reader-composer',
          status: 'completed',
          snapshot: const AiSeminarRunCardSnapshot(
            openQuestions: [
              'Which interpretation should the reader test next?'
            ],
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'reader_turn',
                id: 'reader-turn-clear-reader-composer',
                parentRunId: 'seminar-chat-clear-reader-composer',
                roleId: 'supportive',
                label: 'ask-role',
                text: '请支持者回应这个开放问题。',
                status: 'completed',
              ),
              AiSeminarRunCardMessagePart(
                type: 'role_turn',
                id: 'turn-supportive-follow-up',
                parentRunId: 'seminar-chat-clear-reader-composer',
                roleId: 'supportive',
                text: 'supportive follow-up response',
              ),
            ],
          ),
        );

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final parts = restoredCard?.snapshot?.messageParts ?? const [];
    expect(
      parts.where((part) => part.type == 'reader_composer'),
      isEmpty,
    );
    expect(
      parts.where(
        (part) => part.type == 'director_state' && part.label == 'ask-user',
      ),
      isEmpty,
    );
    final readerPart = parts.singleWhere(
      (part) => part.type == 'reader_turn' && part.label == 'ask-role',
    );
    expect(readerPart.text, '请支持者回应这个开放问题。');
    expect(readerPart.roleId, 'supportive');
  });

  test('updateSeminarRunCardSnapshot preserves sent review artifact action',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-seminar-artifact-action-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-artifact-action',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-artifact-action',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-artifact-action',
          status: 'completed',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'artifact_actions',
                id: 'artifact-actions-seminar-chat-artifact-action',
                agentRunId: 'seminar-chat-artifact-action',
                label: 'available',
                text: '异常已送审',
                actionIds: ['sent-to-review', 'ignore-artifact-actions'],
              ),
            ],
          ),
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-artifact-action',
          status: 'completed',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'artifact_actions',
                id: 'artifact-actions-seminar-chat-artifact-action',
                agentRunId: 'seminar-chat-artifact-action',
                label: 'available',
                text: '异常内容可送审处理。',
                actionIds: ['send-to-review', 'ignore-artifact-actions'],
              ),
            ],
          ),
        );

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final artifactPart = restoredCard?.snapshot?.messageParts.singleWhere(
      (part) => part.type == 'artifact_actions',
    );
    expect(artifactPart?.actionIds, contains('sent-to-review'));
    expect(artifactPart?.actionIds, isNot(contains('send-to-review')));
    expect(artifactPart?.text, contains('异常已送审'));
  });

  test('updateSeminarRunCardSnapshot records terminal artifact action events',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-artifact-action-events-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-artifact-action-events',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-artifact-action-events',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-artifact-action-events',
          status: 'completed',
          snapshot: AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'artifact_actions',
                id: 'artifact-actions-seminar-chat-artifact-action-events',
                agentRunId: 'seminar-chat-artifact-action-events',
                label: 'available',
                text: '知识卡已保存；复习已加入；图谱已加入。',
                actionIds: const [
                  'knowledge-card-saved',
                  'undo-knowledge-card',
                  'spaced-review-added',
                  'undo-spaced-review',
                  'concept-graph-added',
                  'undo-concept-graph',
                ],
                evidenceRefs: [
                  AiSeminarRunCardEvidenceSnapshot(
                    id: 'e1',
                    title: 'Chapter 2',
                    snippet: 'Working memory evidence.',
                    sourceRef: SourceRef(
                      bookId: 7,
                      cfi: 'epubcfi(/6/2)',
                      sourceKind: SourceRefKind.currentBookRag,
                      sourceTextSnippet: 'Working memory evidence.',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

    final events = await AgentRunGraphStore()
        .listEvents('seminar-chat-artifact-action-events');
    final artifactEvents = events
        .where((event) => event.type == AgentRunEventType.artifactAction)
        .toList(growable: false);

    expect(
      artifactEvents.map((event) => event.actionIds.single).toSet(),
      {
        'knowledge-card-saved',
        'spaced-review-added',
        'concept-graph-added',
      },
    );
    expect(
      artifactEvents.map((event) => event.status).toSet(),
      {SubAgentRunStatus.completed},
    );
    expect(
      artifactEvents.every(
        (event) => event.evidenceRefs.single.sourceRef?.bookId == 7,
      ),
      true,
    );
  });

  test(
      'loadHistoryEntry replays Seminar agent events into native message parts',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-seminar-graph-replay-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-graph-replay',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-graph-replay',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-graph-replay',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: 'seminar-chat-graph-replay:role-critical-0:delta:0',
      runId: 'seminar-chat-graph-replay:role-critical-0',
      parentRunId: 'seminar-chat-graph-replay',
      type: AgentRunEventType.messageDelta,
      createdAt: DateTime.utc(2026, 6, 4, 16),
      roleId: 'critical',
      nickname: 'Critical',
      delta: 'Recovered from persisted graph event.',
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final partial = restoredCard?.snapshot?.messageParts.singleWhere(
      (part) => part.type == 'role_partial',
    );
    expect(partial?.id, 'seminar-chat-graph-replay:role-critical-0:delta:0');
    expect(partial?.roleId, 'critical');
    expect(partial?.text, 'Recovered from persisted graph event.');
  });

  test('loadHistoryEntry replays Seminar artifact action events', () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-artifact-action-replay-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-artifact-action-replay',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-artifact-action-replay',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-artifact-action-replay',
          status: 'completed',
          snapshot: const AiSeminarRunCardSnapshot(),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId:
          'seminar-chat-artifact-action-replay:artifact-action:sent-to-review',
      runId: 'seminar-chat-artifact-action-replay',
      type: AgentRunEventType.artifactAction,
      createdAt: DateTime.utc(2026, 6, 4, 23),
      status: SubAgentRunStatus.completed,
      roleId: 'director',
      nickname: 'Director',
      actionIds: const ['sent-to-review'],
      result: 'Exception sent to Review Inbox.',
      evidenceRefs: [
        AiSeminarRunCardEvidenceSnapshot(
          id: 'e1',
          title: 'Chapter 2',
          snippet: 'Working memory evidence.',
          sourceRef: SourceRef(
            bookId: 7,
            cfi: 'epubcfi(/6/2)',
            sourceKind: SourceRefKind.currentBookRag,
            sourceTextSnippet: 'Working memory evidence.',
          ),
        ),
      ],
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final artifactPart = restoredCard?.snapshot?.messageParts.singleWhere(
      (part) => part.type == 'artifact_actions',
    );
    expect(artifactPart?.id,
        'seminar-chat-artifact-action-replay:artifact-action:sent-to-review');
    expect(artifactPart?.agentRunId, 'seminar-chat-artifact-action-replay');
    expect(artifactPart?.status, 'completed');
    expect(artifactPart?.actionIds, ['sent-to-review']);
    expect(artifactPart?.text, 'Exception sent to Review Inbox.');
    expect(artifactPart?.evidenceRefs.single.sourceRef?.bookId, 7);
  });

  test('loadHistoryEntry replaces stale Seminar artifact actions from graph',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-artifact-action-replace-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-artifact-action-replace',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-artifact-action-replace',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-artifact-action-replace',
          status: 'completed',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'artifact_actions',
                id: 'artifact-actions-seminar-chat-artifact-action-replace',
                agentRunId: 'seminar-chat-artifact-action-replace',
                label: 'available',
                text: '可以保存为知识卡。',
                actionIds: ['save-knowledge-card', 'edit-knowledge-card'],
              ),
            ],
          ),
        );

    await AgentRunGraphStore().upsertEvent(AgentRunEvent(
      eventId:
          'seminar-chat-artifact-action-replace:artifact-action:knowledge-card-saved',
      runId: 'seminar-chat-artifact-action-replace',
      type: AgentRunEventType.artifactAction,
      createdAt: DateTime.utc(2026, 6, 5, 0, 1),
      status: SubAgentRunStatus.completed,
      roleId: 'director',
      nickname: 'Director',
      actionIds: const ['knowledge-card-saved'],
      result: 'KnowledgeCard saved.',
      evidenceRefs: _traceableSeminarArtifactEvidenceRefs(),
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final artifactParts = restoredCard?.snapshot?.messageParts
            .where((part) => part.type == 'artifact_actions')
            .toList(growable: false) ??
        const <AiSeminarRunCardMessagePart>[];

    expect(artifactParts, hasLength(1));
    expect(
      artifactParts.single.actionIds,
      containsAll({'knowledge-card-saved', 'undo-knowledge-card'}),
    );
    expect(
      artifactParts.single.actionIds,
      isNot(contains('save-knowledge-card')),
    );
    expect(artifactParts.single.text, 'KnowledgeCard saved.');
  });

  test(
      'loadHistoryEntry replaces stale Seminar saved artifact actions after undo replay',
      () async {
    final tempDir = Directory.systemTemp
        .createTempSync('ai-chat-artifact-action-undo-replay-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-artifact-action-undo-replay',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-artifact-action-undo-replay',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-artifact-action-undo-replay',
          status: 'completed',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'artifact_actions',
                id: 'artifact-actions-seminar-chat-artifact-action-undo-replay',
                agentRunId: 'seminar-chat-artifact-action-undo-replay',
                label: 'available',
                text: '知识卡已保存。',
                actionIds: [
                  'knowledge-card-saved',
                  'undo-knowledge-card',
                  'spaced-review-added',
                  'undo-spaced-review',
                  'concept-graph-added',
                  'undo-concept-graph',
                ],
              ),
            ],
          ),
        );

    final undoCreatedAt = DateTime.now().add(const Duration(minutes: 1));
    await AgentRunGraphStore().upsertEvent(AgentRunEvent(
      eventId:
          'seminar-chat-artifact-action-undo-replay:artifact-action:undo-knowledge-card',
      runId: 'seminar-chat-artifact-action-undo-replay',
      type: AgentRunEventType.artifactAction,
      createdAt: undoCreatedAt,
      status: SubAgentRunStatus.completed,
      roleId: 'director',
      nickname: 'Director',
      actionIds: const [
        'undo-knowledge-card',
        'save-knowledge-card',
        'edit-knowledge-card',
      ],
      result: 'KnowledgeCard save undone.',
      evidenceRefs: _traceableSeminarArtifactEvidenceRefs(),
    ));
    await AgentRunGraphStore().upsertEvent(AgentRunEvent(
      eventId:
          'seminar-chat-artifact-action-undo-replay:artifact-action:undo-spaced-review',
      runId: 'seminar-chat-artifact-action-undo-replay',
      type: AgentRunEventType.artifactAction,
      createdAt: undoCreatedAt.add(const Duration(seconds: 1)),
      status: SubAgentRunStatus.completed,
      roleId: 'director',
      nickname: 'Director',
      actionIds: const ['undo-spaced-review', 'add-spaced-review'],
      result: 'Spaced review undone.',
      evidenceRefs: _traceableSeminarArtifactEvidenceRefs(),
    ));
    await AgentRunGraphStore().upsertEvent(AgentRunEvent(
      eventId:
          'seminar-chat-artifact-action-undo-replay:artifact-action:undo-concept-graph',
      runId: 'seminar-chat-artifact-action-undo-replay',
      type: AgentRunEventType.artifactAction,
      createdAt: undoCreatedAt.add(const Duration(seconds: 2)),
      status: SubAgentRunStatus.completed,
      roleId: 'director',
      nickname: 'Director',
      actionIds: const ['undo-concept-graph', 'add-concept-graph'],
      result: 'Concept graph save undone.',
      evidenceRefs: _traceableSeminarArtifactEvidenceRefs(),
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final artifactParts = restoredCard?.snapshot?.messageParts
            .where((part) => part.type == 'artifact_actions')
            .toList(growable: false) ??
        const <AiSeminarRunCardMessagePart>[];

    expect(artifactParts, hasLength(1));
    expect(
      artifactParts.single.actionIds,
      containsAll({'save-knowledge-card', 'edit-knowledge-card'}),
    );
    expect(
      artifactParts.single.actionIds,
      containsAll({'add-spaced-review', 'add-concept-graph'}),
    );
    expect(
      artifactParts.single.actionIds,
      isNot(contains('knowledge-card-saved')),
    );
    expect(
      artifactParts.single.actionIds,
      isNot(contains('undo-knowledge-card')),
    );
    expect(
      artifactParts.single.actionIds,
      isNot(contains('spaced-review-added')),
    );
    expect(
      artifactParts.single.actionIds,
      isNot(contains('undo-spaced-review')),
    );
    expect(
      artifactParts.single.actionIds,
      isNot(contains('concept-graph-added')),
    );
    expect(
      artifactParts.single.actionIds,
      isNot(contains('undo-concept-graph')),
    );
    expect(artifactParts.single.text, 'Concept graph save undone.');
  });

  test(
      'loadHistoryEntry replaces ignored Seminar artifact actions after restore replay',
      () async {
    final tempDir = Directory.systemTemp
        .createTempSync('ai-chat-artifact-action-restore-replay-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-artifact-action-restore-replay',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-artifact-action-restore-replay',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-artifact-action-restore-replay',
          status: 'completed',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'artifact_actions',
                id: 'artifact-actions-seminar-chat-artifact-action-restore-replay',
                agentRunId: 'seminar-chat-artifact-action-restore-replay',
                label: 'ignored',
                text: '沉淀建议已忽略。',
                actionIds: [
                  'artifact-actions-ignored',
                  'restore-artifact-actions',
                ],
              ),
            ],
          ),
        );

    await AgentRunGraphStore().upsertEvent(AgentRunEvent(
      eventId:
          'seminar-chat-artifact-action-restore-replay:artifact-action:restore-artifact-actions',
      runId: 'seminar-chat-artifact-action-restore-replay',
      type: AgentRunEventType.artifactAction,
      createdAt: DateTime.now().add(const Duration(minutes: 1)),
      status: SubAgentRunStatus.completed,
      roleId: 'director',
      nickname: 'Director',
      actionIds: const [
        'restore-artifact-actions',
        'save-knowledge-card',
        'edit-knowledge-card',
        'add-spaced-review',
        'add-concept-graph',
        'ignore-artifact-actions',
      ],
      result: 'Artifact suggestions restored.',
      evidenceRefs: _traceableSeminarArtifactEvidenceRefs(),
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final artifactParts = restoredCard?.snapshot?.messageParts
            .where((part) => part.type == 'artifact_actions')
            .toList(growable: false) ??
        const <AiSeminarRunCardMessagePart>[];

    expect(artifactParts, hasLength(1));
    expect(
      artifactParts.single.actionIds,
      containsAll({
        'save-knowledge-card',
        'edit-knowledge-card',
        'add-spaced-review',
        'add-concept-graph',
        'ignore-artifact-actions',
      }),
    );
    expect(
      artifactParts.single.actionIds,
      isNot(contains('artifact-actions-ignored')),
    );
    expect(
      artifactParts.single.actionIds,
      isNot(contains('restore-artifact-actions')),
    );
    expect(artifactParts.single.text, 'Artifact suggestions restored.');
  });

  test(
      'loadHistoryEntry replaces stale Seminar tool call parts from graph replay',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-tool-replay-replace-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-tool-replay-replace',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-tool-replay-replace',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-tool-replay-replace',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'tool_call',
                id: 'seminar-chat-tool-replay-replace:tool:current-book',
                agentRunId:
                    'seminar-chat-tool-replay-replace:tool:current-book',
                parentRunId: 'seminar-chat-tool-replay-replace',
                toolId: 'semantic_search_current_book',
                status: 'running',
                query: '这个概念怎么理解？',
                roleIds: ['critical', 'supportive', 'synthesizer'],
              ),
            ],
          ),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: 'seminar-chat-tool-replay-replace:tool:current-book',
      runId: 'seminar-chat-tool-replay-replace:tool:current-book',
      parentRunId: 'seminar-chat-tool-replay-replace',
      type: AgentRunEventType.toolCall,
      createdAt: DateTime.utc(2026, 6, 4, 21),
      status: SubAgentRunStatus.errored,
      toolId: 'semantic_search_current_book',
      query: '这个概念怎么理解？',
      roleIds: const ['critical', 'supportive', 'synthesizer'],
      error: 'index unavailable',
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final toolCall = restoredCard?.snapshot?.messageParts.singleWhere(
      (part) => part.type == 'tool_call',
    );

    expect(toolCall?.status, 'errored');
    expect(toolCall?.text, contains('index unavailable'));
  });

  test('updateSeminarRunCardSnapshot keeps tool call start time after terminal',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-tool-started-at-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-tool-started-at',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-tool-started-at',
        );

    const startedAt = 1717516800000;
    const interruptedAt = 1717516803000;
    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-tool-started-at',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'tool_call',
                id: 'seminar-chat-tool-started-at:tool:concept-graph:running',
                agentRunId: 'seminar-chat-tool-started-at:role-critical-0',
                parentRunId: 'seminar-chat-tool-started-at',
                toolId: 'concept_graph_search',
                status: 'running',
                query: 'agency map',
                startedAt: startedAt,
                roleIds: ['critical'],
              ),
            ],
          ),
        );
    final runningCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final runningToolCall = runningCard?.snapshot?.messageParts.singleWhere(
      (part) => part.type == 'tool_call',
    );
    expect(runningToolCall?.startedAt, startedAt);

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-tool-started-at',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'tool_call',
                id: 'seminar-chat-tool-started-at:tool:concept-graph:interrupted',
                agentRunId: 'seminar-chat-tool-started-at:role-critical-0',
                parentRunId: 'seminar-chat-tool-started-at',
                toolId: 'concept_graph_search',
                status: 'interrupted',
                query: 'agency map',
                text: 'tool call was interrupted',
                completedAt: interruptedAt,
                roleIds: ['critical'],
              ),
            ],
          ),
        );

    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final toolCalls = card?.snapshot?.messageParts
        .where((part) => part.type == 'tool_call')
        .toList(growable: false);

    expect(toolCalls, hasLength(1));
    expect(toolCalls?.single.status, 'interrupted');
    expect(toolCalls?.single.startedAt, startedAt);
    expect(toolCalls?.single.completedAt, interruptedAt);
  });

  test('updateSeminarRunCardSnapshot keeps tool call roles after terminal',
      () async {
    final tempDir = Directory.systemTemp.createTempSync('ai-chat-tool-roles-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-tool-roles',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-tool-roles',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-tool-roles',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'tool_call',
                id: 'seminar-chat-tool-roles:tool:memory:running',
                agentRunId: 'seminar-chat-tool-roles:role-critical-0',
                parentRunId: 'seminar-chat-tool-roles',
                toolId: 'memory_search',
                status: 'running',
                query: 'agency memory',
                startedAt: 1717516820000,
                roleIds: ['critical', 'supportive'],
              ),
            ],
          ),
        );
    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-tool-roles',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'tool_call',
                id: 'seminar-chat-tool-roles:tool:memory:completed',
                agentRunId: 'seminar-chat-tool-roles:role-critical-0',
                parentRunId: 'seminar-chat-tool-roles',
                toolId: 'memory_search',
                status: 'completed',
                text: 'Returned 2 traceable memory notes.',
                query: 'agency memory',
                resultCount: 2,
                completedAt: 1717516823000,
              ),
            ],
          ),
        );

    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final toolCalls = card?.snapshot?.messageParts
        .where((part) => part.type == 'tool_call')
        .toList(growable: false);

    expect(toolCalls, hasLength(1));
    expect(toolCalls?.single.status, 'completed');
    expect(toolCalls?.single.roleIds, ['critical', 'supportive']);
  });

  test('updateSeminarRunCardSnapshot keeps tool call evidence after terminal',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-tool-evidence-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-tool-evidence',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-tool-evidence',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-tool-evidence',
          status: 'running',
          snapshot: AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'tool_call',
                id: 'seminar-chat-tool-evidence:tool:book:running',
                agentRunId: 'seminar-chat-tool-evidence:role-critical-0',
                parentRunId: 'seminar-chat-tool-evidence',
                toolId: 'semantic_search_current_book',
                status: 'running',
                query: 'agency evidence',
                startedAt: 1717516840000,
                evidenceRefs: [
                  AiSeminarRunCardEvidenceSnapshot(
                    id: 'evidence-keep',
                    title: 'Chapter 3',
                    snippet: 'Traceable evidence should stay.',
                    sourceRef: SourceRef(
                      bookId: 7,
                      cfi: 'epubcfi(/6/4)',
                      sourceKind: SourceRefKind.currentBookRag,
                      sourceTextSnippet: 'Traceable evidence should stay.',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-tool-evidence',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'tool_call',
                id: 'seminar-chat-tool-evidence:tool:book:completed',
                agentRunId: 'seminar-chat-tool-evidence:role-critical-0',
                parentRunId: 'seminar-chat-tool-evidence',
                toolId: 'semantic_search_current_book',
                status: 'completed',
                text: 'Returned 1 traceable evidence chunk.',
                query: 'agency evidence',
                resultCount: 1,
                completedAt: 1717516843000,
              ),
            ],
          ),
        );

    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final toolCalls = card?.snapshot?.messageParts
        .where((part) => part.type == 'tool_call')
        .toList(growable: false);

    expect(toolCalls, hasLength(1));
    expect(toolCalls?.single.status, 'completed');
    expect(toolCalls?.single.evidenceRefs, hasLength(1));
    expect(toolCalls?.single.evidenceRefs.single.id, 'evidence-keep');
  });

  test('updateSeminarRunCardSnapshot keeps tool call query after terminal',
      () async {
    final tempDir = Directory.systemTemp.createTempSync('ai-chat-tool-query-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-tool-query',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-tool-query',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-tool-query',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'tool_call',
                id: 'seminar-chat-tool-query:tool:memory',
                agentRunId: 'seminar-chat-tool-query:role-critical-0',
                parentRunId: 'seminar-chat-tool-query',
                toolId: 'memory_search',
                status: 'running',
                query: 'agency query should stay',
                startedAt: 1717516860000,
              ),
            ],
          ),
        );
    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-tool-query',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'tool_call',
                id: 'seminar-chat-tool-query:tool:memory',
                agentRunId: 'seminar-chat-tool-query:role-critical-0',
                parentRunId: 'seminar-chat-tool-query',
                toolId: 'memory_search',
                status: 'completed',
                text: 'Returned 2 traceable memory notes.',
                resultCount: 2,
                completedAt: 1717516863000,
              ),
            ],
          ),
        );

    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final toolCalls = card?.snapshot?.messageParts
        .where((part) => part.type == 'tool_call')
        .toList(growable: false);

    expect(toolCalls, hasLength(1));
    expect(toolCalls?.single.status, 'completed');
    expect(toolCalls?.single.query, 'agency query should stay');
  });

  test(
      'updateSeminarRunCardSnapshot keeps snapshot tool call start time after terminal',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-legacy-tool-started-at-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-legacy-tool-started-at',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-legacy-tool-started-at',
        );

    const startedAt = 1717516810000;
    const interruptedAt = 1717516813000;
    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-legacy-tool-started-at',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            toolCalls: [
              AiSeminarRunCardToolCallSnapshot(
                id: 'seminar-chat-legacy-tool-started-at:tool:memory:running',
                agentRunId:
                    'seminar-chat-legacy-tool-started-at:role-critical-0',
                parentRunId: 'seminar-chat-legacy-tool-started-at',
                toolId: 'memory_search',
                status: 'running',
                query: 'agency memory',
                resultCount: 0,
                startedAt: startedAt,
                roleIds: ['critical'],
              ),
            ],
          ),
        );
    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-legacy-tool-started-at',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            toolCalls: [
              AiSeminarRunCardToolCallSnapshot(
                id: 'seminar-chat-legacy-tool-started-at:tool:memory:interrupted',
                agentRunId:
                    'seminar-chat-legacy-tool-started-at:role-critical-0',
                parentRunId: 'seminar-chat-legacy-tool-started-at',
                toolId: 'memory_search',
                status: 'interrupted',
                text: 'tool call was interrupted',
                query: 'agency memory',
                resultCount: 0,
                completedAt: interruptedAt,
                roleIds: ['critical'],
              ),
            ],
          ),
        );

    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final toolCalls = card?.snapshot?.toolCalls;

    expect(toolCalls, hasLength(1));
    expect(toolCalls?.single.status, 'interrupted');
    expect(toolCalls?.single.startedAt, startedAt);
    expect(toolCalls?.single.completedAt, interruptedAt);
  });

  test(
      'updateSeminarRunCardSnapshot keeps snapshot tool call roles after terminal',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-legacy-tool-roles-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-legacy-tool-roles',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-legacy-tool-roles',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-legacy-tool-roles',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            toolCalls: [
              AiSeminarRunCardToolCallSnapshot(
                id: 'seminar-chat-legacy-tool-roles:tool:concept:running',
                agentRunId: 'seminar-chat-legacy-tool-roles:role-supportive-0',
                parentRunId: 'seminar-chat-legacy-tool-roles',
                toolId: 'concept_graph_search',
                status: 'running',
                query: 'agency graph',
                resultCount: 0,
                startedAt: 1717516830000,
                roleIds: ['supportive', 'synthesizer'],
              ),
            ],
          ),
        );
    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-legacy-tool-roles',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            toolCalls: [
              AiSeminarRunCardToolCallSnapshot(
                id: 'seminar-chat-legacy-tool-roles:tool:concept:completed',
                agentRunId: 'seminar-chat-legacy-tool-roles:role-supportive-0',
                parentRunId: 'seminar-chat-legacy-tool-roles',
                toolId: 'concept_graph_search',
                status: 'completed',
                text: 'Returned 1 traceable graph node.',
                query: 'agency graph',
                resultCount: 1,
                completedAt: 1717516833000,
              ),
            ],
          ),
        );

    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final toolCalls = card?.snapshot?.toolCalls;

    expect(toolCalls, hasLength(1));
    expect(toolCalls?.single.status, 'completed');
    expect(toolCalls?.single.roleIds, ['supportive', 'synthesizer']);
  });

  test(
      'updateSeminarRunCardSnapshot keeps snapshot tool call evidence after terminal',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-legacy-tool-evidence-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-legacy-tool-evidence',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-legacy-tool-evidence',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-legacy-tool-evidence',
          status: 'running',
          snapshot: AiSeminarRunCardSnapshot(
            toolCalls: [
              AiSeminarRunCardToolCallSnapshot(
                id: 'seminar-chat-legacy-tool-evidence:tool:book:running',
                agentRunId:
                    'seminar-chat-legacy-tool-evidence:role-supportive-0',
                parentRunId: 'seminar-chat-legacy-tool-evidence',
                toolId: 'semantic_search_current_book',
                status: 'running',
                query: 'agency evidence',
                resultCount: 1,
                startedAt: 1717516850000,
                evidenceRefs: [
                  AiSeminarRunCardEvidenceSnapshot(
                    id: 'legacy-evidence-keep',
                    title: 'Chapter 4',
                    snippet: 'Legacy traceable evidence should stay.',
                    sourceRef: SourceRef(
                      bookId: 7,
                      cfi: 'epubcfi(/6/8)',
                      sourceKind: SourceRefKind.currentBookRag,
                      sourceTextSnippet:
                          'Legacy traceable evidence should stay.',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-legacy-tool-evidence',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            toolCalls: [
              AiSeminarRunCardToolCallSnapshot(
                id: 'seminar-chat-legacy-tool-evidence:tool:book:completed',
                agentRunId:
                    'seminar-chat-legacy-tool-evidence:role-supportive-0',
                parentRunId: 'seminar-chat-legacy-tool-evidence',
                toolId: 'semantic_search_current_book',
                status: 'completed',
                text: 'Returned 1 traceable evidence chunk.',
                query: 'agency evidence',
                resultCount: 1,
                completedAt: 1717516853000,
              ),
            ],
          ),
        );

    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final toolCalls = card?.snapshot?.toolCalls;

    expect(toolCalls, hasLength(1));
    expect(toolCalls?.single.status, 'completed');
    expect(toolCalls?.single.evidenceRefs, hasLength(1));
    expect(toolCalls?.single.evidenceRefs.single.id, 'legacy-evidence-keep');
  });

  test(
      'updateSeminarRunCardSnapshot keeps snapshot tool call query after terminal',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-legacy-tool-query-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-legacy-tool-query',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-legacy-tool-query',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-legacy-tool-query',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            toolCalls: [
              AiSeminarRunCardToolCallSnapshot(
                id: 'seminar-chat-legacy-tool-query:tool:memory',
                agentRunId: 'seminar-chat-legacy-tool-query:role-supportive-0',
                parentRunId: 'seminar-chat-legacy-tool-query',
                toolId: 'memory_search',
                status: 'running',
                query: 'legacy agency query should stay',
                resultCount: 0,
                startedAt: 1717516870000,
              ),
            ],
          ),
        );
    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-legacy-tool-query',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            toolCalls: [
              AiSeminarRunCardToolCallSnapshot(
                id: 'seminar-chat-legacy-tool-query:tool:memory',
                agentRunId: 'seminar-chat-legacy-tool-query:role-supportive-0',
                parentRunId: 'seminar-chat-legacy-tool-query',
                toolId: 'memory_search',
                status: 'completed',
                text: 'Returned 1 traceable memory note.',
                query: '',
                resultCount: 1,
                completedAt: 1717516873000,
              ),
            ],
          ),
        );

    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final toolCalls = card?.snapshot?.toolCalls;

    expect(toolCalls, hasLength(1));
    expect(toolCalls?.single.status, 'completed');
    expect(toolCalls?.single.query, 'legacy agency query should stay');
  });

  test(
      'loadHistoryEntry replaces stale Seminar tool call parts by run metadata',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-tool-meta-replace-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-tool-meta-replace',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-tool-meta-replace',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-tool-meta-replace',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'tool_call',
                id: 'seminar-chat-tool-meta-replace:tool:current-book:snapshot-running',
                agentRunId: 'seminar-chat-tool-meta-replace:tool:current-book',
                parentRunId: 'seminar-chat-tool-meta-replace',
                toolId: 'semantic_search_current_book',
                status: 'running',
                query: '这个概念怎么理解？',
                roleIds: ['critical', 'supportive', 'synthesizer'],
              ),
            ],
          ),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId:
          'seminar-chat-tool-meta-replace:tool:current-book:graph-completed',
      runId: 'seminar-chat-tool-meta-replace:tool:current-book',
      parentRunId: 'seminar-chat-tool-meta-replace',
      type: AgentRunEventType.toolCall,
      createdAt: DateTime.utc(2026, 6, 4, 22, 30),
      status: SubAgentRunStatus.completed,
      toolId: 'semantic_search_current_book',
      query: '这个概念怎么理解？',
      result: 'Returned 2 traceable evidence chunks.',
      resultCount: 2,
      roleIds: const ['critical', 'supportive', 'synthesizer'],
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final toolCalls = restoredCard?.snapshot?.messageParts
        .where((part) => part.type == 'tool_call')
        .toList(growable: false);

    expect(toolCalls, hasLength(1));
    expect(toolCalls?.single.id,
        'seminar-chat-tool-meta-replace:tool:current-book:graph-completed');
    expect(toolCalls?.single.status, 'completed');
    expect(toolCalls?.single.text,
        contains('Returned 2 traceable evidence chunks.'));
    expect(toolCalls?.single.resultCount, 2);
  });

  test(
      'loadHistoryEntry preserves stale Seminar tool call metadata during graph replay',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-tool-replay-metadata-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-tool-replay-metadata',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-tool-replay-metadata',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-tool-replay-metadata',
          status: 'running',
          snapshot: AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'tool_call',
                id: 'seminar-chat-tool-replay-metadata:tool:current-book:snapshot-running',
                agentRunId:
                    'seminar-chat-tool-replay-metadata:tool:current-book',
                parentRunId: 'seminar-chat-tool-replay-metadata',
                toolId: 'semantic_search_current_book',
                status: 'running',
                query: 'agency trace',
                roleIds: ['critical', 'supportive'],
                evidenceRefs: [
                  AiSeminarRunCardEvidenceSnapshot(
                    id: 'evidence-replay-keep',
                    title: 'Chapter 5',
                    snippet: 'Graph replay should keep evidence.',
                    sourceRef: SourceRef(
                      bookId: 7,
                      cfi: 'epubcfi(/6/10)',
                      sourceKind: SourceRefKind.currentBookRag,
                      sourceTextSnippet: 'Graph replay should keep evidence.',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId:
          'seminar-chat-tool-replay-metadata:tool:current-book:graph-completed',
      runId: 'seminar-chat-tool-replay-metadata:tool:current-book',
      parentRunId: 'seminar-chat-tool-replay-metadata',
      type: AgentRunEventType.toolCall,
      createdAt: DateTime.utc(2026, 6, 4, 22, 35),
      status: SubAgentRunStatus.completed,
      toolId: 'semantic_search_current_book',
      query: 'agency trace',
      result: 'Returned 1 traceable evidence chunk.',
      resultCount: 1,
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final toolCalls = restoredCard?.snapshot?.messageParts
        .where((part) => part.type == 'tool_call')
        .toList(growable: false);

    expect(toolCalls, hasLength(1));
    expect(toolCalls?.single.status, 'completed');
    expect(toolCalls?.single.text,
        contains('Returned 1 traceable evidence chunk.'));
    expect(toolCalls?.single.query, 'agency trace');
    expect(toolCalls?.single.roleIds, ['critical', 'supportive']);
    expect(toolCalls?.single.evidenceRefs.single.id, 'evidence-replay-keep');
  });

  test('loadHistoryEntry normalizes Seminar tool call refs into evidence block',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-history-evidence-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-history-evidence',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-history-evidence',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-history-evidence',
          status: 'running',
          snapshot: AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'tool_call',
                id: 'seminar-chat-history-evidence:tool:current-book:running',
                agentRunId: 'seminar-chat-history-evidence:tool:current-book',
                parentRunId: 'seminar-chat-history-evidence',
                toolId: 'semantic_search_current_book',
                status: 'running',
                query: 'agency trace',
                resultCount: 1,
                evidenceRefs: [
                  AiSeminarRunCardEvidenceSnapshot(
                    id: 'history-evidence-block',
                    title: 'Chapter 7',
                    snippet: 'History load should expose evidence.',
                    sourceRef: SourceRef(
                      bookId: 7,
                      cfi: 'epubcfi(/6/14)',
                      sourceKind: SourceRefKind.currentBookRag,
                      sourceTextSnippet: 'History load should expose evidence.',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final evidenceParts = restoredCard?.snapshot?.messageParts
        .where((part) => part.type == 'evidence')
        .toList(growable: false);

    expect(evidenceParts, hasLength(1));
    expect(evidenceParts?.single.id,
        'seminar-chat-history-evidence:evidence:tool-call');
    expect(evidenceParts?.single.parentRunId, 'seminar-chat-history-evidence');
    expect(
        evidenceParts?.single.evidenceRefs.single.id, 'history-evidence-block');
    expect(evidenceParts?.single.evidenceRefs.single.sourceRef?.bookId, 7);
  });

  test(
      'loadHistoryEntry restores evidence block from preserved Seminar tool call refs',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-tool-replay-evidence-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-tool-replay-evidence',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-tool-replay-evidence',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-tool-replay-evidence',
          status: 'running',
          snapshot: AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'tool_call',
                id: 'seminar-chat-tool-replay-evidence:tool:current-book:snapshot-running',
                agentRunId:
                    'seminar-chat-tool-replay-evidence:tool:current-book',
                parentRunId: 'seminar-chat-tool-replay-evidence',
                toolId: 'semantic_search_current_book',
                status: 'running',
                query: 'agency trace',
                resultCount: 1,
                evidenceRefs: [
                  AiSeminarRunCardEvidenceSnapshot(
                    id: 'evidence-block-restore',
                    title: 'Chapter 6',
                    snippet: 'Evidence block should be restored.',
                    sourceRef: SourceRef(
                      bookId: 7,
                      cfi: 'epubcfi(/6/12)',
                      sourceKind: SourceRefKind.currentBookRag,
                      sourceTextSnippet: 'Evidence block should be restored.',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId:
          'seminar-chat-tool-replay-evidence:tool:current-book:graph-completed',
      runId: 'seminar-chat-tool-replay-evidence:tool:current-book',
      parentRunId: 'seminar-chat-tool-replay-evidence',
      type: AgentRunEventType.toolCall,
      createdAt: DateTime.utc(2026, 6, 4, 22, 36),
      status: SubAgentRunStatus.completed,
      toolId: 'semantic_search_current_book',
      query: 'agency trace',
      result: 'Returned 1 traceable evidence chunk.',
      resultCount: 1,
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final evidenceParts = restoredCard?.snapshot?.messageParts
        .where((part) => part.type == 'evidence')
        .toList(growable: false);

    expect(evidenceParts, hasLength(1));
    expect(evidenceParts?.single.id,
        'seminar-chat-tool-replay-evidence:evidence:tool-call');
    expect(
        evidenceParts?.single.parentRunId, 'seminar-chat-tool-replay-evidence');
    expect(
        evidenceParts?.single.evidenceRefs.single.id, 'evidence-block-restore');
    expect(evidenceParts?.single.evidenceRefs.single.sourceRef?.bookId, 7);
  });

  test(
      'loadHistoryEntry preserves stale Seminar tool call result count during graph replay',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-tool-replay-count-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-tool-replay-count',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-tool-replay-count',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-tool-replay-count',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'tool_call',
                id: 'seminar-chat-tool-replay-count:tool:current-book:snapshot-running',
                agentRunId: 'seminar-chat-tool-replay-count:tool:current-book',
                parentRunId: 'seminar-chat-tool-replay-count',
                toolId: 'semantic_search_current_book',
                status: 'running',
                query: 'agency count',
                resultCount: 3,
              ),
            ],
          ),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId:
          'seminar-chat-tool-replay-count:tool:current-book:graph-completed',
      runId: 'seminar-chat-tool-replay-count:tool:current-book',
      parentRunId: 'seminar-chat-tool-replay-count',
      type: AgentRunEventType.toolCall,
      createdAt: DateTime.utc(2026, 6, 4, 22, 40),
      status: SubAgentRunStatus.completed,
      toolId: 'semantic_search_current_book',
      query: 'agency count',
      result: 'Returned traceable evidence chunks.',
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final toolCalls = restoredCard?.snapshot?.messageParts
        .where((part) => part.type == 'tool_call')
        .toList(growable: false);

    expect(toolCalls, hasLength(1));
    expect(toolCalls?.single.status, 'completed');
    expect(toolCalls?.single.query, 'agency count');
    expect(toolCalls?.single.resultCount, 3);
  });

  test(
      'loadHistoryEntry preserves stale Seminar tool call output during graph replay',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-tool-replay-output-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-tool-replay-output',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-tool-replay-output',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-tool-replay-output',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'tool_call',
                id: 'seminar-chat-tool-replay-output:tool:current-book:snapshot-running',
                agentRunId: 'seminar-chat-tool-replay-output:tool:current-book',
                parentRunId: 'seminar-chat-tool-replay-output',
                toolId: 'semantic_search_current_book',
                status: 'running',
                query: 'agency output',
                text: 'Returned 3 traceable evidence chunks.',
                resultCount: 3,
              ),
            ],
          ),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId:
          'seminar-chat-tool-replay-output:tool:current-book:graph-completed',
      runId: 'seminar-chat-tool-replay-output:tool:current-book',
      parentRunId: 'seminar-chat-tool-replay-output',
      type: AgentRunEventType.toolCall,
      createdAt: DateTime.utc(2026, 6, 4, 22, 42),
      status: SubAgentRunStatus.completed,
      toolId: 'semantic_search_current_book',
      query: 'agency output',
      resultCount: 3,
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final toolCalls = restoredCard?.snapshot?.messageParts
        .where((part) => part.type == 'tool_call')
        .toList(growable: false);

    expect(toolCalls, hasLength(1));
    expect(toolCalls?.single.status, 'completed');
    expect(toolCalls?.single.query, 'agency output');
    expect(toolCalls?.single.text, 'Returned 3 traceable evidence chunks.');
  });

  test(
      'loadHistoryEntry clears stale Seminar tool call result count when graph replay interrupts',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-tool-replay-count-stop-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-tool-replay-count-stop',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-tool-replay-count-stop',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-tool-replay-count-stop',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'tool_call',
                id: 'seminar-chat-tool-replay-count-stop:tool:current-book:snapshot-running',
                agentRunId:
                    'seminar-chat-tool-replay-count-stop:tool:current-book',
                parentRunId: 'seminar-chat-tool-replay-count-stop',
                toolId: 'semantic_search_current_book',
                status: 'running',
                query: 'agency interrupted count',
                resultCount: 3,
              ),
            ],
          ),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId:
          'seminar-chat-tool-replay-count-stop:tool:current-book:graph-interrupted',
      runId: 'seminar-chat-tool-replay-count-stop:tool:current-book',
      parentRunId: 'seminar-chat-tool-replay-count-stop',
      type: AgentRunEventType.toolCall,
      createdAt: DateTime.utc(2026, 6, 4, 22, 44),
      status: SubAgentRunStatus.interrupted,
      toolId: 'semantic_search_current_book',
      query: 'agency interrupted count',
      error: 'Tool call interrupted before results were returned.',
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final toolCalls = restoredCard?.snapshot?.messageParts
        .where((part) => part.type == 'tool_call')
        .toList(growable: false);

    expect(toolCalls, hasLength(1));
    expect(toolCalls?.single.status, 'interrupted');
    expect(toolCalls?.single.text,
        'Tool call interrupted before results were returned.');
    expect(toolCalls?.single.resultCount, 0);
  });

  test(
      'loadHistoryEntry promotes legacy Seminar tool call parts to graph-traced parts',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-tool-legacy-replace-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-tool-legacy-replace',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-tool-legacy-replace',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-tool-legacy-replace',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'tool_call',
                id: 'seminar-chat-tool-legacy-replace:tool:current-book:legacy-running',
                parentRunId: 'seminar-chat-tool-legacy-replace',
                toolId: 'semantic_search_current_book',
                status: 'running',
                query: '这个概念怎么理解？',
                roleIds: ['critical', 'supportive', 'synthesizer'],
              ),
            ],
          ),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId:
          'seminar-chat-tool-legacy-replace:tool:current-book:graph-completed',
      runId: 'seminar-chat-tool-legacy-replace:tool:current-book',
      parentRunId: 'seminar-chat-tool-legacy-replace',
      type: AgentRunEventType.toolCall,
      createdAt: DateTime.utc(2026, 6, 4, 22, 45),
      status: SubAgentRunStatus.completed,
      toolId: 'semantic_search_current_book',
      query: '这个概念怎么理解？',
      result: 'Returned 1 traceable evidence chunk.',
      resultCount: 1,
      roleIds: const ['critical', 'supportive', 'synthesizer'],
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final toolCalls = restoredCard?.snapshot?.messageParts
        .where((part) => part.type == 'tool_call')
        .toList(growable: false);

    expect(toolCalls, hasLength(1));
    expect(toolCalls?.single.id,
        'seminar-chat-tool-legacy-replace:tool:current-book:graph-completed');
    expect(toolCalls?.single.agentRunId,
        'seminar-chat-tool-legacy-replace:tool:current-book');
    expect(toolCalls?.single.status, 'completed');
    expect(toolCalls?.single.text,
        contains('Returned 1 traceable evidence chunk.'));
  });

  test(
      'loadHistoryEntry keeps terminal Seminar tool call when graph replay is stale running',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-tool-no-downgrade-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-tool-no-downgrade',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-tool-no-downgrade',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-tool-no-downgrade',
          status: 'completed',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'tool_call',
                id: 'seminar-chat-tool-no-downgrade:tool:current-book:completed-snapshot',
                agentRunId: 'seminar-chat-tool-no-downgrade:tool:current-book',
                parentRunId: 'seminar-chat-tool-no-downgrade',
                toolId: 'semantic_search_current_book',
                status: 'completed',
                query: '这个概念怎么理解？',
                text: 'Returned 3 traceable evidence chunks.',
                resultCount: 3,
                roleIds: ['critical', 'supportive', 'synthesizer'],
              ),
            ],
          ),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: 'seminar-chat-tool-no-downgrade:tool:current-book:graph-running',
      runId: 'seminar-chat-tool-no-downgrade:tool:current-book',
      parentRunId: 'seminar-chat-tool-no-downgrade',
      type: AgentRunEventType.toolCall,
      createdAt: DateTime.utc(2026, 6, 4, 23),
      status: SubAgentRunStatus.running,
      toolId: 'semantic_search_current_book',
      query: '这个概念怎么理解？',
      roleIds: const ['critical', 'supportive', 'synthesizer'],
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final toolCalls = restoredCard?.snapshot?.messageParts
        .where((part) => part.type == 'tool_call')
        .toList(growable: false);

    expect(toolCalls, hasLength(1));
    expect(toolCalls?.single.id,
        'seminar-chat-tool-no-downgrade:tool:current-book:completed-snapshot');
    expect(toolCalls?.single.status, 'completed');
    expect(toolCalls?.single.text,
        contains('Returned 3 traceable evidence chunks.'));
    expect(toolCalls?.single.resultCount, 3);
  });

  test(
      'loadHistoryEntry keeps notFound Seminar tool call when graph replay is stale running',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-tool-missing-terminal-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-tool-missing-terminal',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-tool-missing-terminal',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-tool-missing-terminal',
          status: 'completed',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'tool_call',
                id: 'seminar-chat-tool-missing-terminal:tool:current-book:not-found-snapshot',
                agentRunId:
                    'seminar-chat-tool-missing-terminal:tool:current-book',
                parentRunId: 'seminar-chat-tool-missing-terminal',
                toolId: 'semantic_search_current_book',
                status: 'notFound',
                query: '这个概念怎么理解？',
                text: 'Graph tool call was not found.',
                roleIds: ['critical', 'supportive', 'synthesizer'],
              ),
            ],
          ),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId:
          'seminar-chat-tool-missing-terminal:tool:current-book:graph-running',
      runId: 'seminar-chat-tool-missing-terminal:tool:current-book',
      parentRunId: 'seminar-chat-tool-missing-terminal',
      type: AgentRunEventType.toolCall,
      createdAt: DateTime.utc(2026, 6, 5, 17),
      status: SubAgentRunStatus.running,
      toolId: 'semantic_search_current_book',
      query: '这个概念怎么理解？',
      roleIds: const ['critical', 'supportive', 'synthesizer'],
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final toolCalls = restoredCard?.snapshot?.messageParts
        .where((part) => part.type == 'tool_call')
        .toList(growable: false);

    expect(toolCalls, hasLength(1));
    expect(toolCalls?.single.id,
        'seminar-chat-tool-missing-terminal:tool:current-book:not-found-snapshot');
    expect(toolCalls?.single.status, 'notFound');
    expect(toolCalls?.single.text, 'Graph tool call was not found.');
  });

  test(
      'loadHistoryEntry replaces stale Seminar role status parts from graph terminal replay',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-status-replay-replace-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-status-replay-replace',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-status-replay-replace',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-status-replay-replace',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'agent_status',
                id: 'seminar-chat-status-replay-replace:role-critical-0:status:running',
                agentRunId:
                    'seminar-chat-status-replay-replace:role-critical-0',
                parentRunId: 'seminar-chat-status-replay-replace',
                roleId: 'critical',
                label: 'role-running',
                text: 'Critical is running.',
                actionIds: ['wait-agent', 'close-agent'],
              ),
            ],
          ),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: 'seminar-chat-status-replay-replace:role-critical-0:error',
      runId: 'seminar-chat-status-replay-replace:role-critical-0',
      parentRunId: 'seminar-chat-status-replay-replace',
      type: AgentRunEventType.error,
      createdAt: DateTime.utc(2026, 6, 4, 22),
      roleId: 'critical',
      nickname: 'Critical',
      error: 'provider timeout',
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final statusParts = restoredCard?.snapshot?.messageParts
        .where(
          (part) => part.type == 'agent_status' && part.roleId == 'critical',
        )
        .toList(growable: false);

    expect(statusParts, hasLength(1));
    expect(statusParts?.single.label, 'role-error');
    expect(statusParts?.single.text, contains('provider timeout'));
    expect(statusParts?.single.actionIds, ['retry-agent-control']);
  });

  test(
      'loadHistoryEntry promotes legacy Seminar role turns to graph-traced parts',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-role-turn-replay-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-role-turn-replay',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-role-turn-replay',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-role-turn-replay',
          status: 'completed',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'role_turn',
                roleId: 'critical',
                label: 'Critical',
                text: 'Critical traced response.',
              ),
            ],
          ),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: 'seminar-chat-role-turn-replay:role-critical-0:result',
      runId: 'seminar-chat-role-turn-replay:role-critical-0',
      parentRunId: 'seminar-chat-role-turn-replay',
      type: AgentRunEventType.result,
      createdAt: DateTime.utc(2026, 6, 4, 23),
      roleId: 'critical',
      nickname: 'Critical',
      result: 'Critical traced response.',
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final roleTurns = restoredCard?.snapshot?.messageParts
        .where(
          (part) => part.type == 'role_turn' && part.roleId == 'critical',
        )
        .toList(growable: false);

    expect(roleTurns, hasLength(1));
    expect(roleTurns?.single.text, 'Critical traced response.');
    expect(
      roleTurns?.single.agentRunId,
      'seminar-chat-role-turn-replay:role-critical-0',
    );
    expect(
      roleTurns?.single.parentRunId,
      'seminar-chat-role-turn-replay',
    );
  });

  test(
      'loadHistoryEntry promotes live Seminar role turns to graph result parts',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-live-role-result-replay-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-live-role-result-replay',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-live-role-result-replay',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-live-role-result-replay',
          status: 'completed',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'role_turn',
                agentRunId:
                    'seminar-chat-live-role-result-replay:role-critical-0',
                parentRunId: 'seminar-chat-live-role-result-replay',
                roleId: 'critical',
                label: 'Critical',
                text: 'Critical traced response.',
              ),
            ],
          ),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: 'seminar-chat-live-role-result-replay:role-critical-0:result',
      runId: 'seminar-chat-live-role-result-replay:role-critical-0',
      parentRunId: 'seminar-chat-live-role-result-replay',
      type: AgentRunEventType.result,
      createdAt: DateTime.utc(2026, 6, 4, 23, 30),
      roleId: 'critical',
      nickname: 'Critical',
      result: 'Critical traced response.',
      evidenceRefs: [
        AiSeminarRunCardEvidenceSnapshot(
          id: 'e1',
          title: 'Traceable source',
          snippet: 'Evidence snippet.',
          sourceRef: SourceRef(
            bookId: 7,
            href: 'chapter.xhtml',
            cfi: '/6/2',
            sourceTextSnippet: 'Evidence snippet.',
            sourceKind: SourceRefKind.currentBookRag,
          ),
        ),
      ],
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final roleTurns = restoredCard?.snapshot?.messageParts
        .where(
          (part) => part.type == 'role_turn' && part.roleId == 'critical',
        )
        .toList(growable: false);

    expect(roleTurns, hasLength(1));
    expect(roleTurns?.single.id,
        'seminar-chat-live-role-result-replay:role-critical-0:result');
    expect(roleTurns?.single.text, 'Critical traced response.');
    expect(
      roleTurns?.single.agentRunId,
      'seminar-chat-live-role-result-replay:role-critical-0',
    );
    expect(roleTurns?.single.evidenceRefs.single.id, 'e1');
    expect(roleTurns?.single.evidenceRefs.single.sourceRef?.bookId, 7);
  });

  test('loadHistoryEntry drops stale Seminar role partial after graph result',
      () async {
    final tempDir = Directory.systemTemp
        .createTempSync('ai-chat-role-partial-result-replay-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-role-partial-result-replay',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-role-partial-result-replay',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-role-partial-result-replay',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'role_partial',
                id: 'seminar-chat-role-partial-result-replay:role-critical-0:delta:0',
                agentRunId:
                    'seminar-chat-role-partial-result-replay:role-critical-0',
                parentRunId: 'seminar-chat-role-partial-result-replay',
                roleId: 'critical',
                label: 'Critical',
                text: 'Critical partial response...',
              ),
            ],
          ),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: 'seminar-chat-role-partial-result-replay:role-critical-0:result',
      runId: 'seminar-chat-role-partial-result-replay:role-critical-0',
      parentRunId: 'seminar-chat-role-partial-result-replay',
      type: AgentRunEventType.result,
      createdAt: DateTime.utc(2026, 6, 4, 23, 45),
      roleId: 'critical',
      nickname: 'Critical',
      result: 'Critical completed response.',
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final partials = restoredCard?.snapshot?.messageParts
        .where(
          (part) => part.type == 'role_partial' && part.roleId == 'critical',
        )
        .toList(growable: false);
    final roleTurns = restoredCard?.snapshot?.messageParts
        .where(
          (part) => part.type == 'role_turn' && part.roleId == 'critical',
        )
        .toList(growable: false);

    expect(partials, isEmpty);
    expect(roleTurns, hasLength(1));
    expect(roleTurns?.single.text, 'Critical completed response.');
    expect(
      roleTurns?.single.agentRunId,
      'seminar-chat-role-partial-result-replay:role-critical-0',
    );
  });

  test(
      'loadHistoryEntry drops stale id-only Seminar role partial after graph result',
      () async {
    final tempDir = Directory.systemTemp
        .createTempSync('ai-chat-role-partial-id-result-replay-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-role-partial-id-result-replay',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-role-partial-id-result-replay',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-role-partial-id-result-replay',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'role_partial',
                id: 'seminar-chat-role-partial-id-result-replay:role-critical-0:delta:0',
                parentRunId: 'seminar-chat-role-partial-id-result-replay',
                roleId: 'critical',
                label: 'Critical',
                text: 'Critical partial response...',
              ),
            ],
          ),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId:
          'seminar-chat-role-partial-id-result-replay:role-critical-0:result',
      runId: 'seminar-chat-role-partial-id-result-replay:role-critical-0',
      parentRunId: 'seminar-chat-role-partial-id-result-replay',
      type: AgentRunEventType.result,
      createdAt: DateTime.utc(2026, 6, 5),
      roleId: 'critical',
      nickname: 'Critical',
      result: 'Critical completed response.',
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final partials = restoredCard?.snapshot?.messageParts
        .where(
          (part) => part.type == 'role_partial' && part.roleId == 'critical',
        )
        .toList(growable: false);
    final roleTurns = restoredCard?.snapshot?.messageParts
        .where(
          (part) => part.type == 'role_turn' && part.roleId == 'critical',
        )
        .toList(growable: false);

    expect(partials, isEmpty);
    expect(roleTurns, hasLength(1));
    expect(roleTurns?.single.text, 'Critical completed response.');
    expect(
      roleTurns?.single.agentRunId,
      'seminar-chat-role-partial-id-result-replay:role-critical-0',
    );
  });

  test(
      'loadHistoryEntry drops stale generic thinking after graph streamed thinking',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-thinking-stream-replay-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-thinking-stream-replay',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-thinking-stream-replay',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-thinking-stream-replay',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'thinking',
                id: 'seminar-chat-thinking-stream-replay:role-critical-0:thinking:start',
                parentRunId: 'seminar-chat-thinking-stream-replay',
                roleId: 'critical',
                label: 'role-start',
                text: '角色正在准备基于证据发言。',
              ),
            ],
          ),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId:
          'seminar-chat-thinking-stream-replay:role-critical-0:thinking:stream:0',
      runId: 'seminar-chat-thinking-stream-replay:role-critical-0',
      parentRunId: 'seminar-chat-thinking-stream-replay',
      type: AgentRunEventType.thinking,
      createdAt: DateTime.utc(2026, 6, 5, 1),
      roleId: 'critical',
      nickname: 'Critical',
      result: 'Checking the strongest evidence before responding.',
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final thinkingParts = restoredCard?.snapshot?.messageParts
        .where(
          (part) => part.type == 'thinking' && part.roleId == 'critical',
        )
        .toList(growable: false);

    expect(thinkingParts, hasLength(1));
    expect(
      thinkingParts?.single.id,
      'seminar-chat-thinking-stream-replay:role-critical-0:thinking:stream:0',
    );
    expect(
      thinkingParts?.single.text,
      'Checking the strongest evidence before responding.',
    );
    expect(
      thinkingParts?.single.agentRunId,
      'seminar-chat-thinking-stream-replay:role-critical-0',
    );
  });

  test('loadHistoryEntry drops stale Seminar role partial after graph error',
      () async {
    final tempDir = Directory.systemTemp
        .createTempSync('ai-chat-role-partial-error-replay-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-role-partial-error-replay',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-role-partial-error-replay',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-role-partial-error-replay',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'role_partial',
                id: 'seminar-chat-role-partial-error-replay:role-critical-0:delta:0',
                agentRunId:
                    'seminar-chat-role-partial-error-replay:role-critical-0',
                parentRunId: 'seminar-chat-role-partial-error-replay',
                roleId: 'critical',
                label: 'Critical',
                text: 'Critical partial response...',
              ),
            ],
          ),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: 'seminar-chat-role-partial-error-replay:role-critical-0:error',
      runId: 'seminar-chat-role-partial-error-replay:role-critical-0',
      parentRunId: 'seminar-chat-role-partial-error-replay',
      type: AgentRunEventType.error,
      createdAt: DateTime.utc(2026, 6, 4, 23, 50),
      roleId: 'critical',
      nickname: 'Critical',
      error: 'provider timeout',
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final partials = restoredCard?.snapshot?.messageParts
        .where(
          (part) => part.type == 'role_partial' && part.roleId == 'critical',
        )
        .toList(growable: false);
    final statusParts = restoredCard?.snapshot?.messageParts
        .where(
          (part) => part.type == 'agent_status' && part.roleId == 'critical',
        )
        .toList(growable: false);

    expect(partials, isEmpty);
    expect(statusParts, hasLength(1));
    expect(statusParts?.single.label, 'role-error');
    expect(statusParts?.single.text, contains('provider timeout'));
  });

  test(
      'loadHistoryEntry drops stale Seminar role error after graph restart partial',
      () async {
    final tempDir = Directory.systemTemp
        .createTempSync('ai-chat-role-error-restart-partial-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-role-error-restart-partial',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-role-error-restart-partial',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-role-error-restart-partial',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'agent_status',
                id: 'seminar-chat-role-error-restart-partial:role-critical-0:error',
                agentRunId:
                    'seminar-chat-role-error-restart-partial:role-critical-0',
                parentRunId: 'seminar-chat-role-error-restart-partial',
                roleId: 'critical',
                label: 'role-error',
                text: 'Critical failed: provider timeout',
                actionIds: ['retry-agent-control'],
              ),
            ],
          ),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId:
          'seminar-chat-role-error-restart-partial:role-critical-0:delta:retry',
      runId: 'seminar-chat-role-error-restart-partial:role-critical-0',
      parentRunId: 'seminar-chat-role-error-restart-partial',
      type: AgentRunEventType.messageDelta,
      createdAt: DateTime.utc(2026, 6, 5, 15),
      roleId: 'critical',
      nickname: 'Critical',
      delta: 'Retry is generating a replacement answer.',
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final statusParts = restoredCard?.snapshot?.messageParts
        .where(
          (part) => part.type == 'agent_status' && part.roleId == 'critical',
        )
        .toList(growable: false);
    final partials = restoredCard?.snapshot?.messageParts
        .where(
          (part) => part.type == 'role_partial' && part.roleId == 'critical',
        )
        .toList(growable: false);

    expect(statusParts, isEmpty);
    expect(partials, hasLength(1));
    expect(partials?.single.text, 'Retry is generating a replacement answer.');
    expect(
      partials?.single.agentRunId,
      'seminar-chat-role-error-restart-partial:role-critical-0',
    );
  });

  test(
      'loadHistoryEntry drops stale Seminar role error after graph retry result',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-role-error-retry-result-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-role-error-retry-result',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-role-error-retry-result',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-role-error-retry-result',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'agent_status',
                id: 'seminar-chat-role-error-retry-result:role-critical-0:error',
                agentRunId:
                    'seminar-chat-role-error-retry-result:role-critical-0',
                parentRunId: 'seminar-chat-role-error-retry-result',
                roleId: 'critical',
                label: 'role-error',
                text: 'Critical failed: provider timeout',
                actionIds: ['retry-agent-control'],
              ),
            ],
          ),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: 'seminar-chat-role-error-retry-result:role-critical-0:result',
      runId: 'seminar-chat-role-error-retry-result:role-critical-0',
      parentRunId: 'seminar-chat-role-error-retry-result',
      type: AgentRunEventType.result,
      createdAt: DateTime.utc(2026, 6, 5, 15, 10),
      roleId: 'critical',
      nickname: 'Critical',
      result: 'Critical retry completed response.',
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final statusParts = restoredCard?.snapshot?.messageParts
        .where(
          (part) => part.type == 'agent_status' && part.roleId == 'critical',
        )
        .toList(growable: false);
    final roleTurns = restoredCard?.snapshot?.messageParts
        .where(
          (part) => part.type == 'role_turn' && part.roleId == 'critical',
        )
        .toList(growable: false);

    expect(statusParts, isEmpty);
    expect(roleTurns, hasLength(1));
    expect(roleTurns?.single.text, 'Critical retry completed response.');
    expect(
      roleTurns?.single.agentRunId,
      'seminar-chat-role-error-retry-result:role-critical-0',
    );
  });

  test(
      'closeSeminarRunCardAgent replaces an open role status with shutdown part',
      () async {
    final tempDir = Directory.systemTemp.createTempSync('ai-chat-close-agent-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-close-agent',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-close-agent',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-close-agent',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'director_state',
                id: 'seminar-chat-close-agent:role-critical-0:status:running',
                roleId: 'critical',
                label: 'role-running',
                text: 'Critical is running.',
                actionIds: ['wait-agent', 'close-agent'],
              ),
            ],
          ),
        );

    final startedAt = DateTime.utc(2026, 6, 4, 17);
    final graphStore = AgentRunGraphStore();
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-close-agent',
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: SubAgentRunStatus.running,
      task: '这个概念怎么理解？',
      startedAt: startedAt,
    ));
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-close-agent:role-critical-0',
      parentRunId: 'seminar-chat-close-agent',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.running,
      task: '这个概念怎么理解？',
      startedAt: startedAt.add(const Duration(seconds: 1)),
    ));

    final closed =
        await container.read(aiChatProvider.notifier).closeSeminarRunCardAgent(
              seminarSessionId: 'seminar-chat-close-agent',
              agentRunId: 'seminar-chat-close-agent:role-critical-0',
              now: startedAt.add(const Duration(seconds: 6)),
            );

    expect(closed, isTrue);
    expect(
        await graphStore.listOpenChildren('seminar-chat-close-agent'), isEmpty);
    final childRun = await graphStore.getRun(
      'seminar-chat-close-agent:role-critical-0',
    );
    expect(childRun?.status, SubAgentRunStatus.shutdown);

    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final statusParts = card?.snapshot?.messageParts
        .where(
          (part) => part.type == 'agent_status' && part.roleId == 'critical',
        )
        .toList(growable: false);
    final readerTurns = card?.snapshot?.messageParts
        .where(
          (part) => part.type == 'reader_turn' && part.roleId == 'critical',
        )
        .toList(growable: false);

    expect(statusParts, hasLength(1));
    expect(statusParts?.single.label, 'role-shutdown');
    expect(statusParts?.single.actionIds, isEmpty);
    expect(readerTurns, hasLength(1));
    expect(readerTurns?.single.label, 'close-agent');
    expect(readerTurns?.single.status, 'completed');
    expect(readerTurns?.single.text, isNull);
    expect(
      readerTurns?.single.completedAt,
      startedAt.add(const Duration(seconds: 6)).millisecondsSinceEpoch,
    );
  });

  test('updateSeminarRunCardSnapshot does not reopen a shutdown child status',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-shutdown-no-reopen-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-shutdown-no-reopen',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-shutdown-no-reopen',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-shutdown-no-reopen',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'agent_status',
                id: 'seminar-chat-shutdown-no-reopen:role-critical-0:status:shutdown',
                agentRunId: 'seminar-chat-shutdown-no-reopen:role-critical-0',
                parentRunId: 'seminar-chat-shutdown-no-reopen',
                roleId: 'critical',
                label: 'role-shutdown',
                text: 'Critical was stopped.',
                actionIds: [],
                completedAt: 1717516806000,
              ),
            ],
          ),
        );

    final updated = await container
        .read(aiChatProvider.notifier)
        .updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-shutdown-no-reopen',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'agent_status',
                id: 'seminar-chat-shutdown-no-reopen:role-critical-0:status:running',
                agentRunId: 'seminar-chat-shutdown-no-reopen:role-critical-0',
                parentRunId: 'seminar-chat-shutdown-no-reopen',
                roleId: 'critical',
                label: 'role-running',
                text: 'Critical is still running from a stale snapshot.',
                actionIds: ['wait-agent', 'close-agent'],
              ),
            ],
          ),
        );

    expect(updated, isTrue);
    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final statusParts = card?.snapshot?.messageParts
        .where(
          (part) => part.type == 'agent_status' && part.roleId == 'critical',
        )
        .toList(growable: false);

    expect(statusParts, hasLength(1));
    expect(statusParts?.single.label, 'role-shutdown');
    expect(statusParts?.single.actionIds, isEmpty);
    expect(statusParts?.single.completedAt, 1717516806000);
  });

  test('closeSeminarRunCardAgent does not downgrade a completed child run',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-close-completed-agent-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-close-completed-agent',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-close-completed-agent',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-close-completed-agent',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'agent_status',
                id: 'seminar-chat-close-completed-agent:role-critical-0:status:running',
                agentRunId:
                    'seminar-chat-close-completed-agent:role-critical-0',
                parentRunId: 'seminar-chat-close-completed-agent',
                roleId: 'critical',
                label: 'role-running',
                text: 'Critical is running.',
                actionIds: ['wait-agent', 'close-agent'],
              ),
            ],
          ),
        );

    final startedAt = DateTime.utc(2026, 6, 4, 17);
    final graphStore = AgentRunGraphStore();
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-close-completed-agent',
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: SubAgentRunStatus.running,
      task: '这个概念怎么理解？',
      startedAt: startedAt,
    ));
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-close-completed-agent:role-critical-0',
      parentRunId: 'seminar-chat-close-completed-agent',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.completed,
      task: '这个概念怎么理解？',
      startedAt: startedAt.add(const Duration(seconds: 1)),
      finishedAt: startedAt.add(const Duration(seconds: 5)),
      result: 'Critical already completed.',
    ));

    final closed =
        await container.read(aiChatProvider.notifier).closeSeminarRunCardAgent(
              seminarSessionId: 'seminar-chat-close-completed-agent',
              agentRunId: 'seminar-chat-close-completed-agent:role-critical-0',
              now: startedAt.add(const Duration(seconds: 6)),
            );

    expect(closed, isTrue);
    final childRun = await graphStore.getRun(
      'seminar-chat-close-completed-agent:role-critical-0',
    );
    expect(childRun?.status, SubAgentRunStatus.completed);

    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final statusParts = card?.snapshot?.messageParts
        .where(
          (part) => part.type == 'agent_status' && part.roleId == 'critical',
        )
        .toList(growable: false);
    final roleTurn = card?.snapshot?.messageParts.singleWhere(
      (part) => part.type == 'role_turn' && part.roleId == 'critical',
    );

    expect(statusParts, hasLength(1));
    expect(statusParts?.single.label, 'role-completed');
    expect(statusParts?.single.actionIds, isEmpty);
    expect(roleTurn?.text, 'Critical already completed.');
  });

  test(
      'waitSeminarRunCardAgent refreshes a completed child run into message parts',
      () async {
    final tempDir = Directory.systemTemp.createTempSync('ai-chat-wait-agent-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-wait-agent',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-wait-agent',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-wait-agent',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'director_state',
                id: 'seminar-chat-wait-agent:role-critical-0:status:running',
                roleId: 'critical',
                label: 'role-running',
                text: 'Critical is running.',
                actionIds: ['wait-agent', 'close-agent'],
              ),
            ],
          ),
        );

    final startedAt = DateTime.utc(2026, 6, 4, 18);
    final graphStore = AgentRunGraphStore();
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-wait-agent',
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: SubAgentRunStatus.running,
      task: '这个概念怎么理解？',
      startedAt: startedAt,
    ));
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-wait-agent:role-critical-0',
      parentRunId: 'seminar-chat-wait-agent',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.completed,
      task: '这个概念怎么理解？',
      startedAt: startedAt.add(const Duration(seconds: 1)),
      finishedAt: startedAt.add(const Duration(seconds: 5)),
      result: 'Critical result from graph.',
    ));

    final refreshed =
        await container.read(aiChatProvider.notifier).waitSeminarRunCardAgent(
              seminarSessionId: 'seminar-chat-wait-agent',
              agentRunId: 'seminar-chat-wait-agent:role-critical-0',
            );

    expect(refreshed, isTrue);
    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final criticalStatusParts = card?.snapshot?.messageParts
        .where(
          (part) => part.type == 'agent_status' && part.roleId == 'critical',
        )
        .toList(growable: false);
    final criticalTurn = card?.snapshot?.messageParts.singleWhere(
      (part) => part.type == 'role_turn' && part.roleId == 'critical',
    );

    expect(criticalStatusParts, hasLength(1));
    expect(criticalStatusParts?.single.label, 'role-completed');
    expect(criticalStatusParts?.single.actionIds, isEmpty);
    expect(criticalTurn?.text, 'Critical result from graph.');
  });

  test(
      'waitSeminarRunCardAgent records a wait request while child is still running',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-wait-running-agent-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-wait-running-agent',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-wait-running-agent',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-wait-running-agent',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'agent_status',
                id: 'seminar-chat-wait-running-agent:role-critical-0:status:running',
                agentRunId: 'seminar-chat-wait-running-agent:role-critical-0',
                parentRunId: 'seminar-chat-wait-running-agent',
                roleId: 'critical',
                label: 'role-running',
                text: 'Critical is running.',
                actionIds: ['wait-agent', 'close-agent'],
              ),
            ],
          ),
        );

    final startedAt = DateTime.utc(2026, 6, 4, 18, 20);
    final graphStore = AgentRunGraphStore();
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-wait-running-agent',
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: SubAgentRunStatus.running,
      task: '这个概念怎么理解？',
      startedAt: startedAt,
    ));
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-wait-running-agent:role-critical-0',
      parentRunId: 'seminar-chat-wait-running-agent',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.running,
      task: '这个概念怎么理解？',
      startedAt: startedAt.add(const Duration(seconds: 1)),
    ));

    final waited =
        await container.read(aiChatProvider.notifier).waitSeminarRunCardAgent(
              seminarSessionId: 'seminar-chat-wait-running-agent',
              agentRunId: 'seminar-chat-wait-running-agent:role-critical-0',
              now: startedAt.add(const Duration(seconds: 9)),
            );

    expect(waited, isTrue);
    final events = await graphStore.listEvents(
      'seminar-chat-wait-running-agent:role-critical-0',
    );
    expect(events.last.type, AgentRunEventType.waitRequest);
    expect(events.last.acknowledgedAt, isNull);

    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final readerTurn = card?.snapshot?.messageParts.singleWhere(
      (part) => part.type == 'reader_turn' && part.roleId == 'critical',
    );
    final statusPart = card?.snapshot?.messageParts.singleWhere(
      (part) => part.type == 'agent_status' && part.roleId == 'critical',
    );

    expect(readerTurn?.label, 'wait-agent');
    expect(readerTurn?.status, 'pending');
    expect(readerTurn?.text, 'Waiting for role to finish.');
    expect(statusPart?.actionIds, contains('close-agent'));
    expect(statusPart?.actionIds, isNot(contains('wait-agent')));

    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-wait-running-agent:role-critical-0',
      parentRunId: 'seminar-chat-wait-running-agent',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.completed,
      task: '这个概念怎么理解？',
      startedAt: startedAt.add(const Duration(seconds: 1)),
      finishedAt: startedAt.add(const Duration(seconds: 12)),
      result: 'Critical result after wait.',
    ));

    final refreshed =
        await container.read(aiChatProvider.notifier).waitSeminarRunCardAgent(
              seminarSessionId: 'seminar-chat-wait-running-agent',
              agentRunId: 'seminar-chat-wait-running-agent:role-critical-0',
              now: startedAt.add(const Duration(seconds: 13)),
            );

    expect(refreshed, isTrue);
    final waitEvents = (await graphStore.listEvents(
      'seminar-chat-wait-running-agent:role-critical-0',
    ))
        .where((event) => event.type == AgentRunEventType.waitRequest)
        .toList(growable: false);
    expect(waitEvents, hasLength(1));
    expect(
      waitEvents.single.acknowledgedAt,
      startedAt.add(const Duration(seconds: 13)),
    );

    final refreshedCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final waitReaderTurns = refreshedCard?.snapshot?.messageParts
        .where((part) =>
            part.type == 'reader_turn' &&
            part.roleId == 'critical' &&
            part.label == 'wait-agent')
        .toList(growable: false);
    expect(waitReaderTurns, hasLength(1));
    expect(waitReaderTurns?.single.status, 'completed');
    expect(waitReaderTurns?.single.completedAt, isNotNull);
    expect(
      refreshedCard?.snapshot?.messageParts
          .singleWhere(
            (part) => part.type == 'role_turn' && part.roleId == 'critical',
          )
          .text,
      'Critical result after wait.',
    );
  });

  test(
      'waitSeminarRunCardToolCall records a tool wait request while tool is running',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-wait-running-tool-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-wait-running-tool',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-wait-running-tool',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-wait-running-tool',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'tool_call',
                id: 'seminar-chat-wait-running-tool:role-critical-0:tool:notes',
                agentRunId: 'seminar-chat-wait-running-tool:role-critical-0',
                parentRunId: 'seminar-chat-wait-running-tool',
                roleId: 'critical',
                toolId: 'notes_search',
                status: 'running',
                query: 'agency notes',
                actionIds: ['wait-tool-call', 'cancel-tool-call'],
              ),
            ],
          ),
        );

    final startedAt = DateTime.utc(2026, 6, 7, 18);
    final graphStore = AgentRunGraphStore();
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-wait-running-tool',
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: SubAgentRunStatus.running,
      task: '这个概念怎么理解？',
      startedAt: startedAt,
    ));
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-wait-running-tool:role-critical-0',
      parentRunId: 'seminar-chat-wait-running-tool',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.running,
      task: '这个概念怎么理解？',
      startedAt: startedAt.add(const Duration(seconds: 1)),
    ));
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: 'seminar-chat-wait-running-tool:role-critical-0:tool:notes',
      runId: 'seminar-chat-wait-running-tool:role-critical-0',
      parentRunId: 'seminar-chat-wait-running-tool',
      type: AgentRunEventType.toolCall,
      createdAt: startedAt.add(const Duration(seconds: 2)),
      status: SubAgentRunStatus.running,
      roleId: 'critical',
      nickname: 'Critical',
      toolId: 'notes_search',
      query: 'agency notes',
      actionIds: const ['wait-tool-call', 'cancel-tool-call'],
    ));

    final waited = await container
        .read(aiChatProvider.notifier)
        .waitSeminarRunCardToolCall(
          seminarSessionId: 'seminar-chat-wait-running-tool',
          agentRunId: 'seminar-chat-wait-running-tool:role-critical-0',
          toolCallId:
              'seminar-chat-wait-running-tool:role-critical-0:tool:notes',
          now: startedAt.add(const Duration(seconds: 4)),
        );

    expect(waited, isTrue);
    final waitEvents = (await graphStore.listEvents(
      'seminar-chat-wait-running-tool:role-critical-0',
    ))
        .where((event) => event.type == AgentRunEventType.waitRequest)
        .toList(growable: false);
    expect(waitEvents, hasLength(1));
    expect(waitEvents.single.toolId, 'notes_search');
    expect(waitEvents.single.result,
        'seminar-chat-wait-running-tool:role-critical-0:tool:notes');
    expect(waitEvents.single.acknowledgedAt, isNull);

    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final readerTurn = card?.snapshot?.messageParts.singleWhere(
      (part) => part.type == 'reader_turn' && part.label == 'wait-tool-call',
    );
    final toolCall = card?.snapshot?.messageParts.singleWhere(
      (part) => part.type == 'tool_call' && part.toolId == 'notes_search',
    );

    expect(readerTurn?.status, 'pending');
    expect(readerTurn?.toolId, 'notes_search');
    expect(readerTurn?.query, 'agency notes');
    expect(readerTurn?.text, 'Waiting for tool call to finish.');
    expect(toolCall?.actionIds, contains('cancel-tool-call'));
    expect(toolCall?.actionIds, isNot(contains('wait-tool-call')));

    await graphStore.upsertEvent(AgentRunEvent(
      eventId: 'seminar-chat-wait-running-tool:role-critical-0:tool:notes',
      runId: 'seminar-chat-wait-running-tool:role-critical-0',
      parentRunId: 'seminar-chat-wait-running-tool',
      type: AgentRunEventType.toolCall,
      createdAt: startedAt.add(const Duration(seconds: 7)),
      status: SubAgentRunStatus.completed,
      roleId: 'critical',
      nickname: 'Critical',
      toolId: 'notes_search',
      query: 'agency notes',
      result: 'Returned waited notes.',
      resultCount: 1,
    ));

    final refreshed = await container
        .read(aiChatProvider.notifier)
        .waitSeminarRunCardToolCall(
          seminarSessionId: 'seminar-chat-wait-running-tool',
          agentRunId: 'seminar-chat-wait-running-tool:role-critical-0',
          toolCallId:
              'seminar-chat-wait-running-tool:role-critical-0:tool:notes',
          now: startedAt.add(const Duration(seconds: 8)),
        );

    expect(refreshed, isTrue);
    final acknowledgedWaitEvents = (await graphStore.listEvents(
      'seminar-chat-wait-running-tool:role-critical-0',
    ))
        .where((event) => event.type == AgentRunEventType.waitRequest)
        .toList(growable: false);
    expect(acknowledgedWaitEvents, hasLength(1));
    expect(acknowledgedWaitEvents.single.acknowledgedAt,
        startedAt.add(const Duration(seconds: 8)));

    final refreshedCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final completedReaderTurn =
        refreshedCard?.snapshot?.messageParts.singleWhere(
      (part) => part.type == 'reader_turn' && part.label == 'wait-tool-call',
    );
    final completedToolCall = refreshedCard?.snapshot?.messageParts.singleWhere(
      (part) => part.type == 'tool_call' && part.toolId == 'notes_search',
    );

    expect(completedReaderTurn?.status, 'completed');
    expect(completedReaderTurn?.completedAt, isNotNull);
    expect(completedToolCall?.status, 'completed');
    expect(completedToolCall?.text, 'Returned waited notes.');
  });

  test(
      'cancelSeminarRunCardToolCall records a cancel reader turn while shutting down tool call',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-cancel-running-tool-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-cancel-running-tool',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-cancel-running-tool',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-cancel-running-tool',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'tool_call',
                id: 'seminar-chat-cancel-running-tool:role-critical-0:tool:notes',
                agentRunId: 'seminar-chat-cancel-running-tool:role-critical-0',
                parentRunId: 'seminar-chat-cancel-running-tool',
                roleId: 'critical',
                toolId: 'notes_search',
                status: 'running',
                query: 'agency notes',
                actionIds: ['wait-tool-call', 'cancel-tool-call'],
              ),
            ],
          ),
        );

    final startedAt = DateTime.utc(2026, 6, 8, 12);
    final graphStore = AgentRunGraphStore();
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-cancel-running-tool',
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: SubAgentRunStatus.running,
      task: '这个概念怎么理解？',
      startedAt: startedAt,
    ));
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-cancel-running-tool:role-critical-0',
      parentRunId: 'seminar-chat-cancel-running-tool',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.running,
      task: '这个概念怎么理解？',
      startedAt: startedAt.add(const Duration(seconds: 1)),
    ));
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: 'seminar-chat-cancel-running-tool:role-critical-0:tool:notes',
      runId: 'seminar-chat-cancel-running-tool:role-critical-0',
      parentRunId: 'seminar-chat-cancel-running-tool',
      type: AgentRunEventType.toolCall,
      createdAt: startedAt.add(const Duration(seconds: 2)),
      status: SubAgentRunStatus.running,
      roleId: 'critical',
      nickname: 'Critical',
      toolId: 'notes_search',
      query: 'agency notes',
      actionIds: const ['wait-tool-call', 'cancel-tool-call'],
    ));

    final cancelled = await container
        .read(aiChatProvider.notifier)
        .cancelSeminarRunCardToolCall(
          seminarSessionId: 'seminar-chat-cancel-running-tool',
          agentRunId: 'seminar-chat-cancel-running-tool:role-critical-0',
          toolCallId:
              'seminar-chat-cancel-running-tool:role-critical-0:tool:notes',
          now: startedAt.add(const Duration(seconds: 4)),
        );

    expect(cancelled, isTrue);
    final events = await graphStore.listEvents(
      'seminar-chat-cancel-running-tool:role-critical-0',
    );
    final cancelEvents = events
        .where((event) =>
            event.type == AgentRunEventType.cancelRequest &&
            event.toolId == 'notes_search')
        .toList(growable: false);
    expect(cancelEvents, hasLength(1));
    expect(cancelEvents.single.query, 'agency notes');
    expect(cancelEvents.single.result,
        'seminar-chat-cancel-running-tool:role-critical-0:tool:notes');
    expect(cancelEvents.single.acknowledgedAt,
        startedAt.add(const Duration(seconds: 4)));

    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final cancelReaderTurn = card?.snapshot?.messageParts.singleWhere(
      (part) => part.type == 'reader_turn' && part.label == 'cancel-tool-call',
    );
    final toolCall = card?.snapshot?.messageParts.singleWhere(
      (part) => part.type == 'tool_call' && part.toolId == 'notes_search',
    );

    expect(cancelReaderTurn?.status, 'completed');
    expect(cancelReaderTurn?.toolId, 'notes_search');
    expect(cancelReaderTurn?.query, 'agency notes');
    expect(cancelReaderTurn?.completedAt,
        startedAt.add(const Duration(seconds: 4)).millisecondsSinceEpoch);
    expect(toolCall?.status, 'shutdown');
    expect(toolCall?.actionIds, isEmpty);
  });

  test('waitSeminarRunCardAgent completes wait when child is interrupted',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-wait-interrupted-agent-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-wait-interrupted-agent',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-wait-interrupted-agent',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-wait-interrupted-agent',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'agent_status',
                id: 'seminar-chat-wait-interrupted-agent:role-critical-0:status:running',
                agentRunId:
                    'seminar-chat-wait-interrupted-agent:role-critical-0',
                parentRunId: 'seminar-chat-wait-interrupted-agent',
                roleId: 'critical',
                label: 'role-running',
                text: 'Critical is running.',
                actionIds: ['wait-agent', 'close-agent'],
              ),
            ],
          ),
        );

    final startedAt = DateTime.utc(2026, 6, 4, 18, 40);
    final graphStore = AgentRunGraphStore();
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-wait-interrupted-agent',
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: SubAgentRunStatus.running,
      task: '这个概念怎么理解？',
      startedAt: startedAt,
    ));
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-wait-interrupted-agent:role-critical-0',
      parentRunId: 'seminar-chat-wait-interrupted-agent',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.running,
      task: '这个概念怎么理解？',
      startedAt: startedAt.add(const Duration(seconds: 1)),
    ));

    final waited =
        await container.read(aiChatProvider.notifier).waitSeminarRunCardAgent(
              seminarSessionId: 'seminar-chat-wait-interrupted-agent',
              agentRunId: 'seminar-chat-wait-interrupted-agent:role-critical-0',
              now: startedAt.add(const Duration(seconds: 9)),
            );
    expect(waited, isTrue);

    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-wait-interrupted-agent:role-critical-0',
      parentRunId: 'seminar-chat-wait-interrupted-agent',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.interrupted,
      task: '这个概念怎么理解？',
      startedAt: startedAt.add(const Duration(seconds: 1)),
      finishedAt: startedAt.add(const Duration(seconds: 12)),
    ));

    final refreshed =
        await container.read(aiChatProvider.notifier).waitSeminarRunCardAgent(
              seminarSessionId: 'seminar-chat-wait-interrupted-agent',
              agentRunId: 'seminar-chat-wait-interrupted-agent:role-critical-0',
              now: startedAt.add(const Duration(seconds: 13)),
            );

    expect(refreshed, isTrue);
    final waitEvents = (await graphStore.listEvents(
      'seminar-chat-wait-interrupted-agent:role-critical-0',
    ))
        .where((event) => event.type == AgentRunEventType.waitRequest)
        .toList(growable: false);
    expect(waitEvents, hasLength(1));
    expect(
      waitEvents.single.acknowledgedAt,
      startedAt.add(const Duration(seconds: 13)),
    );

    final refreshedCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final waitReaderTurns = refreshedCard?.snapshot?.messageParts
        .where((part) =>
            part.type == 'reader_turn' &&
            part.roleId == 'critical' &&
            part.label == 'wait-agent')
        .toList(growable: false);
    final statusParts = refreshedCard?.snapshot?.messageParts
        .where(
          (part) => part.type == 'agent_status' && part.roleId == 'critical',
        )
        .toList(growable: false);

    expect(waitReaderTurns, hasLength(1));
    expect(waitReaderTurns?.single.status, 'completed');
    expect(waitReaderTurns?.single.completedAt, isNotNull);
    expect(statusParts, hasLength(1));
    expect(statusParts?.single.label, 'role-interrupted');
    expect(statusParts?.single.actionIds, contains('resume-agent'));
  });

  test(
      'updateSeminarRunCardSnapshot completes satisfied wait requests from graph',
      () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'ai-chat-wait-satisfied-snapshot-',
    );
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-wait-satisfied-snapshot',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-wait-satisfied-snapshot',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-wait-satisfied-snapshot',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'agent_status',
                id: 'seminar-chat-wait-satisfied-snapshot:role-critical-0:status:running',
                agentRunId:
                    'seminar-chat-wait-satisfied-snapshot:role-critical-0',
                parentRunId: 'seminar-chat-wait-satisfied-snapshot',
                roleId: 'critical',
                label: 'role-running',
                text: 'Critical is running.',
                actionIds: ['wait-agent', 'close-agent'],
              ),
            ],
          ),
        );

    final startedAt = DateTime.utc(2026, 6, 6, 20);
    final graphStore = AgentRunGraphStore();
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-wait-satisfied-snapshot',
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: SubAgentRunStatus.running,
      task: '这个概念怎么理解？',
      startedAt: startedAt,
    ));
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-wait-satisfied-snapshot:role-critical-0',
      parentRunId: 'seminar-chat-wait-satisfied-snapshot',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.running,
      task: '这个概念怎么理解？',
      startedAt: startedAt.add(const Duration(seconds: 1)),
    ));

    final waited = await container
        .read(aiChatProvider.notifier)
        .waitSeminarRunCardAgent(
          seminarSessionId: 'seminar-chat-wait-satisfied-snapshot',
          agentRunId: 'seminar-chat-wait-satisfied-snapshot:role-critical-0',
          now: startedAt.add(const Duration(seconds: 2)),
        );
    expect(waited, isTrue);

    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-wait-satisfied-snapshot:role-critical-0',
      parentRunId: 'seminar-chat-wait-satisfied-snapshot',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.completed,
      task: '这个概念怎么理解？',
      startedAt: startedAt.add(const Duration(seconds: 1)),
      finishedAt: startedAt.add(const Duration(seconds: 8)),
      result: 'Critical completed through runtime snapshot.',
    ));

    final updated = await container
        .read(aiChatProvider.notifier)
        .updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-wait-satisfied-snapshot',
          status: 'completed',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'role_turn',
                agentRunId:
                    'seminar-chat-wait-satisfied-snapshot:role-critical-0',
                parentRunId: 'seminar-chat-wait-satisfied-snapshot',
                roleId: 'critical',
                label: 'Critical',
                text: 'Critical completed through runtime snapshot.',
              ),
            ],
          ),
        );

    expect(updated, isTrue);
    final events = await graphStore.listEvents(
      'seminar-chat-wait-satisfied-snapshot:role-critical-0',
    );
    final waitEvent = events.singleWhere(
      (event) => event.type == AgentRunEventType.waitRequest,
    );
    expect(waitEvent.acknowledgedAt, isNotNull);

    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final waitTurns = card?.snapshot?.messageParts
        .where(
          (part) =>
              part.type == 'reader_turn' &&
              part.roleId == 'critical' &&
              part.label == 'wait-agent',
        )
        .toList(growable: false);
    expect(waitTurns, hasLength(1));
    expect(waitTurns?.single.status, 'completed');
    expect(waitTurns?.single.completedAt, isNotNull);
    expect(
      card?.snapshot?.messageParts.any(
        (part) =>
            part.type == 'agent_status' &&
            part.roleId == 'critical' &&
            part.label == 'role-completed',
      ),
      isTrue,
    );
  });

  test('waitSeminarRunCardAgent records a new wait after restarted child run',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-wait-restarted-agent-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-wait-restarted-agent',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-wait-restarted-agent',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-wait-restarted-agent',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'agent_status',
                id: 'seminar-chat-wait-restarted-agent:role-critical-0:status:running',
                agentRunId: 'seminar-chat-wait-restarted-agent:role-critical-0',
                parentRunId: 'seminar-chat-wait-restarted-agent',
                roleId: 'critical',
                label: 'role-running',
                text: 'Critical is running.',
                actionIds: ['wait-agent', 'close-agent'],
              ),
            ],
          ),
        );

    final startedAt = DateTime.utc(2026, 6, 4, 18, 20);
    final graphStore = AgentRunGraphStore();
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-wait-restarted-agent',
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: SubAgentRunStatus.running,
      task: '这个概念怎么理解？',
      startedAt: startedAt,
    ));
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-wait-restarted-agent:role-critical-0',
      parentRunId: 'seminar-chat-wait-restarted-agent',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.running,
      task: '这个概念怎么理解？',
      startedAt: startedAt.add(const Duration(seconds: 1)),
    ));

    final firstWait =
        await container.read(aiChatProvider.notifier).waitSeminarRunCardAgent(
              seminarSessionId: 'seminar-chat-wait-restarted-agent',
              agentRunId: 'seminar-chat-wait-restarted-agent:role-critical-0',
              now: startedAt.add(const Duration(seconds: 9)),
            );
    expect(firstWait, isTrue);

    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-wait-restarted-agent:role-critical-0',
      parentRunId: 'seminar-chat-wait-restarted-agent',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.completed,
      task: '这个概念怎么理解？',
      startedAt: startedAt.add(const Duration(seconds: 1)),
      finishedAt: startedAt.add(const Duration(seconds: 12)),
      result: 'Critical result after first wait.',
    ));

    final acknowledged =
        await container.read(aiChatProvider.notifier).waitSeminarRunCardAgent(
              seminarSessionId: 'seminar-chat-wait-restarted-agent',
              agentRunId: 'seminar-chat-wait-restarted-agent:role-critical-0',
              now: startedAt.add(const Duration(seconds: 13)),
            );
    expect(acknowledged, isTrue);

    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-wait-restarted-agent:role-critical-0',
      parentRunId: 'seminar-chat-wait-restarted-agent',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.running,
      task: '这个概念怎么理解？',
      startedAt: startedAt.add(const Duration(seconds: 20)),
    ));

    final secondWait =
        await container.read(aiChatProvider.notifier).waitSeminarRunCardAgent(
              seminarSessionId: 'seminar-chat-wait-restarted-agent',
              agentRunId: 'seminar-chat-wait-restarted-agent:role-critical-0',
              now: startedAt.add(const Duration(seconds: 21)),
            );
    expect(secondWait, isTrue);

    final waitEvents = (await graphStore.listEvents(
      'seminar-chat-wait-restarted-agent:role-critical-0',
    ))
        .where((event) => event.type == AgentRunEventType.waitRequest)
        .toList(growable: false);
    expect(waitEvents, hasLength(2));
    expect(waitEvents.first.acknowledgedAt, isNotNull);
    expect(waitEvents.last.acknowledgedAt, isNull);
  });

  test('runtime snapshot completes an active pending wait reader turn',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-wait-runtime-merge-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-wait-runtime-merge',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-wait-runtime-merge',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-wait-runtime-merge',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'reader_turn',
                id: 'seminar-chat-wait-runtime-merge:role-critical-0:wait-request:1',
                agentRunId: 'seminar-chat-wait-runtime-merge:role-critical-0',
                parentRunId: 'seminar-chat-wait-runtime-merge',
                roleId: 'critical',
                label: 'wait-agent',
                status: 'pending',
                text: 'Waiting for role to finish.',
              ),
              AiSeminarRunCardMessagePart(
                type: 'agent_status',
                id: 'seminar-chat-wait-runtime-merge:role-critical-0:status:running',
                agentRunId: 'seminar-chat-wait-runtime-merge:role-critical-0',
                parentRunId: 'seminar-chat-wait-runtime-merge',
                roleId: 'critical',
                label: 'role-running',
                text: 'Critical is running.',
                actionIds: ['close-agent'],
              ),
            ],
          ),
        );

    final updated = await container
        .read(aiChatProvider.notifier)
        .updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-wait-runtime-merge',
          status: 'completed',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'role_turn',
                id: 'seminar-chat-wait-runtime-merge:role-critical-0:result',
                agentRunId: 'seminar-chat-wait-runtime-merge:role-critical-0',
                parentRunId: 'seminar-chat-wait-runtime-merge',
                roleId: 'critical',
                text: 'Critical result after runtime wait.',
              ),
            ],
          ),
        );

    expect(updated, isTrue);
    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final waitTurns = card?.snapshot?.messageParts
        .where((part) =>
            part.type == 'reader_turn' &&
            part.label == 'wait-agent' &&
            part.roleId == 'critical')
        .toList(growable: false);
    expect(waitTurns, hasLength(1));
    expect(waitTurns?.single.status, 'completed');
    expect(waitTurns?.single.completedAt, isNotNull);
    expect(
      card?.snapshot?.messageParts
          .singleWhere((part) => part.type == 'role_turn')
          .text,
      'Critical result after runtime wait.',
    );
  });

  test('runtime snapshot completes an active pending tool wait reader turn',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-tool-wait-runtime-merge-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-tool-wait-runtime-merge',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-tool-wait-runtime-merge',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-tool-wait-runtime-merge',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'reader_turn',
                id: 'seminar-chat-tool-wait-runtime-merge:role-critical-0:wait-tool-call:notes:1',
                agentRunId:
                    'seminar-chat-tool-wait-runtime-merge:role-critical-0',
                parentRunId: 'seminar-chat-tool-wait-runtime-merge',
                roleId: 'critical',
                toolId: 'notes_search',
                label: 'wait-tool-call',
                status: 'pending',
                text: 'Waiting for tool call to finish.',
                query: 'agency notes',
              ),
              AiSeminarRunCardMessagePart(
                type: 'tool_call',
                id: 'seminar-chat-tool-wait-runtime-merge:role-critical-0:tool:notes',
                agentRunId:
                    'seminar-chat-tool-wait-runtime-merge:role-critical-0',
                parentRunId: 'seminar-chat-tool-wait-runtime-merge',
                roleId: 'critical',
                toolId: 'notes_search',
                status: 'running',
                query: 'agency notes',
                actionIds: ['cancel-tool-call'],
              ),
            ],
          ),
        );

    final completedAt = DateTime.utc(2026, 6, 8, 12, 0, 4);
    final updated = await container
        .read(aiChatProvider.notifier)
        .updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-tool-wait-runtime-merge',
          status: 'running',
          snapshot: AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'tool_call',
                id: 'seminar-chat-tool-wait-runtime-merge:role-critical-0:tool:notes',
                agentRunId:
                    'seminar-chat-tool-wait-runtime-merge:role-critical-0',
                parentRunId: 'seminar-chat-tool-wait-runtime-merge',
                roleId: 'critical',
                toolId: 'notes_search',
                status: 'completed',
                query: 'agency notes',
                text: 'Returned waited notes.',
                resultCount: 1,
                completedAt: completedAt.millisecondsSinceEpoch,
              ),
            ],
          ),
        );

    expect(updated, isTrue);
    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final waitTurns = card?.snapshot?.messageParts
        .where((part) =>
            part.type == 'reader_turn' &&
            part.label == 'wait-tool-call' &&
            part.roleId == 'critical')
        .toList(growable: false);
    final toolCall = card?.snapshot?.messageParts.singleWhere(
      (part) => part.type == 'tool_call' && part.toolId == 'notes_search',
    );

    expect(waitTurns, hasLength(1));
    expect(waitTurns?.single.status, 'completed');
    expect(waitTurns?.single.completedAt, completedAt.millisecondsSinceEpoch);
    expect(toolCall?.status, 'completed');
    expect(toolCall?.text, 'Returned waited notes.');
  });

  test('runtime snapshot cancels an unacknowledged pending reader control',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-control-runtime-merge-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-control-runtime-merge',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-control-runtime-merge',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-control-runtime-merge',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'reader_turn',
                id: 'seminar-chat-control-runtime-merge:role-critical-0:user-input:1',
                agentRunId:
                    'seminar-chat-control-runtime-merge:role-critical-0',
                parentRunId: 'seminar-chat-control-runtime-merge',
                roleId: 'critical',
                label: 'send-input',
                status: 'pending',
                text: '请先解释这里还缺哪条原文证据。',
              ),
              AiSeminarRunCardMessagePart(
                type: 'agent_status',
                id: 'seminar-chat-control-runtime-merge:role-critical-0:status:waiting_input',
                agentRunId:
                    'seminar-chat-control-runtime-merge:role-critical-0',
                parentRunId: 'seminar-chat-control-runtime-merge',
                roleId: 'critical',
                label: 'role-waiting-input',
                text: 'Critical is waiting for input.',
                actionIds: ['close-agent'],
              ),
            ],
          ),
        );

    final updated = await container
        .read(aiChatProvider.notifier)
        .updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-control-runtime-merge',
          status: 'completed',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'role_turn',
                id: 'seminar-chat-control-runtime-merge:role-critical-0:result',
                agentRunId:
                    'seminar-chat-control-runtime-merge:role-critical-0',
                parentRunId: 'seminar-chat-control-runtime-merge',
                roleId: 'critical',
                text: 'Critical result without consuming input.',
              ),
            ],
          ),
        );

    expect(updated, isTrue);
    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final readerTurns = card?.snapshot?.messageParts
        .where((part) =>
            part.type == 'reader_turn' &&
            part.label == 'send-input' &&
            part.roleId == 'critical')
        .toList(growable: false);
    expect(readerTurns, hasLength(1));
    expect(readerTurns?.single.status, 'cancelled');
    expect(readerTurns?.single.completedAt, isNotNull);
    expect(readerTurns?.single.text, '请先解释这里还缺哪条原文证据。');
    expect(
      card?.snapshot?.messageParts
          .singleWhere((part) => part.type == 'role_turn')
          .text,
      'Critical result without consuming input.',
    );
  });

  test('runtime snapshot does not downgrade terminal reader control status',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-control-no-downgrade-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-control-no-downgrade',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-control-no-downgrade',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-control-no-downgrade',
          status: 'completed',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'reader_turn',
                id: 'seminar-chat-control-no-downgrade:role-critical-0:user-input:1',
                agentRunId: 'seminar-chat-control-no-downgrade:role-critical-0',
                parentRunId: 'seminar-chat-control-no-downgrade',
                roleId: 'critical',
                label: 'send-input',
                status: 'cancelled',
                text: '请先解释这里还缺哪条原文证据。',
                completedAt: 1717516803000,
              ),
              AiSeminarRunCardMessagePart(
                type: 'role_turn',
                id: 'seminar-chat-control-no-downgrade:role-critical-0:result',
                agentRunId: 'seminar-chat-control-no-downgrade:role-critical-0',
                parentRunId: 'seminar-chat-control-no-downgrade',
                roleId: 'critical',
                text: 'Critical result after cancellation.',
              ),
            ],
          ),
        );

    final updated = await container
        .read(aiChatProvider.notifier)
        .updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-control-no-downgrade',
          status: 'completed',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'reader_turn',
                id: 'seminar-chat-control-no-downgrade:role-critical-0:user-input:1',
                agentRunId: 'seminar-chat-control-no-downgrade:role-critical-0',
                parentRunId: 'seminar-chat-control-no-downgrade',
                roleId: 'critical',
                label: 'send-input',
                status: 'pending',
                text: '请先解释这里还缺哪条原文证据。',
              ),
              AiSeminarRunCardMessagePart(
                type: 'role_turn',
                id: 'seminar-chat-control-no-downgrade:role-critical-0:result',
                agentRunId: 'seminar-chat-control-no-downgrade:role-critical-0',
                parentRunId: 'seminar-chat-control-no-downgrade',
                roleId: 'critical',
                text: 'Critical result after cancellation.',
              ),
            ],
          ),
        );

    expect(updated, isTrue);
    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final readerTurns = card?.snapshot?.messageParts
        .where((part) =>
            part.type == 'reader_turn' &&
            part.label == 'send-input' &&
            part.roleId == 'critical')
        .toList(growable: false);
    expect(readerTurns, hasLength(1));
    expect(readerTurns?.single.status, 'cancelled');
    expect(readerTurns?.single.completedAt, 1717516803000);
  });

  test(
      'runtime snapshot does not resurrect stale pending input after retry completion',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-retry-input-stale-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-retry-input-stale',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-retry-input-stale',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-retry-input-stale',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'reader_turn',
                id: 'seminar-chat-retry-input-stale:role-critical-0:retry-request:1',
                agentRunId: 'seminar-chat-retry-input-stale:role-critical-0',
                parentRunId: 'seminar-chat-retry-input-stale',
                roleId: 'critical',
                label: 'retry-agent-control',
                status: 'completed',
                text: 'Retry requested.',
                completedAt: 1717516803000,
              ),
              AiSeminarRunCardMessagePart(
                type: 'role_turn',
                id: 'seminar-chat-retry-input-stale:role-critical-0:result',
                agentRunId: 'seminar-chat-retry-input-stale:role-critical-0',
                parentRunId: 'seminar-chat-retry-input-stale',
                roleId: 'critical',
                text: 'Critical result after retry.',
              ),
            ],
          ),
        );

    final updated = await container
        .read(aiChatProvider.notifier)
        .updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-retry-input-stale',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'reader_turn',
                id: 'seminar-chat-retry-input-stale:role-critical-0:user-input:stale',
                agentRunId: 'seminar-chat-retry-input-stale:role-critical-0',
                parentRunId: 'seminar-chat-retry-input-stale',
                roleId: 'critical',
                label: 'send-input',
                status: 'pending',
                text: '旧输入不应该盖过已处理的重试。',
              ),
            ],
          ),
        );

    expect(updated, isTrue);
    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final readerTurns = card?.snapshot?.messageParts
        .where(
            (part) => part.type == 'reader_turn' && part.roleId == 'critical')
        .toList(growable: false);

    expect(readerTurns, hasLength(1));
    expect(readerTurns?.single.label, 'retry-agent-control');
    expect(readerTurns?.single.status, 'completed');
    expect(readerTurns?.single.completedAt, 1717516803000);
  });

  test('runtime snapshot keeps completed retry when stale error status returns',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-retry-error-stale-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-retry-error-stale',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-retry-error-stale',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-retry-error-stale',
          status: 'completed',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'reader_turn',
                id: 'seminar-chat-retry-error-stale:role-critical-0:retry-request:1',
                agentRunId: 'seminar-chat-retry-error-stale:role-critical-0',
                parentRunId: 'seminar-chat-retry-error-stale',
                roleId: 'critical',
                label: 'retry-agent-control',
                status: 'completed',
                text: 'Retry requested.',
                completedAt: 1717516803000,
              ),
              AiSeminarRunCardMessagePart(
                type: 'role_turn',
                id: 'seminar-chat-retry-error-stale:role-critical-0:result',
                agentRunId: 'seminar-chat-retry-error-stale:role-critical-0',
                parentRunId: 'seminar-chat-retry-error-stale',
                roleId: 'critical',
                text: 'Critical result after retry.',
              ),
            ],
          ),
        );

    final updated = await container
        .read(aiChatProvider.notifier)
        .updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-retry-error-stale',
          status: 'completed',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'agent_status',
                id: 'seminar-chat-retry-error-stale:role-critical-0:status:errored',
                agentRunId: 'seminar-chat-retry-error-stale:role-critical-0',
                parentRunId: 'seminar-chat-retry-error-stale',
                roleId: 'critical',
                label: 'role-error',
                text: 'Stale provider timeout.',
                actionIds: ['retry-agent-control'],
              ),
            ],
          ),
        );

    expect(updated, isTrue);
    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final readerTurns = card?.snapshot?.messageParts
        .where(
            (part) => part.type == 'reader_turn' && part.roleId == 'critical')
        .toList(growable: false);
    final roleTurns = card?.snapshot?.messageParts
        .where((part) => part.type == 'role_turn' && part.roleId == 'critical')
        .toList(growable: false);
    final statusParts = card?.snapshot?.messageParts
        .where(
            (part) => part.type == 'agent_status' && part.roleId == 'critical')
        .toList(growable: false);

    expect(readerTurns, hasLength(1));
    expect(readerTurns?.single.label, 'retry-agent-control');
    expect(readerTurns?.single.status, 'completed');
    expect(readerTurns?.single.completedAt, 1717516803000);
    expect(roleTurns, hasLength(1));
    expect(roleTurns?.single.text, 'Critical result after retry.');
    for (final statusPart
        in statusParts ?? const <AiSeminarRunCardMessagePart>[]) {
      expect(statusPart.actionIds, isNot(contains('retry-agent-control')));
    }
  });

  test('loadHistoryEntry marks stale pending wait after graph result completed',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-wait-result-replay-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-wait-result-replay',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-wait-result-replay',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-wait-result-replay',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'reader_turn',
                id: 'seminar-chat-wait-result-replay:role-critical-0:wait-request:snapshot',
                agentRunId: 'seminar-chat-wait-result-replay:role-critical-0',
                parentRunId: 'seminar-chat-wait-result-replay',
                roleId: 'critical',
                label: 'wait-agent',
                status: 'pending',
                text: '等待批判者完成。',
              ),
            ],
          ),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: 'seminar-chat-wait-result-replay:role-critical-0:result',
      runId: 'seminar-chat-wait-result-replay:role-critical-0',
      parentRunId: 'seminar-chat-wait-result-replay',
      type: AgentRunEventType.result,
      createdAt: DateTime.utc(2026, 6, 5, 1, 30),
      roleId: 'critical',
      nickname: 'Critical',
      result: 'Critical completed response after wait.',
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final waitTurns = restoredCard?.snapshot?.messageParts
        .where(
          (part) =>
              part.type == 'reader_turn' &&
              part.roleId == 'critical' &&
              part.label == 'wait-agent',
        )
        .toList(growable: false);
    final roleTurns = restoredCard?.snapshot?.messageParts
        .where(
          (part) => part.type == 'role_turn' && part.roleId == 'critical',
        )
        .toList(growable: false);

    expect(waitTurns, hasLength(1));
    expect(waitTurns?.single.status, 'completed');
    expect(waitTurns?.single.completedAt, isNotNull);
    expect(roleTurns, hasLength(1));
    expect(roleTurns?.single.text, 'Critical completed response after wait.');
  });

  test('loadHistoryEntry marks stale pending wait after graph error completed',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-wait-error-replay-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-wait-error-replay',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-wait-error-replay',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-wait-error-replay',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'reader_turn',
                id: 'seminar-chat-wait-error-replay:role-critical-0:wait-request:snapshot',
                agentRunId: 'seminar-chat-wait-error-replay:role-critical-0',
                parentRunId: 'seminar-chat-wait-error-replay',
                roleId: 'critical',
                label: 'wait-agent',
                status: 'pending',
                text: '等待批判者完成。',
              ),
            ],
          ),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId: 'seminar-chat-wait-error-replay:role-critical-0:error',
      runId: 'seminar-chat-wait-error-replay:role-critical-0',
      parentRunId: 'seminar-chat-wait-error-replay',
      type: AgentRunEventType.error,
      createdAt: DateTime.utc(2026, 6, 5, 1, 45),
      roleId: 'critical',
      nickname: 'Critical',
      error: 'provider timeout',
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final waitTurns = restoredCard?.snapshot?.messageParts
        .where(
          (part) =>
              part.type == 'reader_turn' &&
              part.roleId == 'critical' &&
              part.label == 'wait-agent',
        )
        .toList(growable: false);
    final statusParts = restoredCard?.snapshot?.messageParts
        .where(
          (part) => part.type == 'agent_status' && part.roleId == 'critical',
        )
        .toList(growable: false);

    expect(waitTurns, hasLength(1));
    expect(waitTurns?.single.status, 'completed');
    expect(waitTurns?.single.completedAt, isNotNull);
    expect(statusParts, hasLength(1));
    expect(statusParts?.single.label, 'role-error');
    expect(statusParts?.single.text, contains('provider timeout'));
  });

  test(
      'loadHistoryEntry marks stale pending wait after graph shutdown completed',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-wait-shutdown-replay-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-wait-shutdown-replay',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-wait-shutdown-replay',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-wait-shutdown-replay',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'reader_turn',
                id: 'seminar-chat-wait-shutdown-replay:role-critical-0:wait-request:snapshot',
                agentRunId: 'seminar-chat-wait-shutdown-replay:role-critical-0',
                parentRunId: 'seminar-chat-wait-shutdown-replay',
                roleId: 'critical',
                label: 'wait-agent',
                status: 'pending',
                text: '等待批判者完成。',
              ),
            ],
          ),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId:
          'seminar-chat-wait-shutdown-replay:role-critical-0:status:shutdown',
      runId: 'seminar-chat-wait-shutdown-replay:role-critical-0',
      parentRunId: 'seminar-chat-wait-shutdown-replay',
      type: AgentRunEventType.status,
      createdAt: DateTime.utc(2026, 6, 5, 2),
      status: SubAgentRunStatus.shutdown,
      roleId: 'critical',
      nickname: 'Critical',
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final waitTurns = restoredCard?.snapshot?.messageParts
        .where(
          (part) =>
              part.type == 'reader_turn' &&
              part.roleId == 'critical' &&
              part.label == 'wait-agent',
        )
        .toList(growable: false);
    final statusParts = restoredCard?.snapshot?.messageParts
        .where(
          (part) => part.type == 'agent_status' && part.roleId == 'critical',
        )
        .toList(growable: false);

    expect(waitTurns, hasLength(1));
    expect(waitTurns?.single.status, 'completed');
    expect(waitTurns?.single.completedAt, isNotNull);
    expect(statusParts, hasLength(1));
    expect(statusParts?.single.label, 'role-shutdown');
  });

  test(
      'loadHistoryEntry marks stale pending wait after graph interrupted completed',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-wait-interrupted-replay-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-wait-interrupted-replay',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-wait-interrupted-replay',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-wait-interrupted-replay',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'reader_turn',
                id: 'seminar-chat-wait-interrupted-replay:role-critical-0:wait-request:snapshot',
                agentRunId:
                    'seminar-chat-wait-interrupted-replay:role-critical-0',
                parentRunId: 'seminar-chat-wait-interrupted-replay',
                roleId: 'critical',
                label: 'wait-agent',
                status: 'pending',
                text: '等待批判者完成。',
              ),
            ],
          ),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId:
          'seminar-chat-wait-interrupted-replay:role-critical-0:status:interrupted',
      runId: 'seminar-chat-wait-interrupted-replay:role-critical-0',
      parentRunId: 'seminar-chat-wait-interrupted-replay',
      type: AgentRunEventType.status,
      createdAt: DateTime.utc(2026, 6, 5, 2, 15),
      status: SubAgentRunStatus.interrupted,
      roleId: 'critical',
      nickname: 'Critical',
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final waitTurns = restoredCard?.snapshot?.messageParts
        .where(
          (part) =>
              part.type == 'reader_turn' &&
              part.roleId == 'critical' &&
              part.label == 'wait-agent',
        )
        .toList(growable: false);
    final statusParts = restoredCard?.snapshot?.messageParts
        .where(
          (part) => part.type == 'agent_status' && part.roleId == 'critical',
        )
        .toList(growable: false);

    expect(waitTurns, hasLength(1));
    expect(waitTurns?.single.status, 'completed');
    expect(waitTurns?.single.completedAt, isNotNull);
    expect(statusParts, hasLength(1));
    expect(statusParts?.single.label, 'role-interrupted');
    expect(statusParts?.single.actionIds, contains('resume-agent'));
  });

  test(
      'loadHistoryEntry cancels stale pending reader control after graph shutdown',
      () async {
    final tempDir = Directory.systemTemp
        .createTempSync('ai-chat-reader-control-shutdown-replay-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-reader-control-shutdown-replay',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-reader-control-shutdown-replay',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-reader-control-shutdown-replay',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'reader_turn',
                id: 'seminar-chat-reader-control-shutdown-replay:role-critical-0:user-input:snapshot',
                agentRunId:
                    'seminar-chat-reader-control-shutdown-replay:role-critical-0',
                parentRunId: 'seminar-chat-reader-control-shutdown-replay',
                roleId: 'critical',
                label: 'send-input',
                status: 'pending',
                text: '请先解释这里还缺哪条原文证据。',
              ),
            ],
          ),
        );

    final graphStore = AgentRunGraphStore();
    await graphStore.upsertEvent(AgentRunEvent(
      eventId:
          'seminar-chat-reader-control-shutdown-replay:role-critical-0:status:shutdown',
      runId: 'seminar-chat-reader-control-shutdown-replay:role-critical-0',
      parentRunId: 'seminar-chat-reader-control-shutdown-replay',
      type: AgentRunEventType.status,
      createdAt: DateTime.utc(2026, 6, 5, 2, 30),
      status: SubAgentRunStatus.shutdown,
      roleId: 'critical',
      nickname: 'Critical',
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final readerTurns = restoredCard?.snapshot?.messageParts
        .where(
          (part) =>
              part.type == 'reader_turn' &&
              part.roleId == 'critical' &&
              part.label == 'send-input',
        )
        .toList(growable: false);
    final statusParts = restoredCard?.snapshot?.messageParts
        .where(
          (part) => part.type == 'agent_status' && part.roleId == 'critical',
        )
        .toList(growable: false);

    expect(readerTurns, hasLength(1));
    expect(readerTurns?.single.status, 'cancelled');
    expect(readerTurns?.single.completedAt, isNotNull);
    expect(statusParts, hasLength(1));
    expect(statusParts?.single.label, 'role-shutdown');
  });

  test(
      'sendSeminarRunCardAgentInput records reader input for a waiting child run',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-send-input-agent-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-send-input-agent',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-send-input-agent',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-send-input-agent',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'director_state',
                id: 'seminar-chat-send-input-agent:role-critical-0:status:waiting_input',
                roleId: 'critical',
                label: 'role-waiting-input',
                text: 'Critical is waiting for input.',
                actionIds: ['send-input', 'close-agent'],
              ),
            ],
          ),
        );

    final startedAt = DateTime.utc(2026, 6, 4, 19);
    final graphStore = AgentRunGraphStore();
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-send-input-agent',
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: SubAgentRunStatus.running,
      task: '这个概念怎么理解？',
      startedAt: startedAt,
    ));
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-send-input-agent:role-critical-0',
      parentRunId: 'seminar-chat-send-input-agent',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.waitingInput,
      task: '这个概念怎么理解？',
      startedAt: startedAt.add(const Duration(seconds: 1)),
    ));

    final sent = await container
        .read(aiChatProvider.notifier)
        .sendSeminarRunCardAgentInput(
          seminarSessionId: 'seminar-chat-send-input-agent',
          agentRunId: 'seminar-chat-send-input-agent:role-critical-0',
          inputText: '请先解释这里还缺哪条原文证据。',
          now: startedAt.add(const Duration(seconds: 8)),
        );

    expect(sent, isTrue);
    final events = await graphStore.listEvents(
      'seminar-chat-send-input-agent:role-critical-0',
    );
    expect(events.last.type, AgentRunEventType.userInput);
    expect(events.last.delta, '请先解释这里还缺哪条原文证据。');
    final duplicateSent = await container
        .read(aiChatProvider.notifier)
        .sendSeminarRunCardAgentInput(
          seminarSessionId: 'seminar-chat-send-input-agent',
          agentRunId: 'seminar-chat-send-input-agent:role-critical-0',
          inputText: '请先解释这里还缺哪条原文证据。',
          now: startedAt.add(const Duration(seconds: 9)),
        );
    expect(duplicateSent, isTrue);
    final inputEvents = (await graphStore.listEvents(
      'seminar-chat-send-input-agent:role-critical-0',
    ))
        .where((event) => event.type == AgentRunEventType.userInput)
        .toList(growable: false);
    expect(inputEvents, hasLength(1));
    expect(inputEvents.single.delta, '请先解释这里还缺哪条原文证据。');

    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final readerTurns = card?.snapshot?.messageParts
        .where(
          (part) => part.type == 'reader_turn' && part.roleId == 'critical',
        )
        .toList(growable: false);
    final readerTurn = readerTurns?.single;
    final statusPart = card?.snapshot?.messageParts.singleWhere(
      (part) =>
          (part.type == 'director_state' || part.type == 'agent_status') &&
          part.roleId == 'critical',
    );

    expect(readerTurns, hasLength(1));
    expect(readerTurn?.label, 'send-input');
    expect(readerTurn?.text, '请先解释这里还缺哪条原文证据。');
    expect(statusPart?.actionIds, contains('close-agent'));
    expect(statusPart?.actionIds, isNot(contains('send-input')));
  });

  test('sendSeminarRunCardAgentInput refreshes a stale completed child run',
      () async {
    final tempDir = Directory.systemTemp
        .createTempSync('ai-chat-send-input-completed-agent-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-send-input-completed-agent',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-send-input-completed-agent',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-send-input-completed-agent',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'agent_status',
                id: 'seminar-chat-send-input-completed-agent:role-critical-0:status:waiting_input',
                agentRunId:
                    'seminar-chat-send-input-completed-agent:role-critical-0',
                parentRunId: 'seminar-chat-send-input-completed-agent',
                roleId: 'critical',
                label: 'role-waiting-input',
                text: 'Critical is waiting for input.',
                actionIds: ['send-input', 'close-agent'],
              ),
            ],
          ),
        );

    final startedAt = DateTime.utc(2026, 6, 4, 19, 30);
    final graphStore = AgentRunGraphStore();
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-send-input-completed-agent',
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: SubAgentRunStatus.running,
      task: '这个概念怎么理解？',
      startedAt: startedAt,
    ));
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-send-input-completed-agent:role-critical-0',
      parentRunId: 'seminar-chat-send-input-completed-agent',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.completed,
      task: '这个概念怎么理解？',
      startedAt: startedAt.add(const Duration(seconds: 1)),
      finishedAt: startedAt.add(const Duration(seconds: 5)),
      result: 'Critical already answered.',
    ));

    final sent = await container
        .read(aiChatProvider.notifier)
        .sendSeminarRunCardAgentInput(
          seminarSessionId: 'seminar-chat-send-input-completed-agent',
          agentRunId: 'seminar-chat-send-input-completed-agent:role-critical-0',
          inputText: '这条输入已经过期了。',
          now: startedAt.add(const Duration(seconds: 8)),
        );

    expect(sent, isTrue);
    final userInputEvents = (await graphStore.listEvents(
      'seminar-chat-send-input-completed-agent:role-critical-0',
    ))
        .where((event) => event.type == AgentRunEventType.userInput)
        .toList(growable: false);
    expect(userInputEvents, isEmpty);

    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final statusParts = card?.snapshot?.messageParts
        .where(
          (part) => part.type == 'agent_status' && part.roleId == 'critical',
        )
        .toList(growable: false);
    final roleTurn = card?.snapshot?.messageParts.singleWhere(
      (part) => part.type == 'role_turn' && part.roleId == 'critical',
    );

    expect(statusParts, hasLength(1));
    expect(statusParts?.single.label, 'role-completed');
    expect(statusParts?.single.actionIds, isEmpty);
    expect(roleTurn?.text, 'Critical already answered.');
  });

  test(
      'resumeSeminarRunCardAgent records a resume request without faking child progress',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-resume-agent-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-resume-agent',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-resume-agent',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-resume-agent',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'director_state',
                id: 'seminar-chat-resume-agent:role-critical-0:status:interrupted',
                roleId: 'critical',
                label: 'role-interrupted',
                text: 'Critical was interrupted.',
                actionIds: ['resume-agent', 'close-agent'],
              ),
            ],
          ),
        );

    final startedAt = DateTime.utc(2026, 6, 4, 20);
    final graphStore = AgentRunGraphStore();
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-resume-agent',
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: SubAgentRunStatus.running,
      task: '这个概念怎么理解？',
      startedAt: startedAt,
    ));
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-resume-agent:role-critical-0',
      parentRunId: 'seminar-chat-resume-agent',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.interrupted,
      task: '这个概念怎么理解？',
      startedAt: startedAt.add(const Duration(seconds: 1)),
    ));

    final resumed =
        await container.read(aiChatProvider.notifier).resumeSeminarRunCardAgent(
              seminarSessionId: 'seminar-chat-resume-agent',
              agentRunId: 'seminar-chat-resume-agent:role-critical-0',
              now: startedAt.add(const Duration(seconds: 8)),
            );

    expect(resumed, isTrue);
    final events = await graphStore.listEvents(
      'seminar-chat-resume-agent:role-critical-0',
    );
    expect(events.last.type, AgentRunEventType.resumeRequest);
    expect(events.last.delta, isNull);
    final duplicateResume =
        await container.read(aiChatProvider.notifier).resumeSeminarRunCardAgent(
              seminarSessionId: 'seminar-chat-resume-agent',
              agentRunId: 'seminar-chat-resume-agent:role-critical-0',
              now: startedAt.add(const Duration(seconds: 9)),
            );
    expect(duplicateResume, isTrue);
    final resumeEvents = (await graphStore.listEvents(
      'seminar-chat-resume-agent:role-critical-0',
    ))
        .where((event) => event.type == AgentRunEventType.resumeRequest)
        .toList(growable: false);
    expect(resumeEvents, hasLength(1));
    final childRun = await graphStore.getRun(
      'seminar-chat-resume-agent:role-critical-0',
    );
    expect(childRun?.status, SubAgentRunStatus.interrupted);

    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final readerTurns = card?.snapshot?.messageParts
        .where(
          (part) => part.type == 'reader_turn' && part.roleId == 'critical',
        )
        .toList(growable: false);
    final statusPart = card?.snapshot?.messageParts.singleWhere(
      (part) => part.type == 'agent_status' && part.roleId == 'critical',
    );

    expect(readerTurns, hasLength(1));
    expect(readerTurns?.single.label, 'resume-agent');
    expect(readerTurns?.single.text, isNull);
    expect(statusPart?.label, 'role-interrupted');
    expect(statusPart?.actionIds, contains('close-agent'));
    expect(statusPart?.actionIds, isNot(contains('resume-agent')));
  });

  test('resumeSeminarRunCardAgent refreshes a stale completed child run',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-resume-completed-agent-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-resume-completed-agent',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-resume-completed-agent',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-resume-completed-agent',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'agent_status',
                id: 'seminar-chat-resume-completed-agent:role-critical-0:status:interrupted',
                agentRunId:
                    'seminar-chat-resume-completed-agent:role-critical-0',
                parentRunId: 'seminar-chat-resume-completed-agent',
                roleId: 'critical',
                label: 'role-interrupted',
                text: 'Critical was interrupted.',
                actionIds: ['resume-agent', 'close-agent'],
              ),
            ],
          ),
        );

    final startedAt = DateTime.utc(2026, 6, 4, 20, 30);
    final graphStore = AgentRunGraphStore();
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-resume-completed-agent',
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: SubAgentRunStatus.running,
      task: '这个概念怎么理解？',
      startedAt: startedAt,
    ));
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-resume-completed-agent:role-critical-0',
      parentRunId: 'seminar-chat-resume-completed-agent',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.completed,
      task: '这个概念怎么理解？',
      startedAt: startedAt.add(const Duration(seconds: 1)),
      finishedAt: startedAt.add(const Duration(seconds: 7)),
      result: 'Critical completed before resume.',
    ));

    final resumed =
        await container.read(aiChatProvider.notifier).resumeSeminarRunCardAgent(
              seminarSessionId: 'seminar-chat-resume-completed-agent',
              agentRunId: 'seminar-chat-resume-completed-agent:role-critical-0',
              now: startedAt.add(const Duration(seconds: 8)),
            );

    expect(resumed, isTrue);
    final resumeEvents = (await graphStore.listEvents(
      'seminar-chat-resume-completed-agent:role-critical-0',
    ))
        .where((event) => event.type == AgentRunEventType.resumeRequest)
        .toList(growable: false);
    expect(resumeEvents, isEmpty);

    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final statusParts = card?.snapshot?.messageParts
        .where(
          (part) => part.type == 'agent_status' && part.roleId == 'critical',
        )
        .toList(growable: false);
    final roleTurn = card?.snapshot?.messageParts.singleWhere(
      (part) => part.type == 'role_turn' && part.roleId == 'critical',
    );

    expect(statusParts, hasLength(1));
    expect(statusParts?.single.label, 'role-completed');
    expect(statusParts?.single.actionIds, isEmpty);
    expect(roleTurn?.text, 'Critical completed before resume.');
  });

  test(
      'retrySeminarRunCardAgent records a retry request without faking child progress',
      () async {
    final tempDir = Directory.systemTemp.createTempSync('ai-chat-retry-agent-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-retry-agent',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-retry-agent',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-retry-agent',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'agent_status',
                id: 'seminar-chat-retry-agent:role-critical-0:status:errored',
                agentRunId: 'seminar-chat-retry-agent:role-critical-0',
                parentRunId: 'seminar-chat-retry-agent',
                roleId: 'critical',
                label: 'role-error',
                text: 'Critical failed.',
                actionIds: ['retry-agent-control'],
              ),
            ],
          ),
        );

    final startedAt = DateTime.utc(2026, 6, 4, 21);
    final graphStore = AgentRunGraphStore();
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-retry-agent',
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: SubAgentRunStatus.running,
      task: '这个概念怎么理解？',
      startedAt: startedAt,
    ));
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-retry-agent:role-critical-0',
      parentRunId: 'seminar-chat-retry-agent',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.errored,
      task: '这个概念怎么理解？',
      startedAt: startedAt.add(const Duration(seconds: 1)),
      finishedAt: startedAt.add(const Duration(seconds: 5)),
      error: 'provider timeout',
    ));

    final retried =
        await container.read(aiChatProvider.notifier).retrySeminarRunCardAgent(
              seminarSessionId: 'seminar-chat-retry-agent',
              agentRunId: 'seminar-chat-retry-agent:role-critical-0',
              now: startedAt.add(const Duration(seconds: 8)),
            );

    expect(retried, isTrue);
    final events = await graphStore.listEvents(
      'seminar-chat-retry-agent:role-critical-0',
    );
    expect(events.last.type, AgentRunEventType.retryRequest);
    expect(events.last.delta, isNull);
    final duplicateRetry =
        await container.read(aiChatProvider.notifier).retrySeminarRunCardAgent(
              seminarSessionId: 'seminar-chat-retry-agent',
              agentRunId: 'seminar-chat-retry-agent:role-critical-0',
              now: startedAt.add(const Duration(seconds: 9)),
            );
    expect(duplicateRetry, isTrue);
    final retryEvents = (await graphStore.listEvents(
      'seminar-chat-retry-agent:role-critical-0',
    ))
        .where((event) => event.type == AgentRunEventType.retryRequest)
        .toList(growable: false);
    expect(retryEvents, hasLength(1));
    final childRun = await graphStore.getRun(
      'seminar-chat-retry-agent:role-critical-0',
    );
    expect(childRun?.status, SubAgentRunStatus.errored);

    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final readerTurns = card?.snapshot?.messageParts
        .where(
          (part) => part.type == 'reader_turn' && part.roleId == 'critical',
        )
        .toList(growable: false);
    final statusParts = card?.snapshot?.messageParts
        .where(
          (part) => part.type == 'agent_status' && part.roleId == 'critical',
        )
        .toList(growable: false);

    expect(readerTurns, hasLength(1));
    expect(readerTurns?.single.label, 'retry-agent-control');
    expect(readerTurns?.single.text, isNull);
    expect(statusParts?.map((part) => part.label), contains('role-error'));
    expect(statusParts?.map((part) => part.label),
        isNot(contains('role-running')));
    expect(
      statusParts?.expand((part) => part.actionIds),
      isNot(contains('retry-agent-control')),
    );
  });

  test('retrySeminarRunCardAgent refreshes a stale completed child run',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-retry-completed-agent-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-retry-completed-agent',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-retry-completed-agent',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-retry-completed-agent',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'agent_status',
                id: 'seminar-chat-retry-completed-agent:role-critical-0:status:errored',
                agentRunId:
                    'seminar-chat-retry-completed-agent:role-critical-0',
                parentRunId: 'seminar-chat-retry-completed-agent',
                roleId: 'critical',
                label: 'role-error',
                text: 'Critical failed.',
                actionIds: ['retry-agent-control'],
              ),
            ],
          ),
        );

    final startedAt = DateTime.utc(2026, 6, 4, 21, 30);
    final graphStore = AgentRunGraphStore();
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-retry-completed-agent',
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: SubAgentRunStatus.running,
      task: '这个概念怎么理解？',
      startedAt: startedAt,
    ));
    await graphStore.upsertRun(AgentRunRecord(
      runId: 'seminar-chat-retry-completed-agent:role-critical-0',
      parentRunId: 'seminar-chat-retry-completed-agent',
      source: 'seminar',
      profile: 'critical',
      roleId: 'critical',
      nickname: 'Critical',
      status: SubAgentRunStatus.completed,
      task: '这个概念怎么理解？',
      startedAt: startedAt.add(const Duration(seconds: 1)),
      finishedAt: startedAt.add(const Duration(seconds: 9)),
      result: 'Critical completed before retry.',
    ));

    final retried =
        await container.read(aiChatProvider.notifier).retrySeminarRunCardAgent(
              seminarSessionId: 'seminar-chat-retry-completed-agent',
              agentRunId: 'seminar-chat-retry-completed-agent:role-critical-0',
              now: startedAt.add(const Duration(seconds: 10)),
            );

    expect(retried, isTrue);
    final retryEvents = (await graphStore.listEvents(
      'seminar-chat-retry-completed-agent:role-critical-0',
    ))
        .where((event) => event.type == AgentRunEventType.retryRequest)
        .toList(growable: false);
    expect(retryEvents, isEmpty);

    final card = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final statusParts = card?.snapshot?.messageParts
        .where(
          (part) => part.type == 'agent_status' && part.roleId == 'critical',
        )
        .toList(growable: false);
    final roleTurn = card?.snapshot?.messageParts.singleWhere(
      (part) => part.type == 'role_turn' && part.roleId == 'critical',
    );

    expect(statusParts, hasLength(1));
    expect(statusParts?.single.label, 'role-completed');
    expect(statusParts?.single.actionIds, isEmpty);
    expect(roleTurn?.text, 'Critical completed before retry.');
  });

  test(
      'loadHistoryEntry drops stale pending reader control after graph ack replay',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-reader-control-replay-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-reader-control-replay',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-reader-control-replay',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-reader-control-replay',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'reader_turn',
                id: 'seminar-chat-reader-control-replay:role-critical-0:user-input:snapshot-old',
                agentRunId:
                    'seminar-chat-reader-control-replay:role-critical-0',
                parentRunId: 'seminar-chat-reader-control-replay',
                roleId: 'critical',
                label: 'send-input',
                status: 'pending',
                text: '旧的读者输入还没有处理。',
              ),
            ],
          ),
        );

    final acknowledgedAt = DateTime.utc(2026, 6, 5, 15, 0, 4);
    await AgentRunGraphStore().upsertEvent(AgentRunEvent(
      eventId:
          'seminar-chat-reader-control-replay:role-critical-0:retry-request:graph',
      runId: 'seminar-chat-reader-control-replay:role-critical-0',
      parentRunId: 'seminar-chat-reader-control-replay',
      type: AgentRunEventType.retryRequest,
      createdAt: DateTime.utc(2026, 6, 5, 15, 0, 2),
      roleId: 'critical',
      nickname: 'Critical',
      delta: 'Retry requested.',
      acknowledgedAt: acknowledgedAt,
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final readerTurns = restoredCard?.snapshot?.messageParts
        .where(
          (part) => part.type == 'reader_turn' && part.roleId == 'critical',
        )
        .toList(growable: false);

    expect(readerTurns, hasLength(1));
    expect(readerTurns?.single.label, 'retry-agent-control');
    expect(readerTurns?.single.status, 'completed');
    expect(
        readerTurns?.single.completedAt, acknowledgedAt.millisecondsSinceEpoch);
  });

  test('loadHistoryEntry suppresses stale pending control action ids',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-pending-action-replay-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-pending-action-replay',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-pending-action-replay',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-pending-action-replay',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'agent_status',
                id: 'seminar-chat-pending-action-replay:role-critical-0:status:waiting_input',
                agentRunId:
                    'seminar-chat-pending-action-replay:role-critical-0',
                parentRunId: 'seminar-chat-pending-action-replay',
                roleId: 'critical',
                label: 'role-waiting-input',
                text: 'Critical is waiting for input.',
                actionIds: ['send-input', 'close-agent'],
              ),
              AiSeminarRunCardMessagePart(
                type: 'reader_turn',
                id: 'seminar-chat-pending-action-replay:role-critical-0:user-input:snapshot-old',
                agentRunId:
                    'seminar-chat-pending-action-replay:role-critical-0',
                parentRunId: 'seminar-chat-pending-action-replay',
                roleId: 'critical',
                label: 'send-input',
                status: 'pending',
                text: '旧的读者输入还没有处理。',
              ),
            ],
          ),
        );

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final statusPart = restoredCard?.snapshot?.messageParts.singleWhere(
      (part) => part.type == 'agent_status' && part.roleId == 'critical',
    );
    final readerTurn = restoredCard?.snapshot?.messageParts.singleWhere(
      (part) => part.type == 'reader_turn' && part.roleId == 'critical',
    );

    expect(readerTurn?.label, 'send-input');
    expect(readerTurn?.status, 'pending');
    expect(statusPart?.actionIds, contains('close-agent'));
    expect(statusPart?.actionIds, isNot(contains('send-input')));
  });

  test(
      'loadHistoryEntry drops stale id-only pending reader control after graph ack replay',
      () async {
    final tempDir = Directory.systemTemp
        .createTempSync('ai-chat-reader-control-id-replay-');
    _mockPathProvider(tempDir.path);
    documentPath = tempDir.path;
    addTearDown(() {
      _mockPathProvider(null);
      documentPath = '';
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [ChatMessage.humanText('已有会话')],
      sessionId: 'session-seminar-reader-control-id-replay',
    );

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '这个概念怎么理解？',
          bookId: 7,
          seminarSessionId: 'seminar-chat-reader-control-id-replay',
        );

    await container.read(aiChatProvider.notifier).updateSeminarRunCardSnapshot(
          seminarSessionId: 'seminar-chat-reader-control-id-replay',
          status: 'running',
          snapshot: const AiSeminarRunCardSnapshot(
            messageParts: [
              AiSeminarRunCardMessagePart(
                type: 'reader_turn',
                id: 'seminar-chat-reader-control-id-replay:role-critical-0:user-input:snapshot-old',
                parentRunId: 'seminar-chat-reader-control-id-replay',
                roleId: 'critical',
                label: 'send-input',
                status: 'pending',
                text: '旧的 id-only 读者输入还没有处理。',
              ),
            ],
          ),
        );

    final acknowledgedAt = DateTime.utc(2026, 6, 5, 16, 0, 4);
    await AgentRunGraphStore().upsertEvent(AgentRunEvent(
      eventId:
          'seminar-chat-reader-control-id-replay:role-critical-0:retry-request:graph',
      runId: 'seminar-chat-reader-control-id-replay:role-critical-0',
      parentRunId: 'seminar-chat-reader-control-id-replay',
      type: AgentRunEventType.retryRequest,
      createdAt: DateTime.utc(2026, 6, 5, 16, 0, 2),
      roleId: 'critical',
      nickname: 'Critical',
      delta: 'Retry requested.',
      acknowledgedAt: acknowledgedAt,
    ));

    final history = await AiHistoryStore.readHistory();
    expect(history, hasLength(1));

    container.read(aiChatProvider.notifier).clear();
    container.read(aiChatProvider.notifier).loadHistoryEntry(history.single);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final restoredCard = container
        .read(aiChatProvider.notifier)
        .seminarRunCardForMessageIndex(2);
    final readerTurns = restoredCard?.snapshot?.messageParts
        .where(
          (part) => part.type == 'reader_turn' && part.roleId == 'critical',
        )
        .toList(growable: false);

    expect(readerTurns, hasLength(1));
    expect(readerTurns?.single.label, 'retry-agent-control');
    expect(readerTurns?.single.status, 'completed');
    expect(
        readerTurns?.single.completedAt, acknowledgedAt.millisecondsSinceEpoch);
  });

  test('appendSeminarRunCard ignores empty cards without source evidence',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-empty-seminar-card-');
    _mockPathProvider(tempDir.path);
    addTearDown(() {
      _mockPathProvider(null);
      tempDir.deleteSync(recursive: true);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);

    await container.read(aiChatProvider.notifier).appendSeminarRunCard(
          question: '   ',
          bookId: 7,
        );

    final history = await AiHistoryStore.readHistory();
    expect(history, isEmpty);
    expect(container.read(aiChatProvider.notifier).currentSessionId, isNull);
  });

  test('startStreaming coalesces rapid assistant chunk updates for scrolling',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-stream-throttle-');
    _mockPathProvider(tempDir.path);
    final controller = StreamController<String>();
    addTearDown(() async {
      _mockPathProvider(null);
      await controller.close();
      tempDir.deleteSync(recursive: true);
    });

    debugAiChatGenerateStreamOverride = (
      messages, {
      scope = AiRequestScope.chat,
      identifier,
      config,
      regenerate = false,
      useAgent = false,
      conversationId,
      ref,
    }) =>
        controller.stream;

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(aiChatProvider.future);

    final visibleAssistantUpdates = <String>[];
    final subscription = container.listen<AsyncValue<List<ChatMessage>>>(
      aiChatProvider,
      (_, next) {
        final messages = next.value;
        if (messages == null || messages.isEmpty) {
          return;
        }
        final last = messages.last;
        if (last is AIChatMessage) {
          visibleAssistantUpdates.add(last.contentAsString);
        }
      },
    );
    addTearDown(subscription.close);

    container
        .read(aiChatProvider.notifier)
        .startStreaming('Explain this', false);
    await Future<void>.delayed(Duration.zero);

    for (var i = 0; i < 20; i++) {
      controller.add('rapid-$i');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final earlyVisible = _latestAssistantText(container);
    expect(earlyVisible, isNot('rapid-19'));
    expect(
      visibleAssistantUpdates.where((text) => text.startsWith('rapid-')).length,
      lessThan(20),
    );

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(_latestAssistantText(container), isNot('rapid-19'));

    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(_latestAssistantText(container), 'rapid-19');
    await controller.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(aiChatStreamingProvider), isFalse);
  });

  test('startStreaming slows UI flushes while chat surface is hidden',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-stream-hidden-throttle-');
    _mockPathProvider(tempDir.path);
    final controller = StreamController<String>();
    addTearDown(() async {
      _mockPathProvider(null);
      await controller.close();
      tempDir.deleteSync(recursive: true);
    });

    debugAiChatGenerateStreamOverride = (
      messages, {
      scope = AiRequestScope.chat,
      identifier,
      config,
      regenerate = false,
      useAgent = false,
      conversationId,
      ref,
    }) =>
        controller.stream;

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(aiChatProvider.future);
    container.read(aiChatUiVisibleProvider.notifier).state = false;

    container
        .read(aiChatProvider.notifier)
        .startStreaming('Explain this in the background', false);
    await Future<void>.delayed(Duration.zero);

    for (var i = 0; i < 8; i++) {
      controller.add('hidden-$i');
    }
    await Future<void>.delayed(const Duration(milliseconds: 220));

    expect(_latestAssistantText(container), isNot('hidden-7'));

    container.read(aiChatUiVisibleProvider.notifier).state = true;
    container.read(aiChatProvider.notifier).flushPendingStreamingUi();
    await Future<void>.delayed(Duration.zero);

    expect(_latestAssistantText(container), 'hidden-7');
    await controller.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(aiChatStreamingProvider), isFalse);
  });

  test('startStreaming reschedules pending UI flush when chat becomes hidden',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-stream-hide-reschedule-');
    _mockPathProvider(tempDir.path);
    final controller = StreamController<String>();
    addTearDown(() async {
      _mockPathProvider(null);
      await controller.close();
      tempDir.deleteSync(recursive: true);
    });

    debugAiChatGenerateStreamOverride = (
      messages, {
      scope = AiRequestScope.chat,
      identifier,
      config,
      regenerate = false,
      useAgent = false,
      conversationId,
      ref,
    }) =>
        controller.stream;

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(aiChatProvider.future);

    container
        .read(aiChatProvider.notifier)
        .startStreaming('Explain this while hiding', false);
    await Future<void>.delayed(Duration.zero);

    controller.add('visible-0');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(_latestAssistantText(container), 'visible-0');

    controller.add('hidden-pending');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    container.read(aiChatProvider.notifier).setStreamingUiVisible(false);
    await Future<void>.delayed(const Duration(milliseconds: 220));

    expect(_latestAssistantText(container), 'visible-0');

    await Future<void>.delayed(const Duration(milliseconds: 850));
    expect(_latestAssistantText(container), 'hidden-pending');

    await controller.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(aiChatStreamingProvider), isFalse);
  });

  test('startStreaming flushes pending assistant text when stream finishes',
      () async {
    final tempDir =
        Directory.systemTemp.createTempSync('ai-chat-stream-completion-flush-');
    _mockPathProvider(tempDir.path);
    final controller = StreamController<String>();
    addTearDown(() async {
      _mockPathProvider(null);
      await controller.close();
      tempDir.deleteSync(recursive: true);
    });

    debugAiChatGenerateStreamOverride = (
      messages, {
      scope = AiRequestScope.chat,
      identifier,
      config,
      regenerate = false,
      useAgent = false,
      conversationId,
      ref,
    }) =>
        controller.stream;

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(aiChatProvider.future);

    container
        .read(aiChatProvider.notifier)
        .startStreaming('Explain this', false);
    await Future<void>.delayed(Duration.zero);

    controller.add('first');
    await Future<void>.delayed(Duration.zero);
    controller.add('final');
    await controller.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(_latestAssistantText(container), 'final');
    expect(container.read(aiChatStreamingProvider), isFalse);
  });
}

void _mockPathProvider(String? cachePath) {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          channel,
          cachePath == null
              ? null
              : (call) async {
                  if (call.method == 'getApplicationCacheDirectory') {
                    return cachePath;
                  }
                  return cachePath;
                });
}

void _configureAiProvider() {
  const providerId = 'openai';
  final provider = AiProviderMeta(
    id: providerId,
    name: 'OpenAI',
    type: AiProviderType.openaiCompatible,
    enabled: true,
    isBuiltIn: true,
    createdAt: 1,
    updatedAt: 1,
  );
  Prefs().selectedAiService = providerId;
  Prefs().aiProvidersV1 = [provider];
  Prefs().saveAiConfig(providerId, {
    'apiKey': 'test-key',
    'baseUrl': 'http://127.0.0.1.invalid/v1',
    'model': 'test-model',
  });
}

List<AiSeminarRunCardEvidenceSnapshot> _traceableSeminarArtifactEvidenceRefs() {
  return [
    AiSeminarRunCardEvidenceSnapshot(
      id: 'e1',
      title: 'Chapter 2',
      snippet: 'Working memory evidence.',
      sourceRef: SourceRef(
        bookId: 7,
        cfi: 'epubcfi(/6/2)',
        sourceKind: SourceRefKind.currentBookRag,
        sourceTextSnippet: 'Working memory evidence.',
      ),
    ),
  ];
}

String _latestAssistantText(ProviderContainer container) {
  final messages = container.read(aiChatProvider).value;
  expect(messages, isNotNull);
  expect(messages, isNotEmpty);
  final last = messages!.last;
  expect(last, isA<AIChatMessage>());
  return last.contentAsString;
}
