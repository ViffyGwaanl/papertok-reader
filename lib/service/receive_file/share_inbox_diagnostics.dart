import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';

class ShareInboundEvent {
  ShareInboundEvent({
    required this.id,
    required this.atMs,
    required this.source,
    required this.sourceType,
    required this.mode,
    required this.destination,
    required this.textLen,
    required this.images,
    required this.files,
    required this.textFiles,
    required this.docxFiles,
    required this.bookshelfFiles,
    required this.otherFiles,
    required this.urlCount,
    required this.urlHosts,
    required this.titlePresent,
    required this.providerTypes,
    required this.eventIds,
    required this.receiveStatus,
    required this.routingStatus,
    required this.handoffStatus,
    required this.cleanupStatus,
    required this.failureReason,
  });

  final String id;
  final int atMs;
  final String source;
  final String sourceType;
  final String mode;
  final String destination;

  final int textLen;
  final int images;
  final int files;
  final int textFiles;
  final int docxFiles;
  final int bookshelfFiles;
  final int otherFiles;
  final int urlCount;
  final List<String> urlHosts;
  final bool titlePresent;
  final List<String> providerTypes;

  final List<String> eventIds;

  /// received|ignored_empty|error
  final String receiveStatus;

  /// pending|ai_chat|bookshelf|ask|cancelled|error|skipped
  final String routingStatus;

  /// pending|success|cards_only|skipped|cancelled|error
  final String handoffStatus;

  /// pending|skipped|success|partial|error
  final String cleanupStatus;

  final String failureReason;

  ShareInboundEvent copyWith({
    String? id,
    int? atMs,
    String? source,
    String? sourceType,
    String? mode,
    String? destination,
    int? textLen,
    int? images,
    int? files,
    int? textFiles,
    int? docxFiles,
    int? bookshelfFiles,
    int? otherFiles,
    int? urlCount,
    List<String>? urlHosts,
    bool? titlePresent,
    List<String>? providerTypes,
    List<String>? eventIds,
    String? receiveStatus,
    String? routingStatus,
    String? handoffStatus,
    String? cleanupStatus,
    String? failureReason,
  }) {
    return ShareInboundEvent(
      id: id ?? this.id,
      atMs: atMs ?? this.atMs,
      source: source ?? this.source,
      sourceType: sourceType ?? this.sourceType,
      mode: mode ?? this.mode,
      destination: destination ?? this.destination,
      textLen: textLen ?? this.textLen,
      images: images ?? this.images,
      files: files ?? this.files,
      textFiles: textFiles ?? this.textFiles,
      docxFiles: docxFiles ?? this.docxFiles,
      bookshelfFiles: bookshelfFiles ?? this.bookshelfFiles,
      otherFiles: otherFiles ?? this.otherFiles,
      urlCount: urlCount ?? this.urlCount,
      urlHosts: urlHosts ?? this.urlHosts,
      titlePresent: titlePresent ?? this.titlePresent,
      providerTypes: providerTypes ?? this.providerTypes,
      eventIds: eventIds ?? this.eventIds,
      receiveStatus: receiveStatus ?? this.receiveStatus,
      routingStatus: routingStatus ?? this.routingStatus,
      handoffStatus: handoffStatus ?? this.handoffStatus,
      cleanupStatus: cleanupStatus ?? this.cleanupStatus,
      failureReason: failureReason ?? this.failureReason,
    );
  }

  String get overallStatus {
    final values = <String>[
      receiveStatus,
      routingStatus,
      handoffStatus,
      cleanupStatus,
    ];
    if (failureReason.trim().isNotEmpty || values.contains('error')) {
      return 'error';
    }
    if (values.contains('cancelled')) {
      return 'cancelled';
    }
    if (values.contains('pending')) {
      return 'pending';
    }
    if (values.contains('success') || values.contains('cards_only')) {
      return 'success';
    }
    return 'skipped';
  }

  Set<String> get kindTags {
    final tags = <String>{};
    if (urlCount > 0) tags.add('web');
    if (images > 0) tags.add('image');
    if (textFiles > 0) tags.add('text');
    if (docxFiles > 0) tags.add('docx');
    if (bookshelfFiles > 0) tags.add('book');
    if (otherFiles > 0) tags.add('other');
    return tags;
  }

  String get searchText {
    return [
      id,
      source,
      sourceType,
      mode,
      destination,
      overallStatus,
      receiveStatus,
      routingStatus,
      handoffStatus,
      cleanupStatus,
      failureReason,
      ...eventIds,
      ...providerTypes,
      ...urlHosts,
      ...kindTags,
      titlePresent ? 'title' : '',
      if (urlCount > 0) 'url',
    ].join(' ').toLowerCase();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'atMs': atMs,
      'source': source,
      'sourceType': sourceType,
      'mode': mode,
      'destination': destination,
      'textLen': textLen,
      'images': images,
      'files': files,
      'textFiles': textFiles,
      'docxFiles': docxFiles,
      'bookshelfFiles': bookshelfFiles,
      'otherFiles': otherFiles,
      'urlCount': urlCount,
      'urlHosts': urlHosts,
      'titlePresent': titlePresent,
      'providerTypes': providerTypes,
      'eventIds': eventIds,
      'receiveStatus': receiveStatus,
      'routingStatus': routingStatus,
      'handoffStatus': handoffStatus,
      'cleanupStatus': cleanupStatus,
      'failureReason': failureReason,
    };
  }

  static ShareInboundEvent? fromJson(Map<String, dynamic> obj) {
    try {
      List<String> parseList(Object? raw) {
        final out = <String>[];
        if (raw is List) {
          for (final x in raw) {
            final s = (x ?? '').toString().trim();
            if (s.isNotEmpty) out.add(s);
          }
        }
        return out;
      }

      return ShareInboundEvent(
        id: (obj['id'] ?? '').toString(),
        atMs: (obj['atMs'] as num?)?.toInt() ?? 0,
        source: (obj['source'] ?? '').toString(),
        sourceType: (obj['sourceType'] ?? '').toString(),
        mode: (obj['mode'] ?? '').toString(),
        destination: (obj['destination'] ?? '').toString(),
        textLen: (obj['textLen'] as num?)?.toInt() ?? 0,
        images: (obj['images'] as num?)?.toInt() ?? 0,
        files: (obj['files'] as num?)?.toInt() ?? 0,
        textFiles: (obj['textFiles'] as num?)?.toInt() ?? 0,
        docxFiles: (obj['docxFiles'] as num?)?.toInt() ?? 0,
        bookshelfFiles: (obj['bookshelfFiles'] as num?)?.toInt() ?? 0,
        otherFiles: (obj['otherFiles'] as num?)?.toInt() ?? 0,
        urlCount: (obj['urlCount'] as num?)?.toInt() ?? 0,
        urlHosts: parseList(obj['urlHosts']),
        titlePresent: obj['titlePresent'] == true,
        providerTypes: parseList(obj['providerTypes']),
        eventIds: parseList(obj['eventIds']),
        receiveStatus: (obj['receiveStatus'] ?? 'pending').toString(),
        routingStatus: (obj['routingStatus'] ?? 'pending').toString(),
        handoffStatus: (obj['handoffStatus'] ?? 'pending').toString(),
        cleanupStatus: (obj['cleanupStatus'] ?? 'pending').toString(),
        failureReason: (obj['failureReason'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    }
  }
}

class ShareInboxDiagnosticsFilter {
  const ShareInboxDiagnosticsFilter({
    this.query = '',
    this.destination = 'all',
    this.status = 'all',
    this.kind = 'all',
    this.onlyErrors = false,
  });

  final String query;
  final String destination;
  final String status;
  final String kind;
  final bool onlyErrors;

  bool matches(ShareInboundEvent event) {
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty && !event.searchText.contains(q)) {
      return false;
    }

    if (destination != 'all' && event.destination != destination) {
      return false;
    }

    if (onlyErrors && event.overallStatus != 'error') {
      return false;
    }

    if (status != 'all' && event.overallStatus != status) {
      return false;
    }

    if (kind != 'all' && !event.kindTags.contains(kind)) {
      return false;
    }

    return true;
  }
}

class ShareInboxDiagnosticsStore {
  ShareInboxDiagnosticsStore._();

  static const String _key = 'shareInboxInboundEventsV1';
  static const int _max = 50;

  static String newId() => DateTime.now().microsecondsSinceEpoch.toString();

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

  static List<ShareInboundEvent> filter(
    List<ShareInboundEvent> events,
    ShareInboxDiagnosticsFilter filter,
  ) {
    return events.where(filter.matches).toList(growable: false);
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

  static void updateById(
    String id,
    ShareInboundEvent Function(ShareInboundEvent current) updater,
  ) {
    try {
      final items = read();
      if (items.isEmpty) return;
      final next = <ShareInboundEvent>[];
      for (final e in items) {
        if (e.id == id) {
          next.add(updater(e));
        } else {
          next.add(e);
        }
      }
      Prefs().prefs.setString(
            _key,
            jsonEncode(next.map((e) => e.toJson()).toList()),
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
        next.add(e.copyWith(cleanupStatus: status));
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
