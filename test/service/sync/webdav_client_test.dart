import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/service/sync/sync_client_base.dart';
import 'package:papertok_reader/service/sync/webdav_client.dart';

void main() {
  test('conditional upload sends If-Match for existing remote writes',
      () async {
    final server = _FakeWebdavServer();
    await server.start();
    addTearDown(server.stop);
    final localFile = await _writeTempFile('if-match');

    final client = WebdavClient(
      url: server.baseUrl,
      username: 'user',
      password: 'pass',
    );

    await client.uploadFileConditionally(
      localFile.path,
      'paper_reader/.knowledge/sync bundle.json',
      precondition: const SyncRemoteWritePrecondition.ifMatch('"etag-1"'),
    );

    expect(server.putRequests, hasLength(1));
    final request = server.putRequests.single;
    expect(request.path, '/paper_reader/.knowledge/sync%20bundle.json');
    expect(request.ifMatch, '"etag-1"');
    expect(request.ifNoneMatch, isNull);
    expect(request.body, 'if-match');
  });

  test('conditional upload sends If-None-Match for new remote writes',
      () async {
    final server = _FakeWebdavServer();
    await server.start();
    addTearDown(server.stop);
    final localFile = await _writeTempFile('if-none-match');

    final client = WebdavClient(
      url: server.baseUrl,
      username: 'user',
      password: 'pass',
    );

    await client.uploadFileConditionally(
      localFile.path,
      'paper_reader/.knowledge/knowledge_sync_bundle_v1.json',
      precondition: const SyncRemoteWritePrecondition.ifNoneMatch(),
    );

    expect(server.putRequests, hasLength(1));
    final request = server.putRequests.single;
    expect(request.ifMatch, isNull);
    expect(request.ifNoneMatch, '*');
    expect(request.body, 'if-none-match');
  });

  test('conditional upload maps HTTP 412 to precondition failure', () async {
    final server = _FakeWebdavServer(putStatusCode: 412);
    await server.start();
    addTearDown(server.stop);
    final localFile = await _writeTempFile('stale');

    final client = WebdavClient(
      url: server.baseUrl,
      username: 'user',
      password: 'pass',
    );

    await expectLater(
      client.uploadFileConditionally(
        localFile.path,
        'paper_reader/.knowledge/knowledge_sync_bundle_v1.json',
        precondition: const SyncRemoteWritePrecondition.ifMatch('"stale"'),
      ),
      throwsA(isA<SyncPreconditionFailedException>()),
    );

    expect(server.putRequests, hasLength(1));
    expect(server.putRequests.single.ifMatch, '"stale"');
  });
}

Future<File> _writeTempFile(String content) async {
  final dir = await Directory.systemTemp.createTemp('papertok_webdav_test_');
  final file = File('${dir.path}/bundle.json');
  await file.writeAsString(content);
  return file;
}

class _FakeWebdavServer {
  _FakeWebdavServer({this.putStatusCode = 201});

  final int putStatusCode;
  final putRequests = <_CapturedPutRequest>[];
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;

  String get baseUrl {
    final server = _server;
    if (server == null) {
      throw StateError('Server not started');
    }
    return 'http://${server.address.host}:${server.port}/';
  }

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _subscription = _server!.listen((request) async {
      if (request.method == 'OPTIONS') {
        request.response.statusCode = 200;
        await request.response.close();
        return;
      }
      if (request.method == 'PUT') {
        final body = await utf8.decodeStream(request);
        putRequests.add(
          _CapturedPutRequest(
            path: request.uri.path,
            ifMatch: request.headers.value('if-match'),
            ifNoneMatch: request.headers.value('if-none-match'),
            body: body,
          ),
        );
        request.response.statusCode = putStatusCode;
        await request.response.close();
        return;
      }
      request.response.statusCode = 405;
      await request.response.close();
    });
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    await _server?.close(force: true);
  }
}

class _CapturedPutRequest {
  const _CapturedPutRequest({
    required this.path,
    required this.ifMatch,
    required this.ifNoneMatch,
    required this.body,
  });

  final String path;
  final String? ifMatch;
  final String? ifNoneMatch;
  final String body;
}
