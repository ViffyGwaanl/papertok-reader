import 'package:flutter/foundation.dart';
import 'package:papertok_reader/models/source_ref.dart';

enum AiSeminarRole {
  critical('critical'),
  supportive('supportive'),
  synthesizer('synthesizer'),
  verifier('verifier');

  const AiSeminarRole(this.asString);

  final String asString;

  bool get isDefaultRole =>
      this == AiSeminarRole.critical ||
      this == AiSeminarRole.supportive ||
      this == AiSeminarRole.synthesizer;

  static const List<AiSeminarRole> defaultRoles = <AiSeminarRole>[
    AiSeminarRole.critical,
    AiSeminarRole.supportive,
    AiSeminarRole.synthesizer,
  ];

  static AiSeminarRole? fromString(String? value) {
    for (final role in AiSeminarRole.values) {
      if (role.asString == value) return role;
    }
    return null;
  }
}

enum AiSeminarEvidenceScope {
  currentChapter('current-chapter'),
  currentBook('current-book'),
  library('library'),
  notes('notes'),
  memory('memory'),
  conceptGraph('concept-graph');

  const AiSeminarEvidenceScope(this.asString);

  final String asString;

  static AiSeminarEvidenceScope? fromString(String? value) {
    for (final scope in AiSeminarEvidenceScope.values) {
      if (scope.asString == value) return scope;
    }
    return null;
  }
}

enum AiSeminarWhiteboardKind {
  claim('claim'),
  evidenceRef('evidenceRef'),
  disagreement('disagreement'),
  openQuestion('openQuestion'),
  candidateCard('candidateCard'),
  reviewSuggestion('reviewSuggestion');

  const AiSeminarWhiteboardKind(this.asString);

  final String asString;

  static AiSeminarWhiteboardKind fromString(String? value) {
    for (final kind in AiSeminarWhiteboardKind.values) {
      if (kind.asString == value) return kind;
    }
    return AiSeminarWhiteboardKind.openQuestion;
  }
}

enum AiSeminarRunStatus {
  draft('draft'),
  running('running'),
  completed('completed'),
  needsEvidence('needs-evidence'),
  cancelled('cancelled'),
  failed('failed');

  const AiSeminarRunStatus(this.asString);

  final String asString;

  bool get isTerminal =>
      this == AiSeminarRunStatus.completed ||
      this == AiSeminarRunStatus.needsEvidence ||
      this == AiSeminarRunStatus.cancelled ||
      this == AiSeminarRunStatus.failed;

  static AiSeminarRunStatus fromString(String? value) {
    for (final status in AiSeminarRunStatus.values) {
      if (status.asString == value) return status;
    }
    return AiSeminarRunStatus.draft;
  }
}

@immutable
class AiSeminarSessionContract {
  factory AiSeminarSessionContract({
    required String id,
    required String question,
    int? bookId,
    List<AiSeminarRole> roles = AiSeminarRole.defaultRoles,
    List<AiSeminarEvidenceScope> scopes = const <AiSeminarEvidenceScope>[
      AiSeminarEvidenceScope.currentBook,
    ],
    bool allowWeb = false,
    bool writeRequiresApproval = true,
    int maxRounds = 2,
    int? createdAt,
  }) {
    final normalizedRoles = _normalizeRoles(roles);
    final normalizedScopes = _dedupeScopes(scopes);
    return AiSeminarSessionContract._(
      id: id.trim(),
      question: question.trim(),
      bookId: bookId,
      roles: normalizedRoles,
      scopes: normalizedScopes.isEmpty
          ? const <AiSeminarEvidenceScope>[
              AiSeminarEvidenceScope.currentBook,
            ]
          : normalizedScopes,
      allowWeb: allowWeb,
      writeRequiresApproval: writeRequiresApproval,
      maxRounds: maxRounds.clamp(1, 5),
      createdAt: createdAt,
    );
  }

  const AiSeminarSessionContract._({
    required this.id,
    required this.question,
    required this.bookId,
    required this.roles,
    required this.scopes,
    required this.allowWeb,
    required this.writeRequiresApproval,
    required this.maxRounds,
    required this.createdAt,
  });

  final String id;
  final String question;
  final int? bookId;
  final List<AiSeminarRole> roles;
  final List<AiSeminarEvidenceScope> scopes;
  final bool allowWeb;
  final bool writeRequiresApproval;
  final int maxRounds;
  final int? createdAt;

  bool get hasVerifier => roles.contains(AiSeminarRole.verifier);
  bool get canUseLibrary => scopes.contains(AiSeminarEvidenceScope.library);

  Map<String, dynamic> toJson() => {
        'id': id,
        'question': question,
        if (bookId != null) 'bookId': bookId,
        'roles': roles.map((role) => role.asString).toList(growable: false),
        'scopes': scopes.map((scope) => scope.asString).toList(growable: false),
        'allowWeb': allowWeb,
        'writeRequiresApproval': writeRequiresApproval,
        'maxRounds': maxRounds,
        if (createdAt != null) 'createdAt': createdAt,
      };

  factory AiSeminarSessionContract.fromJson(Map<String, dynamic> json) {
    final rawRoles = (json['roles'] as List?)
            ?.map((e) => AiSeminarRole.fromString(e?.toString()))
            .whereType<AiSeminarRole>()
            .toList(growable: false) ??
        AiSeminarRole.defaultRoles;
    final rawScopes = (json['scopes'] as List?)
            ?.map((e) => AiSeminarEvidenceScope.fromString(e?.toString()))
            .whereType<AiSeminarEvidenceScope>()
            .toList(growable: false) ??
        const <AiSeminarEvidenceScope>[AiSeminarEvidenceScope.currentBook];
    return AiSeminarSessionContract(
      id: (json['id'] ?? '').toString(),
      question: (json['question'] ?? '').toString(),
      bookId: (json['bookId'] as num?)?.toInt(),
      roles: rawRoles,
      scopes: rawScopes,
      allowWeb: json['allowWeb'] == true,
      writeRequiresApproval: json['writeRequiresApproval'] != false,
      maxRounds: (json['maxRounds'] as num?)?.toInt() ?? 2,
      createdAt: (json['createdAt'] as num?)?.toInt(),
    );
  }

  static List<AiSeminarRole> _normalizeRoles(List<AiSeminarRole> roles) {
    final out = <AiSeminarRole>[];
    for (final role in roles) {
      if (!out.contains(role)) out.add(role);
    }
    if (!out.contains(AiSeminarRole.critical)) {
      out.insert(0, AiSeminarRole.critical);
    }
    if (!out.contains(AiSeminarRole.supportive)) {
      out.insert(out.length, AiSeminarRole.supportive);
    }
    if (!out.contains(AiSeminarRole.synthesizer)) {
      out.add(AiSeminarRole.synthesizer);
    }
    out.sort((a, b) {
      final order = <AiSeminarRole, int>{
        AiSeminarRole.critical: 0,
        AiSeminarRole.supportive: 1,
        AiSeminarRole.synthesizer: 2,
        AiSeminarRole.verifier: 3,
      };
      return order[a]!.compareTo(order[b]!);
    });
    return List.unmodifiable(out);
  }

  static List<AiSeminarEvidenceScope> _dedupeScopes(
    List<AiSeminarEvidenceScope> scopes,
  ) {
    final out = <AiSeminarEvidenceScope>[];
    for (final scope in scopes) {
      if (!out.contains(scope)) out.add(scope);
    }
    return List.unmodifiable(out);
  }
}

@immutable
class AiSeminarEvidence {
  const AiSeminarEvidence({
    required this.id,
    required this.scope,
    required this.text,
    required this.sourceRef,
    this.role,
    this.relevance,
    this.note,
  });

  final String id;
  final AiSeminarEvidenceScope scope;
  final String text;
  final SourceRef sourceRef;
  final AiSeminarRole? role;
  final double? relevance;
  final String? note;

  bool get isTraceable => sourceRef.hasEvidence;

  Map<String, dynamic> toJson() => {
        'id': id,
        'scope': scope.asString,
        'text': text,
        'sourceRef': sourceRef.toSafeJson(),
        if (role != null) 'role': role!.asString,
        if (relevance != null) 'relevance': relevance,
        if (note != null && note!.trim().isNotEmpty) 'note': note,
      };

  factory AiSeminarEvidence.fromJson(Map<String, dynamic> json) {
    return AiSeminarEvidence(
      id: (json['id'] ?? '').toString(),
      scope: AiSeminarEvidenceScope.fromString(json['scope']?.toString()) ??
          AiSeminarEvidenceScope.currentBook,
      text: (json['text'] ?? '').toString(),
      sourceRef: SourceRef.fromJson(
        Map<String, dynamic>.from((json['sourceRef'] as Map?) ?? const {}),
      ),
      role: AiSeminarRole.fromString(json['role']?.toString()),
      relevance: (json['relevance'] as num?)?.toDouble(),
      note: json['note']?.toString(),
    );
  }
}

@immutable
class AiSeminarEvidenceBundle {
  const AiSeminarEvidenceBundle({
    required this.query,
    required this.evidence,
  });

  final String query;
  final List<AiSeminarEvidence> evidence;

  bool get allEvidenceTraceable => evidence.every((e) => e.isTraceable);

  Map<String, dynamic> toJson() => {
        'query': query,
        'evidence': evidence.map((e) => e.toJson()).toList(growable: false),
      };

  factory AiSeminarEvidenceBundle.fromJson(Map<String, dynamic> json) {
    return AiSeminarEvidenceBundle(
      query: (json['query'] ?? '').toString(),
      evidence: (json['evidence'] as List?)
              ?.whereType<Map>()
              .map((e) => AiSeminarEvidence.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .toList(growable: false) ??
          const <AiSeminarEvidence>[],
    );
  }
}

@immutable
class AiSeminarWhiteboardEntry {
  const AiSeminarWhiteboardEntry({
    required this.id,
    required this.kind,
    required this.text,
    this.role,
    this.evidenceRefIds = const <String>[],
    this.createdAt,
    this.requiresReview = true,
  });

  final String id;
  final AiSeminarWhiteboardKind kind;
  final String text;
  final AiSeminarRole? role;
  final List<String> evidenceRefIds;
  final int? createdAt;
  final bool requiresReview;

  bool get mustTraceEvidence =>
      kind == AiSeminarWhiteboardKind.claim ||
      kind == AiSeminarWhiteboardKind.disagreement ||
      kind == AiSeminarWhiteboardKind.candidateCard ||
      kind == AiSeminarWhiteboardKind.reviewSuggestion;

  bool get isTraceable => !mustTraceEvidence || evidenceRefIds.isNotEmpty;

  bool hasTraceableEvidence(Set<String> traceableEvidenceIds) {
    if (!mustTraceEvidence) return true;
    return evidenceRefIds.isNotEmpty &&
        evidenceRefIds.every(traceableEvidenceIds.contains);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.asString,
        'text': text,
        if (role != null) 'role': role!.asString,
        'evidenceRefIds': evidenceRefIds,
        if (createdAt != null) 'createdAt': createdAt,
        'requiresReview': requiresReview,
      };

  factory AiSeminarWhiteboardEntry.fromJson(Map<String, dynamic> json) {
    return AiSeminarWhiteboardEntry(
      id: (json['id'] ?? '').toString(),
      kind: AiSeminarWhiteboardKind.fromString(json['kind']?.toString()),
      text: (json['text'] ?? '').toString(),
      role: AiSeminarRole.fromString(json['role']?.toString()),
      evidenceRefIds: (json['evidenceRefIds'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList(growable: false) ??
          const <String>[],
      createdAt: (json['createdAt'] as num?)?.toInt(),
      requiresReview: json['requiresReview'] != false,
    );
  }
}

@immutable
class AiSeminarRoleTurn {
  const AiSeminarRoleTurn({
    required this.id,
    required this.role,
    required this.prompt,
    required this.responseText,
    this.evidenceRefIds = const <String>[],
    this.whiteboardEntries = const <AiSeminarWhiteboardEntry>[],
    this.startedAt,
    this.completedAt,
    this.error,
  });

  final String id;
  final AiSeminarRole role;
  final String prompt;
  final String responseText;
  final List<String> evidenceRefIds;
  final List<AiSeminarWhiteboardEntry> whiteboardEntries;
  final int? startedAt;
  final int? completedAt;
  final String? error;

  bool get isFailed => error != null && error!.trim().isNotEmpty;

  bool hasTraceableEvidence(Set<String> traceableEvidenceIds) {
    final refsOk = evidenceRefIds.isNotEmpty &&
        evidenceRefIds.every(traceableEvidenceIds.contains);
    final entriesOk = whiteboardEntries
        .every((entry) => entry.hasTraceableEvidence(traceableEvidenceIds));
    return refsOk && entriesOk;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.asString,
        'prompt': prompt,
        'responseText': responseText,
        'evidenceRefIds': evidenceRefIds,
        'whiteboardEntries': whiteboardEntries
            .map((entry) => entry.toJson())
            .toList(growable: false),
        if (startedAt != null) 'startedAt': startedAt,
        if (completedAt != null) 'completedAt': completedAt,
        if (error != null) 'error': error,
      };

  factory AiSeminarRoleTurn.fromJson(Map<String, dynamic> json) {
    return AiSeminarRoleTurn(
      id: (json['id'] ?? '').toString(),
      role: AiSeminarRole.fromString(json['role']?.toString()) ??
          AiSeminarRole.synthesizer,
      prompt: (json['prompt'] ?? '').toString(),
      responseText: (json['responseText'] ?? '').toString(),
      evidenceRefIds: AiSeminarSynthesis.stringList(json['evidenceRefIds']),
      whiteboardEntries: (json['whiteboardEntries'] as List?)
              ?.whereType<Map>()
              .map((e) => AiSeminarWhiteboardEntry.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .toList(growable: false) ??
          const <AiSeminarWhiteboardEntry>[],
      startedAt: (json['startedAt'] as num?)?.toInt(),
      completedAt: (json['completedAt'] as num?)?.toInt(),
      error: json['error']?.toString(),
    );
  }
}

@immutable
class AiSeminarSynthesis {
  const AiSeminarSynthesis({
    required this.summary,
    required this.supportiveView,
    required this.criticalView,
    this.disagreements = const <String>[],
    this.openQuestions = const <String>[],
    this.candidateCards = const <AiSeminarWhiteboardEntry>[],
    this.candidateReviewQuestions = const <String>[],
    this.evidenceRefIds = const <String>[],
    this.evidence = const <AiSeminarEvidence>[],
    this.readyForReview = true,
  });

  final String summary;
  final String supportiveView;
  final String criticalView;
  final List<String> disagreements;
  final List<String> openQuestions;
  final List<AiSeminarWhiteboardEntry> candidateCards;
  final List<String> candidateReviewQuestions;
  final List<String> evidenceRefIds;
  final List<AiSeminarEvidence> evidence;
  final bool readyForReview;

  bool get hasTraceableHandoff {
    final traceableEvidenceIds = evidence
        .where((item) => item.isTraceable)
        .map((item) => item.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    return evidenceRefIds.isNotEmpty &&
        evidenceRefIds.every(traceableEvidenceIds.contains) &&
        candidateCards
            .every((card) => card.hasTraceableEvidence(traceableEvidenceIds));
  }

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'supportiveView': supportiveView,
        'criticalView': criticalView,
        'disagreements': disagreements,
        'openQuestions': openQuestions,
        'candidateCards':
            candidateCards.map((card) => card.toJson()).toList(growable: false),
        'candidateReviewQuestions': candidateReviewQuestions,
        'evidenceRefIds': evidenceRefIds,
        'evidence':
            evidence.map((item) => item.toJson()).toList(growable: false),
        'readyForReview': readyForReview,
      };

  factory AiSeminarSynthesis.fromJson(Map<String, dynamic> json) {
    return AiSeminarSynthesis(
      summary: (json['summary'] ?? '').toString(),
      supportiveView: (json['supportiveView'] ?? '').toString(),
      criticalView: (json['criticalView'] ?? '').toString(),
      disagreements: stringList(json['disagreements']),
      openQuestions: stringList(json['openQuestions']),
      candidateCards: (json['candidateCards'] as List?)
              ?.whereType<Map>()
              .map((e) => AiSeminarWhiteboardEntry.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .toList(growable: false) ??
          const <AiSeminarWhiteboardEntry>[],
      candidateReviewQuestions: stringList(json['candidateReviewQuestions']),
      evidenceRefIds: stringList(json['evidenceRefIds']),
      evidence: (json['evidence'] as List?)
              ?.whereType<Map>()
              .map((e) => AiSeminarEvidence.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .toList(growable: false) ??
          const <AiSeminarEvidence>[],
      readyForReview: json['readyForReview'] != false,
    );
  }

  static List<String> stringList(Object? value) {
    return (value as List?)
            ?.map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
  }
}

@immutable
class AiSeminarRun {
  const AiSeminarRun({
    required this.session,
    required this.status,
    required this.evidenceBundle,
    this.turns = const <AiSeminarRoleTurn>[],
    this.synthesis,
    this.startedAt,
    this.completedAt,
    this.message,
  });

  final AiSeminarSessionContract session;
  final AiSeminarRunStatus status;
  final AiSeminarEvidenceBundle evidenceBundle;
  final List<AiSeminarRoleTurn> turns;
  final AiSeminarSynthesis? synthesis;
  final int? startedAt;
  final int? completedAt;
  final String? message;

  bool get readyForReview =>
      status == AiSeminarRunStatus.completed &&
      synthesis != null &&
      synthesis!.readyForReview &&
      synthesis!.hasTraceableHandoff;

  Map<String, dynamic> toJson() => {
        'session': session.toJson(),
        'status': status.asString,
        'evidenceBundle': evidenceBundle.toJson(),
        'turns': turns.map((turn) => turn.toJson()).toList(growable: false),
        if (synthesis != null) 'synthesis': synthesis!.toJson(),
        if (startedAt != null) 'startedAt': startedAt,
        if (completedAt != null) 'completedAt': completedAt,
        if (message != null) 'message': message,
      };

  factory AiSeminarRun.fromJson(Map<String, dynamic> json) {
    return AiSeminarRun(
      session: AiSeminarSessionContract.fromJson(
        Map<String, dynamic>.from((json['session'] as Map?) ?? const {}),
      ),
      status: AiSeminarRunStatus.fromString(json['status']?.toString()),
      evidenceBundle: AiSeminarEvidenceBundle.fromJson(
        Map<String, dynamic>.from(
          (json['evidenceBundle'] as Map?) ?? const {},
        ),
      ),
      turns: (json['turns'] as List?)
              ?.whereType<Map>()
              .map((e) => AiSeminarRoleTurn.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .toList(growable: false) ??
          const <AiSeminarRoleTurn>[],
      synthesis: json['synthesis'] is Map
          ? AiSeminarSynthesis.fromJson(
              Map<String, dynamic>.from(json['synthesis'] as Map),
            )
          : null,
      startedAt: (json['startedAt'] as num?)?.toInt(),
      completedAt: (json['completedAt'] as num?)?.toInt(),
      message: json['message']?.toString(),
    );
  }
}
