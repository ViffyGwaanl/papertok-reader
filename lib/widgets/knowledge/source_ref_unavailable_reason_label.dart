import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/source_ref.dart';

const String legacyAiChatNoReaderDeepLinkReason =
    'AI chat message is stored in conversation history; no reader deep link is available for the chat bubble.';

String localizedSourceRefUnavailableReason(
  L10n l10n,
  String rawReason,
) {
  final reason = rawReason.trim();
  if (reason.isEmpty) return reason;
  if (reason == legacyAiChatNoReaderDeepLinkReason ||
      reason == 'ai-chat-no-reader-deep-link') {
    return l10n.sourceUnavailableAiChatNoReaderLink;
  }
  if (reason == 'sync-conflict-no-source') {
    return l10n.sourceUnavailableSyncConflictNoSource;
  }
  if (reason == 'book-note-source-not-jumpable') {
    return l10n.sourceUnavailableBookNoteNotJumpable;
  }
  if (reason == 'memory-source-not-jumpable') {
    return l10n.sourceUnavailableMemoryNotJumpable;
  }
  if (reason.startsWith('memory-source-not-jumpable:')) {
    final pointer = reason.split(':').skip(1).join(':').trim();
    if (pointer.isEmpty) return l10n.sourceUnavailableMemoryNotJumpable;
    return '${l10n.sourceUnavailableMemoryNotJumpable} $pointer';
  }
  return reason;
}

String localizedSourceRefUnavailableMessage(
  L10n l10n,
  Iterable<SourceRef> sourceRefs, {
  required String fallbackMessage,
}) {
  for (final ref in sourceRefs) {
    final reason = ref.unavailableReason?.trim();
    if (reason != null && reason.isNotEmpty) {
      return localizedSourceRefUnavailableReason(l10n, reason);
    }
  }
  return fallbackMessage;
}
