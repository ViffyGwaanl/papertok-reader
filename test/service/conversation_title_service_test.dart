import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/ai/conversation_title_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'aiTitleGenerationEnabledV1': false,
      'aiTitleMaxCharsV1': 16,
    });
    await Prefs().initPrefs();
  });

  test('deriveFallbackTitle uses first human line and trims punctuation', () {
    const service = ConversationTitleService();
    final title = service.deriveFallbackTitle(const [
      HumanChatMessage(
        content: ChatMessageContentText(text: '怎么做 Memory workflow。\n第二行'),
      ),
      AIChatMessage(content: '可以先做 candidate inbox'),
    ]);

    expect(title, '怎么做 Memory workf');
  });

  test('generateTitle falls back when automatic title generation is disabled',
      () async {
    const service = ConversationTitleService();
    final title = await service.generateTitle(const [
      HumanChatMessage(
        content: ChatMessageContentText(text: '给这段对话起一个标题'),
      ),
      AIChatMessage(content: '好的'),
    ]);

    expect(title, '给这段对话起一个标题');
  });
}
