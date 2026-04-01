import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/ai_provider_center/ai_provider_center_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('AiProviderCenterPage builds', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh', 'CN'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: AiProviderCenterPage(),
      ),
    );

    // Let the FutureBuilder complete one turn; avoid pumpAndSettle here because
    // this page may host timers/animations that keep the test alive.
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AiProviderCenterPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
