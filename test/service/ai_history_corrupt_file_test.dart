import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/service/ai/ai_history.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('corrupt history file is quarantined, not deleted', () async {
    final dir = await Directory.systemTemp.createTemp('ai_history_test');
    addTearDown(() => dir.delete(recursive: true));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );

    final file = File('${dir.path}/${AiHistoryStore.historyFileName}');
    await file.writeAsString('{not valid json');

    final history = await AiHistoryStore.readHistory();
    expect(history, isEmpty);

    // The live file is moved aside, never destroyed: one .corrupt-* copy
    // with the original bytes must remain in the directory.
    expect(await file.exists(), isFalse);
    final quarantined = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('.corrupt-'))
        .toList();
    expect(quarantined, hasLength(1));
    expect(await quarantined.single.readAsString(), '{not valid json');

    // Store keeps working after quarantine.
    expect(await AiHistoryStore.readHistory(), isEmpty);
  });
}
