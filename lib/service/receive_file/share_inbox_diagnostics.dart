import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';

class ShareInboundEvent {
  ShareInboundEvent({
    required this.atMs,
    required this.source,
    required this.mode,
    required this.destination,
    required this.textLen,
    required this.images,
    required this.files,
    required this.textFiles,
    required this.docxFiles,
    required this.bookshelfFiles,
    required this.otherFiles,
    required this.eventIds,
    required this.cleanupStatus,
  });

  final int atMs;
  final String source;
  final String mode;
  final String destination;

  final int textLen;
  final int images;
  final int files;
  final int textFiles;
  final int docxFiles;
  final int bookshelfFiles;
  final int otherFiles;

  final List<String> eventIds;

  /// pending|skipped|success|partial|error
  final String cleanupStatus;

  Map<String, dynamic> toJson() {
    return {
      'atMs': atMs,
      'source': source,
      'mode': mode,
      'destination': destination,
      'textLen': textLen,
      'images': images,
      'files': files,
      'textFiles': textFiles,
      'docxFiles': docxFiles,
      'bookshelfFiles': bookshelfFiles,
      'otherFiles': otherFiles,
      'eventIds': eventIds,
      'cleanupStatus': cleanupStatus,
    };
  }

  static ShareInboundEvent? fromJson(Map<String, dynamic> obj) {
    try {
      final eventIdsRaw = obj['eventIds'];
      final ids = <String>[];
      if (eventIdsRaw is List) {
        for (final x in eventIdsRaw) {
          final s = (x ?? '').toString().trim();
          if (s.isNotEmpty) ids.add(s);
        }
      }

      return ShareInboundEvent(
        atMs: (obj['atMs'] as num?)?.toInt() ?? 0,
        source: (obj['source'] ?? '').toString(),
        mode: (obj['mode'] ?? '').toString(),
        destination: (obj['destination'] ?? '').toString(),
        textLen: (obj['textLen'] as num?)?.toInt() ?? 0,
        images: (obj['images'] as num?)?.toInt() ?? 0,
        files: (obj['files'] as num?)?.toInt() ?? 0,
        textFiles: (obj['textFiles'] as num?)?.toInt() ?? 0,
        docxFiles: (obj['docxFiles'] as num?)?.toInt() ?? 0,
        bookshelfFiles: (obj['bookshelfFiles'] as num?)?.toInt() ?? 0,
        otherFiles: (obj['otherFiles'] as num?)?.toInt() ?? 0,
        eventIds: ids,
        cleanupStatus: (obj['cleanupStatus'] ?? 'pending').toString(),
      );
    } catch (_) {
      return null;
    }
  }
}

class ShareInboxDiagnosticsStore {
  ShareInboxDiagnosticsStore._();

  static const String _key = 'shareInboxInboundEventsV1';
  static const int _max = 50;

  static List<ShareInboundEvent> read() {
    try {
      final raw = Prefs().prefs.getString(_key);
      if (raw == null || raw.trim().isEmpty) return const [];
      final obj = jsonDecode(raw);
      if (obj is! List) return const [];

      final out = <ShareInboundEvent>[];
      for (final item in obj) {
        if (item is! Map) continue;
        final e = ShareInboundEvent.fromJson(item.cast<String, dynamic>());
        if (e != null) out.add(e);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static void append(ShareInboundEvent event) {
    try {
      final items = [...read(), event];
      final trimmed =
          items.length <= _max ? items : items.sublist(items.length - _max);
      Prefs().prefs.setString(
            _key,
            jsonEncode(trimmed.map((e) => e.toJson()).toList()),
          );
    } catch (_) {
      // ignore
    }
  }

  static void updateCleanupStatusForEventIds(
    List<String> eventIds,
    String status,
  ) {
    if (eventIds.isEmpty) return;
    try {
      final items = read();
      if (items.isEmpty) return;

      final next = <ShareInboundEvent>[];
      for (final e in items) {
        final intersects = e.eventIds.any(eventIds.contains);
        if (!intersects) {
          next.add(e);
          continue;
        }
        next.add(
          ShareInboundEvent(
            atMs: e.atMs,
            source: e.source,
            mode: e.mode,
            destination: e.destination,
            textLen: e.textLen,
            images: e.images,
            files: e.files,
            textFiles: e.textFiles,
            docxFiles: e.docxFiles,
            bookshelfFiles: e.bookshelfFiles,
            otherFiles: e.otherFiles,
            eventIds: e.eventIds,
            cleanupStatus: status,
          ),
        );
      }

      Prefs().prefs.setString(
            _key,
            jsonEncode(next.map((e) => e.toJson()).toList()),
          );
    } catch (_) {
      // ignore
    }
  }
}
