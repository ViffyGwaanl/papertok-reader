import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/widgets/ai/seminar/seminar_evidence_numbering.dart';

void main() {
  test('evidence numbering follows broker ids with fallback order', () {
    expect(seminarEvidenceNumberFromId('current-3'), 3);
    expect(seminarEvidenceNumberFromId('e2'), 2);
    expect(seminarEvidenceNumberFromId('evidence-12'), 12);
    expect(seminarEvidenceNumberFromId('memory'), isNull);
    expect(seminarEvidenceLabel(id: 'current-3', zh: true), '证据3');
    expect(
        seminarEvidenceLabel(id: 'memory', fallbackIndex: 4, zh: true), '证据4');
    expect(seminarEvidenceLabel(id: 'current-2', zh: false), 'Evidence 2');
  });
}
