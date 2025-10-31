import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/widgets/common/axis_flex.dart';
import 'package:flutter/material.dart';
import 'package:icons_plus/icons_plus.dart';

class ReaderNoteMenu extends StatefulWidget {
  const ReaderNoteMenu({
    super.key,
    this.noteId,
    required this.decoration,
    required this.axis,
  });

  final int? noteId;
  final BoxDecoration decoration;
  final Axis axis;

  @override
  State<ReaderNoteMenu> createState() => ReaderNoteMenuState();
}

class ReaderNoteMenuState extends State<ReaderNoteMenu> {
  BookNote? note;
  bool isLoading = true;
  bool _showNoteDialog = false;
  final textFieldController = TextEditingController();
  bool showSaveButton = false;
  int? noteId;

  @override
  void initState() {
    super.initState();
    if (mounted) {
      getNoteDetail(widget.noteId);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> getNoteDetail(int? id) async {
    if (id == null) return;
    try {
      note = await selectBookNoteById(id);

      if (note != null &&
          note!.readerNote != null &&
          note!.readerNote!.isNotEmpty) {
        textFieldController.text = note!.readerNote!;
        setState(() {
          _showNoteDialog = true;
        });
      }
    } finally {
      isLoading = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> showNoteDialog(int noteId) async {
    await getNoteDetail(noteId);
    setState(() {
      _showNoteDialog = true;
    });
  }

  void saveNote() {
    textFieldController.text = textFieldController.text.trim();
    note!.readerNote = textFieldController.text;
    updateBookNoteById(note!);
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
        child: AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: widget.axis == Axis.vertical ? double.infinity : 200,
          maxWidth: widget.axis == Axis.vertical ? 100 : double.infinity,
        ),
        child: !_showNoteDialog
            ? null
            : Container(
                decoration: widget.decoration,
                padding: const EdgeInsets.all(8),
                child: AxisFlex(
                  reverse: false,
                  axis: widget.axis,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        // scrollDirection: widget.axis,
                        child: TextField(
                          controller: textFieldController,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: L10n.of(context).contextMenuAddNoteTips,
                          ),
                          maxLines: widget.axis == Axis.vertical
                              ? double.maxFinite.toInt()
                              : 5,
                          minLines: 1,
                          onSubmitted: (String value) {
                            saveNote();
                          },
                          onChanged: (String value) {
                            setState(() {
                              showSaveButton = true;
                            });
                          },
                        ),
                      ),
                    ),
                    if (showSaveButton)
                      IconButton(
                        icon: const Icon(EvaIcons.checkmark_circle_2_outline),
                        onPressed: () {
                          saveNote();
                          // remove focus
                          FocusScope.of(context).unfocus();
                          setState(() {
                            showSaveButton = false;
                          });
                        },
                      ),
                    const Spacer(),
                  ],
                ),
              ),
      ),
    ));
  }
}
