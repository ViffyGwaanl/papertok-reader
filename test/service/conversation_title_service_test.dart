import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/service/ai/conversation_title_service.dart';
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

  test('deriveFallbackTitle uses first AI reply line, not the question', () {
    const service = ConversationTitleService();
    final title = service.deriveFallbackTitle(const [
      HumanChatMessage(
        content: ChatMessageContentText(text: '怎么做 Memory workflow？'),
      ),
      AIChatMessage(content: 'Memory 分三步。\n第二行'),
    ]);

    expect(title, 'Memory 分三步');
  });

  test('deriveFallbackTitle returns Conversation when no AI reply', () {
    const service = ConversationTitleService();
    final title = service.deriveFallbackTitle(const [
      HumanChatMessage(
        content: ChatMessageContentText(text: '只有提问'),
      ),
    ]);

    expect(title, 'Conversation');
  });

  test('generateTitle falls back to first AI reply when disabled', () async {
    const service = ConversationTitleService();
    final title = await service.generateTitle(const [
      HumanChatMessage(
        content: ChatMessageContentText(text: '给这段对话起一个标题'),
      ),
      AIChatMessage(content: '好的，这是关于 RAG 的讨论'),
    ]);

    expect(title, '好的，这是关于 RAG 的讨论');
  });
}
