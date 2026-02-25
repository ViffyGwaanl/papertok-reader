import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/ai/tools/repository/books_repository.dart';
import 'package:anx_reader/service/rag/library/ai_library_index_job.dart';
import 'package:anx_reader/service/rag/library/ai_library_index_queue_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _Filter {
  unindexed,
  expired,
  indexed,
}

class AiLibraryIndexPage extends ConsumerStatefulWidget {
  const AiLibraryIndexPage({super.key});

  @override
  ConsumerState<AiLibraryIndexPage> createState() => _AiLibraryIndexPageState();
}

class _AiLibraryIndexPageState extends ConsumerState<AiLibraryIndexPage> {
  _Filter _filter = _Filter.unindexed;
  bool _selecting = false;
  final Set<int> _selectedBookIds = {};

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final queue = ref.watch(aiLibraryIndexQueueProvider);
    final queueSvc = ref.read(aiLibraryIndexQueueProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsAiLibraryIndexTitle),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _selecting = !_selecting;
                if (!_selecting) _selectedBookIds.clear();
              });
            },
            child: Text(
              _selecting
                  ? l10n.aiLibraryIndexActionClearSelection
                  : l10n.aiLibraryIndexActionSelect,
            ),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                l10n.settingsAiLibraryIndexSubtitle,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            _buildFilterBar(context),
            const Divider(height: 1),
            _buildQueueSection(context, queue, queueSvc),
            const Divider(height: 1),
            _buildBooksSection(context),
          ],
        ),
      ),
      bottomNavigationBar: _selecting
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _selectedBookIds.isEmpty
                            ? null
                            : () {
                                setState(() {
                                  _selectedBookIds.clear();
                                });
                              },
                        child: Text(l10n.aiLibraryIndexActionClearSelection),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _selectedBookIds.isEmpty
                            ? null
                            : () async {
                                final ids = _selectedBookIds.toList();
                                await queueSvc.enqueueBooks(ids);
                                if (!mounted) return;
                                setState(() {
                                  _selecting = false;
                                  _selectedBookIds.clear();
                                });
                              },
                        child: Text(l10n.aiLibraryIndexActionEnqueue),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    final l10n = L10n.of(context);

    Widget chip(_Filter f, String label) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _filter == f,
          onSelected: (_) {
            setState(() {
              _filter = f;
            });
          },
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Wrap(
        children: [
          chip(_Filter.unindexed, l10n.aiLibraryIndexFilterUnindexed),
          chip(_Filter.expired, l10n.aiLibraryIndexFilterExpired),
          chip(_Filter.indexed, l10n.aiLibraryIndexFilterIndexed),
        ],
      ),
    );
  }

  Widget _buildQueueSection(
    BuildContext context,
    AiLibraryIndexQueueState queue,
    AiLibraryIndexQueueService queueSvc,
  ) {
    final l10n = L10n.of(context);

    final active = queue.activeJob;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.aiLibraryIndexQueueTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (queue.isPaused)
                Text(
                  l10n.aiLibraryIndexQueuePaused,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: Theme.of(context).colorScheme.primary),
                ),
              const SizedBox(width: 8),
              if (queue.isPaused)
                OutlinedButton(
                  onPressed: queueSvc.resume,
                  child: Text(l10n.aiLibraryIndexActionResume),
                )
              else
                OutlinedButton(
                  onPressed: queueSvc.pause,
                  child: Text(l10n.aiLibraryIndexActionPause),
                ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: queueSvc.clearFinishedJobs,
                child: Text(l10n.aiLibraryIndexActionClearFinished),
              ),
            ],
          ),
          if (active == null) ...[
            const SizedBox(height: 8),
            Text(l10n.aiLibraryIndexQueueEmpty),
          ] else ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: active.progress.clamp(0, 1)),
            const SizedBox(height: 8),
            Text(
              '${l10n.aiLibraryIndexQueueRunning}: #${active.bookId}  ${(active.currentChapterTitle ?? '').trim()}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if ((active.lastError ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                active.lastError!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton(
                  onPressed: () => queueSvc.cancelJob(active.id),
                  child: Text(l10n.aiLibraryIndexActionCancel),
                ),
              ],
            )
          ],
        ],
      ),
    );
  }

  Widget _buildBooksSection(BuildContext context) {
    // First iteration: show a small searchable list.
    // We only show the default filter text; the actual filter will be wired to
    // index status in a follow-up patch.
    final repo = const BooksRepository();

    return FutureBuilder<List<BookSearchResult>>(
      future: repo.searchBooks(limit: 50),
      builder: (context, snapshot) {
        final books = snapshot.data ?? const <BookSearchResult>[];

        return Column(
          children: [
            for (final b in books) _buildBookTile(context, b),
          ],
        );
      },
    );
  }

  Widget _buildBookTile(BuildContext context, BookSearchResult r) {
    final book = r.book;
    final selected = _selectedBookIds.contains(book.id);

    return ListTile(
      leading: _selecting
          ? Checkbox(
              value: selected,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selectedBookIds.add(book.id);
                  } else {
                    _selectedBookIds.remove(book.id);
                  }
                });
              },
            )
          : const Icon(Icons.book_outlined),
      title: Text(book.title),
      subtitle: Text(book.author),
      onTap: _selecting
          ? () {
              setState(() {
                if (selected) {
                  _selectedBookIds.remove(book.id);
                } else {
                  _selectedBookIds.add(book.id);
                }
              });
            }
          : null,
    );
  }
}
