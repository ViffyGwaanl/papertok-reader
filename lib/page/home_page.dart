import 'dart:ui';

import 'package:cupertino_native/cupertino_native.dart';
import 'package:flutter/foundation.dart';

import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/enums/sync_trigger.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/home_page/ai_page.dart';
import 'package:anx_reader/page/home_page/home_bottom_inset_scope.dart';
import 'package:anx_reader/service/initialization_check.dart';
import 'package:anx_reader/page/home_page/bookshelf_page.dart';
import 'package:anx_reader/page/home_page/papers_page.dart';
import 'package:anx_reader/page/home_page/notes_page.dart';
import 'package:anx_reader/page/home_page/settings_page.dart';
import 'package:anx_reader/page/home_page/statistics_page.dart';
import 'package:anx_reader/service/receive_file/receive_share.dart';
import 'package:anx_reader/service/vibration_service.dart';
import 'package:anx_reader/utils/check_update.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:anx_reader/utils/get_path/get_temp_dir.dart';
import 'package:anx_reader/utils/load_default_font.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:anx_reader/widgets/home/icon_only_native_tab_bar.dart';
import 'package:anx_reader/widgets/settings/about.dart';
import 'package:flutter/cupertino.dart';
// import 'package:flutter_floating_bottom_bar/flutter_floating_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:url_launcher/url_launcher.dart';

WebViewEnvironment? webViewEnvironment;

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  String _currentTab = Prefs.homeTabPapers;

  bool? _expanded;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => initAnx());
  }

  Future<void> _checkWindowsWebview() async {
    final availableVersion = await WebViewEnvironment.getAvailableVersion();
    AnxLog.info('WebView2 version: $availableVersion');

    if (availableVersion == null) {
      SmartDialog.show(
        builder: (context) => AlertDialog(
          title: const Icon(Icons.error),
          content: Text(L10n.of(context).webview2NotInstalled),
          actions: [
            TextButton(
              onPressed: () => {
                launchUrl(
                  Uri.parse(
                    'https://developer.microsoft.com/en-us/microsoft-edge/webview2',
                  ),
                  mode: LaunchMode.externalApplication,
                ),
              },
              child: Text(L10n.of(context).webview2Install),
            ),
          ],
        ),
      );
    } else {
      webViewEnvironment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
          userDataFolder: (await getAnxTempDir()).path,
        ),
      );
    }
  }

  void _showDbUpdatedDialog() {
    SmartDialog.show(
      clickMaskDismiss: false,
      builder: (context) => AlertDialog(
        title: Text(L10n.of(context).commonAttention),
        content: Text(L10n.of(context).dbUpdatedTip),
        actions: [
          TextButton(
            onPressed: () {
              SmartDialog.dismiss();
            },
            child: Text(L10n.of(context).commonOk),
          ),
        ],
      ),
    );
  }

  Future<void> initAnx() async {
    AnxToast.init(context);
    checkUpdate(false);
    InitializationCheck.check();
    if (Prefs().webdavStatus) {
      await Sync().init();
      await Sync().syncData(SyncDirection.both, ref, trigger: SyncTrigger.auto);
    }
    loadDefaultFont();

    if (AnxPlatform.isWindows) {
      await _checkWindowsWebview();
    }

    if (AnxPlatform.isAndroid || AnxPlatform.isIOS || AnxPlatform.isOhos) {
      receiveShareIntent(ref);
    }

    if (DBHelper.updatedDB) {
      _showDbUpdatedDialog();
    }
  }

  @override
  Widget build(BuildContext context) {
    final homeOrder = Prefs().homeTabsOrder;
    final homeEnabled = Prefs().homeTabsEnabled;

    final defs = <String, Map<String, dynamic>>{
      Prefs.homeTabPapers: {
        'icon': Icons.article_outlined,
        'label': L10n.of(context).navBarPapers,
        'identifier': Prefs.homeTabPapers,
      },
      Prefs.homeTabBookshelf: {
        'icon': EvaIcons.book_open,
        'label': L10n.of(context).navBarBookshelf,
        'identifier': Prefs.homeTabBookshelf,
      },
      Prefs.homeTabStatistics: {
        'icon': Icons.show_chart,
        'label': L10n.of(context).navBarStatistics,
        'identifier': Prefs.homeTabStatistics,
      },
      Prefs.homeTabAI: {
        'icon': Icons.auto_awesome,
        'label': L10n.of(context).navBarAI,
        'identifier': Prefs.homeTabAI,
      },
      Prefs.homeTabNotes: {
        'icon': Icons.note,
        'label': L10n.of(context).navBarNotes,
        'identifier': Prefs.homeTabNotes,
      },
      Prefs.homeTabSettings: {
        'icon': EvaIcons.settings_2,
        'label': L10n.of(context).navBarSettings,
        'identifier': Prefs.homeTabSettings,
      },
    };

    final List<Map<String, dynamic>> navBarItems = [];
    for (final id in homeOrder) {
      if (!(homeEnabled[id] ?? true)) continue;
      if (id == Prefs.homeTabAI && !EnvVar.enableAIFeature) continue;
      final def = defs[id];
      if (def != null) navBarItems.add(def);
    }

    int currentIndex = navBarItems.indexWhere(
      (element) => element['identifier'] == _currentTab,
    );
    if (currentIndex == -1) {
      _currentTab = Prefs.homeTabPapers;
      currentIndex = navBarItems.indexWhere(
        (element) => element['identifier'] == _currentTab,
      );
      if (currentIndex == -1 && navBarItems.isNotEmpty) {
        currentIndex = 0;
        _currentTab = navBarItems[0]['identifier'];
      }
    }

    Widget pageFor(String id, ScrollController? controller) {
      switch (id) {
        case Prefs.homeTabPapers:
          return PapersPage(controller: controller);
        case Prefs.homeTabBookshelf:
          return BookshelfPage(controller: controller);
        case Prefs.homeTabStatistics:
          return StatisticPage(controller: controller);
        case Prefs.homeTabAI:
          return const AiPage();
        case Prefs.homeTabNotes:
          return NotesPage(controller: controller);
        case Prefs.homeTabSettings:
          return SettingsPage(controller: controller);
        default:
          return BookshelfPage(controller: controller);
      }
    }

    Widget pages(
      int index,
      BoxConstraints constraints,
      ScrollController? controller,
    ) {
      final id = navBarItems[index]['identifier'] as String;
      return pageFor(id, controller);
    }

    void onBottomTap(int index, bool fromRail) {
      VibrationService.heavy();
      setState(() {
        _currentTab = navBarItems[index]['identifier'];
      });
    }

    List<NavigationRailDestination> railBarItems = navBarItems.map((item) {
      return NavigationRailDestination(
        icon: Icon(item['icon'] as IconData),
        label: Text(item['label'] as String),
      );
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        _expanded ??= constraints.maxWidth > 1000;
        if (constraints.maxWidth > 600) {
          return Scaffold(
            extendBody: true,
            body: Row(
              children: [
                SafeArea(
                  bottom: false,
                  child: FilledContainer(
                    margin: const EdgeInsets.all(16),
                    color: ElevationOverlay.applySurfaceTint(
                      Theme.of(context).colorScheme.surface,
                      Theme.of(context).colorScheme.primary,
                      3,
                    ),
                    radius: 20,
                    child: SafeArea(
                      child: NavigationRail(
                        leading: InkWell(
                          onTap: () => openAboutDialog(),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 2.0),
                            child: Image.asset(
                              'assets/icon/paper_reader_logo.png',
                              width: 32,
                              height: 32,
                            ),
                          ),
                        ),
                        groupAlignment: 1,
                        extended: false,
                        selectedIndex: currentIndex,
                        onDestinationSelected: (int index) =>
                            onBottomTap(index, true),
                        destinations: railBarItems,
                        labelType: NavigationRailLabelType.all,
                        backgroundColor: Colors.transparent,
                        // elevation: 0,
                      ),
                    ),
                  ),
                ),
                Expanded(child: pages(currentIndex, constraints, null)),
              ],
            ),
          );
        } else {
          // Floating tab bar on phones.
          final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

          // Recommended policy: when keyboard is visible, hide the tab bar.
          // This avoids the bar being lifted above the keyboard and keeps the
          // input area unobstructed.
          final showTabBar = !keyboardVisible;

          final bottomInset = MediaQuery.of(context).padding.bottom;

          bool useCupertinoNativeTabBar() {
            if (kIsWeb) return false;
            return defaultTargetPlatform == TargetPlatform.iOS;
          }

          // Keep stable dimensions regardless of whether labels are shown.
          final tabBarHeight = useCupertinoNativeTabBar() ? 76.0 : 64.0;
          // Visual lift above the very bottom edge.
          const tabBarBottomPadding = 4.0;

          // Pages with bottom interactive UI (e.g. chat input) should avoid
          // being covered by the floating tab bar.
          final contentBottomInset =
              showTabBar ? (tabBarHeight + tabBarBottomPadding) : 0.0;

          String symbolForId(String id) {
            switch (id) {
              case Prefs.homeTabPapers:
                return 'doc.text.fill';
              case Prefs.homeTabBookshelf:
                return 'books.vertical.fill';
              case Prefs.homeTabStatistics:
                return 'chart.bar.fill';
              case Prefs.homeTabAI:
                return 'sparkles';
              case Prefs.homeTabNotes:
                return 'note.text';
              case Prefs.homeTabSettings:
                return 'gearshape.fill';
              default:
                return 'circle.fill';
            }
          }

          Widget buildMaterialFloatingTabBar() {
            final cs = Theme.of(context).colorScheme;
            return ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18.0, sigmaY: 18.0),
                child: Container(
                  height: tabBarHeight,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainer.withAlpha(170),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: cs.outline.withAlpha(110),
                      width: 0.5,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  // Icon-only tab row: every segment is fully tappable.
                  child: Material(
                    color: Colors.transparent,
                    child: Row(
                      children: List.generate(navBarItems.length, (i) {
                        final item = navBarItems[i];
                        final selected = i == currentIndex;
                        final color =
                            selected ? cs.primary : cs.onSurfaceVariant;

                        return Expanded(
                          child: Semantics(
                            button: true,
                            selected: selected,
                            label: item['label'] as String,
                            child: InkResponse(
                              onTap: () => onBottomTap(i, false),
                              containedInkWell: true,
                              highlightShape: BoxShape.rectangle,
                              highlightColor: cs.primary.withAlpha(18),
                              splashColor: Colors.transparent,
                              child: SizedBox(
                                height: tabBarHeight,
                                width: double.infinity,
                                child: Center(
                                  child: Icon(
                                    item['icon'] as IconData,
                                    color: color,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
            );
          }

          Widget buildCupertinoNativeTabBar() {
            return IconOnlyNativeTabBar(
              height: tabBarHeight,
              items: [
                for (final item in navBarItems)
                  CNSymbol(
                    symbolForId(item['identifier'] as String),
                    size: 20,
                  ),
              ],
              currentIndex: currentIndex,
              onTap: (i) => onBottomTap(i, false),
            );
          }

          Widget buildTabBar() {
            return SafeArea(
              top: false,
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 0, 16, tabBarBottomPadding),
                child: useCupertinoNativeTabBar()
                    ? buildCupertinoNativeTabBar()
                    : buildMaterialFloatingTabBar(),
              ),
            );
          }

          return Scaffold(
            extendBody: false,
            body: Stack(
              children: [
                HomeBottomInsetScope(
                  bottomInset: contentBottomInset,
                  child: pages(currentIndex, constraints, null),
                ),
                if (showTabBar)
                  Positioned(
                    left: 0,
                    right: 0,
                    // Place the bar into the bottom safe-area region to reduce
                    // content obstruction.
                    bottom: -bottomInset,
                    child: buildTabBar(),
                  ),
              ],
            ),
          );
        }
      },
    );
  }
}
