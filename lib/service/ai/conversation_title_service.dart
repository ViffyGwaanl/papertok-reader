import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/ai_provider_meta.dart';
import 'package:anx_reader/service/ai/ai_services.dart';
import 'package:anx_reader/service/ai/index.dart';
import 'package:langchain_core/chat_models.dart';

class ConversationTitleService {
  const ConversationTitleService();

  Future<String> generateTitle(List<ChatMessage> messages) async {
    final fallback = deriveFallbackTitle(messages);
    final prefs = Prefs();
    if (!prefs.aiTitleGenerationEnabled) {
      return _truncate(fallback, prefs.aiTitleMaxChars);
    }

    final providerId = prefs.aiTitleProviderIdEffective;
    final provider = prefs.getAiProviderMeta(providerId);
    if (provider == null || !provider.enabled) {
      return _truncate(fallback, prefs.aiTitleMaxChars);
    }

    final transcript = _buildTranscript(messages);
    if (transcript.isEmpty) {
      return _truncate(fallback, prefs.aiTitleMaxChars);
    }

    final config = <String, String>{...prefs.getAiConfig(providerId)};
    final titleModel = prefs.aiTitleModel.trim();
    if (titleModel.isNotEmpty) {
      config['model'] = titleModel;
    } else if ((config['model'] ?? '').trim().isEmpty) {
      final defaultModel = _defaultModelForProvider(provider);
      if (defaultModel.isNotEmpty) {
        config['model'] = defaultModel;
      }
    }

    final prompt = _titlePrompt(prefs.aiTitleMaxChars);
    try {
      final stream = aiGenerateStream(
        [
          ChatMessage.system(prompt),
          ChatMessage.humanText(transcript),
        ],
        identifier: providerId,
        config: config,
        useAgent: false,
      );

      var latest = '';
      await for (final chunk in stream) {
        latest = chunk;
      }

      final sanitized = _sanitizeTitle(latest, prefs.aiTitleMaxChars);
      if (sanitized.isNotEmpty) {
        return sanitized;
      }
    } catch (_) {
      // Fall back to heuristic title.
    }

    return _truncate(fallback, prefs.aiTitleMaxChars);
  }

  String deriveFallbackTitle(List<ChatMessage> messages) {
    for (final message in messages) {
      if (message is! HumanChatMessage) {
        continue;
      }
      final text = _plainText(message.content).trim();
      if (text.isEmpty) {
        continue;
      }
      final firstLine = text.split('\n').first.trim();
      if (firstLine.isNotEmpty) {
        return _sanitizeTitle(firstLine, Prefs().aiTitleMaxChars);
      }
    }
    return 'Conversation';
  }

  String _buildTranscript(List<ChatMessage> messages) {
    final lines = <String>[];
    for (final message in messages) {
      late final String role;
      late final String text;
      if (message is HumanChatMessage) {
        role = 'User';
        text = _plainText(message.content).trim();
      } else if (message is AIChatMessage) {
        role = 'Assistant';
        text = message.contentAsString.trim();
      } else {
        role = 'Message';
        text = message.contentAsString.trim();
      }
      if (text.isEmpty) continue;
      lines.add('$role: $text');
      if (lines.length >= 8) {
        break;
      }
    }

    final joined = lines.join('\n');
    if (joined.length <= 1600) {
      return joined;
    }
    return joined.substring(0, 1600);
  }

  String _plainText(ChatMessageContent content) {
    if (content is ChatMessageContentText) {
      return content.text;
    }
    if (content is ChatMessageContentMultiModal) {
      return content.parts
          .whereType<ChatMessageContentText>()
          .map((e) => e.text)
          .join('\n');
    }
    return content.toString();
  }

  String _titlePrompt(int maxChars) {
    return 'Generate a concise conversation title in the same language as the conversation. '
        'Return only the title text, no quotes, no punctuation at the end, and keep it under $maxChars characters.';
  }

  String _sanitizeTitle(String raw, int maxChars) {
    final firstLine = raw
        .replaceAll(RegExp(r'[`#*_]+'), ' ')
        .replaceAll(RegExp(r'^title\s*[:：]\s*', caseSensitive: false), '')
        .split('\n')
        .first
        .trim();
    final collapsed = firstLine.replaceAll(RegExp(r'\s+'), ' ').trim();
    final withoutQuotes = collapsed
        .replaceAll(RegExp("^[\"'“”‘’]+"), '')
        .replaceAll(RegExp("[\"'“”‘’]+\$"), '')
        .trim();
    final withoutTailPunctuation =
        withoutQuotes.replaceAll(RegExp(r'[。！？!?,，、;；:：]+$'), '').trim();
    if (withoutTailPunctuation.isEmpty) {
      return '';
    }
    return _truncate(withoutTailPunctuation, maxChars);
  }

  String _truncate(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    return text.substring(0, maxChars).trim();
  }

  String _defaultModelForProvider(AiProviderMeta provider) {
    final builtIns = buildDefaultAiServices();
    for (final option in builtIns) {
      if (option.identifier == provider.id) {
        return option.defaultModel;
      }
    }
    return '';
  }
}
