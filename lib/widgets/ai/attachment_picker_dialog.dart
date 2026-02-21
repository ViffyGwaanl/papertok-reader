import 'dart:convert';
import 'dart:typed_data';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/attachment_item.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// Attachment picker bottom sheet.
///
/// Responsibilities:
/// - Pick images from camera/photos/files
/// - Pick a plain-text file
/// - Compress images to JPEG (max 1536px, quality 82)
/// - Return selected attachments via [onPicked]
class AttachmentPickerDialog extends StatelessWidget {
  const AttachmentPickerDialog({
    super.key,
    required this.onPicked,
  });

  final void Function(List<AttachmentItem> items) onPicked;

  static const int _maxTextChars = 200000;
  static const int _maxImageSize = 1536;
  static const int _jpegQuality = 82;

  Future<void> _handlePick(
    BuildContext context,
    Future<List<AttachmentItem>> Function() picker,
  ) async {
    try {
      final items = await picker();
      if (items.isNotEmpty) {
        onPicked(items);
      }
    } finally {
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Uint8List? _compressToJpeg(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      final w = decoded.width;
      final h = decoded.height;

      img.Image resized = decoded;
      if (w > _maxImageSize || h > _maxImageSize) {
        final scale = _maxImageSize / (w > h ? w : h);
        final targetW = (w * scale).round().clamp(1, _maxImageSize);
        final targetH = (h * scale).round().clamp(1, _maxImageSize);
        resized = img.copyResize(decoded, width: targetW, height: targetH);
      }

      return Uint8List.fromList(img.encodeJpg(resized, quality: _jpegQuality));
    } catch (_) {
      return null;
    }
  }

  AttachmentItem? _bytesToImageAttachment(Uint8List originalBytes) {
    final jpegBytes = _compressToJpeg(originalBytes);
    if (jpegBytes == null || jpegBytes.isEmpty) return null;

    final base64 = base64Encode(jpegBytes);
    if (base64.isEmpty) return null;

    return AttachmentItem.image(bytes: jpegBytes, base64: base64);
  }

  Future<List<AttachmentItem>> _pickFromCamera() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera);
    if (image == null) return const [];

    final bytes = await image.readAsBytes();
    final item = _bytesToImageAttachment(bytes);
    return item == null ? const [] : [item];
  }

  Future<List<AttachmentItem>> _pickFromPhotos() async {
    final picker = ImagePicker();
    try {
      final images = await picker.pickMultiImage();
      if (images.isEmpty) return const [];

      final out = <AttachmentItem>[];
      for (final image in images) {
        final bytes = await image.readAsBytes();
        final item = _bytesToImageAttachment(bytes);
        if (item != null) out.add(item);
      }
      return out;
    } catch (_) {
      // Fallback for platforms that don't support pickMultiImage.
      final image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return const [];
      final bytes = await image.readAsBytes();
      final item = _bytesToImageAttachment(bytes);
      return item == null ? const [] : [item];
    }
  }

  Future<List<AttachmentItem>> _pickImageFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return const [];

    final out = <AttachmentItem>[];
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) continue;
      final item = _bytesToImageAttachment(bytes);
      if (item != null) out.add(item);
    }

    return out;
  }

  Future<List<AttachmentItem>> _pickTextFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'md', 'log', 'json'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return const [];

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return const [];

    final decoded = utf8.decode(bytes, allowMalformed: true);
    final text = decoded.length > _maxTextChars
        ? decoded.substring(0, _maxTextChars)
        : decoded;

    return [
      AttachmentItem.textFile(
        filename: file.name,
        bytes: Uint8List.fromList(utf8.encode(text)),
        text: text,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: Text(l10n.attachmentCamera),
            onTap: () => _handlePick(context, _pickFromCamera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: Text(l10n.attachmentPhotos),
            onTap: () => _handlePick(context, _pickFromPhotos),
          ),
          ListTile(
            leading: const Icon(Icons.image),
            title: Text(l10n.attachmentImages),
            onTap: () => _handlePick(context, _pickImageFiles),
          ),
          ListTile(
            leading: const Icon(Icons.description),
            title: Text(l10n.attachmentTextFile),
            onTap: () => _handlePick(context, _pickTextFile),
          ),
        ],
      ),
    );
  }
}
