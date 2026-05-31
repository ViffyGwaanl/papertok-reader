import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/book.dart';
import 'package:papertok_reader/models/current_reading_state.dart';
import 'package:papertok_reader/providers/current_reading.dart';
import 'package:papertok_reader/service/ai/tools/semantic_search_current_book_tool.dart';
import 'package:papertok_reader/service/rag/semantic_search_current_book.dart';

void main() {
  test('semantic current-book tool cancels scan on timeout', () async {
    late AiCurrentBookSearchCancellationToken capturedToken;
    final toolProvider = Provider(
      (ref) => SemanticSearchCurrentBookTool(
        ref,
        searchTimeout: const Duration(milliseconds: 10),
        search: ({
          required int bookId,
          required String query,
          required int maxResults,
          AiCurrentBookSearchCancellationToken? cancelToken,
        }) {
          capturedToken = cancelToken!;
          return Completer<AiSemanticSearchResult>().future;
        },
      ),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(currentReadingProvider.notifier).start(
          CurrentReadingState(
            book: Book.mock().copyWith(id: 34, title: 'Hot Book'),
          ),
        );

    final result = await container.read(toolProvider).run({
      'query': 'needle',
      'maxResults': 3,
    });

    expect(capturedToken.isCancelled, true);
    expect(result['ok'], false);
    expect(result['cancelled'], true);
    expect(result['message'], contains('timeout'));
  });
}
