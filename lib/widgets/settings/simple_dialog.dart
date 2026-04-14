import 'package:flutter/material.dart';
import 'package:papertok_reader/main.dart';
import 'package:papertok_reader/theme/morandi_palette.dart';
import 'package:papertok_reader/theme/app_spacing.dart';
import 'package:papertok_reader/widgets/common/pt_dialog.dart';

/// Generic picker dialog wrapper — rewritten on top of [PTDialog] so every
/// caller automatically gets the Morandi look. The [saveToPrefs] parameter
/// is retained for API compatibility with existing call sites.
Future<dynamic> showSimpleDialog(
    String title, Function saveToPrefs, List<Widget> children) {
  final context = navigatorKey.currentContext!;
  return PTDialog.show(
    context,
    title: title,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
    actions: [
      PTDialogAction(
        label: MaterialLocalizations.of(context).cancelButtonLabel,
        onPressed: () => Navigator.of(context).pop(),
      ),
    ],
  );
}

Widget dialogOption(String name, String value, Function saveToPrefs) {
  return Builder(builder: (context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadius),
        onTap: () {
          saveToPrefs(value);
          Navigator.pop(context);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
              vertical: 12, horizontal: AppSpacing.md),
          child: Text(
            name,
            style: TextStyle(
              fontSize: 15,
              color: MorandiPalette.primaryText(context),
            ),
          ),
        ),
      ),
    );
  });
}
