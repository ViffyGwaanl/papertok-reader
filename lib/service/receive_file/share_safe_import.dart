import 'dart:io';

import 'package:anx_reader/service/receive_file/share_inbox_cleanup_service.dart';
import 'package:anx_reader/service/receive_file/share_inbox_paths.dart';
import 'package:anx_reader/utils/get_path/get_cache_dir.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:path/path.dart' as p;

class ShareSafeImport {
  ShareSafeImport._();

  static Future<List<File>> prepareImportFiles(List<String> paths) async {
    final out = <File>[];
    if (paths.isEmpty) return out;

    final cacheDir = await getAnxCacheDir();
    final staging = Directory(p.join(cacheDir.path, 'share_import_staging'));
    if (!await staging.exists()) {
      await staging.create(recursive: true);
    }

    final pendingEventDirs = <String>[];

    for (final raw in paths) {
      final path = raw.trim();
      if (path.isEmpty) continue;

      final info = ShareInboxPaths.tryParse(path);
      if (info != null) {
        // Managed inbox file: safe to import directly.
        out.add(File(path));
        pendingEventDirs.add(info.eventDir);
        continue;
      }

      // Unsafe: copy into our own staging, then import from the copy.
      try {
        final src = File(path);
        if (!await src.exists()) continue;

        final bn = p.basename(path);
        final ts = DateTime.now().millisecondsSinceEpoch;
        final dst = File(p.join(staging.path, '${ts}_$bn'));

        await src.copy(dst.path);
        out.add(dst);
      } catch (e, st) {
        AnxLog.warning('share: copy-to-staging failed: $e', e, st);
      }
    }

    // Make sure cleanup service knows our roots.
    ShareInboxCleanupService.recordKnownRootsFromPaths(paths);

    return out;
  }
}
