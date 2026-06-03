import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/main.dart';
import 'package:papertok_reader/models/ai_provider_meta.dart';
import 'package:papertok_reader/providers/ai_chat.dart';
import 'package:papertok_reader/service/memory/memory_candidate.dart';
import 'package:papertok_reader/service/memory/memory_source_kind.dart';
import 'package:papertok_reader/service/memory/memory_workflow_service.dart';
import 'package:papertok_reader/utils/toast/common.dart';
import 'package:papertok_reader/widgets/ai/ai_chat_stream.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('assistant answer Memory action remembers inline and can undo',
      (tester) async {
    final fakeMemoryWorkflow = _FakeMemoryWorkflowService();
    final container = await _pumpMemoryChat(
      tester,
      fakeMemoryWorkflow: fakeMemoryWorkflow,
    );
    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [
        ChatMessage.humanText('What should I remember?'),
        ChatMessage.ai('Remember that evidence must stay attached.'),
      ],
      sessionId: 'memory-widget-session',
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('Memory actions').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remember this'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 2100));

    expect(fakeMemoryWorkflow.saveDailyCalls, hasLength(1));
    expect(fakeMemoryWorkflow.reviewInboxCalls, isEmpty);
    final call = fakeMemoryWorkflow.saveDailyCalls.single;
    expect(call.text, 'Remember that evidence must stay attached.');
    expect(call.targetDoc, MemoryDocTarget.daily);
    expect(call.sourceType, 'chat');
    expect(call.conversationId, 'memory-widget-session');
    expect(call.messageNodeId, 'assistant:1');
    expect(call.displayText, 'Remember that evidence must stay attached.');
    expect(call.sourcePointer, 'memory-widget-session#assistant:1');
    expect(call.rawContextRef, 'conversation:memory-widget-session');
    expect(call.triggerKind, 'manual_save');

    await tester.tap(find.byTooltip('Memory actions').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo memory'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 2100));

    expect(fakeMemoryWorkflow.undoCalls, ['fake-memory-candidate-1']);
  });

  testWidgets('assistant Memory action is disabled while streaming',
      (tester) async {
    final fakeMemoryWorkflow = _FakeMemoryWorkflowService();
    final container = await _pumpMemoryChat(
      tester,
      fakeMemoryWorkflow: fakeMemoryWorkflow,
    );
    await container.read(aiChatProvider.future);
    container.read(aiChatProvider.notifier).restore(
      [
        ChatMessage.humanText('Keep this?'),
        ChatMessage.ai('This partial answer is still streaming.'),
      ],
      sessionId: 'memory-streaming-session',
    );
    container.read(aiChatStreamingProvider.notifier).setStreaming(true);
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('Memory actions').last,
        warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Remember this'), findsNothing);
    expect(fakeMemoryWorkflow.reviewInboxCalls, isEmpty);
  });
}

Future<ProviderContainer> _pumpMemoryChat(
  WidgetTester tester, {
  required _FakeMemoryWorkflowService fakeMemoryWorkflow,
}) async {
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
  });

  await Prefs().initPrefs();

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        navigatorKey: navigatorKey,
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: AiChatStream(
          memoryWorkflowService: fakeMemoryWorkflow,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  AnxToast.init(tester.element(find.byType(AiChatStream)));
  await tester.pump();

  return ProviderScope.containerOf(
    tester.element(find.byType(AiChatStream)),
  );
}

class _FakeMemoryWorkflowService extends MemoryWorkflowService {
  _FakeMemoryWorkflowService();

  final reviewInboxCalls = <_MemoryReviewInboxCall>[];
  final saveDailyCalls = <_MemoryReviewInboxCall>[];
  final undoCalls = <String>[];

  @override
  Future<MemoryCandidate> saveToDaily({
    required String text,
    DateTime? date,
    String sourceType = 'manual',
    String? conversationId,
    String? messageNodeId,
    String? summary,
    String sensitivity = 'normal',
    double? confidence,
    String? displayText,
    String? sourcePointer,
    String? rawContextRef,
    String? triggerKind,
    int? bookId,
    String? cfi,
    String? chapter,
    MemorySourceKind sourceKind = MemorySourceKind.chat,
    String? rationale,
  }) async {
    saveDailyCalls.add(
      _MemoryReviewInboxCall(
        text: text,
        targetDoc: MemoryDocTarget.daily,
        sourceType: sourceType,
        conversationId: conversationId,
        messageNodeId: messageNodeId,
        displayText: displayText,
        sourcePointer: sourcePointer,
        rawContextRef: rawContextRef,
        triggerKind: triggerKind,
      ),
    );
    return MemoryCandidate(
      id: 'fake-memory-candidate-${saveDailyCalls.length}',
      summary: summary ?? text,
      text: text,
      targetDoc: MemoryDocTarget.daily,
      sourceType: sourceType,
      createdAtMs: saveDailyCalls.length,
      status: MemoryCandidateStatus.applied,
      conversationId: conversationId,
      messageNodeId: messageNodeId,
      displayText: displayText,
      sourcePointer: sourcePointer,
      rawContextRef: rawContextRef,
      triggerKind: triggerKind,
      decisionSource: 'direct_save',
    );
  }

  @override
  Future<MemoryCandidate> undoDirectSave(
    String candidateId, {
    DateTime? date,
  }) async {
    undoCalls.add(candidateId);
    return MemoryCandidate(
      id: candidateId,
      summary: 'undone',
      text: 'undone',
      targetDoc: MemoryDocTarget.daily,
      sourceType: 'chat',
      createdAtMs: undoCalls.length,
      status: MemoryCandidateStatus.dismissed,
      decisionSource: 'user_undo',
    );
  }

  @override
  Future<MemoryCandidate> addToReviewInbox({
    required String text,
    required MemoryDocTarget targetDoc,
    String sourceType = 'manual',
    String? conversationId,
    String? messageNodeId,
    String? summary,
    String sensitivity = 'normal',
    double? confidence,
    String? displayText,
    String? sourcePointer,
    String? rawContextRef,
    String? triggerKind,
    int? bookId,
    String? cfi,
    String? chapter,
    MemorySourceKind sourceKind = MemorySourceKind.chat,
    String? rationale,
  }) async {
    reviewInboxCalls.add(
      _MemoryReviewInboxCall(
        text: text,
        targetDoc: targetDoc,
        sourceType: sourceType,
        conversationId: conversationId,
        messageNodeId: messageNodeId,
        displayText: displayText,
        sourcePointer: sourcePointer,
        rawContextRef: rawContextRef,
        triggerKind: triggerKind,
      ),
    );
    return MemoryCandidate(
      id: 'fake-memory-candidate-${reviewInboxCalls.length}',
      summary: summary ?? text,
      text: text,
      targetDoc: targetDoc,
      sourceType: sourceType,
      createdAtMs: reviewInboxCalls.length,
      status: MemoryCandidateStatus.pending,
      conversationId: conversationId,
      messageNodeId: messageNodeId,
      displayText: displayText,
      sourcePointer: sourcePointer,
      rawContextRef: rawContextRef,
      triggerKind: triggerKind,
    );
  }
}

class _MemoryReviewInboxCall {
  const _MemoryReviewInboxCall({
    required this.text,
    required this.targetDoc,
    required this.sourceType,
    required this.conversationId,
    required this.messageNodeId,
    required this.displayText,
    required this.sourcePointer,
    required this.rawContextRef,
    required this.triggerKind,
  });

  final String text;
  final MemoryDocTarget targetDoc;
  final String sourceType;
  final String? conversationId;
  final String? messageNodeId;
  final String? displayText;
  final String? sourcePointer;
  final String? rawContextRef;
  final String? triggerKind;
}
