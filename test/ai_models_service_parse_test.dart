import 'package:ai_provider_kit/ai_provider_kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AiModelsService registryIdentifierFor maps types', () {
    expect(
      AiModelsService.registryIdentifierFor(
        AiProviderMeta(
          id: 'x',
          name: 'x',
          type: AiProviderType.openaiCompatible,
          enabled: true,
          isBuiltIn: false,
          createdAt: 0,
          updatedAt: 0,
        ),
      ),
      'openai',
    );
    expect(
      AiModelsService.registryIdentifierFor(
        AiProviderMeta(
          id: 'x',
          name: 'x',
          type: AiProviderType.anthropic,
          enabled: true,
          isBuiltIn: false,
          createdAt: 0,
          updatedAt: 0,
        ),
      ),
      'claude',
    );
    expect(
      AiModelsService.registryIdentifierFor(
        AiProviderMeta(
          id: 'x',
          name: 'x',
          type: AiProviderType.gemini,
          enabled: true,
          isBuiltIn: false,
          createdAt: 0,
          updatedAt: 0,
        ),
      ),
      'gemini',
    );
  });
}
