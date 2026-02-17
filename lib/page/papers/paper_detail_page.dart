import 'dart:io';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/service/papertok/models.dart';
import 'package:anx_reader/service/papertok/papertok_api.dart';
import 'package:anx_reader/utils/get_path/get_temp_dir.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';

class _DownloadProgress {
  const _DownloadProgress(this.received, this.total);

  final int received;
  final int total;

  double? get fraction => total > 0 ? (received / total) : null;

  String formatText() {
    final rMb = received / 1024 / 1024;
    if (total <= 0) {
      return '${rMb.toStringAsFixed(1)} MB';
    }
    final tMb = total / 1024 / 1024;
    final pct = ((received / total) * 100).clamp(0, 100).toStringAsFixed(0);
    return '${rMb.toStringAsFixed(1)} / ${tMb.toStringAsFixed(1)} MB  $pct%';
  }
}

class PaperDetailPage extends ConsumerStatefulWidget {
  const PaperDetailPage({super.key, required this.paperId});

  final int paperId;

  @override
  ConsumerState<PaperDetailPage> createState() => _PaperDetailPageState();
}

class _PaperDetailPageState extends ConsumerState<PaperDetailPage> {
  late Future<PaperTokDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = PaperTokApi.instance.fetchPaperDetail(widget.paperId, lang: 'zh');
  }

  String _sanitizeFilename(String input) {
    var s = input.trim();
    s = s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) return 'paper';
    if (s.length > 80) s = s.substring(0, 80);
    return s;
  }

  Future<void> _downloadAndImportFile({
    required PaperTokDetail p,
    required String url,
    required String extension,
    required String dialogTitle,
  }) async {
    final tempDir = await getAnxTempDir();
    if (!mounted) return;

    final baseName = _sanitizeFilename('${p.title}-${p.id}');
    final savePath = path.join(tempDir.path, '$baseName.$extension');

    final cancelToken = CancelToken();
    final progressNotifier =
        ValueNotifier<_DownloadProgress>(const _DownloadProgress(0, 0));

    bool dialogClosed = false;
    BuildContext? dialogContext;

    void closeDialogIfOpen() {
      if (dialogClosed) return;
      dialogClosed = true;
      final ctx = dialogContext;
      if (ctx != null && Navigator.of(ctx).canPop()) {
        Navigator.of(ctx).pop();
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return ValueListenableBuilder<_DownloadProgress>(
          valueListenable: progressNotifier,
          builder: (context, prog, _) {
            return AlertDialog(
              title: Text(dialogTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: prog.fraction),
                  const SizedBox(height: 8),
                  Text(
                    prog.formatText(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    cancelToken.cancel('User cancelled');
                    closeDialogIfOpen();
                  },
                  child: Text(L10n.of(context).commonCancel),
                ),
              ],
            );
          },
        );
      },
    );

    try {
      await Directory(path.dirname(savePath)).create(recursive: true);

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(seconds: 30),
        ),
      );

      await dio.download(
        url,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (r, t) {
          progressNotifier.value = _DownloadProgress(r, t);
        },
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveDataWhenStatusError: true,
        ),
      );

      if (!mounted) return;
      closeDialogIfOpen();

      importBookList([File(savePath)], context, ref);
    } catch (e) {
      if (!mounted) return;
      closeDialogIfOpen();

      // Cleanup partial file on failure/cancel.
      try {
        final f = File(savePath);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}

      if (!mounted) return;
      final isCancelled = e is DioException && CancelToken.isCancel(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isCancelled
              ? L10n.of(context).papersCancelled
              : L10n.of(context).papersDownloadFailed(e.toString())),
        ),
      );
    }
  }

  Future<void> _downloadAndImportPdf(PaperTokDetail p) async {
    final api = PaperTokApi.instance;

    final raw = (p.pdfLocalUrl ?? '').trim().isNotEmpty
        ? p.pdfLocalUrl!.trim()
        : (p.pdfUrl ?? '').trim();

    if (raw.isEmpty) return;

    final url = api.resolveUrl(raw);

    await _downloadAndImportFile(
      p: p,
      url: url,
      extension: 'pdf',
      dialogTitle: L10n.of(context).papersDownloadingPdf,
    );
  }

  Future<void> _downloadAndImportEpubFromUrl(
    PaperTokDetail p,
    String raw,
  ) async {
    final api = PaperTokApi.instance;
    if (raw.trim().isEmpty) return;

    final url = api.resolveUrl(raw);

    await _downloadAndImportFile(
      p: p,
      url: url,
      extension: 'epub',
      dialogTitle: L10n.of(context).papersDownloadingEpub,
    );
  }

  Future<void> _showEpubPicker(PaperTokDetail p) async {
    final options = <({String title, String url})>[];

    void add(String title, String? url) {
      final u = (url ?? '').trim();
      if (u.isEmpty) return;
      if (options.any((e) => e.url == u)) return;
      options.add((title: title, url: u));
    }

    // Prefer showing explicit editions.
    add(L10n.of(context).papersEpubEditionEn, p.epubUrlEn);
    add(L10n.of(context).papersEpubEditionZh, p.epubUrlZh);
    add(L10n.of(context).papersEpubEditionBilingual, p.epubUrlBilingual);

    // Fallback: show the primary epub_url if it's not already included.
    add(L10n.of(context).papersEpubEditionDefault, p.epubUrl);

    if (options.isEmpty) return;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    L10n.of(context).papersChooseEpubEdition,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: options.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final o = options[index];
                    return ListTile(
                      title: Text(o.title),
                      leading: const Icon(Icons.menu_book_outlined),
                      trailing: const Icon(Icons.download_outlined),
                      onTap: () async {
                        Navigator.pop(context);
                        await _downloadAndImportEpubFromUrl(p, o.url);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('')),
      body: FutureBuilder<PaperTokDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(L10n.of(context).papersLoadFailed),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _future = PaperTokApi.instance
                            .fetchPaperDetail(widget.paperId, lang: 'zh');
                      });
                    },
                    child: Text(L10n.of(context).commonRetry),
                  ),
                ],
              ),
            );
          }

          final p = snapshot.data!;
          final api = PaperTokApi.instance;

          Widget imageCarousel() {
            final imgs = p.carouselImages;
            if (imgs.isEmpty) return const SizedBox.shrink();

            return SizedBox(
              height: 260,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: imgs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final url = api.resolveUrl(imgs[index]);
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CachedNetworkImage(
                      imageUrl: url,
                      width: 160,
                      fit: BoxFit.cover,
                      placeholder: (context, _) => Container(
                        width: 160,
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (context, _, __) => Container(
                        width: 160,
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  );
                },
              ),
            );
          }

          final hasPdf = (p.pdfLocalUrl ?? '').trim().isNotEmpty ||
              (p.pdfUrl ?? '').trim().isNotEmpty;
          final hasEpub = (p.bestEpubUrl ?? '').trim().isNotEmpty;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(
                (p.displayTitle != null && p.displayTitle!.trim().isNotEmpty)
                    ? p.displayTitle!
                    : p.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if ((p.oneLiner ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(p.oneLiner!,
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
              const SizedBox(height: 16),
              imageCarousel(),
              if ((p.contentExplain ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  p.contentExplain!,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if ((p.url ?? '').trim().isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final uri = Uri.tryParse(p.url!);
                        if (uri != null) {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        }
                      },
                      icon: const Icon(Icons.link),
                      label: Text(
                          L10n.of(context).readingPageOpenExternalLinkAction),
                    ),
                  FilledButton.icon(
                    onPressed: hasPdf ? () => _downloadAndImportPdf(p) : null,
                    icon: const Icon(Icons.download_outlined),
                    label: Text(L10n.of(context).papersImportPdf),
                  ),
                  FilledButton.icon(
                    onPressed: hasEpub ? () => _showEpubPicker(p) : null,
                    icon: const Icon(Icons.download_for_offline_outlined),
                    label: Text(L10n.of(context).papersImportEpub),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
