import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/ai_model_capability.dart';
import 'package:papertok_reader/models/ai_provider_meta.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/knowledge_card.dart';
import 'package:papertok_reader/models/review_item.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/page/settings_page/ai_seminar_config.dart';
import 'package:papertok_reader/page/settings_page/ai_seminar_runtime.dart';
import 'package:papertok_reader/providers/ai_seminar_runtime.dart';
import 'package:papertok_reader/service/ai/ai_seminar_runtime_service.dart';
import 'package:papertok_reader/service/knowledge/knowledge_card_store.dart';
import 'package:papertok_reader/service/review/review_item_store.dart';
import 'package:papertok_reader/widgets/markdown/styled_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
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
  });

  SourceRef traceableRef() => SourceRef(
        bookId: 7,
        href: 'Text/ch.xhtml',
        cfi: 'epubcfi(/6/8)',
        jumpLink: 'paperreader://reader/open?bookId=7&cfi=epubcfi%28/6/8%29',
        sourceTextSnippet: 'The source passage.',
        sourceKind: SourceRefKind.currentBookRag,
      );

  AiSeminarRuntimeService service() {
    final bundle = AiSeminarEvidenceBundle(
      query: 'What is the claim?',
      evidence: [
        AiSeminarEvidence(
          id: 'e1',
          scope: AiSeminarEvidenceScope.currentBook,
          text: 'The source passage.',
          sourceRef: traceableRef(),
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
            evidenceRefIds: const ['e1'],
            whiteboardEntries: [
              if (invocation.role == AiSeminarRole.synthesizer)
                const AiSeminarWhiteboardEntry(
                  id: 'card-1',
                  kind: AiSeminarWhiteboardKind.candidateCard,
                  text: 'Candidate card',
                  evidenceRefIds: ['e1'],
                  conceptRefs: ['Seminar concept'],
                ),
              if (invocation.role == AiSeminarRole.synthesizer)
                const AiSeminarWhiteboardEntry(
                  id: 'review-1',
                  kind: AiSeminarWhiteboardKind.reviewSuggestion,
                  text: 'What should be reviewed later?',
                  evidenceRefIds: ['e1'],
                ),
            ],
          ),
        );
      },
      now: () => 1000,
    );
  }

  AiSeminarRuntimeService providerUsageService() {
    final bundle = AiSeminarEvidenceBundle(
      query: 'What is the claim?',
      evidence: [
        AiSeminarEvidence(
          id: 'e1',
          scope: AiSeminarEvidenceScope.currentBook,
          text: 'The source passage.',
          sourceRef: traceableRef(),
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
            evidenceRefIds: const ['e1'],
            tokenUsage: const AiSeminarTokenUsage(
              inputTokens: 9,
              outputTokens: 4,
              isEstimated: false,
              estimationMethod: 'provider-usage-tracker-v1',
              source: 'provider-reported',
            ),
          ),
        );
      },
      now: () => 1000,
    );
  }

  void configurePricingCapability() {
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
          inputCostPerMillionTokens: 2,
          outputCostPerMillionTokens: 8,
          cacheReadCostPerMillionTokens: 0.2,
          cacheWriteCostPerMillionTokens: 1,
          pricingSource: 'test-pricing-v1',
        ),
      ],
    );
  }

  Finder textFieldWithLabel(String label) {
    return find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
      description: 'TextField with label "$label"',
    );
  }

  Future<void> scrollToStartSeminar(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('Start Seminar'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'shows structured seminar roles evidence whiteboard and synthesis',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiSeminarRuntimePage(initialQuestion: 'What is the claim?'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(
      textFieldWithLabel('Seminar question'),
      'What is the claim?',
    );
    await scrollToStartSeminar(tester);
    await tester.tap(find.text('Start Seminar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Seminar Mode'), findsWidgets);
    expect(find.text('Evidence'), findsOneWidget);
    expect(find.text('The source passage.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('critical response'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Local token estimate'), findsOneWidget);
    expect(find.textContaining('Provider billing may differ'), findsOneWidget);
    expect(find.textContaining('local-char-estimate-v1'), findsOneWidget);
    expect(find.text('critical response'), findsWidgets);
    expect(find.text('supportive response'), findsWidgets);
    expect(find.text('synthesizer response'), findsWidgets);
    expect(find.byType(StyledMarkdown), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Shared whiteboard'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Shared whiteboard'), findsOneWidget);
    expect(find.text('Candidate card'), findsOneWidget);
    expect(find.text('Synthesis'), findsOneWidget);
    expect(find.text('Send to Review'), findsOneWidget);
  });

  testWidgets('shows director next step when Seminar needs reader input',
      (tester) async {
    final runtimeService = AiSeminarRuntimeService(
      fetchEvidence: (_) async => AiSeminarEvidenceBundle(
        query: 'What should I test?',
        evidence: [
          AiSeminarEvidence(
            id: 'e1',
            scope: AiSeminarEvidenceScope.currentBook,
            text: 'The source passage.',
            sourceRef: traceableRef(),
          ),
        ],
      ),
      streamRole: (invocation, _) async* {
        final isFollowUp = invocation.priorTurns.length >= 3;
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: isFollowUp
                ? 'turn-${invocation.role.asString}-follow-up'
                : 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: isFollowUp
                ? '${invocation.role.asString} follow-up response'
                : '${invocation.role.asString} response',
            evidenceRefIds: const ['e1'],
            whiteboardEntries: [
              if (invocation.role == AiSeminarRole.synthesizer && !isFollowUp)
                const AiSeminarWhiteboardEntry(
                  id: 'question-1',
                  kind: AiSeminarWhiteboardKind.openQuestion,
                  text: 'Which interpretation should the reader test next?',
                  role: AiSeminarRole.synthesizer,
                  evidenceRefIds: ['e1'],
                ),
            ],
          ),
        );
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiSeminarRuntimeServiceProvider.overrideWithValue(runtimeService),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiSeminarRuntimePage(initialQuestion: 'What should I test?'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await scrollToStartSeminar(tester);
    await tester.tap(find.text('Start Seminar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('Director next: ask reader'), findsOneWidget);
    expect(textFieldWithLabel('Your Seminar reply'), findsOneWidget);
    expect(find.text('Refresh evidence'), findsOneWidget);
    expect(find.text('Synthesize'), findsOneWidget);

    await tester.enterText(
      textFieldWithLabel('Your Seminar reply'),
      'Please ask the critical role to respond.',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ask selected role'));
    await tester.tap(find.text('Ask selected role'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AiSeminarRuntimePanel)),
    );
    final state = container.read(aiSeminarRuntimeProvider);
    expect(state.directorState!.lastUserIntervention!.text,
        'Please ask the critical role to respond.');
    expect(
      state.directorState!.lastUserIntervention!.requestedAction,
      AiSeminarUserInterventionAction.askRole,
    );
    expect(state.directorState!.lastUserIntervention!.targetRole,
        AiSeminarRole.critical);
    expect(state.directorState!.lastUserIntervention!.isEvidence, false);
    expect(state.evidenceBundle!.evidence.map((item) => item.id), ['e1']);
    expect(state.turns.last.id, 'turn-critical-follow-up');
    expect(
      state.turns.last.prompt,
      contains('Please ask the critical role to respond.'),
    );
    await tester.scrollUntilVisible(
      find.text('critical follow-up response'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('critical follow-up response'), findsOneWidget);
  });

  testWidgets('refresh evidence action reruns Seminar with new evidence',
      (tester) async {
    var fetchCount = 0;
    final runtimeService = AiSeminarRuntimeService(
      fetchEvidence: (_) async {
        fetchCount += 1;
        return AiSeminarEvidenceBundle(
          query: 'What should I test?',
          evidence: [
            AiSeminarEvidence(
              id: fetchCount == 1 ? 'e1' : 'e2',
              scope: AiSeminarEvidenceScope.currentBook,
              text: fetchCount == 1
                  ? 'The first source passage.'
                  : 'The refreshed source passage.',
              sourceRef: traceableRef(),
            ),
          ],
        );
      },
      streamRole: (invocation, _) async* {
        final evidenceId = invocation.evidenceBundle.evidence.single.id;
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}-$evidenceId',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText:
                '${invocation.role.asString} response using $evidenceId',
            evidenceRefIds: [evidenceId],
            whiteboardEntries: [
              if (invocation.role == AiSeminarRole.synthesizer &&
                  evidenceId == 'e1')
                const AiSeminarWhiteboardEntry(
                  id: 'question-1',
                  kind: AiSeminarWhiteboardKind.openQuestion,
                  text: 'Which evidence should be refreshed?',
                  role: AiSeminarRole.synthesizer,
                  evidenceRefIds: ['e1'],
                ),
            ],
          ),
        );
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiSeminarRuntimeServiceProvider.overrideWithValue(runtimeService),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiSeminarRuntimePage(initialQuestion: 'What should I test?'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await scrollToStartSeminar(tester);
    await tester.tap(find.text('Start Seminar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('Director next: ask reader'), findsOneWidget);
    await tester.enterText(
      textFieldWithLabel('Your Seminar reply'),
      'Please find better evidence.',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Refresh evidence'));
    await tester.tap(find.text('Refresh evidence'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AiSeminarRuntimePanel)),
    );
    final state = container.read(aiSeminarRuntimeProvider);
    expect(fetchCount, 2);
    expect(state.evidenceBundle!.evidence.map((item) => item.id), ['e2']);
    expect(state.directorState!.evidenceRefreshCount, 1);
    expect(
      state.directorState!.lastUserIntervention!.requestedAction,
      AiSeminarUserInterventionAction.refreshEvidence,
    );
    expect(state.directorState!.lastUserIntervention!.isEvidence, false);
    await tester.scrollUntilVisible(
      find.text('synthesizer response using e2'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('The refreshed source passage.'), findsOneWidget);
    expect(find.text('synthesizer response using e2'), findsOneWidget);
  });

  testWidgets('role configuration can add verifier to a Seminar agent run',
      (tester) async {
    AiSeminarSessionContract? capturedSession;
    final runtimeService = AiSeminarRuntimeService(
      fetchEvidence: (session) async {
        capturedSession = session;
        return AiSeminarEvidenceBundle(
          query: session.question,
          evidence: [
            AiSeminarEvidence(
              id: 'e1',
              scope: AiSeminarEvidenceScope.currentBook,
              text: 'The source passage.',
              sourceRef: traceableRef(),
            ),
          ],
        );
      },
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiSeminarRuntimeServiceProvider.overrideWithValue(runtimeService),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiSeminarRuntimePage(initialQuestion: 'What is the claim?'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.scrollUntilVisible(
      find.text('Agent roles'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Agent roles'), findsOneWidget);
    expect(find.textContaining('Evidence-gated role agents'), findsOneWidget);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Verifier'));
    await tester.pump();
    await scrollToStartSeminar(tester);
    await tester.tap(find.text('Start Seminar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(capturedSession, isNotNull);
    expect(capturedSession!.roles, contains(AiSeminarRole.verifier));
    expect(Prefs().aiSeminarIncludeVerifier, true);
  });

  testWidgets('Seminar settings prefill verifier and budget defaults',
      (tester) async {
    Prefs().aiSeminarIncludeVerifier = true;
    Prefs().aiSeminarDefaultRoleOutputTokenBudget = 1200;
    Prefs().aiSeminarDefaultRunTokenBudget = 3600;
    Prefs().aiSeminarDefaultRunCostCapUsd = 0.42;
    configurePricingCapability();

    AiSeminarSessionContract? capturedSession;
    final runtimeService = AiSeminarRuntimeService(
      fetchEvidence: (session) async {
        capturedSession = session;
        return AiSeminarEvidenceBundle(
          query: session.question,
          evidence: [
            AiSeminarEvidence(
              id: 'e1',
              scope: AiSeminarEvidenceScope.currentBook,
              text: 'The source passage.',
              sourceRef: traceableRef(),
            ),
          ],
        );
      },
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiSeminarRuntimeServiceProvider.overrideWithValue(runtimeService),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiSeminarRuntimePage(initialQuestion: 'What is the claim?'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byIcon(Icons.tune_outlined), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            textFieldWithLabel('Role output token budget'),
          )
          .controller
          ?.text,
      '1200',
    );
    expect(
      tester
          .widget<TextField>(
            textFieldWithLabel('Run token budget'),
          )
          .controller
          ?.text,
      '3600',
    );
    expect(
      tester
          .widget<TextField>(
            textFieldWithLabel('Run cost cap USD'),
          )
          .controller
          ?.text,
      '0.42',
    );
    await tester.scrollUntilVisible(
      find.text('Agent roles'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Verifier'),
            )
            .value,
        true);

    await scrollToStartSeminar(tester);
    await tester.tap(find.text('Start Seminar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(capturedSession, isNotNull);
    expect(capturedSession!.roles, contains(AiSeminarRole.verifier));
    expect(capturedSession!.budgetPolicy?.maxRoleOutputTokens, 1200);
    expect(capturedSession!.budgetPolicy?.maxRunTokens, 3600);
    expect(capturedSession!.budgetPolicy?.maxRunCostUsd, 0.42);
  });

  testWidgets('Seminar settings page persists default run configuration',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: AiSeminarConfigPage(),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('How Seminar runs'), findsOneWidget);
    expect(
      find.textContaining('role agents orchestrated by generated prompts'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(SwitchListTile, 'Verifier'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Role output token budget'),
      '900',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Run token budget'),
      '2400',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Run cost cap USD'),
      '0.25',
    );

    expect(Prefs().aiSeminarIncludeVerifier, true);
    expect(Prefs().aiSeminarDefaultRoleOutputTokenBudget, 900);
    expect(Prefs().aiSeminarDefaultRunTokenBudget, 2400);
    expect(Prefs().aiSeminarDefaultRunCostCapUsd, 0.25);
  });

  testWidgets('Seminar settings page persists role prompt profiles',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: AiSeminarConfigPage(),
      ),
    );

    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -520));
    await tester.pumpAndSettle();

    expect(find.text('Role prompt profiles'), findsOneWidget);
    expect(textFieldWithLabel('Critical role name'), findsOneWidget);
    expect(textFieldWithLabel('Critical custom prompt'), findsOneWidget);

    await tester.enterText(
      textFieldWithLabel('Critical role name'),
      'Evidence Challenger',
    );
    await tester.enterText(
      textFieldWithLabel('Critical custom prompt'),
      'Challenge causal claims and name missing evidence.',
    );

    final raw = Prefs().prefs.getString('aiSeminarRoleProfilesV1');
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!) as Map<String, dynamic>;
    expect(decoded['critical']['name'], 'Evidence Challenger');
    expect(
      decoded['critical']['customPrompt'],
      'Challenge causal claims and name missing evidence.',
    );
  });

  testWidgets('start injects configured role prompt into seminar invocation',
      (tester) async {
    await Prefs().prefs.setString(
          'aiSeminarRoleProfilesV1',
          jsonEncode({
            'critical': {
              'name': 'Evidence Challenger',
              'customPrompt':
                  'Challenge causal claims and name missing evidence.',
            },
          }),
        );
    expect(Prefs().aiSeminarRoleProfiles.single.name, 'Evidence Challenger');
    String? criticalPrompt;
    final runtimeService = AiSeminarRuntimeService(
      fetchEvidence: (_) async => AiSeminarEvidenceBundle(
        query: 'What is the claim?',
        evidence: [
          AiSeminarEvidence(
            id: 'e1',
            scope: AiSeminarEvidenceScope.currentBook,
            text: 'Traceable evidence.',
            sourceRef: traceableRef(),
          ),
        ],
      ),
      streamRole: (invocation, _) async* {
        if (invocation.role == AiSeminarRole.critical) {
          criticalPrompt = invocation.prompt;
        }
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
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiSeminarRuntimeServiceProvider.overrideWithValue(runtimeService),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiSeminarRuntimePage(initialQuestion: 'What is the claim?'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await scrollToStartSeminar(tester);
    await tester.tap(find.text('Start Seminar'));
    await tester.pumpAndSettle();

    expect(criticalPrompt, contains('Evidence Challenger'));
    expect(
      criticalPrompt,
      contains('Challenge causal claims and name missing evidence.'),
    );
  });

  testWidgets('start passes reader selection SourceRef into seminar session',
      (tester) async {
    AiSeminarSessionContract? capturedSession;
    final selectedRef = SourceRef(
      bookId: 42,
      cfi: 'epubcfi(/6/4)',
      jumpLink: 'paperreader://reader/open?bookId=42&cfi=epubcfi%28/6/4%29',
      sourceTextSnippet: 'Evidence-backed learning needs jump links.',
      sourceKind: SourceRefKind.reader,
    );
    final runtimeService = AiSeminarRuntimeService(
      fetchEvidence: (session) async {
        capturedSession = session;
        return AiSeminarEvidenceBundle(
          query: session.question,
          evidence: [
            AiSeminarEvidence(
              id: 'selection-1',
              scope: AiSeminarEvidenceScope.currentBook,
              text: session.sourceRefs.single.sourceTextSnippet!,
              sourceRef: session.sourceRefs.single,
            ),
          ],
        );
      },
      streamRole: (invocation, _) async* {
        yield AiSeminarRoleStreamChunk(
          completedTurn: AiSeminarRoleTurn(
            id: 'turn-${invocation.role.asString}',
            role: invocation.role,
            prompt: invocation.prompt,
            responseText: '${invocation.role.asString} response',
            evidenceRefIds: const ['selection-1'],
          ),
        );
      },
      now: () => 1000,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiSeminarRuntimeServiceProvider.overrideWithValue(runtimeService),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiSeminarRuntimePage(
            initialQuestion: 'Discuss this selection.',
            bookId: 42,
            initialSourceRef: selectedRef,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await scrollToStartSeminar(tester);
    await tester.tap(find.text('Start Seminar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(capturedSession, isNotNull);
    expect(capturedSession!.bookId, 42);
    expect(capturedSession!.sourceRefs, hasLength(1));
    expect(capturedSession!.sourceRefs.single.cfi, 'epubcfi(/6/4)');
    expect(capturedSession!.sourceRefs.single.sourceTextSnippet,
        'Evidence-backed learning needs jump links.');
    expect(capturedSession!.sourceRefs.single.sourceKind, SourceRefKind.reader);
  });

  testWidgets('shows provider reported token usage when available',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiSeminarRuntimeServiceProvider.overrideWithValue(
            providerUsageService(),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiSeminarRuntimePage(initialQuestion: 'What is the claim?'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await scrollToStartSeminar(tester);
    await tester.tap(find.text('Start Seminar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    await tester.scrollUntilVisible(
      find.textContaining('Provider reported usage'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Provider reported usage'), findsOneWidget);
    expect(
      find.textContaining('Stored from provider usage metadata'),
      findsOneWidget,
    );
    expect(find.textContaining('provider-usage-tracker-v1'), findsOneWidget);
    expect(find.textContaining('Provider usage'), findsWidgets);
  });

  testWidgets(
      'shows provider model capability and cost transparency before Start Seminar',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiSeminarRuntimePage(initialQuestion: 'What is the claim?'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Provider readiness'), findsOneWidget);
    expect(find.textContaining('Local Gateway'), findsOneWidget);
    expect(find.textContaining('gpt-5.5'), findsOneWidget);
    expect(find.textContaining('Context: 128K'), findsOneWidget);
    expect(find.textContaining('Max output: 8.2K'), findsOneWidget);
    expect(find.textContaining('Tools'), findsOneWidget);
    expect(find.textContaining('Vision'), findsOneWidget);
    expect(find.textContaining('Thinking'), findsOneWidget);
    expect(find.textContaining('Streaming unknown'), findsOneWidget);
    expect(find.text('Streaming'), findsNothing);
    expect(find.textContaining('Cost: unknown'), findsOneWidget);
    expect(
      find.textContaining('Provider pricing metadata is unavailable'),
      findsOneWidget,
    );
  });

  testWidgets('local token budget fields stop an over-budget seminar',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiSeminarRuntimePage(initialQuestion: 'What is the claim?'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Local budget guardrails'), findsOneWidget);
    expect(textFieldWithLabel('Role output token budget'), findsOneWidget);
    expect(textFieldWithLabel('Run token budget'), findsOneWidget);
    expect(find.textContaining('Cost cap unavailable'), findsOneWidget);

    await tester.enterText(textFieldWithLabel('Role output token budget'), '1');
    await scrollToStartSeminar(tester);
    await tester.tap(find.text('Start Seminar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('role output token budget'), findsOneWidget);
    expect(find.text('Send to Review'), findsNothing);
  });

  testWidgets('pricing metadata enables USD run cost cap field',
      (tester) async {
    configurePricingCapability();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiSeminarRuntimeServiceProvider.overrideWithValue(
            providerUsageService(),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiSeminarRuntimePage(initialQuestion: 'What is the claim?'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(textFieldWithLabel('Run cost cap USD'), findsOneWidget);
    expect(find.textContaining('Pricing: test-pricing-v1'), findsOneWidget);
    expect(
      find.textContaining('Cost cap unavailable until pricing metadata'),
      findsNothing,
    );
  });

  testWidgets('shows billing reconciliation as estimate not provider invoice',
      (tester) async {
    configurePricingCapability();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiSeminarRuntimeServiceProvider.overrideWithValue(
            providerUsageService(),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiSeminarRuntimePage(initialQuestion: 'What is the claim?'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await scrollToStartSeminar(tester);
    await tester.tap(find.text('Start Seminar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    await tester.scrollUntilVisible(
      find.text('Billing reconciliation'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Billing reconciliation'), findsOneWidget);
    expect(find.textContaining('Estimated cost, not invoice'), findsOneWidget);
    expect(find.textContaining('Usage snapshot: Provider metadata'),
        findsOneWidget);
    expect(find.textContaining('Pricing snapshot: test-pricing-v1'),
        findsOneWidget);
    expect(find.textContaining('Invoice reconciliation: Not connected'),
        findsOneWidget);
    expect(find.textContaining('Provider invoice import is not connected'),
        findsOneWidget);
  });

  testWidgets('shows a recovered local state banner for restored seminars',
      (tester) async {
    await Prefs().prefs.setString(
          aiSeminarRuntimeStateV1PrefsKey,
          jsonEncode({
            'status': 'completed',
            'session': {
              'id': 's-restored-page',
              'question': 'Restored question?',
            },
            'evidenceBundle': {
              'query': 'Restored question?',
              'evidence': [
                {
                  'id': 'e1',
                  'scope': 'current-book',
                  'text': 'The source passage.',
                  'sourceRef': traceableRef().toSafeJson(),
                },
              ],
            },
            'turns': [
              {
                'id': 'turn-critical',
                'role': 'critical',
                'prompt': 'prompt',
                'responseText': 'critical restored response',
                'evidenceRefIds': ['e1'],
              },
            ],
            'lastRun': {
              'session': {
                'id': 's-restored-page',
                'question': 'Restored question?',
              },
              'status': 'completed',
              'evidenceBundle': {
                'query': 'Restored question?',
                'evidence': [
                  {
                    'id': 'e1',
                    'scope': 'current-book',
                    'text': 'The source passage.',
                    'sourceRef': traceableRef().toSafeJson(),
                  },
                ],
              },
              'turns': [
                {
                  'id': 'turn-critical',
                  'role': 'critical',
                  'prompt': 'prompt',
                  'responseText': 'critical restored response',
                  'evidenceRefIds': ['e1'],
                },
              ],
            },
          }),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiSeminarRuntimePage(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.scrollUntilVisible(
      find.textContaining('Recovered local Seminar state'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Recovered local Seminar state'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('critical restored response'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('critical restored response'), findsOneWidget);
  });

  testWidgets('shows interrupted background job state after local restore',
      (tester) async {
    await Prefs().prefs.setString(
          aiSeminarRuntimeStateV1PrefsKey,
          jsonEncode({
            'status': 'running',
            'session': {
              'id': 's-restored-background',
              'question': 'Restored background?',
            },
            'backgroundJob': {
              'id': 'job-restored-background',
              'sessionId': 's-restored-background',
              'status': 'running',
              'startedAt': 1000,
              'updatedAt': 1000,
            },
            'evidenceBundle': {
              'query': 'Restored background?',
              'evidence': [
                {
                  'id': 'e1',
                  'scope': 'current-book',
                  'text': 'The source passage.',
                  'sourceRef': traceableRef().toSafeJson(),
                },
              ],
            },
            'turns': [],
          }),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiSeminarRuntimePage(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.scrollUntilVisible(
      find.textContaining('Recovered interrupted local Seminar state'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Recovered interrupted local Seminar state'),
        findsOneWidget);
    expect(
      find.textContaining(
          'Background job: interrupted · job-restored-background'),
      findsOneWidget,
    );
  });

  testWidgets('starting while running queues a visible Seminar job',
      (tester) async {
    final activeRoleStarted = Completer<void>();
    final releaseActiveRole = Completer<void>();
    final runtimeService = AiSeminarRuntimeService(
      fetchEvidence: (_) async => AiSeminarEvidenceBundle(
        query: 'Queue?',
        evidence: [
          AiSeminarEvidence(
            id: 'e1',
            scope: AiSeminarEvidenceScope.currentBook,
            text: 'The source passage.',
            sourceRef: traceableRef(),
          ),
        ],
      ),
      streamRole: (invocation, token) async* {
        if (invocation.session.id.contains('seminar-') &&
            invocation.session.question == 'First queued page run?') {
          if (!activeRoleStarted.isCompleted) activeRoleStarted.complete();
          token.onCancel(() {
            if (!releaseActiveRole.isCompleted) releaseActiveRole.complete();
          });
          await releaseActiveRole.future;
        }
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiSeminarRuntimeServiceProvider.overrideWithValue(runtimeService),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiSeminarRuntimePage(
            initialQuestion: 'First queued page run?',
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await scrollToStartSeminar(tester);
    await tester.tap(find.text('Start Seminar'));
    await tester.pump();
    await activeRoleStarted.future;

    await tester.scrollUntilVisible(
      textFieldWithLabel('Seminar question'),
      -220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      textFieldWithLabel('Seminar question'),
      'Second queued page run?',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.scrollUntilVisible(
      find.text('Queue Seminar'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Queue Seminar'));
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Seminar job queue'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Seminar job queue'), findsOneWidget);
    expect(find.textContaining('running · seminar-job-'), findsOneWidget);
    expect(find.textContaining('queued · seminar-job-'), findsOneWidget);
    expect(find.textContaining('Second queued page run?'), findsOneWidget);

    releaseActiveRole.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('does not show recovered state for a different book selection',
      (tester) async {
    await Prefs().prefs.setString(
          aiSeminarRuntimeStateV1PrefsKey,
          jsonEncode({
            'status': 'completed',
            'session': {
              'id': 's-old-book',
              'question': 'Old selected passage?',
              'bookId': 7,
            },
            'turns': [
              {
                'id': 'turn-critical',
                'role': 'critical',
                'prompt': 'prompt',
                'responseText': 'old restored response',
                'evidenceRefIds': ['e1'],
              },
            ],
          }),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiSeminarRuntimePage(
            initialQuestion: 'New selected passage?',
            bookId: 8,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
    await scrollToStartSeminar(tester);
    expect(find.text('Start Seminar'), findsOneWidget);
    expect(find.textContaining('Recovered local Seminar state'), findsNothing);
    expect(find.text('old restored response'), findsNothing);
    await tester.pump();
    expect(Prefs().prefs.getString(aiSeminarRuntimeStateV1PrefsKey), isNull);
  });

  testWidgets(
      'does not restore selected-text Seminar state for a different SourceRef',
      (tester) async {
    final oldRef = SourceRef(
      bookId: 42,
      cfi: 'epubcfi(/6/4)',
      jumpLink: 'paperreader://reader/open?bookId=42&cfi=epubcfi%28/6/4%29',
      sourceTextSnippet: 'Repeated selected sentence.',
      sourceKind: SourceRefKind.reader,
    );
    final newRef = SourceRef(
      bookId: 42,
      cfi: 'epubcfi(/6/12)',
      jumpLink: 'paperreader://reader/open?bookId=42&cfi=epubcfi%28/6/12%29',
      sourceTextSnippet: 'Repeated selected sentence.',
      sourceKind: SourceRefKind.reader,
    );
    await Prefs().prefs.setString(
          aiSeminarRuntimeStateV1PrefsKey,
          jsonEncode({
            'status': 'completed',
            'session': {
              'id': 's-old-selection',
              'question': 'Discuss repeated selected sentence.',
              'bookId': 42,
              'sourceRefs': [oldRef.toSafeJson()],
            },
            'turns': [
              {
                'id': 'turn-critical',
                'role': 'critical',
                'prompt': 'prompt',
                'responseText': 'old CFI restored response',
                'evidenceRefIds': ['selection-1'],
              },
            ],
          }),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiSeminarRuntimePage(
            initialQuestion: 'Discuss repeated selected sentence.',
            bookId: 42,
            initialSourceRef: newRef,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
    await scrollToStartSeminar(tester);
    expect(find.text('Start Seminar'), findsOneWidget);
    expect(find.textContaining('Recovered local Seminar state'), findsNothing);
    expect(find.text('old CFI restored response'), findsNothing);
    await tester.pump();
    expect(Prefs().prefs.getString(aiSeminarRuntimeStateV1PrefsKey), isNull);
  });

  testWidgets(
      'tapping Send to Review writes seminar card and flashcard candidates without applying',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final reviewStore = _MemoryReviewItemStore();
    final cardStore = _MemoryKnowledgeCardStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiSeminarRuntimeServiceProvider.overrideWithValue(service()),
          aiSeminarReviewItemStoreProvider.overrideWithValue(reviewStore),
          aiSeminarKnowledgeCardStoreProvider.overrideWithValue(cardStore),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiSeminarRuntimePage(initialQuestion: 'What is the claim?'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(
      textFieldWithLabel('Seminar question'),
      'What is the claim?',
    );
    await tester.tap(find.text('Start Seminar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    await tester.scrollUntilVisible(
      find.text('Send to Review'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Send to Review'), findsOneWidget);
    await tester.tap(find.text('Send to Review'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final pendingItems =
        await reviewStore.list(status: ReviewItemStatus.pending);
    final appliedItems =
        await reviewStore.list(status: ReviewItemStatus.applied);
    final seminarCards =
        await cardStore.list(origin: KnowledgeCardOrigin.seminar);
    final sourceTypes = pendingItems.map((item) => item.sourceType).toSet();

    expect(
      sourceTypes,
      containsAll({
        ReviewItemSourceType.seminarSynthesis,
        ReviewItemSourceType.knowledgeCard,
        ReviewItemSourceType.flashcardCandidate,
      }),
    );
    final synthesisItem = pendingItems.singleWhere(
      (item) => item.sourceType == ReviewItemSourceType.seminarSynthesis,
    );
    expect(synthesisItem.payload['summary'], 'synthesizer response');
    expect(synthesisItem.payload['candidateReviewQuestions'], isNotEmpty);
    expect(synthesisItem.sourceRefs.single.hasEvidence, true);

    expect(seminarCards, hasLength(1));
    expect(seminarCards.single.reviewState, KnowledgeCardReviewState.pending);
    expect(seminarCards.single.isUserAsset, false);
    expect(seminarCards.single.conceptRefs, ['Seminar concept']);

    final flashcard = pendingItems.singleWhere(
      (item) => item.sourceType == ReviewItemSourceType.flashcardCandidate,
    );
    expect(flashcard.status, ReviewItemStatus.pending);
    expect(flashcard.sourceId, contains(':question-1'));
    expect(appliedItems, isEmpty);
    expect(find.textContaining('Sent synthesis and 1 card(s) to Review.'),
        findsOneWidget);
  });
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
