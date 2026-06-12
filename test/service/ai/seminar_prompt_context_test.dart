import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/models/ai_conversation_tree.dart';
import 'package:papertok_reader/service/ai/seminar_prompt_context.dart';

void main() {
  AiSeminarRunCardMeta card({
    String status = 'completed',
    AiSeminarRunCardSnapshot? snapshot,
  }) {
    return AiSeminarRunCardMeta(
      question: '什么是心流?',
      createdAt: 1,
      sessionId: 's1',
      status: status,
      snapshot: snapshot,
    );
  }

  test('completed card digests conclusion, disagreements and evidence', () {
    final text = seminarRunCardPromptText(
      card(
        snapshot: const AiSeminarRunCardSnapshot(
          synthesisSummary: '心流是挑战与技能匹配时的深度沉浸状态。',
          disagreements: ['挑战与技能是否必须严格平衡'],
          openQuestions: ['心流能否被刻意训练'],
          evidence: [
            AiSeminarRunCardEvidenceSnapshot(
              id: 'current-1',
              title: '第3章 心流条件',
              snippet: '当挑战与技能匹配时,人会进入心流。',
            ),
          ],
        ),
      ),
    );
    expect(text, contains('【AI研讨会·已完成】'));
    expect(text, contains('什么是心流?'));
    expect(text, contains('心流是挑战与技能匹配时的深度沉浸状态。'));
    expect(text, contains('主要分歧'));
    expect(text, contains('开放问题'));
    expect(text, contains('证据1'));
    expect(text, contains('第3章 心流条件'));
  });

  test('running card stays a single status line without conclusions', () {
    final text = seminarRunCardPromptText(card(status: 'running'));
    expect(text, contains('AI Seminar: 什么是心流?'));
    expect(text, contains('研讨进行中'));
    expect(text.contains('\n'), isFalse);
  });

  test('cancelled card reports no final conclusion', () {
    final text = seminarRunCardPromptText(card(status: 'cancelled'));
    expect(text, contains('已取消'));
    expect(text.contains('【AI研讨会·已完成】'), isFalse);
  });

  test('completed card without synthesis stays base text', () {
    final text = seminarRunCardPromptText(
      card(snapshot: const AiSeminarRunCardSnapshot()),
    );
    expect(text, 'AI Seminar: 什么是心流?');
  });

  test('digest is capped at maxChars', () {
    final text = seminarRunCardPromptText(
      card(
        snapshot: AiSeminarRunCardSnapshot(synthesisSummary: 'x' * 10000),
      ),
      maxChars: 500,
    );
    expect(text.length, lessThanOrEqualTo(500));
  });
}
