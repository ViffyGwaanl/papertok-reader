import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/ai_model_capability.dart';
import 'package:anx_reader/service/ai/prompt_budgeting_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('trimMessages keeps context untouched when capability is unknown', () {
    const service = PromptBudgetingService();
    final messages = List<ChatMessage>.generate(
      10,
      (index) => HumanChatMessage(
        content: ChatMessageContentText(text: 'message $index ' * 80),
      ),
    );

    final result = service.trimMessages(
      providerId: 'demo',
      config: const {'model': 'x'},
      messages: messages,
    );

    expect(result.trimmed, isFalse);
    expect(result.messages.length, messages.length);
  });

  test('trimMessages trims old messages when context window is known', () {
    Prefs().saveAiModelCapabilitiesCacheV1(
      'demo',
      const [
        AiModelCapability(
          id: 'small-model',
          contextWindow: 256,
          maxOutputTokens: 64,
        ),
      ],
    );

    const service = PromptBudgetingService();
    final messages = List<ChatMessage>.generate(
      12,
      (index) => HumanChatMessage(
        content: ChatMessageContentText(text: 'long message $index ' * 60),
      ),
    );

    final result = service.trimMessages(
      providerId: 'demo',
      config: const {'model': 'small-model'},
      messages: messages,
    );

    expect(result.contextWindow, 256);
    expect(result.trimmed, isTrue);
    expect(result.messages.length, lessThan(messages.length));
    expect(result.reservedOutputTokens, 64);
  });
}
