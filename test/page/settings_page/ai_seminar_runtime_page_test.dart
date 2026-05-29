import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/page/settings_page/ai_seminar_runtime.dart';
import 'package:papertok_reader/providers/ai_seminar_runtime.dart';
import 'package:papertok_reader/service/ai/ai_seminar_runtime_service.dart';

void main() {
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
                ),
            ],
          ),
        );
      },
      now: () => 1000,
    );
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

    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'What is the claim?');
    await tester.tap(find.text('Start Seminar'));
    await tester.pumpAndSettle();

    expect(find.text('Seminar Mode'), findsWidgets);
    expect(find.text('Evidence'), findsOneWidget);
    expect(find.text('The source passage.'), findsOneWidget);
    expect(find.text('critical response'), findsOneWidget);
    expect(find.text('supportive response'), findsOneWidget);
    expect(find.text('synthesizer response'), findsWidgets);
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
}
