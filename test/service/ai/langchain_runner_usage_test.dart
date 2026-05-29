import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:langchain_core/language_models.dart';
import 'package:langchain_core/prompts.dart';
import 'package:langchain_core/tools.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/service/ai/ai_usage_tracker.dart';
import 'package:papertok_reader/service/ai/langchain_runner.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('plain stream records usage tracker once after completion', () async {
    final tracker = AiUsageTracker();
    final runner = CancelableLangchainRunner();
    final model = _FakeChatModel(
      const [
        ChatResult(
          id: 'chunk-1',
          output: AIChatMessage(content: 'Hel'),
          finishReason: FinishReason.unspecified,
          metadata: {},
          usage: LanguageModelUsage(promptTokens: 12, responseTokens: 1),
          streaming: true,
        ),
        ChatResult(
          id: 'chunk-2',
          output: AIChatMessage(content: 'lo'),
          finishReason: FinishReason.stop,
          metadata: {},
          usage: LanguageModelUsage(responseTokens: 2),
          streaming: false,
        ),
      ],
    );

    final outputs = await runner
        .stream(
          model: model,
          prompt: PromptValue.chat([ChatMessage.humanText('Say hello')]),
          usageTracker: tracker,
        )
        .toList();

    expect(outputs, ['Hel', 'Hello']);
    expect(tracker.inputTokens, 12);
    expect(tracker.outputTokens, 3);
    expect(tracker.apiCalls, 1);
  });
}

class _FakeChatOptions extends ChatModelOptions {
  const _FakeChatOptions({super.model});

  @override
  _FakeChatOptions copyWith({
    String? model,
    List<ToolSpec>? tools,
    ChatToolChoice? toolChoice,
    int? concurrencyLimit,
  }) {
    return _FakeChatOptions(model: model ?? this.model);
  }
}

class _FakeChatModel extends BaseChatModel<_FakeChatOptions> {
  const _FakeChatModel(this.chunks)
      : super(defaultOptions: const _FakeChatOptions(model: 'fake-model'));

  final List<ChatResult> chunks;

  @override
  String get modelType => 'fake-chat-model';

  @override
  Future<ChatResult> invoke(PromptValue input, {_FakeChatOptions? options}) {
    return Future.value(chunks.last);
  }

  @override
  Stream<ChatResult> stream(PromptValue input, {_FakeChatOptions? options}) {
    return Stream<ChatResult>.fromIterable(chunks);
  }

  @override
  Future<List<int>> tokenize(PromptValue promptValue,
      {_FakeChatOptions? options}) {
    return Future.value(const <int>[]);
  }
}
