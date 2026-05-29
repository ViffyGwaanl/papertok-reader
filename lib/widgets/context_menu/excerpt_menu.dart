import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/constants/note_annotations.dart';
import 'package:papertok_reader/dao/book_note.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/book_note.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/page/settings_page/ai_seminar_runtime.dart';
import 'package:papertok_reader/page/settings_page/concept_graph_explorer.dart';
import 'package:papertok_reader/page/reading_page.dart';
import 'package:papertok_reader/service/deeplink/paperreader_reader_intent.dart';
import 'package:papertok_reader/service/knowledge/selection_knowledge_card_producer.dart';
import 'package:papertok_reader/service/reading/epub_player_key.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/theme/morandi_palette.dart';
import 'package:papertok_reader/utils/env_var.dart';
import 'package:papertok_reader/utils/page_transitions.dart';
import 'package:papertok_reader/utils/toast/common.dart';
import 'package:papertok_reader/widgets/book_share/excerpt_share_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:url_launcher/url_launcher.dart';

typedef ExcerptKnowledgeCardCreator
    = Future<SelectionKnowledgeCardProducerResult> Function({
  required int bookId,
  required String cfi,
  required String selectedText,
  String? chapterTitle,
  String? bookTitle,
});

class ExcerptKnowledgeCardReaderContext {
  const ExcerptKnowledgeCardReaderContext({
    required this.bookId,
    required this.bookTitle,
    this.chapterTitle,
  });

  final int bookId;
  final String bookTitle;
  final String? chapterTitle;
}

class ExcerptMenu extends StatefulWidget {
  final String annoCfi;
  final String annoContent;
  final int? id;
  final Function() onClose;
  final bool footnote;
  final BoxDecoration decoration;
  final Future<void> Function() onTranslate;
  final void Function({bool? show}) toggleReaderNoteMenu;
  final Future<void> Function(int noteId) openReaderNoteMenu;
  final void Function(int noteId) onNoteCreated;
  final Axis axis;
  final bool reverse;
  final ExcerptKnowledgeCardReaderContext? knowledgeCardReaderContext;
  final ExcerptKnowledgeCardCreator? knowledgeCardCreator;
  final ValueChanged<String>? knowledgeCardFeedback;

  const ExcerptMenu({
    super.key,
    required this.annoCfi,
    required this.annoContent,
    this.id,
    required this.onClose,
    required this.footnote,
    required this.decoration,
    required this.onTranslate,
    required this.toggleReaderNoteMenu,
    required this.openReaderNoteMenu,
    required this.onNoteCreated,
    required this.axis,
    required this.reverse,
    this.knowledgeCardReaderContext,
    this.knowledgeCardCreator,
    this.knowledgeCardFeedback,
  });

  @override
  ExcerptMenuState createState() => ExcerptMenuState();
}

class ExcerptMenuState extends State<ExcerptMenu> {
  bool deleteConfirm = false;
  bool _showAnnotationPanel = false;
  int? noteId;
  BookNote? _currentNote;
  late String annoType;
  late String annoColor;

  @override
  initState() {
    super.initState();
    annoType = Prefs().annotationType;
    annoColor = Prefs().annotationColor;
    _initializeExistingNote();
  }

  Future<void> _initializeExistingNote() async {
    final existingId = widget.id;
    if (existingId == null) {
      return;
    }

    try {
      final note = await bookNoteDao.selectBookNoteById(existingId);
      if (!mounted) {
        return;
      }
      setState(() {
        _currentNote = note;
        noteId = note.id;
        annoType = note.type;
        annoColor = note.color;
      });
      if (!widget.footnote &&
          note.readerNote != null &&
          note.readerNote!.isNotEmpty) {
        await widget.openReaderNoteMenu(note.id!);
      }
    } catch (_) {
      // When the note cannot be loaded we keep the defaults from Prefs.
    }
  }

  Future<BookNote?> _fetchLatestNote() async {
    final existingId = noteId ?? widget.id;
    if (existingId == null) {
      return null;
    }

    try {
      return await bookNoteDao.selectBookNoteById(existingId);
    } catch (_) {
      return null;
    }
  }

  Future<BookNote> _persistNote(
      {String? color, String? type, String? content}) async {
    final existingNote = await _fetchLatestNote() ?? _currentNote;
    final now = DateTime.now();

    final resolvedContent = (content ?? widget.annoContent).trim().isNotEmpty
        ? (content ?? widget.annoContent)
        : (existingNote?.content ?? widget.annoContent);
    final resolvedType = type ?? existingNote?.type ?? annoType;
    final resolvedColor = color ?? existingNote?.color ?? annoColor;

    final BookNote bookNote = BookNote(
      id: existingNote?.id ?? widget.id,
      bookId:
          existingNote?.bookId ?? epubPlayerKey.currentState!.widget.book.id,
      content: resolvedContent,
      cfi: existingNote?.cfi ?? widget.annoCfi,
      chapter:
          existingNote?.chapter ?? epubPlayerKey.currentState!.chapterTitle,
      type: resolvedType,
      color: resolvedColor,
      readerNote: existingNote?.readerNote,
      createTime: existingNote?.createTime ?? now,
      updateTime: now,
    );

    final id = await bookNoteDao.save(bookNote);
    bookNote.setId(id);
    widget.onNoteCreated(id);

    if (mounted) {
      setState(() {
        _currentNote = bookNote;
        noteId = id;
        annoType = resolvedType;
        annoColor = resolvedColor;
      });
    } else {
      _currentNote = bookNote;
      noteId = id;
      annoType = resolvedType;
      annoColor = resolvedColor;
    }

    return bookNote;
  }

  void _toggleAnnotationPanel() {
    setState(() {
      _showAnnotationPanel = !_showAnnotationPanel;
    });
  }

  Icon deleteIcon() {
    return deleteConfirm
        ? Icon(
            EvaIcons.close_circle,
            color: MorandiPalette.error(context),
          )
        : const Icon(Icons.delete_outline_rounded);
  }

  void deleteHandler() {
    if (deleteConfirm) {
      if (widget.id != null) {
        bookNoteDao.deleteBookNoteById(widget.id!);
        epubPlayerKey.currentState!.removeAnnotation(widget.annoCfi);
      }
      widget.onClose();
    } else {
      setState(() {
        deleteConfirm = true;
      });
    }
  }

  Future<void> onColorSelected(String color, {bool close = true}) async {
    Prefs().annotationColor = color;
    if (mounted) {
      setState(() {
        annoColor = color;
      });
    } else {
      annoColor = color;
    }
    final bookNote = await _persistNote(color: color);
    epubPlayerKey.currentState!.addAnnotation(bookNote);
    if (close) {
      widget.onClose();
    }
  }

  Future<void> onTypeSelected(String type) async {
    Prefs().annotationType = type;
    if (mounted) {
      setState(() {
        annoType = type;
      });
    } else {
      annoType = type;
    }
    final bookNote = await _persistNote(type: type);
    epubPlayerKey.currentState!.addAnnotation(bookNote);
  }

  Future<void> _createKnowledgeCardFromSelection() async {
    final l10n = L10n.of(context);
    final readerContext = _knowledgeCardReaderContext();
    if (readerContext == null) {
      _showKnowledgeCardFeedback(l10n.knowledgeCardAddFailed);
      return;
    }

    try {
      final creator = widget.knowledgeCardCreator ??
          ({
            required int bookId,
            required String cfi,
            required String selectedText,
            String? chapterTitle,
            String? bookTitle,
          }) =>
              SelectionKnowledgeCardProducer().createFromSelection(
                bookId: bookId,
                cfi: cfi,
                selectedText: selectedText,
                chapterTitle: chapterTitle,
                bookTitle: bookTitle,
              );
      final result = await creator(
        bookId: readerContext.bookId,
        cfi: widget.annoCfi,
        selectedText: widget.annoContent,
        chapterTitle: readerContext.chapterTitle,
        bookTitle: readerContext.bookTitle,
      );
      if (!mounted) return;
      final message = result.addedToReviewInbox
          ? (result.inserted
              ? l10n.knowledgeCardAddedToReviewInbox
              : l10n.knowledgeCardAlreadyInReviewInbox)
          : l10n.knowledgeCardAlreadySaved;
      _showKnowledgeCardFeedback(message);
      widget.onClose();
    } catch (_) {
      if (mounted) {
        _showKnowledgeCardFeedback(l10n.knowledgeCardAddFailed);
      }
    }
  }

  ExcerptKnowledgeCardReaderContext? _knowledgeCardReaderContext() {
    if (widget.knowledgeCardReaderContext case final injected?) {
      return injected;
    }
    final player = epubPlayerKey.currentState;
    if (player == null) return null;
    return ExcerptKnowledgeCardReaderContext(
      bookId: player.widget.book.id,
      bookTitle: player.book.title,
      chapterTitle: player.chapterTitle,
    );
  }

  void _showKnowledgeCardFeedback(String message) {
    final feedback = widget.knowledgeCardFeedback;
    if (feedback != null) {
      feedback(message);
      return;
    }
    AnxToast.show(message);
  }

  Future<void> _openSeminarFromSelection() async {
    final l10n = L10n.of(context);
    final prompt = l10n.contextMenuSeminarPrompt(
      widget.annoContent.trim(),
    );
    final bookId = epubPlayerKey.currentState?.widget.book.id;
    widget.onClose();
    Prefs().activeAiSkillId = 'seminar_mode';
    if (!mounted) return;
    Navigator.of(context).push(
      CupertinoStyleRoute(
        page: AiSeminarRuntimePage(
          initialQuestion: prompt,
          bookId: bookId,
        ),
      ),
    );
  }

  void _openConceptGraphFromSelection() {
    final query = widget.annoContent.trim();
    widget.onClose();
    Navigator.of(context).push(
      CupertinoStyleRoute(
        page: ConceptGraphExplorerPage(
          initialQuery: query.isEmpty ? null : query,
        ),
      ),
    );
  }

  SourceRef? _selectionSourceRef() {
    final player = epubPlayerKey.currentState;
    if (player == null) return null;
    final bookId = player.widget.book.id;
    final cfi = widget.annoCfi.trim();
    final intent = PaperReaderReaderIntent(bookId: bookId, cfi: cfi);
    return SourceRef(
      bookId: bookId,
      cfi: cfi,
      jumpLink: intent.hasTarget ? intent.toUri().toString() : null,
      sourceTitle: player.book.title,
      locationLabel: player.chapterTitle,
      sourceTextSnippet: widget.annoContent,
      sourceTextForHash: widget.annoContent,
      sourceKind: SourceRefKind.reader,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Widget _actionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final isDark = !Prefs().eInkMode;
    final foreground = ClaudePalette.fg(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 18,
                    color: foreground.withValues(alpha: isDark ? 0.96 : 1)),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.05,
                    color: foreground.withValues(alpha: isDark ? 0.88 : 0.92),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _annotationTypeButton(
      BuildContext context, String type, IconData icon) {
    final active = annoType == type;
    final colors = Theme.of(context).colorScheme;
    final highlight = Color(int.parse('0xff$annoColor'));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onTypeSelected(type),
        child: Ink(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: active
                ? highlight.withValues(alpha: 0.16)
                : colors.surface.withValues(alpha: 0.44),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active
                  ? highlight.withValues(alpha: 0.55)
                  : colors.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: active ? highlight : colors.onSecondaryContainer,
          ),
        ),
      ),
    );
  }

  Widget _colorButton(BuildContext context, String color) {
    final active = annoColor == color;
    final swatch = Color(int.parse('0xff$color'));
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => onColorSelected(color),
        child: Ink(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: swatch.withValues(alpha: 0.86),
            border: Border.all(
              color: active
                  ? colors.onSecondaryContainer
                  : swatch.withValues(alpha: 0.18),
              width: active ? 2.2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: swatch.withValues(alpha: 0.22),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _smallRoundButton({
    required BuildContext context,
    required Icon icon,
    required VoidCallback onPressed,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Ink(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.52),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Center(child: icon),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actionButtons = <Widget>[
      _actionButton(
        context: context,
        icon: EvaIcons.copy,
        label: L10n.of(context).contextMenuCopy,
        onTap: () {
          Clipboard.setData(ClipboardData(text: widget.annoContent));
          AnxToast.show(L10n.of(context).notesPageCopied);
          widget.onClose();
        },
      ),
      _actionButton(
        context: context,
        icon: EvaIcons.globe,
        label: L10n.of(context).contextMenuSearch,
        onTap: () {
          widget.onClose();
          launchUrl(
            Uri.parse('https://www.bing.com/search?q=${widget.annoContent}'),
            mode: LaunchMode.externalApplication,
          );
        },
      ),
      _actionButton(
        context: context,
        icon: Icons.translate_rounded,
        label: L10n.of(context).contextMenuTranslate,
        onTap: () {
          widget.onTranslate();
        },
      ),
      if (!widget.footnote)
        _actionButton(
          context: context,
          icon: Icons.format_color_text_rounded,
          label: L10n.of(context).contextMenuHighlight,
          onTap: _toggleAnnotationPanel,
        ),
      if (!widget.footnote)
        _actionButton(
          context: context,
          icon: EvaIcons.edit_2_outline,
          label: L10n.of(context).contextMenuWriteIdea,
          onTap: () async {
            epubPlayerKey.currentState?.setSelectionClearLocked(true);
            await onColorSelected(annoColor, close: false);
            final targetId = noteId ?? widget.id;
            if (targetId != null) {
              await widget.openReaderNoteMenu(targetId);
            } else {
              widget.toggleReaderNoteMenu(show: true);
            }
          },
        ),
      if (EnvVar.enableAIFeature)
        _actionButton(
          context: context,
          icon: Icons.style_outlined,
          label: L10n.of(context).contextMenuKnowledgeCard,
          onTap: () {
            _createKnowledgeCardFromSelection();
          },
        ),
      if (EnvVar.enableAIFeature)
        _actionButton(
          context: context,
          icon: Icons.groups_outlined,
          label: L10n.of(context).contextMenuSeminar,
          onTap: () {
            _openSeminarFromSelection();
          },
        ),
      if (EnvVar.enableAIFeature)
        _actionButton(
          context: context,
          icon: Icons.account_tree_outlined,
          label: L10n.of(context).contextMenuConceptGraph,
          onTap: _openConceptGraphFromSelection,
        ),
      if (EnvVar.enableAIFeature)
        _actionButton(
          context: context,
          icon: EvaIcons.message_circle_outline,
          label: L10n.of(context).navBarAI,
          onTap: () {
            widget.onClose();
            final key = readingPageKey.currentState;
            if (key != null) {
              final sourceRef = _selectionSourceRef();
              key.showAiChat(
                content: widget.annoContent,
                sendImmediate: false,
                sourceRef: sourceRef,
              );
              key.aiChatKey.currentState?.prefillDraft(
                message: widget.annoContent,
                sourceRef: sourceRef,
              );
            }
          },
        ),
      _actionButton(
        context: context,
        icon: EvaIcons.share_outline,
        label: L10n.of(context).contextMenuShare,
        onTap: () {
          widget.onClose();
          ExcerptShareService.showShareExcerpt(
            context: context,
            bookTitle: epubPlayerKey.currentState!.book.title,
            author: epubPlayerKey.currentState!.book.author,
            excerpt: widget.annoContent,
            chapter: epubPlayerKey.currentState!.chapterTitle,
          );
        },
      ),
    ];

    final toolbarDecoration = widget.decoration.copyWith(
      borderRadius: BorderRadius.circular(14),
    );
    final secondaryDecoration = widget.decoration.copyWith(
      borderRadius: BorderRadius.circular(14),
    );

    final panelWidth = widget.axis == Axis.vertical ? 360.0 : 380.0;

    return SizedBox(
      width: panelWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: toolbarDecoration,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: actionButtons),
            ),
          ),
          if (!widget.footnote && _showAnnotationPanel) ...[
            const SizedBox(height: 8),
            Container(
              decoration: secondaryDecoration,
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        L10n.of(context).contextMenuHighlight,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color:
                              ClaudePalette.fg(context).withValues(alpha: 0.72),
                        ),
                      ),
                      const Spacer(),
                      _smallRoundButton(
                        context: context,
                        icon: deleteIcon(),
                        onPressed: deleteHandler,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final type in notesType)
                        _annotationTypeButton(
                          context,
                          type.type,
                          type.icon,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final color in notesColors)
                        _colorButton(context, color),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
