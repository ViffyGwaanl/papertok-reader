import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:flutter/material.dart';

Future<void> showSelectionTranslationSheet(
  BuildContext context, {
  required String content,
  String? contextText,
}) async {
  final size = MediaQuery.of(context).size;
  final bool wide = size.width >= 700;

  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      if (wide) {
        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 680,
                maxHeight: 760,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _SelectionTranslationSheet(
                  content: content,
                  contextText: contextText,
                ),
              ),
            ),
          ),
        );
      }

      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.7,
        maxChildSize: 0.98,
        builder: (ctx, scrollController) {
          return _SelectionTranslationSheet(
            content: content,
            contextText: contextText,
            scrollController: scrollController,
          );
        },
      );
    },
  );
}

class _SelectionTranslationSheet extends StatefulWidget {
  const _SelectionTranslationSheet({
    required this.content,
    this.contextText,
    this.scrollController,
  });

  final String content;
  final String? contextText;
  final ScrollController? scrollController;

  @override
  State<_SelectionTranslationSheet> createState() =>
      _SelectionTranslationSheetState();
}

class _SelectionTranslationSheetState
    extends State<_SelectionTranslationSheet> {
  String? _translationText;
  String? _translationError;
  bool _loading = false;

  Future<void> _continueAskAi() async {
    final translation = _translationText?.trim() ?? '';
    if (translation.isEmpty) {
      AnxToast.show(L10n.of(context).commonFailed);
      return;
    }

    final prompt = '''${L10n.of(context).translationContinueAskPrefill}

${L10n.of(context).translationOriginalLabel}
${widget.content}

${L10n.of(context).translationResultLabel}
$translation

${L10n.of(context).translationLanguageLabel}
${Prefs().translateFrom.getNative(context)} → ${Prefs().translateTo.getNative(context)}''';
    Navigator.of(context).pop();
    await Future<void>.delayed(Duration.zero);
    final reading = readingPageKey.currentState;
    if (reading == null) return;
    await reading.openAiChatDraft(content: prompt);
  }

  @override
  void initState() {
    super.initState();
    _refreshTranslation();
  }

  Future<void> _refreshTranslation() async {
    final effectiveContextText = (widget.contextText?.trim().isEmpty ?? true)
        ? null
        : widget.contextText;
    setState(() {
      _loading = true;
      _translationError = null;
    });
    try {
      final translated = await translateTextOnly(
        widget.content,
        contextText: effectiveContextText,
      );
      if (!mounted) return;
      setState(() {
        _translationText = translated;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _translationError = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickLang(bool isFrom) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return ListView.builder(
          itemCount: LangListEnum.values.length,
          itemBuilder: (ctx, index) {
            final lang = LangListEnum.values[index];
            return ListTile(
              title: Text(lang.getNative(ctx)),
              subtitle: Text(
                lang.name[0].toUpperCase() + lang.name.substring(1),
              ),
              trailing:
                  ((isFrom ? Prefs().translateFrom : Prefs().translateTo) ==
                          lang)
                      ? const Icon(Icons.check)
                      : null,
              onTap: () {
                if (isFrom) {
                  Prefs().translateFrom = lang;
                } else {
                  Prefs().translateTo = lang;
                }
                Navigator.of(ctx).pop();
              },
            );
          },
        );
      },
    );
    if (!mounted) return;
    _refreshTranslation();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = !Prefs().eInkMode;
    final background = isDark ? const Color(0xFF24262B) : colors.surface;
    final foreground = isDark ? Colors.white : colors.onSurface;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.08)
                : colors.outlineVariant.withOpacity(0.24),
          ),
          boxShadow: [
            if (isDark)
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 32,
                spreadRadius: -10,
                offset: const Offset(0, 16),
              ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 5,
                    decoration: BoxDecoration(
                      color: foreground.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        L10n.of(context).contextMenuTranslate,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: foreground,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _refreshTranslation,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    TextButton(
                      onPressed: _continueAskAi,
                      child: Text(L10n.of(context).translationContinueAskAi),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    controller: widget.scrollController,
                    padding: EdgeInsets.zero,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withOpacity(0.05)
                              : colors.surfaceContainerHighest
                                  .withOpacity(0.58),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withOpacity(0.06)
                                : colors.outlineVariant.withOpacity(0.16),
                          ),
                        ),
                        child: Text(
                          widget.content,
                          maxLines: 8,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.4,
                            color: foreground.withOpacity(0.78),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.black.withOpacity(0.16)
                              : colors.surfaceContainerHigh.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            _LangButton(
                              label: Prefs().translateFrom.getNative(context),
                              onTap: () => _pickLang(true),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: Icon(
                                Icons.arrow_forward_rounded,
                                size: 18,
                                color: foreground.withOpacity(0.68),
                              ),
                            ),
                            _LangButton(
                              label: Prefs().translateTo.getNative(context),
                              onTap: () => _pickLang(false),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 220),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withOpacity(0.05)
                              : colors.surfaceContainerHighest
                                  .withOpacity(0.58),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withOpacity(0.06)
                                : colors.outlineVariant.withOpacity(0.16),
                          ),
                        ),
                        child: _loading
                            ? const SizedBox(
                                height: 120,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            : _translationError != null
                                ? Text(_translationError!)
                                : SelectableText(_translationText ?? ''),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LangButton extends StatelessWidget {
  const _LangButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.expand_more, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
