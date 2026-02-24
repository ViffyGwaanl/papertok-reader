import 'dart:io';

import 'package:path/path.dart' as p;

/// Optional backup components.
///
/// - [includeAiIndexDb]: whether to include `databases/ai_index.db` (and its WAL/SHM).
/// - [includeMemory]: whether to include `memory/` directory.
class BackupZipOptions {
  final bool includeAiIndexDb;
  final bool includeMemory;

  const BackupZipOptions({
    this.includeAiIndexDb = false,
    this.includeMemory = true,
  });
}

typedef BackupZipFileEntry = ({File file, String archivePath});

const String kAiIndexDbFileName = 'ai_index.db';

/// sqlite may create these alongside the main db file.
const List<String> kAiIndexDbRelatedFileNames = <String>[
  kAiIndexDbFileName,
  '$kAiIndexDbFileName-wal',
  '$kAiIndexDbFileName-shm',
];

/// Build a deterministic list of zip file entries for backups.
///
/// The returned entries use POSIX paths (`/`) regardless of platform.
List<BackupZipFileEntry> collectBackupZipEntries({
  required Directory fileDir,
  required Directory coverDir,
  required Directory fontDir,
  required Directory bgimgDir,
  required Directory databasesDir,
  required File prefsBackupFile,
  File? manifestFile,
  Directory? memoryDir,
  BackupZipOptions options = const BackupZipOptions(),
}) {
  final entries = <BackupZipFileEntry>[];

  entries.addAll(_collectDirectoryEntries(fileDir));
  entries.addAll(_collectDirectoryEntries(coverDir));
  entries.addAll(_collectDirectoryEntries(fontDir));
  entries.addAll(_collectDirectoryEntries(bgimgDir));

  if (options.includeMemory && memoryDir != null) {
    entries.addAll(_collectDirectoryEntries(memoryDir));
  }

  final dbExcludes = options.includeAiIndexDb
      ? const <String>{}
      : kAiIndexDbRelatedFileNames.toSet();
  entries.addAll(
    _collectDirectoryEntries(databasesDir, excludeBaseNames: dbExcludes),
  );

  // Root-level files.
  if (prefsBackupFile.existsSync()) {
    entries.add((
      file: prefsBackupFile,
      archivePath: p.posix.basename(prefsBackupFile.path),
    ));
  }
  if (manifestFile != null && manifestFile.existsSync()) {
    entries.add((
      file: manifestFile,
      archivePath: p.posix.basename(manifestFile.path),
    ));
  }

  // Make output stable across platforms/filesystems.
  entries.sort((a, b) => a.archivePath.compareTo(b.archivePath));
  return entries;
}

List<BackupZipFileEntry> _collectDirectoryEntries(
  Directory dir, {
  Set<String> excludeBaseNames = const <String>{},
}) {
  if (!dir.existsSync()) return const <BackupZipFileEntry>[];

  final rootName = p.posix.basename(dir.path);
  final out = <BackupZipFileEntry>[];

  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final base = p.basename(entity.path);
    if (excludeBaseNames.contains(base)) continue;

    final rel = p.relative(entity.path, from: dir.path);
    final parts = p.split(rel);

    // Always use POSIX separators inside zip.
    final archivePath = p.posix.joinAll(<String>[rootName, ...parts]);
    out.add((file: entity, archivePath: archivePath));
  }

  out.sort((a, b) => a.archivePath.compareTo(b.archivePath));
  return out;
}
