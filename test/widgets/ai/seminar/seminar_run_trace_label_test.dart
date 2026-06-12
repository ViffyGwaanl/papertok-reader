import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/widgets/ai/seminar/seminar_run_trace_label.dart';

void main() {
  test('seminarRunTraceLabel hides raw role run ids behind readable labels',
      () {
    final label = seminarRunTraceLabel(
      'seminar-chat-history:role-critical-0',
      zh: true,
      roleLabelForId: (roleId) => roleId == 'critical' ? '批判者' : roleId,
    );

    expect(label, '本场研讨 · 批判者');
    expect(label, isNot(contains('seminar-chat-history')));
    expect(label, isNot(contains('role-critical-0')));
  });

  test('seminarRunTraceLabel labels parent and tool-call ids without raw ids',
      () {
    expect(
      seminarRunTraceLabel('seminar-chat-history', zh: true),
      '本场研讨',
    );
    expect(
      seminarRunTraceLabel('seminar-tool-call-6f4b', zh: true),
      '本场研讨 · 工具调用',
    );
  });
}
