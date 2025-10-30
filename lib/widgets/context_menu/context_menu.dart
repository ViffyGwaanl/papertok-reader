import 'dart:math' as math;

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/widgets/common/axis_flex.dart';
import 'package:anx_reader/widgets/context_menu/excerpt_menu.dart';
import 'package:anx_reader/widgets/context_menu/translation_menu.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

void showContextMenu(
  BuildContext context,
  double left,
  double top,
  double right,
  double bottom,
  String annoContent,
  String annoCfi,
  int? annoId,
  bool footnote,
  Axis axis,
) {
  final playerKey = epubPlayerKey.currentState;
  if (playerKey == null) return;

  RenderBox? renderBox =
      epubPlayerKey.currentContext?.findRenderObject() as RenderBox?;
  Size? renderBoxSize = renderBox?.size;

  double screenHeight =
      renderBoxSize?.height ?? MediaQuery.of(context).size.height;
  double screenWidth =
      renderBoxSize?.width ?? MediaQuery.of(context).size.width;

  Offset localToGlobal = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;

  final viewportRect = Rect.fromLTWH(
    localToGlobal.dx,
    localToGlobal.dy,
    screenWidth,
    screenHeight,
  );

  final selectionRect = Rect.fromLTRB(
    localToGlobal.dx + left * screenWidth,
    localToGlobal.dy + top * screenHeight,
    localToGlobal.dx + right * screenWidth,
    localToGlobal.dy + bottom * screenHeight,
  );

  const double horizontalMargin = 16;
  const double verticalMargin = 16;
  const double gap = 12;

  final double menuWidth =
      math.min(350, math.max(120, screenWidth - horizontalMargin * 2));
  final double maxHeight = screenHeight - verticalMargin * 2;
  final double menuHeight = math.min(
    footnote ? 350 : 550,
    math.max(200, maxHeight),
  );

  late double widgetTop;
  late double widgetLeft;

  if (axis == Axis.horizontal) {
    final double spaceAbove = selectionRect.top - viewportRect.top;
    final double spaceBelow = viewportRect.bottom - selectionRect.bottom;
    final bool placeBelow =
        (spaceBelow >= menuHeight + gap) || (spaceBelow >= spaceAbove);

    double desiredTop = placeBelow
        ? selectionRect.bottom + gap
        : selectionRect.top - menuHeight - gap;
    desiredTop = desiredTop.clamp(
      viewportRect.top + verticalMargin,
      viewportRect.bottom - menuHeight - verticalMargin,
    );

    double desiredLeft = selectionRect.center.dx - menuWidth / 2;
    desiredLeft = desiredLeft.clamp(
      viewportRect.left + horizontalMargin,
      viewportRect.right - menuWidth - horizontalMargin,
    );

    widgetTop = desiredTop;
    widgetLeft = desiredLeft;
  } else {
    final double spaceLeft = selectionRect.left - viewportRect.left;
    final double spaceRight = viewportRect.right - selectionRect.right;
    final bool placeRight =
        (spaceRight >= menuWidth + gap) || (spaceRight >= spaceLeft);

    double desiredLeft = placeRight
        ? selectionRect.right + gap
        : selectionRect.left - menuWidth - gap;
    desiredLeft = desiredLeft.clamp(
      viewportRect.left + horizontalMargin,
      viewportRect.right - menuWidth - horizontalMargin,
    );

    double desiredTop = selectionRect.center.dy - menuHeight / 2;
    desiredTop = desiredTop.clamp(
      viewportRect.top + verticalMargin,
      viewportRect.bottom - menuHeight - verticalMargin,
    );

    widgetTop = desiredTop;
    widgetLeft = desiredLeft;
  }

  playerKey.removeOverlay();

  void onClose() {
    playerKey.webViewController.evaluateJavascript(source: 'clearSelection()');
    playerKey.removeOverlay();
  }

  BoxDecoration decoration = BoxDecoration(
    color: Prefs().eInkMode
        ? Colors.white
        : Theme.of(context).colorScheme.secondaryContainer,
    borderRadius: BorderRadius.circular(10),
    boxShadow: [
      if (!Prefs().eInkMode)
        BoxShadow(
          color: Colors.black.withOpacity(0.1),
          spreadRadius: 5,
          blurRadius: 7,
          offset: const Offset(0, 3),
        ),
      if (Prefs().eInkMode)
        BoxShadow(
          color: Colors.black,
          spreadRadius: 1,
          blurRadius: 0,
        ),
    ],
  );

  bool showTranslationMenu = Prefs().autoTranslateSelection;
  playerKey.contextMenuEntry = OverlayEntry(builder: (context) {
    return Positioned(
      left: widgetLeft,
      top: widgetTop,
      child: Container(
        width: menuWidth,
        height: menuHeight,
        color: Colors.transparent,
        child: StatefulBuilder(builder: (context, setState) {
          void toggleTranslationMenu() {
            setState(() {
              showTranslationMenu = !showTranslationMenu;
            });
          }

          return PointerInterceptor(
            child: AxisFlex(
              axis: flipAxis(axis),
              mainAxisSize: MainAxisSize.min,
              children: [
                LayoutBuilder(builder: (context, constraints) {
                  return AxisFlex(
                    axis: flipAxis(axis),
                    children: [
                      AxisFlex(
                        axis: axis,
                        children: [
                          ExcerptMenu(
                            annoCfi: annoCfi,
                            annoContent: annoContent,
                            id: annoId,
                            onClose: onClose,
                            footnote: footnote,
                            decoration: decoration,
                            toggleTranslationMenu: toggleTranslationMenu,
                            axis: axis,
                          ),
                        ],
                      ),
                      // SizedBox(height: bottom),
                    ],
                  );
                }),
                const SizedBox(height: 10),
                if (showTranslationMenu) ...[
                  SizedBox.square(
                    dimension: 10,
                  ),
                  AxisFlex(
                    axis: axis,
                    children: [
                      TranslationMenu(
                        content: annoContent,
                        decoration: decoration,
                        axis: axis,
                      ),
                    ],
                  )
                ],
              ],
            ),
          );
        }),
      ),
    );
  });

  Overlay.of(context).insert(playerKey.contextMenuEntry!);
}
