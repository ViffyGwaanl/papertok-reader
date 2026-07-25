import 'package:ai_provider_kit/ai_provider_kit.dart';
import 'package:test/test.dart';

void main() {
  group('deriveAiBaseUrl', () {
    test('strips well-known operation suffixes', () {
      expect(
        deriveAiBaseUrl('https://api.openai.com/v1/chat/completions'),
        'https://api.openai.com/v1',
      );
      expect(
        deriveAiBaseUrl('https://api.anthropic.com/v1/messages'),
        'https://api.anthropic.com/v1',
      );
      expect(
        deriveAiBaseUrl('https://api.openai.com/v1/responses'),
        'https://api.openai.com/v1',
      );
    });

    test('leaves a bare base untouched and handles empties', () {
      expect(
        deriveAiBaseUrl('https://generativelanguage.googleapis.com'),
        'https://generativelanguage.googleapis.com',
      );
      expect(deriveAiBaseUrl(''), isNull);
      expect(deriveAiBaseUrl(null), isNull);
    });

    test('drops a trailing slash', () {
      expect(deriveAiBaseUrl('https://host/v1/'), 'https://host/v1');
    });
  });

  group('parseAiHeaders', () {
    test('accepts JSON and k=v;k=v', () {
      expect(parseAiHeaders('{"a":"1","b":"2"}'), {'a': '1', 'b': '2'});
      expect(parseAiHeaders('a=1;b=2'), {'a': '1', 'b': '2'});
      expect(parseAiHeaders(null), isEmpty);
      expect(parseAiHeaders('   '), isEmpty);
    });
  });

  group('AiEndpointConfig.fromRawConfig', () {
    test('reads the stored provider config shape', () {
      final config = AiEndpointConfig.fromRawConfig('openai', {
        'api_key': 'sk-test',
        'model': 'gpt-4o-mini',
        'url': 'https://api.openai.com/v1/chat/completions',
        'temperature': '0.7',
        'top_p': '0.9',
        'max_tokens': '1024',
        'max_output_tokens': '2048',
        'headers': '{"X-Trace":"1"}',
        'extra': '{"foo":"bar"}',
      });

      expect(config.identifier, 'openai');
      expect(config.apiKey, 'sk-test');
      expect(config.model, 'gpt-4o-mini');
      expect(config.baseUrl, 'https://api.openai.com/v1');
      expect(config.temperature, 0.7);
      expect(config.topP, 0.9);
      expect(config.maxTokens, 1024);
      expect(config.maxOutputTokens, 2048);
      expect(config.headers, {'X-Trace': '1'});
      expect(config.additional, {'foo': 'bar'});
    });

    test('defaults thinking mode to auto when unset', () {
      final config = AiEndpointConfig.fromRawConfig('openai', const {});
      expect(config.thinkingMode, AiThinkingMode.auto);
      expect(config.model, isEmpty);
      expect(config.apiKey, isEmpty);
      expect(config.baseUrl, isNull);
    });

    test('include_thoughts is opt-in, responses flags are opt-out', () {
      AiEndpointConfig withRaw(Map<String, String> raw) =>
          AiEndpointConfig.fromRawConfig('openai', raw);

      // Opt-in: only affirmative values enable it.
      expect(withRaw(const {}).includeThoughts, isFalse);
      expect(withRaw({'include_thoughts': 'true'}).includeThoughts, isTrue);
      expect(withRaw({'include_thoughts': '1'}).includeThoughts, isTrue);
      expect(withRaw({'include_thoughts': 'yes'}).includeThoughts, isTrue);
      expect(withRaw({'include_thoughts': 'on'}).includeThoughts, isFalse);

      // Opt-out: unset stays null, anything but a negative means enabled.
      expect(
        withRaw(const {}).responsesUsePreviousResponseId,
        isNull,
      );
      expect(
        withRaw({'responses_use_previous_response_id': ''})
            .responsesUsePreviousResponseId,
        isNull,
      );
      expect(
        withRaw({'responses_use_previous_response_id': 'false'})
            .responsesUsePreviousResponseId,
        isFalse,
      );
      expect(
        withRaw({'responses_use_previous_response_id': 'anything'})
            .responsesUsePreviousResponseId,
        isTrue,
      );
      expect(
        withRaw({'responses_request_reasoning_summary': 'no'})
            .responsesRequestReasoningSummary,
        isFalse,
      );
    });
  });

  group('mergedWith', () {
    test('override wins for non-empty values, headers merge key-wise', () {
      final base = AiEndpointConfig(
        identifier: 'openai',
        model: 'base-model',
        apiKey: 'base-key',
        baseUrl: 'https://base',
        headers: const {'keep': 'yes', 'shared': 'base'},
        temperature: 0.1,
        additional: const {'a': 1},
      );
      final override = AiEndpointConfig(
        identifier: 'openai',
        model: 'override-model',
        apiKey: '',
        headers: const {'shared': 'override', 'added': 'yes'},
        additional: const {'b': 2},
      );

      final merged = base.mergedWith(override);

      expect(merged.model, 'override-model');
      expect(merged.apiKey, 'base-key', reason: 'empty override must not win');
      expect(merged.baseUrl, 'https://base');
      expect(merged.temperature, 0.1);
      expect(merged.headers,
          {'keep': 'yes', 'shared': 'override', 'added': 'yes'});
      expect(merged.additional, {'a': 1, 'b': 2});
    });
  });

  group('registryIdentifierForAiProvider', () {
    AiProviderMeta metaOf(AiProviderType type) => AiProviderMeta(
          id: 'x',
          name: 'x',
          type: type,
          enabled: true,
          isBuiltIn: false,
          createdAt: 0,
          updatedAt: 0,
        );

    test('maps every provider type to a stable identifier', () {
      expect(registryIdentifierForAiProvider(null), 'openai');
      expect(
        registryIdentifierForAiProvider(metaOf(AiProviderType.openaiCompatible)),
        'openai',
      );
      expect(
        registryIdentifierForAiProvider(metaOf(AiProviderType.openaiResponses)),
        'openai-responses',
      );
      expect(
        registryIdentifierForAiProvider(metaOf(AiProviderType.anthropic)),
        'claude',
      );
      expect(
        registryIdentifierForAiProvider(metaOf(AiProviderType.gemini)),
        'gemini',
      );
    });
  });
}
