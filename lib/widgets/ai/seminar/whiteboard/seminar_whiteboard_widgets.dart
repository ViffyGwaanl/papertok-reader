import 'package:flutter/material.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/ai/seminar/shared/seminar_snapshot_widgets.dart';

typedef SeminarWhiteboardEvidenceTileBuilder = Widget Function(
  AiSeminarRunCardEvidenceSnapshot evidence,
);
typedef SeminarReviewTriageItemsBuilder = List<SeminarReviewPreviewItem>
    Function(
  List<AiSeminarRunCardMessagePart> parts, {
  required String label,
});
typedef SeminarReviewSynthesisItemsBuilder = List<SeminarReviewPreviewItem>
    Function(AiSeminarSynthesis synthesis);
typedef SeminarReviewReasonTextsBuilder = List<String> Function(
  AiSeminarSynthesis synthesis,
);
typedef SeminarReviewRiskLevelBuilder = String Function(
  AiSeminarSynthesis synthesis,
);
typedef SeminarReviewSuggestedActionBuilder = String Function(
  AiSeminarSynthesis synthesis,
);
typedef SeminarReviewRiskLabelBuilder = String Function(String? risk);
typedef SeminarReviewSuggestedActionLabelBuilder = String Function(
  String? action,
);
typedef SeminarReviewTriageSuggestionTextBuilder = String? Function(
  AiSeminarSynthesis synthesis,
);

class SeminarReviewPreviewItem {
  const SeminarReviewPreviewItem({
    required this.text,
    this.evidenceRefs = const <AiSeminarRunCardEvidenceSnapshot>[],
  });

  final String text;
  final List<AiSeminarRunCardEvidenceSnapshot> evidenceRefs;

  bool get isEmpty => text.trim().isEmpty && evidenceRefs.isEmpty;
}

class SeminarSnapshotWhiteboardSection extends StatelessWidget {
  const SeminarSnapshotWhiteboardSection({
    required this.disagreements,
    required this.openQuestions,
    required this.zh,
    super.key,
  });

  final List<String> disagreements;
  final List<String> openQuestions;
  final bool zh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SeminarSnapshotHeading(
          Icons.dashboard_customize_outlined,
          zh ? '研讨白板' : 'Shared whiteboard',
        ),
        const SizedBox(height: 6),
        if (disagreements.isNotEmpty)
          SeminarSnapshotWhiteboardGroup(
            icon: Icons.report_problem_outlined,
            label: zh ? '分歧' : 'Disagreements',
            items: disagreements,
          ),
        if (openQuestions.isNotEmpty)
          SeminarSnapshotWhiteboardGroup(
            icon: Icons.help_outline,
            label: zh ? '开放问题' : 'Open questions',
            items: openQuestions,
          ),
      ],
    );
  }
}

class SeminarSnapshotReviewPreview extends StatelessWidget {
  const SeminarSnapshotReviewPreview({
    required this.synthesis,
    required this.evidenceCount,
    required this.activeSynthesis,
    required this.reviewTriageParts,
    required this.zh,
    required this.triageItemsBuilder,
    required this.reasonTextsBuilder,
    required this.candidateCardItemsBuilder,
    required this.reviewQuestionItemsBuilder,
    required this.riskLevelBuilder,
    required this.riskLabelBuilder,
    required this.suggestedActionBuilder,
    required this.suggestedActionLabelBuilder,
    required this.triageSuggestionTextBuilder,
    required this.evidenceTileBuilder,
    super.key,
  });

  final String? synthesis;
  final int evidenceCount;
  final AiSeminarSynthesis? activeSynthesis;
  final List<AiSeminarRunCardMessagePart> reviewTriageParts;
  final bool zh;
  final SeminarReviewTriageItemsBuilder triageItemsBuilder;
  final SeminarReviewReasonTextsBuilder reasonTextsBuilder;
  final SeminarReviewSynthesisItemsBuilder candidateCardItemsBuilder;
  final SeminarReviewSynthesisItemsBuilder reviewQuestionItemsBuilder;
  final SeminarReviewRiskLevelBuilder riskLevelBuilder;
  final SeminarReviewRiskLabelBuilder riskLabelBuilder;
  final SeminarReviewSuggestedActionBuilder suggestedActionBuilder;
  final SeminarReviewSuggestedActionLabelBuilder suggestedActionLabelBuilder;
  final SeminarReviewTriageSuggestionTextBuilder triageSuggestionTextBuilder;
  final SeminarWhiteboardEvidenceTileBuilder evidenceTileBuilder;

  @override
  Widget build(BuildContext context) {
    final summary = synthesis?.trim() ?? '';
    final canPreviewHandoff = activeSynthesis != null &&
        activeSynthesis!.readyForReview &&
        activeSynthesis!.hasTraceableHandoff;
    final triageCandidateCardItems = triageItemsBuilder(
      reviewTriageParts,
      label: 'knowledge-card',
    );
    final triageReviewQuestions = triageItemsBuilder(
      reviewTriageParts,
      label: 'spaced-review',
    );
    final triageReasons = reviewTriageParts
        .where((part) => part.label?.trim() == 'reason')
        .map((part) => part.text?.trim() ?? '')
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
    final triageSuggestions = reviewTriageParts
        .where((part) => part.label?.trim() == 'ai-suggestion')
        .map((part) => part.text?.trim() ?? '')
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
    final triageRiskLevels = reviewTriageParts
        .where((part) => part.label?.trim() == 'risk')
        .map((part) => riskLabelBuilder(part.text))
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
    final triageSuggestedActions = reviewTriageParts
        .where((part) => part.label?.trim() == 'suggested-action')
        .map((part) => suggestedActionLabelBuilder(part.text))
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
    final candidateCardItems = canPreviewHandoff
        ? candidateCardItemsBuilder(activeSynthesis!)
        : triageCandidateCardItems;
    final reviewQuestions = canPreviewHandoff
        ? reviewQuestionItemsBuilder(activeSynthesis!)
        : triageReviewQuestions;
    final reviewReasons = canPreviewHandoff
        ? reasonTextsBuilder(activeSynthesis!)
        : triageReasons;
    final reviewSuggestions = canPreviewHandoff
        ? [
            if (triageSuggestionTextBuilder(activeSynthesis!)
                case final suggestion?)
              suggestion,
          ]
        : triageSuggestions;
    final reviewRiskLevels = canPreviewHandoff
        ? [riskLabelBuilder(riskLevelBuilder(activeSynthesis!))]
        : triageRiskLevels;
    final reviewSuggestedActions = canPreviewHandoff
        ? [
            suggestedActionLabelBuilder(
              suggestedActionBuilder(activeSynthesis!),
            ),
          ]
        : triageSuggestedActions;
    final candidateCardCount = canPreviewHandoff
        ? activeSynthesis!.candidateCards.length
        : candidateCardItems.length;
    final flashcardCandidateCount = reviewQuestions.length;
    final hasPreviewPayload = canPreviewHandoff ||
        candidateCardItems.isNotEmpty ||
        reviewQuestions.isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ClaudePalette.divider(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SeminarSnapshotHeading(
              Icons.fact_check_outlined,
              zh ? '异常处理预览' : 'Exception triage preview',
            ),
            const SizedBox(height: 8),
            SeminarSnapshotReviewLine(
              Icons.outbox_outlined,
              zh
                  ? '只在低置信、冲突或来源异常时发送到 Review Inbox'
                  : 'Send to Review Inbox only for low-confidence, conflict, or broken-source cases',
            ),
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 8),
              SeminarSnapshotDetailLabel(zh ? '综合总结' : 'Synthesis'),
              const SizedBox(height: 4),
              SeminarSnapshotExpandableText(
                summary,
                collapsedMaxLines: 5,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ClaudePalette.fg(context),
                      height: 1.35,
                    ),
              ),
            ],
            const SizedBox(height: 8),
            SeminarSnapshotReviewLine(
              Icons.link_outlined,
              zh
                  ? '可追踪证据：$evidenceCount 条'
                  : evidenceCount == 1
                      ? 'Traceable evidence: 1 source'
                      : 'Traceable evidence: $evidenceCount sources',
            ),
            if (reviewReasons.isNotEmpty) ...[
              const SizedBox(height: 8),
              SeminarSnapshotDetailLabel(zh ? '异常原因' : 'Review reasons'),
              const SizedBox(height: 4),
              for (final reason in reviewReasons) ...[
                SeminarSnapshotReviewLine(Icons.warning_amber_outlined, reason),
                const SizedBox(height: 4),
              ],
            ],
            if (reviewSuggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              SeminarSnapshotDetailLabel(
                zh ? 'AI 预审建议' : 'AI triage suggestion',
              ),
              const SizedBox(height: 4),
              for (final suggestion in reviewSuggestions) ...[
                SeminarSnapshotReviewLine(Icons.rule_outlined, suggestion),
                const SizedBox(height: 4),
              ],
            ],
            if (reviewRiskLevels.isNotEmpty) ...[
              const SizedBox(height: 8),
              SeminarSnapshotDetailLabel(zh ? 'AI 风险等级' : 'AI risk level'),
              const SizedBox(height: 4),
              for (final risk in reviewRiskLevels) ...[
                SeminarSnapshotReviewLine(Icons.shield_outlined, risk),
                const SizedBox(height: 4),
              ],
            ],
            if (reviewSuggestedActions.isNotEmpty) ...[
              const SizedBox(height: 8),
              SeminarSnapshotDetailLabel(zh ? '建议动作' : 'Suggested action'),
              const SizedBox(height: 4),
              for (final action in reviewSuggestedActions) ...[
                SeminarSnapshotReviewLine(Icons.task_alt_outlined, action),
                const SizedBox(height: 4),
              ],
            ],
            if (hasPreviewPayload) ...[
              const SizedBox(height: 8),
              SeminarSnapshotDetailLabel(
                zh ? '异常送审内容' : 'Exception Review payload',
              ),
              const SizedBox(height: 4),
              SeminarSnapshotReviewLine(
                Icons.summarize_outlined,
                zh ? '综合总结：1 项' : 'Synthesis: 1 item',
              ),
              const SizedBox(height: 4),
              SeminarSnapshotReviewLine(
                Icons.style_outlined,
                zh
                    ? '知识卡候选：$candidateCardCount 项'
                    : candidateCardCount == 1
                        ? 'KnowledgeCard candidates: 1 item'
                        : 'KnowledgeCard candidates: $candidateCardCount items',
              ),
              if (candidateCardItems.isNotEmpty) ...[
                const SizedBox(height: 3),
                SeminarSnapshotReviewItems(
                  label: zh ? '知识卡候选明细' : 'KnowledgeCard candidate details',
                  evidenceLabel: zh ? '候选证据' : 'Candidate evidence',
                  items: candidateCardItems,
                  evidenceTileBuilder: evidenceTileBuilder,
                ),
              ],
              const SizedBox(height: 4),
              SeminarSnapshotReviewLine(
                Icons.quiz_outlined,
                zh
                    ? '复习候选：$flashcardCandidateCount 项'
                    : flashcardCandidateCount == 1
                        ? 'Spaced Review candidates: 1 item'
                        : 'Spaced Review candidates: $flashcardCandidateCount items',
              ),
              if (reviewQuestions.isNotEmpty) ...[
                const SizedBox(height: 3),
                SeminarSnapshotReviewItems(
                  label: zh ? '复习候选明细' : 'Spaced Review candidate details',
                  evidenceLabel: zh ? '综合证据' : 'Synthesis evidence',
                  items: reviewQuestions,
                  evidenceTileBuilder: evidenceTileBuilder,
                ),
              ],
            ],
            const SizedBox(height: 6),
            Text(
              zh
                  ? '普通学习保存请优先使用知识卡、复习或我的图谱。'
                  : 'For normal learning saves, use KnowledgeCard, Spaced Review, or My Graph first.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ClaudePalette.secondary(context),
                    height: 1.32,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class SeminarSnapshotReviewItems extends StatelessWidget {
  const SeminarSnapshotReviewItems({
    required this.label,
    required this.evidenceLabel,
    required this.items,
    required this.evidenceTileBuilder,
    super.key,
  });

  final String label;
  final String evidenceLabel;
  final List<SeminarReviewPreviewItem> items;
  final SeminarWhiteboardEvidenceTileBuilder evidenceTileBuilder;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.toList(growable: false);
    final remainingCount = items.length - visibleItems.length;
    return Padding(
      padding: const EdgeInsets.only(left: 21),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SeminarSnapshotDetailLabel(label),
          const SizedBox(height: 3),
          for (final item in visibleItems)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '•',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                            ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SeminarSnapshotExpandableText(
                          item.text,
                          collapsedMaxLines: 2,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: ClaudePalette.secondary(context),
                                    height: 1.32,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  if (item.evidenceRefs.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SeminarSnapshotDetailLabel(evidenceLabel),
                          const SizedBox(height: 5),
                          for (final evidence in item.evidenceRefs)
                            evidenceTileBuilder(evidence),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (remainingCount > 0)
            Text(
              remainingCount == 1
                  ? '1 more item'
                  : '$remainingCount more items',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ClaudePalette.secondary(context),
                    height: 1.3,
                  ),
            ),
        ],
      ),
    );
  }
}

class SeminarSnapshotReviewLine extends StatelessWidget {
  const SeminarSnapshotReviewLine(this.icon, this.text, {super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: ClaudePalette.accent(context)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ClaudePalette.secondary(context),
                  height: 1.32,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}

class SeminarSnapshotWhiteboardGroup extends StatelessWidget {
  const SeminarSnapshotWhiteboardGroup({
    required this.icon,
    required this.label,
    required this.items,
    super.key,
  });

  final IconData icon;
  final String label;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ClaudePalette.divider(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15, color: ClaudePalette.accent(context)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: ClaudePalette.fg(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '•',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: ClaudePalette.secondary(context),
                            ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SeminarSnapshotExpandableText(
                          item,
                          collapsedMaxLines: 3,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: ClaudePalette.secondary(context),
                                    height: 1.32,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
