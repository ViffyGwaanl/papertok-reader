import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// A custom Markdown widget with theme-aware styling.
/// This widget provides better contrast and readability in both light and dark modes,
/// especially for blockquotes and code blocks that appear in AI chat responses.
class StyledMarkdown extends StatelessWidget {
  final String data;
  final bool selectable;

  const StyledMarkdown({
    super.key,
    required this.data,
    this.selectable = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return MarkdownBody(
      data: data,
      selectable: selectable,
      styleSheet: _buildStyleSheet(theme, isDark),
    );
  }

  MarkdownStyleSheet _buildStyleSheet(ThemeData theme, bool isDark) {
    final textColor = theme.colorScheme.onSurface;
    
    // For blockquotes, we need better contrast in dark mode
    final blockquoteBgColor = isDark 
        ? theme.colorScheme.surfaceContainer.withValues(alpha: 0.5)
        : theme.colorScheme.surfaceContainer.withValues(alpha: 0.3);
    
    final blockquoteBorderColor = isDark
        ? theme.colorScheme.primary.withValues(alpha: 0.5)
        : theme.colorScheme.primary;
    
    final codeBlockBgColor = isDark
        ? theme.colorScheme.surfaceContainer
        : theme.colorScheme.surfaceContainer.withValues(alpha: 0.5);

    return MarkdownStyleSheet(
      // Base text styles
      p: theme.textTheme.bodyMedium?.copyWith(color: textColor),
      h1: theme.textTheme.headlineLarge?.copyWith(color: textColor),
      h2: theme.textTheme.headlineMedium?.copyWith(color: textColor),
      h3: theme.textTheme.headlineSmall?.copyWith(color: textColor),
      h4: theme.textTheme.titleLarge?.copyWith(color: textColor),
      h5: theme.textTheme.titleMedium?.copyWith(color: textColor),
      h6: theme.textTheme.titleSmall?.copyWith(color: textColor),
      
      // Blockquote styling - this is the key fix for dark mode readability
      blockquote: theme.textTheme.bodyMedium?.copyWith(
        color: textColor,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        color: blockquoteBgColor,
        border: Border(
          left: BorderSide(
            color: blockquoteBorderColor,
            width: 4.0,
          ),
        ),
        borderRadius: BorderRadius.circular(4.0),
      ),
      
      // Code styling
      code: theme.textTheme.bodyMedium?.copyWith(
        fontFamily: 'monospace',
        backgroundColor: codeBlockBgColor,
        color: textColor,
      ),
      codeblockDecoration: BoxDecoration(
        color: codeBlockBgColor,
        borderRadius: BorderRadius.circular(4.0),
      ),
      
      // List styling
      listBullet: theme.textTheme.bodyMedium?.copyWith(color: textColor),
      
      // Link styling
      a: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
      
      // Other text styles
      em: theme.textTheme.bodyMedium?.copyWith(
        color: textColor,
        fontStyle: FontStyle.italic,
      ),
      strong: theme.textTheme.bodyMedium?.copyWith(
        color: textColor,
        fontWeight: FontWeight.bold,
      ),
      del: theme.textTheme.bodyMedium?.copyWith(
        color: textColor.withValues(alpha: 0.6),
        decoration: TextDecoration.lineThrough,
      ),
    );
  }
}
