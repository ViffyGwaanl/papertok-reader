part of 'seminar_run_card_view.dart';

typedef SeminarRunCardLocalizedTextBuilder = String Function({
  required String zh,
  required String en,
});
typedef SeminarRunCardAgentControlActionBuilder = Widget Function(
  AiSeminarRunCardMessagePart part, {
  required String actionId,
  required String? sessionId,
});
typedef SeminarRunCardSnapshotViewBuilder = Widget Function(
  String? sessionId,
  AiSeminarRunCardSnapshot snapshot,
  AiSeminarRuntimeState runtimeState, {
  required int? bookId,
  required List<String> evidenceScopeIds,
});
typedef SeminarRunCardResumeBannerBuilder = Widget Function(
  AiSeminarRunCardMeta card,
  AiSeminarRuntimeState runtimeState, {
  required bool showDetails,
  required VoidCallback onOpen,
  required VoidCallback onContinue,
});
typedef SeminarRunCardSessionAction = Future<void> Function(String? sessionId);

class SeminarRunCardBindings {
  const SeminarRunCardBindings({
    required bool isChineseLocale,
    required Set<String> sentToReviewSessionIds,
    required Set<String> savedKnowledgeCardIds,
    required Set<String> spacedReviewFlashcardIds,
    required Set<String> conceptNodeIds,
    required Set<String> ignoredActionSessionIds,
    required Set<String> resumeDetailSessionIds,
    required SeminarRunCardLocalizedTextBuilder localizedSeminarCardText,
    required List<SourceRef> Function(AiSeminarRuntimeState runtimeState)
        seminarSynthesisKnowledgeCardSourceRefs,
    required String? Function(String? sessionId)
        seminarSynthesisKnowledgeCardId,
    required String? Function(String? sessionId)
        seminarSynthesisReviewFlashcardId,
    required String? Function(String? sessionId) seminarSynthesisConceptNodeId,
    required bool Function(
      AiSeminarRunCardMeta card,
      AiSeminarRuntimeState runtimeState,
    ) shouldShowSeminarCardStartAction,
    required bool Function(AiSeminarRunCardSnapshot snapshot)
        seminarSnapshotHasOnlyRunSetup,
    required bool Function(
      AiSeminarRunCardMeta card,
      AiSeminarRuntimeState runtimeState,
    ) shouldShowSeminarCardCancelAction,
    required Widget Function(AiSeminarRunCardMeta card)
        buildSeminarRunCardCancelActionView,
    required SeminarRunCardAgentControlActionBuilder
        buildSeminarAgentControlActionView,
    required String Function(String status, L10n l10n) seminarStatusLabel,
    required String Function(int count) seminarRoleCountLabel,
    required String Function(List<String> scopeIds, L10n l10n)
        seminarEvidenceScopeSummary,
    required String Function(int count) seminarSourceCountLabel,
    required Widget Function(AiSeminarRunCardMeta card)
        buildSeminarRunCardSetupView,
    required SeminarRunCardSnapshotViewBuilder buildSeminarRunSnapshot,
    required Widget Function(AiSeminarRunCardMeta card)
        buildSeminarRunCardStartActionView,
    required SeminarRunCardResumeBannerBuilder
        buildSeminarRunCardResumeBannerView,
    required SeminarRunCardSessionAction continueSeminarRunCardFromCheckpoint,
    required SeminarRunCardSessionAction sendActiveSeminarRunCardToReview,
    required SeminarRunCardSessionAction saveActiveSeminarRunCardKnowledgeCard,
    required SeminarRunCardSessionAction editActiveSeminarRunCardKnowledgeCard,
    required SeminarRunCardSessionAction undoActiveSeminarRunCardKnowledgeCard,
    required SeminarRunCardSessionAction addActiveSeminarRunCardSpacedReview,
    required SeminarRunCardSessionAction undoActiveSeminarRunCardSpacedReview,
    required SeminarRunCardSessionAction addActiveSeminarRunCardConceptGraph,
    required SeminarRunCardSessionAction undoActiveSeminarRunCardConceptGraph,
    required SeminarRunCardSessionAction ignoreSeminarRunCardAssetActions,
    required SeminarRunCardSessionAction restoreSeminarRunCardAssetActions,
    required void Function(String sessionId, bool showRecoveryDetails)
        onToggleRecoveryDetails,
  })  : _isChineseLocale = isChineseLocale,
        _seminarCardSentToReviewSessionIds = sentToReviewSessionIds,
        _seminarCardSavedKnowledgeCardIds = savedKnowledgeCardIds,
        _seminarCardSpacedReviewFlashcardIds = spacedReviewFlashcardIds,
        _seminarCardConceptNodeIds = conceptNodeIds,
        _seminarCardIgnoredActionSessionIds = ignoredActionSessionIds,
        _seminarCardResumeDetailSessionIds = resumeDetailSessionIds,
        _localizedSeminarCardText = localizedSeminarCardText,
        _seminarSynthesisKnowledgeCardSourceRefs =
            seminarSynthesisKnowledgeCardSourceRefs,
        _seminarSynthesisKnowledgeCardId = seminarSynthesisKnowledgeCardId,
        _seminarSynthesisReviewFlashcardId = seminarSynthesisReviewFlashcardId,
        _seminarSynthesisConceptNodeId = seminarSynthesisConceptNodeId,
        _shouldShowSeminarCardStartAction = shouldShowSeminarCardStartAction,
        _seminarSnapshotHasOnlyRunSetup = seminarSnapshotHasOnlyRunSetup,
        _shouldShowSeminarCardCancelAction = shouldShowSeminarCardCancelAction,
        _buildSeminarRunCardCancelActionView =
            buildSeminarRunCardCancelActionView,
        _buildSeminarAgentControlActionView =
            buildSeminarAgentControlActionView,
        _seminarStatusLabel = seminarStatusLabel,
        _seminarRoleCountLabel = seminarRoleCountLabel,
        _seminarEvidenceScopeSummary = seminarEvidenceScopeSummary,
        _seminarSourceCountLabel = seminarSourceCountLabel,
        _buildSeminarRunCardSetupView = buildSeminarRunCardSetupView,
        _buildSeminarRunSnapshot = buildSeminarRunSnapshot,
        _buildSeminarRunCardStartActionView =
            buildSeminarRunCardStartActionView,
        _buildSeminarRunCardResumeBannerView =
            buildSeminarRunCardResumeBannerView,
        _continueSeminarRunCardFromCheckpoint =
            continueSeminarRunCardFromCheckpoint,
        _sendActiveSeminarRunCardToReview = sendActiveSeminarRunCardToReview,
        _saveActiveSeminarRunCardKnowledgeCard =
            saveActiveSeminarRunCardKnowledgeCard,
        _editActiveSeminarRunCardKnowledgeCard =
            editActiveSeminarRunCardKnowledgeCard,
        _undoActiveSeminarRunCardKnowledgeCard =
            undoActiveSeminarRunCardKnowledgeCard,
        _addActiveSeminarRunCardSpacedReview =
            addActiveSeminarRunCardSpacedReview,
        _undoActiveSeminarRunCardSpacedReview =
            undoActiveSeminarRunCardSpacedReview,
        _addActiveSeminarRunCardConceptGraph =
            addActiveSeminarRunCardConceptGraph,
        _undoActiveSeminarRunCardConceptGraph =
            undoActiveSeminarRunCardConceptGraph,
        _ignoreSeminarRunCardAssetActions = ignoreSeminarRunCardAssetActions,
        _restoreSeminarRunCardAssetActions = restoreSeminarRunCardAssetActions,
        _onToggleRecoveryDetails = onToggleRecoveryDetails;

  final bool _isChineseLocale;
  final Set<String> _seminarCardSentToReviewSessionIds;
  final Set<String> _seminarCardSavedKnowledgeCardIds;
  final Set<String> _seminarCardSpacedReviewFlashcardIds;
  final Set<String> _seminarCardConceptNodeIds;
  final Set<String> _seminarCardIgnoredActionSessionIds;
  final Set<String> _seminarCardResumeDetailSessionIds;
  final SeminarRunCardLocalizedTextBuilder _localizedSeminarCardText;
  final List<SourceRef> Function(AiSeminarRuntimeState runtimeState)
      _seminarSynthesisKnowledgeCardSourceRefs;
  final String? Function(String? sessionId) _seminarSynthesisKnowledgeCardId;
  final String? Function(String? sessionId) _seminarSynthesisReviewFlashcardId;
  final String? Function(String? sessionId) _seminarSynthesisConceptNodeId;
  final bool Function(
    AiSeminarRunCardMeta card,
    AiSeminarRuntimeState runtimeState,
  ) _shouldShowSeminarCardStartAction;
  final bool Function(AiSeminarRunCardSnapshot snapshot)
      _seminarSnapshotHasOnlyRunSetup;
  final bool Function(
    AiSeminarRunCardMeta card,
    AiSeminarRuntimeState runtimeState,
  ) _shouldShowSeminarCardCancelAction;
  final Widget Function(AiSeminarRunCardMeta card)
      _buildSeminarRunCardCancelActionView;
  final SeminarRunCardAgentControlActionBuilder
      _buildSeminarAgentControlActionView;
  final String Function(String status, L10n l10n) _seminarStatusLabel;
  final String Function(int count) _seminarRoleCountLabel;
  final String Function(List<String> scopeIds, L10n l10n)
      _seminarEvidenceScopeSummary;
  final String Function(int count) _seminarSourceCountLabel;
  final Widget Function(AiSeminarRunCardMeta card)
      _buildSeminarRunCardSetupView;
  final SeminarRunCardSnapshotViewBuilder _buildSeminarRunSnapshot;
  final Widget Function(AiSeminarRunCardMeta card)
      _buildSeminarRunCardStartActionView;
  final SeminarRunCardResumeBannerBuilder _buildSeminarRunCardResumeBannerView;
  final SeminarRunCardSessionAction _continueSeminarRunCardFromCheckpoint;
  final SeminarRunCardSessionAction _sendActiveSeminarRunCardToReview;
  final SeminarRunCardSessionAction _saveActiveSeminarRunCardKnowledgeCard;
  final SeminarRunCardSessionAction _editActiveSeminarRunCardKnowledgeCard;
  final SeminarRunCardSessionAction _undoActiveSeminarRunCardKnowledgeCard;
  final SeminarRunCardSessionAction _addActiveSeminarRunCardSpacedReview;
  final SeminarRunCardSessionAction _undoActiveSeminarRunCardSpacedReview;
  final SeminarRunCardSessionAction _addActiveSeminarRunCardConceptGraph;
  final SeminarRunCardSessionAction _undoActiveSeminarRunCardConceptGraph;
  final SeminarRunCardSessionAction _ignoreSeminarRunCardAssetActions;
  final SeminarRunCardSessionAction _restoreSeminarRunCardAssetActions;
  final void Function(String sessionId, bool showRecoveryDetails)
      _onToggleRecoveryDetails;
}
