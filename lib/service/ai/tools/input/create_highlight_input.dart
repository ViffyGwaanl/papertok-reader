class CreateHighlightInput {
  const CreateHighlightInput({
    required this.text,
    required this.cfi,
    this.note,
    this.color,
  });

  final String text;
  final String cfi;
  final String? note;
  final String? color;

  factory CreateHighlightInput.fromJson(Map<String, dynamic> json) {
    return CreateHighlightInput(
      text: json['text'] as String,
      cfi: json['cfi'] as String,
      note: json['note'] as String?,
      color: json['color'] as String?,
    );
  }
}
