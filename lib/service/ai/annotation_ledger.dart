/// Tracks annotations (highlights, notes) created by the AI agent during
/// the current conversation.
///
/// This ledger is injected into the system prompt so the agent knows what
/// it has already annotated, avoiding duplicates and enabling commands like
/// "list what you've highlighted so far".
///
/// Inspired by OpenMAIC's whiteboard ledger concept.
class AnnotationLedger {
  final _entries = <AnnotationLedgerEntry>[];

  /// Record a new highlight created by the agent.
  void addHighlight({
    required String text,
    required String chapterTitle,
    String? note,
    String? color,
  }) {
    _entries.add(AnnotationLedgerEntry(
      type: AnnotationType.highlight,
      text: text,
      chapterTitle: chapterTitle,
      note: note,
      color: color,
    ));
  }

  /// Record a new note created by the agent.
  void addNote({
    required String title,
    required String content,
    String? chapterTitle,
  }) {
    _entries.add(AnnotationLedgerEntry(
      type: AnnotationType.note,
      text: title,
      chapterTitle: chapterTitle,
      note: content,
    ));
  }

  /// Returns all entries.
  List<AnnotationLedgerEntry> get entries =>
      List.unmodifiable(_entries);

  /// Whether any annotations have been created this session.
  bool get isEmpty => _entries.isEmpty;

  /// Clear the ledger (e.g. when starting a new conversation).
  void clear() => _entries.clear();

  /// Format the ledger for injection into the system prompt.
  ///
  /// Returns empty string if no annotations exist.
  String toSystemPromptSection() {
    if (_entries.isEmpty) return '';

    final buffer = StringBuffer();
    buffer.writeln('\n## Annotations Created This Session');

    for (var i = 0; i < _entries.length; i++) {
      final e = _entries[i];
      final prefix = '${i + 1}.';
      switch (e.type) {
        case AnnotationType.highlight:
          final colorTag = e.color != null ? ' [${e.color}]' : '';
          buffer.write('$prefix Highlight$colorTag in "${e.chapterTitle}": ');
          buffer.write('"${_truncate(e.text, 80)}"');
          if (e.note != null && e.note!.isNotEmpty) {
            buffer.write(' — note: "${_truncate(e.note!, 60)}"');
          }
          buffer.writeln();
        case AnnotationType.note:
          buffer.write('$prefix Note');
          if (e.chapterTitle != null) {
            buffer.write(' (${e.chapterTitle})');
          }
          buffer.writeln(': "${_truncate(e.text, 80)}"');
      }
    }

    buffer.writeln(
      '\nDo not re-create annotations for passages already listed above.',
    );
    return buffer.toString();
  }

  static String _truncate(String s, int maxLen) {
    if (s.length <= maxLen) return s;
    return '${s.substring(0, maxLen)}...';
  }
}

enum AnnotationType { highlight, note }

class AnnotationLedgerEntry {
  const AnnotationLedgerEntry({
    required this.type,
    required this.text,
    this.chapterTitle,
    this.note,
    this.color,
  });

  final AnnotationType type;
  final String text;
  final String? chapterTitle;
  final String? note;
  final String? color;
}
