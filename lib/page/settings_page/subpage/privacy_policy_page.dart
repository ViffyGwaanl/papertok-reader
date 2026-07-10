import 'package:flutter/material.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:papertok_reader/theme/claude_palette.dart';

/// Local, static privacy / data-locality statement (S3 batch 3).
/// Describes already-true behavior only — nothing here changes any data
/// flow. Rendered offline; no network access.
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final sections = <(String, String)>[
      (l10n.privacyLocalTitle, l10n.privacyLocalBody),
      (l10n.privacyEgressTitle, l10n.privacyEgressBody),
      (l10n.privacyNoTrackingTitle, l10n.privacyNoTrackingBody),
    ];

    return SettingsSubpageScaffold(
      title: l10n.aboutPrivacyPolicy,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        itemCount: sections.length,
        itemBuilder: (context, index) {
          final (title, body) = sections[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: ClaudePalette.fg(context),
                      ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  body,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.5,
                        color: ClaudePalette.secondary(context),
                      ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
