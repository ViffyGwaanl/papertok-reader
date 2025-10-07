import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/book_share/excerpt_share_service.dart';
import 'package:anx_reader/widgets/context_menu/reader_note_menu.dart';
import 'package:anx_reader/widgets/icon_and_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:url_launcher/url_launcher.dart';

List<String> notesColors = ['66CCFF', 'FF0000', '00FF00', 'EB3BFF', 'FFD700'];
List<Map<String, dynamic>> notesType = [
  {
    'type': 'highlight',
    'icon': AntDesign.highlight_outline,
  },
  {
    'type': 'underline',
    'icon': Icons.format_underline,
  },
];

class ExcerptMenu extends StatefulWidget {
  final String annoCfi;
  final String annoContent;
  final int? id;
  final Function() onClose;
  final bool footnote;
  final BoxDecoration decoration;
  final Function() toggleTranslationMenu;

  const ExcerptMenu({
    super.key,
    required this.annoCfi,
    required this.annoContent,
    this.id,
    required this.onClose,
    required this.footnote,
    required this.decoration,
    required this.toggleTranslationMenu,
  });

  @override
  ExcerptMenuState createState() => ExcerptMenuState();
}

class ExcerptMenuState extends State<ExcerptMenu> {
  bool deleteConfirm = false;
  late final GlobalKey<ReaderNoteMenuState> readerNoteMenuKey;
  int? noteId;
  BookNote? _currentNote;
  late String annoType;
  late String annoColor;

  @override
  initState() {
    super.initState();
    readerNoteMenuKey = GlobalKey<ReaderNoteMenuState>();
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
      final note = await selectBookNoteById(existingId);
      if (!mounted) {
        return;
      }
      setState(() {
        _currentNote = note;
        noteId = note.id;
        annoType = note.type;
        annoColor = note.color;
      });
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
      return await selectBookNoteById(existingId);
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

    final id = await insertBookNote(bookNote);
    bookNote.setId(id);

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

  Icon deleteIcon() {
    return deleteConfirm
        ? const Icon(
            EvaIcons.close_circle,
            color: Colors.red,
          )
        : const Icon(Icons.delete);
  }

  void deleteHandler() {
    if (deleteConfirm) {
      if (widget.id != null) {
        deleteBookNoteById(widget.id!);
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

  Widget iconButton({required Icon icon, required Function() onPressed}) {
    return IconButton(
      padding: const EdgeInsets.all(2),
      constraints: const BoxConstraints(),
      style: const ButtonStyle(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: icon,
      onPressed: onPressed,
    );
  }

  Widget colorButton(String color) {
    return iconButton(
      icon: Icon(
        Icons.circle,
        color: Color(int.parse('0x88$color')),
      ),
      onPressed: () {
        onColorSelected(color);
      },
    );
  }

  Widget typeButton(String type, IconData icon) {
    return iconButton(
      icon: Icon(icon,
          color: annoType == type ? Color(int.parse('0xff$annoColor')) : null),
      onPressed: () {
        onTypeSelected(type);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget annotationMenu = Container(
      height: 48,
      decoration: widget.decoration,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconButton(
            onPressed: deleteHandler,
            icon: deleteIcon(),
          ),
          for (Map<String, dynamic> type in notesType)
            typeButton(type['type'], type['icon']),
          for (String color in notesColors) colorButton(color),
        ],
      ),
    );

    Widget operatorMenu = Container(
      height: 48,
      decoration: widget.decoration,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // copy
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: widget.annoContent));
              AnxToast.show(L10n.of(context).notesPageCopied);
              widget.onClose();
            },
            child: IconAndText(
              icon: const Icon(EvaIcons.copy),
              text: L10n.of(context).contextMenuCopy,
            ),
          ),
          // Web search
          InkWell(
            onTap: () {
              widget.onClose();
              launchUrl(
                Uri.parse(
                    'https://www.bing.com/search?q=${widget.annoContent}'),
                mode: LaunchMode.externalApplication,
              );
            },
            child: IconAndText(
              icon: const Icon(EvaIcons.globe),
              text: L10n.of(context).contextMenuSearch,
            ),
          ),
          // toggle translation menu
          InkWell(
            onTap: widget.toggleTranslationMenu,
            child: IconAndText(
              icon: const Icon(Icons.translate),
              text: L10n.of(context).contextMenuTranslate,
            ),
          ),
          // edit note
          if (!widget.footnote)
            InkWell(
              onTap: () async {
                await onColorSelected(annoColor, close: false);
                // update that noteId is not null
                setState(() {});
                await readerNoteMenuKey.currentState!.showNoteDialog(noteId!);
              },
              child: IconAndText(
                icon: const Icon(EvaIcons.edit_2_outline),
                text: L10n.of(context).contextMenuWriteIdea,
              ),
            ),
          // AI chat
          InkWell(
            onTap: () {
              widget.onClose();
              final key = readingPageKey.currentState;
              if (key != null) {
                key.showAiChat(
                  content: widget.annoContent,
                  sendImmediate: false,
                );
                key.aiChatKey.currentState?.inputController.text =
                    widget.annoContent;
              }
            },
            child: IconAndText(
              icon: const Icon(EvaIcons.message_circle_outline),
              text: L10n.of(context).aiChat,
            ),
          ),
          // share
          InkWell(
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
            child: IconAndText(
              icon: const Icon(EvaIcons.share_outline),
              text: L10n.of(context).contextMenuShare,
            ),
          ),
        ],
      ),
    );

    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                  scrollDirection: Axis.horizontal, child: operatorMenu),
              const SizedBox(height: 10),
              if (!widget.footnote)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: annotationMenu,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ReaderNoteMenu(
                key: readerNoteMenuKey,
                noteId: noteId ?? widget.id,
                decoration: widget.decoration,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
