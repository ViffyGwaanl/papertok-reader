import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/backup/backup_zip_entries.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('backup zip entries', () {
    test(
      'excludes ai_index.db by default; memory included when enabled',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'backup_zip_entries_',
        );
        addTearDown(() async {
          if (await root.exists()) {
            await root.delete(recursive: true);
          }
        });

        final fileDir = Directory(p.join(root.path, 'file'))..createSync();
        final coverDir = Directory(p.join(root.path, 'cover'))..createSync();
        final fontDir = Directory(p.join(root.path, 'font'))..createSync();
        final bgimgDir = Directory(p.join(root.path, 'bgimg'))..createSync();
        final memDir = Directory(p.join(root.path, 'memory'))..createSync();
        final dbDir = Directory(p.join(root.path, 'databases'))..createSync();

        File(p.join(fileDir.path, 'a.txt')).writeAsStringSync('a');
        File(p.join(memDir.path, 'm.txt')).writeAsStringSync('m');
        File(p.join(dbDir.path, 'app_database.db')).writeAsStringSync('db');
        File(p.join(dbDir.path, 'ai_index.db')).writeAsStringSync('idx');
        File(p.join(dbDir.path, 'ai_index.db-wal')).writeAsStringSync('wal');
        File(p.join(dbDir.path, 'ai_index.db-shm')).writeAsStringSync('shm');

        final prefsFile = File(
          p.join(root.path, 'paper_reader_shared_prefs.json'),
        )..writeAsStringSync('{}');
        final manifestFile = File(p.join(root.path, 'manifest.json'))
          ..writeAsStringSync('{"schemaVersion":5}');

        final entries = collectBackupZipEntries(
          fileDir: fileDir,
          coverDir: coverDir,
          fontDir: fontDir,
          bgimgDir: bgimgDir,
          memoryDir: memDir,
          databasesDir: dbDir,
          prefsBackupFile: prefsFile,
          manifestFile: manifestFile,
          options: const BackupZipOptions(
            includeAiIndexDb: false,
            includeMemory: true,
          ),
        );

        final paths = entries.map((e) => e.archivePath).toSet();
        expect(paths, contains('file/a.txt'));
        expect(paths, contains('memory/m.txt'));
        expect(paths, contains('databases/app_database.db'));

        expect(paths, isNot(contains('databases/ai_index.db')));
        expect(paths, isNot(contains('databases/ai_index.db-wal')));
        expect(paths, isNot(contains('databases/ai_index.db-shm')));

        expect(paths, contains('paper_reader_shared_prefs.json'));
        expect(paths, contains('manifest.json'));
      },
    );

    test(
      'includes ai_index.db when enabled; memory excluded when disabled',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'backup_zip_entries_',
        );
        addTearDown(() async {
          if (await root.exists()) {
            await root.delete(recursive: true);
          }
        });

        final fileDir = Directory(p.join(root.path, 'file'))..createSync();
        final coverDir = Directory(p.join(root.path, 'cover'))..createSync();
        final fontDir = Directory(p.join(root.path, 'font'))..createSync();
        final bgimgDir = Directory(p.join(root.path, 'bgimg'))..createSync();
        final memDir = Directory(p.join(root.path, 'memory'))..createSync();
        final dbDir = Directory(p.join(root.path, 'databases'))..createSync();

        File(p.join(memDir.path, 'm.txt')).writeAsStringSync('m');
        File(p.join(dbDir.path, 'ai_index.db')).writeAsStringSync('idx');

        final prefsFile = File(
          p.join(root.path, 'paper_reader_shared_prefs.json'),
        )..writeAsStringSync('{}');

        final entries = collectBackupZipEntries(
          fileDir: fileDir,
          coverDir: coverDir,
          fontDir: fontDir,
          bgimgDir: bgimgDir,
          memoryDir: memDir,
          databasesDir: dbDir,
          prefsBackupFile: prefsFile,
          options: const BackupZipOptions(
            includeAiIndexDb: true,
            includeMemory: false,
          ),
        );

        final paths = entries.map((e) => e.archivePath).toSet();
        expect(paths, contains('databases/ai_index.db'));
        expect(paths, isNot(contains('memory/m.txt')));
      },
    );
  });

  group('plain prefs backup', () {
    test('does not include api_key/api_keys in aiConfig_* entries', () async {
      SharedPreferences.setMockInitialValues({
        'aiConfig_openai': jsonEncode({
          'api_key': 'SECRET',
          'api_keys': '["A","B"]',
          'model': 'gpt-4o-mini',
        }),
      });

      final sp = await SharedPreferences.getInstance();
      // Ensure Prefs singleton uses the mocked store.
      Prefs().prefs = sp;

      final backup = await Prefs().buildPrefsBackupMap();
      final entry = backup['aiConfig_openai'] as Map<String, dynamic>;
      expect(entry['type'], 'string');

      final value = entry['value'] as String;
      final decoded = jsonDecode(value) as Map<String, dynamic>;

      expect(decoded.containsKey('api_key'), isFalse);
      expect(decoded.containsKey('api_keys'), isFalse);
      expect(decoded['model'], 'gpt-4o-mini');
    });
  });
}
