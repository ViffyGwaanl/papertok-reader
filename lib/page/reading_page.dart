import 'dart:async';
import 'dart:math' as math;

import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/dao/reading_time.dart';
import 'package:papertok_reader/dao/theme.dart';
import 'package:papertok_reader/enums/ai_panel_position.dart';
import 'package:papertok_reader/enums/ai_dock_side.dart';
import 'package:papertok_reader/enums/ai_pad_panel_mode.dart';
import 'package:papertok_reader/enums/sync_direction.dart';
import 'package:papertok_reader/enums/sync_trigger.dart';
import 'package:papertok_reader/enums/translation_mode.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/main.dart';
import 'package:papertok_reader/models/ai_quick_prompt_chip.dart';
import 'package:papertok_reader/models/attachment_item.dart';
import 'package:papertok_reader/models/book.dart';
import 'package:papertok_reader/models/read_theme.dart';
import 'package:papertok_reader/models/source_ref.dart';
import 'package:papertok_reader/page/book_player/epub_player.dart';
import 'package:papertok_reader/service/reading/epub_player_key.dart';
import 'package:papertok_reader/providers/sync.dart';
import 'package:papertok_reader/service/ai/index.dart';
import 'package:papertok_reader/service/ai/kairos/kairos_service.dart';
import 'package:papertok_reader/service/ai/prompt_generate.dart';
import 'package:papertok_reader/providers/current_reading.dart';
import 'package:papertok_reader/providers/kairos_provider.dart';
import 'package:papertok_reader/service/deeplink/paperreader_current_source_opener.dart';
import 'package:papertok_reader/service/deeplink/paperreader_source_opener.dart';
import 'package:papertok_reader/utils/env_var.dart';
import 'package:papertok_reader/utils/toast/common.dart';
import 'package:papertok_reader/utils/ui/status_bar.dart';
import 'package:papertok_reader/widgets/ai/ai_multi_tab_chat.dart';
import 'package:papertok_reader/widgets/ai/ai_stream.dart';
import 'package:papertok_reader/widgets/reading_page/notes_widget.dart';
import 'package:papertok_reader/models/reading_time.dart';
import 'package:papertok_reader/widgets/reading_page/progress_widget.dart';
import 'package:papertok_reader/widgets/reading_page/tts_widget.dart';
import 'package:papertok_reader/widgets/reading_page/tts_fab.dart';
import 'package:papertok_reader/widgets/reading_page/style_widget.dart';
import 'package:papertok_reader/widgets/reading_page/toc_widget.dart';
import 'package:papertok_reader/widgets/reading_page/more_settings/more_settings.dart';
import 'package:papertok_reader/widgets/common/axis_flex.dart';
import 'package:papertok_reader/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// import 'package:flutter/foundation.dart'
// show debugPrint, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class ReadingPage extends ConsumerStatefulWidget {
  const ReadingPage({
    super.key,
    required this.book,
    this.cfi,
    this.openHref,
    required this.initialThemes,
    this.heroTag,
  });

  final Book book;
  final String? cfi;

  /// Optional href/anchor to navigate to after initial load.
  final String? openHref;

  final List<ReadTheme> initialThemes;
  final String? heroTag;

  @override
  ConsumerState<ReadingPage> createState() => ReadingPageState();
}

final GlobalKey<ReadingPageState> readingPageKey =
    GlobalKey<ReadingPageState>();

class ReadingPageState extends ConsumerState<ReadingPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  Icon _translationModeIcon(TranslationModeEnum mode) {
    // Keep icons consistent with ReadingMoreSettings segmented control.
    return switch (mode) {
      TranslationModeEnum.off => const Icon(Icons.translate_outlined),
      TranslationModeEnum.originalOnly => const Icon(Icons.translate_outlined),
      TranslationModeEnum.translationOnly => const Icon(Icons.g_translate),
      TranslationModeEnum.bilingual => const Icon(Icons.compare),
    };
  }

  static const empty = SizedBox.shrink();

  double _aiSwipeUpTotalDy = 0;
  bool _aiSwipeUpTriggered = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late Book _book;
  late Widget _currentPage = empty;
  final Stopwatch _readTimeWatch = Stopwatch();
  DateTime? _sessionStart;
  Timer? _awakeTimer;
  late final KairosService _kairos;
  bool bottomBarOffstage = true;
  Widget? _aiChat;
  final aiChatKey = GlobalKey<AiMultiTabChatState>();
  bool _aiChatVisible = false;

  /// Whether the persistent AI bottom-sheet panel has been created at least
  /// once. Once true the widget stays in the tree (via Offstage) so that
  /// ProviderScopes survive minimize/restore and streaming is never interrupted.
  bool _aiChatCreated = false;
  String? _aiInitialMessage;
  SourceRef? _aiInitialSourceRef;
  bool _aiSendImmediate = false;
  static const double _aiChatMinWidth = 240;
  double _aiChatWidth = 300;
  static const double _aiChatMinHeight = 200;
  double _aiChatHeight = 300;
  bool _isResizingAiChat = false;
  bool bookmarkExists = false;

  late final FocusNode _readerFocusNode;
  // late final VolumeKeyBoard _volumeKeyBoard;
  // bool _volumeKeyListenerAttached = false;

  @override
  void initState() {
    _readerFocusNode = FocusNode(debugLabel: 'reading_page_focus');
    if (widget.book.isDeleted) {
      Navigator.pop(context);
      AnxToast.show(L10n.of(context).bookDeleted);
      return;
    }

    // Restore AI panel persisted size.
    _aiChatWidth = Prefs().aiPanelWidth;
    _aiChatHeight = Prefs().aiPanelHeight;

    if (Prefs().hideStatusBar) {
      hideStatusBar();
    }

    WidgetsBinding.instance.addObserver(this);
    _readTimeWatch.start();
    _sessionStart = DateTime.now();
    setAwakeTimer(Prefs().awakeTime);
    _kairos = KairosService(
      onHint: (hint) {
        if (mounted) {
          ref.read(kairosHintProvider.notifier).state = hint;
        }
      },
    );
    _kairos.start();

    _book = widget.book;
    // _volumeKeyBoard = VolumeKeyBoard.instance;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _requestReaderFocus();
        // _attachVolumeKeyListener();
      }
    });
    super.initState();
  }

  @override
  void dispose() {
    Sync().syncData(SyncDirection.upload, ref, trigger: SyncTrigger.auto);
    _readTimeWatch.stop();
    _kairos.stop();
    _awakeTimer?.cancel();
    WakelockPlus.disable();
    showStatusBar();
    WidgetsBinding.instance.removeObserver(this);
    readingTimeDao.insertReadingTime(
      ReadingTime(
        bookId: _book.id,
        readingTime: _readTimeWatch.elapsed.inSeconds,
      ),
      startedAt: _sessionStart,
    );
    _sessionStart = null;
    audioHandler.stop();
    // if (_volumeKeyListenerAttached) {
    //   unawaited(_volumeKeyBoard.removeListener());
    // }
    _readerFocusNode.dispose();
    super.dispose();
  }

  void _requestReaderFocus() {
    if (bottomBarOffstage && !_readerFocusNode.hasFocus) {
      _readerFocusNode.requestFocus();
    }
  }

  void _releaseReaderFocus() {
    if (_readerFocusNode.hasFocus) {
      _readerFocusNode.unfocus();
    }
  }

  // Future<void> _attachVolumeKeyListener() async {
  //   if (defaultTargetPlatform != TargetPlatform.iOS ||
  //       _volumeKeyListenerAttached) {
  //     return;
  //   }

  //   try {
  //     await _volumeKeyBoard.addListener(_handleVolumeKeyEvent);
  //     _volumeKeyListenerAttached = true;
  //   } catch (error) {
  //     debugPrint('Failed to attach volume key listener: $error');
  //   }
  // }

  // void _handleVolumeKeyEvent(VolumeKey key) {
  //   if (!Prefs().volumeKeyTurnPage || !_readerFocusNode.hasFocus) {
  //     return;
  //   }

  //   if (key == VolumeKey.up) {
  //     epubPlayerKey.currentState?.prevPage();
  //   } else if (key == VolumeKey.down) {
  //     epubPlayerKey.currentState?.nextPage();
  //   }
  // }

  KeyEventResult _handleReaderKeyEvent(FocusNode node, KeyEvent event) {
    if (!_readerFocusNode.hasFocus) {
      return KeyEventResult.ignored;
    }

    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final logicalKey = event.logicalKey;

    if (logicalKey == LogicalKeyboardKey.arrowRight ||
        logicalKey == LogicalKeyboardKey.arrowDown ||
        logicalKey == LogicalKeyboardKey.pageDown ||
        logicalKey == LogicalKeyboardKey.space) {
      epubPlayerKey.currentState?.nextPage();
      return KeyEventResult.handled;
    }

    if (logicalKey == LogicalKeyboardKey.arrowLeft ||
        logicalKey == LogicalKeyboardKey.arrowUp ||
        logicalKey == LogicalKeyboardKey.pageUp) {
      epubPlayerKey.currentState?.prevPage();
      return KeyEventResult.handled;
    }

    if (logicalKey == LogicalKeyboardKey.enter) {
      showOrHideAppBarAndBottomBar(true);
      return KeyEventResult.handled;
    }

    if (Prefs().volumeKeyTurnPage) {
      if (event.physicalKey == PhysicalKeyboardKey.audioVolumeUp) {
        epubPlayerKey.currentState?.prevPage();
        return KeyEventResult.handled;
      }
      if (event.physicalKey == PhysicalKeyboardKey.audioVolumeDown) {
        epubPlayerKey.currentState?.nextPage();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_readTimeWatch.isRunning) {
          _readTimeWatch.start();
        }
        _sessionStart ??= DateTime.now();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (_readTimeWatch.isRunning) {
          _readTimeWatch.stop();
        }
        if (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.detached) {
          final elapsedSeconds = _readTimeWatch.elapsed.inSeconds;
          if (elapsedSeconds > 5) {
            epubPlayerKey.currentState?.saveReadingProgress();
            readingTimeDao.insertReadingTime(
              ReadingTime(
                bookId: _book.id,
                readingTime: elapsedSeconds,
              ),
              startedAt: _sessionStart,
            );
          }
          _readTimeWatch.reset();
          _sessionStart = null;
        }
        break;
    }
  }

  Future<void> setAwakeTimer(int minutes) async {
    _awakeTimer?.cancel();
    _awakeTimer = null;
    WakelockPlus.enable();
    _awakeTimer = Timer.periodic(Duration(minutes: minutes), (timer) {
      WakelockPlus.disable();
      _awakeTimer?.cancel();
      _awakeTimer = null;
    });
  }

  void resetAwakeTimer() {
    setAwakeTimer(Prefs().awakeTime);
  }

  void showBottomBar() {
    setState(() {
      showStatusBarWithoutResize();
      bottomBarOffstage = false;
      _releaseReaderFocus();
    });
  }

  void hideBottomBar() {
    setState(() {
      _currentPage = empty;
      bottomBarOffstage = true;
      if (Prefs().hideStatusBar) {
        hideStatusBar();
      }
      _requestReaderFocus();
    });
  }

  void showOrHideAppBarAndBottomBar(bool show) {
    if (show) {
      showBottomBar();
    } else {
      hideBottomBar();
    }
  }

  Future<void> tocHandler() async {
    hideBottomBar();
    _scaffoldKey.currentState?.openDrawer();
  }

  void noteHandler() {
    setState(() {
      _currentPage = ReadingNotes(book: _book);
    });
  }

  void progressHandler() {
    setState(() {
      _currentPage = ProgressWidget(
        epubPlayerKey: epubPlayerKey,
        showOrHideAppBarAndBottomBar: showOrHideAppBarAndBottomBar,
      );
    });
  }

  Future<void> styleHandler(StateSetter modalSetState) async {
    List<ReadTheme> themes = await themeDao.selectThemes();
    setState(() {
      _currentPage = StyleWidget(
        themes: themes,
        epubPlayerKey: epubPlayerKey,
        setCurrentPage: (Widget page) {
          modalSetState(() {
            _currentPage = page;
          });
        },
        hideAppBarAndBottomBar: showOrHideAppBarAndBottomBar,
      );
    });
  }

  Future<void> ttsHandler() async {
    setState(() {
      _currentPage = TtsWidget(
        epubPlayerKey: epubPlayerKey,
      );
    });
  }

  double _aiChatMaxWidth(BuildContext context) {
    final totalWidth = MediaQuery.of(context).size.width;
    final maxByPercentage = totalWidth * 0.65;
    final maxByRemaining = totalWidth - 320;
    final maxWidth = math.min(maxByPercentage, maxByRemaining);
    return math.max(_aiChatMinWidth, maxWidth);
  }

  double _aiChatMaxHeight(BuildContext context) {
    final totalHeight = MediaQuery.of(context).size.height;
    final maxByPercentage = totalHeight * 0.60;
    final maxByRemaining = totalHeight - 320;
    final maxHeight = math.min(maxByPercentage, maxByRemaining);
    return math.max(_aiChatMinHeight, maxHeight);
  }

  void _beginAiChatResize(double globalDx) {
    setState(() {
      _isResizingAiChat = true;
    });
  }

  void _applyAiChatResizeDelta(double delta, BuildContext context) {
    final maxWidth = _aiChatMaxWidth(context);
    final updated =
        (_aiChatWidth - delta).clamp(_aiChatMinWidth, maxWidth).toDouble();
    if (updated != _aiChatWidth) {
      setState(() {
        _aiChatWidth = updated;
      });
    }
  }

  void _endAiChatResize() {
    // Persist size to preferences.
    try {
      Prefs().aiPanelWidth = _aiChatWidth;
      Prefs().aiPanelHeight = _aiChatHeight;
    } catch (_) {}
    if (_isResizingAiChat) {
      setState(() {
        _isResizingAiChat = false;
      });
    }
  }

  void _beginAiChatResizeVertical(double globalDy) {
    setState(() {
      _isResizingAiChat = true;
    });
  }

  void _applyAiChatResizeDeltaVertical(double delta, BuildContext context) {
    final maxHeight = _aiChatMaxHeight(context);
    final updated =
        (_aiChatHeight - delta).clamp(_aiChatMinHeight, maxHeight).toDouble();
    if (updated != _aiChatHeight) {
      setState(() {
        _aiChatHeight = updated;
      });
    }
  }

  Future<void> onLoadEnd() async {
    final pendingHref = widget.openHref;
    if (pendingHref != null && pendingHref.trim().isNotEmpty) {
      try {
        epubPlayerKey.currentState?.goToHref(pendingHref.trim());
      } catch (_) {
        // best-effort
      }
    }

    if (Prefs().autoSummaryPreviousContent) {
      final previousContent =
          await epubPlayerKey.currentState!.previousContent(2000);
      final prompt = generatePromptSummaryThePreviousContent(previousContent);
      SmartDialog.show(
        builder: (context) => AlertDialog(
          title: Text(L10n.of(context).readingPageSummaryPreviousContent),
          content: AiStream(
            prompt: prompt,
          ),
        ),
        onDismiss: () {
          cancelActiveAiRequest();
        },
      );
    }
  }

  List<Widget> _buildAiChatTrailing(BuildContext context) {
    return [
      IconButton(
        onPressed: () {
          setState(() {
            Prefs().aiPanelPosition =
                Prefs().aiPanelPosition == AiPanelPositionEnum.right
                    ? AiPanelPositionEnum.bottom
                    : AiPanelPositionEnum.right;
            // Rebuild the _aiChat widget to update the button
            _rebuildAiChat();
          });
        },
        icon: Icon(
          Prefs().aiPanelPosition == AiPanelPositionEnum.right
              ? Icons.arrow_downward
              : Icons.arrow_forward,
        ),
        tooltip: Prefs().aiPanelPosition == AiPanelPositionEnum.right
            ? L10n.of(context).aiShowAtBottom
            : L10n.of(context).aiShowAtRight,
      ),
      IconButton(
        onPressed: () {
          setState(() {
            _aiChat = null;
          });
        },
        icon: const Icon(Icons.close),
      ),
    ];
  }

  Future<void> _openAiSourceInCurrentReader(WidgetRef ref, Uri uri) async {
    final playerState = epubPlayerKey.currentState;
    if (playerState != null) {
      final opened = PaperReaderCurrentSourceOpener.tryOpen(
        uri: uri,
        currentBookId: _book.id,
        goToCfi: playerState.goToCfi,
        goToHref: playerState.goToHref,
        beforeOpen: () {
          if (_aiChatVisible && mounted) {
            setState(() => _aiChatVisible = false);
          }
        },
      );
      if (opened) {
        return;
      }
    }

    await openPaperReaderSource(ref, uri);
  }

  void _rebuildAiChat() {
    if (_aiChat == null) return;
    final maxWidth = _aiChatMaxWidth(context);
    final maxHeight = _aiChatMaxHeight(context);
    _aiChatWidth = _aiChatWidth.clamp(_aiChatMinWidth, maxWidth);
    _aiChatHeight = _aiChatHeight.clamp(_aiChatMinHeight, maxHeight);
    _aiChat = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: AiMultiTabChat(
            key: aiChatKey,
            initialMessage: null,
            initialSourceRef: _aiInitialSourceRef,
            sourceOpener: _openAiSourceInCurrentReader,
            sendImmediate: false,
            quickPromptChips: _getAiQuickPromptChips(),
            trailing: _buildAiChatTrailing(context),
          ),
        ),
      ],
    );
  }

  /// Returns true if AI panel is currently docked on the left side.
  /// This is used to disable drawer edge-swipe gesture to avoid conflicts.
  bool _isAiDockedLeft() {
    final width = MediaQuery.of(navigatorKey.currentContext!).size.width;
    if (width < 600) return false;
    if (Prefs().aiPadPanelMode != AiPadPanelModeEnum.dock) return false;
    if (Prefs().aiPanelPosition != AiPanelPositionEnum.right) return false;
    return Prefs().aiDockSide == AiDockSideEnum.left && _aiChat != null;
  }

  Widget _buildMainLayout(BuildContext context) {
    final kairosHint = ref.watch(kairosHintProvider);
    final axis = Prefs().aiPanelPosition == AiPanelPositionEnum.right
        ? Axis.horizontal
        : Axis.vertical;
    final dockLeft = Prefs().aiDockSide == AiDockSideEnum.left &&
        Prefs().aiPanelPosition == AiPanelPositionEnum.right;

    final readerContent = Expanded(
      child: MouseRegion(
        onHover: (PointerHoverEvent detail) {
          if (!Prefs().showMenuOnHover) return;
          var y = detail.position.dy;
          if (y < 30 || y > MediaQuery.of(context).size.height - 30) {
            showOrHideAppBarAndBottomBar(true);
          }
        },
        child: Focus(
          focusNode: _readerFocusNode,
          onKeyEvent: _handleReaderKeyEvent,
          child: Stack(
            children: [
              EpubPlayer(
                key: epubPlayerKey,
                book: _book,
                cfi: widget.cfi,
                showOrHideAppBarAndBottomBar: showOrHideAppBarAndBottomBar,
                onLoadEnd: onLoadEnd,
                initialThemes: widget.initialThemes,
                updateParent: updateState,
                onRequestAiChat: () {
                  showAiChat();
                },
                onUserInteraction: resetAwakeTimer,
              ),
              // Swipe up from lower-middle area to open AI bottom sheet.
              if (_shouldUseAiBottomSheet(context))
                Positioned(
                  left: MediaQuery.of(context).size.width * 0.25,
                  right: MediaQuery.of(context).size.width * 0.25,
                  bottom: 0,
                  height: 140,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragStart: (_) {
                      _aiSwipeUpTotalDy = 0;
                      _aiSwipeUpTriggered = false;
                    },
                    onVerticalDragUpdate: (details) {
                      _aiSwipeUpTotalDy += details.delta.dy;
                      if (!_aiSwipeUpTriggered && _aiSwipeUpTotalDy < -40) {
                        _aiSwipeUpTriggered = true;
                        showAiChat();
                      }
                    },
                    onVerticalDragEnd: (details) {
                      final v = details.primaryVelocity ?? 0;
                      if (!_aiSwipeUpTriggered && v < -500) {
                        _aiSwipeUpTriggered = true;
                        showAiChat();
                      }
                      _aiSwipeUpTotalDy = 0;
                      _aiSwipeUpTriggered = false;
                    },
                    onVerticalDragCancel: () {
                      _aiSwipeUpTotalDy = 0;
                      _aiSwipeUpTriggered = false;
                    },
                  ),
                ),
              if (_isResizingAiChat)
                SizedBox.expand(
                  child: Container(
                    color: Theme.of(context).colorScheme.surface.withAlpha(1),
                  ),
                ),
              // KAIROS proactive reading hint.
              if (kairosHint != null)
                Positioned(
                  bottom: 80,
                  left: 16,
                  right: 16,
                  child: Center(
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(24),
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () {
                          ref.read(kairosHintProvider.notifier).state = null;
                          showAiChat(
                            content: kairosHint.suggestedPrompt,
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome,
                                  size: 16,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondaryContainer),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  kairosHint.message,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSecondaryContainer,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () {
                                  ref.read(kairosHintProvider.notifier).state =
                                      null;
                                },
                                child: Icon(Icons.close,
                                    size: 14,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondaryContainer),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return AxisFlex(
      axis: axis,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: dockLeft
          ? [
              if (_aiChat != null) _buildAiPanel(context),
              if (_aiChat != null) _buildAiPanelDivider(context, axis),
              readerContent,
            ]
          : [
              readerContent,
              if (_aiChat != null) _buildAiPanelDivider(context, axis),
              if (_aiChat != null) _buildAiPanel(context),
            ],
    );
  }

  Widget _buildAiPanel(BuildContext context) {
    return SizedBox(
      key: const ValueKey('ai-chat-panel'),
      width: Prefs().aiPanelPosition == AiPanelPositionEnum.right
          ? _aiChatWidth
          : null,
      height: Prefs().aiPanelPosition == AiPanelPositionEnum.bottom
          ? _aiChatHeight
          : null,
      child: _aiChat,
    );
  }

  Widget _buildAiPanelDivider(BuildContext context, Axis axis) {
    final dockLeft = Prefs().aiDockSide == AiDockSideEnum.left &&
        Prefs().aiPanelPosition == AiPanelPositionEnum.right;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart:
          Prefs().aiPanelPosition == AiPanelPositionEnum.right
              ? (details) {
                  HapticFeedback.selectionClick();
                  _beginAiChatResize(details.globalPosition.dx);
                }
              : null,
      onHorizontalDragUpdate:
          Prefs().aiPanelPosition == AiPanelPositionEnum.right
              ? (details) {
                  // Flip delta for left-dock to make drag direction intuitive.
                  final delta = dockLeft ? -details.delta.dx : details.delta.dx;
                  _applyAiChatResizeDelta(delta, context);
                }
              : null,
      onHorizontalDragEnd: Prefs().aiPanelPosition == AiPanelPositionEnum.right
          ? (_) => _endAiChatResize()
          : null,
      onHorizontalDragCancel:
          Prefs().aiPanelPosition == AiPanelPositionEnum.right
              ? () => _endAiChatResize()
              : null,
      onVerticalDragStart: Prefs().aiPanelPosition == AiPanelPositionEnum.bottom
          ? (details) {
              HapticFeedback.selectionClick();
              _beginAiChatResizeVertical(details.globalPosition.dy);
            }
          : null,
      onVerticalDragUpdate:
          Prefs().aiPanelPosition == AiPanelPositionEnum.bottom
              ? (details) {
                  _applyAiChatResizeDeltaVertical(details.delta.dy, context);
                }
              : null,
      onVerticalDragEnd: Prefs().aiPanelPosition == AiPanelPositionEnum.bottom
          ? (_) => _endAiChatResize()
          : null,
      onVerticalDragCancel:
          Prefs().aiPanelPosition == AiPanelPositionEnum.bottom
              ? () => _endAiChatResize()
              : null,
      child: MouseRegion(
        cursor: Prefs().aiPanelPosition == AiPanelPositionEnum.right
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        child: SizedBox(
          width: axis == Axis.horizontal ? 16 : null,
          height: axis == Axis.vertical ? 16 : null,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (axis == Axis.horizontal)
                const VerticalDivider(width: 16, thickness: 1)
              else
                const Divider(height: 16, thickness: 1),
              if (axis == Axis.vertical)
                RotatedBox(
                  quarterTurns: 1,
                  child: Icon(
                    Icons.drag_indicator,
                    size: 16,
                    color:
                        Theme.of(context).colorScheme.onSurface.withAlpha(120),
                  ),
                )
              else
                Icon(
                  Icons.drag_indicator,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<AiQuickPromptChip> _getAiQuickPromptChips() {
    return [
      AiQuickPromptChip(
        icon: EvaIcons.book,
        label: L10n.of(context).settingsAiPromptSummaryTheChapter,
        prompt: generatePromptSummaryTheChapter().buildString(),
      ),
      AiQuickPromptChip(
        icon: Icons.menu_book_rounded,
        label: L10n.of(context).settingsAiPromptSummaryTheBook,
        prompt: generatePromptSummaryTheBook().buildString(),
      ),
      AiQuickPromptChip(
        icon: Icons.account_tree_outlined,
        label: L10n.of(context).settingsAiPromptMindmap,
        prompt: generatePromptMindmap().buildString(),
      ),
      // User custom prompts (enabled only)
      ...Prefs()
          .userPrompts
          .where((p) => p.enabled)
          .map((userPrompt) => AiQuickPromptChip(
                icon: Icons.person_outline,
                label: userPrompt.name,
                prompt: userPrompt.content,
              )),
    ];
  }

  bool _shouldUseAiBottomSheet(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return screenWidth < 600 ||
        (screenWidth >= 600 &&
            Prefs().aiPadPanelMode == AiPadPanelModeEnum.bottomSheet);
  }

  Future<void> showAiChat({
    String? content,
    bool sendImmediate = false,
    SourceRef? sourceRef,
  }) async {
    List<AiQuickPromptChip> quickPrompts = _getAiQuickPromptChips();
    final useBottomSheet =
        _shouldUseAiBottomSheet(navigatorKey.currentContext!);

    if (useBottomSheet) {
      if (_aiChatCreated) {
        // Panel already in the tree — just reveal it.
        setState(() => _aiChatVisible = true);
        if (content != null) {
          aiChatKey.currentState?.prefillDraft(
            message: content,
            sourceRef: sourceRef,
          );
        }
        if (sendImmediate) {
          aiChatKey.currentState?.sendDraft();
        }
        return;
      }

      // First creation: store initial parameters and make visible.
      setState(() {
        _aiInitialMessage = content;
        _aiInitialSourceRef = sourceRef;
        _aiSendImmediate = sendImmediate;
        _aiChatCreated = true;
        _aiChatVisible = true;
      });
    } else {
      setState(() {
        _aiInitialSourceRef = sourceRef;
        final maxWidth = _aiChatMaxWidth(navigatorKey.currentContext!);
        final maxHeight = _aiChatMaxHeight(navigatorKey.currentContext!);
        _aiChatWidth = _aiChatWidth.clamp(_aiChatMinWidth, maxWidth);
        _aiChatHeight = _aiChatHeight.clamp(_aiChatMinHeight, maxHeight);
        _aiChat = Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: AiMultiTabChat(
                key: aiChatKey,
                initialMessage: content,
                initialSourceRef: sourceRef,
                sourceOpener: _openAiSourceInCurrentReader,
                sendImmediate: sendImmediate,
                quickPromptChips: quickPrompts,
                trailing: _buildAiChatTrailing(navigatorKey.currentContext!),
              ),
            ),
          ],
        );
      });
    }
  }

  Future<void> openAiChatDraft({
    String? content,
    List<AttachmentItem>? attachments,
    bool replaceAttachments = false,
    SourceRef? sourceRef,
  }) async {
    await showAiChat(
      content: content,
      sendImmediate: false,
      sourceRef: sourceRef,
    );
    final aiChat = await _waitForAiChatState();
    aiChat?.prefillDraft(
      message: content,
      attachments: attachments,
      replaceAttachments: replaceAttachments,
      sourceRef: sourceRef,
    );
  }

  Future<void> openAiChatSeminar({
    String? question,
    SourceRef? sourceRef,
    int? bookId,
  }) async {
    await showAiChat(sourceRef: sourceRef);
    final aiChat = await _waitForAiChatState();
    aiChat?.openSeminar(
      question: question,
      bookId: sourceRef?.bookId ?? bookId,
      sourceRef: sourceRef,
    );
  }

  Future<AiMultiTabChatState?> _waitForAiChatState({
    int maxFrames = 8,
  }) async {
    for (var attempt = 0; attempt < maxFrames; attempt += 1) {
      final state = aiChatKey.currentState;
      if (state != null) return state;
      if (!mounted) return null;
      await WidgetsBinding.instance.endOfFrame;
    }
    return aiChatKey.currentState;
  }

  void updateState() {
    if (mounted) {
      setState(() {
        bookmarkExists = epubPlayerKey.currentState!.bookmarkExists;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Feed KAIROS with reading position updates.
    final readingState = ref.watch(currentReadingProvider);
    _kairos.onPositionUpdate(
      cfi: readingState.cfi,
      chapterTitle: readingState.chapterTitle,
      percentage: readingState.percentage,
    );

    var aiButton = IconButton(
      tooltip: L10n.of(context).aiChat,
      icon: const Icon(Icons.auto_awesome),
      onPressed: () async {
        if (MediaQuery.of(context).size.width > 600 && _aiChat != null) {
          setState(() {
            _aiChat = null;
          });
          return;
        }

        showOrHideAppBarAndBottomBar(false);
        showAiChat();
      },
    );
    Offstage controller = Offstage(
      offstage: bottomBarOffstage,
      child: PointerInterceptor(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                  onTap: () {
                    showOrHideAppBarAndBottomBar(false);
                  },
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) {},
                  onVerticalDragEnd: (details) {},
                  child: Container(
                    color: Colors.black.withAlpha(30),
                  )),
            ),
            Column(
              children: [
                AppBar(
                  title: Text(_book.title, overflow: TextOverflow.ellipsis),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      // close reading page
                      Navigator.pop(context);
                    },
                  ),
                  actions: [
                    if (EnvVar.enableAIFeature) aiButton,
                    IconButton(
                      icon: _translationModeIcon(
                        Prefs().getBookTranslationMode(widget.book.id),
                      ),
                      tooltip:
                          L10n.of(context).readingPageToggleFullTextTranslation,
                      onPressed: () {
                        final current =
                            Prefs().getBookTranslationMode(widget.book.id);
                        final next = switch (current) {
                          TranslationModeEnum.off =>
                            TranslationModeEnum.translationOnly,
                          TranslationModeEnum.originalOnly =>
                            TranslationModeEnum.translationOnly,
                          TranslationModeEnum.translationOnly =>
                            TranslationModeEnum.bilingual,
                          TranslationModeEnum.bilingual =>
                            TranslationModeEnum.off,
                        };

                        Prefs().setBookTranslationMode(widget.book.id, next);
                        epubPlayerKey.currentState?.setTranslationMode(next);

                        if (next != TranslationModeEnum.off) {
                          // Ensure HUD is visible when enabling (paginated mode only).
                          epubPlayerKey.currentState?.showInlineTranslateHud();
                        }

                        setState(() {});
                      },
                    ),
                    IconButton(
                        tooltip: L10n.of(context).readingPageBookmark,
                        onPressed: () {
                          if (bookmarkExists) {
                            epubPlayerKey.currentState!.removeAnnotation(
                              epubPlayerKey.currentState!.bookmarkCfi,
                            );
                          } else {
                            epubPlayerKey.currentState!.addBookmarkHere();
                          }
                        },
                        icon: bookmarkExists
                            ? const Icon(Icons.bookmark)
                            : const Icon(Icons.bookmark_border)),
                    IconButton(
                      tooltip: L10n.of(context).readingPageOpenReadingSettings,
                      icon: const Icon(EvaIcons.more_vertical),
                      onPressed: () {
                        showMoreSettings(ReadingSettings.theme);
                      },
                    ),
                  ],
                ),
                const Spacer(),
                BottomSheet(
                  onClosing: () {},
                  enableDrag: false,
                  builder: (context) => SafeArea(
                    top: false,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: StatefulBuilder(
                        builder: (BuildContext context, StateSetter setState) {
                          final hasContent = !identical(_currentPage, empty);
                          return IntrinsicHeight(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (hasContent)
                                  Expanded(
                                    child: _currentPage,
                                  ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.md,
                                      vertical: AppSpacing.sm),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.toc,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface),
                                        onPressed: tocHandler,
                                      ),
                                      IconButton(
                                        icon: Icon(EvaIcons.edit,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface),
                                        onPressed: noteHandler,
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.data_usage,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface),
                                        onPressed: progressHandler,
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.color_lens,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface),
                                        onPressed: () {
                                          styleHandler(setState);
                                        },
                                      ),
                                      IconButton(
                                        icon: Icon(EvaIcons.headphones,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface),
                                        onPressed: ttsHandler,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          height: MediaQuery.of(context).size.height,
          width: MediaQuery.of(context).size.width,
          child: Scaffold(
            key: _scaffoldKey,
            resizeToAvoidBottomInset: false,
            // Disable edge-swipe to open drawer when AI is docked on the left
            // to avoid gesture conflicts.
            drawerEnableOpenDragGesture: !_isAiDockedLeft(),
            drawer: PointerInterceptor(
              child: Drawer(
                width: math.min(
                  MediaQuery.of(context).size.width * 0.8,
                  420,
                ),
                child: SafeArea(
                  child: TocWidget(
                    epubPlayerKey: epubPlayerKey,
                    hideAppBarAndBottomBar: showOrHideAppBarAndBottomBar,
                    closeDrawer: () {
                      _scaffoldKey.currentState?.closeDrawer();
                    },
                  ),
                ),
              ),
            ),
            body: Stack(
              children: [
                _buildMainLayout(context),
                if (bottomBarOffstage && !_aiChatVisible)
                  const Positioned(
                    right: 16,
                    bottom: 24,
                    child: TtsFab(),
                  ),
                controller,
                // Persistent AI chat panel. AnimatedSlide keeps the widget
                // tree alive (including all per-tab ProviderScopes) so that
                // streaming continues and state is preserved while hidden,
                // while still providing a smooth slide-up/down animation.
                if (_aiChatCreated)
                  Positioned.fill(
                    child: AnimatedSlide(
                      offset: _aiChatVisible ? Offset.zero : const Offset(0, 1),
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      child: IgnorePointer(
                        ignoring: !_aiChatVisible,
                        child: PointerInterceptor(
                          child: Material(
                            clipBehavior: Clip.antiAlias,
                            borderRadius: const BorderRadius.vertical(
                              top:
                                  Radius.circular(AppSpacing.cornerRadiusLarge),
                            ),
                            child: AiMultiTabChat(
                              key: aiChatKey,
                              initialMessage: _aiInitialMessage,
                              initialSourceRef: _aiInitialSourceRef,
                              sourceOpener: _openAiSourceInCurrentReader,
                              sendImmediate: _aiSendImmediate,
                              quickPromptChips: _getAiQuickPromptChips(),
                              uiVisible: _aiChatVisible,
                              inputSafeAreaBottom: false,
                              onRequestMinimize: () {
                                if (mounted) {
                                  setState(() => _aiChatVisible = false);
                                }
                              },
                              onTapTabBar: () {
                                if (mounted) {
                                  setState(() => _aiChatVisible = false);
                                }
                              },
                              trailing: [
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    if (mounted) {
                                      setState(() => _aiChatVisible = false);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
