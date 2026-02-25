import 'package:anx_reader/service/reading/epub_player_key.dart';
import 'package:anx_reader/widgets/markdown/selection_control.dart';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// A custom Markdown widget with theme-aware styling.
///
/// This widget provides better contrast and readability in both light and dark
/// modes, especially for blockquotes and code blocks that appear in AI chat
/// responses.
class StyledMarkdown extends StatelessWidget {
  const StyledMarkdown({
    super.key,
    required this.data,
    this.selectable = true,
  });

  final String data;
  final bool selectable;

  ({int bookId, String? cfi, String? href})? _extractReaderTargetFromPaperUri(
    Uri uri,
  ) {
    // Supported:
    // paperreader://reader/open?bookId=123&cfi=...
    // paperreader://reader/open?bookId=123&href=...
    if (uri.scheme.toLowerCase() != 'paperreader') return null;
    if (uri.host.toLowerCase() != 'reader') return null;

    if (uri.pathSegments.isEmpty || uri.pathSegments.first != 'open') {
      return null;
    }

    final bookId = int.tryParse((uri.queryParameters['bookId'] ?? '').trim());
    if (bookId == null || bookId <= 0) return null;

    final cfi = (uri.queryParameters['cfi'] ?? '').trim();
    final href = (uri.queryParameters['href'] ?? '').trim();

    return (
      bookId: bookId,
      cfi: cfi.isEmpty ? null : cfi,
      href: href.isEmpty ? null : href,
    );
  }

  Future<void> _handleLinkTap(String href) async {
    // 1) Try internal reader navigation.
    final trimmed = href.trim();
    if (trimmed.isEmpty) return;

    final player = epubPlayerKey.currentState;

    // raw CFI link
    if (trimmed.startsWith('epubcfi(') || trimmed.startsWith('/')) {
      // CFI strings may omit the wrapper in some outputs; foliate-js accepts both.
      if (player != null) {
        player.goToCfi(trimmed);
        return;
      }
    }

    // local anchors (e.g. "#footnote")
    if (trimmed.startsWith('#')) {
      if (player != null) {
        player.goToHref(trimmed);
        return;
      }
    }

    final uri = Uri.tryParse(trimmed);
    final target = (uri == null) ? null : _extractReaderTargetFromPaperUri(uri);
    if (target != null) {
      // Same-book fast path.
      if (player != null && player.widget.book.id == target.bookId) {
        final cfi = target.cfi;
        final href = target.href;
        if (cfi != null && cfi.trim().isNotEmpty) {
          player.goToCfi(cfi);
          return;
        }
        if (href != null && href.trim().isNotEmpty) {
          player.goToHref(href);
          return;
        }
      }

      // Cross-book navigation: open via OS-level deep link (handled by app_links).
      await launchUrlString(trimmed, mode: LaunchMode.externalApplication);
      return;
    }

    // 2) Fallback to opening as external.
    await launchUrlString(trimmed, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SelectableRegion(
      selectionControls: selectionControls(),
      child: GptMarkdown(
        data,
        followLinkColor: true,
        onLinkTap: (href, text) => _handleLinkTap(href),
        linkBuilder: (context, text, url, style) => Text.rich(
          text,
          style: style.copyWith(
            color: theme.colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}
