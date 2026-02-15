import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/ai_quick_prompt_chip.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AiChatBottomSheet extends StatefulWidget {
  const AiChatBottomSheet({
    super.key,
    required this.aiChatKey,
    this.initialMessage,
    this.sendImmediate = false,
    this.quickPromptChips = const [],
  });

  final GlobalKey<AiChatStreamState> aiChatKey;
  final String? initialMessage;
  final bool sendImmediate;
  final List<AiQuickPromptChip> quickPromptChips;

  @override
  State<AiChatBottomSheet> createState() => _AiChatBottomSheetState();
}

class _AiChatBottomSheetState extends State<AiChatBottomSheet> {
  static const double _minSize = 0.35;
  static const double _maxSize = 0.95;
  static const List<double> _snapSizes = [0.35, 0.6, 0.9, 0.95];

  late final DraggableScrollableController _sheetController;
  late double _currentSize;

  @override
  void initState() {
    super.initState();
    _sheetController = DraggableScrollableController();
    _currentSize = Prefs().aiSheetInitialSize.clamp(_minSize, _maxSize);
  }

  @override
  void dispose() {
    // Persist the last known size.
    try {
      Prefs().aiSheetInitialSize = _currentSize;
    } catch (_) {}
    super.dispose();
  }

  double _clampSize(double size) => size.clamp(_minSize, _maxSize).toDouble();

  double _nearestSnapSize(double size) {
    double best = _snapSizes.first;
    double bestDist = (size - best).abs();
    for (final s in _snapSizes.skip(1)) {
      final d = (size - s).abs();
      if (d < bestDist) {
        best = s;
        bestDist = d;
      }
    }
    return best;
  }

  Future<void> _snapToNearest() async {
    final target = _nearestSnapSize(_currentSize);
    try {
      await _sheetController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    } catch (_) {
      // If the controller is not attached yet (rare), ignore.
    }
  }

  Widget _buildGrip(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface.withAlpha(90);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => HapticFeedback.selectionClick(),
      onVerticalDragUpdate: (details) {
        final height = MediaQuery.of(context).size.height;
        if (height <= 0) return;
        // Drag up => increase size; drag down => decrease size.
        final delta = details.delta.dy / height;
        final target = _clampSize(_currentSize - delta);
        _currentSize = target;
        try {
          _sheetController.jumpTo(target);
        } catch (_) {}
      },
      onVerticalDragEnd: (_) => _snapToNearest(),
      child: Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        _currentSize = notification.extent;
        return false;
      },
      child: DraggableScrollableSheet(
        controller: _sheetController,
        expand: false,
        initialChildSize: _currentSize,
        minChildSize: _minSize,
        maxChildSize: _maxSize,
        snap: true,
        snapSizes: _snapSizes,
        builder: (context, scrollController) {
          return Column(
            children: [
              _buildGrip(context),
              Expanded(
                child: AiChatStream(
                  key: widget.aiChatKey,
                  initialMessage: widget.initialMessage,
                  sendImmediate: widget.sendImmediate,
                  quickPromptChips: widget.quickPromptChips,
                  scrollController: scrollController,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
