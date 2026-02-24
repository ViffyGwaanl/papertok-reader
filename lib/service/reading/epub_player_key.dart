import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:flutter/widgets.dart';

/// Global key for the active [EpubPlayer] instance.
///
/// Kept in a standalone file to avoid import cycles (e.g. markdown widgets
/// needing to trigger in-reader navigation).
final GlobalKey<EpubPlayerState> epubPlayerKey =
    GlobalKey<EpubPlayerState>(debugLabel: 'epubPlayerKey');
