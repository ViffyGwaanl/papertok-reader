import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/main.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/providers/ai_chat.dart';
import 'package:papertok_reader/providers/ai_seminar_runtime.dart';
import 'package:papertok_reader/service/ai/ai_seminar_runtime_service.dart';
import 'package:papertok_reader/widgets/ai/ai_chat_stream.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  testWidgets(
    'successful start_seminar tool step creates and starts native card',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiSeminarRuntimeServiceProvider.overrideWithValue(
              _fastSeminarRuntimeService(),
            ),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            locale: const Locale('en'),
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
        [
          ChatMessage.humanText('Please start a seminar.'),
          ChatMessage.ai(
            _toolStep(
              callId: 'call-start-seminar',
              input: {
                'question': 'Discuss the evidence boundary.',
                'scope': 'notes',
              },
            ),
          ),
        ],
        sessionId: 'chat-start-seminar-tool',
      );

      AiSeminarRunCardMeta? card;
      AiSeminarRuntimeState? runtimeState;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        card = _firstSeminarCard(container);
        final sessionId = card?.sessionId;
        if (sessionId != null && sessionId.isNotEmpty) {
          runtimeState = container.read(aiSeminarRuntimeScopedProvider(
            sessionId,
          ));
          if (runtimeState != null &&
              runtimeState.status != AiSeminarRunStatus.draft) {
            break;
          }
        }
      }

      expect(card, isNotNull);
      expect(card!.question, 'Discuss the evidence boundary.');
      expect(
          card.roleProfiles.every(
            (profile) => profile.evidenceScopes.contains(
              AiSeminarEvidenceScope.notes,
            ),
          ),
          isTrue);
      expect(runtimeState?.session?.id, card.sessionId);
      expect(runtimeState?.status, isNot(AiSeminarRunStatus.draft));
      expect(find.byType(AiChatStream), findsOneWidget);
    },
  );
}

String _toolStep({
  required String callId,
  required Map<String, dynamic> input,
}) {
  final encodedInput = Uri.encodeComponent(
    base64Encode(utf8.encode(jsonEncode(input))),
  );
  return "<tool-step name='start_seminar' status='success' "
      "call_id='$callId' input_b64='$encodedInput'/>";
}

AiSeminarRunCardMeta? _firstSeminarCard(ProviderContainer container) {
  final messages = container.read(aiChatProvider).asData?.value;
  if (messages == null) return null;
  final notifier = container.read(aiChatProvider.notifier);
  for (var i = 0; i < messages.length; i++) {
    final card = notifier.seminarRunCardForMessageIndex(i);
    if (card != null) return card;
  }
  return null;
}

AiSeminarRuntimeService _fastSeminarRuntimeService() {
  return AiSeminarRuntimeService(
    fetchEvidence: (session) async => AiSeminarEvidenceBundle(
      query: session.question,
      evidence: [
        AiSeminarEvidence(
          id: 'e1',
          scope: AiSeminarEvidenceScope.notes,
          text: 'Evidence boundary note.',
          sourceRef: SourceRef(
            sourceTitle: 'Note',
            sourceTextSnippet: 'Evidence boundary note.',
            sourceKind: SourceRefKind.note,
            unavailableReason: 'note source is not openable in this smoke test',
          ),
        ),
      ],
    ),
    streamRole: (invocation, _) async* {
      yield AiSeminarRoleStreamChunk(
        completedTurn: AiSeminarRoleTurn(
          id: 'turn-${invocation.role.asString}',
          role: invocation.role,
          prompt: invocation.prompt,
          responseText: '${invocation.role.asString} response',
          evidenceRefIds: const ['e1'],
        ),
      );
    },
    now: () => 1000,
  );
}
