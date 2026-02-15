import 'package:anx_reader/models/ai_quick_prompt_chip.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:flutter/material.dart';

/// Fixed-size AI chat bottom sheet.
///
/// Previously we used a resizable [DraggableScrollableSheet], but resizing via
/// touch was hard to control. We now open the sheet at a large, stable height
/// and rely on the default downward drag to dismiss.
class AiChatBottomSheet extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    final sheetHeight = height * 0.95;

    return SizedBox(
      height: sheetHeight,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: AiChatStream(
          key: aiChatKey,
          initialMessage: initialMessage,
          sendImmediate: sendImmediate,
          quickPromptChips: quickPromptChips,
        ),
      ),
    );
  }
}
