import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/claude_palette.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/other_settings.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/reading_settings.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/style_settings.dart';
import 'package:contentsize_tabbarview/contentsize_tabbarview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

enum ReadingSettings { theme, style }

void showMoreSettings(ReadingSettings settings) {
  BuildContext context = navigatorKey.currentContext!;
  // Navigator.of(context).pop();
  readingPageKey.currentState!.showOrHideAppBarAndBottomBar(false);

  final List<String> tabLabels = [
    L10n.of(context).readingPageReading,
    L10n.of(context).readingPageStyle,
    L10n.of(context).readingPageOther,
  ];

  List<Widget> children = [
    const ReadingMoreSettings(),
    const StyleSettings(),
    const OtherSettings(),
  ];

  TabController? tabController = TabController(
    length: tabLabels.length,
    vsync: Navigator.of(context),
    initialIndex: settings == ReadingSettings.theme ? 0 : 1,
  );

  showDialog(
    context: context,
    builder: (context) {
      return Dialog(
        backgroundColor: ClaudePalette.card(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusLarge),
        ),
        child: PointerInterceptor(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: _ClaudePillTabBar(
                    controller: tabController,
                    labels: tabLabels,
                  ),
                ),
                Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: ClaudePalette.divider(context),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                    maxWidth: MediaQuery.of(context).size.width * 0.8,
                  ),
                  child: SingleChildScrollView(
                    child: ContentSizeTabBarView(
                      animationDuration: const Duration(milliseconds: 600),
                      controller: tabController,
                      children: children,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Custom pill-shaped tab bar for the reading settings dialog.
///
/// Uses [ClaudePalette] tokens directly so it is immune to any user-selected
/// seed color override that would otherwise leak through Material TabBar.
class _ClaudePillTabBar extends StatefulWidget {
  const _ClaudePillTabBar({
    required this.controller,
    required this.labels,
  });

  final TabController controller;
  final List<String> labels;

  @override
  State<_ClaudePillTabBar> createState() => _ClaudePillTabBarState();
}

class _ClaudePillTabBarState extends State<_ClaudePillTabBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTab);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTab);
    super.dispose();
  }

  void _onTab() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final accent = ClaudePalette.accent(context);
    final accentTint = ClaudePalette.accentTint(context);
    final secondary = ClaudePalette.secondary(context);
    final elevated = ClaudePalette.elevated(context);
    final divider = ClaudePalette.divider(context);

    return Container(
      decoration: BoxDecoration(
        color: elevated,
        borderRadius: BorderRadius.circular(AppSpacing.cornerRadiusPill),
        border: Border.all(color: divider, width: 0.5),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(widget.labels.length, (i) {
          final isSelected = widget.controller.index == i;
          return Expanded(
            child: Material(
              color: Colors.transparent,
              borderRadius:
                  BorderRadius.circular(AppSpacing.cornerRadiusPill),
              child: InkWell(
                borderRadius:
                    BorderRadius.circular(AppSpacing.cornerRadiusPill),
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.controller.animateTo(i);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: isSelected ? accentTint : Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(AppSpacing.cornerRadiusPill),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    widget.labels[i],
                    style: TextStyle(
                      color: isSelected ? accent : secondary,
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
