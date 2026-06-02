import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/main.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/models/ai_provider_meta.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/page/settings_page/ai_seminar_config.dart';
import 'package:papertok_reader/page/settings_page/ai_seminar_runtime.dart';
import 'package:papertok_reader/providers/ai_chat.dart';
import 'package:papertok_reader/providers/ai_seminar_runtime.dart';
import 'package:papertok_reader/service/ai/ai_history.dart';
import 'package:papertok_reader/service/ai/ai_seminar_runtime_service.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';
import 'package:papertok_reader/widgets/ai/ai_chat_stream.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Add-to-Chat Seminar opens inline runtime without changing active style',
    (tester) async {
      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-seminar-entry-');
      _mockPathProvider(tempDir.path);
      addTearDown(() {
        _mockPathProvider(null);
        tempDir.deleteSync(recursive: true);
      });

      const providerId = 'openai';
      final providers = [
        AiProviderMeta(
          id: providerId,
          name: 'OpenAI',
          type: AiProviderType.openaiCompatible,
          enabled: true,
          isBuiltIn: true,
          createdAt: 1,
          updatedAt: 1,
        ),
      ];

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorKey: navigatorKey,
            locale: const Locale('zh', 'CN'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: const AiChatStream(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AiChatStream)),
      );
      await container.read(aiChatProvider.future);
      container.read(aiChatProvider.notifier).restore(
        [ChatMessage.humanText('已有会话')],
        sessionId: 'chat-seminar-entry',
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(find.byType(TextField).first, '这个概念怎么理解？');
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      expect(find.text('AI 研讨会'), findsOneWidget);
      expect(find.text('选择风格'), findsOneWidget);

      await tester.tap(find.text('AI 研讨会'));
      await tester.pumpAndSettle();

      expect(find.byType(AiSeminarRuntimePage), findsNothing);
      expect(find.byType(AiSeminarRuntimePanel), findsOneWidget);
      expect(find.text('这个概念怎么理解？'), findsAtLeastNWidgets(1));
      expect(Prefs().activeAiSkillId, 'paper_analyzer');
    },
  );

  testWidgets(
    'Choose style Seminar row opens settings without selecting Seminar skill',
    (tester) async {
      const providerId = 'openai';
      final providers = [
        AiProviderMeta(
          id: providerId,
          name: 'OpenAI',
          type: AiProviderType.openaiCompatible,
          enabled: true,
          isBuiltIn: true,
          createdAt: 1,
          updatedAt: 1,
        ),
      ];

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorKey: navigatorKey,
            locale: const Locale('zh', 'CN'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: const AiChatStream(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.byType(AiChatStream), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择风格'));
      await tester.pumpAndSettle();

      expect(find.text('研讨会设置'), findsOneWidget);

      await tester.tap(find.text('研讨会模式'));
      await tester.pumpAndSettle();

      expect(find.byType(AiSeminarConfigPage), findsOneWidget);
      expect(Prefs().activeAiSkillId, 'paper_analyzer');
    },
  );

  testWidgets(
    'persisted Seminar chat card reopens inline runtime',
    (tester) async {
      const providerId = 'openai';
      final providers = [
        AiProviderMeta(
          id: providerId,
          name: 'OpenAI',
          type: AiProviderType.openaiCompatible,
          enabled: true,
          isBuiltIn: true,
          createdAt: 1,
          updatedAt: 1,
        ),
      ];

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorKey: navigatorKey,
            locale: const Locale('zh', 'CN'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: const AiChatStream(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AiChatStream)),
      );
      await container.read(aiChatProvider.future);
      final entry = _seminarCardHistoryEntry();
      container.read(aiChatProvider.notifier).loadHistoryEntry(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('AI 研讨会'), findsOneWidget);
      expect(find.text('这个概念怎么理解？'), findsAtLeastNWidgets(1));
      expect(find.text('待开始'), findsOneWidget);
      expect(find.text('3 个角色'), findsOneWidget);
      expect(find.text('证据：当前书籍'), findsOneWidget);
      expect(find.text('写入需确认'), findsOneWidget);
      expect(find.text('证据快照'), findsOneWidget);
      expect(find.text('Working memory evidence.'), findsOneWidget);
      expect(find.text('角色观点'), findsOneWidget);
      expect(find.text('批判者'), findsOneWidget);
      expect(
          find.text('This claim needs a boundary condition.'), findsOneWidget);
      expect(find.text('支持者'), findsOneWidget);
      expect(
          find.text('The surrounding paragraph supports it.'), findsOneWidget);
      expect(find.text('研讨总结'), findsOneWidget);
      expect(find.text('The group agrees on the mechanism but not the scope.'),
          findsOneWidget);
      expect(find.text('1 个分歧'), findsOneWidget);
      expect(find.byTooltip('研讨会设置'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '知识卡'), findsNothing);
      expect(find.widgetWithText(TextButton, '重新生成'), findsNothing);
      expect(find.widgetWithText(TextButton, '复制'), findsOneWidget);

      await tester.tap(find.text('AI 研讨会'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AiSeminarRuntimePanel), findsOneWidget);
      expect(find.text('这个概念怎么理解？'), findsAtLeastNWidgets(1));
      expect(Prefs().activeAiSkillId, 'paper_analyzer');
    },
  );

  testWidgets(
    'inline Seminar completion updates persisted chat card snapshot',
    (tester) async {
      const providerId = 'openai';
      final providers = [
        AiProviderMeta(
          id: providerId,
          name: 'OpenAI',
          type: AiProviderType.openaiCompatible,
          enabled: true,
          isBuiltIn: true,
          createdAt: 1,
          updatedAt: 1,
        ),
      ];

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiSeminarRuntimeServiceProvider.overrideWithValue(
              _seminarSnapshotService(),
            ),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            locale: const Locale('zh', 'CN'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: const AiChatStream(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AiChatStream)),
      );
      await container.read(aiChatProvider.future);
      final entry = _seminarCardHistoryEntry(includeSnapshot: false);
      container.read(aiChatProvider.notifier).loadHistoryEntry(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('证据快照'), findsNothing);

      await tester.tap(find.text('AI 研讨会'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AiSeminarRuntimePanel), findsOneWidget);
      await container.read(aiSeminarRuntimeProvider.notifier).start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: AiSeminarRole.defaultRoles,
              createdAt: 1000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final card = container
          .read(aiChatProvider.notifier)
          .seminarRunCardForMessageIndex(1);
      expect(card?.status, 'completed');
      expect(card?.sourceRefCount, 4);
      expect(card?.snapshot?.evidence, hasLength(3));
      expect(card?.snapshot?.evidence.first.snippet, 'The source passage.');
      expect(
        card?.snapshot?.evidence.map((item) => item.snippet),
        isNot(contains('Unused source passage 5.')),
      );
      expect(card?.snapshot?.roleSummaries.first.summary, 'critical response');
      expect(card?.snapshot?.synthesisSummary, 'synthesizer response');
    },
  );

  testWidgets(
    'persisted Seminar chat card shows whiteboard items from snapshot',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const providerId = 'openai';
      final providers = [
        AiProviderMeta(
          id: providerId,
          name: 'OpenAI',
          type: AiProviderType.openaiCompatible,
          enabled: true,
          isBuiltIn: true,
          createdAt: 1,
          updatedAt: 1,
        ),
      ];

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorKey: navigatorKey,
            locale: const Locale('zh', 'CN'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: const AiChatStream(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AiChatStream)),
      );
      await container.read(aiChatProvider.future);
      container
          .read(aiChatProvider.notifier)
          .loadHistoryEntry(_seminarCardHistoryEntry());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(AiSeminarRuntimePanel), findsNothing);
      expect(find.text('研讨白板'), findsOneWidget);
      expect(find.text('分歧'), findsOneWidget);
      expect(find.text('Scope remains disputed.'), findsOneWidget);
      expect(find.text('开放问题'), findsOneWidget);
      expect(find.text('What evidence would resolve scope?'), findsOneWidget);
    },
  );

  testWidgets(
    'Seminar chat card hides Review handoff for a different active run',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-seminar-review-hide-');
      _mockPathProvider(tempDir.path);
      addTearDown(() {
        _mockPathProvider(null);
        tempDir.deleteSync(recursive: true);
      });

      const providerId = 'openai';
      final providers = [
        AiProviderMeta(
          id: providerId,
          name: 'OpenAI',
          type: AiProviderType.openaiCompatible,
          enabled: true,
          isBuiltIn: true,
          createdAt: 1,
          updatedAt: 1,
        ),
      ];

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiSeminarRuntimeServiceProvider.overrideWithValue(
              _seminarSnapshotService(),
            ),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            locale: const Locale('zh', 'CN'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: const AiChatStream(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AiChatStream)),
      );
      await container.read(aiChatProvider.future);
      container
          .read(aiChatProvider.notifier)
          .loadHistoryEntry(_seminarCardHistoryEntry());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await container.read(aiSeminarRuntimeProvider.notifier).start(
            AiSeminarSessionContract(
              id: 'other-seminar-session',
              question: '另一个研讨',
              bookId: 7,
              roles: AiSeminarRole.defaultRoles,
              createdAt: 1000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('AI 研讨会'), findsOneWidget);
      expect(find.text('发送到待审'), findsNothing);
    },
  );

  testWidgets(
    'Seminar chat card sends active completed run to Review',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tempDir =
          Directory.systemTemp.createTempSync('ai-chat-seminar-review-');
      _mockPathProvider(tempDir.path);
      addTearDown(() {
        _mockPathProvider(null);
        tempDir.deleteSync(recursive: true);
      });

      const providerId = 'openai';
      final providers = [
        AiProviderMeta(
          id: providerId,
          name: 'OpenAI',
          type: AiProviderType.openaiCompatible,
          enabled: true,
          isBuiltIn: true,
          createdAt: 1,
          updatedAt: 1,
        ),
      ];
      final reviewStore = _MemoryReviewItemStore();
      final cardStore = _MemoryKnowledgeCardStore();

      SharedPreferences.setMockInitialValues({
        'selectedAiService': providerId,
        'aiProvidersV1': AiProviderMeta.encodeList(providers),
        'aiConfig_$providerId': jsonEncode({'model': 'gpt-test'}),
        'activeAiSkillId': 'paper_analyzer',
      });
      await Prefs().initPrefs();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiSeminarRuntimeServiceProvider.overrideWithValue(
              _seminarSnapshotService(),
            ),
            aiSeminarReviewItemStoreProvider.overrideWithValue(reviewStore),
            aiSeminarKnowledgeCardStoreProvider.overrideWithValue(cardStore),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            locale: const Locale('zh', 'CN'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: const AiChatStream(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AiChatStream)),
      );
      await container.read(aiChatProvider.future);
      final entry = _seminarCardHistoryEntry();
      container.read(aiChatProvider.notifier).loadHistoryEntry(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await container.read(aiSeminarRuntimeProvider.notifier).start(
            AiSeminarSessionContract(
              id: 'seminar-chat-history',
              question: '这个概念怎么理解？',
              bookId: 7,
              roles: AiSeminarRole.defaultRoles,
              createdAt: 1000,
            ),
          );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(AiSeminarRuntimePanel), findsNothing);
      expect(find.text('发送到待审'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '知识卡'), findsNothing);

      await tester.tap(find.text('发送到待审'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(AiSeminarRuntimePanel), findsNothing);

      final pendingItems =
          await reviewStore.list(status: ReviewItemStatus.pending);
      final appliedItems =
          await reviewStore.list(status: ReviewItemStatus.applied);
      final seminarCards =
          await cardStore.list(origin: KnowledgeCardOrigin.seminar);
      final synthesis = pendingItems.singleWhere(
        (item) => item.sourceType == ReviewItemSourceType.seminarSynthesis,
      );

      expect(synthesis.payload['summary'], 'synthesizer response');
      expect(synthesis.sourceRefs, isNotEmpty);
      expect(synthesis.sourceRefs.every((ref) => ref.hasEvidence), true);
      expect(seminarCards, isEmpty);
      expect(appliedItems, isEmpty);
      expect(find.textContaining('已将综合总结和 0 张卡片发送到待审。'), findsOneWidget);
    },
  );
}

class _MemoryReviewItemStore extends ReviewItemStore {
  final _items = <String, ReviewItem>{};

  @override
  Future<List<ReviewItem>> list({
    ReviewItemStatus? status,
    ReviewItemSourceType? sourceType,
  }) async {
    return _items.values.where((item) {
      if (status != null && item.status != status) return false;
      if (sourceType != null && item.sourceType != sourceType) return false;
      return true;
    }).toList(growable: false);
  }

  @override
  Future<ReviewItem?> getById(String id) async => _items[id];

  @override
  Future<ReviewItem> upsert(ReviewItem item) async {
    if (item.status != ReviewItemStatus.draft &&
        item.status != ReviewItemStatus.pending) {
      throw ArgumentError(
        'Only draft/pending review items can be staged.',
      );
    }
    _items[item.id] = item;
    return item;
  }
}

class _MemoryKnowledgeCardStore extends KnowledgeCardStore {
  final _cards = <KnowledgeCard>[];

  @override
  Future<List<KnowledgeCard>> list({
    KnowledgeCardReviewState? reviewState,
    KnowledgeCardOrigin? origin,
  }) async {
    return _cards.where((card) {
      if (reviewState != null && card.reviewState != reviewState) {
        return false;
      }
      if (origin != null && card.origin != origin) return false;
      return true;
    }).toList(growable: false);
  }

  @override
  Future<KnowledgeCard?> getById(String id) async {
    for (final card in _cards) {
      if (card.id == id) return card;
    }
    return null;
  }

  @override
  Future<KnowledgeCardStoreUpsertResult> upsertCandidate(
    KnowledgeCard candidate,
  ) async {
    for (final card in _cards) {
      if (card.id == candidate.id ||
          KnowledgeCardDedupe.isLikelyDuplicate(card, candidate)) {
        return KnowledgeCardStoreUpsertResult(
          card: card,
          inserted: false,
          duplicateOfId: card.id,
        );
      }
    }
    final staged = candidate.copyWith(
      reviewState: candidate.reviewState == KnowledgeCardReviewState.draft
          ? KnowledgeCardReviewState.draft
          : KnowledgeCardReviewState.pending,
      ownership: AiOutputOwnership.aiGeneratedDraft,
    );
    _cards.add(staged);
    return KnowledgeCardStoreUpsertResult(card: staged, inserted: true);
  }
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

AiChatHistoryEntry _seminarCardHistoryEntry({bool includeSnapshot = true}) {
  final human = ChatMessage.humanText('这个概念怎么理解？');
  final assistant = ChatMessage.ai('AI Seminar: 这个概念怎么理解？');
  final card = AiSeminarRunCardMeta(
    question: '这个概念怎么理解？',
    sessionId: 'seminar-chat-history',
    bookId: 7,
    status: 'ready',
    roleIds: ['critical', 'supportive', 'synthesizer'],
    evidenceScopeIds: ['current-book'],
    sourceRefCount: 0,
    allowWeb: false,
    writeRequiresApproval: true,
    maxRounds: 2,
    createdAt: 1234,
    snapshot: includeSnapshot
        ? const AiSeminarRunCardSnapshot(
            evidence: [
              AiSeminarRunCardEvidenceSnapshot(
                title: 'Working memory',
                snippet: 'Working memory evidence.',
              ),
            ],
            roleSummaries: [
              AiSeminarRunCardRoleSummary(
                roleId: 'critical',
                label: '批判者',
                summary: 'This claim needs a boundary condition.',
              ),
              AiSeminarRunCardRoleSummary(
                roleId: 'supportive',
                label: '支持者',
                summary: 'The surrounding paragraph supports it.',
              ),
            ],
            synthesisSummary:
                'The group agrees on the mechanism but not the scope.',
            disagreements: ['Scope remains disputed.'],
            openQuestions: ['What evidence would resolve scope?'],
          )
        : null,
  );
  return AiChatHistoryEntry(
    id: 'seminar-card-history',
    serviceId: 'openai',
    model: 'gpt-test',
    createdAt: 1,
    updatedAt: 2,
    messages: [human, assistant],
    completed: true,
    conversationV2: {
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
          'message': human.toMap(),
          'createdAt': 1,
          'updatedAt': 1,
        },
        'assistant-1': {
          'parentId': 'user-1',
          'children': <String>[],
          'activeChildId': null,
          'message': assistant.toMap(),
          'meta': AiSegmentMeta(seminarRunCard: card).toJson(),
          'createdAt': 2,
          'updatedAt': 2,
        },
      },
    },
  );
}

AiSeminarRuntimeService _seminarSnapshotService() {
  final sourceRefs = List<SourceRef>.generate(
    5,
    (index) => SourceRef(
      bookId: 7,
      href: 'Text/ch${index + 1}.xhtml',
      cfi: 'epubcfi(/6/${8 + index})',
      jumpLink:
          'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/${8 + index}%29',
      sourceTextSnippet: index == 0
          ? 'The source passage.'
          : index == 4
              ? 'Unused source passage 5.'
              : 'Additional source passage ${index + 1}.',
      sourceKind: SourceRefKind.currentBookRag,
    ),
  );
  final bundle = AiSeminarEvidenceBundle(
    query: '这个概念怎么理解？',
    evidence: [
      for (var i = 0; i < sourceRefs.length; i++)
        AiSeminarEvidence(
          id: 'e${i + 1}',
          scope: AiSeminarEvidenceScope.currentBook,
          text: i == 0
              ? 'The source passage.'
              : i == 4
                  ? 'Unused source passage 5.'
                  : 'Additional source passage ${i + 1}.',
          sourceRef: sourceRefs[i],
        ),
    ],
  );
  return AiSeminarRuntimeService(
    fetchEvidence: (_) async => bundle,
    streamRole: (invocation, _) async* {
      yield AiSeminarRoleStreamChunk(
        completedTurn: AiSeminarRoleTurn(
          id: 'turn-${invocation.role.asString}',
          role: invocation.role,
          prompt: invocation.prompt,
          responseText: '${invocation.role.asString} response',
          evidenceRefIds: switch (invocation.role) {
            AiSeminarRole.critical => const ['e1', 'e2'],
            AiSeminarRole.supportive => const ['e3'],
            _ => const ['e4'],
          },
        ),
      );
    },
    now: () => 1000,
  );
}
