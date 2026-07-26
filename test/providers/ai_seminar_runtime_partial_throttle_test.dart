import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:ai_provider_kit/ai_provider_kit.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/providers/ai_seminar_runtime.dart';
import 'package:papertok_reader/service/ai/ai_seminar_runtime_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    _configureProvider();
  });

  test('runtime throttles burst role partial updates', () async {
    final sessionId = 'seminar-burst-${DateTime.now().microsecondsSinceEpoch}';
    final runtimeService = AiSeminarRuntimeService(
      fetchEvidence: (_) async => _bundle(),
      streamRole: (invocation, _) async* {
        if (invocation.role == AiSeminarRole.critical) {
          for (var index = 0; index < 20; index += 1) {
            yield AiSeminarRoleStreamChunk(partialText: 'partial $index');
          }
        }
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: 'final response',
            evidenceRefIds: const ['e1'],
          ),
        );
      },
      now: () => 1000,
    );
    final container = ProviderContainer(
      overrides: [
        aiSeminarRuntimeServiceProvider.overrideWithValue(runtimeService),
      ],
    );
    addTearDown(container.dispose);

    final partialTexts = <String>[];
    final subscription = container.listen<AiSeminarRuntimeState>(
      aiSeminarRuntimeScopedProvider(sessionId),
      (previous, next) {
        final partial = next.partialRoleText;
        if (partial == null || partial == previous?.partialRoleText) return;
        if (partial.startsWith('partial ')) partialTexts.add(partial);
      },
    );
    addTearDown(subscription.close);

    await container
        .read(aiSeminarRuntimeScopedProvider(sessionId).notifier)
        .start(
          AiSeminarSessionContract(
            id: sessionId,
            question: 'Throttle burst partials.',
            roles: const [AiSeminarRole.critical],
            maxRounds: 1,
          ),
        );

    expect(partialTexts, contains('partial 0'));
    expect(partialTexts.length, lessThanOrEqualTo(3));
    expect(
      container.read(aiSeminarRuntimeScopedProvider(sessionId)).status,
      AiSeminarRunStatus.completed,
    );
  });
}

void _configureProvider() {
  const now = 1000;
  Prefs().aiProvidersV1 = const [
    AiProviderMeta(
      id: 'local-gateway',
      name: 'Local Gateway',
      type: AiProviderType.openaiCompatible,
      enabled: true,
      isBuiltIn: false,
      createdAt: now,
      updatedAt: now,
    ),
  ];
  Prefs().selectedAiService = 'local-gateway';
  Prefs().saveAiConfig('local-gateway', const {
    'model': 'gpt-5.5',
    'url': 'http://localhost:3003/v1/',
  });
  Prefs().saveAiModelCapabilitiesCacheV1(
    'local-gateway',
    const [
      AiModelCapability(
        id: 'gpt-5.5',
        contextWindow: 128000,
        maxOutputTokens: 8192,
        supportsTools: true,
        supportsImages: true,
        supportsThinking: true,
      ),
    ],
  );
}

SourceRef _traceableRef() => SourceRef(
      bookId: 7,
      href: 'Text/ch.xhtml',
      cfi: 'epubcfi(/6/8)',
      jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
      sourceTextSnippet: 'The source passage.',
      sourceKind: SourceRefKind.currentBookRag,
    );

AiSeminarEvidenceBundle _bundle() => AiSeminarEvidenceBundle(
      query: 'What is the claim?',
      evidence: [
        AiSeminarEvidence(
          id: 'e1',
          scope: AiSeminarEvidenceScope.currentBook,
          text: 'The source passage.',
          sourceRef: _traceableRef(),
        ),
      ],
    );
