/// Defines the scene/context in which an AI tool is available.
///
/// Tools declare which scenes they belong to via [AiToolDefinition.scenes].
/// The agent pipeline filters tools based on the current scene,
/// reducing system prompt token count and improving tool selection accuracy.
enum AiToolScene {
  /// Always available regardless of context.
  global,

  /// Available only when the user is actively reading a book.
  reading,

  /// Available in the library/bookshelf context.
  library,

  /// System-level tools (calendar, reminders, shortcuts).
  system,
}
