import 'dart:io';
import 'dart:math';

import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/page/settings_page/subpage/settings_subpage_scaffold.dart';
import 'package:papertok_reader/providers/storage_info.dart';
import 'package:papertok_reader/theme/claude_palette.dart';
import 'package:papertok_reader/widgets/delete_confirm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StorageDataFilesPage extends ConsumerStatefulWidget {
  const StorageDataFilesPage({super.key});

  @override
  ConsumerState<StorageDataFilesPage> createState() =>
      _StorageDataFilesPageState();
}

class _StorageDataFilesPageState extends ConsumerState<StorageDataFilesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final storageInfoAsync = ref.watch(storageInfoProvider);

    Widget tabBody({
      required String title,
      required IconData icon,
      required Future<List<File>> listFiles,
      required bool showDelete,
    }) {
      return storageInfoAsync.when(
        data: (_) => DataFilesDetailTab(
          title: title,
          icon: icon,
          listFiles: listFiles,
          showDelete: showDelete,
          ref: ref,
        ),
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (_, __) => Center(child: Text(l10n.commonError)),
      );
    }

    return SettingsSubpageScaffold(
      title: l10n.storageDataFileDetails,
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: ClaudePalette.fg(context),
            indicatorColor: ClaudePalette.accent(context),
            unselectedLabelColor: ClaudePalette.secondary(context),
            tabs: [
              Tab(text: l10n.storageBookFile, icon: const Icon(Icons.book)),
              Tab(text: l10n.storageCoverFile, icon: const Icon(Icons.image)),
              Tab(
                text: l10n.storageFontFile,
                icon: const Icon(Icons.font_download),
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                tabBody(
                  title: l10n.storageBookFile,
                  icon: Icons.book,
                  listFiles: ref
                      .read(storageInfoProvider.notifier)
                      .listBookFiles(),
                  showDelete: false,
                ),
                tabBody(
                  title: l10n.storageCoverFile,
                  icon: Icons.image,
                  listFiles: ref
                      .read(storageInfoProvider.notifier)
                      .listCoverFiles(),
                  showDelete: false,
                ),
                tabBody(
                  title: l10n.storageFontFile,
                  icon: Icons.font_download,
                  listFiles: ref
                      .read(storageInfoProvider.notifier)
                      .listFontFiles(),
                  showDelete: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Tab content for data files details
class DataFilesDetailTab extends StatelessWidget {
  final String title;
  final IconData icon;
  final Future<List<File>> listFiles;
  final bool showDelete;
  final WidgetRef ref;

  const DataFilesDetailTab({
    super.key,
    required this.title,
    required this.icon,
    required this.listFiles,
    this.showDelete = false,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    String formatSize(int bytes) {
      if (bytes <= 0) return '0 B';

      const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
      var i = (log(bytes) / log(1024)).floor();
      return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
    }

    Widget fileSizeWidget(File file) {
      return FutureBuilder<int>(
        future: file.length(),
        builder: (context, snapshot) {
          return Text(formatSize(snapshot.data ?? 0));
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: FutureBuilder<List<File>>(
            future: listFiles,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                final files = snapshot.data!;
                files.sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
                return ListView.builder(
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return ListTile(
                      title: Text(file.path.split(Platform.pathSeparator).last),
                      subtitle: showDelete ? fileSizeWidget(file) : null,
                      trailing: showDelete
                          ? file.path.endsWith('SourceHanSerifSC-Regular.otf')
                              ? null
                              : DeleteConfirm(
                                  delete: () {
                                    snapshot.data!.remove(file);
                                    ref
                                        .read(storageInfoProvider.notifier)
                                        .deleteFile(file);
                                  },
                                  deleteIcon: const Icon(Icons.delete),
                                  confirmIcon: const Icon(Icons.check),
                                )
                          : fileSizeWidget(file),
                    );
                  },
                );
              }
              return const Center(child: CircularProgressIndicator.adaptive());
            },
          ),
        ),
      ],
    );
  }
}
