import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/page/home_page/settings_page.dart';
import 'package:papertok_reader/page/settings_page/ai.dart';
import 'package:papertok_reader/page/settings_page/concept_graph_explorer.dart';
import 'package:papertok_reader/page/settings_page/review_inbox.dart';
import 'package:papertok_reader/page/settings_page/spaced_review.dart';

void main() {
  test('AI settings navigation widgets compile', () {
    expect(const SettingsPage(), isA<SettingsPage>());
    expect(const AISettings(), isA<AISettings>());
    expect(const ReviewInboxPage(), isA<ReviewInboxPage>());
    expect(const ConceptGraphExplorerPage(), isA<ConceptGraphExplorerPage>());
    expect(const SpacedReviewPage(), isA<SpacedReviewPage>());
  });
}
