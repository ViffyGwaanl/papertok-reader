enum SeminarAutoScrollMethod {
  jump,
  animate,
}

class SeminarAutoScrollPolicy {
  const SeminarAutoScrollPolicy._();

  static const double bottomThreshold = 80;

  static bool isPinnedToBottom({
    required double maxScrollExtent,
    required double pixels,
  }) {
    return (maxScrollExtent - pixels) < bottomThreshold;
  }

  static bool shouldFollowStreaming({
    required bool pinnedToBottom,
    required bool userScrollInProgress,
  }) {
    return pinnedToBottom && !userScrollInProgress;
  }

  static SeminarAutoScrollMethod methodFor({required bool isStreaming}) {
    return isStreaming
        ? SeminarAutoScrollMethod.jump
        : SeminarAutoScrollMethod.animate;
  }
}
