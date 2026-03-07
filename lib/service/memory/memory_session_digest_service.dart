import 'dart:math' as math;

import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:langchain_core/chat_models.dart';

class MemorySessionDigestDraft {
  const MemorySessionDigestDraft({
    required this.text,
    required this.confidence,
  });

  final String text;
  final double confidence;
}

class MemorySessionDigestService {
  const MemorySessionDigestService();

  static const int defaultMaxCandidates = 3;
  static const int _maxCandidateChars = 420;
  static const int _maxCandidateLines = 4;
  static final RegExp _attachmentHeaderPattern =
      RegExp(r'^\[\[file:[^\]]+\]\]$', multiLine: true);
  static final RegExp _durableKeywordPattern = RegExp(
    r"(记住|记忆|偏好|默认|以后|下次|总是|不要|别再|规则|习惯|决定|结论|待办|todo|follow[ -]?up|prefer|preference|default|always|never|do not|don't|remember|decision|plan|next step|next steps|deadline)",
    caseSensitive: false,
  );
  static final RegExp _genericPattern = RegExp(
    r'^(好的|好啊|收到|谢谢|thanks|thank you|ok|okay|yes|no|哈哈|lol)[.!?\s]*$',
    caseSensitive: false,
  );

  List<MemorySessionDigestDraft> buildCandidates(
    List<ChatMessage> messages, {
    int maxCandidates = defaultMaxCandidates,
  }) {
    if (maxCandidates <= 0 || messages.isEmpty) {
      return const <MemorySessionDigestDraft>[];
    }

    final turns = _extractTurns(messages);
    if (turns.isEmpty) {
      return const <MemorySessionDigestDraft>[];
    }

    turns.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      return b.lastMessageIndex.compareTo(a.lastMessageIndex);
    });

    final selected = <_DigestTurn>[];
    final seen = <String>{};

    for (final turn in turns) {
      if (selected.length >= maxCandidates) break;
      if (turn.score < 0.85 && selected.isNotEmpty) continue;

      final key = _dedupeKey(turn.text);
      if (key.isEmpty || !seen.add(key)) continue;
      selected.add(turn);
    }

    if (selected.isEmpty) {
      for (final turn in turns) {
        if (selected.length >= maxCandidates) break;
        final key = _dedupeKey(turn.text);
        if (key.isEmpty || !seen.add(key)) continue;
        selected.add(turn);
      }
    }

    return selected
        .map(
          (turn) => MemorySessionDigestDraft(
            text: turn.text,
            confidence: turn.confidence,
          ),
        )
        .toList(growable: false);
  }

  List<_DigestTurn> _extractTurns(List<ChatMessage> messages) {
    final turns = <_DigestTurn>[];
    String? currentUser;
    int? currentUserIndex;
    String? currentAssistant;
    int? currentAssistantIndex;

    void flush() {
      final turn = _buildTurn(
        userText: currentUser,
        userIndex: currentUserIndex,
        assistantText: currentAssistant,
        assistantIndex: currentAssistantIndex,
      );
      if (turn != null) {
        turns.add(turn);
      }
      currentUser = null;
      currentUserIndex = null;
      currentAssistant = null;
      currentAssistantIndex = null;
    }

    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      if (message is HumanChatMessage) {
        flush();
        final text = _normalizeUserText(message);
        if (text.isNotEmpty) {
          currentUser = text;
          currentUserIndex = i;
        }
        continue;
      }

      if (message is AIChatMessage) {
        final text = _normalizeAssistantText(message);
        if (text.isEmpty) continue;

        if (currentUser != null) {
          currentAssistant = text;
          currentAssistantIndex = i;
        } else {
          final standalone = _buildTurn(
            assistantText: text,
            assistantIndex: i,
          );
          if (standalone != null) {
            turns.add(standalone);
          }
        }
      }
    }

    flush();
    return turns;
  }

  _DigestTurn? _buildTurn({
    String? userText,
    int? userIndex,
    String? assistantText,
    int? assistantIndex,
  }) {
    final normalizedUser = (userText ?? '').trim();
    final normalizedAssistant = (assistantText ?? '').trim();
    if (normalizedUser.isEmpty && normalizedAssistant.isEmpty) {
      return null;
    }

    final userScore = _scoreUserText(normalizedUser);
    final assistantScore = _scoreAssistantText(normalizedAssistant);
    final userDurable = _looksDurable(normalizedUser);

    String chosen;
    double score;

    if (normalizedAssistant.isNotEmpty &&
        (!userDurable || assistantScore >= userScore)) {
      chosen = normalizedAssistant;
      score = assistantScore;
    } else if (normalizedUser.isNotEmpty) {
      chosen = normalizedUser;
      score = userScore;
    } else {
      chosen = normalizedAssistant;
      score = assistantScore;
    }

    if (chosen.trim().isEmpty) {
      return null;
    }

    final lastIndex = math.max(userIndex ?? -1, assistantIndex ?? -1);
    return _DigestTurn(
      text: chosen,
      lastMessageIndex: lastIndex,
      score: score,
      confidence: _scoreToConfidence(score),
    );
  }

  String _normalizeUserText(HumanChatMessage message) {
    return _cleanText(message.contentAsString);
  }

  String _normalizeAssistantText(AIChatMessage message) {
    final plain = reasoningContentToPlainText(message.contentAsString);
    return _cleanText(plain);
  }

  String _cleanText(String input) {
    var text = input.replaceAll(_attachmentHeaderPattern, ' ');
    text = text.replaceAll(RegExp(r'\r\n?'), '\n');
    text = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(_maxCandidateLines)
        .join('\n');

    if (text.length > _maxCandidateChars) {
      text = '${text.substring(0, _maxCandidateChars - 3).trimRight()}...';
    }

    return text.trim();
  }

  double _scoreUserText(String text) {
    if (text.isEmpty) return -1;

    var score = 0.3;
    final length = text.length;
    if (length >= 18 && length <= 220) {
      score += 0.8;
    } else if (length <= 8) {
      score -= 0.8;
    } else if (length > 500) {
      score -= 0.4;
    }

    if (_looksDurable(text)) {
      score += 1.8;
    }
    if (_looksQuestionOnly(text)) {
      score -= 0.9;
    }
    if (_genericPattern.hasMatch(text)) {
      score -= 1.4;
    }
    return score;
  }

  double _scoreAssistantText(String text) {
    if (text.isEmpty) return -1;

    var score = 0.5;
    final length = text.length;
    if (length >= 24 && length <= 320) {
      score += 0.9;
    } else if (length <= 10) {
      score -= 0.8;
    } else if (length > 550) {
      score -= 0.5;
    }

    if (_looksDurable(text)) {
      score += 1.2;
    }
    if (text.contains('\n- ') || text.contains('\n1.')) {
      score += 0.3;
    }
    if (_looksQuestionOnly(text)) {
      score -= 0.6;
    }
    if (_genericPattern.hasMatch(text)) {
      score -= 1.2;
    }
    return score;
  }

  bool _looksDurable(String text) {
    if (text.isEmpty) return false;
    return _durableKeywordPattern.hasMatch(text);
  }

  bool _looksQuestionOnly(String text) {
    if (text.isEmpty) return false;
    if (_looksDurable(text)) return false;
    final compact = text.replaceAll('\n', ' ').trim();
    return compact.endsWith('?') || compact.endsWith('？');
  }

  String _dedupeKey(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  double _scoreToConfidence(double score) {
    final normalized = ((score + 1.0) / 4.0).clamp(0.2, 0.95);
    return (normalized * 100).roundToDouble() / 100;
  }
}

class _DigestTurn {
  const _DigestTurn({
    required this.text,
    required this.lastMessageIndex,
    required this.score,
    required this.confidence,
  });

  final String text;
  final int lastMessageIndex;
  final double score;
  final double confidence;
}
