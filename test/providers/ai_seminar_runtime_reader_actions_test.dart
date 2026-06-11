import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/providers/ai_seminar_runtime.dart';
import 'package:papertok_reader/service/ai/ai_seminar_runtime_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('one-click reader actions accept empty text but reply action does not',
      () async {
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(
          _runtimeService(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(aiSeminarRuntimeProvider.notifier);

    await notifier.start(
      AiSeminarSessionContract(id: 's-reader-actions', question: 'Explain.'),
    );

    await notifier.recordUserIntervention(
      text: '',
      requestedAction: AiSeminarUserInterventionAction.askRole,
      targetRole: AiSeminarRole.critical,
      now: 2001,
    );
    expect(
      container
          .read(aiSeminarRuntimeProvider)
          .directorState!
          .lastUserIntervention!
          .requestedAction,
      AiSeminarUserInterventionAction.askRole,
    );

    await notifier.recordUserIntervention(
      text: '',
      requestedAction: AiSeminarUserInterventionAction.refreshEvidence,
      now: 2002,
    );
    expect(
      container.read(aiSeminarRuntimeProvider).directorState!.nextIntent,
      AiSeminarDirectorNextIntent.refreshEvidence,
    );

    await notifier.recordUserIntervention(
      text: '',
      requestedAction: AiSeminarUserInterventionAction.synthesize,
      now: 2003,
    );
    expect(
      container.read(aiSeminarRuntimeProvider).directorState!.nextIntent,
      AiSeminarDirectorNextIntent.synthesize,
    );

    await expectLater(
      notifier.recordUserIntervention(
        text: '',
        requestedAction: AiSeminarUserInterventionAction.clarify,
        now: 2004,
      ),
      throwsA(isA<StateError>()),
    );
  });
}

AiSeminarRuntimeService _runtimeService() {
  return AiSeminarRuntimeService(
    fetchEvidence: (session) async => AiSeminarEvidenceBundle(
      query: session.question,
      evidence: [
        AiSeminarEvidence(
          id: 'e1',
          scope: AiSeminarEvidenceScope.currentBook,
          text: 'Traceable source passage.',
          sourceRef: SourceRef(
            bookId: 1,
            cfi: 'epubcfi(/6/2)',
            sourceTitle: 'Book',
            sourceTextSnippet: 'Traceable source passage.',
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
