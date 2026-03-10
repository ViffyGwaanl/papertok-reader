import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/providers/ai_chat.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('beginFreshConversation clears current ai chat session state', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider.future);

    container.read(aiChatProvider.notifier).restore(
      [
        ChatMessage.humanText('hello'),
        ChatMessage.ai('world'),
      ],
      sessionId: 'session-1',
    );

    expect(
        container.read(aiChatProvider.notifier).currentSessionId, 'session-1');
    expect(container.read(aiChatProvider).value, isNotEmpty);

    container
        .read(aiChatProvider.notifier)
        .beginFreshConversation(container, persistCurrent: false);

    expect(container.read(aiChatProvider.notifier).currentSessionId, isNull);
    expect(container.read(aiChatProvider).value, isEmpty);
  });
}
