import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:papertok_reader/service/ai/ai_history.dart';

void main() {
  test('AiChatHistoryEntry serializes book metadata and reads legacy json', () {
    final entry = AiChatHistoryEntry(
      id: 'session-1',
      serviceId: 'openai',
      model: 'gpt-test',
      createdAt: 1,
      updatedAt: 2,
      title: 'Book chat',
      titleSource: 'heuristic',
      messages: [ChatMessage.humanText('Question')],
      completed: true,
      bookId: 42,
      bookTitle: 'Current Book',
    );

    final json = entry.toJson();

    expect(json['bookId'], 42);
    expect(json['bookTitle'], 'Current Book');

    final roundTrip = AiChatHistoryEntry.fromJson(json);
    expect(roundTrip.bookId, 42);
    expect(roundTrip.bookTitle, 'Current Book');

    final legacy = AiChatHistoryEntry.fromJson({
      'id': 'legacy-session',
      'serviceId': 'openai',
      'model': 'gpt-test',
      'createdAt': 1,
      'updatedAt': 2,
      'completed': true,
      'messages': [
        ChatMessage.humanText('Legacy question').toMap(),
      ],
    });

    expect(legacy.bookId, isNull);
    expect(legacy.bookTitle, isNull);
  });

  test('filterAiHistoryForBook keeps current book separate from all history',
      () {
    AiChatHistoryEntry entry({
      required String id,
      int? bookId,
    }) {
      return AiChatHistoryEntry(
        id: id,
        serviceId: 'openai',
        model: 'gpt-test',
        createdAt: 1,
        updatedAt: 2,
        messages: [ChatMessage.humanText(id)],
        completed: true,
        bookId: bookId,
      );
    }

    final items = [
      entry(id: 'current', bookId: 7),
      entry(id: 'other', bookId: 8),
      entry(id: 'legacy'),
    ];

    expect(
      filterAiHistoryForBook(
        items,
        currentBookId: 7,
        scope: AiHistoryScope.currentBook,
      ).map((e) => e.id),
      ['current'],
    );

    expect(
      filterAiHistoryForBook(
        items,
        currentBookId: 7,
        scope: AiHistoryScope.all,
      ).map((e) => e.id),
      ['current', 'other', 'legacy'],
    );
  });
}
