import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/home_page/home_bottom_inset_scope.dart';
import 'package:anx_reader/theme/claude_palette.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Home AI page (non-modal).
///
/// Note: This is a normal tab page like Bookshelf/Settings, not a popup.
class AiPage extends StatelessWidget {
  const AiPage({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Prefs(),
      builder: (context, _) {
        // HomePage overlays a floating tab bar on phones.
        // We keep the AI page full-height (no external padding) so the bar can
        // visually float above the content.
        //
        // To prevent the input controls from being covered, we add the tab bar
        // height as *internal* padding inside the input box.
        final homeBottomInset = HomeBottomInsetScope.of(context);

        return AiChatStream(
          bottomPadding: homeBottomInset,
          // AiChatStream is an inner Scaffold under HomePage's Scaffold.
          // Avoid double-applying the keyboard inset.
          resizeToAvoidBottomInset: false,
          inputSafeAreaBottom: false,
          // Home AI empty state: Claude-style ghost pill rows — muted
          // warm background, hairline border, secondary text, no filled
          // terracotta CTAs (that color is reserved for the send button).
          emptyStateBuilder: (context, send) {
            final l10n = L10n.of(context);
            final prompts =
                Prefs().userPrompts.where((p) => p.enabled).toList();

            Widget ghostPromptRow({
              required String title,
              required String prompt,
            }) {
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    send(prompt);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: ClaudePalette.bg(context).withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: ClaudePalette.divider(context),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome_outlined,
                          size: 16,
                          color: ClaudePalette.secondary(context),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: ClaudePalette.secondary(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final top = prompts.take(3).toList(growable: false);

            return Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.tryAQuickPrompt,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: ClaudePalette.secondary(context),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      if (top.isNotEmpty) ...[
                        for (var i = 0; i < top.length; i++) ...[
                          ghostPromptRow(
                            title: top[i].name,
                            prompt: top[i].content,
                          ),
                          if (i != top.length - 1) const SizedBox(height: 8),
                        ],
                      ] else ...[
                        Text(
                          '你还没有配置「用户提示词」。\n可以在设置里添加常用快捷入口。',
                          style: TextStyle(
                            fontSize: 12,
                            color: ClaudePalette.tertiary(context),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
