enum MemoryDocTarget { daily, longTerm }

enum MemoryCandidateStatus { pending, applied, dismissed }

class MemoryCandidate {
  const MemoryCandidate({
    required this.id,
    required this.summary,
    required this.text,
    required this.targetDoc,
    required this.sourceType,
    required this.createdAtMs,
    required this.status,
    this.conversationId,
    this.messageNodeId,
    this.sensitivity = 'normal',
    this.confidence,
    this.appliedAtMs,
    this.displayText,
    this.sourcePointer,
    this.rawContextRef,
    this.appliedTargetDoc,
    this.reviewedAtMs,
    this.dismissedAtMs,
    this.decisionSource,
    this.triggerKind,
  });

  final String id;
  final String summary;
  final String text;

  /// The system's original recommendation.
  final MemoryDocTarget targetDoc;

  /// The destination actually chosen when the candidate is applied.
  final MemoryDocTarget? appliedTargetDoc;

  final String sourceType;
  final int createdAtMs;
  final MemoryCandidateStatus status;
  final String? conversationId;
  final String? messageNodeId;
  final String sensitivity;
  final double? confidence;
  final int? appliedAtMs;
  final int? reviewedAtMs;
  final int? dismissedAtMs;
  final String? decisionSource;
  final String? triggerKind;
  final String? displayText;
  final String? sourcePointer;
  final String? rawContextRef;

  MemoryDocTarget get effectiveTargetDoc => appliedTargetDoc ?? targetDoc;

  bool get isPending => status == MemoryCandidateStatus.pending;
  bool get isApplied => status == MemoryCandidateStatus.applied;
  bool get isDismissed => status == MemoryCandidateStatus.dismissed;

  String get effectiveDisplayText {
    final value = (displayText ?? '').trim();
    if (value.isNotEmpty) {
      return value;
    }
    return text;
  }

  String get effectiveSourcePointer {
    final value = (sourcePointer ?? '').trim();
    if (value.isNotEmpty) {
      return value;
    }
    final conversation = (conversationId ?? '').trim();
    final messageNode = (messageNodeId ?? '').trim();
    if (conversation.isEmpty && messageNode.isEmpty) {
      return '';
    }
    if (conversation.isNotEmpty && messageNode.isNotEmpty) {
      return '$conversation#$messageNode';
    }
    return conversation.isNotEmpty ? conversation : messageNode;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'summary': summary,
      'text': text,
      'targetDoc': targetDoc.name,
      'appliedTargetDoc': appliedTargetDoc?.name,
      'sourceType': sourceType,
      'createdAtMs': createdAtMs,
      'status': status.name,
      'conversationId': conversationId,
      'messageNodeId': messageNodeId,
      'sensitivity': sensitivity,
      'confidence': confidence,
      'appliedAtMs': appliedAtMs,
      'reviewedAtMs': reviewedAtMs,
      'dismissedAtMs': dismissedAtMs,
      'decisionSource': decisionSource,
      'triggerKind': triggerKind,
      'displayText': displayText,
      'sourcePointer': sourcePointer,
      'rawContextRef': rawContextRef,
    };
  }

  factory MemoryCandidate.fromJson(Map<String, dynamic> json) {
    return MemoryCandidate(
      id: (json['id'] ?? '').toString(),
      summary: (json['summary'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      targetDoc: MemoryDocTarget.values.firstWhere(
        (value) =>
            value.name == (json['targetDoc'] ?? json['proposedTargetDoc']),
        orElse: () => MemoryDocTarget.daily,
      ),
      appliedTargetDoc: () {
        for (final value in MemoryDocTarget.values) {
          if (value.name == json['appliedTargetDoc']) {
            return value;
          }
        }
        return null;
      }(),
      sourceType: (json['sourceType'] ?? '').toString(),
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
      status: MemoryCandidateStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => MemoryCandidateStatus.pending,
      ),
      conversationId: json['conversationId']?.toString(),
      messageNodeId: json['messageNodeId']?.toString(),
      sensitivity: (json['sensitivity'] ?? 'normal').toString(),
      confidence: (json['confidence'] as num?)?.toDouble(),
      appliedAtMs: (json['appliedAtMs'] as num?)?.toInt(),
      reviewedAtMs: (json['reviewedAtMs'] as num?)?.toInt(),
      dismissedAtMs: (json['dismissedAtMs'] as num?)?.toInt(),
      decisionSource: json['decisionSource']?.toString(),
      triggerKind: json['triggerKind']?.toString(),
      displayText: json['displayText']?.toString(),
      sourcePointer: json['sourcePointer']?.toString(),
      rawContextRef: json['rawContextRef']?.toString(),
    );
  }

  MemoryCandidate copyWith({
    String? id,
    String? summary,
    String? text,
    MemoryDocTarget? targetDoc,
    MemoryDocTarget? appliedTargetDoc,
    String? sourceType,
    int? createdAtMs,
    MemoryCandidateStatus? status,
    String? conversationId,
    String? messageNodeId,
    String? sensitivity,
    double? confidence,
    int? appliedAtMs,
    int? reviewedAtMs,
    int? dismissedAtMs,
    String? decisionSource,
    String? triggerKind,
    String? displayText,
    String? sourcePointer,
    String? rawContextRef,
  }) {
    return MemoryCandidate(
      id: id ?? this.id,
      summary: summary ?? this.summary,
      text: text ?? this.text,
      targetDoc: targetDoc ?? this.targetDoc,
      appliedTargetDoc: appliedTargetDoc ?? this.appliedTargetDoc,
      sourceType: sourceType ?? this.sourceType,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      status: status ?? this.status,
      conversationId: conversationId ?? this.conversationId,
      messageNodeId: messageNodeId ?? this.messageNodeId,
      sensitivity: sensitivity ?? this.sensitivity,
      confidence: confidence ?? this.confidence,
      appliedAtMs: appliedAtMs ?? this.appliedAtMs,
      reviewedAtMs: reviewedAtMs ?? this.reviewedAtMs,
      dismissedAtMs: dismissedAtMs ?? this.dismissedAtMs,
      decisionSource: decisionSource ?? this.decisionSource,
      triggerKind: triggerKind ?? this.triggerKind,
      displayText: displayText ?? this.displayText,
      sourcePointer: sourcePointer ?? this.sourcePointer,
      rawContextRef: rawContextRef ?? this.rawContextRef,
    );
  }
}
