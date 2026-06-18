part of 'seminar_run_snapshot_view.dart';

typedef SeminarSnapshotLocalizedTextBuilder = String Function({
  required String zh,
  required String en,
});
typedef SeminarSnapshotToolCallsBuilder = List<AiSeminarRunCardToolCallSnapshot>
    Function(
  AiSeminarRunCardSnapshot snapshot, {
  required int? bookId,
  required List<String> evidenceScopeIds,
});
typedef SeminarSnapshotNativeTimelinePartsBuilder
    = List<AiSeminarRunCardMessagePart> Function(
  AiSeminarRunCardSnapshot snapshot, {
  required int? bookId,
  required List<String> evidenceScopeIds,
});
typedef SeminarSnapshotNativeTimelinePredicate = bool Function(
  AiSeminarRunCardSnapshot snapshot,
  List<AiSeminarRunCardMessagePart> parts, {
  required bool allowLegacySnapshotContent,
});
typedef SeminarSnapshotTimelinePartViewBuilder = Widget Function(
  AiSeminarRunCardMessagePart part, {
  required String? sessionId,
  required int? bookId,
  required bool showInlineEvidence,
  required bool showTraceDetails,
  required int? roleTurnNumber,
});
typedef SeminarSnapshotDirectorCueBuilder = Widget Function(
  AiSeminarRunCardMessagePart part, {
  required String? sessionId,
});
typedef SeminarSnapshotAgentControlActionBuilder = Widget Function(
  AiSeminarRunCardMessagePart part, {
  required String actionId,
  required String? sessionId,
});
typedef SeminarSnapshotAllowedToolIdsBuilder = List<String> Function(
  List<String> toolIds, {
  required int? bookId,
});
typedef SeminarSnapshotAgentInputComposerBuilder = Widget? Function(
  AiSeminarRunCardMessagePart part, {
  required String? sessionId,
});
typedef SeminarSnapshotToolActionEnabledBuilder = bool Function(
  AiSeminarRunCardToolCallSnapshot toolCall, {
  required String actionId,
  required String? sessionId,
});
typedef SeminarSnapshotToolActionPressedBuilder = VoidCallback? Function(
  AiSeminarRunCardToolCallSnapshot toolCall, {
  required String actionId,
  required String? sessionId,
});
typedef SeminarSnapshotCountLabelBuilder = String Function(
  int count, {
  required String zhUnit,
  required String enSingular,
  required String enPlural,
});
typedef SeminarSnapshotSubviewSelectedCallback = void Function(
  String sessionId,
  SeminarRunSnapshotSubview subview,
);
typedef SeminarSnapshotTimelineExpansionCallback = void Function(
  String? sessionId,
  bool isExpanded,
);

class SeminarRunSnapshotBindings {
  const SeminarRunSnapshotBindings({
    required bool isChineseLocale,
    required Map<String, SeminarRunSnapshotSubview> snapshotSubviews,
    required Set<String> timelineExpandedSessionIds,
    required Set<String> submittingSessionIds,
    required String linkedEvidenceLabel,
    required String missingSourceLabel,
    required SeminarSnapshotLocalizedTextBuilder localizedSeminarCardText,
    required List<AiSeminarRunCardEvidenceSnapshot> Function(
      AiSeminarRunCardSnapshot snapshot,
    ) seminarSnapshotEvidence,
    required SeminarSnapshotToolCallsBuilder seminarSnapshotToolCalls,
    required List<AiSeminarRunCardRoleSummary> Function(
      AiSeminarRunCardSnapshot snapshot,
    ) seminarSnapshotRoleTurns,
    required List<AiSeminarRunCardMessagePart> Function(
      AiSeminarRunCardSnapshot snapshot,
    ) seminarSnapshotReaderTurns,
    required List<AiSeminarRunCardMessagePart> Function(
      AiSeminarRunCardSnapshot snapshot,
    ) seminarSnapshotReaderComposers,
    required List<AiSeminarRunCardMessagePart> Function(
      AiSeminarRunCardSnapshot snapshot,
    ) seminarSnapshotDirectorCues,
    required List<AiSeminarRunCardMessagePart> Function(
      AiSeminarRunCardSnapshot snapshot,
    ) seminarSnapshotAgentStatuses,
    required String? Function(AiSeminarRunCardSnapshot snapshot)
        seminarSnapshotSynthesisSummary,
    required List<AiSeminarRunCardEvidenceSnapshot> Function(
      AiSeminarRunCardSnapshot snapshot,
    ) seminarSnapshotSynthesisEvidenceRefs,
    required List<AiSeminarRunCardDisagreementDetail> Function(
      AiSeminarRunCardSnapshot snapshot,
    ) seminarSnapshotDisagreementDetailsFromParts,
    required List<AiSeminarRunCardMessagePart> Function(
      AiSeminarRunCardSnapshot snapshot,
    ) seminarSnapshotDisagreementRebuttals,
    required List<AiSeminarRunCardMessagePart> Function(
      AiSeminarRunCardSnapshot snapshot,
    ) seminarSnapshotContradictionScans,
    required List<AiSeminarRunCardRoleSummary> Function(
      AiSeminarRunCardSnapshot snapshot,
    ) seminarSnapshotRolePartials,
    required SeminarSnapshotNativeTimelinePartsBuilder
        seminarSnapshotNativeTimelineParts,
    required bool Function(AiSeminarRunCardSnapshot snapshot)
        seminarSnapshotHasLegacySnapshotContent,
    required List<AiSeminarRunCardMessagePart> Function(
      AiSeminarRunCardSnapshot snapshot,
    ) seminarSnapshotReviewTriageParts,
    required List<AiSeminarRunCardMessagePart> Function(
      AiSeminarRunCardSnapshot snapshot,
    ) seminarSnapshotArtifactActionParts,
    required List<AiSeminarRunCardMessagePart> Function(
      List<AiSeminarRunCardMessagePart> directorCues,
    ) seminarSnapshotControlDirectorCues,
    required List<AiSeminarRunCardMessagePart> Function(
      AiSeminarRunCardSnapshot snapshot,
    ) seminarSnapshotThinkingParts,
    required List<AiSeminarRunCardMessagePart> Function(
      AiSeminarRuntimeState state,
    ) seminarRuntimeThinkingParts,
    required List<AiSeminarRunCardMessagePart> Function(
      List<AiSeminarRunCardMessagePart> preferred,
      List<AiSeminarRunCardMessagePart> fallback,
    ) mergeSeminarNativeTimelineParts,
    required SeminarSnapshotNativeTimelinePredicate
        seminarSnapshotShouldUseNativeTimeline,
    required List<AiSeminarRunCardMessagePart> Function(
      List<AiSeminarRunCardMessagePart> parts,
    ) seminarSnapshotCompactNativeTimelineParts,
    required List<AiSeminarRunCardMessagePart> Function(
      List<AiSeminarRunCardMessagePart> parts,
    ) seminarSnapshotCollapsedNativeTimelineParts,
    required SeminarSnapshotTimelinePartViewBuilder seminarTimelinePartView,
    required SeminarSnapshotDirectorCueBuilder buildSeminarDirectorCueView,
    required String Function(String? status) seminarAgentStatusLabel,
    required String Function(String roleId) seminarRoleFallbackLabel,
    required SeminarSnapshotAgentControlActionBuilder
        buildSeminarAgentControlActionView,
    required SeminarSnapshotAllowedToolIdsBuilder
        effectiveSeminarStatusAllowedToolIds,
    required String Function(String toolId) seminarToolDisplayLabel,
    required SeminarSnapshotAgentInputComposerBuilder
        buildSeminarAgentInputComposerForPart,
    required Widget Function(AiSeminarRunCardMessagePart part)
        buildSeminarReaderComposerView,
    required Widget Function(AiSeminarRunCardMessagePart part)
        buildSeminarReaderTurnView,
    required IconData Function(String roleId) seminarRoleIconById,
    required void Function(AiSeminarRunCardEvidenceSnapshot evidence)
        jumpToSeminarEvidenceRow,
    required Widget? Function(SourceRef? sourceRef)
        seminarSnapshotEvidenceSourceAction,
    required String Function(AiSeminarRunCardToolCallSnapshot toolCall)
        seminarToolCallLabel,
    required String? Function(AiSeminarRunCardToolCallSnapshot toolCall)
        seminarToolCallStatusLabel,
    required String? Function(AiSeminarRunCardToolCallSnapshot toolCall)
        seminarToolCallStartedAtLabel,
    required String? Function(AiSeminarRunCardToolCallSnapshot toolCall)
        seminarToolCallCompletedAtLabel,
    required String? Function(AiSeminarRunCardToolCallSnapshot toolCall)
        seminarToolCallDurationLabel,
    required String Function(AiSeminarRunCardToolCallSnapshot toolCall)
        seminarToolCallVisibleRoleLabel,
    required String Function(AiSeminarRunCardToolCallSnapshot toolCall)
        seminarToolCallOutputLabel,
    required String Function(String? actionId) seminarToolCallActionLabel,
    required IconData Function(String actionId) seminarToolCallActionIcon,
    required SeminarSnapshotToolActionEnabledBuilder
        seminarToolCallActionIsExecutable,
    required SeminarSnapshotToolActionPressedBuilder
        seminarToolCallActionPressed,
    required GlobalKey Function(AiSeminarRunCardEvidenceSnapshot evidence)
        seminarEvidenceTileKey,
    required SeminarSnapshotCountLabelBuilder seminarCountLabel,
    required String Function(List<String> roleIds) seminarRoleLabels,
    required SeminarReviewTriageItemsBuilder seminarReviewTriageItems,
    required SeminarReviewReasonTextsBuilder seminarReviewReasonTexts,
    required SeminarReviewSynthesisItemsBuilder seminarReviewCandidateCardItems,
    required SeminarReviewSynthesisItemsBuilder seminarReviewQuestionItems,
    required SeminarReviewRiskLevelBuilder seminarReviewRiskLevel,
    required SeminarReviewRiskLabelBuilder seminarReviewRiskLabel,
    required SeminarReviewSuggestedActionBuilder seminarReviewSuggestedAction,
    required SeminarReviewSuggestedActionLabelBuilder
        seminarReviewSuggestedActionLabel,
    required SeminarReviewTriageSuggestionTextBuilder
        seminarReviewTriageSuggestionText,
    required String Function(String actionId) seminarArtifactActionChipLabel,
    required String Function(String rawText) seminarArtifactActionDisplayText,
    required String? Function(String? status) seminarArtifactActionStatusLabel,
    required String? Function(String? status, int? completedAt)
        seminarArtifactActionCompletedAtLabel,
    required String Function(String? status) seminarArtifactActionDetailLabel,
    required SeminarSnapshotSubviewSelectedCallback onSnapshotSubviewSelected,
    required SeminarSnapshotTimelineExpansionCallback
        onToggleNativeTimelineExpansion,
  })  : _isChineseLocale = isChineseLocale,
        _seminarCardSnapshotSubviews = snapshotSubviews,
        _seminarCardTimelineExpandedSessionIds = timelineExpandedSessionIds,
        _seminarCardSubmittingSessionIds = submittingSessionIds,
        _seminarLinkedEvidenceLabel = linkedEvidenceLabel,
        _seminarMissingSourceLabel = missingSourceLabel,
        _localizedSeminarCardText = localizedSeminarCardText,
        _seminarSnapshotEvidence = seminarSnapshotEvidence,
        _seminarSnapshotToolCalls = seminarSnapshotToolCalls,
        _seminarSnapshotRoleTurns = seminarSnapshotRoleTurns,
        _seminarSnapshotReaderTurns = seminarSnapshotReaderTurns,
        _seminarSnapshotReaderComposers = seminarSnapshotReaderComposers,
        _seminarSnapshotDirectorCues = seminarSnapshotDirectorCues,
        _seminarSnapshotAgentStatuses = seminarSnapshotAgentStatuses,
        _seminarSnapshotSynthesisSummary = seminarSnapshotSynthesisSummary,
        _seminarSnapshotSynthesisEvidenceRefs =
            seminarSnapshotSynthesisEvidenceRefs,
        _seminarSnapshotDisagreementDetailsFromParts =
            seminarSnapshotDisagreementDetailsFromParts,
        _seminarSnapshotDisagreementRebuttals =
            seminarSnapshotDisagreementRebuttals,
        _seminarSnapshotContradictionScans = seminarSnapshotContradictionScans,
        _seminarSnapshotRolePartials = seminarSnapshotRolePartials,
        _seminarSnapshotNativeTimelineParts =
            seminarSnapshotNativeTimelineParts,
        _seminarSnapshotHasLegacySnapshotContent =
            seminarSnapshotHasLegacySnapshotContent,
        _seminarSnapshotReviewTriageParts = seminarSnapshotReviewTriageParts,
        _seminarSnapshotArtifactActionParts =
            seminarSnapshotArtifactActionParts,
        _seminarSnapshotControlDirectorCues =
            seminarSnapshotControlDirectorCues,
        _seminarSnapshotThinkingParts = seminarSnapshotThinkingParts,
        _seminarRuntimeThinkingParts = seminarRuntimeThinkingParts,
        _mergeSeminarNativeTimelineParts = mergeSeminarNativeTimelineParts,
        _seminarSnapshotShouldUseNativeTimeline =
            seminarSnapshotShouldUseNativeTimeline,
        _seminarSnapshotCompactNativeTimelineParts =
            seminarSnapshotCompactNativeTimelineParts,
        _seminarSnapshotCollapsedNativeTimelineParts =
            seminarSnapshotCollapsedNativeTimelineParts,
        _seminarTimelinePartView = seminarTimelinePartView,
        _buildSeminarDirectorCueView = buildSeminarDirectorCueView,
        _seminarAgentStatusLabel = seminarAgentStatusLabel,
        _seminarRoleFallbackLabel = seminarRoleFallbackLabel,
        _buildSeminarAgentControlActionView =
            buildSeminarAgentControlActionView,
        _effectiveSeminarStatusAllowedToolIds =
            effectiveSeminarStatusAllowedToolIds,
        _seminarToolDisplayLabel = seminarToolDisplayLabel,
        _buildSeminarAgentInputComposerForPart =
            buildSeminarAgentInputComposerForPart,
        _buildSeminarReaderComposerView = buildSeminarReaderComposerView,
        _buildSeminarReaderTurnView = buildSeminarReaderTurnView,
        _seminarRoleIconById = seminarRoleIconById,
        _jumpToSeminarEvidenceRow = jumpToSeminarEvidenceRow,
        _seminarSnapshotEvidenceSourceAction =
            seminarSnapshotEvidenceSourceAction,
        _seminarToolCallLabel = seminarToolCallLabel,
        _seminarToolCallStatusLabel = seminarToolCallStatusLabel,
        _seminarToolCallStartedAtLabel = seminarToolCallStartedAtLabel,
        _seminarToolCallCompletedAtLabel = seminarToolCallCompletedAtLabel,
        _seminarToolCallDurationLabel = seminarToolCallDurationLabel,
        _seminarToolCallVisibleRoleLabel = seminarToolCallVisibleRoleLabel,
        _seminarToolCallOutputLabel = seminarToolCallOutputLabel,
        _seminarToolCallActionLabel = seminarToolCallActionLabel,
        _seminarToolCallActionIcon = seminarToolCallActionIcon,
        _seminarToolCallActionIsExecutable = seminarToolCallActionIsExecutable,
        _seminarToolCallActionPressed = seminarToolCallActionPressed,
        _seminarEvidenceTileKey = seminarEvidenceTileKey,
        _seminarCountLabel = seminarCountLabel,
        _seminarRoleLabels = seminarRoleLabels,
        _seminarReviewTriageItems = seminarReviewTriageItems,
        _seminarReviewReasonTexts = seminarReviewReasonTexts,
        _seminarReviewCandidateCardItems = seminarReviewCandidateCardItems,
        _seminarReviewQuestionItems = seminarReviewQuestionItems,
        _seminarReviewRiskLevel = seminarReviewRiskLevel,
        _seminarReviewRiskLabel = seminarReviewRiskLabel,
        _seminarReviewSuggestedAction = seminarReviewSuggestedAction,
        _seminarReviewSuggestedActionLabel = seminarReviewSuggestedActionLabel,
        _seminarReviewTriageSuggestionText = seminarReviewTriageSuggestionText,
        _seminarArtifactActionChipLabel = seminarArtifactActionChipLabel,
        _seminarArtifactActionDisplayText = seminarArtifactActionDisplayText,
        _seminarArtifactActionStatusLabel = seminarArtifactActionStatusLabel,
        _seminarArtifactActionCompletedAtLabel =
            seminarArtifactActionCompletedAtLabel,
        _seminarArtifactActionDetailLabel = seminarArtifactActionDetailLabel,
        _onSnapshotSubviewSelected = onSnapshotSubviewSelected,
        _onToggleNativeTimelineExpansion = onToggleNativeTimelineExpansion;

  final bool _isChineseLocale;
  final Map<String, SeminarRunSnapshotSubview> _seminarCardSnapshotSubviews;
  final Set<String> _seminarCardTimelineExpandedSessionIds;
  final Set<String> _seminarCardSubmittingSessionIds;
  final String _seminarLinkedEvidenceLabel;
  final String _seminarMissingSourceLabel;
  final SeminarSnapshotLocalizedTextBuilder _localizedSeminarCardText;
  final List<AiSeminarRunCardEvidenceSnapshot> Function(
    AiSeminarRunCardSnapshot snapshot,
  ) _seminarSnapshotEvidence;
  final SeminarSnapshotToolCallsBuilder _seminarSnapshotToolCalls;
  final List<AiSeminarRunCardRoleSummary> Function(
    AiSeminarRunCardSnapshot snapshot,
  ) _seminarSnapshotRoleTurns;
  final List<AiSeminarRunCardMessagePart> Function(
    AiSeminarRunCardSnapshot snapshot,
  ) _seminarSnapshotReaderTurns;
  final List<AiSeminarRunCardMessagePart> Function(
    AiSeminarRunCardSnapshot snapshot,
  ) _seminarSnapshotReaderComposers;
  final List<AiSeminarRunCardMessagePart> Function(
    AiSeminarRunCardSnapshot snapshot,
  ) _seminarSnapshotDirectorCues;
  final List<AiSeminarRunCardMessagePart> Function(
    AiSeminarRunCardSnapshot snapshot,
  ) _seminarSnapshotAgentStatuses;
  final String? Function(AiSeminarRunCardSnapshot snapshot)
      _seminarSnapshotSynthesisSummary;
  final List<AiSeminarRunCardEvidenceSnapshot> Function(
    AiSeminarRunCardSnapshot snapshot,
  ) _seminarSnapshotSynthesisEvidenceRefs;
  final List<AiSeminarRunCardDisagreementDetail> Function(
    AiSeminarRunCardSnapshot snapshot,
  ) _seminarSnapshotDisagreementDetailsFromParts;
  final List<AiSeminarRunCardMessagePart> Function(
    AiSeminarRunCardSnapshot snapshot,
  ) _seminarSnapshotDisagreementRebuttals;
  final List<AiSeminarRunCardMessagePart> Function(
    AiSeminarRunCardSnapshot snapshot,
  ) _seminarSnapshotContradictionScans;
  final List<AiSeminarRunCardRoleSummary> Function(
    AiSeminarRunCardSnapshot snapshot,
  ) _seminarSnapshotRolePartials;
  final SeminarSnapshotNativeTimelinePartsBuilder
      _seminarSnapshotNativeTimelineParts;
  final bool Function(AiSeminarRunCardSnapshot snapshot)
      _seminarSnapshotHasLegacySnapshotContent;
  final List<AiSeminarRunCardMessagePart> Function(
    AiSeminarRunCardSnapshot snapshot,
  ) _seminarSnapshotReviewTriageParts;
  final List<AiSeminarRunCardMessagePart> Function(
    AiSeminarRunCardSnapshot snapshot,
  ) _seminarSnapshotArtifactActionParts;
  final List<AiSeminarRunCardMessagePart> Function(
    List<AiSeminarRunCardMessagePart> directorCues,
  ) _seminarSnapshotControlDirectorCues;
  final List<AiSeminarRunCardMessagePart> Function(
    AiSeminarRunCardSnapshot snapshot,
  ) _seminarSnapshotThinkingParts;
  final List<AiSeminarRunCardMessagePart> Function(
    AiSeminarRuntimeState state,
  ) _seminarRuntimeThinkingParts;
  final List<AiSeminarRunCardMessagePart> Function(
    List<AiSeminarRunCardMessagePart> preferred,
    List<AiSeminarRunCardMessagePart> fallback,
  ) _mergeSeminarNativeTimelineParts;
  final SeminarSnapshotNativeTimelinePredicate
      _seminarSnapshotShouldUseNativeTimeline;
  final List<AiSeminarRunCardMessagePart> Function(
    List<AiSeminarRunCardMessagePart> parts,
  ) _seminarSnapshotCompactNativeTimelineParts;
  final List<AiSeminarRunCardMessagePart> Function(
    List<AiSeminarRunCardMessagePart> parts,
  ) _seminarSnapshotCollapsedNativeTimelineParts;
  final SeminarSnapshotTimelinePartViewBuilder _seminarTimelinePartView;
  final SeminarSnapshotDirectorCueBuilder _buildSeminarDirectorCueView;
  final String Function(String? status) _seminarAgentStatusLabel;
  final String Function(String roleId) _seminarRoleFallbackLabel;
  final SeminarSnapshotAgentControlActionBuilder
      _buildSeminarAgentControlActionView;
  final SeminarSnapshotAllowedToolIdsBuilder
      _effectiveSeminarStatusAllowedToolIds;
  final String Function(String toolId) _seminarToolDisplayLabel;
  final SeminarSnapshotAgentInputComposerBuilder
      _buildSeminarAgentInputComposerForPart;
  final Widget Function(AiSeminarRunCardMessagePart part)
      _buildSeminarReaderComposerView;
  final Widget Function(AiSeminarRunCardMessagePart part)
      _buildSeminarReaderTurnView;
  final IconData Function(String roleId) _seminarRoleIconById;
  final void Function(AiSeminarRunCardEvidenceSnapshot evidence)
      _jumpToSeminarEvidenceRow;
  final Widget? Function(SourceRef? sourceRef)
      _seminarSnapshotEvidenceSourceAction;
  final String Function(AiSeminarRunCardToolCallSnapshot toolCall)
      _seminarToolCallLabel;
  final String? Function(AiSeminarRunCardToolCallSnapshot toolCall)
      _seminarToolCallStatusLabel;
  final String? Function(AiSeminarRunCardToolCallSnapshot toolCall)
      _seminarToolCallStartedAtLabel;
  final String? Function(AiSeminarRunCardToolCallSnapshot toolCall)
      _seminarToolCallCompletedAtLabel;
  final String? Function(AiSeminarRunCardToolCallSnapshot toolCall)
      _seminarToolCallDurationLabel;
  final String Function(AiSeminarRunCardToolCallSnapshot toolCall)
      _seminarToolCallVisibleRoleLabel;
  final String Function(AiSeminarRunCardToolCallSnapshot toolCall)
      _seminarToolCallOutputLabel;
  final String Function(String? actionId) _seminarToolCallActionLabel;
  final IconData Function(String actionId) _seminarToolCallActionIcon;
  final SeminarSnapshotToolActionEnabledBuilder
      _seminarToolCallActionIsExecutable;
  final SeminarSnapshotToolActionPressedBuilder _seminarToolCallActionPressed;
  final GlobalKey Function(AiSeminarRunCardEvidenceSnapshot evidence)
      _seminarEvidenceTileKey;
  final SeminarSnapshotCountLabelBuilder _seminarCountLabel;
  final String Function(List<String> roleIds) _seminarRoleLabels;
  final SeminarReviewTriageItemsBuilder _seminarReviewTriageItems;
  final SeminarReviewReasonTextsBuilder _seminarReviewReasonTexts;
  final SeminarReviewSynthesisItemsBuilder _seminarReviewCandidateCardItems;
  final SeminarReviewSynthesisItemsBuilder _seminarReviewQuestionItems;
  final SeminarReviewRiskLevelBuilder _seminarReviewRiskLevel;
  final SeminarReviewRiskLabelBuilder _seminarReviewRiskLabel;
  final SeminarReviewSuggestedActionBuilder _seminarReviewSuggestedAction;
  final SeminarReviewSuggestedActionLabelBuilder
      _seminarReviewSuggestedActionLabel;
  final SeminarReviewTriageSuggestionTextBuilder
      _seminarReviewTriageSuggestionText;
  final String Function(String actionId) _seminarArtifactActionChipLabel;
  final String Function(String rawText) _seminarArtifactActionDisplayText;
  final String? Function(String? status) _seminarArtifactActionStatusLabel;
  final String? Function(String? status, int? completedAt)
      _seminarArtifactActionCompletedAtLabel;
  final String Function(String? status) _seminarArtifactActionDetailLabel;
  final SeminarSnapshotSubviewSelectedCallback _onSnapshotSubviewSelected;
  final SeminarSnapshotTimelineExpansionCallback
      _onToggleNativeTimelineExpansion;
}
