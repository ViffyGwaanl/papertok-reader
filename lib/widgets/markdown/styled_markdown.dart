import 'package:anx_reader/service/deeplink/paperreader_deeplink_handler.dart';
import 'package:anx_reader/service/reading/epub_player_key.dart';
import 'package:anx_reader/widgets/markdown/selection_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  String _normalizeUriText(String s) {
    var out = s.trim();

    // Common fullwidth punctuation when users/LLMs output links in Chinese.
    out = out
        .replaceAll('？', '?')
        .replaceAll('＆', '&')
        .replaceAll('＝', '=')
        .replaceAll('＃', '#');

    // Common typo: single slash after scheme.
    if (out.startsWith('paperreader:/') && !out.startsWith('paperreader://')) {
      out = out.replaceFirst('paperreader:/', 'paperreader://');
    }

    return out;
  }

  /// Make custom scheme links tappable even when the model outputs raw URLs
  /// (not markdown links).
  String _linkifyPaperreaderUris(String s) {
    // Match a conservative URI charset to avoid swallowing trailing punctuation.
    final re = RegExp(
      r'(?<!\()(?<!\<)(paperreader:\/\/[A-Za-z0-9\-._~:/?#[\]@!$&()*+,;=%]+)',
    );

    return s.replaceAllMapped(re, (m) {
      final raw = m.group(1) ?? '';
      // Markdown link format is the most reliably recognized across parsers.
      return '[$raw]($raw)';
    });
  }

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

    final bookIdRaw = (uri.queryParameters['bookId'] ??
            uri.queryParameters['bookID'] ??
            // Common OCR/typo: bookId -> bookld
            uri.queryParameters['bookld'] ??
            uri.queryParameters['bookLd'] ??
            '')
        .trim();

    final bookId = int.tryParse(bookIdRaw);
    if (bookId == null || bookId <= 0) return null;

    final cfi = (uri.queryParameters['cfi'] ?? '').trim();
    final href = (uri.queryParameters['href'] ?? '').trim();

    return (
      bookId: bookId,
      cfi: cfi.isEmpty ? null : cfi,
      href: href.isEmpty ? null : href,
    );
  }

  Future<void> _handleLinkTap(BuildContext context, String href) async {
    // 1) Try internal reader navigation.
    final trimmed = _normalizeUriText(href);
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

      // Cross-book navigation: prefer in-app deeplink handling.
      //
      // Using url_launcher for custom schemes can be flaky on iOS because it may
      // rely on canOpenURL (LSApplicationQueriesSchemes). In-app routing is
      // faster and more reliable.
      try {
        final container = ProviderScope.containerOf(context);
        await PaperReaderDeepLinkHandler.handleIncomingUriWithContainer(
          container,
          uri!,
        );
      } catch (_) {
        // Best-effort fallback.
        await launchUrlString(trimmed, mode: LaunchMode.externalApplication);
      }
      return;
    }

    // 2) Fallback to opening as external.
    await launchUrlString(trimmed, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalized = _linkifyPaperreaderUris(data);
    return SelectableRegion(
      selectionControls: selectionControls(),
      child: GptMarkdown(
        normalized,
        followLinkColor: true,
        onLinkTap: (href, text) => _handleLinkTap(context, href),
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
