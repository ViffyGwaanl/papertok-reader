import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/service/ai/ai_seminar_text_normalizer.dart';

void main() {
  test('normalizes seminar evidence ids into readable labels', () {
    final text = normalizeSeminarDisplayText(
      'Use (current-2), e3 and evidence-4.',
      evidenceLabelBuilder: (number) => '证据$number',
    );

    expect(text, 'Use 证据2, 证据3 and 证据4.');
    expect(
      seminarEvidenceLabelFromInternalId(
        'e3',
        evidenceLabelBuilder: (number) => '证据$number',
      ),
      '证据3',
    );
  });
}
