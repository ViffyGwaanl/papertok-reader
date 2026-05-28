import 'package:flutter/foundation.dart';
import 'package:papertok_reader/models/source_ref.dart';

enum ConceptNodeType {
  concept('concept'),
  entity('entity'),
  claim('claim'),
  method('method'),
  book('book'),
  chapter('chapter'),
  card('card'),
  unknown('unknown');

  const ConceptNodeType(this.asString);

  final String asString;

  static ConceptNodeType fromString(String? value) {
    for (final type in ConceptNodeType.values) {
      if (type.asString == value) return type;
    }
    return ConceptNodeType.unknown;
  }
}

enum ConceptEdgeType {
  explains('explains'),
  supports('supports'),
  contradicts('contradicts'),
  exemplifies('exemplifies'),
  dependsOn('depends_on'),
  relatedTo('related_to'),
  appearsIn('appears_in'),
  unknown('unknown');

  const ConceptEdgeType(this.asString);

  final String asString;

  static ConceptEdgeType fromString(String? value) {
    for (final type in ConceptEdgeType.values) {
      if (type.asString == value) return type;
    }
    return ConceptEdgeType.unknown;
  }
}

@immutable
class ConceptNode {
  const ConceptNode({
    required this.id,
    required this.type,
    required this.label,
    this.summary,
    this.sourceRefs = const <SourceRef>[],
    this.cardIds = const <String>[],
    this.ownership = AiOutputOwnership.aiGeneratedDraft,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final ConceptNodeType type;
  final String label;
  final String? summary;
  final List<SourceRef> sourceRefs;
  final List<String> cardIds;
  final AiOutputOwnership ownership;
  final int? createdAt;
  final int? updatedAt;

  bool get hasEvidence => sourceRefs.any((ref) => ref.hasEvidence);

  bool get isFormal =>
      hasEvidence && ownership != AiOutputOwnership.aiGeneratedDraft;

  bool get isOrphan => !hasEvidence && cardIds.isEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.asString,
        'label': label,
        if (summary != null) 'summary': summary,
        'sourceRefs':
            sourceRefs.map((ref) => ref.toSafeJson()).toList(growable: false),
        'cardIds': cardIds,
        'ownership': ownership.asString,
        if (createdAt != null) 'createdAt': createdAt,
        if (updatedAt != null) 'updatedAt': updatedAt,
      };

  factory ConceptNode.fromJson(Map<String, dynamic> json) {
    return ConceptNode(
      id: (json['id'] ?? '').toString(),
      type: ConceptNodeType.fromString(json['type']?.toString()),
      label: (json['label'] ?? '').toString(),
      summary: json['summary']?.toString(),
      sourceRefs: (json['sourceRefs'] as List?)
              ?.whereType<Map>()
              .map((e) => SourceRef.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false) ??
          const <SourceRef>[],
      cardIds: _stringList(json['cardIds']),
      ownership: AiOutputOwnership.fromString(json['ownership']?.toString()),
      createdAt: (json['createdAt'] as num?)?.toInt(),
      updatedAt: (json['updatedAt'] as num?)?.toInt(),
    );
  }
}

@immutable
class ConceptEdge {
  const ConceptEdge({
    required this.id,
    required this.sourceNodeId,
    required this.targetNodeId,
    required this.type,
    this.label,
    this.evidenceRefs = const <SourceRef>[],
    this.confidence,
    this.ownership = AiOutputOwnership.aiGeneratedDraft,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String sourceNodeId;
  final String targetNodeId;
  final ConceptEdgeType type;
  final String? label;
  final List<SourceRef> evidenceRefs;
  final double? confidence;
  final AiOutputOwnership ownership;
  final int? createdAt;
  final int? updatedAt;

  bool get hasEvidence => evidenceRefs.any((ref) => ref.hasEvidence);

  bool get isFormal =>
      hasEvidence && ownership != AiOutputOwnership.aiGeneratedDraft;

  bool get isBroken =>
      sourceNodeId.trim().isEmpty || targetNodeId.trim().isEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceNodeId': sourceNodeId,
        'targetNodeId': targetNodeId,
        'type': type.asString,
        if (label != null) 'label': label,
        'evidenceRefs':
            evidenceRefs.map((ref) => ref.toSafeJson()).toList(growable: false),
        if (confidence != null) 'confidence': confidence,
        'ownership': ownership.asString,
        if (createdAt != null) 'createdAt': createdAt,
        if (updatedAt != null) 'updatedAt': updatedAt,
      };

  factory ConceptEdge.fromJson(Map<String, dynamic> json) {
    return ConceptEdge(
      id: (json['id'] ?? '').toString(),
      sourceNodeId: (json['sourceNodeId'] ?? '').toString(),
      targetNodeId: (json['targetNodeId'] ?? '').toString(),
      type: ConceptEdgeType.fromString(json['type']?.toString()),
      label: json['label']?.toString(),
      evidenceRefs: (json['evidenceRefs'] as List?)
              ?.whereType<Map>()
              .map((e) => SourceRef.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false) ??
          const <SourceRef>[],
      confidence: (json['confidence'] as num?)?.toDouble(),
      ownership: AiOutputOwnership.fromString(json['ownership']?.toString()),
      createdAt: (json['createdAt'] as num?)?.toInt(),
      updatedAt: (json['updatedAt'] as num?)?.toInt(),
    );
  }
}

@immutable
class ConceptDossier {
  const ConceptDossier({
    required this.node,
    this.definition,
    this.appearances = const <SourceRef>[],
    this.relatedEdges = const <ConceptEdge>[],
    this.supportingEvidence = const <SourceRef>[],
    this.contradictingEvidence = const <SourceRef>[],
    this.recommendedNextNodeIds = const <String>[],
  });

  final ConceptNode node;
  final String? definition;
  final List<SourceRef> appearances;
  final List<ConceptEdge> relatedEdges;
  final List<SourceRef> supportingEvidence;
  final List<SourceRef> contradictingEvidence;
  final List<String> recommendedNextNodeIds;

  bool get canJumpBack =>
      node.sourceRefs.any((ref) => ref.canJumpBack) ||
      appearances.any((ref) => ref.canJumpBack);

  Map<String, dynamic> toJson() => {
        'node': node.toJson(),
        if (definition != null) 'definition': definition,
        'appearances':
            appearances.map((ref) => ref.toSafeJson()).toList(growable: false),
        'relatedEdges':
            relatedEdges.map((edge) => edge.toJson()).toList(growable: false),
        'supportingEvidence': supportingEvidence
            .map((ref) => ref.toSafeJson())
            .toList(growable: false),
        'contradictingEvidence': contradictingEvidence
            .map((ref) => ref.toSafeJson())
            .toList(growable: false),
        'recommendedNextNodeIds': recommendedNextNodeIds,
      };
}

@immutable
class ConceptExplorationPolicy {
  const ConceptExplorationPolicy({
    this.maxDepth = 2,
    this.maxNodesPerDepth = 7,
    this.allowExternal = false,
  });

  final int maxDepth;
  final int maxNodesPerDepth;
  final bool allowExternal;

  int clampDepth(int requestedDepth) => requestedDepth.clamp(0, maxDepth);

  List<T> clampLayer<T>(Iterable<T> nodes) {
    return nodes.take(maxNodesPerDepth.clamp(1, 20)).toList(growable: false);
  }

  Map<String, dynamic> toJson() => {
        'maxDepth': maxDepth,
        'maxNodesPerDepth': maxNodesPerDepth,
        'allowExternal': allowExternal,
      };
}

@immutable
class ConceptExplorationPath {
  const ConceptExplorationPath({
    required this.startNodeId,
    required this.nodeIds,
    required this.returnPath,
    this.policy = const ConceptExplorationPolicy(),
  });

  final String startNodeId;
  final List<String> nodeIds;
  final List<String> returnPath;
  final ConceptExplorationPolicy policy;

  bool get isWithinDepth => returnPath.length <= policy.maxDepth + 1;

  Map<String, dynamic> toJson() => {
        'startNodeId': startNodeId,
        'nodeIds': nodeIds,
        'returnPath': returnPath,
        'policy': policy.toJson(),
      };
}

List<String> _stringList(Object? value) {
  return (value as List?)
          ?.map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(growable: false) ??
      const <String>[];
}
