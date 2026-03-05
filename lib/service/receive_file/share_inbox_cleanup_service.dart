import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/receive_file/share_inbox_diagnostics.dart';
import 'package:anx_reader/service/receive_file/share_inbox_paths.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:path/path.dart' as p;

class ShareInboxCleanupService {
  ShareInboxCleanupService._();

  static const String _knownRootsKey = 'shareInboxKnownRootsV1';
  static const String _lastCleanupAtKey = 'shareInboxLastCleanupAtMsV1';

  static void recordKnownRootsFromPaths(List<String> paths) {
    final roots = <String>{..._readKnownRoots()};

    for (final raw in paths) {
      final info = ShareInboxPaths.tryParse(raw);
      if (info == null) continue;
      roots.add(info.inboxRoot);
    }

    _writeKnownRoots(roots.toList(growable: false));
  }

  static Future<void> cleanupNow({bool bestEffort = true}) async {
    await _cleanupInternal(force: true, bestEffort: bestEffort);
  }

  static Future<void> maybeCleanupOnStartup() async {
    await _cleanupInternal(force: false, bestEffort: true);
  }

  static Future<void> cleanupEventDirsIfSafe({
    required List<String> eventDirs,
  }) async {
    if (eventDirs.isEmpty) return;

    final eventIds = <String>[];
    for (final d in eventDirs) {
      final info = ShareInboxPaths.tryParse(d);
      if (info != null) eventIds.add(info.eventId);
    }

    try {
      for (final raw in eventDirs) {
        final info = ShareInboxPaths.tryParse(raw);
        if (info == null) continue;

        // Only remove empty dirs (or dirs with only meta.json).
        final dir = Directory(info.eventDir);
        if (!await dir.exists()) continue;

        final entries = await dir.list(recursive: true).toList();
        final files = entries.whereType<File>().toList();

        final realFiles = files.where((f) {
          final bn = p.basename(f.path);
          return bn != 'meta.json';
        }).toList();

        if (realFiles.isNotEmpty) continue;

        final ok = await _safeDeleteDir(dir, allowRoot: info.inboxRoot);
        if (ok) {
          ShareInboxDiagnosticsStore.updateCleanupStatusForEventIds(
            [info.eventId],
            'success',
          );
        }
      }
    } catch (e, st) {
      AnxLog.warning('share: cleanupEventDirsIfSafe failed: $e', e, st);
      ShareInboxDiagnosticsStore.updateCleanupStatusForEventIds(
        eventIds,
        'error',
      );
    }
  }

  static List<String> _readKnownRoots() {
    try {
      final raw = Prefs().prefs.getString(_knownRootsKey);
      if (raw == null || raw.trim().isEmpty) return const [];
      final obj = jsonDecode(raw);
      if (obj is! List) return const [];
      return obj
          .map((e) => (e ?? '').toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static void _writeKnownRoots(List<String> roots) {
    try {
      Prefs().prefs.setString(_knownRootsKey, jsonEncode(roots));
    } catch (_) {
      // ignore
    }
  }

  static Future<void> _cleanupInternal({
    required bool force,
    required bool bestEffort,
  }) async {
    final ttlDays = Prefs().sharePanelTtlDaysV1;

    // Throttle (even when ttl=0, we still may prune empty dirs).
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = Prefs().prefs.getInt(_lastCleanupAtKey) ?? 0;
    if (!force && now - last < 6 * 60 * 60 * 1000) {
      return;
    }

    Prefs().prefs.setInt(_lastCleanupAtKey, now);

    final roots = _readKnownRoots();
    if (roots.isEmpty) return;

    final cutoffMs = ttlDays <= 0 ? null : now - ttlDays * 24 * 60 * 60 * 1000;

    for (final root in roots) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;

      try {
        await for (final ent in dir.list(followLinks: false)) {
          if (ent is! Directory) continue;

          final eventDir = ent;

          final createdAtMs = await _readCreatedAtMs(eventDir) ??
              (await eventDir.stat()).modified.millisecondsSinceEpoch;

          final shouldDeleteByTtl = cutoffMs != null && createdAtMs <= cutoffMs;

          // Always prune empty dirs even when ttl=0.
          final isEmpty = await _isEffectivelyEmpty(eventDir);

          if (shouldDeleteByTtl || isEmpty) {
            await _safeDeleteDir(eventDir, allowRoot: root);
          }
        }
      } catch (e, st) {
        if (!bestEffort) rethrow;
        AnxLog.warning('share: inbox cleanup failed: $e', e, st);
      }
    }
  }

  static Future<int?> _readCreatedAtMs(Directory eventDir) async {
    try {
      final meta = File(p.join(eventDir.path, 'meta.json'));
      if (!await meta.exists()) return null;
      final raw = await meta.readAsString();
      final obj = jsonDecode(raw);
      if (obj is! Map) return null;
      final v = obj['createdAtMs'];
      if (v is num) return v.toInt();
      return int.tryParse((v ?? '').toString());
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _isEffectivelyEmpty(Directory eventDir) async {
    try {
      final items = await eventDir.list(recursive: true).toList();
      final files = items.whereType<File>().toList();
      if (files.isEmpty) return true;

      final realFiles = files.where((f) => p.basename(f.path) != 'meta.json');
      return realFiles.isEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _safeDeleteDir(
    Directory dir, {
    required String allowRoot,
  }) async {
    try {
      final canonDir = await ShareInboxPaths.canonicalizeBestEffort(dir.path);
      final canonRoot = await ShareInboxPaths.canonicalizeBestEffort(allowRoot);

      if (!(p.isWithin(canonRoot, canonDir) || canonDir == canonRoot)) {
        AnxLog.warning('share: refuse delete dir outside root: $canonDir');
        return false;
      }

      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      return true;
    } catch (e, st) {
      AnxLog.warning('share: delete dir failed: $e', e, st);
      return false;
    }
  }
}
