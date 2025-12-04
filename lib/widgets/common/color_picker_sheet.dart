import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/utils/color/rgb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

/// Reusable RGB color picker dialog.
/// Returns selected color as RGB int (0xRRGGBB), alpha is always 0xFF when displaying.
Future<int?> showRgbColorPicker({
  required BuildContext context,
  required int initialColor, // expect RGB (0xRRGGBB)
}) async {
  Color pickedColor = colorFromRgb(initialColor);

  final result = await showDialog<int>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        content: SingleChildScrollView(
          child: ColorPicker(
            hexInputBar: true,
            //
            enableAlpha: false,
            pickerColor: pickedColor,
            onColorChanged: (Color color) {
              pickedColor = color.withAlpha(0xFF);
            },
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actions: <Widget>[
          TextButton(
            child: Text(L10n.of(context).commonCancel),
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
          ),
          TextButton(
            child: Text(L10n.of(context).commonOk),
            onPressed: () {
              Navigator.of(dialogContext).pop(rgbFromColor(pickedColor));
            },
          ),
        ],
      );
    },
  );

  return result;
}
