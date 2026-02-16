import 'package:anx_reader/service/papertok/papertok_api.dart';
import 'package:anx_reader/service/papertok/models.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PaperDetailPage extends StatefulWidget {
  const PaperDetailPage({super.key, required this.paperId});

  final int paperId;

  @override
  State<PaperDetailPage> createState() => _PaperDetailPageState();
}

class _PaperDetailPageState extends State<PaperDetailPage> {
  late Future<PaperTokDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = PaperTokApi.instance.fetchPaperDetail(widget.paperId, lang: 'zh');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(''),
      ),
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
                  const Text('Load failed'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _future = PaperTokApi.instance
                            .fetchPaperDetail(widget.paperId, lang: 'zh');
                      });
                    },
                    child: const Text('Retry'),
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
                Text(
                  p.oneLiner!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
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
              Row(
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
                      label: const Text('Open'),
                    ),
                  const SizedBox(width: 12),
                  if (((p.pdfLocalUrl ?? '').trim().isNotEmpty) ||
                      ((p.pdfUrl ?? '').trim().isNotEmpty))
                    FilledButton.icon(
                      onPressed: () {
                        // TODO: Milestone 3 - download + import book (PDF)
                        // Leave placeholder for now.
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('PDF import: TODO')),
                        );
                      },
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Import PDF'),
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
