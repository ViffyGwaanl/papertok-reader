import 'dart:async';
import 'dart:math' as math;

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:anx_reader/widgets/common/axis_flex.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

class TranslationMenu extends StatefulWidget {
  const TranslationMenu({
    super.key,
    required this.content,
    required this.decoration,
    required this.axis,
    this.contextText,
  });

  final String content;
  final BoxDecoration decoration;
  final Axis axis;
  final String? contextText;

  @override
  State<TranslationMenu> createState() => _TranslationMenuState();
}

class _TranslationMenuState extends State<TranslationMenu> {
  Widget? _translationWidget;
  Timer? _debounceTimer;
  bool _translationInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeTranslation();
  }

  void _initializeTranslation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _translationInitialized) return;

      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        if (!mounted || _translationInitialized) return;

        setState(() {
          final effectiveContextText =
              (widget.contextText?.trim().isEmpty ?? true)
                  ? null
                  : widget.contextText;
          _translationWidget = translateText(
            widget.content,
            contextText: effectiveContextText,
          );
          _translationInitialized = true;
        });
      });
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Widget _langPicker(bool isFrom) {
    final MenuController menuController = MenuController();

    return PointerInterceptor(
      child: MenuAnchor(
        style: MenuStyle(
          backgroundColor: WidgetStateProperty.all(
            Theme.of(context).colorScheme.secondaryContainer,
          ),
          maximumSize: WidgetStateProperty.all(const Size(300, 300)),
        ),
        controller: menuController,
        menuChildren: [
          for (var lang in LangListEnum.values)
            PointerInterceptor(
              child: MenuItemButton(
                onPressed: () {
                  if (isFrom) {
                    Prefs().translateFrom = lang;
                  } else {
                    Prefs().translateTo = lang;
                  }
                },
                child: Text(lang.getNative(context)),
              ),
            ),
        ],
        builder: (context, controller, child) {
          final label = isFrom
              ? Prefs().translateFrom.getNative(context)
              : Prefs().translateTo.getNative(context);
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more, size: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  BoxConstraints _cardConstraints(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final maxWidth = math.min(size.width * 0.82, 360.0);
    final minWidth =
        math.min(maxWidth, widget.axis == Axis.vertical ? 260.0 : 280.0);
    final maxHeight = math.min(size.height * 0.42, 320.0);
    final minHeight = math.min(maxHeight, 180.0);

    return BoxConstraints(
      minWidth: minWidth,
      maxWidth: maxWidth,
      minHeight: minHeight,
      maxHeight: maxHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final constraints = _cardConstraints(context);

    return ConstrainedBox(
      constraints: constraints,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: Container(
          decoration: widget.decoration,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.content,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.35,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer
                              .withOpacity(0.86),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surface
                              .withOpacity(0.58),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: _translationWidget ??
                            const SizedBox(
                              height: 44,
                              child: Center(child: Text('...')),
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color:
                      Theme.of(context).colorScheme.surface.withOpacity(0.42),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: AxisFlex(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  axis: widget.axis == Axis.vertical
                      ? Axis.horizontal
                      : widget.axis,
                  children: [
                    Flexible(child: _langPicker(true)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: Theme.of(context)
                            .colorScheme
                            .onSecondaryContainer
                            .withOpacity(0.68),
                      ),
                    ),
                    Flexible(child: _langPicker(false)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
