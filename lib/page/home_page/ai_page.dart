import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/home_page/home_bottom_inset_scope.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:flutter/material.dart';

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
          // Keep the Home AI empty state clean (no right-bottom overlay chips).
          emptyStateBuilder: (context, send) {
            final theme = Theme.of(context);
            final l10n = L10n.of(context);
            final prompts =
                Prefs().userPrompts.where((p) => p.enabled).toList();

            Widget actionButton({
              required String title,
              required String prompt,
            }) {
              return SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () => send(prompt),
                  icon: const Icon(Icons.person_outline),
                  label: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
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
                        style: theme.textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      if (top.isNotEmpty) ...[
                        for (var i = 0; i < top.length; i++) ...[
                          actionButton(
                            title: top[i].name,
                            prompt: top[i].content,
                          ),
                          if (i != top.length - 1) const SizedBox(height: 10),
                        ],
                      ] else ...[
                        Text(
                          '你还没有配置「用户提示词」。\n可以在设置里添加常用快捷入口。',
                          style: theme.textTheme.bodySmall,
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
