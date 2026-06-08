import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:papertok_reader/models/ai_agent_governance.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/service/ai/sub_agent_runner.dart';
import 'package:papertok_reader/service/memory/markdown_memory_store.dart';
import 'package:path/path.dart' as p;

enum AgentRunEdgeStatus {
  open('open'),
  closed('closed');

  const AgentRunEdgeStatus(this.asString);

  final String asString;

  static AgentRunEdgeStatus fromString(String? value) {
    for (final status in AgentRunEdgeStatus.values) {
      if (status.asString == value) return status;
    }
    return AgentRunEdgeStatus.open;
  }
}

enum AgentRunEventType {
  status('status'),
  thinking('thinking'),
  messageDelta('message_delta'),
  toolCall('tool_call'),
  userInput('user_input'),
  waitRequest('wait_request'),
  resumeRequest('resume_request'),
  retryRequest('retry_request'),
  closeRequest('close_request'),
  cancelRequest('cancel_request'),
  artifactAction('artifact_action'),
  result('result'),
  error('error');

  const AgentRunEventType(this.asString);

  final String asString;

  static AgentRunEventType fromString(String? value) {
    for (final type in AgentRunEventType.values) {
      if (type.asString == value) return type;
    }
    return AgentRunEventType.status;
  }
}

@immutable
class AgentRunRecord {
  const AgentRunRecord({
    required this.runId,
    required this.source,
    required this.profile,
    required this.roleId,
    required this.nickname,
    required this.status,
    required this.task,
    required this.startedAt,
    this.parentRunId,
    this.maxSteps,
    this.agentScene,
    this.allowedToolIds = const <String>[],
    this.finishedAt,
    this.result,
    this.evidenceRefs = const <AiSeminarRunCardEvidenceSnapshot>[],
    this.error,
  });

  factory AgentRunRecord.fromJson(Map<String, dynamic> json) {
    return AgentRunRecord(
      runId: _stringField(json, 'runId'),
      parentRunId: _optionalStringField(json, 'parentRunId'),
      source: _stringField(json, 'source'),
      profile: _stringField(json, 'profile'),
      roleId: _stringField(json, 'roleId'),
      nickname: _stringField(json, 'nickname'),
      status: _subAgentStatusFromString(json['status']?.toString()),
      task: _stringField(json, 'task'),
      maxSteps: json['maxSteps'] is int ? json['maxSteps'] as int : null,
      agentScene: AiAgentScene.tryParse(json['agentScene']?.toString()),
      allowedToolIds: _stringListField(json['allowedToolIds']),
      startedAt: _dateTimeField(json, 'startedAt'),
      finishedAt: _optionalDateTimeField(json, 'finishedAt'),
      result: _optionalStringField(json, 'result'),
      evidenceRefs: _evidenceRefsField(json['evidenceRefs']),
      error: _optionalStringField(json, 'error'),
    );
  }

  factory AgentRunRecord.fromSubAgentResult(
    SubAgentRunResult result, {
    required String source,
    required String profile,
    required String roleId,
    required String nickname,
  }) {
    return AgentRunRecord(
      runId: result.agentRunId,
      parentRunId: result.parentRunId,
      source: source,
      profile: profile,
      roleId: roleId,
      nickname: nickname,
      status: result.status,
      task: result.task,
      maxSteps: result.maxSteps,
      agentScene: result.agentScene,
      allowedToolIds: result.allowedToolIds,
      startedAt: result.startedAt,
      finishedAt: result.finishedAt,
      result: result.result,
      error: result.error,
    );
  }

  factory AgentRunRecord.fromSeminarRoleTurn({
    required AiSeminarSessionContract session,
    required AiSeminarRoleTurn turn,
    String? runId,
    List<AiSeminarRunCardEvidenceSnapshot> evidenceRefs =
        const <AiSeminarRunCardEvidenceSnapshot>[],
  }) {
    return AgentRunRecord(
      runId: runId ?? '${session.id}:${turn.id}',
      parentRunId: session.id,
      source: 'seminar',
      profile: turn.role.asString,
      roleId: turn.role.asString,
      nickname: seminarRoleNickname(turn.role),
      status: turn.isFailed
          ? SubAgentRunStatus.errored
          : SubAgentRunStatus.completed,
      task: session.question,
      agentScene: AiAgentScene.seminar,
      allowedToolIds:
          session.roleProfileFor(turn.role)?.allowedToolIds ?? const <String>[],
      startedAt: _dateTimeFromMillis(turn.startedAt ?? session.createdAt),
      finishedAt: turn.completedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(turn.completedAt!),
      result: turn.responseText,
      evidenceRefs: evidenceRefs,
      error: turn.error,
    );
  }

  factory AgentRunRecord.fromSeminarRoleStart({
    required AiSeminarSessionContract session,
    required AiSeminarRole role,
    required String runId,
    required DateTime startedAt,
  }) {
    return AgentRunRecord(
      runId: runId,
      parentRunId: session.id,
      source: 'seminar',
      profile: role.asString,
      roleId: role.asString,
      nickname: seminarRoleNickname(role),
      status: SubAgentRunStatus.running,
      task: session.question,
      agentScene: AiAgentScene.seminar,
      allowedToolIds:
          session.roleProfileFor(role)?.allowedToolIds ?? const <String>[],
      startedAt: startedAt,
    );
  }

  factory AgentRunRecord.fromSeminarSessionStart({
    required AiSeminarSessionContract session,
    required DateTime startedAt,
  }) {
    return AgentRunRecord(
      runId: session.id,
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: SubAgentRunStatus.running,
      task: session.question,
      maxSteps: session.maxRounds,
      agentScene: AiAgentScene.seminar,
      allowedToolIds: _seminarSessionAllowedToolIds(session),
      startedAt: startedAt,
    );
  }

  factory AgentRunRecord.fromSeminarRun(AiSeminarRun run) {
    return AgentRunRecord(
      runId: run.session.id,
      source: 'seminar',
      profile: 'director',
      roleId: 'director',
      nickname: 'Director',
      status: _subAgentStatusForSeminarStatus(run.status),
      task: run.session.question,
      maxSteps: run.session.maxRounds,
      agentScene: AiAgentScene.seminar,
      allowedToolIds: _seminarSessionAllowedToolIds(run.session),
      startedAt: _dateTimeFromMillis(run.startedAt),
      finishedAt: run.completedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(run.completedAt!),
      result: run.synthesis?.summary,
      evidenceRefs: _seminarSynthesisEvidenceSnapshots(run.synthesis),
      error: run.status == AiSeminarRunStatus.failed ? run.message : null,
    );
  }

  final String runId;
  final String? parentRunId;
  final String source;
  final String profile;
  final String roleId;
  final String nickname;
  final SubAgentRunStatus status;
  final String task;
  final int? maxSteps;
  final AiAgentScene? agentScene;
  final List<String> allowedToolIds;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String? result;
  final List<AiSeminarRunCardEvidenceSnapshot> evidenceRefs;
  final String? error;

  AgentRunRecord copyWith({
    String? runId,
    String? parentRunId,
    String? source,
    String? profile,
    String? roleId,
    String? nickname,
    SubAgentRunStatus? status,
    String? task,
    int? maxSteps,
    AiAgentScene? agentScene,
    List<String>? allowedToolIds,
    DateTime? startedAt,
    DateTime? finishedAt,
    String? result,
    List<AiSeminarRunCardEvidenceSnapshot>? evidenceRefs,
    String? error,
  }) {
    return AgentRunRecord(
      runId: runId ?? this.runId,
      parentRunId: parentRunId ?? this.parentRunId,
      source: source ?? this.source,
      profile: profile ?? this.profile,
      roleId: roleId ?? this.roleId,
      nickname: nickname ?? this.nickname,
      status: status ?? this.status,
      task: task ?? this.task,
      maxSteps: maxSteps ?? this.maxSteps,
      agentScene: agentScene ?? this.agentScene,
      allowedToolIds: allowedToolIds ?? this.allowedToolIds,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      result: result ?? this.result,
      evidenceRefs: evidenceRefs ?? this.evidenceRefs,
      error: error ?? this.error,
    );
  }

  Map<String, dynamic> toJson() => {
        'runId': runId,
        if (parentRunId != null) 'parentRunId': parentRunId,
        'source': source,
        'profile': profile,
        'roleId': roleId,
        'nickname': nickname,
        'status': status.asString,
        'task': task,
        if (maxSteps != null) 'maxSteps': maxSteps,
        if (agentScene != null) 'agentScene': agentScene!.asString,
        'allowedToolIds': allowedToolIds,
        'startedAt': startedAt.toIso8601String(),
        if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
        if (result != null) 'result': result,
        if (evidenceRefs.where((item) => !item.isEmpty).isNotEmpty)
          'evidenceRefs': evidenceRefs
              .where((item) => !item.isEmpty)
              .map((item) => item.toJson())
              .toList(growable: false),
        if (error != null) 'error': error,
      };
}

@immutable
class AgentRunEvent {
  const AgentRunEvent({
    required this.eventId,
    required this.runId,
    required this.type,
    required this.createdAt,
    this.parentRunId,
    this.status,
    this.roleId,
    this.nickname,
    this.toolId,
    this.query,
    this.resultCount = 0,
    this.roleIds = const <String>[],
    this.actionIds = const <String>[],
    this.allowedToolIds = const <String>[],
    this.evidenceRefs = const <AiSeminarRunCardEvidenceSnapshot>[],
    this.delta,
    this.result,
    this.error,
    this.acknowledgedAt,
  });

  factory AgentRunEvent.fromJson(Map<String, dynamic> json) {
    return AgentRunEvent(
      eventId: _stringField(json, 'eventId'),
      runId: _stringField(json, 'runId'),
      parentRunId: _optionalStringField(json, 'parentRunId'),
      type: AgentRunEventType.fromString(json['type']?.toString()),
      createdAt: _dateTimeField(json, 'createdAt'),
      status: _optionalSubAgentStatusFromString(json['status']?.toString()),
      roleId: _optionalStringField(json, 'roleId'),
      nickname: _optionalStringField(json, 'nickname'),
      toolId: _optionalStringField(json, 'toolId'),
      query: _optionalStringField(json, 'query'),
      resultCount: _nonNegativeInt(json['resultCount']),
      roleIds: _stringListField(json['roleIds']),
      actionIds: _stringListField(json['actionIds']),
      allowedToolIds: _stringListField(json['allowedToolIds']),
      evidenceRefs: _evidenceRefsField(json['evidenceRefs']),
      delta: _optionalStringField(json, 'delta'),
      result: _optionalStringField(json, 'result'),
      error: _optionalStringField(json, 'error'),
      acknowledgedAt: _optionalDateTimeField(json, 'acknowledgedAt'),
    );
  }

  final String eventId;
  final String runId;
  final String? parentRunId;
  final AgentRunEventType type;
  final DateTime createdAt;
  final SubAgentRunStatus? status;
  final String? roleId;
  final String? nickname;
  final String? toolId;
  final String? query;
  final int resultCount;
  final List<String> roleIds;
  final List<String> actionIds;
  final List<String> allowedToolIds;
  final List<AiSeminarRunCardEvidenceSnapshot> evidenceRefs;
  final String? delta;
  final String? result;
  final String? error;
  final DateTime? acknowledgedAt;

  AgentRunEvent copyWith({
    DateTime? acknowledgedAt,
  }) {
    return AgentRunEvent(
      eventId: eventId,
      runId: runId,
      parentRunId: parentRunId,
      type: type,
      createdAt: createdAt,
      status: status,
      roleId: roleId,
      nickname: nickname,
      toolId: toolId,
      query: query,
      resultCount: resultCount,
      roleIds: roleIds,
      actionIds: actionIds,
      allowedToolIds: allowedToolIds,
      evidenceRefs: evidenceRefs,
      delta: delta,
      result: result,
      error: error,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'runId': runId,
        if (parentRunId != null) 'parentRunId': parentRunId,
        'type': type.asString,
        'createdAt': createdAt.toIso8601String(),
        if (status != null) 'status': status!.asString,
        if (roleId != null) 'roleId': roleId,
        if (nickname != null) 'nickname': nickname,
        if (toolId != null) 'toolId': toolId,
        if (query != null) 'query': query,
        if (resultCount > 0) 'resultCount': resultCount,
        if (roleIds.where((item) => item.trim().isNotEmpty).isNotEmpty)
          'roleIds': roleIds
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false),
        if (actionIds.where((item) => item.trim().isNotEmpty).isNotEmpty)
          'actionIds': actionIds
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false),
        if (allowedToolIds.where((item) => item.trim().isNotEmpty).isNotEmpty)
          'allowedToolIds': allowedToolIds
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false),
        if (evidenceRefs.where((item) => !item.isEmpty).isNotEmpty)
          'evidenceRefs': evidenceRefs
              .where((item) => !item.isEmpty)
              .map((item) => item.toJson())
              .toList(growable: false),
        if (delta != null) 'delta': delta,
        if (result != null) 'result': result,
        if (error != null) 'error': error,
        if (acknowledgedAt != null)
          'acknowledgedAt': acknowledgedAt!.toIso8601String(),
      };
}

@immutable
class AgentRunEdge {
  const AgentRunEdge({
    required this.parentRunId,
    required this.childRunId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AgentRunEdge.fromJson(Map<String, dynamic> json) {
    return AgentRunEdge(
      parentRunId: _stringField(json, 'parentRunId'),
      childRunId: _stringField(json, 'childRunId'),
      status: AgentRunEdgeStatus.fromString(json['status']?.toString()),
      createdAt: _dateTimeField(json, 'createdAt'),
      updatedAt: _dateTimeField(json, 'updatedAt'),
    );
  }

  final String parentRunId;
  final String childRunId;
  final AgentRunEdgeStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  AgentRunEdge copyWith({
    AgentRunEdgeStatus? status,
    DateTime? updatedAt,
  }) {
    return AgentRunEdge(
      parentRunId: parentRunId,
      childRunId: childRunId,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'parentRunId': parentRunId,
        'childRunId': childRunId,
        'status': status.asString,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}

@immutable
class AgentRunGraphEntry {
  const AgentRunGraphEntry({
    required this.run,
    required this.edge,
  });

  final AgentRunRecord run;
  final AgentRunEdge edge;
}

class AgentRunGraphStore {
  AgentRunGraphStore({Directory? rootDir})
      : rootDir = rootDir ?? MarkdownMemoryStore().rootDir;

  static const _schemaVersion = 1;
  static const _encoder = JsonEncoder.withIndent('  ');

  final Directory rootDir;
  Future<void> _tail = Future<void>.value();

  Directory get workflowDir => Directory(p.join(rootDir.path, '.workflow'));
  File get graphFile => File(p.join(workflowDir.path, 'agent_runs_v1.json'));

  Future<void> ensureInitialized() async {
    if (!await workflowDir.exists()) {
      await workflowDir.create(recursive: true);
    }
    if (!await graphFile.exists()) {
      await graphFile.writeAsString(_encode(_AgentRunGraphData.empty()));
    }
  }

  Future<AgentRunRecord> upsertRun(AgentRunRecord run) {
    return _enqueue(() async {
      final data = await _readUnlocked();
      data.upsertRun(run);
      if (run.parentRunId != null) {
        data.upsertEdge(_edgeFor(
          parentRunId: run.parentRunId!,
          childRunId: run.runId,
          now: run.startedAt,
          status: _edgeStatusForRunStatus(run.status),
        ));
      }
      for (final event in _eventsForRunSnapshot(run)) {
        data.upsertEvent(event);
      }
      await _writeUnlocked(data);
      return run;
    });
  }

  Future<AgentRunRecord> upsertFromSubAgentResult(
    SubAgentRunResult result, {
    required String source,
    required String profile,
    required String roleId,
    required String nickname,
  }) {
    return upsertRun(AgentRunRecord.fromSubAgentResult(
      result,
      source: source,
      profile: profile,
      roleId: roleId,
      nickname: nickname,
    ));
  }

  Future<AgentRunRecord> upsertFromSeminarRoleTurn({
    required AiSeminarSessionContract session,
    required AiSeminarRoleTurn turn,
    String? runId,
    List<AiSeminarRunCardEvidenceSnapshot> evidenceRefs =
        const <AiSeminarRunCardEvidenceSnapshot>[],
  }) {
    return upsertRun(AgentRunRecord.fromSeminarRoleTurn(
      session: session,
      turn: turn,
      runId: runId,
      evidenceRefs: evidenceRefs,
    ));
  }

  Future<AgentRunRecord> upsertFromSeminarRoleStart({
    required AiSeminarSessionContract session,
    required AiSeminarRole role,
    required String runId,
    required DateTime startedAt,
  }) {
    return upsertRun(AgentRunRecord.fromSeminarRoleStart(
      session: session,
      role: role,
      runId: runId,
      startedAt: startedAt,
    ));
  }

  Future<AgentRunRecord> upsertFromSeminarSessionStart({
    required AiSeminarSessionContract session,
    required DateTime startedAt,
  }) {
    return upsertRun(AgentRunRecord.fromSeminarSessionStart(
      session: session,
      startedAt: startedAt,
    ));
  }

  Future<AgentRunRecord> upsertFromSeminarRun(AiSeminarRun run) {
    return upsertRun(AgentRunRecord.fromSeminarRun(run));
  }

  Future<AgentRunRecord?> getRun(String runId) {
    return _enqueue(() async {
      final data = await _readUnlocked();
      return data.runById(runId);
    });
  }

  Future<List<AgentRunGraphEntry>> listChildren(String parentRunId) {
    return _enqueue(() async {
      final data = await _readUnlocked();
      return data.childrenOf(parentRunId);
    });
  }

  Future<List<AgentRunGraphEntry>> listOpenChildren(String parentRunId) {
    return _enqueue(() async {
      final data = await _readUnlocked();
      return data.openChildrenOf(parentRunId);
    });
  }

  Future<List<AgentRunGraphEntry>> listDescendants(String parentRunId) {
    return _enqueue(() async {
      final data = await _readUnlocked();
      return data.descendantsOf(parentRunId);
    });
  }

  Future<AgentRunRecord> closeChildRun({
    required String parentRunId,
    required String childRunId,
    DateTime? now,
  }) {
    return _enqueue(() async {
      final data = await _readUnlocked();
      final run = data.runById(childRunId);
      if (run == null) {
        throw StateError('Agent run not found: $childRunId');
      }
      if (run.parentRunId != parentRunId) {
        throw StateError(
            'Agent run is not a child of $parentRunId: $childRunId');
      }
      final requestedClosedAt = now ?? DateTime.now();
      final closedAt = requestedClosedAt.isAfter(run.startedAt)
          ? requestedClosedAt
          : run.startedAt.add(const Duration(microseconds: 1));
      final closedRun = run.copyWith(
        status: SubAgentRunStatus.shutdown,
        finishedAt: closedAt,
      );
      data.upsertRun(closedRun);
      data.setEdgeStatus(
        parentRunId: parentRunId,
        childRunId: childRunId,
        status: AgentRunEdgeStatus.closed,
        now: closedAt,
      );
      for (final event in _eventsForRunSnapshot(closedRun)) {
        data.upsertEvent(event);
      }
      await _writeUnlocked(data);
      return closedRun;
    });
  }

  Future<AgentRunEvent> upsertEvent(AgentRunEvent event) {
    return _enqueue(() async {
      final data = await _readUnlocked();
      data.upsertEvent(event);
      await _writeUnlocked(data);
      return event;
    });
  }

  Future<List<AgentRunEvent>> listEvents(String runId) {
    return _enqueue(() async {
      final data = await _readUnlocked();
      return data.eventsOf(runId);
    });
  }

  Future<List<AgentRunEvent>> listChildEvents(String parentRunId) {
    return _enqueue(() async {
      final data = await _readUnlocked();
      return data.childEventsOf(parentRunId);
    });
  }

  Future<List<AgentRunEvent>> listPendingControlEvents({
    required String parentRunId,
    required String childRunId,
  }) {
    return _enqueue(() async {
      final data = await _readUnlocked();
      return data.pendingControlEvents(
        parentRunId: parentRunId,
        childRunId: childRunId,
      );
    });
  }

  Future<AgentRunEvent> acknowledgeControlEvent({
    required String parentRunId,
    required String childRunId,
    required String eventId,
    DateTime? now,
  }) {
    return _enqueue(() async {
      final data = await _readUnlocked();
      final acknowledged = data.acknowledgeControlEvent(
        parentRunId: parentRunId,
        childRunId: childRunId,
        eventId: eventId,
        now: now ?? DateTime.now(),
      );
      await _writeUnlocked(data);
      return acknowledged;
    });
  }

  Future<void> setEdgeStatus({
    required String parentRunId,
    required String childRunId,
    required AgentRunEdgeStatus status,
    DateTime? now,
  }) {
    return _enqueue(() async {
      final data = await _readUnlocked();
      data.setEdgeStatus(
        parentRunId: parentRunId,
        childRunId: childRunId,
        status: status,
        now: now ?? DateTime.now(),
      );
      await _writeUnlocked(data);
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  Future<_AgentRunGraphData> _readUnlocked() async {
    await ensureInitialized();
    final raw = await graphFile.readAsString();
    if (raw.trim().isEmpty) return _AgentRunGraphData.empty();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return _AgentRunGraphData.empty();
    return _AgentRunGraphData.fromJson(decoded);
  }

  Future<void> _writeUnlocked(_AgentRunGraphData data) async {
    await ensureInitialized();
    await graphFile.writeAsString(_encode(data));
  }

  static AgentRunEdge _edgeFor({
    required String parentRunId,
    required String childRunId,
    required DateTime now,
    required AgentRunEdgeStatus status,
  }) {
    return AgentRunEdge(
      parentRunId: parentRunId,
      childRunId: childRunId,
      status: status,
      createdAt: now,
      updatedAt: now,
    );
  }

  static AgentRunEdgeStatus _edgeStatusForRunStatus(
    SubAgentRunStatus status,
  ) {
    return switch (status) {
      SubAgentRunStatus.completed ||
      SubAgentRunStatus.errored ||
      SubAgentRunStatus.shutdown ||
      SubAgentRunStatus.notFound =>
        AgentRunEdgeStatus.closed,
      SubAgentRunStatus.pendingInit ||
      SubAgentRunStatus.running ||
      SubAgentRunStatus.waitingInput ||
      SubAgentRunStatus.interrupted =>
        AgentRunEdgeStatus.open,
    };
  }

  static List<AgentRunEvent> _eventsForRunSnapshot(AgentRunRecord run) {
    final eventAt = run.finishedAt ?? run.startedAt;
    return [
      AgentRunEvent(
        eventId: '${run.runId}:status:${run.status.asString}',
        runId: run.runId,
        parentRunId: run.parentRunId,
        type: AgentRunEventType.status,
        createdAt: eventAt,
        status: run.status,
        roleId: run.roleId,
        nickname: run.nickname,
        allowedToolIds: run.allowedToolIds,
      ),
      if (run.result != null)
        AgentRunEvent(
          eventId: '${run.runId}:result',
          runId: run.runId,
          parentRunId: run.parentRunId,
          type: AgentRunEventType.result,
          createdAt: eventAt,
          roleId: run.roleId,
          nickname: run.nickname,
          result: run.result,
          evidenceRefs: run.evidenceRefs
              .where((item) => !item.isEmpty)
              .toList(growable: false),
        ),
      if (run.error != null)
        AgentRunEvent(
          eventId: '${run.runId}:error',
          runId: run.runId,
          parentRunId: run.parentRunId,
          type: AgentRunEventType.error,
          createdAt: eventAt,
          roleId: run.roleId,
          nickname: run.nickname,
          error: run.error,
        ),
    ];
  }

  static String _encode(_AgentRunGraphData data) => _encoder.convert({
        'schemaVersion': _schemaVersion,
        'runs': data.runs.map((run) => run.toJson()).toList(growable: false),
        'edges':
            data.edges.map((edge) => edge.toJson()).toList(growable: false),
        'events':
            data.events.map((event) => event.toJson()).toList(growable: false),
      });
}

class _AgentRunGraphData {
  _AgentRunGraphData({
    required this.runs,
    required this.edges,
    required this.events,
  });

  factory _AgentRunGraphData.empty() => _AgentRunGraphData(
        runs: <AgentRunRecord>[],
        edges: <AgentRunEdge>[],
        events: <AgentRunEvent>[],
      );

  factory _AgentRunGraphData.fromJson(Map<String, dynamic> json) {
    final runs = json['runs'] is List
        ? (json['runs'] as List)
            .whereType<Map<String, dynamic>>()
            .map(AgentRunRecord.fromJson)
            .toList()
        : <AgentRunRecord>[];
    final edges = json['edges'] is List
        ? (json['edges'] as List)
            .whereType<Map<String, dynamic>>()
            .map(AgentRunEdge.fromJson)
            .toList()
        : <AgentRunEdge>[];
    final events = json['events'] is List
        ? (json['events'] as List)
            .whereType<Map<String, dynamic>>()
            .map(AgentRunEvent.fromJson)
            .toList()
        : <AgentRunEvent>[];
    return _AgentRunGraphData(runs: runs, edges: edges, events: events);
  }

  final List<AgentRunRecord> runs;
  final List<AgentRunEdge> edges;
  final List<AgentRunEvent> events;

  void upsertRun(AgentRunRecord run) {
    final index = runs.indexWhere((item) => item.runId == run.runId);
    if (index >= 0) {
      runs[index] = run;
    } else {
      runs.add(run);
    }
  }

  void upsertEdge(AgentRunEdge edge) {
    final index = edges.indexWhere((item) =>
        item.parentRunId == edge.parentRunId &&
        item.childRunId == edge.childRunId);
    if (index >= 0) {
      final current = edges[index];
      final shouldUseIncomingStatus =
          edge.updatedAt.isAfter(current.updatedAt) ||
              edge.updatedAt.isAtSameMomentAs(current.updatedAt);
      edges[index] = AgentRunEdge(
        parentRunId: current.parentRunId,
        childRunId: current.childRunId,
        status: shouldUseIncomingStatus ? edge.status : current.status,
        createdAt: current.createdAt,
        updatedAt: edge.updatedAt,
      );
    } else {
      edges.add(edge);
    }
  }

  void upsertEvent(AgentRunEvent event) {
    final index = events.indexWhere((item) => item.eventId == event.eventId);
    if (index >= 0) {
      events[index] = event;
    } else {
      events.add(event);
    }
  }

  void setEdgeStatus({
    required String parentRunId,
    required String childRunId,
    required AgentRunEdgeStatus status,
    required DateTime now,
  }) {
    final index = edges.indexWhere((item) =>
        item.parentRunId == parentRunId && item.childRunId == childRunId);
    if (index < 0) {
      throw StateError('Agent run edge not found: $parentRunId -> $childRunId');
    }
    edges[index] = edges[index].copyWith(status: status, updatedAt: now);
  }

  List<AgentRunGraphEntry> childrenOf(String parentRunId) {
    final childEdges = edges
        .where((edge) => edge.parentRunId == parentRunId)
        .toList()
      ..sort(_compareEdges);
    return childEdges
        .map((edge) {
          final run = _runById(edge.childRunId);
          return run == null ? null : AgentRunGraphEntry(run: run, edge: edge);
        })
        .whereType<AgentRunGraphEntry>()
        .toList(growable: false);
  }

  List<AgentRunGraphEntry> openChildrenOf(String parentRunId) {
    return childrenOf(parentRunId)
        .where((entry) => entry.edge.status == AgentRunEdgeStatus.open)
        .toList(growable: false);
  }

  List<AgentRunGraphEntry> descendantsOf(String parentRunId) {
    final out = <AgentRunGraphEntry>[];
    final queue = <String>[parentRunId];
    final seen = <String>{parentRunId};
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      for (final child in childrenOf(current)) {
        if (!seen.add(child.run.runId)) continue;
        out.add(child);
        queue.add(child.run.runId);
      }
    }
    return out;
  }

  List<AgentRunEvent> eventsOf(String runId) {
    return events.where((event) => event.runId == runId).toList()
      ..sort(_compareEvents);
  }

  List<AgentRunEvent> childEventsOf(String parentRunId) {
    return events.where((event) => event.parentRunId == parentRunId).toList()
      ..sort(_compareEvents);
  }

  List<AgentRunEvent> pendingControlEvents({
    required String parentRunId,
    required String childRunId,
  }) {
    return events
        .where((event) =>
            event.parentRunId == parentRunId &&
            event.runId == childRunId &&
            _isPendingControlEventType(event.type) &&
            event.acknowledgedAt == null)
        .toList(growable: false)
      ..sort(_compareEvents);
  }

  AgentRunEvent acknowledgeControlEvent({
    required String parentRunId,
    required String childRunId,
    required String eventId,
    required DateTime now,
  }) {
    final index = events.indexWhere((event) => event.eventId == eventId);
    if (index < 0) {
      throw StateError('Agent run control event not found: $eventId');
    }
    final event = events[index];
    if (event.parentRunId != parentRunId || event.runId != childRunId) {
      throw StateError(
        'Agent run control event is not scoped to '
        '$parentRunId -> $childRunId: $eventId',
      );
    }
    if (!_isAcknowledgeableControlEventType(event.type)) {
      throw StateError('Agent run event is not a control event: $eventId');
    }
    final acknowledged = event.acknowledgedAt == null
        ? event.copyWith(acknowledgedAt: now)
        : event;
    events[index] = acknowledged;
    return acknowledged;
  }

  AgentRunRecord? _runById(String runId) {
    return runById(runId);
  }

  AgentRunRecord? runById(String runId) {
    for (final run in runs) {
      if (run.runId == runId) return run;
    }
    return null;
  }

  static int _compareEdges(AgentRunEdge a, AgentRunEdge b) {
    final byCreatedAt = a.createdAt.compareTo(b.createdAt);
    if (byCreatedAt != 0) return byCreatedAt;
    return a.childRunId.compareTo(b.childRunId);
  }

  static int _compareEvents(AgentRunEvent a, AgentRunEvent b) {
    final byCreatedAt = a.createdAt.compareTo(b.createdAt);
    if (byCreatedAt != 0) return byCreatedAt;
    final byType = _eventTypeOrder(a.type).compareTo(_eventTypeOrder(b.type));
    if (byType != 0) return byType;
    return a.eventId.compareTo(b.eventId);
  }

  static int _eventTypeOrder(AgentRunEventType type) {
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

  static bool _isPendingControlEventType(AgentRunEventType type) {
    return type == AgentRunEventType.userInput ||
        type == AgentRunEventType.resumeRequest ||
        type == AgentRunEventType.retryRequest;
  }

  static bool _isAcknowledgeableControlEventType(AgentRunEventType type) {
    return _isPendingControlEventType(type) ||
        type == AgentRunEventType.waitRequest ||
        type == AgentRunEventType.cancelRequest;
  }
}

SubAgentRunStatus _subAgentStatusFromString(String? value) {
  for (final status in SubAgentRunStatus.values) {
    if (status.asString == value) return status;
  }
  return SubAgentRunStatus.notFound;
}

SubAgentRunStatus? _optionalSubAgentStatusFromString(String? value) {
  if (value == null) return null;
  for (final status in SubAgentRunStatus.values) {
    if (status.asString == value) return status;
  }
  return null;
}

SubAgentRunStatus _subAgentStatusForSeminarStatus(AiSeminarRunStatus status) {
  return switch (status) {
    AiSeminarRunStatus.draft => SubAgentRunStatus.pendingInit,
    AiSeminarRunStatus.running => SubAgentRunStatus.running,
    AiSeminarRunStatus.completed => SubAgentRunStatus.completed,
    AiSeminarRunStatus.needsEvidence => SubAgentRunStatus.interrupted,
    AiSeminarRunStatus.cancelled => SubAgentRunStatus.interrupted,
    AiSeminarRunStatus.failed => SubAgentRunStatus.errored,
  };
}

List<String> _seminarSessionAllowedToolIds(AiSeminarSessionContract session) {
  final out = <String>[];
  for (final profile in session.roleProfiles) {
    for (final toolId in profile.allowedToolIds) {
      final normalized = toolId.trim();
      if (normalized.isEmpty || out.contains(normalized)) continue;
      out.add(normalized);
    }
  }
  return List.unmodifiable(out);
}

List<AiSeminarRunCardEvidenceSnapshot> _seminarSynthesisEvidenceSnapshots(
  AiSeminarSynthesis? synthesis,
) {
  if (synthesis == null || synthesis.evidenceRefIds.isEmpty) {
    return const <AiSeminarRunCardEvidenceSnapshot>[];
  }
  final ids = synthesis.evidenceRefIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  return synthesis.evidence
      .where((item) => ids.contains(item.id.trim()))
      .map(_seminarEvidenceSnapshotFromEvidence)
      .where((item) => !item.isEmpty)
      .toList(growable: false);
}

AiSeminarRunCardEvidenceSnapshot _seminarEvidenceSnapshotFromEvidence(
  AiSeminarEvidence evidence,
) {
  final ref = evidence.sourceRef;
  return AiSeminarRunCardEvidenceSnapshot(
    id: evidence.id,
    title: _trimmedOrFallback(
      ref.sourceTitle,
      _trimmedOrFallback(ref.locationLabel, evidence.scope.asString),
    ),
    snippet: _trimmedOrFallback(ref.sourceTextSnippet, evidence.text),
    sourceRef: ref,
  );
}

String _trimmedOrFallback(String? value, String fallback) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? fallback.trim() : trimmed;
}

String _stringField(Map<String, dynamic> json, String key) =>
    json[key]?.toString() ?? '';

String? _optionalStringField(Map<String, dynamic> json, String key) {
  final value = json[key]?.toString().trim();
  return value == null || value.isEmpty ? null : value;
}

List<String> _stringListField(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

List<AiSeminarRunCardEvidenceSnapshot> _evidenceRefsField(Object? value) {
  if (value is! List) return const <AiSeminarRunCardEvidenceSnapshot>[];
  return value
      .whereType<Map>()
      .map(
        (item) => AiSeminarRunCardEvidenceSnapshot.fromJson(
          item.map((key, value) => MapEntry(key.toString(), value)),
        ),
      )
      .where((item) => !item.isEmpty)
      .toList(growable: false);
}

int _nonNegativeInt(Object? raw) {
  if (raw is int) return raw < 0 ? 0 : raw;
  if (raw is num) return raw < 0 ? 0 : raw.toInt();
  final parsed = int.tryParse(raw?.toString() ?? '') ?? 0;
  return parsed < 0 ? 0 : parsed;
}

DateTime _dateTimeField(Map<String, dynamic> json, String key) =>
    _optionalDateTimeField(json, key) ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

DateTime? _optionalDateTimeField(Map<String, dynamic> json, String key) {
  final value = json[key]?.toString();
  return value == null ? null : DateTime.tryParse(value);
}

DateTime _dateTimeFromMillis(int? value) {
  return DateTime.fromMillisecondsSinceEpoch(value ?? 0);
}

String seminarRoleNickname(AiSeminarRole role) {
  return switch (role) {
    AiSeminarRole.critical => 'Critical',
    AiSeminarRole.supportive => 'Supportive',
    AiSeminarRole.synthesizer => 'Synthesizer',
    AiSeminarRole.verifier => 'Verifier',
  };
}
