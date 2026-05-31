import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:papertok_reader/providers/toc_search.dart';

void main() {
  test('semantic search progress is observable and cancelled clears results',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(tocSearchProvider.notifier);

    notifier.start('needle');
    notifier.startSemanticSearch();
    notifier.updateSemanticProgress(0.42);

    var state = container.read(tocSearchProvider);
    expect(state.isSemanticSearching, true);
    expect(state.semanticProgress, 0.42);

    notifier.cancelSemanticSearch();

    state = container.read(tocSearchProvider);
    expect(state.isSemanticSearching, false);
    expect(state.semanticProgress, 0);
    expect(state.semanticResults, isEmpty);
  });
}
