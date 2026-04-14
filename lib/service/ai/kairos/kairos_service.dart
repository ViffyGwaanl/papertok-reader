import 'dart:async';

import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/utils/log/common.dart';

/// KAIROS — Proactive reading assistant that detects when the user lingers
/// on a passage and offers contextual AI suggestions.
///
/// Monitors reading position changes and triggers hints when the same CFI
/// position stays unchanged beyond a configurable threshold.
class KairosService {
  KairosService({this.onHint});

  /// Callback invoked when a proactive hint should be shown.
  final void Function(KairosHint hint)? onHint;

  Timer? _checkTimer;
  String? _lastCfi;
  DateTime? _lastCfiChangeTime;
  String? _lastChapterTitle;
  bool _hintShownForCurrentPosition = false;

  static const _checkInterval = Duration(seconds: 5);

  /// Linger thresholds per KAIROS level (0=off, 1=light, 2=medium, 3=eager).
  static const _thresholds = <int, Duration>{
    1: Duration(seconds: 30),
    2: Duration(seconds: 20),
    3: Duration(seconds: 10),
  };

  /// Start monitoring. Call this when the reading page opens.
  void start() {
    stop();
    final level = Prefs().kairosLevel;
    if (level <= 0) return;

    _checkTimer = Timer.periodic(_checkInterval, (_) => _check());
    AnxLog.info('KAIROS: started at level $level');
  }

  /// Stop monitoring. Call this when the reading page closes.
  void stop() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _lastCfi = null;
    _lastCfiChangeTime = null;
    _hintShownForCurrentPosition = false;
  }

  /// Called when the reading position changes (from onRelocated handler).
  void onPositionUpdate({
    required String? cfi,
    String? chapterTitle,
    double? percentage,
  }) {
    if (cfi == null) return;

    if (cfi != _lastCfi) {
      _lastCfi = cfi;
      _lastCfiChangeTime = DateTime.now();
      _lastChapterTitle = chapterTitle;
      _hintShownForCurrentPosition = false;
    }
  }

  void _check() {
    final level = Prefs().kairosLevel;
    if (level <= 0) {
      stop();
      return;
    }

    if (_hintShownForCurrentPosition) return;
    if (_lastCfi == null || _lastCfiChangeTime == null) return;

    final threshold = _thresholds[level];
    if (threshold == null) return;

    final elapsed = DateTime.now().difference(_lastCfiChangeTime!);
    if (elapsed >= threshold) {
      _hintShownForCurrentPosition = true;
      _fireHint();
    }
  }

  void _fireHint() {
    final chapter = _lastChapterTitle ?? '';
    final hint = KairosHint(
      message: chapter.isNotEmpty
          ? 'Need help understanding this section of "$chapter"?'
          : 'Need help understanding this passage?',
      suggestedPrompt: chapter.isNotEmpty
          ? 'Explain the key ideas in the current section of "$chapter" in simple terms'
          : 'Explain the key ideas in the current passage in simple terms',
    );

    AnxLog.info('KAIROS: triggering hint for position $_lastCfi');
    onHint?.call(hint);
  }
}

/// A proactive reading suggestion from KAIROS.
class KairosHint {
  const KairosHint({
    required this.message,
    required this.suggestedPrompt,
  });

  /// Short message shown to the user (e.g. floating chip).
  final String message;

  /// Pre-filled prompt to send to AI if the user taps the hint.
  final String suggestedPrompt;
}
