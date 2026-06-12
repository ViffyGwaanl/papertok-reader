import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/widgets/ai/seminar/seminar_reader_composer_policy.dart';

void main() {
  test('reader composer submit policy separates one-click and text actions',
      () {
    expect(
      seminarReaderComposerActionRequiresText(
        AiSeminarUserInterventionAction.askRole,
      ),
      false,
    );
    expect(
      seminarReaderComposerActionRequiresText(
        AiSeminarUserInterventionAction.refreshEvidence,
      ),
      false,
    );
    expect(
      seminarReaderComposerActionRequiresText(
        AiSeminarUserInterventionAction.synthesize,
      ),
      false,
    );
    expect(
      seminarReaderComposerActionRequiresText(
        AiSeminarUserInterventionAction.clarify,
      ),
      true,
    );
    expect(
      seminarReaderComposerSubmittedText(
        AiSeminarUserInterventionAction.refreshEvidence,
        ' ignored ',
      ),
      '',
    );
    expect(
      seminarReaderComposerActionSubmitsImmediately(
        AiSeminarUserInterventionAction.refreshEvidence,
      ),
      true,
    );
    expect(
      seminarReaderComposerActionSubmitsImmediately(
        AiSeminarUserInterventionAction.synthesize,
      ),
      true,
    );
    expect(
      seminarReaderComposerActionSubmitsImmediately(
        AiSeminarUserInterventionAction.askRole,
      ),
      false,
    );
    expect(
      seminarReaderComposerSubmittedText(
        AiSeminarUserInterventionAction.askRole,
        ' optional ',
      ),
      'optional',
    );
    expect(
      seminarReaderComposerCanSubmit(
        AiSeminarUserInterventionAction.clarify,
        '',
        false,
      ),
      false,
    );
    expect(
      seminarReaderComposerCanSubmit(
        AiSeminarUserInterventionAction.clarify,
        ' my point ',
        false,
      ),
      true,
    );
  });
}
