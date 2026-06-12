enum SeminarAutoScrollMethod {
  jump,
  animate,
}

class SeminarAutoScrollPolicy {
  const SeminarAutoScrollPolicy._();

  static const double bottomThreshold = 80;
  static const double shortcutThreshold = 320;

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

  static bool shouldShowShortcut({
    required double maxScrollExtent,
    required double pixels,
  }) {
    return (maxScrollExtent - pixels) >= shortcutThreshold;
  }

  static bool shouldMarkNewContentBelow({
    required bool pinnedToBottom,
    required String previousSignature,
    required String currentSignature,
  }) {
    return !pinnedToBottom &&
        previousSignature.isNotEmpty &&
        previousSignature != currentSignature;
  }
}
