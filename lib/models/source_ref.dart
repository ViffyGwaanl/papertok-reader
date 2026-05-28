import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

enum SourceRefKind {
  reader('reader'),
  currentBookRag('current-book-rag'),
  libraryRag('library-rag'),
  note('note'),
  highlight('highlight'),
  memory('memory'),
  conversation('conversation'),
  external('external'),
  unknown('unknown');

  const SourceRefKind(this.asString);

  final String asString;

  static SourceRefKind fromString(String? value) {
    for (final kind in SourceRefKind.values) {
      if (kind.asString == value) return kind;
    }
    return SourceRefKind.unknown;
  }
}

enum AiOutputOwnership {
  aiGeneratedDraft('AI-generated-draft'),
  aiGeneratedApproved('AI-generated-approved'),
  userAuthored('user-authored'),
  derivedCache('derived-cache'),
  sourceOfTruth('source-of-truth');

  const AiOutputOwnership(this.asString);

  final String asString;

  static AiOutputOwnership fromString(String? value) {
    for (final ownership in AiOutputOwnership.values) {
      if (ownership.asString == value) return ownership;
    }
    return AiOutputOwnership.aiGeneratedDraft;
  }
}

enum AiProvenanceDataClass {
  userAsset('user-asset'),
  derivedCache('derived-cache'),
  sourceOfTruth('source-of-truth'),
  secret('secret'),
  external('external'),
  unknown('unknown');

  const AiProvenanceDataClass(this.asString);

  final String asString;

  static AiProvenanceDataClass fromString(String? value) {
    for (final dataClass in AiProvenanceDataClass.values) {
      if (dataClass.asString == value) return dataClass;
    }
    return AiProvenanceDataClass.unknown;
  }
}

@immutable
class SourceRef {
  factory SourceRef({
    int? bookId,
    String? href,
    String? cfi,
    int? chunkId,
    String? jumpLink,
    String? sourceTitle,
    String? locationLabel,
    String? sourceTextSnippet,
    String? sourceTextForHash,
    String? sourceHash,
    String? modelId,
    String? algorithmVersion,
    int? createdAt,
    SourceRefKind sourceKind = SourceRefKind.unknown,
    double? confidence,
    String? unavailableReason,
  }) {
    final normalizedSnippet = _normalizeSnippet(sourceTextSnippet);
    return SourceRef._(
      bookId: bookId,
      href: _blankToNull(href),
      cfi: _blankToNull(cfi),
      chunkId: chunkId,
      jumpLink: _blankToNull(jumpLink),
      sourceTitle: _blankToNull(sourceTitle),
      locationLabel: _blankToNull(locationLabel),
      sourceTextSnippet: normalizedSnippet,
      sourceHash: _blankToNull(sourceHash) ??
          _deriveHash(
            bookId: bookId,
            href: href,
            cfi: cfi,
            sourceKind: sourceKind,
            sourceText: sourceTextForHash ?? sourceTextSnippet,
          ),
      modelId: _blankToNull(modelId),
      algorithmVersion: _blankToNull(algorithmVersion),
      createdAt: createdAt,
      sourceKind: sourceKind,
      confidence: confidence,
      unavailableReason: _blankToNull(unavailableReason),
    );
  }

  const SourceRef._({
    required this.bookId,
    required this.href,
    required this.cfi,
    required this.chunkId,
    required this.jumpLink,
    required this.sourceTitle,
    required this.locationLabel,
    required this.sourceTextSnippet,
    required this.sourceHash,
    required this.modelId,
    required this.algorithmVersion,
    required this.createdAt,
    required this.sourceKind,
    required this.confidence,
    required this.unavailableReason,
  });

  static const int maxSnippetChars = 500;

  final int? bookId;
  final String? href;
  final String? cfi;

  /// Optional retrieval hint into ai_index.db.
  ///
  /// `ai_index.db` is a rebuildable cache, so this value must never be treated
  /// as the durable identity of a user asset.
  final int? chunkId;

  final String? jumpLink;
  final String? sourceTitle;
  final String? locationLabel;
  final String? sourceTextSnippet;
  final String? sourceHash;
  final String? modelId;
  final String? algorithmVersion;
  final int? createdAt;
  final SourceRefKind sourceKind;
  final double? confidence;
  final String? unavailableReason;

  bool get hasBookAnchor =>
      bookId != null &&
      bookId! > 0 &&
      ((href != null && href!.isNotEmpty) || (cfi != null && cfi!.isNotEmpty));

  bool get canJumpBack {
    final link = jumpLink?.trim();
    if (link == null || link.isEmpty) return false;
    final uri = Uri.tryParse(link);
    if (uri == null) return false;
    if (uri.scheme.toLowerCase() != 'paperreader') return false;
    if (uri.host.toLowerCase() != 'reader') return false;
    final segment = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    if (segment.toLowerCase() != 'open') return false;
    final bookId = int.tryParse(uri.queryParameters['bookId'] ?? '');
    if (bookId == null || bookId <= 0) return false;
    final href = uri.queryParameters['href']?.trim() ?? '';
    final cfi = uri.queryParameters['cfi']?.trim() ?? '';
    return href.isNotEmpty || cfi.isNotEmpty;
  }

  bool get hasUnavailableReason =>
      unavailableReason != null && unavailableReason!.isNotEmpty;

  bool get hasEvidence => hasBookAnchor || canJumpBack || hasUnavailableReason;

  bool get hasHashOnlyFingerprint =>
      !hasEvidence && sourceHash != null && sourceHash!.isNotEmpty;

  bool get hasDerivedChunkHint =>
      chunkId != null &&
      (sourceKind == SourceRefKind.currentBookRag ||
          sourceKind == SourceRefKind.libraryRag);

  Map<String, dynamic> toJson() => toSafeJson();

  Map<String, dynamic> toSafeJson() {
    return {
      if (bookId != null) 'bookId': bookId,
      if (href != null) 'href': href,
      if (cfi != null) 'cfi': cfi,
      if (chunkId != null) 'chunkId': chunkId,
      if (jumpLink != null) 'jumpLink': jumpLink,
      if (sourceTitle != null) 'sourceTitle': sourceTitle,
      if (locationLabel != null) 'locationLabel': locationLabel,
      if (sourceTextSnippet != null) 'sourceTextSnippet': sourceTextSnippet,
      if (sourceHash != null) 'sourceHash': sourceHash,
      if (modelId != null) 'modelId': modelId,
      if (algorithmVersion != null) 'algorithmVersion': algorithmVersion,
      if (createdAt != null) 'createdAt': createdAt,
      'sourceKind': sourceKind.asString,
      if (confidence != null) 'confidence': confidence,
      if (unavailableReason != null) 'unavailableReason': unavailableReason,
      if (hasDerivedChunkHint) 'derivedCacheHint': true,
    };
  }

  factory SourceRef.fromJson(Map<String, dynamic> json) {
    return SourceRef(
      bookId: (json['bookId'] as num?)?.toInt(),
      href: json['href']?.toString(),
      cfi: json['cfi']?.toString(),
      chunkId: (json['chunkId'] as num?)?.toInt(),
      jumpLink: json['jumpLink']?.toString(),
      sourceTitle: json['sourceTitle']?.toString(),
      locationLabel: json['locationLabel']?.toString(),
      sourceTextSnippet: json['sourceTextSnippet']?.toString(),
      sourceHash: json['sourceHash']?.toString(),
      modelId: json['modelId']?.toString(),
      algorithmVersion: json['algorithmVersion']?.toString(),
      createdAt: (json['createdAt'] as num?)?.toInt(),
      sourceKind: SourceRefKind.fromString(json['sourceKind']?.toString()),
      confidence: (json['confidence'] as num?)?.toDouble(),
      unavailableReason: json['unavailableReason']?.toString(),
    );
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  static String? _normalizeSnippet(String? value) {
    final trimmed = _blankToNull(value);
    if (trimmed == null) return null;
    if (trimmed.length <= maxSnippetChars) return trimmed;
    return '${trimmed.substring(0, maxSnippetChars - 3)}...';
  }

  static String? _deriveHash({
    required int? bookId,
    required String? href,
    required String? cfi,
    required SourceRefKind sourceKind,
    required String? sourceText,
  }) {
    final normalizedText = _blankToNull(sourceText);
    final normalizedHref = _blankToNull(href);
    final normalizedCfi = _blankToNull(cfi);
    if (bookId == null &&
        normalizedHref == null &&
        normalizedCfi == null &&
        normalizedText == null) {
      return null;
    }
    final parts = <String>[
      'book=${bookId ?? ''}',
      'href=${normalizedHref ?? ''}',
      'cfi=${normalizedCfi ?? ''}',
      'kind=${sourceKind.asString}',
      'text=${normalizedText ?? ''}',
    ];
    return 'sha256:${sha256.convert(utf8.encode(parts.join('\u001f')))}';
  }
}

@immutable
class AiProvenance {
  const AiProvenance({
    this.ownership = AiOutputOwnership.aiGeneratedDraft,
    this.dataClass = AiProvenanceDataClass.derivedCache,
    this.sourceRefs = const <SourceRef>[],
    this.modelInferred = false,
    this.unavailableReason,
  });

  final AiOutputOwnership ownership;
  final AiProvenanceDataClass dataClass;
  final List<SourceRef> sourceRefs;
  final bool modelInferred;
  final String? unavailableReason;

  bool get hasEvidence => sourceRefs.any((ref) => ref.hasEvidence);

  bool get canEnterFormalKnowledge =>
      hasEvidence &&
      ownership != AiOutputOwnership.aiGeneratedDraft &&
      (dataClass == AiProvenanceDataClass.userAsset ||
          dataClass == AiProvenanceDataClass.sourceOfTruth);

  Map<String, dynamic> toJson() => toSafeJson();

  Map<String, dynamic> toSafeJson() {
    return {
      'ownership': ownership.asString,
      'dataClass': dataClass.asString,
      'sourceRefs': sourceRefs.map((ref) => ref.toSafeJson()).toList(),
      'modelInferred': modelInferred,
      if (unavailableReason != null) 'unavailableReason': unavailableReason,
    };
  }

  factory AiProvenance.fromJson(Map<String, dynamic> json) {
    final refs = (json['sourceRefs'] as List?)
            ?.whereType<Map>()
            .map((e) => SourceRef.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false) ??
        const <SourceRef>[];
    return AiProvenance(
      ownership: AiOutputOwnership.fromString(json['ownership']?.toString()),
      dataClass:
          AiProvenanceDataClass.fromString(json['dataClass']?.toString()),
      sourceRefs: refs,
      modelInferred: json['modelInferred'] == true,
      unavailableReason: json['unavailableReason']?.toString(),
    );
  }
}
