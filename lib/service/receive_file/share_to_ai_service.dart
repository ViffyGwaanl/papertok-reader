import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/attachment_item.dart';
import 'package:anx_reader/models/share_prompt_preset.dart';
import 'package:anx_reader/service/receive_file/docx_plain_text_extractor.dart';
import 'package:anx_reader/service/shortcuts/papertok_ai_chat_navigator.dart';
import 'package:anx_reader/service/shortcuts/papertok_quick_ask_service.dart';
import 'package:anx_reader/service/shortcuts/papertok_shortcuts_handoff_service.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:image/image.dart' as img;

class ShareToAiService {
  ShareToAiService._();

  static Future<void> askPapertokFromShare(
    BuildContext context, {
    required String prompt,
    required List<File> imageFiles,
  }) async {
    final l10n = L10n.of(context);

    final files = imageFiles.take(4).toList(growable: false);
    if (files.isEmpty && prompt.trim().isEmpty) return;

    SmartDialog.showLoading();

    try {
      final imagesB64 = <String>[];
      for (final f in files) {
        final b64 = await _readAndNormalizeJpegBase64(f);
        if (b64 != null && b64.trim().isNotEmpty) imagesB64.add(b64);
      }

      final reply = await PapertokQuickAskService.send(
        prompt: prompt,
        imagesBase64Jpeg: imagesB64,
      );

      SmartDialog.dismiss(status: SmartStatus.loading);

      if (Prefs().shortcutsSendMessageShowDialogDefaultV1) {
        SmartDialog.show(
          clickMaskDismiss: true,
          builder: (ctx) {
            return AlertDialog(
              title: Text('Papertok'),
              content: SingleChildScrollView(
                child: Text(reply),
              ),
              actions: [
                TextButton(
                  onPressed: () => SmartDialog.dismiss(),
                  child: Text(l10n.commonOk),
                ),
              ],
            );
          },
        );
      }
    } catch (e, st) {
      SmartDialog.dismiss(status: SmartStatus.loading);
      AnxLog.warning('share->ai failed: $e', e, st);
      SmartDialog.show(
        clickMaskDismiss: true,
        builder: (ctx) {
          return AlertDialog(
            title: Text(l10n.commonAttention),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => SmartDialog.dismiss(),
                child: Text(l10n.commonOk),
              ),
            ],
          );
        },
      );
    }
  }

  static Future<void> sendToAiChatFromShare(
    BuildContext context, {
    required String sharedText,
    required List<File> imageFiles,
    List<File> textFiles = const [],
    List<File> docxFiles = const [],
  }) async {
    final preset = await _pickPromptPresetIfNeeded(context);

    // "Preset prompt" is prepended to the Share Sheet text content.
    final prefix = (preset?.prompt ?? '').trim();
    final content = sharedText.trim();

    var mergedPrompt =
        [prefix, content].where((e) => e.trim().isNotEmpty).join('\n\n').trim();

    final files = imageFiles.take(4).toList(growable: false);

    final mayHaveTextFiles = textFiles.isNotEmpty || docxFiles.isNotEmpty;

    if (files.isEmpty && mergedPrompt.isEmpty && !mayHaveTextFiles) {
      return;
    }

    SmartDialog.showLoading();

    try {
      final textAttachments = await _buildTextFileAttachments(
        context,
        textFiles: textFiles,
        docxFiles: docxFiles,
      );

      if (files.isEmpty && mergedPrompt.isEmpty && textAttachments.isEmpty) {
        SmartDialog.dismiss(status: SmartStatus.loading);
        return;
      }

      if (mergedPrompt.isEmpty && textAttachments.isNotEmpty) {
        // Provide a reasonable default instruction when user only shares files.
        mergedPrompt = L10n.of(context).aiQuickPromptSummaryText;
      }

      final imagesB64 = <String>[];
      for (final f in files) {
        final b64 = await _readAndNormalizeJpegBase64(f);
        if (b64 != null && b64.trim().isNotEmpty) imagesB64.add(b64);
      }

      SmartDialog.dismiss(status: SmartStatus.loading);

      // Ensure the AI chat UI is visible before handoff.
      await PapertokAiChatNavigator.show();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final ok = await PapertokShortcutsHandoffService.sendToChat(
        prompt: mergedPrompt,
        imagesBase64Jpeg: imagesB64,
        textFileAttachments: textAttachments,
      );

      if (!ok) {
        AnxLog.warning('share->ai_chat handoff failed');
      }
    } catch (e, st) {
      SmartDialog.dismiss(status: SmartStatus.loading);
      AnxLog.warning('share->ai_chat failed: $e', e, st);

      final l10n = L10n.of(context);
      SmartDialog.show(
        clickMaskDismiss: true,
        builder: (ctx) {
          return AlertDialog(
            title: Text(l10n.commonAttention),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => SmartDialog.dismiss(),
                child: Text(l10n.commonOk),
              ),
            ],
          );
        },
      );
    }
  }

  static const int _maxTextChars = 200000;
  static const int _maxTextFileBytes = 900 * 1024;
  static const int _maxTextFileAttachments = 3;

  static Future<List<AttachmentItem>> _buildTextFileAttachments(
    BuildContext context, {
    required List<File> textFiles,
    required List<File> docxFiles,
  }) async {
    final out = <AttachmentItem>[];

    Future<void> addTextAttachment({
      required String filename,
      required String text,
    }) async {
      final trimmed = text.trim();
      if (trimmed.isEmpty) return;

      final limited = trimmed.length > _maxTextChars
          ? trimmed.substring(0, _maxTextChars)
          : trimmed;

      out.add(
        AttachmentItem.textFile(
          filename: filename,
          bytes: Uint8List.fromList(utf8.encode(limited)),
          text: limited,
        ),
      );
    }

    for (final f in textFiles) {
      if (out.length >= _maxTextFileAttachments) break;
      final filename = f.path.split(Platform.pathSeparator).last;

      try {
        final bytes = await _readFileHeadBytes(f, _maxTextFileBytes);
        if (bytes.isEmpty) continue;
        final decoded = utf8.decode(bytes, allowMalformed: true);
        await addTextAttachment(filename: filename, text: decoded);
      } catch (e, st) {
        AnxLog.warning('share: read text file failed: $e', e, st);
      }
    }

    for (final f in docxFiles) {
      if (out.length >= _maxTextFileAttachments) break;
      final filename = f.path.split(Platform.pathSeparator).last;

      try {
        final len = await f.length();
        if (len <= 0) continue;

        // Coarse guardrail to avoid loading huge files.
        const maxDocxBytes = 25 * 1024 * 1024;
        if (len > maxDocxBytes) {
          AnxLog.warning('share: docx too large: $len bytes');
          continue;
        }

        final bytes = Uint8List.fromList(await f.readAsBytes());

        final r = await Isolate.run(() {
          return DocxPlainTextExtractor.extract(bytes, maxChars: _maxTextChars);
        });

        await addTextAttachment(filename: filename, text: r.text);
      } catch (e, st) {
        AnxLog.warning('share: docx extract exception: $e', e, st);
      }
    }

    return out;
  }

  static Future<Uint8List> _readFileHeadBytes(File file, int maxBytes) async {
    final out = <int>[];
    try {
      await for (final chunk in file.openRead(0, maxBytes)) {
        out.addAll(chunk);
        if (out.length >= maxBytes) break;
      }
    } catch (_) {
      // Ignore.
    }
    if (out.length > maxBytes) {
      return Uint8List.fromList(out.sublist(0, maxBytes));
    }
    return Uint8List.fromList(out);
  }

  /// Pure helper used by Share Sheet routing.
  ///
  /// Returns a preset only when there is exactly 1 enabled preset.
  static SharePromptPreset? autoPickSingleEnabledPreset(
    SharePromptPresetsState state,
  ) {
    final enabled = state.enabledPresets;
    if (enabled.length == 1) return enabled.first;
    return null;
  }

  static String? initialPresetIdForDialog(SharePromptPresetsState state) {
    final enabled = state.enabledPresets;
    if (enabled.isEmpty) return null;

    final lastId = state.lastSelectedPresetId;
    if (lastId != null && enabled.any((p) => p.id == lastId)) {
      return lastId;
    }
    return enabled.first.id;
  }

  static Future<SharePromptPreset?> _pickPromptPresetIfNeeded(
    BuildContext context,
  ) async {
    final state = Prefs().sharePromptPresetsStateV2;
    final enabled = state.enabledPresets;

    if (enabled.isEmpty) return null;

    // Requirement: if exactly 1 preset enabled, do not show dialog.
    final autoPicked = autoPickSingleEnabledPreset(state);
    if (autoPicked != null) {
      _persistLastSelectedPresetId(autoPicked.id);
      return autoPicked;
    }

    final l10n = L10n.of(context);

    final initialId = initialPresetIdForDialog(state) ?? enabled.first.id;

    // Ensure the UI is painted before showing dialogs on cold-start.
    await Future<void>.delayed(const Duration(milliseconds: 16));

    final picked = await showDialog<SharePromptPreset>(
      context: context,
      builder: (ctx) {
        var group = initialId;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return SimpleDialog(
              title: Text(l10n.settingsSharePromptPresetsTitle),
              children: [
                for (final p in enabled)
                  RadioListTile<String>(
                    value: p.id,
                    groupValue: group,
                    title: Text(p.title),
                    subtitle: _buildPresetPreview(p.prompt),
                    isThreeLine: true,
                    onChanged: (val) => setLocal(() => group = val ?? group),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text(l10n.commonCancel),
                      ),
                      TextButton(
                        onPressed: () {
                          final selected = enabled.firstWhere(
                            (e) => e.id == group,
                            orElse: () => enabled.first,
                          );
                          Navigator.of(ctx).pop(selected);
                        },
                        child: Text(l10n.commonOk),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked == null) return null;

    _persistLastSelectedPresetId(picked.id);
    return picked;
  }

  static void _persistLastSelectedPresetId(String id) {
    try {
      final before = Prefs().sharePromptPresetsStateV2;
      Prefs().sharePromptPresetsStateV2 = SharePromptPresetsState(
        schemaVersion: before.schemaVersion,
        presets: before.presets,
        lastSelectedPresetId: id,
      );
    } catch (e, st) {
      AnxLog.warning('share: persist last preset failed: $e', e, st);
    }
  }

  static Widget _buildPresetPreview(String prompt) {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) return const SizedBox();

    final lines = trimmed
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final preview = lines.isEmpty ? trimmed : lines.first;

    return Text(
      preview,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  static Future<String?> _readAndNormalizeJpegBase64(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      final normalized = _downsample(decoded, maxPixel: 2048);
      final jpg = img.encodeJpg(normalized, quality: 86);
      return Uint8List.fromList(jpg).toBase64();
    } catch (_) {
      return null;
    }
  }

  static img.Image _downsample(img.Image src, {required int maxPixel}) {
    final w = src.width;
    final h = src.height;
    final maxSide = w > h ? w : h;
    if (maxSide <= maxPixel) return src;

    final scale = maxPixel / maxSide;
    final nw = (w * scale).round();
    final nh = (h * scale).round();
    return img.copyResize(src, width: nw, height: nh);
  }
}

extension on Uint8List {
  String toBase64() {
    return base64Encode(this);
  }
}
