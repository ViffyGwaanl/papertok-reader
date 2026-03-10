import 'dart:ui';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/papers/paper_detail_page.dart';
import 'package:anx_reader/service/papertok/models.dart';
import 'package:anx_reader/service/papertok/papertok_api.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
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
  bool _lockVerticalPaging = false;
  String? _error;
  String _dayFilter = 'all';
  String _searchQuery = '';
  Set<int> _likedIds = <int>{};
  bool _likedOnly = false;

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

  List<PaperTokCard> get _sourceCards {
    if (_likedOnly) {
      return Prefs()
          .paperTokLikedSnapshots
          .map((item) => item.toCard())
          .toList(growable: false);
    }
    return _cards;
  }

  List<PaperTokCard> get _visibleCards {
    final sourceCards = _sourceCards;
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return sourceCards;
    }

    return sourceCards.where((card) {
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
      var effectiveDay = _dayFilter;
      var next = await PaperTokApi.instance.fetchRandomPapers(
        limit: 20,
        lang: _lang,
        day: effectiveDay,
      );

      if (reset && next.isEmpty && effectiveDay == 'latest') {
        effectiveDay = 'all';
        next = await PaperTokApi.instance.fetchRandomPapers(
          limit: 20,
          lang: _lang,
          day: effectiveDay,
        );
      }

      if (next.isNotEmpty && effectiveDay != _dayFilter) {
        _dayFilter = effectiveDay;
      }

      final existing = _cards.map((e) => e.id).toSet();
      for (final c in next) {
        if (_likedIds.contains(c.id) &&
            Prefs().getPaperTokLikedSnapshot(c.id) == null) {
          Prefs().savePaperTokLikedSnapshot(c);
        }
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
                subtitle: Text(
                  _dayFilter == 'latest' || _dayFilter == 'all'
                      ? 'Choose a specific day'
                      : _dayFilter,
                ),
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
    Prefs().setPaperTokLiked(card.id, liked, card: liked ? card : null);
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

  void _openDetail(PaperTokCard card) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaperDetailPage(paperId: card.id),
      ),
    );
  }

  Widget _buildGlassActionButton({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
    Color? activeColor,
  }) {
    final highlight = activeColor ?? const Color(0xFFFF5470);
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Material(
          color: active
              ? highlight.withValues(alpha: 0.26)
              : Colors.white.withValues(alpha: 0.13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(
              color: active
                  ? highlight.withValues(alpha: 0.56)
                  : Colors.white.withValues(alpha: 0.16),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onTap,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 14,
                    offset: Offset(0, 7),
                  ),
                ],
              ),
              child: Icon(
                icon,
                color: active ? highlight : Colors.white,
                size: 27,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageProgressBar(int total, int current) {
    if (total <= 1) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(total, (index) {
              final active = index == current;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: active ? 24 : 10,
                height: 4,
                decoration: BoxDecoration(
                  color: active
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }),
          ),
        ),
      ),
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

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis != Axis.horizontal) {
          return false;
        }
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null &&
            !_lockVerticalPaging) {
          setState(() {
            _lockVerticalPaging = true;
          });
        }
        if (notification is ScrollEndNotification && _lockVerticalPaging) {
          setState(() {
            _lockVerticalPaging = false;
          });
        }
        return false;
      },
      child: PageView.builder(
        padEnds: false,
        allowImplicitScrolling: true,
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleCards = _visibleCards;
    final hasSearchQuery = _searchQuery.trim().isNotEmpty;

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

    if (_cards.isEmpty && !_likedOnly) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome_motion_outlined, size: 40),
                  const SizedBox(height: 12),
                  const Text(
                    'No PaperTok cards available right now',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _dayFilter == 'latest'
                        ? 'Latest feed came back empty, retrying or switching to all days should recover it.'
                        : 'Try reloading the feed or switching the day filter.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _loadMore(reset: true),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reload feed'),
                      ),
                      if (_dayFilter != 'all')
                        OutlinedButton.icon(
                          onPressed: () async {
                            setState(() {
                              _dayFilter = 'all';
                            });
                            await _loadMore(reset: true);
                          },
                          icon: const Icon(Icons.calendar_view_day_outlined),
                          label: const Text('Try all days'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (visibleCards.isEmpty && _likedOnly && !hasSearchQuery) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(CupertinoIcons.heart_slash, size: 40),
                  const SizedBox(height: 12),
                  const Text(
                    'No liked papers yet',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the heart on papers you want to keep, then come back with the liked filter.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        _likedOnly = false;
                      });
                    },
                    icon: const Icon(Icons.auto_awesome_motion_outlined),
                    label: const Text('Browse all papers'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (visibleCards.isEmpty && hasSearchQuery) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.search_off_outlined, size: 40),
                const SizedBox(height: 12),
                Text(
                  _likedOnly
                      ? 'No liked papers match the current search'
                      : 'No papers match the current search',
                ),
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
        physics: _lockVerticalPaging
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        scrollDirection: Axis.vertical,
        itemCount: visibleCards.length,
        onPageChanged: (index) {
          if (!_likedOnly &&
              index >= visibleCards.length - 3 &&
              _searchQuery.trim().isEmpty) {
            _loadMore();
          }
        },
        itemBuilder: (context, index) {
          final card = visibleCards[index];
          final images = _imagesForCard(card);
          final imageIndex = _imageIndexes[card.id] ?? 0;
          final liked = _likedIds.contains(card.id);

          return Stack(
            fit: StackFit.expand,
            children: [
              _buildImageCarousel(card),
              IgnorePointer(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x66000000),
                        Color(0x00000000),
                        Color(0xCC000000),
                      ],
                    ),
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
                                if (_likedOnly) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.18),
                                      ),
                                    ),
                                    child: const Text(
                                      'Liked only',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                if (_searchQuery.trim().isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.18),
                                      ),
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
                            if (images.length > 1) ...[
                              _buildImageProgressBar(images.length, imageIndex),
                              const SizedBox(height: 14),
                            ],
                            GestureDetector(
                              onTap: () => _openDetail(card),
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 420),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
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
                                            height: 1.05,
                                          ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      card.extract,
                                      maxLines: 5,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Colors.white
                                                .withValues(alpha: 0.94),
                                            height: 1.45,
                                          ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Day: ${card.day ?? '-'}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.white70),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_loading && index >= visibleCards.length - 2)
                              const Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: LinearProgressIndicator(),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 18),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _buildGlassActionButton(
                              icon: liked
                                  ? CupertinoIcons.heart_fill
                                  : CupertinoIcons.heart,
                              active: liked,
                              activeColor: const Color(0xFFFF5978),
                              onTap: () => _toggleLike(card),
                            ),
                            const SizedBox(height: 16),
                            _buildGlassActionButton(
                              icon: _likedOnly
                                  ? CupertinoIcons.heart_circle_fill
                                  : CupertinoIcons.heart_circle,
                              active: _likedOnly,
                              activeColor: const Color(0xFFFFA347),
                              onTap: () {
                                setState(() {
                                  _likedOnly = !_likedOnly;
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                            _buildGlassActionButton(
                              icon: CupertinoIcons.calendar,
                              active: _dayFilter != 'all',
                              activeColor: const Color(0xFF7ED6FF),
                              onTap: _pickDateFilter,
                            ),
                            const SizedBox(height: 16),
                            _buildGlassActionButton(
                              icon: CupertinoIcons.search,
                              active: _searchQuery.trim().isNotEmpty,
                              activeColor: const Color(0xFFB9A7FF),
                              onTap: _editSearch,
                            ),
                            const SizedBox(height: 16),
                            _buildGlassActionButton(
                              icon: CupertinoIcons.refresh,
                              onTap: () => _loadMore(reset: true),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
