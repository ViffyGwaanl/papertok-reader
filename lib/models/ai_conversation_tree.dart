import 'package:flutter/foundation.dart';
import 'package:langchain_core/chat_models.dart';
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
    this.maxRounds = 2,
  });

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
  final int createdAt;

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
      'createdAt': createdAt,
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
      maxRounds: _positiveInt(json['maxRounds'], fallback: 2),
      createdAt: json['createdAt'] is int ? json['createdAt'] as int : 0,
    );
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

  static bool _boolOrDefault(Object? raw, bool fallback) {
    if (raw is bool) return raw;
    final text = raw?.toString().trim().toLowerCase();
    if (text == 'true') return true;
    if (text == 'false') return false;
    return fallback;
  }
}
