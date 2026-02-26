import 'package:anx_reader/service/rag/semantic_search_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SemanticSearchLibrary builds safe FTS query for hyphen tokens', () {
    final service = SemanticSearchLibrary();

    final ftsQuery = service.debugBuildFtsQuery('GLM-5 论文 主要 内容');

    // GLM-5 must be quoted, otherwise SQLite FTS5 can raise:
    // "no such column: 5".
    expect(ftsQuery, contains('"GLM-5"'));
    expect(ftsQuery, contains('论文'));
  });
}
