import 'dart:io';

import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/page/settings_page/storage_data_files_page.dart';
import 'package:papertok_reader/providers/storage_info.dart';

import 'package:papertok_reader/utils/get_path/get_base_path.dart';
import 'package:papertok_reader/utils/get_path/storage_migration.dart';
import 'package:papertok_reader/utils/platform_utils.dart';
import 'package:papertok_reader/utils/toast/common.dart';
import 'package:papertok_reader/widgets/common/anx_button.dart';
import 'package:papertok_reader/widgets/settings/settings_section.dart';
import 'package:papertok_reader/widgets/settings/settings_tile.dart';
import 'package:papertok_reader/widgets/settings/settings_title.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StorageSettings extends ConsumerStatefulWidget {
  const StorageSettings({super.key});

  @override
  ConsumerState<StorageSettings> createState() => _StorageSettingsState();
}

class _StorageSettingsState extends ConsumerState<StorageSettings> {
  // Custom storage location state
  String? _selectedNewPath;
  bool _isMigrating = false;
  String _migrationCurrentItem = '';
  int _migrationProgress = 0;
  int _migrationTotal = 6;
  String? _currentStoragePath;

  @override
  void initState() {
    super.initState();
    _loadCurrentPath();
  }

  Future<void> _loadCurrentPath() async {
    final path = await getAnxDocumentsPath();
    if (mounted) {
      setState(() {
        _currentStoragePath = path;
      });
    }
  }

  Future<void> _selectNewPath() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result == null) return;

    // Check if directory is empty
    final isEmpty = await isDirectoryEmpty(result);
    if (!isEmpty) {
      if (mounted) {
        AnxToast.show(L10n.of(context).storagePathNotEmpty);
      }
      return;
    }

    // Check write permission by creating a test file
    try {
      final testFile =
          File('$result${Platform.pathSeparator}.anx_permission_test');
      await testFile.writeAsString('test');
      await testFile.delete();
    } catch (e) {
      if (mounted) {
        AnxToast.show(L10n.of(context).storagePathNoPermission);
      }
      return;
    }

    setState(() {
      _selectedNewPath = result;
    });
  }

  Future<void> _startMigration() async {
    if (_selectedNewPath == null || _currentStoragePath == null) return;

    setState(() {
      _isMigrating = true;
      _migrationProgress = 0;
      _migrationCurrentItem = '';
    });

    final success = await performStorageMigration(
      sourcePath: _currentStoragePath!,
      destinationPath: _selectedNewPath!,
      onProgress: (currentItem, progress, total) {
        if (mounted) {
          setState(() {
            _migrationCurrentItem = currentItem;
            _migrationProgress = progress;
            _migrationTotal = total;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isMigrating = false;
      });

      if (success) {
        Prefs().customStoragePath = _selectedNewPath;
        setState(() {
          _currentStoragePath = _selectedNewPath;
          _selectedNewPath = null;
        });
        AnxToast.show(L10n.of(context).storageMigrationSuccess);
      } else {
        AnxToast.show(L10n.of(context).storageMigrationFailed);
      }
    }
  }

  Future<void> _resetToDefaultPath() async {
    final defaultPath = await getDefaultStoragePath();
    if (_currentStoragePath == defaultPath) return;

    setState(() {
      _selectedNewPath = defaultPath;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final storageInfoAsync = ref.watch(storageInfoProvider);

    Widget fileSizeTrailing(String? size) {
      if (size == null) {
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
        );
      }
      return Text(
        size,
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    Widget cacheSizeTrailing(String? size) {
      if (size == null) {
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
        );
      }
      return ElevatedButton(
        onPressed: () async {
          await ref.read(storageInfoProvider.notifier).clearCache();
          ref.invalidate(storageInfoProvider);
        },
        child: Text('${l10n.storageClearCache} $size'),
      );
    }

    final storageInfoTiles = <AbstractSettingsTile>[
      SettingsTile(
        title: Text(l10n.storageTotalSize),
        trailing: fileSizeTrailing(storageInfoAsync.value?.totalSizeStr),
      ),
      SettingsTile(
        title: Text(l10n.storageDatabaseFile),
        trailing: fileSizeTrailing(storageInfoAsync.value?.databaseSizeStr),
      ),
      SettingsTile(
        title: Text(l10n.storageLogFile),
        trailing: fileSizeTrailing(storageInfoAsync.value?.logSizeStr),
      ),
      SettingsTile(
        title: Text(l10n.storageCacheFile),
        trailing: cacheSizeTrailing(storageInfoAsync.value?.cacheSizeStr),
      ),
      SettingsTile(
        title: Text(l10n.storageDataFile),
        trailing: fileSizeTrailing(storageInfoAsync.value?.dataFilesSizeStr),
      ),
      SettingsTile(
        title: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Text(l10n.storageBookFile),
        ),
        trailing: fileSizeTrailing(storageInfoAsync.value?.booksSizeStr),
      ),
      SettingsTile(
        title: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Text(l10n.storageCoverFile),
        ),
        trailing: fileSizeTrailing(storageInfoAsync.value?.coverSizeStr),
      ),
      SettingsTile(
        title: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Text(l10n.storageFontFile),
        ),
        trailing: fileSizeTrailing(storageInfoAsync.value?.fontSizeStr),
      ),
    ];

    return settingsSections(sections: [
      SettingsSection(
        title: Text(l10n.storageInfo),
        tiles: storageInfoTiles,
      ),

      // Custom storage location (Windows only)
      if (AnxPlatform.isWindows)
        SettingsSection(
          title: Text(l10n.storageCustomLocation),
          tiles: [
            SettingsTile(
              title: Text(l10n.storageCurrentPath),
              description: Text(_currentStoragePath ?? '...'),
            ),
            if (_selectedNewPath != null)
              SettingsTile(
                title: Text(l10n.storageNewPath),
                description: Text(
                  _selectedNewPath!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _selectedNewPath = null;
                    });
                  },
                ),
              ),
            CustomSettingsTile(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Action buttons
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        if (_selectedNewPath == null)
                          Expanded(
                            child: AnxButton(
                              onPressed: _selectNewPath,
                              child: Text(l10n.storageSelectPath),
                            ),
                          )
                        else
                          Expanded(
                            child: AnxButton(
                              onPressed: _isMigrating ? null : _startMigration,
                              isLoading: _isMigrating,
                              child: Text(l10n.storageMigrateData),
                            ),
                          ),
                        const SizedBox(width: 8),
                        if (Prefs().customStoragePath != null &&
                            _selectedNewPath == null)
                          AnxButton.outlined(
                            onPressed:
                                _isMigrating ? null : _resetToDefaultPath,
                            child: Text(l10n.storageResetPath),
                          ),
                      ],
                    ),
                  ),
                  // Migration progress
                  if (_isMigrating) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        children: [
                          LinearProgressIndicator(
                            value: _migrationTotal > 0
                                ? _migrationProgress / _migrationTotal
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _migrationCurrentItem.isNotEmpty
                                ? '${l10n.migrationCurrentItem}: $_migrationCurrentItem'
                                : l10n.migrationPreparing,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            '$_migrationProgress / $_migrationTotal',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),

      // Data files details — extracted to its own sub-page.
      SettingsSection(
        title: Text(l10n.storageDataFileDetails),
        tiles: [
          SettingsTile.navigation(
            title: Text(l10n.storageDataFileDetails),
            leading: const Icon(Icons.folder_outlined),
            onPressed: (ctx) => Navigator.push(
              ctx,
              CupertinoPageRoute(
                builder: (_) => const StorageDataFilesPage(),
              ),
            ),
          ),
        ],
      ),
    ]);
  }
}
