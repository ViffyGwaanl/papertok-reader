import 'dart:async';
import 'dart:convert';

enum AgentToolCallEventStatus {
  running,
  completed,
  errored,
}

class AgentToolCallEvent {
  const AgentToolCallEvent({
    required this.callId,
    required this.toolId,
    required this.input,
    required this.status,
    this.agentRunId,
    this.parentRunId,
    this.roleId,
    this.output,
    this.error,
    this.resultCount,
    this.durationMs,
  });

  final String? agentRunId;
  final String? parentRunId;
  final String? roleId;
  final String callId;
  final String toolId;
  final Map<String, dynamic> input;
  final AgentToolCallEventStatus status;
  final String? output;
  final String? error;
  final int? resultCount;
  final int? durationMs;

  AgentToolCallEvent copyWith({
    String? agentRunId,
    String? parentRunId,
    String? roleId,
    String? callId,
    String? toolId,
    Map<String, dynamic>? input,
    AgentToolCallEventStatus? status,
    String? output,
    String? error,
    int? resultCount,
    int? durationMs,
  }) {
    return AgentToolCallEvent(
      agentRunId: agentRunId ?? this.agentRunId,
      parentRunId: parentRunId ?? this.parentRunId,
      roleId: roleId ?? this.roleId,
      callId: callId ?? this.callId,
      toolId: toolId ?? this.toolId,
      input: input ?? this.input,
      status: status ?? this.status,
      output: output ?? this.output,
      error: error ?? this.error,
      resultCount: resultCount ?? this.resultCount,
      durationMs: durationMs ?? this.durationMs,
    );
  }
}

typedef AgentToolCallObserver = FutureOr<void> Function(
  AgentToolCallEvent event,
);

String agentToolCallEventIdSegment(AgentToolCallEvent event) {
  final callId = event.callId.trim();
  if (callId.isNotEmpty) return callId;
  final toolId = event.toolId.trim();
  final toolKey = toolId.isEmpty ? 'unknown' : toolId;
  final inputKey = _stableToolInputKey(event.input);
  return inputKey.isEmpty ? toolKey : '$toolKey:$inputKey';
}

String _stableToolInputKey(Map<String, dynamic> input) {
  if (input.isEmpty) return '';
  final canonical = jsonEncode(_canonicalToolInputValue(input));
  final hash = _stableHash(canonical);
  return 'input-$hash-${canonical.length}';
}

Object? _canonicalToolInputValue(Object? value) {
  if (value is Map) {
    final entries = value.entries
        .map((entry) => MapEntry(entry.key.toString(), entry.value))
        .toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    return {
      for (final entry in entries)
        entry.key: _canonicalToolInputValue(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_canonicalToolInputValue).toList(growable: false);
  }
  if (value == null || value is num || value is bool || value is String) {
    return value;
  }
  return value.toString();
}

String _stableHash(String value) {
  var hash = 5381;
  for (final codeUnit in value.codeUnits) {
    hash = (((hash << 5) + hash) + codeUnit) & 0x7fffffff;
  }
  return hash.toRadixString(16);
}
