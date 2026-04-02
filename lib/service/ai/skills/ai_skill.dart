/// A skill is a reusable prompt template that augments the AI's system prompt
/// with domain-specific instructions and starter messages.
class AiSkill {
  const AiSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.systemPromptAppend,
    this.starterMessages = const [],
    this.iconCodePoint,
    this.isBuiltIn = true,
  });

  final String id;
  final String name;
  final String description;

  /// Text appended to the base system prompt when this skill is active.
  final String systemPromptAppend;

  /// Suggested first messages shown as quick-prompt chips.
  final List<String> starterMessages;

  /// Material icon code point (e.g. Icons.science.codePoint).
  final int? iconCodePoint;

  /// Whether this is a built-in skill (cannot be deleted).
  final bool isBuiltIn;
}
