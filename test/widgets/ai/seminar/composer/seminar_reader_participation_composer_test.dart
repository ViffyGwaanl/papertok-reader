import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/widgets/ai/seminar/composer/seminar_reader_composer_policy.dart';
import 'package:papertok_reader/widgets/ai/seminar/composer/seminar_reader_participation_composer.dart';

void main() {
  testWidgets('participation composer renders chat-native controls',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    SeminarParticipationQuickAction? quickAction;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: SeminarReaderParticipationComposer(
            sessionId: 's1',
            controller: controller,
            roles: const [AiSeminarRole.critical, AiSeminarRole.supportive],
            selectedRole: null,
            activeIntentId: null,
            isSubmitting: false,
            isAwaitingReader: false,
            showHint: true,
            roleLabelBuilder: (roleId) => roleId,
            onQuickAction: (action) => quickAction = action,
            onSend: () {},
            onRoleChanged: (_) {},
            onDraftChanged: (_) {},
            onDismissHint: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('继续讨论'), findsOneWidget);
    expect(find.text('换个角度看'), findsOneWidget);
    expect(find.text('补充证据'), findsOneWidget);
    expect(find.text('出总结'), findsOneWidget);
    expect(find.text('主持人分配'), findsOneWidget);
    expect(find.text('你可以随时插话、补充证据或要求总结'), findsOneWidget);
    expect(find.textContaining('让批判者反驳'), findsNothing);
    expect(find.textContaining('回应角色'), findsNothing);

    await tester.tap(find.text('补充证据'));
    expect(quickAction, SeminarParticipationQuickAction.refreshEvidence);
  });

  testWidgets('disagreement actions expose only continue and evidence chips',
      (tester) async {
    var continued = '';
    var verified = '';

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: SeminarDisagreementParticipationChips(
            sessionId: 's1',
            disagreements: const ['Scope remains disputed.'],
            isSubmitting: false,
            onContinue: (text) => continued = text,
            onVerifyEvidence: (text) => verified = text,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('就这点继续讨论'), findsOneWidget);
    expect(find.text('找证据验证'), findsOneWidget);
    expect(find.textContaining('已有证据分歧'), findsNothing);
    expect(find.textContaining('优先处理'), findsNothing);

    await tester.tap(find.text('就这点继续讨论'));
    await tester.tap(find.text('找证据验证'));
    expect(continued, 'Scope remains disputed.');
    expect(verified, 'Scope remains disputed.');
  });
}
