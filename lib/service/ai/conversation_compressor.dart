import 'dart:async';

import 'package:anx_reader/utils/log/common.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:langchain_core/prompts.dart';

/// LLM-based conversation compressor.
///
/// Instead of simply truncating old messages (which loses information),
/// this uses the LLM itself to generate a summary of the conversation
/// so far, preserving semantic content while reducing token count.
///
/// Inspired by Claude Code's `autoCompact.ts`.
class ConversationCompressor {
  const ConversationCompressor();

  /// Context usage ratio above which compression is triggered.
  static const double triggerThreshold = 0.85;

  /// Maximum output tokens for the summary generation call.
  static const int maxSummaryOutputTokens = 4000;

  /// Number of recent messages to keep verbatim after compression.
  static const int keepRecentMessages = 10;

  /// Stop attempting after this many consecutive failures.
  static const int maxConsecutiveFailures = 3;

  /// Check whether the conversation should be compressed.
  bool shouldCompress({
    required int estimatedTokens,
    required int contextWindowSize,
    required int consecutiveFailures,
  }) {
    if (consecutiveFailures >= maxConsecutiveFailures) return false;
    if (contextWindowSize <= 0) return false;
    return estimatedTokens / contextWindowSize > triggerThreshold;
  }

  /// Compress the conversation by summarising old messages.
  ///
  /// Returns a new message list: [summaryMessage] + recent messages.
  /// The [model] is used to generate the summary.
  Future<ConversationCompressionResult> compress({
    required List<ChatMessage> messages,
    required BaseChatModel model,
    String languageHint = 'English',
  }) async {
    if (messages.length <= keepRecentMessages + 2) {
      return ConversationCompressionResult(
        messages: messages,
        compressed: false,
        summaryTokens: 0,
      );
    }

    final splitIndex = messages.length - keepRecentMessages;
    final oldMessages = messages.sublist(0, splitIndex);
    final recentMessages = messages.sublist(splitIndex);

    try {
      final summaryPrompt = _buildSummaryPrompt(oldMessages, languageHint);
      final result = await model.invoke(PromptValue.string(summaryPrompt));
      final summary = result.output.content.trim();

      if (summary.isEmpty) {
        return ConversationCompressionResult(
          messages: messages,
          compressed: false,
          summaryTokens: 0,
        );
      }

      final summaryMessage = ChatMessage.system(
        '[Conversation Summary]\n'
        'The following is a summary of the conversation so far:\n\n'
        '$summary\n\n'
        '[End of Summary — recent messages follow]',
      );

      final compressed = <ChatMessage>[summaryMessage, ...recentMessages];

      AnxLog.info(
        'ConversationCompressor: compressed ${oldMessages.length} messages '
        'into summary (${summary.length} chars), keeping $keepRecentMessages recent',
      );

      return ConversationCompressionResult(
        messages: compressed,
        compressed: true,
        summaryTokens: _estimateTokens(summary),
      );
    } catch (e) {
      AnxLog.warning('ConversationCompressor: failed to compress: $e');
      return ConversationCompressionResult(
        messages: messages,
        compressed: false,
        summaryTokens: 0,
      );
    }
  }

  String _buildSummaryPrompt(
    List<ChatMessage> messages,
    String languageHint,
  ) {
    final buffer = StringBuffer();
    buffer.writeln(
      'Please summarise the following conversation in $languageHint. '
      'Preserve all important facts, decisions, tool results, and context '
      'that would be needed to continue the conversation. '
      'Be concise but thorough. Output only the summary, no preamble.',
    );
    buffer.writeln();

    for (final msg in messages) {
      final role = switch (msg) {
        final HumanChatMessage _ => 'User',
        final AIChatMessage _ => 'Assistant',
        final SystemChatMessage _ => 'System',
        final ToolChatMessage _ => 'Tool',
        _ => 'Unknown',
      };
      final content = msg.contentAsString;
      if (content.trim().isNotEmpty) {
        // Truncate very long messages to avoid exceeding input limits
        final truncated = content.length > 2000
            ? '${content.substring(0, 2000)}... [truncated]'
            : content;
        buffer.writeln('$role: $truncated');
      }
    }

    return buffer.toString();
  }

  int _estimateTokens(String text) => (text.length / 3.5).ceil();
}

class ConversationCompressionResult {
  const ConversationCompressionResult({
    required this.messages,
    required this.compressed,
    required this.summaryTokens,
  });

  final List<ChatMessage> messages;
  final bool compressed;
  final int summaryTokens;
}
