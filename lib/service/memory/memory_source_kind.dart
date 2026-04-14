/// Discriminator for how a MemoryCandidate was produced.
///
/// `reading` means the user was actively in a book when the candidate was
/// captured, so `bookId` / `cfi` / `chapter` fields should be populated.
/// `chat` means a pure chat-session digest. `manual` means the user
/// explicitly saved text to memory.
enum MemorySourceKind {
  chat('chat'),
  reading('reading'),
  manual('manual');

  final String asString;
  const MemorySourceKind(this.asString);

  static MemorySourceKind fromString(String? value) {
    for (final k in MemorySourceKind.values) {
      if (k.asString == value) return k;
    }
    return MemorySourceKind.chat;
  }
}
