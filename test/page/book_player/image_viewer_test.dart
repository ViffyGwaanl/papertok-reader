import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/page/book_player/image_viewer.dart';

void main() {
  testWidgets('image analysis sheet exposes KnowledgeCard action',
      (tester) async {
    var cardText = '';

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            height: 420,
            child: AiImageAnalysisSheet(
              stream: Stream<String>.value(
                'The image explains a traceable evidence chain.',
              ),
              onContinueAsk: (_) async {},
              onCreateKnowledgeCard: (text) async {
                cardText = text;
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('AI Image Analysis'), findsOneWidget);
    expect(find.text('Card'), findsOneWidget);

    await tester.tap(find.text('Card'));
    await tester.pump();

    expect(cardText, contains('traceable evidence chain'));
  });
}
