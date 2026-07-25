import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:ai_provider_kit/ai_provider_kit.dart';
import 'package:papertok_reader/service/ai/ai_seminar_provider_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  void configureProvider({bool withCapability = true}) {
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
    if (withCapability) {
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
  }

  test(
      'resolves selected provider model and cached capability for seminar transparency',
      () {
    configureProvider();

    final diagnostics = const AiSeminarProviderContextService().resolve();

    expect(diagnostics.providerId, 'local-gateway');
    expect(diagnostics.providerName, 'Local Gateway');
    expect(diagnostics.modelId, 'gpt-5.5');
    expect(diagnostics.contextWindow, 128000);
    expect(diagnostics.maxOutputTokens, 8192);
    expect(diagnostics.supportsTools, true);
    expect(diagnostics.supportsImages, true);
    expect(diagnostics.supportsThinking, true);
    expect(diagnostics.supportsStreaming, isNull);
    expect(diagnostics.hasCapabilityCache, true);
    expect(diagnostics.seminarReady, true);
  });

  test('reports cost unknown when pricing metadata is unavailable', () {
    configureProvider(withCapability: false);

    final diagnostics = const AiSeminarProviderContextService().resolve();

    expect(diagnostics.costStatus, AiSeminarCostStatus.unknown);
    expect(diagnostics.costUnknownReason, contains('pricing metadata'));
    expect(diagnostics.estimatedCostUsd, isNull);
  });

  test('exposes pricing metadata for Seminar cost caps', () {
    configureProvider();

    final diagnostics = const AiSeminarProviderContextService().resolve();

    expect(diagnostics.costStatus, AiSeminarCostStatus.estimated);
    expect(diagnostics.inputCostPerMillionTokens, 2);
    expect(diagnostics.outputCostPerMillionTokens, 8);
    expect(diagnostics.cacheReadCostPerMillionTokens, 0.2);
    expect(diagnostics.cacheWriteCostPerMillionTokens, 1);
    expect(diagnostics.costPriceSource, 'test-pricing-v1');
    expect(diagnostics.costUnknownReason, isNull);
  });

  test('keeps model visible while warning when capability cache is missing',
      () {
    configureProvider(withCapability: false);

    final diagnostics = const AiSeminarProviderContextService().resolve();

    expect(diagnostics.providerName, 'Local Gateway');
    expect(diagnostics.modelId, 'gpt-5.5');
    expect(diagnostics.hasCapabilityCache, false);
    expect(diagnostics.seminarReady, true);
    expect(
        diagnostics.warnings, contains('Model capability cache is missing.'));
  });

  test('does not claim streaming support when provider metadata lacks it', () {
    configureProvider();

    final diagnostics = const AiSeminarProviderContextService().resolve();

    expect(diagnostics.supportsStreaming, isNull);
    expect(diagnostics.warnings, isNot(contains('Streaming unsupported.')));
  });

  test('restored estimated cost without amount degrades to unknown', () {
    final diagnostics = AiSeminarProviderDiagnostics.fromJson(const {
      'providerId': 'local-gateway',
      'providerName': 'Local Gateway',
      'providerType': 'openai',
      'modelId': 'gpt-5.5',
      'hasProviderConfig': true,
      'hasCapabilityCache': true,
      'seminarReady': true,
      'costStatus': 'estimated',
    });

    expect(diagnostics.costStatus, AiSeminarCostStatus.unknown);
    expect(diagnostics.estimatedCostUsd, isNull);
    expect(diagnostics.costUnknownReason, contains('usage metadata'));
  });
}
