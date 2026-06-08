import 'package:flutter/foundation.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:papertok_reader/models/ai_seminar.dart';
import 'package:papertok_reader/models/source_ref.dart';

/// A persistent conversation tree that supports branching edits and per-turn
/// variants (Cherry-style).
///
/// Design:
/// - Nodes form a tree rooted at a sentinel [rootId].
/// - Each node has an ordered list of children.
/// - Each node stores an [activeChildId] pointer, which determines the active
///   conversation path. Switching variants updates the parent's activeChildId.
/// - The active path is derived by following [activeChildId] pointers from root.
@immutable
class AiConversationTree {
  const AiConversationTree({
    required this.rootId,
    required this.nodes,
  });

  final String rootId;
  final Map<String, AiConversationNode> nodes;

  factory AiConversationTree.empty() {
    const rootId = 'root';
    return AiConversationTree(
      rootId: rootId,
      nodes: {
        rootId: const AiConversationNode(
          id: rootId,
          parentId: null,
          children: <String>[],
          activeChildId: null,
          message: null,
          createdAt: 0,
          updatedAt: 0,
        ),
      },
    );
  }

  AiConversationNode get root => nodes[rootId]!;

  List<String> activePathNodeIds() {
    final result = <String>[];
    var currentId = rootId;
    while (true) {
      final node = nodes[currentId];
      if (node == null) break;
      final nextId = node.activeChildId;
      if (nextId == null) break;
      result.add(nextId);
      currentId = nextId;
    }
    return result;
  }

  List<ChatMessage> activePathMessages() {
    final ids = activePathNodeIds();
    return ids
        .map((id) => nodes[id])
        .whereType<AiConversationNode>()
        .map((n) => n.toChatMessage())
        .whereType<ChatMessage>()
        .toList(growable: false);
  }

  List<String> siblingsOf(String nodeId) {
    final node = nodes[nodeId];
    if (node == null) return const [];
    final parentId = node.parentId;
    if (parentId == null) return const [];
    final parent = nodes[parentId];
    return parent?.children ?? const [];
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': 2,
      'rootId': rootId,
      'nodes': nodes.map((k, v) => MapEntry(k, v.toJson())),
    };
  }

  factory AiConversationTree.fromJson(Map<String, dynamic> json) {
    final rootId = json['rootId']?.toString() ?? 'root';
    final rawNodes = json['nodes'];
    final nodes = <String, AiConversationNode>{};

    if (rawNodes is Map) {
      for (final entry in rawNodes.entries) {
        final id = entry.key.toString();
        final value = entry.value;
        if (value is Map) {
          nodes[id] = AiConversationNode.fromJson(
            id,
            value.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
      }
    }

    if (!nodes.containsKey(rootId)) {
      nodes[rootId] = AiConversationTree.empty().nodes[rootId]!;
    }

    return AiConversationTree(rootId: rootId, nodes: nodes);
  }

  /// Build a tree from a linear message list (migration from v1 history).
  ///
  /// Legacy history encodes assistant variants by appending multiple
  /// [AIChatMessage] consecutively after a single [HumanChatMessage]. This
  /// migration groups consecutive assistant messages under the latest human as
  /// siblings (variants), and uses the *last* assistant in the run as the active
  /// one.
  factory AiConversationTree.fromLinearMessages(List<ChatMessage> messages) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final nodes =
        Map<String, AiConversationNode>.from(AiConversationTree.empty().nodes);

    // The last node on the active path (used to attach the next human message).
    var activeTailId = 'root';

    // The latest human node in the current turn (used to attach assistant variants).
    String? currentTurnHumanId;

    String newId() =>
        '${DateTime.now().microsecondsSinceEpoch}-${nodes.length}';

    void attachChild(String parentId, String childId) {
      final parent = nodes[parentId]!;
      nodes[parentId] = parent.copyWith(
        children: [...parent.children, childId],
        activeChildId: childId,
        updatedAt: now,
      );
    }

    for (final msg in messages) {
      if (msg is HumanChatMessage) {
        final id = newId();
        nodes[id] = AiConversationNode(
          id: id,
          parentId: activeTailId,
          children: const [],
          activeChildId: null,
          message: msg.toMap(),
          createdAt: now,
          updatedAt: now,
        );
        attachChild(activeTailId, id);
        activeTailId = id;
        currentTurnHumanId = id;
        continue;
      }

      if (msg is AIChatMessage) {
        final parentId = currentTurnHumanId ?? activeTailId;
        final id = newId();
        nodes[id] = AiConversationNode(
          id: id,
          parentId: parentId,
          children: const [],
          activeChildId: null,
          message: msg.toMap(),
          createdAt: now,
          updatedAt: now,
        );
        attachChild(parentId, id);

        // The active continuation after this turn should follow the latest
        // assistant variant.
        activeTailId = id;
        continue;
      }

      // Fallback: chain other message types.
      final id = newId();
      nodes[id] = AiConversationNode(
        id: id,
        parentId: activeTailId,
        children: const [],
        activeChildId: null,
        message: msg.toMap(),
        createdAt: now,
        updatedAt: now,
      );
      attachChild(activeTailId, id);
      activeTailId = id;
      currentTurnHumanId = null;
    }

    return AiConversationTree(rootId: 'root', nodes: nodes);
  }

  /// Returns a new tree with [parentId]'s active child switched to [childId].
  AiConversationTree setActiveChild(String parentId, String? childId) {
    final parent = nodes[parentId];
    if (parent == null) return this;
    if (childId != null && !parent.children.contains(childId)) {
      return this;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    return copyWithNode(
      parentId,
      parent.copyWith(activeChildId: childId, updatedAt: now),
    );
  }

  AiConversationTree copyWithNode(String id, AiConversationNode node) {
    return AiConversationTree(
      rootId: rootId,
      nodes: {
        ...nodes,
        id: node,
      },
    );
  }

  /// Append a new child node under [parentId] and set it active.
  AiConversationTree appendChild({
    required String parentId,
    required ChatMessage message,
    SourceRef? sourceRef,
  }) {
    final parent = nodes[parentId];
    if (parent == null) return this;

    final now = DateTime.now().millisecondsSinceEpoch;
    final id = '${DateTime.now().microsecondsSinceEpoch}-${nodes.length}';
    final child = AiConversationNode(
      id: id,
      parentId: parentId,
      children: const [],
      activeChildId: null,
      message: message.toMap(),
      createdAt: now,
      updatedAt: now,
      sourceRef: sourceRef,
    );

    final updatedParent = parent.copyWith(
      children: [...parent.children, id],
      activeChildId: id,
      updatedAt: now,
    );

    return AiConversationTree(
      rootId: rootId,
      nodes: {
        ...nodes,
        parentId: updatedParent,
        id: child,
      },
    );
  }

  /// Update the message map for an existing node.
  AiConversationTree updateNodeMessage(String nodeId, ChatMessage message) {
    final node = nodes[nodeId];
    if (node == null) return this;
    final now = DateTime.now().millisecondsSinceEpoch;
    return copyWithNode(
      nodeId,
      node.copyWith(message: message.toMap(), updatedAt: now),
    );
  }
}

@immutable
class AiConversationNode {
  const AiConversationNode({
    required this.id,
    required this.parentId,
    required this.children,
    required this.activeChildId,
    required this.message,
    required this.createdAt,
    required this.updatedAt,
    this.meta,
    this.sourceRef,
  });

  final String id;
  final String? parentId;
  final List<String> children;
  final String? activeChildId;

  /// A ChatMessage.toMap() map. Null only for the root sentinel node.
  final Map<String, dynamic>? message;

  final int createdAt;
  final int updatedAt;

  /// Per-segment metadata (model + token usage). Null for non-assistant nodes
  /// and legacy data created before this field existed.
  final AiSegmentMeta? meta;

  /// Optional reader provenance for a user turn. Stored on the user node so
  /// assistant actions can recover the exact selected text after history reload.
  final SourceRef? sourceRef;

  ChatMessage? toChatMessage() {
    final msg = message;
    if (msg == null) return null;
    return ChatMessage.fromMap(msg);
  }

  Map<String, dynamic> toJson() {
    return {
      'parentId': parentId,
      'children': children,
      'activeChildId': activeChildId,
      'message': message,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      if (meta != null) 'meta': meta!.toJson(),
      if (sourceRef != null) 'sourceRef': sourceRef!.toJson(),
    };
  }

  factory AiConversationNode.fromJson(String id, Map<String, dynamic> json) {
    final rawChildren = json['children'];
    final children = <String>[];
    if (rawChildren is List) {
      for (final item in rawChildren) {
        children.add(item.toString());
      }
    }

    final rawMessage = json['message'];
    Map<String, dynamic>? message;
    if (rawMessage is Map) {
      message = rawMessage.map((k, v) => MapEntry(k.toString(), v));
    }

    final rawMeta = json['meta'];
    AiSegmentMeta? meta;
    if (rawMeta is Map) {
      meta = AiSegmentMeta.fromJson(
        rawMeta.map((k, v) => MapEntry(k.toString(), v)),
      );
    }

    SourceRef? sourceRef;
    final rawSourceRef = json['sourceRef'];
    if (rawSourceRef is Map) {
      sourceRef = SourceRef.fromJson(
        rawSourceRef.map((k, v) => MapEntry(k.toString(), v)),
      );
    }

    return AiConversationNode(
      id: id,
      parentId: json['parentId']?.toString(),
      children: children,
      activeChildId: json['activeChildId']?.toString(),
      message: message,
      createdAt: json['createdAt'] is int
          ? json['createdAt'] as int
          : DateTime.now().millisecondsSinceEpoch,
      updatedAt: json['updatedAt'] is int
          ? json['updatedAt'] as int
          : DateTime.now().millisecondsSinceEpoch,
      meta: meta,
      sourceRef: sourceRef,
    );
  }

  AiConversationNode copyWith({
    String? parentId,
    List<String>? children,
    String? activeChildId,
    Map<String, dynamic>? message,
    int? createdAt,
    int? updatedAt,
    AiSegmentMeta? meta,
    SourceRef? sourceRef,
  }) {
    return AiConversationNode(
      id: id,
      parentId: parentId ?? this.parentId,
      children: children ?? this.children,
      activeChildId: activeChildId ?? this.activeChildId,
      message: message ?? this.message,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      meta: meta ?? this.meta,
      sourceRef: sourceRef ?? this.sourceRef,
    );
  }
}

/// Per-segment metadata captured for a single assistant turn.
///
/// Stored on the assistant [AiConversationNode] so it persists with the
/// conversation tree. All fields are optional for backward compatibility.
@immutable
class AiSegmentMeta {
  const AiSegmentMeta({
    this.model,
    this.inputTokens,
    this.outputTokens,
    this.seminarRunCard,
  });

  /// The model name used for this turn (e.g. `gpt-4o`).
  final String? model;

  /// Input tokens consumed by this turn (delta of the session tracker).
  final int? inputTokens;

  /// Output tokens produced by this turn (delta of the session tracker).
  final int? outputTokens;

  /// Optional AI Seminar launcher/restoration card attached to an assistant
  /// node. Older clients ignore this field and render the assistant fallback
  /// text from [AiConversationNode.message].
  final AiSeminarRunCardMeta? seminarRunCard;

  bool get isEmpty =>
      (model == null || model!.isEmpty) &&
      inputTokens == null &&
      outputTokens == null &&
      seminarRunCard == null;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (model != null && model!.isNotEmpty) map['model'] = model;
    if (inputTokens != null) map['inputTokens'] = inputTokens;
    if (outputTokens != null) map['outputTokens'] = outputTokens;
    if (seminarRunCard != null) {
      map['seminarRunCard'] = seminarRunCard!.toJson();
    }
    return map;
  }

  factory AiSegmentMeta.fromJson(Map<String, dynamic> json) {
    final rawIn = json['inputTokens'];
    final rawOut = json['outputTokens'];
    final rawSeminarRunCard = json['seminarRunCard'];
    return AiSegmentMeta(
      model: json['model']?.toString(),
      inputTokens: rawIn is int ? rawIn : (rawIn is num ? rawIn.toInt() : null),
      outputTokens:
          rawOut is int ? rawOut : (rawOut is num ? rawOut.toInt() : null),
      seminarRunCard: rawSeminarRunCard is Map
          ? AiSeminarRunCardMeta.fromJson(
              rawSeminarRunCard.map((k, v) => MapEntry(k.toString(), v)),
            )
          : null,
    );
  }

  /// One-line label for the per-segment footer. Returns '' when nothing to show.
  String footerText() {
    final parts = <String>[];
    if (model != null && model!.isNotEmpty) {
      parts.add(model!);
    }
    if (inputTokens != null || outputTokens != null) {
      final total = (inputTokens ?? 0) + (outputTokens ?? 0);
      final detail = StringBuffer('${_formatTokenCount(total)} tok');
      if (inputTokens != null && outputTokens != null) {
        detail.write(' ($inputTokens in / $outputTokens out)');
      }
      parts.add(detail.toString());
    }
    return parts.join(' · ');
  }

  static String _formatTokenCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}

@immutable
class AiSeminarRunCardEvidenceSnapshot {
  const AiSeminarRunCardEvidenceSnapshot({
    this.id,
    required this.title,
    required this.snippet,
    this.sourceRef,
  });

  final String? id;
  final String title;
  final String snippet;
  final SourceRef? sourceRef;

  bool get isEmpty =>
      (id == null || id!.trim().isEmpty) &&
      title.trim().isEmpty &&
      snippet.trim().isEmpty &&
      (sourceRef == null || !sourceRef!.hasEvidence);

  Map<String, dynamic> toJson() => {
        if (id != null && id!.trim().isNotEmpty) 'id': id!.trim(),
        if (title.trim().isNotEmpty) 'title': title.trim(),
        if (snippet.trim().isNotEmpty) 'snippet': snippet.trim(),
        if (sourceRef != null && sourceRef!.hasEvidence)
          'sourceRef': sourceRef!.toSafeJson(),
      };

  factory AiSeminarRunCardEvidenceSnapshot.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawSourceRef = json['sourceRef'];
    return AiSeminarRunCardEvidenceSnapshot(
      id: _trimmedOrNull(json['id']),
      title: json['title']?.toString().trim() ?? '',
      snippet: json['snippet']?.toString().trim() ?? '',
      sourceRef: rawSourceRef is Map
          ? SourceRef.fromJson(
              rawSourceRef.map((key, value) => MapEntry(key.toString(), value)),
            )
          : null,
    );
  }

  static String? _trimmedOrNull(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }
}

@immutable
class AiSeminarRunCardRoleSummary {
  const AiSeminarRunCardRoleSummary({
    required this.roleId,
    required this.label,
    required this.summary,
    this.evidenceRefs = const <AiSeminarRunCardEvidenceSnapshot>[],
  });

  final String roleId;
  final String label;
  final String summary;
  final List<AiSeminarRunCardEvidenceSnapshot> evidenceRefs;

  bool get isEmpty =>
      roleId.trim().isEmpty &&
      label.trim().isEmpty &&
      summary.trim().isEmpty &&
      evidenceRefs.where((item) => !item.isEmpty).isEmpty;

  Map<String, dynamic> toJson() => {
        if (roleId.trim().isNotEmpty) 'roleId': roleId.trim(),
        if (label.trim().isNotEmpty) 'label': label.trim(),
        if (summary.trim().isNotEmpty) 'summary': summary.trim(),
        if (evidenceRefs.where((item) => !item.isEmpty).isNotEmpty)
          'evidenceRefs': evidenceRefs
              .where((item) => !item.isEmpty)
              .map((item) => item.toJson())
              .toList(growable: false),
      };

  factory AiSeminarRunCardRoleSummary.fromJson(Map<String, dynamic> json) {
    return AiSeminarRunCardRoleSummary(
      roleId: json['roleId']?.toString().trim() ?? '',
      label: json['label']?.toString().trim() ?? '',
      summary: json['summary']?.toString().trim() ?? '',
      evidenceRefs: (json['evidenceRefs'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => AiSeminarRunCardEvidenceSnapshot.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .where((item) => !item.isEmpty)
              .toList(growable: false) ??
          const <AiSeminarRunCardEvidenceSnapshot>[],
    );
  }
}

@immutable
class AiSeminarRunCardDisagreementDetail {
  const AiSeminarRunCardDisagreementDetail({
    required this.text,
    this.agentRunId,
    this.parentRunId,
    this.roleIds = const <String>[],
    this.evidenceRefs = const <AiSeminarRunCardEvidenceSnapshot>[],
  });

  final String text;
  final String? agentRunId;
  final String? parentRunId;
  final List<String> roleIds;
  final List<AiSeminarRunCardEvidenceSnapshot> evidenceRefs;

  bool get isEmpty =>
      text.trim().isEmpty &&
      roleIds.where((item) => item.trim().isNotEmpty).isEmpty &&
      evidenceRefs.where((item) => !item.isEmpty).isEmpty;

  Map<String, dynamic> toJson() => {
        if (text.trim().isNotEmpty) 'text': text.trim(),
        if (agentRunId?.trim().isNotEmpty == true)
          'agentRunId': agentRunId!.trim(),
        if (parentRunId?.trim().isNotEmpty == true)
          'parentRunId': parentRunId!.trim(),
        if (roleIds.where((item) => item.trim().isNotEmpty).isNotEmpty)
          'roleIds': roleIds
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false),
        if (evidenceRefs.where((item) => !item.isEmpty).isNotEmpty)
          'evidenceRefs': evidenceRefs
              .where((item) => !item.isEmpty)
              .map((item) => item.toJson())
              .toList(growable: false),
      };

  factory AiSeminarRunCardDisagreementDetail.fromJson(
    Map<String, dynamic> json,
  ) {
    return AiSeminarRunCardDisagreementDetail(
      text: json['text']?.toString().trim() ?? '',
      agentRunId: json['agentRunId']?.toString().trim(),
      parentRunId: json['parentRunId']?.toString().trim(),
      roleIds: AiSeminarRunCardSnapshot._stringList(json['roleIds']),
      evidenceRefs: (json['evidenceRefs'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => AiSeminarRunCardEvidenceSnapshot.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .where((item) => !item.isEmpty)
              .toList(growable: false) ??
          const <AiSeminarRunCardEvidenceSnapshot>[],
    );
  }
}

@immutable
class AiSeminarRunCardToolCallSnapshot {
  const AiSeminarRunCardToolCallSnapshot({
    this.id,
    this.agentRunId,
    this.parentRunId,
    required this.toolId,
    this.status,
    this.label,
    this.text,
    required this.query,
    required this.resultCount,
    this.startedAt,
    this.completedAt,
    this.roleIds = const <String>[],
    this.actionIds = const <String>[],
    this.evidenceRefs = const <AiSeminarRunCardEvidenceSnapshot>[],
  });

  final String? id;
  final String? agentRunId;
  final String? parentRunId;
  final String toolId;
  final String? status;
  final String? label;
  final String? text;
  final String query;
  final int resultCount;
  final int? startedAt;
  final int? completedAt;
  final List<String> roleIds;
  final List<String> actionIds;
  final List<AiSeminarRunCardEvidenceSnapshot> evidenceRefs;

  bool get isEmpty =>
      (id == null || id!.trim().isEmpty) &&
      (agentRunId == null || agentRunId!.trim().isEmpty) &&
      (parentRunId == null || parentRunId!.trim().isEmpty) &&
      toolId.trim().isEmpty &&
      (status == null || status!.trim().isEmpty) &&
      (label == null || label!.trim().isEmpty) &&
      (text == null || text!.trim().isEmpty) &&
      query.trim().isEmpty &&
      resultCount <= 0 &&
      (startedAt == null || startedAt! <= 0) &&
      (completedAt == null || completedAt! <= 0) &&
      roleIds.where((item) => item.trim().isNotEmpty).isEmpty &&
      actionIds.where((item) => item.trim().isNotEmpty).isEmpty &&
      evidenceRefs.where((item) => !item.isEmpty).isEmpty;

  Map<String, dynamic> toJson() => {
        if (id != null && id!.trim().isNotEmpty) 'id': id!.trim(),
        if (agentRunId != null && agentRunId!.trim().isNotEmpty)
          'agentRunId': agentRunId!.trim(),
        if (parentRunId != null && parentRunId!.trim().isNotEmpty)
          'parentRunId': parentRunId!.trim(),
        if (toolId.trim().isNotEmpty) 'toolId': toolId.trim(),
        if (status != null && status!.trim().isNotEmpty)
          'status': status!.trim(),
        if (label != null && label!.trim().isNotEmpty) 'label': label!.trim(),
        if (text != null && text!.trim().isNotEmpty) 'text': text!.trim(),
        if (query.trim().isNotEmpty) 'query': query.trim(),
        if (resultCount > 0) 'resultCount': resultCount,
        if (startedAt != null && startedAt! > 0) 'startedAt': startedAt,
        if (completedAt != null && completedAt! > 0) 'completedAt': completedAt,
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
        if (evidenceRefs.where((item) => !item.isEmpty).isNotEmpty)
          'evidenceRefs': evidenceRefs
              .where((item) => !item.isEmpty)
              .map((item) => item.toJson())
              .toList(growable: false),
      };

  factory AiSeminarRunCardToolCallSnapshot.fromJson(
    Map<String, dynamic> json,
  ) {
    return AiSeminarRunCardToolCallSnapshot(
      id: _trimmedOrNull(json['id']),
      agentRunId: _trimmedOrNull(json['agentRunId']),
      parentRunId: _trimmedOrNull(json['parentRunId']),
      toolId: json['toolId']?.toString().trim() ?? '',
      status: _trimmedOrNull(json['status']),
      label: _trimmedOrNull(json['label']),
      text: _trimmedOrNull(json['text']),
      query: json['query']?.toString().trim() ?? '',
      resultCount: _nonNegativeInt(json['resultCount']),
      startedAt: _positiveIntOrNull(json['startedAt']),
      completedAt: _positiveIntOrNull(json['completedAt']),
      roleIds: AiSeminarRunCardSnapshot._stringList(json['roleIds']),
      actionIds: AiSeminarRunCardSnapshot._stringList(json['actionIds']),
      evidenceRefs: (json['evidenceRefs'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => AiSeminarRunCardEvidenceSnapshot.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .where((item) => !item.isEmpty)
              .toList(growable: false) ??
          const <AiSeminarRunCardEvidenceSnapshot>[],
    );
  }

  static String? _trimmedOrNull(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static int _nonNegativeInt(Object? raw) {
    if (raw is int) return raw < 0 ? 0 : raw;
    if (raw is num) return raw < 0 ? 0 : raw.toInt();
    final parsed = int.tryParse(raw?.toString() ?? '') ?? 0;
    return parsed < 0 ? 0 : parsed;
  }

  static int? _positiveIntOrNull(Object? raw) {
    final value = _nonNegativeInt(raw);
    return value > 0 ? value : null;
  }
}

@immutable
class AiSeminarRunCardMessagePart {
  const AiSeminarRunCardMessagePart({
    required this.type,
    this.id,
    this.agentRunId,
    this.parentRunId,
    this.roleId,
    this.roleIds = const <String>[],
    this.actionIds = const <String>[],
    this.allowedToolIds = const <String>[],
    this.defaultRoleId,
    this.defaultActionId,
    this.selectedRoleId,
    this.selectedActionId,
    this.draftText,
    this.toolId,
    this.status,
    this.label,
    this.text,
    this.query,
    this.resultCount = 0,
    this.startedAt,
    this.completedAt,
    this.evidenceRefs = const <AiSeminarRunCardEvidenceSnapshot>[],
  });

  final String type;
  final String? id;
  final String? agentRunId;
  final String? parentRunId;
  final String? roleId;
  final List<String> roleIds;
  final List<String> actionIds;
  final List<String> allowedToolIds;
  final String? defaultRoleId;
  final String? defaultActionId;
  final String? selectedRoleId;
  final String? selectedActionId;
  final String? draftText;
  final String? toolId;
  final String? status;
  final String? label;
  final String? text;
  final String? query;
  final int resultCount;
  final int? startedAt;
  final int? completedAt;
  final List<AiSeminarRunCardEvidenceSnapshot> evidenceRefs;

  bool get isEmpty =>
      type.trim().isEmpty &&
      (id == null || id!.trim().isEmpty) &&
      (agentRunId == null || agentRunId!.trim().isEmpty) &&
      (parentRunId == null || parentRunId!.trim().isEmpty) &&
      (roleId == null || roleId!.trim().isEmpty) &&
      roleIds.where((item) => item.trim().isNotEmpty).isEmpty &&
      actionIds.where((item) => item.trim().isNotEmpty).isEmpty &&
      allowedToolIds.where((item) => item.trim().isNotEmpty).isEmpty &&
      (defaultRoleId == null || defaultRoleId!.trim().isEmpty) &&
      (defaultActionId == null || defaultActionId!.trim().isEmpty) &&
      (selectedRoleId == null || selectedRoleId!.trim().isEmpty) &&
      (selectedActionId == null || selectedActionId!.trim().isEmpty) &&
      (draftText == null || draftText!.trim().isEmpty) &&
      (toolId == null || toolId!.trim().isEmpty) &&
      (status == null || status!.trim().isEmpty) &&
      (label == null || label!.trim().isEmpty) &&
      (text == null || text!.trim().isEmpty) &&
      (query == null || query!.trim().isEmpty) &&
      resultCount <= 0 &&
      (startedAt == null || startedAt! <= 0) &&
      (completedAt == null || completedAt! <= 0) &&
      evidenceRefs.where((item) => !item.isEmpty).isEmpty;

  Map<String, dynamic> toJson() => {
        if (type.trim().isNotEmpty) 'type': type.trim(),
        if (id != null && id!.trim().isNotEmpty) 'id': id!.trim(),
        if (agentRunId != null && agentRunId!.trim().isNotEmpty)
          'agentRunId': agentRunId!.trim(),
        if (parentRunId != null && parentRunId!.trim().isNotEmpty)
          'parentRunId': parentRunId!.trim(),
        if (roleId != null && roleId!.trim().isNotEmpty)
          'roleId': roleId!.trim(),
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
        if (defaultRoleId != null && defaultRoleId!.trim().isNotEmpty)
          'defaultRoleId': defaultRoleId!.trim(),
        if (defaultActionId != null && defaultActionId!.trim().isNotEmpty)
          'defaultActionId': defaultActionId!.trim(),
        if (selectedRoleId != null && selectedRoleId!.trim().isNotEmpty)
          'selectedRoleId': selectedRoleId!.trim(),
        if (selectedActionId != null && selectedActionId!.trim().isNotEmpty)
          'selectedActionId': selectedActionId!.trim(),
        if (draftText != null && draftText!.trim().isNotEmpty)
          'draftText': draftText!.trim(),
        if (toolId != null && toolId!.trim().isNotEmpty)
          'toolId': toolId!.trim(),
        if (status != null && status!.trim().isNotEmpty)
          'status': status!.trim(),
        if (label != null && label!.trim().isNotEmpty) 'label': label!.trim(),
        if (text != null && text!.trim().isNotEmpty) 'text': text!.trim(),
        if (query != null && query!.trim().isNotEmpty) 'query': query!.trim(),
        if (resultCount > 0) 'resultCount': resultCount,
        if (startedAt != null && startedAt! > 0) 'startedAt': startedAt,
        if (completedAt != null && completedAt! > 0) 'completedAt': completedAt,
        if (evidenceRefs.where((item) => !item.isEmpty).isNotEmpty)
          'evidenceRefs': evidenceRefs
              .where((item) => !item.isEmpty)
              .map((item) => item.toJson())
              .toList(growable: false),
      };

  factory AiSeminarRunCardMessagePart.fromJson(
    Map<String, dynamic> json,
  ) {
    return AiSeminarRunCardMessagePart(
      type: json['type']?.toString().trim() ?? '',
      id: _trimmedOrNull(json['id']),
      agentRunId: _trimmedOrNull(json['agentRunId']),
      parentRunId: _trimmedOrNull(json['parentRunId']),
      roleId: _trimmedOrNull(json['roleId']),
      roleIds: AiSeminarRunCardSnapshot._stringList(json['roleIds']),
      actionIds: AiSeminarRunCardSnapshot._stringList(json['actionIds']),
      allowedToolIds:
          AiSeminarRunCardSnapshot._stringList(json['allowedToolIds']),
      defaultRoleId: _trimmedOrNull(json['defaultRoleId']),
      defaultActionId: _trimmedOrNull(json['defaultActionId']),
      selectedRoleId: _trimmedOrNull(json['selectedRoleId']),
      selectedActionId: _trimmedOrNull(json['selectedActionId']),
      draftText: _trimmedOrNull(json['draftText']),
      toolId: _trimmedOrNull(json['toolId']),
      status: _trimmedOrNull(json['status']),
      label: _trimmedOrNull(json['label']),
      text: _trimmedOrNull(json['text']),
      query: _trimmedOrNull(json['query']),
      resultCount: _nonNegativeInt(json['resultCount']),
      startedAt: _positiveIntOrNull(json['startedAt']),
      completedAt: _positiveIntOrNull(json['completedAt']),
      evidenceRefs: (json['evidenceRefs'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => AiSeminarRunCardEvidenceSnapshot.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .where((item) => !item.isEmpty)
              .toList(growable: false) ??
          const <AiSeminarRunCardEvidenceSnapshot>[],
    );
  }

  static String? _trimmedOrNull(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static int _nonNegativeInt(Object? raw) {
    if (raw is int) return raw < 0 ? 0 : raw;
    if (raw is num) return raw < 0 ? 0 : raw.toInt();
    final parsed = int.tryParse(raw?.toString() ?? '') ?? 0;
    return parsed < 0 ? 0 : parsed;
  }

  static int? _positiveIntOrNull(Object? raw) {
    final value = _nonNegativeInt(raw);
    return value > 0 ? value : null;
  }
}

@immutable
class AiSeminarRunCardSnapshot {
  const AiSeminarRunCardSnapshot({
    this.evidence = const <AiSeminarRunCardEvidenceSnapshot>[],
    this.toolCalls = const <AiSeminarRunCardToolCallSnapshot>[],
    this.roleSummaries = const <AiSeminarRunCardRoleSummary>[],
    this.messageParts = const <AiSeminarRunCardMessagePart>[],
    this.synthesisSummary,
    this.disagreements = const <String>[],
    this.disagreementDetails = const <AiSeminarRunCardDisagreementDetail>[],
    this.openQuestions = const <String>[],
  });

  final List<AiSeminarRunCardEvidenceSnapshot> evidence;
  final List<AiSeminarRunCardToolCallSnapshot> toolCalls;
  final List<AiSeminarRunCardRoleSummary> roleSummaries;
  final List<AiSeminarRunCardMessagePart> messageParts;
  final String? synthesisSummary;
  final List<String> disagreements;
  final List<AiSeminarRunCardDisagreementDetail> disagreementDetails;
  final List<String> openQuestions;

  bool get isEmpty =>
      evidence.where((item) => !item.isEmpty).isEmpty &&
      toolCalls.where((item) => !item.isEmpty).isEmpty &&
      roleSummaries.where((item) => !item.isEmpty).isEmpty &&
      messageParts.where((item) => !item.isEmpty).isEmpty &&
      (synthesisSummary == null || synthesisSummary!.trim().isEmpty) &&
      disagreements.where((item) => item.trim().isNotEmpty).isEmpty &&
      disagreementDetails.where((item) => !item.isEmpty).isEmpty &&
      openQuestions.where((item) => item.trim().isNotEmpty).isEmpty;

  Map<String, dynamic> toJson() => {
        if (evidence.where((item) => !item.isEmpty).isNotEmpty)
          'evidence': evidence
              .where((item) => !item.isEmpty)
              .map((item) => item.toJson())
              .toList(growable: false),
        if (toolCalls.where((item) => !item.isEmpty).isNotEmpty)
          'toolCalls': toolCalls
              .where((item) => !item.isEmpty)
              .map((item) => item.toJson())
              .toList(growable: false),
        if (roleSummaries.where((item) => !item.isEmpty).isNotEmpty)
          'roleSummaries': roleSummaries
              .where((item) => !item.isEmpty)
              .map((item) => item.toJson())
              .toList(growable: false),
        if (messageParts.where((item) => !item.isEmpty).isNotEmpty)
          'messageParts': messageParts
              .where((item) => !item.isEmpty)
              .map((item) => item.toJson())
              .toList(growable: false),
        if (synthesisSummary != null && synthesisSummary!.trim().isNotEmpty)
          'synthesisSummary': synthesisSummary!.trim(),
        if (disagreements.where((item) => item.trim().isNotEmpty).isNotEmpty)
          'disagreements': disagreements
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false),
        if (disagreementDetails.where((item) => !item.isEmpty).isNotEmpty)
          'disagreementDetails': disagreementDetails
              .where((item) => !item.isEmpty)
              .map((item) => item.toJson())
              .toList(growable: false),
        if (openQuestions.where((item) => item.trim().isNotEmpty).isNotEmpty)
          'openQuestions': openQuestions
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false),
      };

  factory AiSeminarRunCardSnapshot.fromJson(Map<String, dynamic> json) {
    return AiSeminarRunCardSnapshot(
      evidence: (json['evidence'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => AiSeminarRunCardEvidenceSnapshot.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .where((item) => !item.isEmpty)
              .toList(growable: false) ??
          const <AiSeminarRunCardEvidenceSnapshot>[],
      toolCalls: (json['toolCalls'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => AiSeminarRunCardToolCallSnapshot.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .where((item) => !item.isEmpty)
              .toList(growable: false) ??
          const <AiSeminarRunCardToolCallSnapshot>[],
      roleSummaries: (json['roleSummaries'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => AiSeminarRunCardRoleSummary.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .where((item) => !item.isEmpty)
              .toList(growable: false) ??
          const <AiSeminarRunCardRoleSummary>[],
      messageParts: (json['messageParts'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => AiSeminarRunCardMessagePart.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .where((item) => !item.isEmpty)
              .toList(growable: false) ??
          const <AiSeminarRunCardMessagePart>[],
      synthesisSummary: _trimmedOrNull(json['synthesisSummary']),
      disagreements: _stringList(json['disagreements']),
      disagreementDetails: (json['disagreementDetails'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => AiSeminarRunCardDisagreementDetail.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              )
              .where((item) => !item.isEmpty)
              .toList(growable: false) ??
          const <AiSeminarRunCardDisagreementDetail>[],
      openQuestions: _stringList(json['openQuestions']),
    );
  }

  static String? _trimmedOrNull(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const <String>[];
    return raw
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}

@immutable
class AiSeminarRunCardMeta {
  const AiSeminarRunCardMeta({
    required this.question,
    required this.createdAt,
    this.sessionId,
    this.bookId,
    this.sourceRef,
    this.status = 'ready',
    this.roleIds = const <String>[
      'critical',
      'supportive',
      'synthesizer',
    ],
    this.evidenceScopeIds = const <String>['current-book'],
    this.sourceRefCount = 0,
    this.allowWeb = false,
    this.writeRequiresApproval = true,
    int maxRounds = 2,
    this.roleProfiles = const <AiSeminarRoleProfile>[],
    this.snapshot,
  }) : maxRounds = maxRounds <= 0
            ? 2
            : maxRounds > 5
                ? 5
                : maxRounds;

  final String question;
  final String? sessionId;
  final int? bookId;
  final SourceRef? sourceRef;
  final String status;
  final List<String> roleIds;
  final List<String> evidenceScopeIds;
  final int sourceRefCount;
  final bool allowWeb;
  final bool writeRequiresApproval;
  final int maxRounds;
  final List<AiSeminarRoleProfile> roleProfiles;
  final int createdAt;
  final AiSeminarRunCardSnapshot? snapshot;

  AiSeminarRunCardMeta copyWith({
    String? question,
    String? status,
    List<String>? roleIds,
    List<String>? evidenceScopeIds,
    int? maxRounds,
    List<AiSeminarRoleProfile>? roleProfiles,
    int? sourceRefCount,
    AiSeminarRunCardSnapshot? snapshot,
  }) {
    return AiSeminarRunCardMeta(
      question: question ?? this.question,
      sessionId: sessionId,
      bookId: bookId,
      sourceRef: sourceRef,
      status: status ?? this.status,
      roleIds: roleIds ?? this.roleIds,
      evidenceScopeIds: evidenceScopeIds ?? this.evidenceScopeIds,
      sourceRefCount: sourceRefCount ?? this.sourceRefCount,
      allowWeb: allowWeb,
      writeRequiresApproval: writeRequiresApproval,
      maxRounds: maxRounds ?? this.maxRounds,
      roleProfiles: roleProfiles ?? this.roleProfiles,
      createdAt: createdAt,
      snapshot: snapshot ?? this.snapshot,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'question': question,
      if (sessionId != null && sessionId!.trim().isNotEmpty)
        'sessionId': sessionId,
      if (bookId != null) 'bookId': bookId,
      if (sourceRef != null) 'sourceRef': sourceRef!.toJson(),
      'status': status,
      'roleIds': roleIds,
      'evidenceScopeIds': evidenceScopeIds,
      'sourceRefCount': sourceRefCount,
      'allowWeb': allowWeb,
      'writeRequiresApproval': writeRequiresApproval,
      'maxRounds': maxRounds,
      if (roleProfiles.isNotEmpty)
        'roleProfiles': {
          for (final profile in roleProfiles)
            profile.role.asString: profile.toJson(),
        },
      'createdAt': createdAt,
      if (snapshot != null && !snapshot!.isEmpty)
        'snapshot': snapshot!.toJson(),
    };
  }

  factory AiSeminarRunCardMeta.fromJson(Map<String, dynamic> json) {
    final rawBookId = json['bookId'];
    SourceRef? sourceRef;
    final rawSourceRef = json['sourceRef'];
    if (rawSourceRef is Map) {
      sourceRef = SourceRef.fromJson(
        rawSourceRef.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    AiSeminarRunCardSnapshot? snapshot;
    final rawSnapshot = json['snapshot'];
    if (rawSnapshot is Map) {
      final parsedSnapshot = AiSeminarRunCardSnapshot.fromJson(
        rawSnapshot.map((k, v) => MapEntry(k.toString(), v)),
      );
      if (!parsedSnapshot.isEmpty) snapshot = parsedSnapshot;
    }
    return AiSeminarRunCardMeta(
      question: json['question']?.toString() ?? '',
      sessionId: _trimmedOrNull(json['sessionId']),
      bookId: rawBookId is int
          ? rawBookId
          : rawBookId is num
              ? rawBookId.toInt()
              : int.tryParse(rawBookId?.toString() ?? ''),
      sourceRef: sourceRef,
      status: json['status']?.toString() ?? 'ready',
      roleIds: _stringList(
        json['roleIds'],
        fallback: const <String>['critical', 'supportive', 'synthesizer'],
      ),
      evidenceScopeIds: _stringList(
        json['evidenceScopeIds'],
        fallback: const <String>['current-book'],
      ),
      sourceRefCount: _nonNegativeInt(json['sourceRefCount']),
      allowWeb: _boolOrDefault(json['allowWeb'], false),
      writeRequiresApproval:
          _boolOrDefault(json['writeRequiresApproval'], true),
      maxRounds: _supportedMaxRounds(
        _positiveInt(json['maxRounds'], fallback: 2),
      ),
      roleProfiles: _roleProfilesFromJson(json['roleProfiles']),
      createdAt: json['createdAt'] is int ? json['createdAt'] as int : 0,
      snapshot: snapshot,
    );
  }

  static List<AiSeminarRoleProfile> _roleProfilesFromJson(Object? raw) {
    final out = <AiSeminarRoleProfile>[];
    if (raw is Map) {
      for (final entry in raw.entries) {
        final role = AiSeminarRole.fromString(entry.key.toString());
        if (role == null || entry.value is! Map) continue;
        final profile = AiSeminarRoleProfile.fromJson(
          role,
          Map<String, dynamic>.from(entry.value as Map),
        );
        if (profile.hasOverrides) out.add(profile);
      }
    } else if (raw is List) {
      for (final item in raw.whereType<Map>()) {
        final role = AiSeminarRole.fromString(item['role']?.toString());
        if (role == null) continue;
        final profile = AiSeminarRoleProfile.fromJson(
          role,
          Map<String, dynamic>.from(item),
        );
        if (profile.hasOverrides) out.add(profile);
      }
    }
    if (out.isEmpty) return const <AiSeminarRoleProfile>[];
    return List.unmodifiable(out);
  }

  static String? _trimmedOrNull(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static List<String> _stringList(
    Object? raw, {
    required List<String> fallback,
  }) {
    if (raw is! List) return fallback;
    final values = raw
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    return values.isEmpty ? fallback : values;
  }

  static int _nonNegativeInt(Object? raw) {
    final parsed = raw is int
        ? raw
        : raw is num
            ? raw.toInt()
            : int.tryParse(raw?.toString() ?? '');
    if (parsed == null || parsed < 0) return 0;
    return parsed;
  }

  static int _positiveInt(Object? raw, {required int fallback}) {
    final parsed = raw is int
        ? raw
        : raw is num
            ? raw.toInt()
            : int.tryParse(raw?.toString() ?? '');
    if (parsed == null || parsed <= 0) return fallback;
    return parsed;
  }

  static int _supportedMaxRounds(int value) {
    if (value <= 0) return 2;
    return value.clamp(1, 5).toInt();
  }

  static bool _boolOrDefault(Object? raw, bool fallback) {
    if (raw is bool) return raw;
    final text = raw?.toString().trim().toLowerCase();
    if (text == 'true') return true;
    if (text == 'false') return false;
    return fallback;
  }
}
