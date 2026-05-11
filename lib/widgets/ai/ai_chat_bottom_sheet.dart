import 'dart:async';

import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/models/ai_quick_prompt_chip.dart';
import 'package:papertok_reader/theme/app_spacing.dart';
import 'package:papertok_reader/widgets/ai/ai_multi_tab_chat.dart';
import 'package:flutter/material.dart';

/// Resizable AI chat bottom sheet.
///
/// Design goals:
/// - Allow minimizing the chat into a small bar so users can keep reading while
///   the assistant continues streaming.
/// - Persist the last sheet height.
/// - Avoid dismissing the sheet via drag (ReadingPage uses enableDrag=false).
enum AiChatBottomSheetMinimizeBehavior {
  /// Minimize into a small bar (DraggableScrollableSheet min size).
  toBar,

  /// Close/dismiss the sheet.
  close,
}

class AiChatBottomSheet extends StatefulWidget {
  const AiChatBottomSheet({
    super.key,
    required this.aiChatKey,
    this.initialMessage,
    this.sendImmediate = false,
    this.quickPromptChips = const [],
    this.initialSizeOverride,
    this.rememberSize = true,
    this.minimizeBehavior = AiChatBottomSheetMinimizeBehavior.toBar,
    this.onRequestClose,
    this.lockToInitialSize = false,
  });

  final GlobalKey<AiMultiTabChatState> aiChatKey;
  final String? initialMessage;
  final bool sendImmediate;
  final List<AiQuickPromptChip> quickPromptChips;

  /// Optional override for the initial sheet height (0-1).
  /// When set, it takes precedence over persisted size.
  final double? initialSizeOverride;

  /// Whether to persist sheet height while dragging.
  /// Note: minimized state is not persisted.
  final bool rememberSize;

  /// Minimize behavior.
  final AiChatBottomSheetMinimizeBehavior minimizeBehavior;

  /// Close callback.
  /// - Modal sheet: pass `Navigator.pop`.
  /// - Persistent sheet: pass `PersistentBottomSheetController.close`.
  final VoidCallback? onRequestClose;

  /// When true, the sheet height is locked to [initialSizeOverride] and the
  /// only allowed gesture is "drag down to close" (no intermediate sizes).
  /// Used by the reading page where the AI chat should always be near full
  /// height when open.
  final bool lockToInitialSize;

  @override
  State<AiChatBottomSheet> createState() => _AiChatBottomSheetState();
}

class _AiChatBottomSheetState extends State<AiChatBottomSheet> {
  static const double _minSize = 0.12;
  static const double _maxSize = 0.95;

  /// When the sheet height is below this threshold, we treat it as "minimized"
  /// and never persist it as the default opening size.
  static const double _minPersistSize = 0.25;

  static const double _minimizedEpsilon = 0.02;

  final _sheetController = DraggableScrollableController();
  Timer? _saveDebounce;

  /// Last non-minimized size used for toggle expand.
  double _lastExpandedSize = 0.6;

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _sheetController.dispose();
    super.dispose();
  }

  void _scheduleSave(double size) {
    if (!widget.rememberSize) {
      return;
    }

    final clamped = size.clamp(_minSize, _maxSize).toDouble();

    // Never persist minimized / too-small sizes, otherwise users can get
    // stuck opening the chat in a tiny state.
    if (clamped < _minPersistSize) {
      return;
    }

    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 250), () {
      Prefs().aiSheetInitialSize = clamped;
    });
  }

  Future<void> _toggleMinimize() async {
    if (widget.minimizeBehavior == AiChatBottomSheetMinimizeBehavior.close) {
      // In some contexts (e.g. Home AI as a Cupertino sheet), the preferred
      // behavior is to dismiss the sheet entirely.
      final close = widget.onRequestClose ?? () => Navigator.of(context).pop();
      close();
      return;
    }
    double size = _maxSize;
    try {
      size = _sheetController.size;
    } catch (_) {
      // ignore (controller might not be attached yet)
    }

    final isMinimized = size <= _minSize + _minimizedEpsilon;

    // Expand.
    if (isMinimized) {
      final target = _lastExpandedSize.clamp(_minPersistSize, _maxSize);
      try {
        await _sheetController.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } catch (_) {}
      return;
    }

    // Minimize.
    if (size >= _minPersistSize) {
      _lastExpandedSize = size;
    }

    try {
      await _sheetController.animateTo(
        _minSize,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    } catch (_) {
      // ignore
    }
  }

  bool _closing = false;

  @override
  Widget build(BuildContext context) {
    var initial = (widget.initialSizeOverride ?? Prefs().aiSheetInitialSize)
        .clamp(_minSize, _maxSize)
        .toDouble();

    // If we ever persisted a too-small size, ignore it on open.
    if (initial < _minPersistSize) {
      initial = _maxSize;
    }

    // Seed last expanded size.
    _lastExpandedSize = initial;

    final lock = widget.lockToInitialSize;
    // Locked mode: only two valid extents — full (initial) or fully closed (0).
    // Unlocked: the legacy multi-stop snap layout.
    final double sheetMin = lock ? 0.0 : _minSize;
    final double sheetMax = initial;
    final List<double> snapPoints = lock
        ? <double>[0.0, initial]
        : const <double>[_minSize, 0.35, 0.6, 0.9, _maxSize];

    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (n) {
        _scheduleSave(n.extent);
        if (lock && !_closing && n.extent <= 0.05) {
          _closing = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final close = widget.onRequestClose ??
                () => Navigator.of(context).maybePop();
            close();
          });
        }
        return false;
      },
      child: DraggableScrollableSheet(
        controller: _sheetController,
        initialChildSize: initial,
        minChildSize: sheetMin,
        maxChildSize: sheetMax,
        snap: true,
        snapSizes: snapPoints,
        builder: (context, scrollController) {
          return Material(
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppSpacing.cornerRadiusLarge),
            ),
            child: AiMultiTabChat(
              key: widget.aiChatKey,
              initialMessage: widget.initialMessage,
              sendImmediate: widget.sendImmediate,
              quickPromptChips: widget.quickPromptChips,
              scrollController: scrollController,
              // In lock mode the only minimize-equivalent is closing the
              // sheet entirely (drag-down or close button). Don't expose the
              // collapse-to-bar affordance.
              onRequestMinimize: lock ? null : _toggleMinimize,
              trailing: [
                if (!lock)
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down),
                    onPressed: _toggleMinimize,
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onRequestClose ??
                      () => Navigator.of(context).pop(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
