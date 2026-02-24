import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared draft input for the AI chat text field.
///
/// This allows other pages (e.g. Memory settings) to insert snippets into the
/// current AI chat input.
final aiChatDraftInputProvider =
    StateNotifierProvider<AiChatDraftInputNotifier, String>((ref) {
  return AiChatDraftInputNotifier();
});

class AiChatDraftInputNotifier extends StateNotifier<String> {
  AiChatDraftInputNotifier() : super('');

  void set(String value) {
    state = value;
  }

  void clear() {
    state = '';
  }

  /// Insert [text] at the end of the current draft.
  ///
  /// This is intentionally simple; the chat UI owns cursor position.
  void append(String text, {String separatorIfNeeded = '\n'}) {
    final t = text;
    if (t.trim().isEmpty) return;

    final cur = state;
    if (cur.trim().isEmpty) {
      state = t;
      return;
    }

    final sep = separatorIfNeeded;
    if (sep.isEmpty) {
      state = '$cur$t';
      return;
    }

    if (cur.endsWith(sep) || t.startsWith(sep)) {
      state = '$cur$t';
    } else {
      state = '$cur$sep$t';
    }
  }
}
