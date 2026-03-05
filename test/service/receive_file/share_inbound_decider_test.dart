import 'package:anx_reader/service/receive_file/share_inbound_decider.dart';
import 'package:anx_reader/service/receive_file/share_routing_models.dart';
import 'package:flutter_test/flutter_test.dart';

ShareInboundFile f(String filename) {
  return ShareInboundFile(
    path: '/tmp/$filename',
    filename: filename,
    kind: ShareInboundFile.classifyByFilename(filename),
  );
}

ShareInboundPayload payload({
  String text = '',
  List<String> files = const [],
  int images = 0,
}) {
  return ShareInboundPayload(
    sharedText: text,
    urls: const [],
    images: List.generate(images, (i) => ShareInboundImage(path: '/tmp/i$i.jpg')),
    files: files.map(f).toList(),
  );
}

void main() {
  test('auto: image -> ai chat', () {
    final d = ShareInboundDecider.decide(
      mode: SharePanelMode.auto,
      payload: payload(images: 1),
    );
    expect(d.destination, ShareDestination.aiChat);
  });

  test('auto: epub only -> bookshelf import', () {
    final d = ShareInboundDecider.decide(
      mode: SharePanelMode.auto,
      payload: payload(files: const ['a.epub']),
    );
    expect(d.destination, ShareDestination.bookshelf);
    expect(d.bookshelfImportFiles, contains('/tmp/a.epub'));
  });

  test('auto: mixed image + pdf -> ai chat, pdf is a card (policy B)', () {
    final d = ShareInboundDecider.decide(
      mode: SharePanelMode.auto,
      payload: payload(images: 1, files: const ['p.pdf']),
    );
    expect(d.destination, ShareDestination.aiChat);
    expect(d.bookshelfFileCards.map((e) => e.filename), contains('p.pdf'));
    expect(d.bookshelfImportFiles, isEmpty);
  });

  test('auto: txt defaults to ai chat (text attachment)', () {
    final d = ShareInboundDecider.decide(
      mode: SharePanelMode.auto,
      payload: payload(files: const ['note.txt']),
    );
    expect(d.destination, ShareDestination.aiChat);
  });

  test('aiChat forced: returns cards for importable bookshelf files', () {
    final d = ShareInboundDecider.decide(
      mode: SharePanelMode.aiChat,
      payload: payload(files: const ['a.epub', 'b.pdf']),
    );
    expect(d.destination, ShareDestination.aiChat);
    expect(d.bookshelfFileCards.length, 2);
  });

  test('bookshelf forced: imports only bookshelf files, ignores others', () {
    final d = ShareInboundDecider.decide(
      mode: SharePanelMode.bookshelf,
      payload: payload(files: const ['a.epub', 'note.txt']),
    );
    expect(d.destination, ShareDestination.bookshelf);
    expect(d.bookshelfImportFiles, contains('/tmp/a.epub'));
  });

  test('ask: asks user', () {
    final d = ShareInboundDecider.decide(
      mode: SharePanelMode.ask,
      payload: payload(text: 'hi'),
    );
    expect(d.destination, ShareDestination.askUser);
  });
}
