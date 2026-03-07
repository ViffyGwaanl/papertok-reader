import 'dart:convert';

enum MemoryDocTarget {
  daily,
  longTerm;

  String get wire => this == MemoryDocTarget.daily ? 'daily' : 'memory';

  static MemoryDocTarget fromWire(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    if (normalized == 'memory' ||
        normalized == 'mem' ||
        normalized == 'long_term' ||
        normalized == 'longterm') {
      return MemoryDocTarget.longTerm;
    }
    return MemoryDocTarget.daily;
  }
}

enum MemoryCandidateStatus {
  pending,
  applied,
  dismissed;

  String get wire => switch (this) {
        MemoryCandidateStatus.pending => 'pending',
        MemoryCandidateStatus.applied => 'applied',
        MemoryCandidateStatus.dismissed => 'dismissed',
      };

  static MemoryCandidateStatus fromWire(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    return switch (normalized) {
      'applied' => MemoryCandidateStatus.applied,
      'dismissed' => MemoryCandidateStatus.dismissed,
      _ => MemoryCandidateStatus.pending,
    };
  }
}

class MemoryCandidate {
  const MemoryCandidate({
    required this.id,
    required this.sourceType,
    required this.targetDoc,
    required this.text,
    required this.summary,
    required this.status,
    required this.createdAtMs,
    this.conversationId,
    this.messageNodeId,
    this.sensitivity = 'normal',
    this.confidence,
    this.appliedAtMs,
  });

  final String id;
  final String sourceType;
  final String? conversationId;
  final String? messageNodeId;
  final MemoryDocTarget targetDoc;
  final String text;
  final String summary;
  final String sensitivity;
  final double? confidence;
  final MemoryCandidateStatus status;
  final int createdAtMs;
  final int? appliedAtMs;

  bool get isPending => status == MemoryCandidateStatus.pending;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourceType': sourceType,
      'conversationId': conversationId,
      'messageNodeId': messageNodeId,
      'targetDoc': targetDoc.wire,
      'text': text,
      'summary': summary,
      'sensitivity': sensitivity,
      'confidence': confidence,
      'status': status.wire,
      'createdAtMs': createdAtMs,
      'appliedAtMs': appliedAtMs,
    };
  }

  factory MemoryCandidate.fromJson(Map<String, dynamic> json) {
    return MemoryCandidate(
      id: (json['id'] ?? '').toString(),
      sourceType: (json['sourceType'] ?? 'manual').toString(),
      conversationId: json['conversationId']?.toString(),
      messageNodeId: json['messageNodeId']?.toString(),
      targetDoc: MemoryDocTarget.fromWire(json['targetDoc']?.toString()),
      text: (json['text'] ?? '').toString(),
      summary: (json['summary'] ?? '').toString(),
      sensitivity: (json['sensitivity'] ?? 'normal').toString(),
      confidence: (json['confidence'] as num?)?.toDouble(),
      status: MemoryCandidateStatus.fromWire(json['status']?.toString()),
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
      appliedAtMs: (json['appliedAtMs'] as num?)?.toInt(),
    );
  }

  MemoryCandidate copyWith({
    String? id,
    String? sourceType,
    String? conversationId,
    String? messageNodeId,
    MemoryDocTarget? targetDoc,
    String? text,
    String? summary,
    String? sensitivity,
    double? confidence,
    MemoryCandidateStatus? status,
    int? createdAtMs,
    int? appliedAtMs,
  }) {
    return MemoryCandidate(
      id: id ?? this.id,
      sourceType: sourceType ?? this.sourceType,
      conversationId: conversationId ?? this.conversationId,
      messageNodeId: messageNodeId ?? this.messageNodeId,
      targetDoc: targetDoc ?? this.targetDoc,
      text: text ?? this.text,
      summary: summary ?? this.summary,
      sensitivity: sensitivity ?? this.sensitivity,
      confidence: confidence ?? this.confidence,
      status: status ?? this.status,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      appliedAtMs: appliedAtMs ?? this.appliedAtMs,
    );
  }

  @override
  String toString() => jsonEncode(toJson());
}
