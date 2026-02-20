import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/ai_quick_prompt_chip.dart';
import 'package:anx_reader/widgets/ai/ai_chat_bottom_sheet.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:flutter/material.dart';

class AiPage extends StatefulWidget {
  const AiPage({super.key});

  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  final GlobalKey<AiChatStreamState> _aiChatKey =
      GlobalKey<AiChatStreamState>();

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
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            top: false,
            child: AiChatBottomSheet(
              aiChatKey: _aiChatKey,
              quickPromptChips: _buildQuickPromptChips(),
              onRequestClose: () => Navigator.of(context).maybePop(),
            ),
          ),
        );
      },
    );
  }
}
