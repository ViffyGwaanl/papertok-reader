import 'dart:convert';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/index.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/utils/save_img.dart';
import 'package:anx_reader/utils/get_path/get_temp_dir.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/save_image_to_path.dart';
import 'package:anx_reader/utils/share_file.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:langchain_core/chat_models.dart';
import 'package:photo_view/photo_view.dart';

class ImageViewer extends StatefulWidget {
  final String image;
  final String bookName;
  final String? contextText;
  final String? alt;
  final String? title;

  const ImageViewer({
    super.key,
    required this.image,
    required this.bookName,
    this.contextText,
    this.alt,
    this.title,
  });

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  late PhotoViewController _controller;

  static const int _maxImageSize = 1536;
  static const int _jpegQuality = 82;

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

  @override
  void initState() {
    super.initState();
    _controller = PhotoViewController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleScroll(PointerScrollEvent event) {
    final scrollDelta = event.scrollDelta.dy;
    final currentScale = _controller.scale ?? 1.0;

    // Adjust sensitivity: negative delta = zoom in, positive = zoom out
    final scaleFactor = scrollDelta > 0 ? 0.95 : 1.05;
    final newScale = currentScale * scaleFactor;

    _controller.scale = newScale;
  }

  Future<void> _showAnalyzeSheet({
    required String base64,
    required String mimeType,
  }) async {
    final providerId = Prefs().aiImageAnalysisProviderIdEffective;
    if (providerId.trim().isEmpty) {
      AnxToast.show(L10n.of(context).aiServiceNotConfigured);
      return;
    }

    final model = Prefs().aiImageAnalysisModel.trim();

    final alt = (widget.alt ?? '').trim();
    final title = (widget.title ?? '').trim();
    final contextText = (widget.contextText ?? '').trim();

    String applyTemplate(String template) {
      return template
          .replaceAll('{{alt}}', alt.isEmpty ? '(empty)' : alt)
          .replaceAll('{{title}}', title.isEmpty ? '(empty)' : title)
          .replaceAll(
              '{{contextText}}', contextText.isEmpty ? '(empty)' : contextText);
    }

    final prompt = applyTemplate(Prefs().aiImageAnalysisPromptEffective);

    final messages = <ChatMessage>[
      ChatMessage.human(
        ChatMessageContent.multiModal([
          ChatMessageContent.text(prompt),
          ChatMessageContent.image(
            data: base64,
            mimeType: mimeType,
          ),
        ]),
      ),
    ];

    final stream = aiGenerateStream(
      messages,
      scope: AiRequestScope.imageAnalysis,
      identifier: providerId,
      config: model.isEmpty ? null : {'model': model},
      regenerate: false,
      useAgent: false,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: _AiImageAnalysisSheet(stream: stream),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Uint8List? imageBytes;
    String? mimeType;
    String? base64;

    try {
      final parts = widget.image.split(',');
      base64 = parts.length > 1 ? parts[1] : '';
      imageBytes = base64Decode(base64);

      final header = parts.first;
      // data:image/png;base64
      final match = RegExp(r'^data:([^;]+);base64$').firstMatch(header);
      mimeType = match?.group(1);
    } catch (e) {
      AnxLog.severe('Error decoding image: $e');
      return const Center(child: Text('Error'));
    }

    if (imageBytes == null || imageBytes.isEmpty) {
      return const Center(child: Text('Error'));
    }

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          _handleScroll(event);
        }
      },
      child: Stack(
        children: [
          PhotoView(
            imageProvider: MemoryImage(imageBytes),
            controller: _controller,
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            loadingBuilder: (context, event) => const Center(
              child: CircularProgressIndicator(),
            ),
            minScale: PhotoViewComputedScale.contained * 0.8,
            maxScale: PhotoViewComputedScale.covered * 3,
          ),
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(18.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          onPressed: () {
                            // Keep filename prefix stable for product.
                            SaveImg.downloadImg(
                              imageBytes!,
                              (mimeType ?? 'image/jpeg').split('/').last,
                              'PaperReader_${widget.bookName}',
                            );
                          },
                          icon: const Icon(Icons.download, color: Colors.white),
                        ),
                        IconButton(
                          onPressed: () async {
                            final path = await saveB64ImageToPath(
                              widget.image,
                              (await getAnxTempDir()).path,
                              'PaperReader_${widget.bookName}',
                            );

                            await shareFile(filePath: path);
                          },
                          icon: const Icon(Icons.share, color: Colors.white),
                        ),
                        IconButton(
                          onPressed: () {
                            final jpegBytes = _compressToJpeg(imageBytes!);
                            if (jpegBytes == null || jpegBytes.isEmpty) {
                              // Most likely a vector image (e.g. SVG) or an
                              // unsupported bitmap format.
                              AnxToast.show(
                                '当前图片格式暂不支持解析（仅支持常见位图图片）。',
                              );
                              return;
                            }

                            final jpegB64 = base64Encode(jpegBytes);
                            if (jpegB64.isEmpty) {
                              AnxToast.show(L10n.of(context).commonFailed);
                              return;
                            }

                            _showAnalyzeSheet(
                              base64: jpegB64,
                              mimeType: 'image/jpeg',
                            );
                          },
                          tooltip: L10n.of(context).imageAnalyze,
                          icon: const Icon(
                            Icons.auto_awesome,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiImageAnalysisSheet extends StatefulWidget {
  const _AiImageAnalysisSheet({required this.stream});

  final Stream<String> stream;

  @override
  State<_AiImageAnalysisSheet> createState() => _AiImageAnalysisSheetState();
}

class _AiImageAnalysisSheetState extends State<_AiImageAnalysisSheet> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: widget.stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(snapshot.error.toString());
        }

        if (!snapshot.hasData) {
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data ?? '';
        final parsed = parseReasoningContent(data);

        final replyText = parsed.timeline
            .where((e) => e.type == ParsedReasoningEntryType.reply)
            .map((e) => e.text ?? '')
            .where((t) => t.trim().isNotEmpty)
            .join('\n\n');

        final displayText = replyText.trim().isEmpty ? data : replyText;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              L10n.of(context).imageAnalyze,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: StyledMarkdown(
                  data: displayText,
                  selectable: true,
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: displayText));
                    AnxToast.show(L10n.of(context).notesPageCopied);
                  },
                  child: Text(L10n.of(context).commonCopy),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
