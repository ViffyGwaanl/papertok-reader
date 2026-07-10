import 'package:flutter/material.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/providers/ai_seminar_runtime.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/ai/seminar/seminar_stable_width_section.dart';
import 'package:papertok_reader/widgets/ai/seminar/setup/seminar_run_card_resume_widgets.dart';
import 'package:papertok_reader/widgets/ai/seminar/setup/seminar_run_card_setup_widgets.dart';
import 'package:papertok_reader/widgets/ai/seminar/shared/seminar_snapshot_widgets.dart';

part 'seminar_run_card_bindings.dart';

class SeminarRunCardView extends StatelessWidget {
  const SeminarRunCardView({
    required this.card,
    required this.runtimeState,
    required this.bindings,
    super.key,
  });

  final AiSeminarRunCardMeta card;
  final AiSeminarRuntimeState runtimeState;
  final SeminarRunCardBindings bindings;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final question = card.question.trim();
    final normalizedSessionId = card.sessionId?.trim();
    final hasSentToReview = normalizedSessionId != null &&
        normalizedSessionId.isNotEmpty &&
        bindings._seminarCardSentToReviewSessionIds
            .contains(normalizedSessionId);
    final canSendToReview = card.sessionId != null &&
        runtimeState.session?.id == card.sessionId &&
        runtimeState.canSendToReview &&
        !hasSentToReview;
    final canSaveKnowledgeCard = card.sessionId != null &&
        runtimeState.session?.id == card.sessionId &&
        bindings
            ._seminarSynthesisKnowledgeCardSourceRefs(runtimeState)
            .isNotEmpty;
    final canAddSpacedReview = canSaveKnowledgeCard;
    final canAddConceptGraph = canSaveKnowledgeCard;
    final knowledgeCardId =
        bindings._seminarSynthesisKnowledgeCardId(card.sessionId);
    final hasSavedKnowledgeCard = knowledgeCardId != null &&
        bindings._seminarCardSavedKnowledgeCardIds.contains(knowledgeCardId);
    final reviewFlashcardId =
        bindings._seminarSynthesisReviewFlashcardId(card.sessionId);
    final hasAddedSpacedReview = reviewFlashcardId != null &&
        bindings._seminarCardSpacedReviewFlashcardIds
            .contains(reviewFlashcardId);
    final conceptNodeId =
        bindings._seminarSynthesisConceptNodeId(card.sessionId);
    final hasAddedConceptGraph = conceptNodeId != null &&
        bindings._seminarCardConceptNodeIds.contains(conceptNodeId);
    final hasIgnoredActions = normalizedSessionId != null &&
        normalizedSessionId.isNotEmpty &&
        bindings._seminarCardIgnoredActionSessionIds
            .contains(normalizedSessionId);
    final hasAnyAssetAction = canSaveKnowledgeCard ||
        canAddSpacedReview ||
        canAddConceptGraph ||
        canSendToReview;
    final canIgnoreAssetActions = normalizedSessionId != null &&
        normalizedSessionId.isNotEmpty &&
        !hasSavedKnowledgeCard &&
        !hasAddedSpacedReview &&
        !hasAddedConceptGraph &&
        hasAnyAssetAction;
    final canStartFromCard = bindings._shouldShowSeminarCardStartAction(
      card,
      runtimeState,
    );
    final snapshot = card.snapshot;
    final shouldShowSnapshot = snapshot != null &&
        !snapshot.isEmpty &&
        !(canStartFromCard &&
            bindings._seminarSnapshotHasOnlyRunSetup(snapshot));
    final canCancelFromCard = bindings._shouldShowSeminarCardCancelAction(
      card,
      runtimeState,
    );
    final headerControls = seminarRunCardHeaderControls(
      sessionId: card.sessionId,
      snapshot: snapshot,
      canCancelFromCard: canCancelFromCard,
      zh: bindings._isChineseLocale,
      cancelActionBuilder: () =>
          bindings._buildSeminarRunCardCancelActionView(card),
      actionWidgetBuilder: (part, actionId) =>
          bindings._buildSeminarAgentControlActionView(
        part,
        actionId: actionId,
        sessionId: card.sessionId?.trim() ?? '',
      ),
    );

    final showRecoveryDetails = normalizedSessionId != null &&
        normalizedSessionId.isNotEmpty &&
        bindings._seminarCardResumeDetailSessionIds
            .contains(normalizedSessionId);

    void toggleRecoveryDetails() {
      if (normalizedSessionId == null || normalizedSessionId.isEmpty) return;
      bindings._onToggleRecoveryDetails(
        normalizedSessionId,
        showRecoveryDetails,
      );
    }

    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: ClaudePalette.divider(context)),
            color: ClaudePalette.card(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.groups_2_outlined,
                    size: 18,
                    color: ClaudePalette.accent(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.aiChatSeminarFeatureTitle,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: ClaudePalette.fg(context),
                          ),
                    ),
                  ),
                  if (headerControls.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: headerControls,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              SeminarMetaChips(
                chips: [
                  SeminarMetaChipData(
                    icon: Icons.flag_outlined,
                    label: bindings._seminarStatusLabel(card.status, l10n),
                  ),
                  SeminarMetaChipData(
                    icon: Icons.groups_2_outlined,
                    label: bindings._seminarRoleCountLabel(card.roleIds.length),
                  ),
                  SeminarMetaChipData(
                    icon: Icons.manage_search_outlined,
                    label: bindings._seminarEvidenceScopeSummary(
                      card.evidenceScopeIds,
                      l10n,
                    ),
                  ),
                  if (card.sourceRefCount > 0)
                    SeminarMetaChipData(
                      icon: Icons.link_outlined,
                      label: bindings
                          ._seminarSourceCountLabel(card.sourceRefCount),
                    ),
                  if (card.writeRequiresApproval)
                    SeminarMetaChipData(
                      icon: Icons.fact_check_outlined,
                      label: bindings._localizedSeminarCardText(
                        zh: '写入需确认',
                        en: 'Approval before write',
                      ),
                    ),
                  if (card.allowWeb)
                    SeminarMetaChipData(
                      icon: Icons.public_outlined,
                      label: bindings._localizedSeminarCardText(
                        zh: '允许联网',
                        en: 'Web allowed',
                      ),
                    ),
                  if (card.maxRounds > 1)
                    SeminarMetaChipData(
                      icon: Icons.repeat_outlined,
                      label: bindings._localizedSeminarCardText(
                        zh: '最多 ${card.maxRounds} 轮',
                        en: 'Up to ${card.maxRounds} rounds',
                      ),
                    ),
                ],
              ),
              if (question.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  question,
                  key: card.sessionId == null
                      ? null
                      : ValueKey(
                          'seminar-chat-card-question-${card.sessionId}'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: ClaudePalette.fg(context),
                        height: 1.35,
                      ),
                ),
              ],
              if (canStartFromCard) ...[
                const SizedBox(height: 12),
                SeminarFullWidthSection(
                  child: bindings._buildSeminarRunCardSetupView(card),
                ),
              ],
              if (shouldShowSnapshot) ...[
                const SizedBox(height: 9),
                KeyedSubtree(
                  key: card.sessionId == null
                      ? null
                      : ValueKey(
                          'seminar-chat-card-snapshot-${card.sessionId}'),
                  child: SeminarFullWidthSection(
                    child: bindings._buildSeminarRunSnapshot(
                      card.sessionId,
                      snapshot,
                      runtimeState,
                      bookId: card.bookId,
                      evidenceScopeIds: card.evidenceScopeIds,
                    ),
                  ),
                ),
              ],
              if (canStartFromCard) ...[
                const SizedBox(height: 12),
                bindings._buildSeminarRunCardStartActionView(card),
              ],
              if (shouldShowSeminarCardResumeBanner(card, runtimeState)) ...[
                const SizedBox(height: 12),
                bindings._buildSeminarRunCardResumeBannerView(
                  card,
                  runtimeState,
                  showDetails: showRecoveryDetails,
                  onOpen: toggleRecoveryDetails,
                  onContinue: () =>
                      bindings._continueSeminarRunCardFromCheckpoint(
                    card.sessionId,
                  ),
                ),
              ],
              if (_shouldShowSeminarCardFollowUpHint(card, runtimeState)) ...[
                const SizedBox(height: 12),
                _buildSeminarRunCardFollowUpHint(context),
                if (_seminarRunCardEstimatedCost() != null)
                  _buildSeminarRunCardCostLine(
                    context,
                    _seminarRunCardEstimatedCost()!,
                  ),
              ],
              if (hasIgnoredActions) ...[
                const SizedBox(height: 12),
                _buildSeminarRunCardIgnoredActionsNotice(
                  context,
                  card.sessionId,
                ),
              ] else if (hasAnyAssetAction) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (canSaveKnowledgeCard)
                      hasSavedKnowledgeCard
                          ? OutlinedButton.icon(
                              icon: const Icon(Icons.undo_outlined, size: 18),
                              label: Text(
                                bindings._localizedSeminarCardText(
                                  zh: '撤销保存',
                                  en: 'Undo save',
                                ),
                              ),
                              onPressed: () => bindings
                                  ._undoActiveSeminarRunCardKnowledgeCard(
                                card.sessionId,
                              ),
                            )
                          : FilledButton.icon(
                              icon: const Icon(Icons.style_outlined, size: 18),
                              label: Text(
                                bindings._localizedSeminarCardText(
                                  zh: '保存知识卡',
                                  en: 'Save card',
                                ),
                              ),
                              onPressed: () => bindings
                                  ._saveActiveSeminarRunCardKnowledgeCard(
                                card.sessionId,
                              ),
                            ),
                    if (canSaveKnowledgeCard && !hasSavedKnowledgeCard)
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.edit_note_outlined, size: 18),
                        label: Text(
                          bindings._localizedSeminarCardText(
                            zh: '编辑后保存',
                            en: 'Edit and save',
                          ),
                        ),
                        onPressed: () =>
                            bindings._editActiveSeminarRunCardKnowledgeCard(
                          card.sessionId,
                        ),
                      ),
                    if (canAddSpacedReview)
                      hasAddedSpacedReview
                          ? OutlinedButton.icon(
                              icon: const Icon(Icons.undo_outlined, size: 18),
                              label: Text(
                                bindings._localizedSeminarCardText(
                                  zh: '撤销复习',
                                  en: 'Undo review',
                                ),
                              ),
                              onPressed: () => bindings
                                  ._undoActiveSeminarRunCardSpacedReview(
                                card.sessionId,
                              ),
                            )
                          : FilledButton.tonalIcon(
                              icon: const Icon(Icons.school_outlined, size: 18),
                              label: Text(
                                bindings._localizedSeminarCardText(
                                  zh: '加入复习',
                                  en: 'Add review',
                                ),
                              ),
                              onPressed: () =>
                                  bindings._addActiveSeminarRunCardSpacedReview(
                                card.sessionId,
                              ),
                            ),
                    if (canAddConceptGraph)
                      hasAddedConceptGraph
                          ? OutlinedButton.icon(
                              icon: const Icon(Icons.undo_outlined, size: 18),
                              label: Text(
                                bindings._localizedSeminarCardText(
                                  zh: '撤销图谱',
                                  en: 'Undo graph',
                                ),
                              ),
                              onPressed: () => bindings
                                  ._undoActiveSeminarRunCardConceptGraph(
                                card.sessionId,
                              ),
                            )
                          : FilledButton.tonalIcon(
                              icon: const Icon(
                                Icons.account_tree_outlined,
                                size: 18,
                              ),
                              label: Text(
                                bindings._localizedSeminarCardText(
                                  zh: '加入我的图谱',
                                  en: 'Add to graph',
                                ),
                              ),
                              onPressed: () =>
                                  bindings._addActiveSeminarRunCardConceptGraph(
                                card.sessionId,
                              ),
                            ),
                    if (canSendToReview)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.fact_check_outlined, size: 18),
                        label: Text(l10n.seminarSendToReview),
                        onPressed: () =>
                            bindings._sendActiveSeminarRunCardToReview(
                          card.sessionId,
                        ),
                      ),
                    if (canIgnoreAssetActions)
                      TextButton.icon(
                        icon:
                            const Icon(Icons.visibility_off_outlined, size: 18),
                        label: Text(
                          bindings._localizedSeminarCardText(
                            zh: '忽略',
                            en: 'Ignore',
                          ),
                        ),
                        onPressed: () =>
                            bindings._ignoreSeminarRunCardAssetActions(
                          card.sessionId,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeminarRunCardIgnoredActionsNotice(
    BuildContext context,
    String? sessionId,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: ClaudePalette.bg(context).withValues(alpha: 0.55),
        border: Border.all(color: ClaudePalette.divider(context)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.visibility_off_outlined,
            size: 17,
            color: ClaudePalette.fg(context).withValues(alpha: 0.62),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              bindings._localizedSeminarCardText(
                zh: '已忽略本次沉淀建议',
                en: 'Suggestions ignored',
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ClaudePalette.fg(context).withValues(alpha: 0.62),
                  ),
            ),
          ),
          TextButton(
            onPressed: () =>
                bindings._restoreSeminarRunCardAssetActions(sessionId),
            child: Text(
              bindings._localizedSeminarCardText(
                zh: '恢复操作',
                en: 'Restore',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // P1 F19b: the in-card participation layer is frozen. Completed cards show
  // a static hint pointing readers to the main composer, where seminar
  // conclusions are available through the F19a prompt digest.
  bool _shouldShowSeminarCardFollowUpHint(
    AiSeminarRunCardMeta card,
    AiSeminarRuntimeState runtimeState,
  ) {
    if (card.status.trim() == 'completed') return true;
    final sessionId = card.sessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) return false;
    return runtimeState.session?.id == sessionId &&
        runtimeState.status == AiSeminarRunStatus.completed;
  }

  /// Estimated USD cost of the completed run, when the active runtime
  /// matches this card and pricing metadata produced a positive estimate.
  /// BYOK users otherwise have no in-app visibility of what a run cost.
  double? _seminarRunCardEstimatedCost() {
    final sessionId = card.sessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) return null;
    if (runtimeState.session?.id != sessionId) return null;
    final cost = runtimeState.lastRun?.estimatedCostUsd;
    if (cost == null || cost <= 0) return null;
    return cost;
  }

  Widget _buildSeminarRunCardCostLine(BuildContext context, double cost) {
    final theme = Theme.of(context);
    final formatted = cost < 0.005
        ? '<\$0.01'
        : '\$${cost.toStringAsFixed(cost < 0.1 ? 3 : 2)}';
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 22),
      child: Text(
        L10n.of(context).aiSeminarEstimatedCost(formatted),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }

  Widget _buildSeminarRunCardFollowUpHint(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.chat_bubble_outline,
          size: 16,
          color: theme.colorScheme.outline,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            bindings._localizedSeminarCardText(
              zh: '研讨已结束,可直接在下方对话框继续追问本场结论',
              en: 'Seminar finished — ask follow-ups about its conclusions '
                  'in the chat box below',
            ),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      ],
    );
  }
}
