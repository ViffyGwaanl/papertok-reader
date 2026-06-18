import 'package:flutter/material.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';

enum SeminarRunSnapshotSubview {
  overview('overview'),
  status('status'),
  thinking('thinking'),
  controls('controls'),
  tools('tools'),
  evidence('evidence'),
  roles('roles'),
  disagreements('disagreements'),
  whiteboard('whiteboard'),
  summary('summary'),
  artifacts('artifacts'),
  review('review');

  const SeminarRunSnapshotSubview(this.id);

  final String id;
}

class SeminarSnapshotSubviewTabs extends StatelessWidget {
  const SeminarSnapshotSubviewTabs({
    required this.sessionId,
    required this.subviews,
    required this.selected,
    required this.zh,
    required this.onSelected,
    super.key,
  });

  final String sessionId;
  final List<SeminarRunSnapshotSubview> subviews;
  final SeminarRunSnapshotSubview selected;
  final bool zh;
  final ValueChanged<SeminarRunSnapshotSubview> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final subview in subviews) ...[
            ChoiceChip(
              key: ValueKey(
                'seminar-chat-card-snapshot-tab-${subview.id}-$sessionId',
              ),
              label: Text(seminarSnapshotSubviewLabel(subview, zh: zh)),
              selected: selected == subview,
              onSelected: (_) => onSelected(subview),
            ),
            if (subview != subviews.last) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

List<SeminarRunSnapshotSubview> seminarSnapshotAvailableSubviews({
  required List<AiSeminarRunCardToolCallSnapshot> toolCalls,
  required List<AiSeminarRunCardEvidenceSnapshot> evidence,
  required List<AiSeminarRunCardRoleSummary> roles,
  required bool hasLiveRole,
  required String? synthesis,
  required bool hasStatus,
  required bool hasThinking,
  required bool hasControls,
  required bool hasReviewTriage,
  required bool hasArtifactActions,
  required List<String> disagreements,
  required bool hasContradictionScans,
  required bool hasDisagreementRebuttals,
  required List<String> openQuestions,
}) {
  return [
    SeminarRunSnapshotSubview.overview,
    if (hasStatus) SeminarRunSnapshotSubview.status,
    if (hasThinking) SeminarRunSnapshotSubview.thinking,
    if (hasControls) SeminarRunSnapshotSubview.controls,
    if (toolCalls.isNotEmpty) SeminarRunSnapshotSubview.tools,
    if (evidence.isNotEmpty) SeminarRunSnapshotSubview.evidence,
    if (roles.isNotEmpty || hasLiveRole) SeminarRunSnapshotSubview.roles,
    if (disagreements.isNotEmpty ||
        hasContradictionScans ||
        hasDisagreementRebuttals)
      SeminarRunSnapshotSubview.disagreements,
    if (disagreements.isNotEmpty || openQuestions.isNotEmpty)
      SeminarRunSnapshotSubview.whiteboard,
    if (synthesis != null && synthesis.isNotEmpty)
      SeminarRunSnapshotSubview.summary,
    if (hasArtifactActions) SeminarRunSnapshotSubview.artifacts,
    if ((synthesis != null && synthesis.isNotEmpty) ||
        evidence.isNotEmpty ||
        hasReviewTriage)
      SeminarRunSnapshotSubview.review,
  ];
}

SeminarRunSnapshotSubview seminarSnapshotSelectedSubview(
  String? sessionId,
  List<SeminarRunSnapshotSubview> available,
  Map<String, SeminarRunSnapshotSubview> selectedBySession,
) {
  final selected = sessionId == null ? null : selectedBySession[sessionId];
  if (selected != null && available.contains(selected)) return selected;
  return SeminarRunSnapshotSubview.overview;
}

String seminarSnapshotSubviewLabel(
  SeminarRunSnapshotSubview subview, {
  required bool zh,
}) {
  switch (subview) {
    case SeminarRunSnapshotSubview.overview:
      return zh ? '全部' : 'All';
    case SeminarRunSnapshotSubview.status:
      return zh ? '状态' : 'Status';
    case SeminarRunSnapshotSubview.thinking:
      return zh ? '思考' : 'Thinking';
    case SeminarRunSnapshotSubview.controls:
      return zh ? '控制' : 'Controls';
    case SeminarRunSnapshotSubview.tools:
      return zh ? '调用' : 'Calls';
    case SeminarRunSnapshotSubview.evidence:
      return zh ? '证据' : 'Evidence';
    case SeminarRunSnapshotSubview.roles:
      return zh ? '角色' : 'Roles';
    case SeminarRunSnapshotSubview.disagreements:
      return zh ? '分歧' : 'Disputes';
    case SeminarRunSnapshotSubview.whiteboard:
      return zh ? '白板' : 'Whiteboard';
    case SeminarRunSnapshotSubview.summary:
      return zh ? '总结' : 'Summary';
    case SeminarRunSnapshotSubview.artifacts:
      return zh ? '沉淀' : 'Assets';
    case SeminarRunSnapshotSubview.review:
      return zh ? '异常' : 'Triage';
  }
}
