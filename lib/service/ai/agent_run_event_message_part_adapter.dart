import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/service/ai/agent_run_graph_store.dart';
import 'package:papertok_reader/service/ai/sub_agent_runner.dart';

Future<List<AiSeminarRunCardMessagePart>>
    seminarMessagePartsFromAgentRunGraphStore(
  AgentRunGraphStore store, {
  required String parentRunId,
}) async {
  final events = _mergeAgentRunEvents(
    await store.listEvents(parentRunId),
    await store.listChildEvents(parentRunId),
    _openChildStatusEvents(
      await store.listOpenChildren(parentRunId),
    ),
  );
  return seminarMessagePartsFromAgentRunEvents(events);
}

List<AiSeminarRunCardMessagePart> seminarMessagePartsFromAgentRunEvents(
  Iterable<AgentRunEvent> events,
) {
  final dedupedEvents = _dedupeAgentRunEventsById(events);
  final toolCallStartedAtByKey = _toolCallStartedAtByKey(dedupedEvents);
  final effectiveEvents = _dropSupersededStatusEvents(dedupedEvents);
  final messageParts = <AiSeminarRunCardMessagePart>[];
  for (final event in effectiveEvents) {
    final part = seminarMessagePartFromAgentRunEvent(event);
    if (part == null) continue;
    messageParts.add(
      _withToolCallStartedAt(
        part,
        event,
        toolCallStartedAtByKey,
      ),
    );
  }
  return [
    ..._normalizeTerminalReaderTurnParts(messageParts, effectiveEvents),
    ..._evidencePartsFromToolCallEvents(effectiveEvents),
  ];
}

Map<String, int> _toolCallStartedAtByKey(Iterable<AgentRunEvent> events) {
  final out = <String, int>{};
  for (final event in events) {
    if (event.type != AgentRunEventType.toolCall ||
        !_isActiveToolCallStatus(event.status)) {
      continue;
    }
    final startedAt = event.createdAt.millisecondsSinceEpoch;
    final key = _toolCallEventKey(event);
    final current = out[key];
    if (current == null || startedAt < current) {
      out[key] = startedAt;
    }
  }
  return out;
}

AiSeminarRunCardMessagePart _withToolCallStartedAt(
  AiSeminarRunCardMessagePart part,
  AgentRunEvent event,
  Map<String, int> startedAtByKey,
) {
  if (part.type != 'tool_call' || part.startedAt != null) return part;
  final startedAt = startedAtByKey[_toolCallEventKey(event)];
  if (startedAt == null || startedAt <= 0) return part;
  return AiSeminarRunCardMessagePart(
    type: part.type,
    id: part.id,
    agentRunId: part.agentRunId,
    parentRunId: part.parentRunId,
    roleId: part.roleId,
    roleIds: part.roleIds,
    actionIds: part.actionIds,
    allowedToolIds: part.allowedToolIds,
    defaultRoleId: part.defaultRoleId,
    defaultActionId: part.defaultActionId,
    selectedRoleId: part.selectedRoleId,
    selectedActionId: part.selectedActionId,
    draftText: part.draftText,
    toolId: part.toolId,
    status: part.status,
    label: part.label,
    text: part.text,
    query: part.query,
    resultCount: part.resultCount,
    startedAt: startedAt,
    completedAt: part.completedAt,
    evidenceRefs: part.evidenceRefs,
  );
}

AiSeminarRunCardMessagePart? seminarMessagePartFromAgentRunEvent(
  AgentRunEvent event,
) {
  switch (event.type) {
    case AgentRunEventType.messageDelta:
      return _rolePartialPartFromEvent(event);
    case AgentRunEventType.thinking:
      return _thinkingPartFromEvent(event);
    case AgentRunEventType.status:
      return _roleStatusPartFromEvent(event);
    case AgentRunEventType.result:
      return _roleResultPartFromEvent(event);
    case AgentRunEventType.error:
      return _roleErrorPartFromEvent(event);
    case AgentRunEventType.toolCall:
      return _toolCallPartFromEvent(event);
    case AgentRunEventType.userInput:
      return _readerTurnPartFromUserInputEvent(event);
    case AgentRunEventType.waitRequest:
      return _readerTurnPartFromWaitRequestEvent(event);
    case AgentRunEventType.resumeRequest:
      return _readerTurnPartFromResumeRequestEvent(event);
    case AgentRunEventType.retryRequest:
      return _readerTurnPartFromRetryRequestEvent(event);
    case AgentRunEventType.closeRequest:
      return _readerTurnPartFromCloseRequestEvent(event);
    case AgentRunEventType.cancelRequest:
      return _readerTurnPartFromCancelRequestEvent(event);
    case AgentRunEventType.artifactAction:
      return _artifactActionsPartFromEvent(event);
  }
}

AiSeminarRunCardMessagePart? _thinkingPartFromEvent(
  AgentRunEvent event,
) {
  final text = _trimmedOrNull(event.delta) ??
      _trimmedOrNull(event.result) ??
      _trimmedOrNull(event.query);
  if (text == null || text.isEmpty) return null;
  return AiSeminarRunCardMessagePart(
    type: 'thinking',
    id: _trimmedOrNull(event.eventId),
    agentRunId: _trimmedOrNull(event.runId),
    parentRunId: _trimmedOrNull(event.parentRunId),
    roleId: _trimmedOrNull(event.roleId),
    label: _trimmedOrNull(event.nickname),
    text: text,
    completedAt: event.createdAt.millisecondsSinceEpoch,
  );
}

AiSeminarRunCardMessagePart? _rolePartialPartFromEvent(
  AgentRunEvent event,
) {
  final roleId = event.roleId?.trim();
  final delta = event.delta?.trim();
  if (roleId == null || roleId.isEmpty || delta == null || delta.isEmpty) {
    return null;
  }
  return AiSeminarRunCardMessagePart(
    type: 'role_partial',
    id: _trimmedOrNull(event.eventId),
    agentRunId: _trimmedOrNull(event.runId),
    parentRunId: _trimmedOrNull(event.parentRunId),
    roleId: roleId,
    label: _trimmedOrNull(event.nickname),
    text: delta,
  );
}

AiSeminarRunCardMessagePart? _roleStatusPartFromEvent(
  AgentRunEvent event,
) {
  final roleId = event.roleId?.trim();
  final status = event.status;
  if (roleId == null || roleId.isEmpty || status == null) return null;
  if (_isDirectorRole(roleId) && status == SubAgentRunStatus.waitingInput) {
    return _directorWaitingInputPartFromEvent(event, roleId);
  }
  final displayName = _displayNameForEvent(event, roleId);
  return AiSeminarRunCardMessagePart(
    type: _isDirectorRole(roleId) ? 'director_state' : 'agent_status',
    id: _trimmedOrNull(event.eventId),
    agentRunId: _trimmedOrNull(event.runId),
    parentRunId: _trimmedOrNull(event.parentRunId),
    roleId: roleId,
    actionIds:
        _isDirectorRole(roleId) ? const [] : _roleStatusActionIds(status),
    allowedToolIds: _trimmedList(event.allowedToolIds),
    label: _isDirectorRole(roleId)
        ? _directorStatusLabel(status)
        : _roleStatusLabel(status),
    text: '$displayName ${_roleStatusText(status)}.',
  );
}

AiSeminarRunCardMessagePart _directorWaitingInputPartFromEvent(
  AgentRunEvent event,
  String roleId,
) {
  final prompt = _trimmedOrNull(event.delta) ??
      _trimmedOrNull(event.result) ??
      _trimmedOrNull(event.query);
  final roleIds = _trimmedList(event.roleIds);
  final defaultRoleId = roleIds.isEmpty ? null : roleIds.first;
  return AiSeminarRunCardMessagePart(
    type: 'reader_composer',
    id: _trimmedOrNull(event.eventId),
    agentRunId: _trimmedOrNull(event.runId),
    parentRunId: _trimmedOrNull(event.parentRunId),
    roleId: roleId,
    label: 'ask-user',
    text: prompt,
    actionIds: const [
      'ask-role',
      'refresh-evidence',
      'synthesize',
    ],
    defaultActionId: 'ask-role',
    selectedActionId: 'ask-role',
    roleIds: roleIds,
    defaultRoleId: defaultRoleId,
    selectedRoleId: defaultRoleId,
  );
}

AiSeminarRunCardMessagePart? _roleResultPartFromEvent(
  AgentRunEvent event,
) {
  final roleId = event.roleId?.trim();
  final result = event.result?.trim();
  if (roleId == null || roleId.isEmpty || result == null || result.isEmpty) {
    return null;
  }
  return AiSeminarRunCardMessagePart(
    type: _isDirectorRole(roleId) ? 'synthesis' : 'role_turn',
    id: _trimmedOrNull(event.eventId),
    agentRunId: _trimmedOrNull(event.runId),
    parentRunId: _trimmedOrNull(event.parentRunId),
    roleId: roleId,
    label: _trimmedOrNull(event.nickname),
    text: result,
    evidenceRefs: event.evidenceRefs
        .where((evidence) => !evidence.isEmpty)
        .toList(growable: false),
  );
}

AiSeminarRunCardMessagePart? _roleErrorPartFromEvent(
  AgentRunEvent event,
) {
  final roleId = event.roleId?.trim();
  final error = event.error?.trim();
  if (roleId == null || roleId.isEmpty || error == null || error.isEmpty) {
    return null;
  }
  final displayName = _displayNameForEvent(event, roleId);
  return AiSeminarRunCardMessagePart(
    type: _isDirectorRole(roleId) ? 'director_state' : 'agent_status',
    id: _trimmedOrNull(event.eventId),
    agentRunId: _trimmedOrNull(event.runId),
    parentRunId: _trimmedOrNull(event.parentRunId),
    roleId: roleId,
    actionIds: _isDirectorRole(roleId)
        ? const []
        : _roleStatusActionIds(SubAgentRunStatus.errored),
    allowedToolIds: _trimmedList(event.allowedToolIds),
    label: _isDirectorRole(roleId) ? 'failed' : 'role-error',
    text: '$displayName failed: $error',
  );
}

AiSeminarRunCardMessagePart? _toolCallPartFromEvent(
  AgentRunEvent event,
) {
  final toolId = event.toolId?.trim();
  if (toolId == null || toolId.isEmpty) return null;
  final query = event.query?.trim() ?? event.delta?.trim();
  return AiSeminarRunCardMessagePart(
    type: 'tool_call',
    id: _trimmedOrNull(event.eventId),
    agentRunId: _trimmedOrNull(event.runId),
    parentRunId: _trimmedOrNull(event.parentRunId),
    toolId: toolId,
    status: event.status?.asString,
    text: _trimmedOrNull(event.error) ?? _trimmedOrNull(event.result),
    query: query == null || query.isEmpty ? null : query,
    resultCount: event.resultCount,
    startedAt: _toolCallStartedAt(event),
    completedAt: _toolCallCompletedAt(event),
    roleIds: _trimmedList(event.roleIds),
    actionIds: _trimmedList(event.actionIds),
    evidenceRefs: event.evidenceRefs
        .where((evidence) => !evidence.isEmpty)
        .toList(growable: false),
  );
}

int? _toolCallStartedAt(AgentRunEvent event) {
  if (!_isActiveToolCallStatus(event.status)) return null;
  return event.createdAt.millisecondsSinceEpoch;
}

bool _isActiveToolCallStatus(SubAgentRunStatus? status) {
  return status == SubAgentRunStatus.running ||
      status == SubAgentRunStatus.pendingInit;
}

int? _toolCallCompletedAt(AgentRunEvent event) {
  return switch (event.status) {
    SubAgentRunStatus.completed ||
    SubAgentRunStatus.errored ||
    SubAgentRunStatus.interrupted ||
    SubAgentRunStatus.shutdown ||
    SubAgentRunStatus.notFound =>
      event.createdAt.millisecondsSinceEpoch,
    _ => null,
  };
}

AiSeminarRunCardMessagePart? _artifactActionsPartFromEvent(
  AgentRunEvent event,
) {
  final rawActionIds = _trimmedList(event.actionIds);
  final evidenceRefs = event.evidenceRefs
      .where((evidence) => !evidence.isEmpty)
      .toList(growable: false);
  final missingTraceableAssetEvidence =
      _assetArtifactActionsRequireTraceableEvidence(rawActionIds) &&
          !evidenceRefs
              .any((evidence) => evidence.sourceRef?.hasEvidence == true);
  final actionIds = missingTraceableAssetEvidence
      ? const ['send-to-review']
      : _artifactActionIdsWithAffordances(rawActionIds);
  if (actionIds.isEmpty) return null;
  final text = _trimmedOrNull(event.result) ??
      _trimmedOrNull(event.delta) ??
      _trimmedOrNull(event.query);
  return AiSeminarRunCardMessagePart(
    type: 'artifact_actions',
    id: _trimmedOrNull(event.eventId),
    agentRunId: _trimmedOrNull(event.runId),
    parentRunId: _trimmedOrNull(event.parentRunId),
    roleId: _trimmedOrNull(event.roleId),
    label: _trimmedOrNull(event.nickname),
    status: missingTraceableAssetEvidence
        ? SubAgentRunStatus.interrupted.asString
        : event.status?.asString,
    text: missingTraceableAssetEvidence
        ? 'Artifact action is missing traceable source evidence; send it to exception triage instead of saving it as a knowledge asset.'
        : text,
    completedAt: event.createdAt.millisecondsSinceEpoch,
    actionIds: actionIds,
    evidenceRefs: evidenceRefs,
  );
}

bool _assetArtifactActionsRequireTraceableEvidence(List<String> actionIds) {
  return actionIds.any((actionId) {
    switch (actionId.trim()) {
      case 'save-knowledge-card':
      case 'edit-knowledge-card':
      case 'knowledge-card-saved':
      case 'add-spaced-review':
      case 'spaced-review-added':
      case 'add-concept-graph':
      case 'concept-graph-added':
        return true;
      default:
        return false;
    }
  });
}

List<String> _artifactActionIdsWithAffordances(List<String> actionIds) {
  final result = <String>[];

  void add(String actionId) {
    final normalized = actionId.trim();
    if (normalized.isEmpty || result.contains(normalized)) return;
    result.add(normalized);
  }

  for (final actionId in actionIds) {
    add(actionId);
    switch (actionId.trim()) {
      case 'knowledge-card-saved':
        add('undo-knowledge-card');
        break;
      case 'spaced-review-added':
        add('undo-spaced-review');
        break;
      case 'concept-graph-added':
        add('undo-concept-graph');
        break;
      case 'artifact-actions-ignored':
        add('restore-artifact-actions');
        break;
    }
  }
  return result;
}

List<AiSeminarRunCardMessagePart> _evidencePartsFromToolCallEvents(
  Iterable<AgentRunEvent> events,
) {
  final evidenceByParentRunId =
      <String, Map<String, List<AiSeminarRunCardEvidenceSnapshot>>>{};
  final seenByParentRunId = <String, Map<String, Set<String>>>{};
  for (final event in events) {
    if (event.type != AgentRunEventType.toolCall) continue;
    final parentRunId =
        _trimmedOrNull(event.parentRunId) ?? _trimmedOrNull(event.runId);
    if (parentRunId == null) continue;
    final toolId = _trimmedOrNull(event.toolId) ?? '';
    for (final evidence in event.evidenceRefs) {
      if (evidence.isEmpty) continue;
      final key = _evidenceSnapshotKey(evidence);
      final seen = seenByParentRunId
          .putIfAbsent(parentRunId, () => <String, Set<String>>{})
          .putIfAbsent(toolId, () => <String>{});
      if (!seen.add(key)) continue;
      evidenceByParentRunId
          .putIfAbsent(
            parentRunId,
            () => <String, List<AiSeminarRunCardEvidenceSnapshot>>{},
          )
          .putIfAbsent(
            toolId,
            () => <AiSeminarRunCardEvidenceSnapshot>[],
          )
          .add(evidence);
    }
  }
  final out = <AiSeminarRunCardMessagePart>[];
  for (final parentEntry in evidenceByParentRunId.entries) {
    final groups = parentEntry.value.entries
        .where((entry) => entry.value.isNotEmpty)
        .toList(growable: false);
    final splitByTool = groups.length > 1;
    for (final group in groups) {
      final toolId = group.key.trim();
      final suffix = splitByTool
          ? 'tool-call-${_toolEvidenceIdSuffix(toolId)}'
          : 'tool-call';
      out.add(
        AiSeminarRunCardMessagePart(
          type: 'evidence',
          id: '${parentEntry.key}:evidence:$suffix',
          parentRunId: parentEntry.key,
          toolId: toolId.isEmpty ? null : toolId,
          label: 'Evidence snapshot',
          evidenceRefs: group.value,
        ),
      );
    }
  }
  return out.toList(growable: false);
}

String _toolEvidenceIdSuffix(String toolId) {
  final normalized = toolId.trim();
  if (normalized.isEmpty) return 'unknown';
  return normalized.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '-');
}

String _evidenceSnapshotKey(AiSeminarRunCardEvidenceSnapshot evidence) {
  final id = _trimmedOrNull(evidence.id);
  if (id != null) return 'id:$id';
  final sourceRef = evidence.sourceRef;
  return [
    evidence.title.trim(),
    evidence.snippet.trim(),
    sourceRef?.bookId.toString() ?? '',
    sourceRef?.cfi ?? '',
    sourceRef?.sourceKind.asString ?? '',
    sourceRef?.sourceTextSnippet ?? '',
  ].join('|');
}

AiSeminarRunCardMessagePart? _readerTurnPartFromUserInputEvent(
  AgentRunEvent event,
) {
  final roleId = event.roleId?.trim();
  final text = event.delta?.trim();
  if (roleId == null || roleId.isEmpty || text == null || text.isEmpty) {
    return null;
  }
  return AiSeminarRunCardMessagePart(
    type: 'reader_turn',
    id: _trimmedOrNull(event.eventId),
    agentRunId: _trimmedOrNull(event.runId),
    parentRunId: _trimmedOrNull(event.parentRunId),
    roleId: roleId,
    label: 'send-input',
    status: event.acknowledgedAt == null ? 'pending' : 'completed',
    text: text,
    completedAt: event.acknowledgedAt?.millisecondsSinceEpoch,
  );
}

AiSeminarRunCardMessagePart? _readerTurnPartFromWaitRequestEvent(
  AgentRunEvent event,
) {
  final roleId = event.roleId?.trim();
  if (roleId == null || roleId.isEmpty) return null;
  final toolId = _trimmedOrNull(event.toolId);
  final query = _trimmedOrNull(event.query);
  final isToolWait =
      toolId != null || _targetToolCallIdFromWaitEvent(event) != null;
  return AiSeminarRunCardMessagePart(
    type: 'reader_turn',
    id: _trimmedOrNull(event.eventId),
    agentRunId: _trimmedOrNull(event.runId),
    parentRunId: _trimmedOrNull(event.parentRunId),
    roleId: roleId,
    toolId: toolId,
    label: isToolWait ? 'wait-tool-call' : 'wait-agent',
    status: event.acknowledgedAt == null ? 'pending' : 'completed',
    text: _trimmedOrNull(event.delta) ??
        (isToolWait
            ? 'Waiting for tool call to finish.'
            : 'Waiting for role to finish.'),
    query: query,
    completedAt: event.acknowledgedAt?.millisecondsSinceEpoch,
  );
}

String? _targetToolCallIdFromWaitEvent(AgentRunEvent event) {
  final explicitTarget = _trimmedOrNull(event.result);
  if (explicitTarget != null) return explicitTarget;
  const marker = ':wait-tool-call:';
  final eventId = event.eventId.trim();
  final markerIndex = eventId.indexOf(marker);
  if (markerIndex < 0) return null;
  final suffix = eventId.substring(markerIndex + marker.length);
  final lastSeparator = suffix.lastIndexOf(':');
  final target =
      lastSeparator > 0 ? suffix.substring(0, lastSeparator) : suffix;
  return _trimmedOrNull(target);
}

AiSeminarRunCardMessagePart? _readerTurnPartFromResumeRequestEvent(
  AgentRunEvent event,
) {
  final roleId = event.roleId?.trim();
  if (roleId == null || roleId.isEmpty) return null;
  return AiSeminarRunCardMessagePart(
    type: 'reader_turn',
    id: _trimmedOrNull(event.eventId),
    agentRunId: _trimmedOrNull(event.runId),
    parentRunId: _trimmedOrNull(event.parentRunId),
    roleId: roleId,
    label: 'resume-agent',
    status: event.acknowledgedAt == null ? 'pending' : 'completed',
    text: _controlReaderTurnText(
      event.delta,
      internalDefault: 'Resume requested.',
    ),
    completedAt: event.acknowledgedAt?.millisecondsSinceEpoch,
  );
}

AiSeminarRunCardMessagePart? _readerTurnPartFromRetryRequestEvent(
  AgentRunEvent event,
) {
  final roleId = event.roleId?.trim();
  if (roleId == null || roleId.isEmpty) return null;
  return AiSeminarRunCardMessagePart(
    type: 'reader_turn',
    id: _trimmedOrNull(event.eventId),
    agentRunId: _trimmedOrNull(event.runId),
    parentRunId: _trimmedOrNull(event.parentRunId),
    roleId: roleId,
    label: 'retry-agent-control',
    status: event.acknowledgedAt == null ? 'pending' : 'completed',
    text: _controlReaderTurnText(
      event.delta,
      internalDefault: 'Retry requested.',
    ),
    completedAt: event.acknowledgedAt?.millisecondsSinceEpoch,
  );
}

String? _controlReaderTurnText(
  String? value, {
  required String internalDefault,
}) {
  final text = _trimmedOrNull(value);
  if (text == null || text == internalDefault) return null;
  return text;
}

AiSeminarRunCardMessagePart? _readerTurnPartFromCloseRequestEvent(
  AgentRunEvent event,
) {
  final roleId = event.roleId?.trim();
  if (roleId == null || roleId.isEmpty) return null;
  final completedAt = event.acknowledgedAt ?? event.createdAt;
  return AiSeminarRunCardMessagePart(
    type: 'reader_turn',
    id: _trimmedOrNull(event.eventId),
    agentRunId: _trimmedOrNull(event.runId),
    parentRunId: _trimmedOrNull(event.parentRunId),
    roleId: roleId,
    label: 'close-agent',
    status: 'completed',
    completedAt: completedAt.millisecondsSinceEpoch,
  );
}

AiSeminarRunCardMessagePart? _readerTurnPartFromCancelRequestEvent(
  AgentRunEvent event,
) {
  final roleId = event.roleId?.trim();
  if (roleId == null || roleId.isEmpty) return null;
  final completedAt = event.acknowledgedAt ?? event.createdAt;
  return AiSeminarRunCardMessagePart(
    type: 'reader_turn',
    id: _trimmedOrNull(event.eventId),
    agentRunId: _trimmedOrNull(event.runId),
    parentRunId: _trimmedOrNull(event.parentRunId),
    roleId: roleId,
    toolId: _trimmedOrNull(event.toolId),
    query: _trimmedOrNull(event.query),
    label: 'cancel-tool-call',
    status: 'completed',
    text: _controlReaderTurnText(
      event.delta,
      internalDefault: 'Cancel tool call requested.',
    ),
    completedAt: completedAt.millisecondsSinceEpoch,
  );
}

List<AiSeminarRunCardMessagePart> _normalizeTerminalReaderTurnParts(
  List<AiSeminarRunCardMessagePart> parts,
  List<AgentRunEvent> events,
) {
  final terminalByControlEventId = <String, AgentRunEvent>{};
  final latestTerminalByRun = <String, AgentRunEvent>{};
  final terminalToolCalls = <AgentRunEvent>[];
  for (final event in events) {
    if (_isTerminalToolCallEvent(event)) {
      terminalToolCalls.add(event);
    }
    if (_isControlTerminalEvent(event)) {
      final current = latestTerminalByRun[event.runId];
      if (current == null || _compareAgentRunEvents(current, event) < 0) {
        latestTerminalByRun[event.runId] = event;
      }
    }
  }
  for (final event in events) {
    if (!_isAcknowledgeableSeminarControlEvent(event) ||
        event.acknowledgedAt != null) {
      continue;
    }
    final terminal = event.type == AgentRunEventType.waitRequest
        ? _terminalToolCallForWaitRequest(
              event,
              terminalToolCalls,
            ) ??
            latestTerminalByRun[event.runId]
        : latestTerminalByRun[event.runId];
    if (terminal == null || _compareAgentRunEvents(event, terminal) >= 0) {
      continue;
    }
    terminalByControlEventId[event.eventId] = terminal;
  }
  if (terminalByControlEventId.isEmpty) return parts;
  return parts.map((part) {
    final eventId = part.id?.trim();
    if (part.type.trim() != 'reader_turn' ||
        eventId == null ||
        eventId.isEmpty ||
        part.status?.trim() != 'pending') {
      return part;
    }
    final terminal = terminalByControlEventId[eventId];
    if (terminal == null) return part;
    final label = part.label?.trim();
    if (label == 'wait-agent' || label == 'wait-tool-call') {
      return _copyReaderTurnWithStatus(
        part,
        status: 'completed',
        completedAt: terminal.createdAt.millisecondsSinceEpoch,
      );
    }
    if (label == 'send-input' ||
        label == 'resume-agent' ||
        label == 'retry-agent-control') {
      return _copyReaderTurnWithStatus(
        part,
        status: 'cancelled',
        completedAt: terminal.createdAt.millisecondsSinceEpoch,
      );
    }
    return part;
  }).toList(growable: false);
}

bool _isTerminalToolCallEvent(AgentRunEvent event) {
  return event.type == AgentRunEventType.toolCall &&
      _toolCallCompletedAt(event) != null;
}

AgentRunEvent? _terminalToolCallForWaitRequest(
  AgentRunEvent waitEvent,
  List<AgentRunEvent> terminalToolCalls,
) {
  final targetToolCallId = _targetToolCallIdFromWaitEvent(waitEvent);
  AgentRunEvent? best;
  for (final toolEvent in terminalToolCalls) {
    if (toolEvent.runId != waitEvent.runId ||
        toolEvent.parentRunId != waitEvent.parentRunId ||
        _compareAgentRunEvents(waitEvent, toolEvent) >= 0) {
      continue;
    }
    if (targetToolCallId != null) {
      if (toolEvent.eventId.trim() != targetToolCallId) continue;
    } else if (!_toolCallMatchesWaitRequest(toolEvent, waitEvent)) {
      continue;
    }
    if (best == null || _compareAgentRunEvents(best, toolEvent) < 0) {
      best = toolEvent;
    }
  }
  return best;
}

bool _toolCallMatchesWaitRequest(
  AgentRunEvent toolEvent,
  AgentRunEvent waitEvent,
) {
  final waitToolId = _trimmedOrNull(waitEvent.toolId);
  final toolId = _trimmedOrNull(toolEvent.toolId);
  if (waitToolId == null || toolId == null || waitToolId != toolId) {
    return false;
  }
  final waitQuery = _trimmedOrNull(waitEvent.query);
  final toolQuery = _trimmedOrNull(toolEvent.query);
  return waitQuery == null ||
      toolQuery == null ||
      waitQuery.isEmpty ||
      toolQuery.isEmpty ||
      waitQuery == toolQuery;
}

AiSeminarRunCardMessagePart _copyReaderTurnWithStatus(
  AiSeminarRunCardMessagePart part, {
  required String status,
  required int completedAt,
}) {
  return AiSeminarRunCardMessagePart(
    type: part.type,
    id: part.id,
    agentRunId: part.agentRunId,
    parentRunId: part.parentRunId,
    roleId: part.roleId,
    roleIds: part.roleIds,
    actionIds: part.actionIds,
    allowedToolIds: part.allowedToolIds,
    defaultRoleId: part.defaultRoleId,
    defaultActionId: part.defaultActionId,
    selectedRoleId: part.selectedRoleId,
    selectedActionId: part.selectedActionId,
    draftText: part.draftText,
    toolId: part.toolId,
    status: status,
    label: part.label,
    text: part.text,
    query: part.query,
    resultCount: part.resultCount,
    completedAt: part.completedAt ?? completedAt,
    evidenceRefs: part.evidenceRefs,
  );
}

List<AgentRunEvent> _mergeAgentRunEvents(
  Iterable<AgentRunEvent> parentEvents,
  Iterable<AgentRunEvent> childEvents,
  Iterable<AgentRunEvent> openChildStatusEvents,
) {
  return _dedupeAgentRunEventsById(
    parentEvents.followedBy(childEvents).followedBy(openChildStatusEvents),
  );
}

List<AgentRunEvent> _dedupeAgentRunEventsById(
  Iterable<AgentRunEvent> events,
) {
  final byId = <String, AgentRunEvent>{};
  for (final event in events) {
    final current = byId[event.eventId];
    if (current == null || _compareAgentRunEvents(current, event) <= 0) {
      byId[event.eventId] = event;
    }
  }
  return byId.values.toList(growable: false)..sort(_compareAgentRunEvents);
}

List<AgentRunEvent> _openChildStatusEvents(
  Iterable<AgentRunGraphEntry> entries,
) {
  return entries.map((entry) {
    final run = entry.run;
    return AgentRunEvent(
      eventId: '${run.runId}:status:${run.status.asString}',
      runId: run.runId,
      parentRunId: run.parentRunId,
      type: AgentRunEventType.status,
      createdAt: run.finishedAt ?? run.startedAt,
      status: run.status,
      roleId: run.roleId,
      nickname: run.nickname,
      allowedToolIds: run.allowedToolIds,
    );
  }).toList(growable: false);
}

int _compareAgentRunEvents(AgentRunEvent a, AgentRunEvent b) {
  final byCreatedAt = a.createdAt.compareTo(b.createdAt);
  if (byCreatedAt != 0) return byCreatedAt;
  final byType = _agentRunEventTypeOrder(a.type).compareTo(
    _agentRunEventTypeOrder(b.type),
  );
  if (byType != 0) return byType;
  return a.eventId.compareTo(b.eventId);
}

int _agentRunEventTypeOrder(AgentRunEventType type) {
  return switch (type) {
    AgentRunEventType.status => 0,
    AgentRunEventType.toolCall => 1,
    AgentRunEventType.thinking => 2,
    AgentRunEventType.messageDelta => 3,
    AgentRunEventType.userInput => 4,
    AgentRunEventType.waitRequest => 5,
    AgentRunEventType.resumeRequest => 6,
    AgentRunEventType.retryRequest => 7,
    AgentRunEventType.closeRequest => 8,
    AgentRunEventType.cancelRequest => 9,
    AgentRunEventType.result => 10,
    AgentRunEventType.artifactAction => 11,
    AgentRunEventType.error => 12,
  };
}

List<AgentRunEvent> _dropSupersededStatusEvents(
  Iterable<AgentRunEvent> events,
) {
  final allEvents = events.toList(growable: false);
  final latestStatusByRun = <String, AgentRunEvent>{};
  final latestTerminalByRun = <String, AgentRunEvent>{};
  final latestToolCallByKey = <String, AgentRunEvent>{};
  final latestAcknowledgedControlByRun = <String, AgentRunEvent>{};
  final runsWithStreamedThinking = <String>{};
  for (final event in allEvents) {
    switch (event.type) {
      case AgentRunEventType.status:
        final current = latestStatusByRun[event.runId];
        if (current == null || _compareAgentRunEvents(current, event) < 0) {
          latestStatusByRun[event.runId] = event;
        }
      case AgentRunEventType.result:
      case AgentRunEventType.error:
        final current = latestTerminalByRun[event.runId];
        if (current == null || _compareAgentRunEvents(current, event) < 0) {
          latestTerminalByRun[event.runId] = event;
        }
      case AgentRunEventType.toolCall:
        final key = _toolCallEventKey(event);
        final current = latestToolCallByKey[key];
        if (current == null || _compareAgentRunEvents(current, event) < 0) {
          latestToolCallByKey[key] = event;
        }
      case AgentRunEventType.thinking:
        if (_isStreamedRoleThinkingEvent(event)) {
          runsWithStreamedThinking.add(event.runId);
        }
      case AgentRunEventType.userInput:
      case AgentRunEventType.resumeRequest:
      case AgentRunEventType.retryRequest:
        if (event.acknowledgedAt != null) {
          final current = latestAcknowledgedControlByRun[event.runId];
          if (current == null || _compareAgentRunEvents(current, event) < 0) {
            latestAcknowledgedControlByRun[event.runId] = event;
          }
        }
      case AgentRunEventType.artifactAction:
      case AgentRunEventType.closeRequest:
      case AgentRunEventType.cancelRequest:
      case AgentRunEventType.messageDelta:
      case AgentRunEventType.waitRequest:
        break;
    }
  }
  final latestRestartAfterTerminalByRun = <String, AgentRunEvent>{};
  for (final event in allEvents) {
    if (event.type != AgentRunEventType.status ||
        !_isTransientStatus(event.status)) {
      continue;
    }
    final terminal = latestTerminalByRun[event.runId];
    if (terminal == null || _compareAgentRunEvents(event, terminal) <= 0) {
      continue;
    }
    final current = latestRestartAfterTerminalByRun[event.runId];
    if (current == null || _compareAgentRunEvents(current, event) < 0) {
      latestRestartAfterTerminalByRun[event.runId] = event;
    }
  }
  return allEvents.where((event) {
    final restartAfterTerminal = latestRestartAfterTerminalByRun[event.runId];
    final terminal =
        restartAfterTerminal == null ? latestTerminalByRun[event.runId] : null;
    if (_isTerminalRunEvent(event.type)) {
      if (latestTerminalByRun[event.runId]?.eventId != event.eventId) {
        return false;
      }
      return restartAfterTerminal == null;
    }
    if (restartAfterTerminal != null &&
        _isRestartScopedStreamEvent(event.type) &&
        _compareAgentRunEvents(event, restartAfterTerminal) < 0) {
      return false;
    }
    if (event.type == AgentRunEventType.messageDelta) {
      return terminal == null || _compareAgentRunEvents(event, terminal) >= 0;
    }
    if (event.type == AgentRunEventType.toolCall) {
      return latestToolCallByKey[_toolCallEventKey(event)]?.eventId ==
          event.eventId;
    }
    if (event.type == AgentRunEventType.thinking &&
        runsWithStreamedThinking.contains(event.runId) &&
        _isRoleStartThinkingEvent(event)) {
      return false;
    }
    if (_isPendingRuntimeControlEvent(event)) {
      final acknowledgedControl = latestAcknowledgedControlByRun[event.runId];
      if (acknowledgedControl != null &&
          _compareAgentRunEvents(event, acknowledgedControl) < 0) {
        return false;
      }
    }
    if (event.type != AgentRunEventType.status) return true;
    if (latestStatusByRun[event.runId]?.eventId != event.eventId) {
      return false;
    }
    if (restartAfterTerminal != null ||
        terminal == null ||
        _compareAgentRunEvents(event, terminal) >= 0) {
      return true;
    }
    return !_isTransientStatus(event.status);
  }).toList(growable: false);
}

bool _isTerminalRunEvent(AgentRunEventType type) {
  return type == AgentRunEventType.result || type == AgentRunEventType.error;
}

bool _isControlTerminalEvent(AgentRunEvent event) {
  if (_isTerminalRunEvent(event.type)) return true;
  return event.type == AgentRunEventType.status &&
      event.status != null &&
      !_isTransientStatus(event.status);
}

bool _isAcknowledgeableSeminarControlEvent(AgentRunEvent event) {
  return event.type == AgentRunEventType.userInput ||
      event.type == AgentRunEventType.waitRequest ||
      event.type == AgentRunEventType.resumeRequest ||
      event.type == AgentRunEventType.retryRequest ||
      event.type == AgentRunEventType.closeRequest ||
      event.type == AgentRunEventType.cancelRequest;
}

bool _isRestartScopedStreamEvent(AgentRunEventType type) {
  return type == AgentRunEventType.messageDelta ||
      type == AgentRunEventType.thinking ||
      type == AgentRunEventType.toolCall;
}

bool _isPendingRuntimeControlEvent(AgentRunEvent event) {
  if (event.acknowledgedAt != null) return false;
  return event.type == AgentRunEventType.userInput ||
      event.type == AgentRunEventType.resumeRequest ||
      event.type == AgentRunEventType.retryRequest;
}

bool _isRoleStartThinkingEvent(AgentRunEvent event) {
  return event.eventId.trim().endsWith(':thinking:start');
}

bool _isStreamedRoleThinkingEvent(AgentRunEvent event) {
  return event.eventId.trim().contains(':thinking:stream:');
}

String _toolCallEventKey(AgentRunEvent event) {
  final eventId = _trimmedOrNull(event.eventId);
  if (eventId != null) {
    return '${event.runId}\n${_toolCallLifecycleKeyFromEventId(eventId)}';
  }
  final toolId = _trimmedOrNull(event.toolId) ?? '';
  final query = _trimmedOrNull(event.query) ?? '';
  return '${event.runId}\n$toolId\n$query';
}

String _toolCallLifecycleKeyFromEventId(String eventId) {
  final lastColon = eventId.lastIndexOf(':');
  if (lastColon <= 0) return eventId;
  final suffix = eventId.substring(lastColon + 1);
  if (SubAgentRunStatus.values.any((status) => status.asString == suffix)) {
    return eventId.substring(0, lastColon);
  }
  return eventId;
}

bool _isTransientStatus(SubAgentRunStatus? status) {
  return status == SubAgentRunStatus.pendingInit ||
      status == SubAgentRunStatus.running ||
      status == SubAgentRunStatus.waitingInput ||
      status == SubAgentRunStatus.interrupted;
}

String _displayNameForEvent(AgentRunEvent event, String roleId) {
  return _trimmedOrNull(event.nickname) ?? roleId;
}

bool _isDirectorRole(String roleId) {
  return roleId.trim().toLowerCase() == 'director';
}

String _directorStatusLabel(SubAgentRunStatus status) {
  return switch (status) {
    SubAgentRunStatus.pendingInit => 'pending',
    SubAgentRunStatus.running => 'running',
    SubAgentRunStatus.completed => 'end',
    SubAgentRunStatus.interrupted => 'interrupted',
    SubAgentRunStatus.errored => 'failed',
    SubAgentRunStatus.shutdown => 'stopped',
    SubAgentRunStatus.notFound => 'not-found',
    _ => _roleStatusLabel(status),
  };
}

String _roleStatusLabel(SubAgentRunStatus status) {
  switch (status) {
    case SubAgentRunStatus.pendingInit:
      return 'role-pending';
    case SubAgentRunStatus.running:
      return 'role-running';
    case SubAgentRunStatus.waitingInput:
      return 'role-waiting-input';
    case SubAgentRunStatus.interrupted:
      return 'role-interrupted';
    case SubAgentRunStatus.completed:
      return 'role-completed';
    case SubAgentRunStatus.errored:
      return 'role-error';
    case SubAgentRunStatus.shutdown:
      return 'role-shutdown';
    case SubAgentRunStatus.notFound:
      return 'role-not-found';
  }
}

String _roleStatusText(SubAgentRunStatus status) {
  switch (status) {
    case SubAgentRunStatus.pendingInit:
      return 'is queued';
    case SubAgentRunStatus.running:
      return 'is running';
    case SubAgentRunStatus.waitingInput:
      return 'is waiting for input';
    case SubAgentRunStatus.interrupted:
      return 'was interrupted';
    case SubAgentRunStatus.completed:
      return 'completed';
    case SubAgentRunStatus.errored:
      return 'failed';
    case SubAgentRunStatus.shutdown:
      return 'was shut down';
    case SubAgentRunStatus.notFound:
      return 'was not found';
  }
}

List<String> _roleStatusActionIds(SubAgentRunStatus status) {
  switch (status) {
    case SubAgentRunStatus.pendingInit:
    case SubAgentRunStatus.running:
      return const ['wait-agent', 'close-agent'];
    case SubAgentRunStatus.waitingInput:
      return const ['send-input', 'close-agent'];
    case SubAgentRunStatus.interrupted:
      return const ['resume-agent', 'close-agent'];
    case SubAgentRunStatus.errored:
      return const ['retry-agent-control'];
    case SubAgentRunStatus.completed:
    case SubAgentRunStatus.shutdown:
    case SubAgentRunStatus.notFound:
      return const <String>[];
  }
}

String? _trimmedOrNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

List<String> _trimmedList(Iterable<String> values) {
  return values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}
