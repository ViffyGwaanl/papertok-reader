import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/service/ai/index.dart';

void main() {
  test('mergeStreamErrorWithPartial preserves generated text', () {
    final merged = mergeStreamErrorWithPartial(
      'Already generated answer.',
      'Error: ClientException: Connection closed while receiving data',
    );

    expect(
      merged,
      'Already generated answer.\n\n'
      'Error: ClientException: Connection closed while receiving data',
    );
  });

  test('mergeStreamErrorWithPartial returns error when no text exists', () {
    expect(
      mergeStreamErrorWithPartial('', 'Error: Request timed out'),
      'Error: Request timed out',
    );
  });
}
