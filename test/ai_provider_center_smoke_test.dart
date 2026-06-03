import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/page/settings_page/ai_provider_center/ai_provider_center_page.dart';
import 'package:papertok_reader/page/settings_page/ai_provider_center/ai_provider_detail_page.dart';
import 'package:papertok_reader/models/ai_provider_meta.dart';
import 'package:papertok_reader/service/ai/ai_services.dart';
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

  testWidgets('AiProviderDetailPage localizes API key controls in Chinese',
      (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = AiProviderMeta(
      id: 'openai-responses',
      name: 'OpenAI Responses',
      type: AiProviderType.openaiResponses,
      enabled: true,
      isBuiltIn: true,
      createdAt: 0,
      updatedAt: 0,
    );
    const option = AiServiceOption(
      identifier: 'openai-responses',
      title: 'OpenAI Responses',
      logo: 'assets/images/openai.png',
      defaultUrl: 'https://api.openai.com/v1/responses',
      defaultApiKey: 'YOUR_API_KEY',
      defaultModel: 'gpt-5-mini',
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: AiProviderDetailPage(
          provider: provider,
          builtInOption: option,
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('API 密钥'), findsOneWidget);
    expect(find.byTooltip('导入'), findsOneWidget);
    expect(find.byTooltip('添加'), findsOneWidget);
    expect(find.byTooltip('测试'), findsWidgets);
    expect(find.text('未配置 API 密钥。'), findsOneWidget);
    expect(find.textContaining('密钥仅保存在本机'), findsOneWidget);
    expect(find.text('API Keys'), findsNothing);
    expect(find.text('No API keys configured.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
