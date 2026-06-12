import 'package:papertok_reader/models/ai_seminar.dart';

enum SeminarParticipationQuickAction {
  continueDiscussion('continue-discussion'),
  alternateAngle('alternate-angle'),
  refreshEvidence('refresh-evidence'),
  synthesize('synthesize');

  const SeminarParticipationQuickAction(this.id);

  final String id;

  AiSeminarUserInterventionAction get interventionAction {
    return switch (this) {
      SeminarParticipationQuickAction.continueDiscussion ||
      SeminarParticipationQuickAction.alternateAngle =>
        AiSeminarUserInterventionAction.askRole,
      SeminarParticipationQuickAction.refreshEvidence =>
        AiSeminarUserInterventionAction.refreshEvidence,
      SeminarParticipationQuickAction.synthesize =>
        AiSeminarUserInterventionAction.synthesize,
    };
  }
}

List<AiSeminarUserInterventionAction> seminarReaderComposerActions() {
  return const [
    AiSeminarUserInterventionAction.askRole,
    AiSeminarUserInterventionAction.refreshEvidence,
    AiSeminarUserInterventionAction.synthesize,
    AiSeminarUserInterventionAction.clarify,
  ];
}

bool seminarReaderComposerActionRequiresText(
  AiSeminarUserInterventionAction action,
) {
  return action == AiSeminarUserInterventionAction.clarify;
}

bool seminarReaderComposerActionUsesRole(
  AiSeminarUserInterventionAction action,
) {
  return action == AiSeminarUserInterventionAction.askRole ||
      action == AiSeminarUserInterventionAction.clarify;
}

bool seminarReaderComposerActionShowsTextField(
  AiSeminarUserInterventionAction action,
) {
  return action == AiSeminarUserInterventionAction.askRole ||
      action == AiSeminarUserInterventionAction.clarify;
}

bool seminarReaderComposerActionSubmitsImmediately(
  AiSeminarUserInterventionAction action,
) {
  return action == AiSeminarUserInterventionAction.refreshEvidence ||
      action == AiSeminarUserInterventionAction.synthesize;
}

String seminarReaderComposerSubmittedText(
  AiSeminarUserInterventionAction action,
  String draftText,
) {
  return draftText.trim();
}

bool seminarReaderComposerCanSubmit(
  AiSeminarUserInterventionAction action,
  String draftText,
  bool isSubmitting,
) {
  if (isSubmitting) return false;
  if (!seminarReaderComposerActionRequiresText(action)) return true;
  return draftText.trim().isNotEmpty;
}
