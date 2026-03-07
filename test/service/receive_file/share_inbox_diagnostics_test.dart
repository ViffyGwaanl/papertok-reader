import 'package:anx_reader/service/receive_file/share_inbox_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

ShareInboundEvent _event({
  required String id,
  required String destination,
  required String handoffStatus,
  String failureReason = '',
  int urlCount = 0,
  int docxFiles = 0,
  int textFiles = 0,
  int bookshelfFiles = 0,
  int images = 0,
  String cleanupStatus = 'skipped',
}) {
  return ShareInboundEvent(
    id: id,
    atMs: 1,
    source: 'share',
    sourceType: 'files',
    mode: 'auto',
    destination: destination,
    textLen: 0,
    images: images,
    files: docxFiles + textFiles + bookshelfFiles,
    textFiles: textFiles,
    docxFiles: docxFiles,
    bookshelfFiles: bookshelfFiles,
    otherFiles: 0,
    urlCount: urlCount,
    urlHosts: urlCount > 0 ? const ['example.com'] : const [],
    titlePresent: false,
    providerTypes: const ['file'],
    eventIds: const ['evt1'],
    receiveStatus: 'received',
    routingStatus: destination,
    handoffStatus: handoffStatus,
    cleanupStatus: cleanupStatus,
    failureReason: failureReason,
  );
}

void main() {
  test('overallStatus prefers error', () {
    final e = _event(
      id: '1',
      destination: 'aiChat',
      handoffStatus: 'success',
      failureReason: 'boom',
    );

    expect(e.overallStatus, 'error');
  });

  test('filter matches query and destination and kind', () {
    final events = [
      _event(
        id: '1',
        destination: 'aiChat',
        handoffStatus: 'success',
        docxFiles: 1,
      ),
      _event(
        id: '2',
        destination: 'bookshelf',
        handoffStatus: 'success',
        bookshelfFiles: 1,
      ),
      _event(
        id: '3',
        destination: 'aiChat',
        handoffStatus: 'error',
        urlCount: 1,
        failureReason: 'navigator_context_not_ready',
      ),
    ];

    final filtered = ShareInboxDiagnosticsStore.filter(
      events,
      const ShareInboxDiagnosticsFilter(
        query: 'navigator',
        destination: 'aiChat',
        status: 'error',
        kind: 'web',
      ),
    );

    expect(filtered.map((e) => e.id).toList(), ['3']);
  });

  test('cleanup skipped lets successful handoff resolve to success', () {
    final e = _event(
      id: '1',
      destination: 'aiChat',
      handoffStatus: 'success',
      cleanupStatus: 'skipped',
    );

    expect(e.overallStatus, 'success');
  });

  test('search query matches stored url host', () {
    final filtered = ShareInboxDiagnosticsStore.filter(
      [
        _event(
          id: '1',
          destination: 'aiChat',
          handoffStatus: 'success',
          urlCount: 1,
        ),
      ],
      const ShareInboxDiagnosticsFilter(query: 'example.com'),
    );

    expect(filtered.map((e) => e.id).toList(), ['1']);
  });

  test('onlyErrors filter excludes success records', () {
    final events = [
      _event(id: '1', destination: 'aiChat', handoffStatus: 'success'),
      _event(
        id: '2',
        destination: 'aiChat',
        handoffStatus: 'error',
        failureReason: 'oops',
      ),
    ];

    final filtered = ShareInboxDiagnosticsStore.filter(
      events,
      const ShareInboxDiagnosticsFilter(onlyErrors: true),
    );

    expect(filtered.map((e) => e.id).toList(), ['2']);
  });
}
