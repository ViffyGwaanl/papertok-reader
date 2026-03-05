import 'dart:io';

import 'package:path/path.dart' as p;

class ShareInboxPathInfo {
  const ShareInboxPathInfo({
    required this.inboxRoot,
    required this.eventId,
    required this.eventDir,
  });

  /// Canonical-ish inbox root path: `.../share_handler/inbox`.
  final String inboxRoot;

  /// Folder name under inbox root.
  final String eventId;

  /// `inboxRoot/eventId`.
  final String eventDir;
}

class ShareInboxPaths {
  ShareInboxPaths._();

  static const String inboxMarker = '/share_handler/inbox/';

  static ShareInboxPathInfo? tryParse(String rawPath) {
    final path = _normalizeIncomingPath(rawPath).replaceAll('\\', '/');
    final idx = path.indexOf(inboxMarker);
    if (idx < 0) return null;

    final after = path.substring(idx + inboxMarker.length);
    final seg = after.split('/').first.trim();
    if (seg.isEmpty) return null;

    final inboxRoot = path.substring(0, idx + inboxMarker.length - 1);
    final eventDir = p.join(inboxRoot, seg);

    return ShareInboxPathInfo(
      inboxRoot: inboxRoot,
      eventId: seg,
      eventDir: eventDir,
    );
  }

  static String _normalizeIncomingPath(String raw) {
    final s = raw.trim();
    if (s.startsWith('file://')) {
      try {
        return Uri.parse(s).toFilePath();
      } catch (_) {
        return s.replaceFirst('file://', '');
      }
    }
    return s;
  }

  static Future<String> canonicalizeBestEffort(String path) async {
    try {
      return await File(path).resolveSymbolicLinks();
    } catch (_) {
      return p.normalize(path);
    }
  }

  static Future<bool> isWithinInboxRoot(String path, String inboxRoot) async {
    final canonPath = await canonicalizeBestEffort(path);
    final canonRoot = await canonicalizeBestEffort(inboxRoot);

    return p.isWithin(canonRoot, canonPath) || canonPath == canonRoot;
  }
}
