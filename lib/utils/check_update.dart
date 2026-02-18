import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/utils/app_version.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

const _githubReleasesApi =
    'https://api.github.com/repos/ViffyGwaanl/papertok-reader/releases/latest';
const _githubReleasesPage =
    'https://github.com/ViffyGwaanl/papertok-reader/releases/latest';

Future<void> checkUpdate(bool manualCheck) async {
  if (!EnvVar.enableCheckUpdate) {
    return;
  }
  // if is today
  if (!manualCheck &&
      DateTime.now().difference(Prefs().lastShowUpdate) <
          const Duration(days: 1)) {
    return;
  }
  Prefs().lastShowUpdate = DateTime.now();

  BuildContext context = navigatorKey.currentContext!;
  Response response;
  try {
    response = await Dio().get(
      _githubReleasesApi,
      options: Options(headers: {'Accept': 'application/vnd.github+json'}),
    );
  } catch (e) {
    if (manualCheck) {
      AnxToast.show(L10n.of(context).commonFailed);
    }
    AnxLog.severe('Update: Failed to check for updates $e');
    return;
  }

  // GitHub returns tag_name like "v1.2.3"
  final tagName = response.data['tag_name']?.toString() ?? '';
  final newVersion = tagName.startsWith('v') ? tagName.substring(1) : tagName;
  final releaseBody = response.data['body']?.toString() ?? '';
  String currentVersion = (await getAppVersion()).split('+').first;
  AnxLog.info('Update: new version $newVersion');

  List<String> newVersionList = newVersion.split('.');
  List<String> currentVersionList = currentVersion.split('.');
  AnxLog.info(
      'Current version: $currentVersionList, New version: $newVersionList');
  bool needUpdate = false;
  for (int i = 0;
      i < newVersionList.length && i < currentVersionList.length;
      i++) {
    final newVer = int.tryParse(newVersionList[i]) ?? 0;
    final curVer = int.tryParse(currentVersionList[i]) ?? 0;
    if (newVer > curVer) {
      needUpdate = true;
      break;
    } else if (newVer < curVer) {
      needUpdate = false;
      break;
    }
  }

  if (needUpdate) {
    if (manualCheck) {
      Navigator.of(context).pop();
    }
    SmartDialog.show(
      builder: (BuildContext context) {
        final body = releaseBody.split('\n').skip(1).join('\n');
        return AlertDialog(
          title: Text(L10n.of(context).commonNewVersion,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              )),
          content: SingleChildScrollView(
            child: StyledMarkdown(
                data: '''### ${L10n.of(context).updateNewVersion} $newVersion\n
${L10n.of(context).updateCurrentVersion} $currentVersion\n
$body'''),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                SmartDialog.dismiss();
              },
              child: Text(L10n.of(context).commonCancel),
            ),
            TextButton(
              onPressed: () {
                launchUrl(Uri.parse(_githubReleasesPage),
                    mode: LaunchMode.externalApplication);
              },
              child: Text(L10n.of(context).updateViaGithub),
            ),
          ],
        );
      },
    );
  } else {
    if (manualCheck) {
      AnxToast.show(L10n.of(context).commonNoNewVersion);
    }
  }
}
