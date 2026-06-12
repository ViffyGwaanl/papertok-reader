import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/widgets/ai/seminar/seminar_autoscroll_policy.dart';

void main() {
  test('pins only within the seminar streaming bottom threshold', () {
    expect(
      SeminarAutoScrollPolicy.isPinnedToBottom(
        maxScrollExtent: 1000,
        pixels: 921,
      ),
      true,
    );
    expect(
      SeminarAutoScrollPolicy.isPinnedToBottom(
        maxScrollExtent: 1000,
        pixels: 920,
      ),
      false,
    );
  });

  test('streaming follow is disabled while the user is dragging', () {
    expect(
      SeminarAutoScrollPolicy.shouldFollowStreaming(
        pinnedToBottom: true,
        userScrollInProgress: false,
      ),
      true,
    );
    expect(
      SeminarAutoScrollPolicy.shouldFollowStreaming(
        pinnedToBottom: true,
        userScrollInProgress: true,
      ),
      false,
    );
    expect(
      SeminarAutoScrollPolicy.shouldFollowStreaming(
        pinnedToBottom: false,
        userScrollInProgress: false,
      ),
      false,
    );
  });

  test('streaming follow uses jump instead of animated scrolling', () {
    expect(
      SeminarAutoScrollPolicy.methodFor(isStreaming: true),
      SeminarAutoScrollMethod.jump,
    );
    expect(
      SeminarAutoScrollPolicy.methodFor(isStreaming: false),
      SeminarAutoScrollMethod.animate,
    );
  });
}
