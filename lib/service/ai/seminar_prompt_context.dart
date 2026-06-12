import 'package:papertok_reader/models/ai_conversation_tree.dart';

/// P1 F19a: LLM-facing text for a Seminar run card node.
///
/// The seminar card node participates in the main chat prompt history through
/// its node message. Before F19a it only carried `AI Seminar: <question>`, so
/// follow-up turns in the main conversation were amnesic about seminar
/// outcomes. For completed runs this builds a compact digest (question,
/// conclusion, disagreements, open questions, key evidence); for other states
/// it stays a one-line status note.
String seminarRunCardPromptText(
  AiSeminarRunCardMeta card, {
  int maxChars = 4000,
}) {
  final question = card.question.trim();
  final base = question.isEmpty ? 'AI Seminar' : 'AI Seminar: $question';
  final status = card.status.trim();
  final snapshot = card.snapshot;
  final summary = snapshot?.synthesisSummary?.trim() ?? '';
  if (status != 'completed' || snapshot == null || summary.isEmpty) {
    return switch (status) {
      'running' => '$base(研讨进行中,尚无结论)',
      'cancelled' => '$base(研讨已取消,无最终结论)',
      'failed' => '$base(研讨失败,无最终结论)',
      _ => base,
    };
  }

  final buffer = StringBuffer()
    ..writeln('【AI研讨会·已完成】')
    ..writeln('问题:${question.isEmpty ? '(未记录)' : question}')
    ..writeln('结论:${_clip(summary, 2200)}');
  final disagreements = _takeNonEmpty(snapshot.disagreements, 5);
  if (disagreements.isNotEmpty) {
    buffer.writeln('主要分歧:');
    for (var i = 0; i < disagreements.length; i++) {
      buffer.writeln('${i + 1}. ${_clip(disagreements[i], 220)}');
    }
  }
  final openQuestions = _takeNonEmpty(snapshot.openQuestions, 3);
  if (openQuestions.isNotEmpty) {
    buffer.writeln('开放问题:');
    for (var i = 0; i < openQuestions.length; i++) {
      buffer.writeln('${i + 1}. ${_clip(openQuestions[i], 160)}');
    }
  }
  final evidence = snapshot.evidence.take(6).toList(growable: false);
  if (evidence.isNotEmpty) {
    buffer.writeln('关键证据:');
    for (var i = 0; i < evidence.length; i++) {
      final title = _clip(evidence[i].title.trim(), 60);
      final snippet = _clip(evidence[i].snippet.trim(), 140);
      buffer.writeln(
        '证据${i + 1}(${title.isEmpty ? '未命名来源' : title}):$snippet',
      );
    }
  }
  buffer.write('(以上为本对话中 AI 研讨会的结论,后续回答可直接引用。)');
  return _clip(buffer.toString().trim(), maxChars);
}

List<String> _takeNonEmpty(List<String> items, int limit) {
  return items
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .take(limit)
      .toList(growable: false);
}

String _clip(String text, int maxChars) {
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars - 1)}…';
}
