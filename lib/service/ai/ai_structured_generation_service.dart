import 'dart:async';
import 'dart:convert';

import 'package:papertok_reader/service/ai/index.dart';
import 'package:papertok_reader/service/ai/tools/util/json_repair.dart';
import 'package:langchain_core/chat_models.dart';

typedef AiStructuredGenerateText = Future<String> Function({
  required String systemPrompt,
  required String userPrompt,
  String? providerId,
  Map<String, String>? config,
  Duration timeout,
});

class AiStructuredGenerationService {
  const AiStructuredGenerationService({AiStructuredGenerateText? generateText})
      : _generateText = generateText;

  final AiStructuredGenerateText? _generateText;

  Future<Map<String, dynamic>> generateJson({
    required String systemPrompt,
    required String userPrompt,
    String? providerId,
    Map<String, String>? config,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final raw = await generateText(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      providerId: providerId,
      config: config,
      timeout: timeout,
    );
    final repaired = repairJson(raw);
    final decoded = jsonDecode(repaired);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    throw const FormatException('Structured generation did not return object');
  }

  Future<String> generateText({
    required String systemPrompt,
    required String userPrompt,
    String? providerId,
    Map<String, String>? config,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final fn = _generateText;
    if (fn != null) {
      return fn(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        providerId: providerId,
        config: config,
        timeout: timeout,
      );
    }

    final stream = aiGenerateStream(
      [
        ChatMessage.system(systemPrompt),
        ChatMessage.humanText(userPrompt),
      ],
      identifier: providerId,
      config: config,
      useAgent: false,
    );
    return stream.last.timeout(timeout);
  }
}
