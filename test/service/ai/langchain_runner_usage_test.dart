import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:langchain_core/language_models.dart';
import 'package:langchain_core/prompts.dart';
import 'package:langchain_core/tools.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/service/ai/agent_tool_call_event.dart';
import 'package:papertok_reader/service/ai/ai_usage_tracker.dart';
import 'package:papertok_reader/service/ai/langchain_runner.dart';
import 'package:papertok_reader/service/ai/tool_approval_delegate.dart';
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

  test('agent stream emits tool call events while executing tools', () async {
    final events = <AgentToolCallEvent>[];
    final runner = CancelableLangchainRunner(
      approvalDelegate: (_) async => const ToolApprovalResult(
        approved: true,
        remember: false,
      ),
    );
    final model = _ScriptedChatModel([
      [
        const ChatResult(
          id: 'tool-call-chunk',
          output: AIChatMessage(
            content: '',
            toolCalls: [
              AIChatMessageToolCall(
                id: 'call-calc-1',
                name: 'calculator',
                argumentsRaw: '{"expression":"6*7"}',
                arguments: {'expression': '6*7'},
              ),
            ],
          ),
          finishReason: FinishReason.stop,
          metadata: {},
          usage: LanguageModelUsage(promptTokens: 10, responseTokens: 1),
          streaming: false,
        ),
      ],
      [
        const ChatResult(
          id: 'final-chunk',
          output: AIChatMessage(content: 'The result is 42.'),
          finishReason: FinishReason.stop,
          metadata: {},
          usage: LanguageModelUsage(promptTokens: 12, responseTokens: 5),
          streaming: false,
        ),
      ],
    ]);
    final calculator = Tool.fromFunction<Map<String, dynamic>, String>(
      name: 'calculator',
      description: 'calculator',
      inputJsonSchema: const {'type': 'object'},
      func: (input) => '42',
    );

    final outputs = await runner
        .streamAgent(
          model: model,
          tools: [calculator],
          history: const [],
          inputMessage:
              ChatMessage.humanText('Calculate 6*7') as HumanChatMessage,
          maxIterations: 3,
          toolCallObserver: events.add,
        )
        .toList();

    expect(outputs.last, contains('<reply'));
    expect(outputs.join(), contains("call_id='call-calc-1'"));
    expect(events.map((event) => event.status), [
      AgentToolCallEventStatus.running,
      AgentToolCallEventStatus.completed,
    ]);
    expect(events.first.callId, 'call-calc-1');
    expect(events.first.toolId, 'calculator');
    expect(events.first.input, {'expression': '6*7'});
    expect(events.last.output, '42');
    expect(events.last.error, isNull);
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

class _ScriptedChatModel extends BaseChatModel<_FakeChatOptions> {
  _ScriptedChatModel(this.streams)
      : super(defaultOptions: const _FakeChatOptions(model: 'scripted-model'));

  final List<List<ChatResult>> streams;
  int _streamIndex = 0;

  @override
  String get modelType => 'scripted-chat-model';

  @override
  Future<ChatResult> invoke(PromptValue input, {_FakeChatOptions? options}) {
    final stream = streams[_streamIndex.clamp(0, streams.length - 1)];
    return Future.value(stream.last);
  }

  @override
  Stream<ChatResult> stream(PromptValue input, {_FakeChatOptions? options}) {
    final index = _streamIndex.clamp(0, streams.length - 1);
    _streamIndex += 1;
    return Stream<ChatResult>.fromIterable(streams[index]);
  }

  @override
  Future<List<int>> tokenize(PromptValue promptValue,
      {_FakeChatOptions? options}) {
    return Future.value(const <int>[]);
  }
}
