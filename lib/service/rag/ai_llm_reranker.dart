import 'dart:math' as math;

import 'package:papertok_reader/service/ai/ai_structured_generation_service.dart';
import 'package:papertok_reader/service/rag/semantic_search_library.dart';

class AiLlmReranker {
  const AiLlmReranker({
    this.structuredGeneration = const AiStructuredGenerationService(),
    this.providerId,
    this.config,
    this.timeout = const Duration(seconds: 12),
    this.maxCandidates = 40,
  });

  final AiStructuredGenerationService structuredGeneration;
  final String? providerId;
  final Map<String, String>? config;
  final Duration timeout;
  final int maxCandidates;

  Future<List<double>> rerank(
    String query,
    List<AiSemanticSearchLibraryRerankCandidate> candidates,
  ) async {
    if (candidates.isEmpty) return const [];

    final fallback = candidates.map((c) => c.score).toList(growable: false);
    final limit = maxCandidates.clamp(1, candidates.length);
    final visible = candidates.take(limit).toList(growable: false);

    try {
      final json = await structuredGeneration.generateJson(
        systemPrompt: _systemPrompt,
        userPrompt: _userPrompt(query, visible),
        providerId: providerId,
        config: config,
        timeout: timeout,
      );
      final rawScores = json['scores'];
      if (rawScores is! List || rawScores.length != visible.length) {
        return fallback;
      }

      final next = List<double>.from(fallback);
      for (var i = 0; i < rawScores.length; i++) {
        final raw = rawScores[i];
        if (raw is! num) return fallback;
        next[i] = raw.toDouble().clamp(0.0, 1.0);
      }
      return next;
    } catch (_) {
      return fallback;
    }
  }

  static const String _systemPrompt = '''
You are a retrieval reranker.
Given a user query and candidate passages, return JSON only:
{"scores":[number,...]}
Each score must be between 0 and 1, in the same order as the candidates.
Judge direct answer usefulness, not writing quality.
''';

  String _userPrompt(
    String query,
    List<AiSemanticSearchLibraryRerankCandidate> candidates,
  ) {
    final buffer = StringBuffer()
      ..writeln('Query:')
      ..writeln(query)
      ..writeln()
      ..writeln('Candidates:');
    for (var i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      buffer
        ..writeln('Candidate ${i + 1}')
        ..writeln('BookId: ${c.bookId}')
        ..writeln('Href: ${c.href}')
        ..writeln('Anchor: ${c.anchor}')
        ..writeln('CurrentScore: ${c.score.toStringAsFixed(4)}')
        ..writeln('Text:')
        ..writeln(_truncate(c.text, 1200))
        ..writeln();
    }
    return buffer.toString();
  }

  String _truncate(String text, int maxChars) {
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= maxChars) return compact;
    return '${compact.substring(0, math.max(0, maxChars)).trim()}...';
  }
}
