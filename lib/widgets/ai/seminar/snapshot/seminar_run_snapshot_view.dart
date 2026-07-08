import 'package:flutter/material.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/providers/ai_seminar_runtime.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/ai/seminar/disagreement/seminar_disagreement_widgets.dart';
import 'package:papertok_reader/widgets/ai/seminar/evidence/seminar_evidence_widgets.dart';
import 'package:papertok_reader/widgets/ai/seminar/participation/seminar_participation_widgets.dart';
import 'package:papertok_reader/widgets/ai/seminar/roles/seminar_role_widgets.dart';
import 'package:papertok_reader/widgets/ai/seminar/shared/seminar_snapshot_widgets.dart';
import 'package:papertok_reader/widgets/ai/seminar/snapshot/seminar_snapshot_tabs.dart';
import 'package:papertok_reader/widgets/ai/seminar/timeline/seminar_timeline_widgets.dart';
import 'package:papertok_reader/widgets/ai/seminar/tools/seminar_tool_widgets.dart';
import 'package:papertok_reader/widgets/ai/seminar/whiteboard/seminar_whiteboard_widgets.dart';

part 'seminar_run_snapshot_bindings.dart';

class SeminarRunSnapshotView extends StatelessWidget {
  const SeminarRunSnapshotView({
    required this.sessionId,
    required this.snapshot,
    required this.runtimeState,
    required this.bookId,
    required this.evidenceScopeIds,
    required this.bindings,
    super.key,
  });

  final String? sessionId;
  final AiSeminarRunCardSnapshot snapshot;
  final AiSeminarRuntimeState runtimeState;
  final int? bookId;
  final List<String> evidenceScopeIds;
  final SeminarRunSnapshotBindings bindings;

  @override
  Widget build(BuildContext context) {
    final allEvidence = bindings._seminarSnapshotEvidence(snapshot);
    final evidence = allEvidence;
    final toolCalls = bindings._seminarSnapshotToolCalls(
      snapshot,
      bookId: bookId,
      evidenceScopeIds: evidenceScopeIds,
    );
    final roles = bindings._seminarSnapshotRoleTurns(snapshot);
    final readerTurns = bindings._seminarSnapshotReaderTurns(snapshot);
    final isLiveSession = runtimeState.session?.id == sessionId;
    final hasLiveReaderComposer = isLiveSession &&
        runtimeState.evidenceBundle != null &&
        (runtimeState.status == AiSeminarRunStatus.completed ||
            runtimeState.directorState?.needsUserInput == true);
    final readerComposers = bindings
        ._seminarSnapshotReaderComposers(snapshot)
        .where((_) => !hasLiveReaderComposer)
        .toList(growable: false);
    final hasLiveDirectorCue =
        isLiveSession && runtimeState.directorState?.needsUserInput == true;
    final directorCues = bindings
        ._seminarSnapshotDirectorCues(snapshot)
        .where((_) => !hasLiveDirectorCue)
        .toList(growable: false);
    final agentStatuses = bindings._seminarSnapshotAgentStatuses(snapshot);
    final synthesis = bindings._seminarSnapshotSynthesisSummary(snapshot);
    final synthesisEvidenceRefs =
        bindings._seminarSnapshotSynthesisEvidenceRefs(snapshot);
    final disagreements = snapshot.disagreements
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final disagreementDetails =
        bindings._seminarSnapshotDisagreementDetailsFromParts(
      snapshot,
    );
    final disagreementRebuttals =
        bindings._seminarSnapshotDisagreementRebuttals(snapshot);
    final contradictionScans =
        bindings._seminarSnapshotContradictionScans(snapshot);
    final disagreementDetailTexts = disagreementDetails
        .map((item) => item.text.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final legacyOnlyDisagreements = disagreements
        .where((item) => !disagreementDetailTexts.contains(item))
        .toList(growable: false);
    final disagreementTexts = <String>[
      ...disagreementDetailTexts,
      ...legacyOnlyDisagreements,
    ];
    final openQuestions = snapshot.openQuestions
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final liveRole = isLiveSession ? runtimeState.activeRole : null;
    final liveRoleText =
        isLiveSession ? runtimeState.partialRoleText?.trim() ?? '' : '';
    final hasLiveRole = liveRole != null && liveRoleText.isNotEmpty;
    final rolePartials = bindings
        ._seminarSnapshotRolePartials(snapshot)
        .where(
          (partial) =>
              !(hasLiveRole && partial.roleId.trim() == liveRole.asString),
        )
        .toList(growable: false);
    final hasRolePartial = rolePartials.isNotEmpty || hasLiveRole;
    final nativeTimelineSourceParts = bindings
        ._seminarSnapshotNativeTimelineParts(
          snapshot,
          bookId: bookId,
          evidenceScopeIds: evidenceScopeIds,
        )
        .toList(growable: false);
    final hasLegacySnapshotContent =
        bindings._seminarSnapshotHasLegacySnapshotContent(snapshot);
    final reviewTriageParts =
        bindings._seminarSnapshotReviewTriageParts(snapshot);
    final artifactActionParts =
        bindings._seminarSnapshotArtifactActionParts(snapshot);
    final controlDirectorCues =
        bindings._seminarSnapshotControlDirectorCues(directorCues);
    final hasStatus = directorCues.isNotEmpty && !hasLegacySnapshotContent;
    final hasControlParts = controlDirectorCues.isNotEmpty ||
        agentStatuses.isNotEmpty ||
        readerComposers.isNotEmpty ||
        readerTurns.isNotEmpty;
    final hasControls = hasControlParts && !hasLegacySnapshotContent;
    final snapshotThinkingParts =
        bindings._seminarSnapshotThinkingParts(snapshot);
    final runtimeThinkingParts = isLiveSession
        ? bindings._seminarRuntimeThinkingParts(runtimeState)
        : const <AiSeminarRunCardMessagePart>[];
    final thinkingParts = runtimeThinkingParts.isNotEmpty
        ? bindings._mergeSeminarNativeTimelineParts(
            runtimeThinkingParts,
            snapshotThinkingParts,
          )
        : snapshotThinkingParts;
    final availableSubViews = seminarSnapshotAvailableSubviews(
      toolCalls: toolCalls,
      evidence: evidence,
      roles: roles,
      hasLiveRole: hasRolePartial,
      synthesis: synthesis,
      hasStatus: hasStatus,
      hasThinking: thinkingParts.isNotEmpty,
      hasControls: hasControls,
      hasReviewTriage: reviewTriageParts.isNotEmpty,
      hasArtifactActions: artifactActionParts.isNotEmpty,
      disagreements: disagreementTexts,
      hasContradictionScans: contradictionScans.isNotEmpty,
      hasDisagreementRebuttals: disagreementRebuttals.isNotEmpty,
      openQuestions: openQuestions,
    );
    final selectedSubview = seminarSnapshotSelectedSubview(
      sessionId,
      availableSubViews,
      bindings._seminarCardSnapshotSubviews,
    );
    final showOverview = selectedSubview == SeminarRunSnapshotSubview.overview;
    final showNativeTimeline = showOverview &&
        bindings._seminarSnapshotShouldUseNativeTimeline(
          snapshot,
          nativeTimelineSourceParts,
          allowLegacySnapshotContent: true,
        );
    final useCompactNativeTimeline =
        showNativeTimeline && hasLegacySnapshotContent;
    final collapsedNativeTimelineParts = useCompactNativeTimeline
        ? bindings._seminarSnapshotCompactNativeTimelineParts(
            nativeTimelineSourceParts)
        : bindings._seminarSnapshotCollapsedNativeTimelineParts(
            nativeTimelineSourceParts,
          );
    final isNativeTimelineExpanded = sessionId != null &&
        bindings._seminarCardTimelineExpandedSessionIds.contains(sessionId);
    final canToggleNativeTimelineExpansion = sessionId != null &&
        nativeTimelineSourceParts.length > collapsedNativeTimelineParts.length;
    final nativeTimelineParts = isNativeTimelineExpanded
        ? nativeTimelineSourceParts
        : collapsedNativeTimelineParts;
    final hiddenNativeTimelinePartCount =
        nativeTimelineSourceParts.length - nativeTimelineParts.length;
    final showStatus =
        selectedSubview == SeminarRunSnapshotSubview.status && hasStatus;
    final showThinking = thinkingParts.isNotEmpty &&
        ((showOverview && !showNativeTimeline) ||
            selectedSubview == SeminarRunSnapshotSubview.thinking);
    final showControls =
        selectedSubview == SeminarRunSnapshotSubview.controls && hasControls;
    final showToolCalls = selectedSubview == SeminarRunSnapshotSubview.tools;
    final showTimeline = showOverview &&
        !showNativeTimeline &&
        (roles.isNotEmpty || hasRolePartial);
    final showDirectorCues =
        showOverview && !showNativeTimeline && directorCues.isNotEmpty;
    final showAgentStatuses =
        showOverview && !showNativeTimeline && agentStatuses.isNotEmpty;
    final showReaderActivity = showOverview &&
        !showNativeTimeline &&
        (readerComposers.isNotEmpty || readerTurns.isNotEmpty);
    final showEvidence = (showOverview &&
            !showNativeTimeline &&
            synthesisEvidenceRefs.isEmpty) ||
        selectedSubview == SeminarRunSnapshotSubview.evidence;
    final showRoles = selectedSubview == SeminarRunSnapshotSubview.roles;
    final showSummary = (showOverview && !showNativeTimeline) ||
        selectedSubview == SeminarRunSnapshotSubview.summary;
    final showArtifacts =
        selectedSubview == SeminarRunSnapshotSubview.artifacts;
    final showReview = selectedSubview == SeminarRunSnapshotSubview.review;
    final showWhiteboard = (showOverview && !showNativeTimeline) ||
        selectedSubview == SeminarRunSnapshotSubview.whiteboard;
    final showDisagreements =
        selectedSubview == SeminarRunSnapshotSubview.disagreements;
    final activeSynthesis = isLiveSession ? runtimeState.synthesis : null;
    final snapshotSessionId = sessionId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (snapshotSessionId != null && availableSubViews.length > 1) ...[
          SeminarSnapshotSubviewTabs(
            sessionId: snapshotSessionId,
            subviews: availableSubViews,
            selected: selectedSubview,
            zh: bindings._isChineseLocale,
            onSelected: (subview) =>
                bindings._onSnapshotSubviewSelected(snapshotSessionId, subview),
          ),
          const SizedBox(height: 8),
        ],
        if (showNativeTimeline) ...[
          SeminarSnapshotNativeTimeline(
            parts: nativeTimelineParts,
            sessionId: sessionId,
            hiddenPartCount: hiddenNativeTimelinePartCount,
            canToggleExpansion: canToggleNativeTimelineExpansion,
            isExpanded: isNativeTimelineExpanded,
            zh: bindings._isChineseLocale,
            onToggleExpansion: () => bindings._onToggleNativeTimelineExpansion(
              sessionId,
              isNativeTimelineExpanded,
            ),
            partBuilder: (part, roleTurnNumber) =>
                bindings._seminarTimelinePartView(
              part,
              sessionId: sessionId,
              bookId: bookId,
              showInlineEvidence:
                  !useCompactNativeTimeline || isNativeTimelineExpanded,
              showTraceDetails:
                  !useCompactNativeTimeline || isNativeTimelineExpanded,
              roleTurnNumber: roleTurnNumber,
            ),
          ),
          if (showToolCalls && toolCalls.isNotEmpty) const SizedBox(height: 10),
        ],
        if (showStatus) ...[
          SeminarSnapshotHeading(
            Icons.pending_actions_outlined,
            bindings._localizedSeminarCardText(
              zh: '状态详情',
              en: 'Status details',
            ),
          ),
          const SizedBox(height: 6),
          for (final cue in directorCues)
            bindings._buildSeminarDirectorCueView(cue, sessionId: sessionId),
          if (showToolCalls && toolCalls.isNotEmpty) const SizedBox(height: 10),
        ],
        if (showThinking && thinkingParts.isNotEmpty) ...[
          SeminarSnapshotHeading(
            Icons.psychology_outlined,
            selectedSubview == SeminarRunSnapshotSubview.thinking
                ? bindings._localizedSeminarCardText(
                    zh: '思考详情',
                    en: 'Thinking details',
                  )
                : bindings._localizedSeminarCardText(
                    zh: '思考',
                    en: 'Thinking',
                  ),
          ),
          const SizedBox(height: 6),
          for (final part in thinkingParts)
            bindings._seminarTimelinePartView(
              part,
              sessionId: sessionId,
              bookId: bookId,
              showInlineEvidence: true,
              showTraceDetails: true,
              roleTurnNumber: null,
            ),
          if (showToolCalls && toolCalls.isNotEmpty) const SizedBox(height: 10),
        ],
        if (showControls) ...[
          SeminarSnapshotHeading(
            Icons.tune_outlined,
            bindings._localizedSeminarCardText(
              zh: '控制详情',
              en: 'Control details',
            ),
          ),
          const SizedBox(height: 6),
          for (final cue in controlDirectorCues)
            bindings._buildSeminarDirectorCueView(cue, sessionId: sessionId),
          for (final status in agentStatuses)
            SeminarSnapshotAgentStatusTile(
              part: status,
              zh: bindings._isChineseLocale,
              statusLabelBuilder: bindings._seminarAgentStatusLabel,
              roleLabelBuilder: bindings._seminarRoleFallbackLabel,
              actionLabelBuilder: (actionId) => seminarAgentControlActionLabel(
                actionId,
                zh: bindings._isChineseLocale,
              ),
              actionEnabledBuilder: (actionId) =>
                  seminarAgentControlActionIsExecutable(
                status,
                actionId: actionId,
                sessionId: sessionId,
              ),
              actionWidgetBuilder: (actionId) =>
                  bindings._buildSeminarAgentControlActionView(
                status,
                actionId: actionId,
                sessionId: sessionId,
              ),
              allowedToolIdsBuilder: (toolIds) =>
                  bindings._effectiveSeminarStatusAllowedToolIds(
                toolIds,
                bookId: bookId,
              ),
              toolLabelBuilder: bindings._seminarToolDisplayLabel,
              agentInputComposer:
                  bindings._buildSeminarAgentInputComposerForPart(
                status,
                sessionId: sessionId,
              ),
            ),
          for (final composer in readerComposers)
            bindings._buildSeminarReaderComposerView(composer),
          for (final readerTurn in readerTurns)
            bindings._buildSeminarReaderTurnView(readerTurn),
          if (showToolCalls && toolCalls.isNotEmpty) const SizedBox(height: 10),
        ],
        if (showTimeline) ...[
          SeminarSnapshotDiscussionTimeline(
            roles: roles,
            rolePartials: rolePartials,
            liveRole: liveRole,
            liveRoleText: liveRoleText,
            zh: bindings._isChineseLocale,
            roleLabelBuilder: bindings._seminarRoleFallbackLabel,
            roleIconBuilder: bindings._seminarRoleIconById,
            onEvidencePressed: bindings._jumpToSeminarEvidenceRow,
            evidenceTileBuilder: (evidence, fallbackIndex) =>
                SeminarSnapshotEvidenceTile(
              evidence,
              zh: bindings._isChineseLocale,
              missingSourceLabel: bindings._seminarMissingSourceLabel,
              sourceAction: bindings._seminarSnapshotEvidenceSourceAction(
                evidence.sourceRef,
              ),
              fallbackIndex: fallbackIndex,
            ),
          ),
          if ((showToolCalls && toolCalls.isNotEmpty) ||
              (showEvidence && evidence.isNotEmpty) ||
              showAgentStatuses ||
              showDirectorCues ||
              showReaderActivity ||
              (showSummary && synthesis != null && synthesis.isNotEmpty) ||
              disagreementTexts.isNotEmpty ||
              openQuestions.isNotEmpty)
            const SizedBox(height: 10),
        ],
        if (showDirectorCues) ...[
          SeminarSnapshotHeading(
            Icons.psychology_outlined,
            bindings._localizedSeminarCardText(
              zh: '主持人下一步',
              en: 'Director next step',
            ),
          ),
          const SizedBox(height: 6),
          for (final cue in directorCues)
            bindings._buildSeminarDirectorCueView(cue, sessionId: sessionId),
          if ((showToolCalls && toolCalls.isNotEmpty) ||
              (showEvidence && evidence.isNotEmpty) ||
              showAgentStatuses ||
              showReaderActivity ||
              (showSummary && synthesis != null && synthesis.isNotEmpty) ||
              disagreementTexts.isNotEmpty ||
              openQuestions.isNotEmpty)
            const SizedBox(height: 10),
        ],
        if (showAgentStatuses) ...[
          SeminarSnapshotHeading(
            Icons.support_agent_outlined,
            bindings._localizedSeminarCardText(
              zh: '角色状态',
              en: 'Role status',
            ),
          ),
          const SizedBox(height: 6),
          for (final status in agentStatuses)
            SeminarSnapshotAgentStatusTile(
              part: status,
              zh: bindings._isChineseLocale,
              statusLabelBuilder: bindings._seminarAgentStatusLabel,
              roleLabelBuilder: bindings._seminarRoleFallbackLabel,
              actionLabelBuilder: (actionId) => seminarAgentControlActionLabel(
                actionId,
                zh: bindings._isChineseLocale,
              ),
              actionEnabledBuilder: (actionId) =>
                  seminarAgentControlActionIsExecutable(
                status,
                actionId: actionId,
                sessionId: sessionId,
              ),
              actionWidgetBuilder: (actionId) =>
                  bindings._buildSeminarAgentControlActionView(
                status,
                actionId: actionId,
                sessionId: sessionId,
              ),
              allowedToolIdsBuilder: (toolIds) =>
                  bindings._effectiveSeminarStatusAllowedToolIds(
                toolIds,
                bookId: bookId,
              ),
              toolLabelBuilder: bindings._seminarToolDisplayLabel,
              agentInputComposer:
                  bindings._buildSeminarAgentInputComposerForPart(
                status,
                sessionId: sessionId,
              ),
            ),
          if ((showToolCalls && toolCalls.isNotEmpty) ||
              (showEvidence && evidence.isNotEmpty) ||
              showReaderActivity ||
              (showSummary && synthesis != null && synthesis.isNotEmpty) ||
              disagreementTexts.isNotEmpty ||
              openQuestions.isNotEmpty)
            const SizedBox(height: 10),
        ],
        if (showReaderActivity) ...[
          SeminarSnapshotHeading(
            Icons.person_outline,
            bindings._localizedSeminarCardText(
              zh: '读者参与',
              en: 'Reader turns',
            ),
          ),
          const SizedBox(height: 6),
          for (final composer in readerComposers)
            bindings._buildSeminarReaderComposerView(composer),
          for (final readerTurn in readerTurns)
            bindings._buildSeminarReaderTurnView(readerTurn),
          if ((showToolCalls && toolCalls.isNotEmpty) ||
              (showEvidence && evidence.isNotEmpty) ||
              (showSummary && synthesis != null && synthesis.isNotEmpty) ||
              disagreementTexts.isNotEmpty ||
              openQuestions.isNotEmpty)
            const SizedBox(height: 10),
        ],
        if (showToolCalls && toolCalls.isNotEmpty) ...[
          SeminarSnapshotHeading(
            Icons.travel_explore_outlined,
            bindings._localizedSeminarCardText(
              zh: '工具调用详情',
              en: 'Tool call details',
            ),
          ),
          const SizedBox(height: 6),
          for (final item in toolCalls)
            SeminarSnapshotToolCallTile(
              toolCall: item,
              label: bindings._seminarToolCallLabel(item),
              statusLabel: bindings._seminarToolCallStatusLabel(item),
              startedAtLabel: bindings._seminarToolCallStartedAtLabel(item),
              completedAtLabel: bindings._seminarToolCallCompletedAtLabel(item),
              durationLabel: bindings._seminarToolCallDurationLabel(item),
              visibleRoleLabels:
                  bindings._seminarToolCallVisibleRoleLabel(item),
              outputLabel: bindings._seminarToolCallOutputLabel(item),
              zh: bindings._isChineseLocale,
              actionLabelBuilder: bindings._seminarToolCallActionLabel,
              actionIconBuilder: bindings._seminarToolCallActionIcon,
              actionEnabledBuilder: (actionId) =>
                  bindings._seminarToolCallActionIsExecutable(
                item,
                actionId: actionId,
                sessionId: sessionId,
              ),
              actionPressedBuilder: (actionId) =>
                  bindings._seminarToolCallActionPressed(
                item,
                actionId: actionId,
                sessionId: sessionId,
              ),
              isSubmitting: bindings._seminarCardSubmittingSessionIds.contains(
                sessionId?.trim(),
              ),
              evidenceTileBuilder: (evidence) => SeminarSnapshotEvidenceTile(
                evidence,
                zh: bindings._isChineseLocale,
                missingSourceLabel: bindings._seminarMissingSourceLabel,
                sourceAction: bindings._seminarSnapshotEvidenceSourceAction(
                  evidence.sourceRef,
                ),
              ),
            ),
        ],
        if (showEvidence && evidence.isNotEmpty) ...[
          if ((showToolCalls && toolCalls.isNotEmpty) || showReaderActivity)
            const SizedBox(height: 10),
          SeminarSnapshotHeading(
            Icons.fact_check_outlined,
            bindings._localizedSeminarCardText(
              zh: '证据快照',
              en: 'Evidence snapshot',
            ),
          ),
          const SizedBox(height: 6),
          for (var index = 0; index < evidence.length; index++)
            SeminarSnapshotEvidenceTile(
              evidence[index],
              key: bindings._seminarEvidenceTileKey(evidence[index]),
              zh: bindings._isChineseLocale,
              missingSourceLabel: bindings._seminarMissingSourceLabel,
              sourceAction: bindings._seminarSnapshotEvidenceSourceAction(
                evidence[index].sourceRef,
              ),
              fallbackIndex: index + 1,
            ),
        ],
        if (showRoles && (roles.isNotEmpty || hasRolePartial)) ...[
          if ((showToolCalls && toolCalls.isNotEmpty) ||
              showReaderActivity ||
              (showEvidence && evidence.isNotEmpty))
            const SizedBox(height: 10),
          SeminarSnapshotHeading(
            Icons.forum_outlined,
            bindings._localizedSeminarCardText(
              zh: '角色观点',
              en: 'Role views',
            ),
          ),
          const SizedBox(height: 6),
          if (hasLiveRole)
            SeminarSnapshotLiveRoleTile(
              label: bindings._seminarRoleFallbackLabel(liveRole.asString),
              icon: bindings._seminarRoleIconById(liveRole.asString),
              partialText: liveRoleText,
              zh: bindings._isChineseLocale,
            ),
          for (final partial in rolePartials)
            SeminarSnapshotRolePartialTile(
              partial: partial,
              label: partial.label.trim().isNotEmpty
                  ? partial.label.trim()
                  : bindings._seminarRoleFallbackLabel(partial.roleId.trim()),
              icon: bindings._seminarRoleIconById(partial.roleId),
              zh: bindings._isChineseLocale,
            ),
          for (final role in roles)
            SeminarSnapshotRoleTile(
              role: role,
              label: role.label.trim().isNotEmpty
                  ? role.label.trim()
                  : bindings._seminarRoleFallbackLabel(role.roleId),
              icon: bindings._seminarRoleIconById(role.roleId),
              zh: bindings._isChineseLocale,
              onEvidencePressed: bindings._jumpToSeminarEvidenceRow,
            ),
        ],
        if (showSummary && synthesis != null && synthesis.isNotEmpty) ...[
          if ((showToolCalls && toolCalls.isNotEmpty) ||
              showReaderActivity ||
              (showEvidence && evidence.isNotEmpty) ||
              (showRoles && roles.isNotEmpty))
            const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SeminarSnapshotHeading(
                  Icons.auto_awesome_outlined,
                  bindings._localizedSeminarCardText(
                    zh: '研讨总结',
                    en: 'Seminar summary',
                  ),
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (snapshot.disagreements.isNotEmpty ||
                      disagreementDetails.isNotEmpty)
                    SeminarSnapshotTinyChip(
                      bindings._seminarCountLabel(
                        disagreementTexts.length,
                        zhUnit: '个分歧',
                        enSingular: 'disagreement',
                        enPlural: 'disagreements',
                      ),
                    ),
                  if (snapshot.openQuestions.isNotEmpty)
                    SeminarSnapshotTinyChip(
                      bindings._seminarCountLabel(
                        snapshot.openQuestions.length,
                        zhUnit: '个问题',
                        enSingular: 'question',
                        enPlural: 'questions',
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          SeminarSnapshotExpandableText(
            synthesis,
            collapsedMaxLines: 4,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ClaudePalette.fg(context),
                  height: 1.35,
                ),
          ),
          SeminarSnapshotCompactEvidenceRows(
            evidenceRefs: synthesisEvidenceRefs,
            linkedEvidenceLabel: bindings._seminarLinkedEvidenceLabel,
            missingSourceLabel: bindings._seminarMissingSourceLabel,
            sourceActionBuilder: (evidence) => bindings
                ._seminarSnapshotEvidenceSourceAction(evidence.sourceRef),
          ),
        ],
        if (showDisagreements &&
            (disagreementTexts.isNotEmpty ||
                contradictionScans.isNotEmpty ||
                disagreementRebuttals.isNotEmpty)) ...[
          SeminarSnapshotHeading(
            Icons.report_problem_outlined,
            bindings._localizedSeminarCardText(
              zh: '分歧视图',
              en: 'Disagreements view',
            ),
          ),
          const SizedBox(height: 6),
          if (contradictionScans.isNotEmpty)
            SeminarSnapshotContradictionScanTiles(
              parts: contradictionScans,
              zh: bindings._isChineseLocale,
              roleLabelsBuilder: bindings._seminarRoleLabels,
              countLabelBuilder: bindings._seminarCountLabel,
              evidenceTileBuilder: (evidence) => SeminarSnapshotEvidenceTile(
                evidence,
                zh: bindings._isChineseLocale,
                missingSourceLabel: bindings._seminarMissingSourceLabel,
                sourceAction: bindings._seminarSnapshotEvidenceSourceAction(
                  evidence.sourceRef,
                ),
              ),
            ),
          if (contradictionScans.isNotEmpty &&
              (disagreementRebuttals.isNotEmpty ||
                  disagreementDetails.isNotEmpty ||
                  legacyOnlyDisagreements.isNotEmpty))
            const SizedBox(height: 6),
          if (disagreementRebuttals.isNotEmpty)
            SeminarSnapshotDisagreementRebuttalTiles(
              parts: disagreementRebuttals,
              zh: bindings._isChineseLocale,
              roleLabelBuilder: bindings._seminarRoleFallbackLabel,
              evidenceTileBuilder: (evidence) => SeminarSnapshotEvidenceTile(
                evidence,
                zh: bindings._isChineseLocale,
                missingSourceLabel: bindings._seminarMissingSourceLabel,
                sourceAction: bindings._seminarSnapshotEvidenceSourceAction(
                  evidence.sourceRef,
                ),
              ),
            ),
          if (disagreementRebuttals.isNotEmpty &&
              (disagreementDetails.isNotEmpty ||
                  legacyOnlyDisagreements.isNotEmpty))
            const SizedBox(height: 6),
          if (disagreementDetails.isNotEmpty)
            SeminarSnapshotDisagreementDetails(
              details: disagreementDetails,
              zh: bindings._isChineseLocale,
              roleLabelsBuilder: bindings._seminarRoleLabels,
              evidenceTileBuilder: (evidence) => SeminarSnapshotEvidenceTile(
                evidence,
                zh: bindings._isChineseLocale,
                missingSourceLabel: bindings._seminarMissingSourceLabel,
                sourceAction: bindings._seminarSnapshotEvidenceSourceAction(
                  evidence.sourceRef,
                ),
              ),
            ),
          if (legacyOnlyDisagreements.isNotEmpty)
            SeminarSnapshotWhiteboardGroup(
              icon: Icons.report_problem_outlined,
              label: bindings._localizedSeminarCardText(
                zh: '分歧',
                en: 'Disagreements',
              ),
              items: legacyOnlyDisagreements,
            ),
        ],
        if (showReview) ...[
          SeminarSnapshotReviewPreview(
            synthesis: synthesis,
            evidenceCount: allEvidence.length,
            activeSynthesis: activeSynthesis,
            reviewTriageParts: reviewTriageParts,
            zh: bindings._isChineseLocale,
            triageItemsBuilder: bindings._seminarReviewTriageItems,
            reasonTextsBuilder: bindings._seminarReviewReasonTexts,
            candidateCardItemsBuilder:
                bindings._seminarReviewCandidateCardItems,
            reviewQuestionItemsBuilder: bindings._seminarReviewQuestionItems,
            riskLevelBuilder: bindings._seminarReviewRiskLevel,
            riskLabelBuilder: bindings._seminarReviewRiskLabel,
            suggestedActionBuilder: bindings._seminarReviewSuggestedAction,
            suggestedActionLabelBuilder:
                bindings._seminarReviewSuggestedActionLabel,
            triageSuggestionTextBuilder:
                bindings._seminarReviewTriageSuggestionText,
            evidenceTileBuilder: (evidence) => SeminarSnapshotEvidenceTile(
              evidence,
              zh: bindings._isChineseLocale,
              missingSourceLabel: bindings._seminarMissingSourceLabel,
              sourceAction: bindings._seminarSnapshotEvidenceSourceAction(
                evidence.sourceRef,
              ),
              expandableSnippet: true,
            ),
          ),
        ],
        if (showArtifacts && artifactActionParts.isNotEmpty) ...[
          SeminarSnapshotHeading(
            Icons.inventory_2_outlined,
            bindings._localizedSeminarCardText(
              zh: '沉淀动作详情',
              en: 'Artifact action details',
            ),
          ),
          const SizedBox(height: 6),
          for (final part in artifactActionParts)
            SeminarSnapshotArtifactActionsPartTile(
              part: part,
              zh: bindings._isChineseLocale,
              actionChipLabelBuilder: bindings._seminarArtifactActionChipLabel,
              displayTextBuilder: bindings._seminarArtifactActionDisplayText,
              statusLabelBuilder: bindings._seminarArtifactActionStatusLabel,
              completedAtLabelBuilder:
                  bindings._seminarArtifactActionCompletedAtLabel,
              detailLabelBuilder: bindings._seminarArtifactActionDetailLabel,
              linkedEvidenceLabel: bindings._seminarLinkedEvidenceLabel,
              missingSourceLabel: bindings._seminarMissingSourceLabel,
              evidenceSourceActionBuilder: (evidence) => bindings
                  ._seminarSnapshotEvidenceSourceAction(evidence.sourceRef),
            ),
        ],
        if (showWhiteboard &&
            (disagreementTexts.isNotEmpty || openQuestions.isNotEmpty)) ...[
          if ((showToolCalls && toolCalls.isNotEmpty) ||
              showReaderActivity ||
              (showEvidence && evidence.isNotEmpty) ||
              (showRoles && roles.isNotEmpty) ||
              (showSummary && synthesis != null))
            const SizedBox(height: 10),
          SeminarSnapshotWhiteboardSection(
            disagreements: disagreementTexts,
            openQuestions: openQuestions,
            zh: bindings._isChineseLocale,
          ),
        ],
      ],
    );
  }
}
