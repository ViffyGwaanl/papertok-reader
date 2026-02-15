import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/ai_quick_prompt_chip.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:flutter/material.dart';

/// Resizable AI chat bottom sheet.
///
/// Design goals:
/// - Allow minimizing the chat into a small bar so users can keep reading while
///   the assistant continues streaming.
/// - Persist the last sheet height.
/// - Avoid dismissing the sheet via drag (ReadingPage uses enableDrag=false).
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
  static const double _minSize = 0.12;
  static const double _maxSize = 0.95;

  Timer? _saveDebounce;

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  void _scheduleSave(double size) {
    final clamped = size.clamp(_minSize, _maxSize).toDouble();
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 250), () {
      Prefs().aiSheetInitialSize = clamped;
    });
  }

  @override
  Widget build(BuildContext context) {
    final initial = Prefs().aiSheetInitialSize.clamp(_minSize, _maxSize);

    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (n) {
        _scheduleSave(n.extent);
        return false;
      },
      child: DraggableScrollableSheet(
        initialChildSize: initial,
        minChildSize: _minSize,
        maxChildSize: _maxSize,
        snap: true,
        snapSizes: const [
          _minSize,
          0.35,
          0.6,
          0.9,
          _maxSize,
        ],
        builder: (context, scrollController) {
          return Material(
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(16),
            ),
            child: AiChatStream(
              key: widget.aiChatKey,
              initialMessage: widget.initialMessage,
              sendImmediate: widget.sendImmediate,
              quickPromptChips: widget.quickPromptChips,
              scrollController: scrollController,
              trailing: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
