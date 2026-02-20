import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/ai_quick_prompt_chip.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:flutter/material.dart';

/// Home AI page (non-modal).
///
/// Note: This is a normal tab page like Bookshelf/Settings, not a popup.
class AiPage extends StatelessWidget {
  const AiPage({super.key});

  List<AiQuickPromptChip> _buildQuickPromptChips() {
    // Home AI page doesn't have a "current book" context, so we only show
    // user-defined prompts here.
    return Prefs()
        .userPrompts
        .where((p) => p.enabled)
        .map(
          (p) => AiQuickPromptChip(
            icon: Icons.person_outline,
            label: p.name,
            prompt: p.content,
          ),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Prefs(),
      builder: (context, _) {
        final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

        // Home (phone) uses a floating bottom tab bar (64px height + 10px
        // padding top/bottom inside the floating BottomBar widget).
        // Add extra space so the input box is never covered by the tab bar.
        final bottomPadding = keyboardVisible ? 0.0 : (64.0 + 20.0);

        return AiChatStream(
          quickPromptChips: _buildQuickPromptChips(),
          bottomPadding: bottomPadding,
        );
      },
    );
  }
}
