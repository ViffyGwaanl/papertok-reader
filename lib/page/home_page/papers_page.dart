import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/papers/paper_detail_page.dart';
import 'package:anx_reader/service/papertok/models.dart';
import 'package:anx_reader/service/papertok/papertok_api.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class PapersPage extends StatefulWidget {
  const PapersPage({super.key, this.controller});

  final ScrollController? controller;

  @override
  State<PapersPage> createState() => _PapersPageState();
}

class _PapersPageState extends State<PapersPage> {
  final _cards = <PaperTokCard>[];
  final _imageIndexes = <int, int>{};
  bool _loading = false;
  String? _error;
  String _dayFilter = 'latest';
  String _searchQuery = '';
  Set<int> _likedIds = <int>{};

  @override
  void initState() {
    super.initState();
    _likedIds = Prefs().paperTokLikedPaperIds.toSet();
    _loadMore(reset: true);
  }

  String get _lang {
    final locale =
        Prefs().locale ?? WidgetsBinding.instance.platformDispatcher.locale;
    final code = locale.languageCode.toLowerCase();
    return code.startsWith('en') ? 'en' : 'zh';
  }

  List<PaperTokCard> get _visibleCards {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return _cards;
    }

    return _cards.where((card) {
      final haystack = [
        card.bestTitle,
        card.extract,
        card.day ?? '',
      ].join('\n').toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);
  }

  Future<void> _loadMore({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _cards.clear();
        _imageIndexes.clear();
      }
    });

    try {
      final next = await PaperTokApi.instance.fetchRandomPapers(
        limit: 20,
        lang: _lang,
        day: _dayFilter,
      );
      final existing = _cards.map((e) => e.id).toSet();
      for (final c in next) {
        if (!existing.contains(c.id)) {
          _cards.add(c);
          existing.add(c.id);
        }
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  List<String> _imagesForCard(PaperTokCard card) {
    final out = <String>[];
    for (final item in card.thumbnails) {
      final normalized = PaperTokApi.instance.resolveUrl(item);
      if (normalized.trim().isNotEmpty) {
        out.add(normalized);
      }
    }
    if (out.isNotEmpty) {
      return out;
    }
    final single = PaperTokApi.instance.resolveUrl(card.thumbnail);
    if (single.trim().isNotEmpty) {
      return [single];
    }
    return const [];
  }

  Future<void> _pickDateFilter() async {
    await showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: const Text('Latest'),
                subtitle: const Text('Use the newest available PaperTok day'),
                trailing:
                    _dayFilter == 'latest' ? const Icon(Icons.check) : null,
                onTap: () {
                  Navigator.pop(context, 'latest');
                },
              ),
              ListTile(
                title: const Text('All days'),
                subtitle: const Text('Random across the whole archive'),
                trailing: _dayFilter == 'all' ? const Icon(Icons.check) : null,
                onTap: () {
                  Navigator.pop(context, 'all');
                },
              ),
              ListTile(
                title: const Text('Pick a date'),
                subtitle: Text(_dayFilter == 'latest' || _dayFilter == 'all'
                    ? 'Choose a specific day'
                    : _dayFilter),
                onTap: () async {
                  Navigator.pop(context);
                  final now = DateTime.now();
                  final initial = _parseDay(_dayFilter) ?? now;
                  final picked = await showDatePicker(
                    context: this.context,
                    initialDate: initial,
                    firstDate: DateTime(2020, 1, 1),
                    lastDate: DateTime(now.year + 1, 12, 31),
                  );
                  if (picked == null || !mounted) return;
                  final day = _formatDay(picked);
                  if (_dayFilter == day) return;
                  setState(() {
                    _dayFilter = day;
                  });
                  await _loadMore(reset: true);
                },
              ),
            ],
          ),
        );
      },
    ).then((result) async {
      if (result is! String || !mounted) return;
      if (_dayFilter == result) return;
      setState(() {
        _dayFilter = result;
      });
      await _loadMore(reset: true);
    });
  }

  Future<void> _editSearch() async {
    final controller = TextEditingController(text: _searchQuery);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Search papers'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search title or summary',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, _searchQuery),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Clear'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );

    if (result != null && mounted) {
      setState(() {
        _searchQuery = result.trim();
      });
    }
  }

  void _toggleLike(PaperTokCard card) {
    final liked = !_likedIds.contains(card.id);
    setState(() {
      if (liked) {
        _likedIds.add(card.id);
      } else {
        _likedIds.remove(card.id);
      }
    });
    Prefs().setPaperTokLiked(card.id, liked);
  }

  DateTime? _parseDay(String value) {
    if (value == 'latest' || value == 'all') {
      return null;
    }
    final parts = value.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  String _formatDay(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  String _dayFilterLabel() {
    switch (_dayFilter) {
      case 'latest':
        return 'Latest';
      case 'all':
        return 'All';
      default:
        return _dayFilter;
    }
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(32),
          onTap: onTap,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0x44000000),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Icon(icon, color: color ?? Colors.white, size: 28),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 64,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageCarousel(PaperTokCard card) {
    final images = _imagesForCard(card);
    if (images.isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: const Icon(Icons.article_outlined, size: 60),
      );
    }

    return PageView.builder(
      itemCount: images.length,
      onPageChanged: (index) {
        setState(() {
          _imageIndexes[card.id] = index;
        });
      },
      itemBuilder: (context, index) {
        final img = images[index];
        return CachedNetworkImage(
          imageUrl: img,
          fit: BoxFit.cover,
          placeholder: (context, _) => Container(
            color: Theme.of(context).colorScheme.surfaceContainer,
          ),
          errorWidget: (context, _, __) => Container(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: const Icon(Icons.broken_image_outlined, size: 40),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleCards = _visibleCards;

    if (_cards.isEmpty && _loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_cards.isEmpty && _error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.of(context).navBarPapers)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _loadMore(reset: true),
                child: Text(L10n.of(context).commonRetry),
              ),
            ],
          ),
        ),
      );
    }

    if (visibleCards.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.search_off_outlined, size: 40),
                const SizedBox(height: 12),
                const Text('No papers match the current search'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                  child: const Text('Clear search'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: PageView.builder(
        scrollDirection: Axis.vertical,
        itemCount: visibleCards.length,
        onPageChanged: (index) {
          if (index >= visibleCards.length - 3 && _searchQuery.trim().isEmpty) {
            _loadMore();
          }
        },
        itemBuilder: (context, index) {
          final card = visibleCards[index];
          final images = _imagesForCard(card);
          final imageIndex = _imageIndexes[card.id] ?? 0;
          final liked = _likedIds.contains(card.id);

          return InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PaperDetailPage(paperId: card.id),
                ),
              );
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildImageCarousel(card),
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x66000000),
                        Color(0x00000000),
                        Color(0xAA000000),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      24 + MediaQuery.of(context).padding.bottom + 96,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    L10n.of(context).navBarPapers,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(color: Colors.white),
                                  ),
                                  const SizedBox(width: 12),
                                  if (_searchQuery.trim().isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0x55000000),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        'Search: $_searchQuery',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const Spacer(),
                              if (images.length > 1)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0x55000000),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${imageIndex + 1}/${images.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              Text(
                                card.bestTitle,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                card.extract,
                                maxLines: 5,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: Colors.white),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Day: ${card.day ?? '-'}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.white70),
                              ),
                              if (_loading && index >= visibleCards.length - 2)
                                const Padding(
                                  padding: EdgeInsets.only(top: 12),
                                  child: LinearProgressIndicator(),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _buildActionButton(
                              icon: liked
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              label: liked ? 'Liked' : 'Like',
                              color: liked ? Colors.redAccent : Colors.white,
                              onTap: () => _toggleLike(card),
                            ),
                            const SizedBox(height: 20),
                            _buildActionButton(
                              icon: Icons.event_outlined,
                              label: _dayFilterLabel(),
                              onTap: _pickDateFilter,
                            ),
                            const SizedBox(height: 20),
                            _buildActionButton(
                              icon: Icons.search,
                              label: _searchQuery.trim().isEmpty
                                  ? 'Search'
                                  : 'Searching',
                              onTap: _editSearch,
                            ),
                            const SizedBox(height: 20),
                            _buildActionButton(
                              icon: Icons.shuffle,
                              label: 'Refresh',
                              onTap: () => _loadMore(reset: true),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
