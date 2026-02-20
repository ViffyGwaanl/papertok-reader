import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book_style.dart';
import 'package:anx_reader/models/font_model.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/page/settings_page/subpage/fonts.dart';
import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:anx_reader/service/font.dart';
import 'package:anx_reader/utils/font_parser.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/widgets/icon_and_text.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/more_settings.dart';
import 'package:anx_reader/widgets/reading_page/widget_title.dart';
import 'package:anx_reader/dao/theme.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/widgets/reading_page/widgets/bgimg_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

enum PageTurn {
  noAnimation,
  slide,
  scroll;

  String getLabel(BuildContext context) {
    switch (this) {
      case PageTurn.noAnimation:
        return L10n.of(context).noAnimation;
      case PageTurn.slide:
        return L10n.of(context).slide;
      case PageTurn.scroll:
        return L10n.of(context).scroll;
    }
  }
}

class StyleWidget extends StatefulWidget {
  const StyleWidget({
    super.key,
    required this.themes,
    required this.epubPlayerKey,
    required this.setCurrentPage,
    required this.hideAppBarAndBottomBar,
  });

  final List<ReadTheme> themes;
  final GlobalKey<EpubPlayerState> epubPlayerKey;
  final Function setCurrentPage;
  final Function hideAppBarAndBottomBar;

  @override
  StyleWidgetState createState() => StyleWidgetState();
}

class StyleWidgetState extends State<StyleWidget> {
  BookStyle bookStyle = Prefs().bookStyle;
  int? currentThemeId = Prefs().readTheme.id;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _fontSizeSliderRow(theme),
            const SizedBox(height: 12),
            _marginStepperRow(theme),
            const SizedBox(height: 10),
            _lineHeightStepperRow(theme),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _pillMenuButton(
                    theme,
                    label: _currentFontLabel(context),
                    onTap: () => _showFontPicker(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _pillMenuButton(
                    theme,
                    label: _indentLabel(context),
                    onTap: () => _showIndentPicker(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _pillMenuButton(
                    theme,
                    label: _pageTurnLabel(context),
                    onTap: () => _showPageTurnPicker(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                L10n.of(context).readingPageStyle,
                style: theme.textTheme.titleSmall,
              ),
              subtitle: Text(
                L10n.of(context).readingPageStyleBackground,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: themeSelector()),
                    const SizedBox(width: 10),
                    _pillMenuButton(
                      theme,
                      label: L10n.of(context).readingPageStyleBackground,
                      onTap: () => widget.setCurrentPage(const BgimgSelector()),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(
    ThemeData theme, {
    required Widget child,
    VoidCallback? onTap,
    bool selected = false,
    EdgeInsetsGeometry padding =
        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  }) {
    final cs = theme.colorScheme;
    final bg = selected
        ? cs.primary.withAlpha(40)
        : cs.surfaceContainerHighest.withAlpha(140);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Material(
        color: bg,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              border: Border.all(
                color: cs.outline.withAlpha(90),
                width: 0.5,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: DefaultTextStyle(
              style: theme.textTheme.bodyMedium!.copyWith(
                color: cs.onSurface,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _pillMenuButton(
    ThemeData theme, {
    required String label,
    required VoidCallback onTap,
  }) {
    return _pill(
      theme,
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 18),
        ],
      ),
    );
  }

  void _applyBookStyle(BookStyle next) {
    setState(() {
      bookStyle = next;
    });
    widget.epubPlayerKey.currentState?.changeStyle(next);
    Prefs().saveBookStyleToPrefs(next);
  }

  int _nearestIndex(double value, List<double> options) {
    var bestIdx = 0;
    var bestDist = (value - options[0]).abs();
    for (var i = 1; i < options.length; i++) {
      final d = (value - options[i]).abs();
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  Widget _fontSizeSliderRow(ThemeData theme) {
    final cs = theme.colorScheme;
    final enabled = !Prefs().useBookStyles;

    const min = 0.5;
    const max = 3.0;
    final t = ((bookStyle.fontSize - min) / (max - min)).clamp(0.0, 1.0);

    final display = (bookStyle.fontSize * 14).round();

    return _pill(
      theme,
      selected: true,
      onTap: null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Text(
            'A',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 36,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 18,
                      ),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 0,
                      ),
                      activeTrackColor: cs.onSurfaceVariant.withAlpha(160),
                      inactiveTrackColor: cs.onSurfaceVariant.withAlpha(60),
                    ),
                    child: Slider(
                      value: bookStyle.fontSize,
                      onChanged: enabled
                          ? (value) {
                              _applyBookStyle(bookStyle.copyWith(
                                fontSize: value,
                              ));
                            }
                          : null,
                      min: min,
                      max: max,
                      divisions: 25,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Align(
                      alignment: Alignment(-1 + 2 * t, 0),
                      child: IgnorePointer(
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withAlpha(220),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: cs.outline.withAlpha(120),
                              width: 0.5,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '$display',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
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
          const SizedBox(width: 8),
          Text(
            'A',
            style: theme.textTheme.titleMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _marginStepperRow(ThemeData theme) {
    final enabled = !Prefs().useBookStyles;
    const options = <double>[2, 6, 12];
    final idx = _nearestIndex(bookStyle.sideMargin, options);

    String levelLabel() {
      return switch (idx) {
        0 => '小',
        1 => '中',
        _ => '大',
      };
    }

    return Row(
      children: [
        Expanded(
          child: _pill(
            theme,
            onTap: enabled && idx > 0
                ? () => _applyBookStyle(
                      bookStyle.copyWith(sideMargin: options[idx - 1]),
                    )
                : null,
            child: const Center(child: Text('小')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _pill(
            theme,
            selected: true,
            onTap: null,
            child: Center(child: Text('边距 ${levelLabel()}')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _pill(
            theme,
            onTap: enabled && idx < options.length - 1
                ? () => _applyBookStyle(
                      bookStyle.copyWith(sideMargin: options[idx + 1]),
                    )
                : null,
            child: const Center(child: Text('大')),
          ),
        ),
      ],
    );
  }

  Widget _lineHeightStepperRow(ThemeData theme) {
    final enabled = !Prefs().useBookStyles;
    const options = <double>[1.4, 1.8, 2.2];
    final idx = _nearestIndex(bookStyle.lineHeight, options);

    String levelLabel() {
      return switch (idx) {
        0 => '紧',
        1 => '标准',
        _ => '松',
      };
    }

    return Row(
      children: [
        Expanded(
          child: _pill(
            theme,
            onTap: enabled && idx > 0
                ? () => _applyBookStyle(
                      bookStyle.copyWith(lineHeight: options[idx - 1]),
                    )
                : null,
            child: const Center(child: Text('紧')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _pill(
            theme,
            selected: true,
            onTap: null,
            child: Center(child: Text('行距 ${levelLabel()}')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _pill(
            theme,
            onTap: enabled && idx < options.length - 1
                ? () => _applyBookStyle(
                      bookStyle.copyWith(lineHeight: options[idx + 1]),
                    )
                : null,
            child: const Center(child: Text('松')),
          ),
        ),
      ],
    );
  }

  String _currentFontLabel(BuildContext context) {
    final label = Prefs().font.label.trim();
    return label.isEmpty ? L10n.of(context).font : label;
  }

  String _indentLabel(BuildContext context) {
    final v = bookStyle.indent;
    final state = v <= 0 ? '无' : (v <= 2 ? '标准' : '较大');
    return '首行缩进 $state';
  }

  String _pageTurnLabel(BuildContext context) {
    return Prefs().pageTurnStyle.getLabel(context);
  }

  Future<void> _showFontPicker(BuildContext context) async {
    final l10n = L10n.of(context);
    final all = fonts();
    final selected = await showModalBottomSheet<FontModel>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            children: all
                .map(
                  (f) => ListTile(
                    title: Text(f.label),
                    trailing: f.path == Prefs().font.path
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.of(ctx).pop(f),
                  ),
                )
                .toList(growable: false),
          ),
        );
      },
    );

    if (selected == null) return;

    if (selected.name == 'newFont') {
      widget.hideAppBarAndBottomBar(false);
      await importFont();
      return;
    }

    if (selected.name == 'download') {
      widget.hideAppBarAndBottomBar(false);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const FontsSettingPage()),
      );
      return;
    }

    widget.epubPlayerKey.currentState?.changeFont(selected);
    Prefs().font = selected;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.commonSaved)),
    );

    setState(() {});
  }

  Future<void> _showIndentPicker(BuildContext context) async {
    if (Prefs().useBookStyles) return;
    final options = <double, String>{
      0: '无',
      2: '标准',
      4: '较大',
    };

    final selected = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.entries
                .map(
                  (e) => ListTile(
                    title: Text(e.value),
                    trailing: bookStyle.indent == e.key
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.of(ctx).pop(e.key),
                  ),
                )
                .toList(growable: false),
          ),
        );
      },
    );

    if (selected == null) return;
    _applyBookStyle(bookStyle.copyWith(indent: selected));
  }

  Future<void> _showPageTurnPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<PageTurn>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: PageTurn.values
                .map(
                  (v) => ListTile(
                    title: Text(v.getLabel(context)),
                    trailing: Prefs().pageTurnStyle == v
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.of(ctx).pop(v),
                  ),
                )
                .toList(growable: false),
          ),
        );
      },
    );

    if (selected == null) return;
    Prefs().pageTurnStyle = selected;
    widget.epubPlayerKey.currentState?.changePageTurnStyle(selected);
    setState(() {});
  }

  List<FontModel> fonts() {
    Directory fontDir = getFontDir();
    List<FontModel> fontList = [
      FontModel(
        label: L10n.of(context).downloadFonts,
        name: 'download',
        path: 'download',
      ),
      FontModel(
        label: L10n.of(context).addNewFont,
        name: 'newFont',
        path: 'newFount',
      ),
      FontModel(
        label: L10n.of(context).followBook,
        name: 'book',
        path: 'book',
      ),
      FontModel(
        label: L10n.of(context).systemFont,
        name: 'system',
        path: 'system',
      ),
    ];
    // fontDir.listSync().forEach((element) {
    //   if (element is File) {
    //     fontList.add(FontModel(
    //       label: getFontNameFromFile(element),
    //       name: 'customFont' + ,
    //       path:
    //           'http://127.0.0.1:${Server().port}/fonts/${element.path.split('/').last}',
    //     ));
    //   }
    // });
    // name = 'customFont' + index
    for (int i = 0; i < fontDir.listSync().length; i++) {
      File element = fontDir.listSync()[i] as File;
      fontList.add(FontModel(
        label: getFontNameFromFile(element),
        name: 'customFont$i',
        path:
            'http://127.0.0.1:${Server().port}/fonts/${element.path.split(Platform.pathSeparator).last}',
      ));
    }

    return fontList;
  }

  Widget fontAndPageTurn() {
    FontModel? font = fonts().firstWhere(
        (element) => element.path == Prefs().font.path,
        orElse: () => FontModel(
            label: L10n.of(context).followBook, name: 'book', path: 'book'));

    Widget? leadingIcon(String name) {
      if (name == 'download') {
        return const Icon(Icons.download);
      } else if (name == 'newFont') {
        return const Icon(Icons.add);
      }
      return null;
    }

    return Row(children: [
      Expanded(
        child: DropdownMenu<PageTurn>(
          label: Text(L10n.of(context).readingPagePageTurningMethod),
          initialSelection: Prefs().pageTurnStyle,
          expandedInsets: const EdgeInsets.only(right: 5),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(50),
            ),
          ),
          onSelected: (PageTurn? value) {
            if (value != null) {
              Prefs().pageTurnStyle = value;
              epubPlayerKey.currentState!.changePageTurnStyle(value);
            }
          },
          dropdownMenuEntries: PageTurn.values
              .map((e) => DropdownMenuEntry(
                    value: e,
                    label: e.getLabel(context),
                  ))
              .toList(),
        ),
      ),
      Expanded(
        child: DropdownMenu<FontModel>(
          label: Text(L10n.of(context).font),
          expandedInsets: const EdgeInsets.only(left: 5),
          initialSelection: font,
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(50),
            ),
          ),
          onSelected: (FontModel? font) async {
            if (font == null) return;
            if (font.name == 'newFont') {
              widget.hideAppBarAndBottomBar(false);
              await importFont();
              return;
            } else if (font.name == 'download') {
              widget.hideAppBarAndBottomBar(false);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const FontsSettingPage()),
              );
              return;
            } else {
              epubPlayerKey.currentState!.changeFont(font);
              Prefs().font = font;
            }
          },
          dropdownMenuEntries: fonts()
              .map((font) => DropdownMenuEntry(
                    value: font,
                    label: font.label,
                    leadingIcon: leadingIcon(font.name),
                  ))
              .toList(),
        ),
      ),
    ]);
  }

  Padding sliders() {
    return Padding(
      padding: const EdgeInsets.all(3.0),
      child: Column(
        children: [
          fontSizeSlider(),
          lineHeightAndParagraphSpacingSlider(),
        ],
      ),
    );
  }

  Row lineHeightAndParagraphSpacingSlider() {
    bool enabled = !Prefs().useBookStyles;
    return Row(
      children: [
        IconAndText(
          icon: const Icon(Icons.line_weight),
          text: L10n.of(context).readingPageLineSpacing,
        ),
        Expanded(
          child: Slider(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              value: bookStyle.lineHeight,
              onChanged: enabled
                  ? (double value) {
                      setState(() {
                        bookStyle.lineHeight = value;
                        widget.epubPlayerKey.currentState!
                            .changeStyle(bookStyle);
                        Prefs().saveBookStyleToPrefs(bookStyle);
                      });
                    }
                  : null,
              min: 0,
              max: 3,
              divisions: 10,
              label: (bookStyle.lineHeight / 3 * 10).round().toString()),
        ),
        IconAndText(
          icon: const Icon(Icons.height),
          text: L10n.of(context).readingPageParagraphSpacing,
        ),
        Expanded(
          child: Slider(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            value: bookStyle.paragraphSpacing,
            onChanged: enabled
                ? (double value) {
                    setState(() {
                      bookStyle.paragraphSpacing = value;
                      widget.epubPlayerKey.currentState!.changeStyle(bookStyle);
                      Prefs().saveBookStyleToPrefs(bookStyle);
                    });
                  }
                : null,
            min: 0,
            max: 5,
            divisions: 10,
            label: (bookStyle.paragraphSpacing / 5 * 10).round().toString(),
          ),
        ),
      ],
    );
  }

  Row fontSizeSlider() {
    bool enabled = !Prefs().useBookStyles;
    return Row(
      children: [
        IconAndText(
          icon: const Icon(Icons.format_size),
          text: L10n.of(context).readingPageFontSize,
        ),
        Expanded(
          child: Slider(
            value: bookStyle.fontSize,
            onChanged: enabled
                ? (double value) {
                    setState(() {
                      bookStyle.fontSize = value;
                      widget.epubPlayerKey.currentState!.changeStyle(bookStyle);
                      Prefs().saveBookStyleToPrefs(bookStyle);
                    });
                  }
                : null,
            min: 0.5,
            max: 3.0,
            divisions: 25,
            label: bookStyle.fontSize.toStringAsFixed(2),
          ),
        ),
      ],
    );
  }

  SizedBox themeSelector() {
    const size = 40.0;
    const paddingSize = 5.0;
    EdgeInsetsGeometry padding = const EdgeInsets.all(paddingSize);
    return SizedBox(
      height: size + paddingSize * 2,
      child: ListView.builder(
        itemCount: widget.themes.length + 1,
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          if (index == widget.themes.length) {
            // add a new theme
            return Padding(
              padding: padding,
              child: Container(
                  padding: padding,
                  width: size,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(
                      color: Colors.black45,
                      width: 1,
                    ),
                  ),
                  child: InkWell(
                    onTap: () async {
                      int currId = await themeDao.insertTheme(ReadTheme(
                          backgroundColor: 'ff121212',
                          textColor: 'ffcccccc',
                          backgroundImagePath: ''));
                      widget.setCurrentPage(ThemeChangeWidget(
                        readTheme: ReadTheme(
                            id: currId,
                            backgroundColor: 'ff121212',
                            textColor: 'ffcccccc',
                            backgroundImagePath: ''),
                        setCurrentPage: widget.setCurrentPage,
                      ));
                    },
                    child: Icon(Icons.add,
                        size: size / 2,
                        color: Color(int.parse('0x${'ffcccccc'}'))),
                  )),
            );
          }
          // theme list
          return Padding(
            padding: padding,
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: Color(
                    int.parse('0x${widget.themes[index].backgroundColor}')),
                borderRadius: BorderRadius.circular(50),
                border: Border.all(
                  color: index + 1 == currentThemeId
                      ? Theme.of(context).primaryColor
                      : Colors.black45,
                  width: index + 1 == currentThemeId ? 3 : 1,
                ),
              ),
              height: size,
              width: size,
              child: InkWell(
                onTap: () {
                  Prefs().saveReadThemeToPrefs(widget.themes[index]);
                  widget.epubPlayerKey.currentState!
                      .changeTheme(widget.themes[index]);
                  setState(() {
                    currentThemeId = widget.themes[index].id;
                  });
                },
                onSecondaryTap: () {
                  setState(() {
                    widget.setCurrentPage(ThemeChangeWidget(
                      readTheme: widget.themes[index],
                      setCurrentPage: widget.setCurrentPage,
                    ));
                  });
                },
                onLongPress: () {
                  setState(() {
                    widget.setCurrentPage(ThemeChangeWidget(
                      readTheme: widget.themes[index],
                      setCurrentPage: widget.setCurrentPage,
                    ));
                  });
                },
                child: Center(
                  child: Text(
                    "A",
                    style: TextStyle(
                      color: Color(
                          int.parse('0x${widget.themes[index].textColor}')),
                      fontSize: size / 3,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ThemeChangeWidget extends StatefulWidget {
  const ThemeChangeWidget({
    super.key,
    required this.readTheme,
    required this.setCurrentPage,
  });

  final ReadTheme readTheme;
  final Function setCurrentPage;

  @override
  State<ThemeChangeWidget> createState() => _ThemeChangeWidgetState();
}

class _ThemeChangeWidgetState extends State<ThemeChangeWidget> {
  late ReadTheme readTheme;

  @override
  void initState() {
    super.initState();
    readTheme = widget.readTheme;
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      IconButton(
        onPressed: () async {
          String? pickingColor =
              await showColorPickerDialog(readTheme.backgroundColor);
          if (pickingColor != '') {
            setState(() {
              readTheme.backgroundColor = pickingColor!;
            });
            themeDao.updateTheme(readTheme);
          }
        },
        icon: Icon(Icons.circle,
            size: 80,
            color: Color(int.parse('0x${readTheme.backgroundColor}'))),
      ),
      IconButton(
          onPressed: () async {
            String? pickingColor =
                await showColorPickerDialog(readTheme.textColor);
            if (pickingColor != '') {
              setState(() {
                readTheme.textColor = pickingColor!;
              });
              themeDao.updateTheme(readTheme);
            }
          },
          icon: Icon(Icons.text_fields,
              size: 60, color: Color(int.parse('0x${readTheme.textColor}')))),
      const Expanded(
        child: SizedBox(),
      ),
      IconButton(
        onPressed: () {
          themeDao.deleteTheme(readTheme.id!);
          widget.setCurrentPage(const SizedBox(height: 1));
          // setState(() {});
        },
        icon: const Icon(
          Icons.delete,
          size: 40,
        ),
      ),
    ]);
  }

  Future<String?> showColorPickerDialog(String currColor) async {
    Color pickedColor = Color(int.parse('0x$currColor'));

    await showDialog<void>(
      context: navigatorKey.currentState!.overlay!.context,
      builder: (BuildContext context) {
        return AlertDialog(
          content: SingleChildScrollView(
            child: ColorPicker(
              hexInputBar: true,
              pickerColor: pickedColor,
              onColorChanged: (Color color) {
                pickedColor = color;
              },
              pickerAreaHeightPercent: 0.8,
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop(pickedColor.value.toRadixString(16));
              },
            ),
          ],
        );
      },
    );

    return pickedColor.value.toRadixString(16);
  }
}
