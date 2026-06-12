import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/widgets/ai/seminar/composer/seminar_reader_composer_policy.dart';

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
        ' 围绕这条分歧找证据验证 ',
      ),
      '围绕这条分歧找证据验证',
    );
    expect(
      seminarReaderComposerSubmittedText(
        AiSeminarUserInterventionAction.synthesize,
        ' 请先出总结 ',
      ),
      '请先出总结',
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
