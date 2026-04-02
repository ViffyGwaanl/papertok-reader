class CreateNoteInput {
  const CreateNoteInput({
    required this.content,
    required this.cfi,
    this.chapter,
    this.color,
  });

  final String content;
  final String cfi;
  final String? chapter;
  final String? color;

  factory CreateNoteInput.fromJson(Map<String, dynamic> json) {
    return CreateNoteInput(
      content: json['content'] as String,
      cfi: json['cfi'] as String,
      chapter: json['chapter'] as String?,
      color: json['color'] as String?,
    );
  }
}
