import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/service/sync/ai_settings_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('AI settings sync includes library rerank settings without secrets', () {
    Prefs().aiLibraryIndexRerankEnabled = true;
    Prefs().aiLibraryIndexRerankFollowIndexProvider = false;
    Prefs().aiLibraryIndexRerankProviderId = 'local-rag';
    Prefs().aiLibraryIndexRerankModel = 'Qwen/Qwen3-Reranker-8B';
    Prefs().aiLibraryIndexRerankInstruction = 'Prefer direct answers.';
    Prefs().aiLibraryIndexRerankMaxCandidates = 24;
    Prefs().aiLibraryIndexRerankTimeoutSeconds = 33;

    final json = buildLocalAiSettingsJson();
    final libraryIndex = json['libraryIndex'] as Map<String, dynamic>;

    expect(libraryIndex['aiLibraryIndexRerankEnabledV1'], true);
    expect(libraryIndex['aiLibraryIndexRerankFollowIndexProviderV1'], false);
    expect(libraryIndex['aiLibraryIndexRerankProviderIdV1'], 'local-rag');
    expect(
      libraryIndex['aiLibraryIndexRerankModelV1'],
      'Qwen/Qwen3-Reranker-8B',
    );
    expect(
      libraryIndex['aiLibraryIndexRerankInstructionV1'],
      'Prefer direct answers.',
    );
    expect(libraryIndex['aiLibraryIndexRerankMaxCandidatesV1'], 24);
    expect(libraryIndex['aiLibraryIndexRerankTimeoutSecV1'], 33);
    expect(libraryIndex.values.join(' '), isNot(contains('sk-')));
  });

  test('AI settings sync applies library rerank settings', () {
    applyAiSettingsJson({
      'schemaVersion': aiSettingsSchemaVersion,
      'updatedAt': 123,
      'libraryIndex': {
        'aiLibraryIndexRerankEnabledV1': true,
        'aiLibraryIndexRerankFollowIndexProviderV1': false,
        'aiLibraryIndexRerankProviderIdV1': 'local-rag',
        'aiLibraryIndexRerankModelV1': 'Qwen/Qwen3-Reranker-8B',
        'aiLibraryIndexRerankInstructionV1': 'Prefer direct answers.',
        'aiLibraryIndexRerankMaxCandidatesV1': 24,
        'aiLibraryIndexRerankTimeoutSecV1': 33,
      },
    });

    expect(Prefs().aiLibraryIndexRerankEnabled, true);
    expect(Prefs().aiLibraryIndexRerankFollowIndexProvider, false);
    expect(Prefs().aiLibraryIndexRerankProviderId, 'local-rag');
    expect(
      Prefs().aiLibraryIndexRerankModel,
      'Qwen/Qwen3-Reranker-8B',
    );
    expect(Prefs().aiLibraryIndexRerankInstruction, 'Prefer direct answers.');
    expect(Prefs().aiLibraryIndexRerankMaxCandidates, 24);
    expect(Prefs().aiLibraryIndexRerankTimeoutSeconds, 33);
  });
}
