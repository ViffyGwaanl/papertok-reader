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

  String? _extractCfiFromAnxUri(Uri uri) {
    // Supported:
    // - anx://cfi?value=<cfi>
    // - anx://cfi/<urlEncodedCfi>
    // - anx://goto?cfi=<cfi>
    final host = uri.host.toLowerCase();

    if (host == 'cfi') {
      final q = uri.queryParameters['value'] ?? uri.queryParameters['cfi'];
      if (q != null && q.trim().isNotEmpty) return q.trim();

      final path = uri.path;
      if (path.isNotEmpty && path != '/') {
        return Uri.decodeComponent(
                path.startsWith('/') ? path.substring(1) : path)
            .trim();
      }
    }

    if (host == 'goto') {
      final cfi = uri.queryParameters['cfi'] ?? uri.queryParameters['value'];
      if (cfi != null && cfi.trim().isNotEmpty) return cfi.trim();
    }

    // Alternative: anx:///cfi/<encoded>
    if (uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'cfi') {
      final rest = uri.pathSegments.skip(1).join('/');
      if (rest.trim().isNotEmpty) return Uri.decodeComponent(rest).trim();
    }

    return null;
  }

  String? _extractHrefFromAnxUri(Uri uri) {
    // Supported:
    // - anx://href?value=<href>
    // - anx://href/<urlEncodedHref>
    final host = uri.host.toLowerCase();

    if (host == 'href') {
      final q = uri.queryParameters['value'] ?? uri.queryParameters['href'];
      if (q != null && q.trim().isNotEmpty) return q.trim();

      final path = uri.path;
      if (path.isNotEmpty && path != '/') {
        return Uri.decodeComponent(
                path.startsWith('/') ? path.substring(1) : path)
            .trim();
      }
    }

    if (uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'href') {
      final rest = uri.pathSegments.skip(1).join('/');
      if (rest.trim().isNotEmpty) return Uri.decodeComponent(rest).trim();
    }

    return null;
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
    if (uri != null && uri.scheme.toLowerCase() == 'anx') {
      final cfi = _extractCfiFromAnxUri(uri);
      if (cfi != null && player != null) {
        player.goToCfi(cfi);
        return;
      }

      final targetHref = _extractHrefFromAnxUri(uri);
      if (targetHref != null && player != null) {
        player.goToHref(targetHref);
        return;
      }
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
