import 'package:anx_reader/service/deeplink/paperreader_deeplink_handler.dart';
import 'package:anx_reader/service/reading/epub_player_key.dart';
import 'package:anx_reader/widgets/markdown/selection_control.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      try {
        final container = ProviderScope.containerOf(context);
        await PaperReaderDeepLinkHandler.handleIncomingUriWithContainer(
          container,
          uri!,
        );
      } catch (_) {
        await launchUrlString(trimmed, mode: LaunchMode.externalApplication);
      }
      return;
    }

    // 2) Fallback to opening as external.
    await launchUrlString(trimmed, mode: LaunchMode.externalApplication);
  }

  Widget _buildMarkdown(BuildContext context) {
    final theme = Theme.of(context);
    final normalized = _linkifyPaperreaderUris(data);
    final scaler = MediaQuery.textScalerOf(context);
    final bodyStyle = StyledMarkdownTypography.scaledStyle(
      StyledMarkdownTypography.baseBodyStyle(theme),
      scaler,
    );

    // Freeze markdown subtree scaling so prose, headings, code, and LaTeX all
    // resolve from the same scaled typography baseline.
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: GptMarkdownTheme(
        gptThemeData: StyledMarkdownTypography.markdownTheme(
          brightness: theme.brightness,
          bodyStyle: bodyStyle,
        ),
        child: GptMarkdown(
          normalized,
          style: bodyStyle,
          textScaler: TextScaler.noScaling,
          followLinkColor: true,
          onLinkTap: (href, text) => _handleLinkTap(context, href),
          codeBuilder: (context, name, code, closed) => _MarkdownCodeBlock(
            name: name,
            code: code,
            textStyle: bodyStyle,
          ),
          linkBuilder: (context, text, url, style) => Text.rich(
            text,
            style: style.copyWith(
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final markdown = _buildMarkdown(context);
    if (!selectable) {
      return markdown;
    }
    return SelectableRegion(
      selectionControls: selectionControls(),
      child: markdown,
    );
  }
}

class _MarkdownCodeBlock extends StatefulWidget {
  const _MarkdownCodeBlock({
    required this.name,
    required this.code,
    required this.textStyle,
  });

  final String name;
  final String code;
  final TextStyle textStyle;

  @override
  State<_MarkdownCodeBlock> createState() => _MarkdownCodeBlockState();
}

class _MarkdownCodeBlockState extends State<_MarkdownCodeBlock> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = widget.name.trim().isEmpty ? 'text' : widget.name.trim();
    final codeStyle = StyledMarkdownTypography.codeStyle(widget.textStyle);

    return Material(
      color: theme.colorScheme.onInverseSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  label,
                  style: widget.textStyle.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurface,
                  textStyle: widget.textStyle.copyWith(
                    fontSize: (widget.textStyle.fontSize ?? 14) * 0.9,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: widget.code));
                  if (!mounted) return;
                  setState(() {
                    _copied = true;
                  });
                  await Future.delayed(const Duration(seconds: 2));
                  if (!mounted) return;
                  setState(() {
                    _copied = false;
                  });
                },
                icon: Icon(
                  _copied ? Icons.done : Icons.content_paste,
                  size: 15,
                ),
                label: Text(_copied ? 'Copied!' : 'Copy code'),
              ),
            ],
          ),
          const Divider(height: 1),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              widget.code,
              style: codeStyle,
            ),
          ),
        ],
      ),
    );
  }
}
