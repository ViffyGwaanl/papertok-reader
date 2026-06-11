import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/service/ai/tools/start_seminar_tool.dart';

void main() {
  test('start seminar tool accepts question and optional scope override',
      () async {
    final input = StartSeminarInput.fromJson({
      'question': 'Discuss the central claim.',
      'scope': 'library',
    });

    expect(input.question, 'Discuss the central claim.');
    expect(input.evidenceScopes, [AiSeminarEvidenceScope.library]);

    final result = await StartSeminarTool().run(input);

    expect(result['ok'], isTrue);
    expect(result['question'], 'Discuss the central claim.');
    expect(result['scopeIds'], ['library']);
    expect(result['messageKey'], 'aiToolStartSeminarLaunched');
  });

  test('start seminar tool rejects empty questions', () {
    expect(
      () => StartSeminarInput.fromJson({'question': '  '}),
      throwsArgumentError,
    );
  });
}
