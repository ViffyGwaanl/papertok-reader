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

  // NOTE:
  // Some OpenAI-compatible gateways incorrectly count base64 image payloads as
  // text tokens. To avoid `context_length_exceeded` even on the first request,
  // we cap JPEG output bytes aggressively.
  static const int _maxImageSizeSingle = 1024;
  static const int _jpegQualitySingle = 78;
  static const int _maxImageSizeMulti = 896;
  static const int _jpegQualityMulti = 72;

  // Hard cap for encoded JPEG bytes (before base64). Keeping this small avoids
  // naive "tokenize the base64" servers from exploding prompt tokens.
  static const int _maxJpegBytesSingle = 350 * 1024;
  static const int _maxJpegBytesMulti = 280 * 1024;

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

  Uint8List? _compressToJpeg(
    img.Image decoded, {
    required int maxSize,
    required int quality,
  }) {
    final w = decoded.width;
    final h = decoded.height;

    img.Image resized = decoded;
    if (w > maxSize || h > maxSize) {
      final scale = maxSize / (w > h ? w : h);
      final targetW = (w * scale).round().clamp(1, maxSize);
      final targetH = (h * scale).round().clamp(1, maxSize);
      resized = img.copyResize(decoded, width: targetW, height: targetH);
    }

    return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  }

  Uint8List? _compressToJpegCapped(
    Uint8List bytes, {
    required int maxSize,
    required int quality,
    required int maxBytes,
  }) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      var currentMaxSize = maxSize;
      var currentQuality = quality;

      for (var attempt = 0; attempt < 10; attempt++) {
        final jpeg = _compressToJpeg(
          decoded,
          maxSize: currentMaxSize,
          quality: currentQuality,
        );
        if (jpeg == null || jpeg.isEmpty) return null;

        if (jpeg.lengthInBytes <= maxBytes) {
          return jpeg;
        }

        // Degrade quality first, then resolution.
        if (currentQuality > 50) {
          currentQuality = (currentQuality - 8).clamp(50, 95);
        } else if (currentMaxSize > 640) {
          currentMaxSize = (currentMaxSize * 0.85).round().clamp(640, maxSize);
        } else {
          // Give up further shrinking.
          return jpeg;
        }
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  AttachmentItem? _bytesToImageAttachment(
    Uint8List originalBytes, {
    required int maxSize,
    required int quality,
    required int maxBytes,
  }) {
    final jpegBytes = _compressToJpegCapped(
      originalBytes,
      maxSize: maxSize,
      quality: quality,
      maxBytes: maxBytes,
    );
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
    final item = _bytesToImageAttachment(
      bytes,
      maxSize: _maxImageSizeSingle,
      quality: _jpegQualitySingle,
      maxBytes: _maxJpegBytesSingle,
    );
    return item == null ? const [] : [item];
  }

  Future<List<AttachmentItem>> _pickFromPhotos() async {
    final picker = ImagePicker();
    try {
      final images = await picker.pickMultiImage();
      if (images.isEmpty) return const [];

      final isMulti = images.length > 1;
      final out = <AttachmentItem>[];
      for (final image in images) {
        final bytes = await image.readAsBytes();
        final item = _bytesToImageAttachment(
          bytes,
          maxSize: isMulti ? _maxImageSizeMulti : _maxImageSizeSingle,
          quality: isMulti ? _jpegQualityMulti : _jpegQualitySingle,
          maxBytes: isMulti ? _maxJpegBytesMulti : _maxJpegBytesSingle,
        );
        if (item != null) out.add(item);
      }
      return out;
    } catch (_) {
      // Fallback for platforms that don't support pickMultiImage.
      final image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return const [];
      final bytes = await image.readAsBytes();
      final item = _bytesToImageAttachment(
        bytes,
        maxSize: _maxImageSizeSingle,
        quality: _jpegQualitySingle,
        maxBytes: _maxJpegBytesSingle,
      );
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

    final isMulti = result.files.length > 1;

    final out = <AttachmentItem>[];
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) continue;
      final item = _bytesToImageAttachment(
        bytes,
        maxSize: isMulti ? _maxImageSizeMulti : _maxImageSizeSingle,
        quality: isMulti ? _jpegQualityMulti : _jpegQualitySingle,
        maxBytes: isMulti ? _maxJpegBytesMulti : _maxJpegBytesSingle,
      );
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
