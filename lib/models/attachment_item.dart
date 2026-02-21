import 'dart:typed_data';
import 'package:meta/meta.dart';

/// Attachment type for user messages
enum AttachmentType {
  image,
  textFile,
}

/// Represents an attached item (image or text file)
@immutable
class AttachmentItem {
  const AttachmentItem({
    required this.type,
    this.filename,
    required this.bytes,
    this.base64,
    this.text,
  });

  final AttachmentType type;
  final String? filename;
  final Uint8List bytes;
  final String? base64; // For images (without data: prefix)
  final String? text; // For text files

  /// Create an image attachment with base64 data
  factory AttachmentItem.image({
    required Uint8List bytes,
    required String base64,
  }) {
    return AttachmentItem(
      type: AttachmentType.image,
      bytes: bytes,
      base64: base64,
    );
  }

  /// Create a text file attachment
  factory AttachmentItem.textFile({
    required String filename,
    required Uint8List bytes,
    required String text,
  }) {
    return AttachmentItem(
      type: AttachmentType.textFile,
      filename: filename,
      bytes: bytes,
      text: text,
    );
  }

  AttachmentItem copyWith({
    AttachmentType? type,
    String? filename,
    Uint8List? bytes,
    String? base64,
    String? text,
  }) {
    return AttachmentItem(
      type: type ?? this.type,
      filename: filename ?? this.filename,
      bytes: bytes ?? this.bytes,
      base64: base64 ?? this.base64,
      text: text ?? this.text,
    );
  }
}
