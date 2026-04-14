import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/widgets/common/pt_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

void showDonateDialog(BuildContext context) {
  SmartDialog.show(
    builder: (context) => PTDialog(
      title: L10n.of(context).appDonate,
      message: L10n.of(context).appDonateTips,
      actions: [
        PTDialogAction(
          label: L10n.of(context).appDonate,
          isDefault: true,
          onPressed: () {
            launchUrl(
              Uri.parse('https://anxcye.com/home/7'),
              mode: LaunchMode.externalApplication,
            );
          },
        ),
      ],
    ),
  );
}
