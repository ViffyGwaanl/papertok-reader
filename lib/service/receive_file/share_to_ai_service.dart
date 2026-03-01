import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/shortcuts/papertok_quick_ask_service.dart';
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
