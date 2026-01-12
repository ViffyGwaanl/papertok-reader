import 'dart:io';
import 'package:anx_reader/utils/platform_utils.dart';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

String documentPath = '';

Future<String> getAnxDocumentsPath() async {
  final directory = await getApplicationDocumentsDirectory();
  switch (AnxPlatform.type) {
    case AnxPlatformEnum.android:
      return directory.path;
    case AnxPlatformEnum.windows:
      // return '${directory.path}\\AnxReader';
      return (await getApplicationSupportDirectory()).path;
    // case TargetPlatform.linux:
    //   final path = '${directory.path}/AnxReader';
    //   return path;
    case AnxPlatformEnum.macos:
      return directory.path;
    case AnxPlatformEnum.ios:
      return (await getApplicationSupportDirectory()).path;
    }
}

Future<Directory> getAnxDocumentDir() async {
  return Directory(await getAnxDocumentsPath());
}

void initBasePath() async {
  Directory appDocDir = await getAnxDocumentDir();
  documentPath = appDocDir.path;
  debugPrint('documentPath: $documentPath');
  final fileDir = getFileDir();
  final coverDir = getCoverDir();
  final fontDir = getFontDir();
  final bgimgDir = getBgimgDir();
  if (!fileDir.existsSync()) {
    fileDir.createSync(recursive: true);
  }
  if (!coverDir.existsSync()) {
    coverDir.createSync(recursive: true);
  }
  if (!fontDir.existsSync()) {
    fontDir.createSync(recursive: true);
  }
  if (!bgimgDir.existsSync()) {
    bgimgDir.createSync(recursive: true);
  }
}

String getBasePath(String path) {
  // the path that in database using "/"
  path.replaceAll("/", Platform.pathSeparator);
  return '$documentPath${Platform.pathSeparator}$path';
}

Directory getFontDir({String? path}) {
  path ??= documentPath;
  return Directory('$path${Platform.pathSeparator}font');
}

Directory getCoverDir({String? path}) {
  path ??= documentPath;
  return Directory('$path${Platform.pathSeparator}cover');
}

Directory getFileDir({String? path}) {
  path ??= documentPath;
  return Directory('$path${Platform.pathSeparator}file');
}

Directory getBgimgDir({String? path}) {
  path ??= documentPath;
  return Directory('$path${Platform.pathSeparator}bgimg');
}
