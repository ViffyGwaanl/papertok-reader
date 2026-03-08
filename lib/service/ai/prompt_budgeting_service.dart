import 'dart:math' as math;

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/ai_model_capability.dart';
import 'package:langchain_core/chat_models.dart';

class PromptBudgetResult {
  const PromptBudgetResult({
    required this.messages,
    required this.trimmed,
    required this.estimatedTokens,
    required this.reservedOutputTokens,
    required this.contextWindow,
  });

  final List<ChatMessage> messages;
  final bool trimmed;
  final int estimatedTokens;
  final int reservedOutputTokens;
  final int? contextWindow;
}

class PromptBudgetingService {
  const PromptBudgetingService();

  PromptBudgetResult trimMessages({
    required String providerId,
    required Map<String, String> config,
    required List<ChatMessage> messages,
  }) {
    final capability = _resolveCapability(providerId, config['model'] ?? '');
    final contextWindow = capability?.contextWindow;
    final reservedOutputTokens = _reservedOutputTokens(
        config, capability?.maxOutputTokens, contextWindow);

    if (contextWindow == null || contextWindow <= 0) {
      return PromptBudgetResult(
        messages: messages,
        trimmed: false,
        estimatedTokens: _estimateMessages(messages),
        reservedOutputTokens: reservedOutputTokens,
        contextWindow: contextWindow,
      );
    }

    final targetBudget =
        math.max(512, (contextWindow * 0.9).floor() - reservedOutputTokens);
    final next = List<ChatMessage>.from(messages);
    var trimmed = false;

    while (_estimateMessages(next) > targetBudget && next.length > 4) {
      next.removeAt(0);
      trimmed = true;
    }

    return PromptBudgetResult(
      messages: next,
      trimmed: trimmed,
      estimatedTokens: _estimateMessages(next),
      reservedOutputTokens: reservedOutputTokens,
      contextWindow: contextWindow,
    );
  }

  int _reservedOutputTokens(
    Map<String, String> config,
    int? capabilityMaxOutputTokens,
    int? contextWindow,
  ) {
    final maxOutput = int.tryParse((config['max_output_tokens'] ?? '').trim());
    if (maxOutput != null && maxOutput > 0) {
      return maxOutput;
    }
    final maxTokens = int.tryParse((config['max_tokens'] ?? '').trim());
    if (maxTokens != null && maxTokens > 0) {
      return maxTokens;
    }
    if (capabilityMaxOutputTokens != null && capabilityMaxOutputTokens > 0) {
      return capabilityMaxOutputTokens;
    }
    if (contextWindow != null && contextWindow > 0) {
      return math.min(4096, math.max(512, (contextWindow * 0.2).floor()));
    }
    return 2048;
  }

  int _estimateMessages(List<ChatMessage> messages) {
    var total = 0;
    for (final message in messages) {
      total += 24;
      if (message is HumanChatMessage) {
        total += _estimateContent(message.content);
      } else if (message is AIChatMessage) {
        total += _estimateText(message.contentAsString);
      } else {
        total += _estimateText(message.contentAsString);
      }
    }
    return total;
  }

  int _estimateContent(ChatMessageContent content) {
    if (content is ChatMessageContentText) {
      return _estimateText(content.text);
    }
    if (content is ChatMessageContentMultiModal) {
      var total = 0;
      for (final part in content.parts) {
        if (part is ChatMessageContentText) {
          total += _estimateText(part.text);
        } else {
          total += 300;
        }
      }
      return total;
    }
    return _estimateText(content.toString());
  }

  int _estimateText(String text) {
    if (text.trim().isEmpty) {
      return 0;
    }
    var cjk = 0;
    var nonCjk = 0;
    for (final rune in text.runes) {
      if (_isCjk(rune)) {
        cjk += 1;
      } else {
        nonCjk += 1;
      }
    }
    return cjk + (nonCjk / 4).ceil();
  }

  bool _isCjk(int rune) {
    return (rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0x3400 && rune <= 0x4DBF) ||
        (rune >= 0x20000 && rune <= 0x2A6DF);
  }

  AiModelCapability? _resolveCapability(String providerId, String modelId) {
    final cache = Prefs().getAiModelCapabilitiesCacheV1(providerId);
    final normalized = modelId.trim();
    if (cache == null || normalized.isEmpty) {
      return null;
    }
    for (final capability in cache.models) {
      if (capability.id == normalized) {
        return capability;
      }
    }
    return null;
  }
}
