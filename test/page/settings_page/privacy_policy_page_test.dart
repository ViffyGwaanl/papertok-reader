import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/page/settings_page/subpage/privacy_policy_page.dart';

void main() {
  testWidgets('privacy page renders all three sections offline',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: PrivacyPolicyPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your data lives on this device'), findsOneWidget);
    expect(find.text('When data leaves this device'), findsOneWidget);
    expect(find.text('No tracking'), findsOneWidget);
  });
}
