import 'package:cupertino_native/channel/params.dart';
import 'package:cupertino_native/style/sf_symbol.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Icon-only Cupertino-native tab bar.
///
/// `cupertino_native`'s default [CNTabBar] always sends a non-empty `labels`
/// array to the platform view, which makes iOS allocate space for titles.
/// For Paper Reader we want a compact, icon-only floating tab bar.
///
/// This widget reuses the same platform view type (`CupertinoNativeTabBar`)
/// but sends an empty `labels` list so UITabBarItem titles become `nil`.
class IconOnlyNativeTabBar extends StatefulWidget {
  const IconOnlyNativeTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.tint,
    this.backgroundColor,
    this.iconSize,
    this.height,
  });

  final List<CNSymbol> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  final Color? tint;
  final Color? backgroundColor;
  final double? iconSize;
  final double? height;

  @override
  State<IconOnlyNativeTabBar> createState() => _IconOnlyNativeTabBarState();
}

class _IconOnlyNativeTabBarState extends State<IconOnlyNativeTabBar> {
  MethodChannel? _channel;
  int? _lastIndex;
  int? _lastTint;
  int? _lastBg;
  bool? _lastIsDark;
  String? _lastItemsSignature;

  String _itemsSignature() {
    final symbols = widget.items.map((e) => e.name).join('|');
    final iconSize = widget.iconSize;
    return '${widget.items.length}|${iconSize ?? ''}|$symbols';
  }

  bool get _isDark => CupertinoTheme.of(context).brightness == Brightness.dark;
  Color? get _effectiveTint =>
      widget.tint ?? CupertinoTheme.of(context).primaryColor;

  @override
  void didUpdateWidget(covariant IconOnlyNativeTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPropsToNativeIfNeeded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBrightnessIfNeeded();
    _syncPropsToNativeIfNeeded();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!(defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS)) {
      // Non-Apple fallback (shouldn't be used in our iOS-first product).
      return SizedBox(
        height: widget.height,
        child: CupertinoTabBar(
          items: [
            for (var i = 0; i < widget.items.length; i++)
              BottomNavigationBarItem(
                icon: const Icon(CupertinoIcons.circle),
                label: '',
              ),
          ],
          currentIndex: widget.currentIndex,
          onTap: widget.onTap,
          backgroundColor: widget.backgroundColor,
          inactiveColor: CupertinoColors.inactiveGray,
          activeColor: widget.tint ?? CupertinoTheme.of(context).primaryColor,
        ),
      );
    }

    final symbols = widget.items.map((e) => e.name).toList(growable: false);
    final sizes = widget.items
        .map((e) => (widget.iconSize ?? e.size))
        .toList(growable: false);
    final colors = widget.items
        .map((e) => resolveColorToArgb(e.color, context))
        .toList(growable: false);

    final creationParams = <String, dynamic>{
      // Important: empty labels => UITabBarItem(title:nil)
      'labels': <String>[],
      'sfSymbols': symbols,
      'sfSymbolSizes': sizes,
      'sfSymbolColors': colors,
      'selectedIndex': widget.currentIndex,
      'isDark': _isDark,
      'split': false,
      'rightCount': 1,
      'splitSpacing': 8.0,
      'style': encodeStyle(context, tint: _effectiveTint)
        ..addAll({
          if (widget.backgroundColor != null)
            'backgroundColor':
                resolveColorToArgb(widget.backgroundColor, context),
        }),
    };

    const viewType = 'CupertinoNativeTabBar';
    final platformView = defaultTargetPlatform == TargetPlatform.iOS
        ? UiKitView(
            viewType: viewType,
            creationParams: creationParams,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _onCreated,
          )
        : AppKitView(
            viewType: viewType,
            creationParams: creationParams,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _onCreated,
          );

    return SizedBox(
      height: widget.height ?? 50.0,
      width: double.infinity,
      child: platformView,
    );
  }

  void _onCreated(int id) {
    final ch = MethodChannel('CupertinoNativeTabBar_$id');
    _channel = ch;
    ch.setMethodCallHandler(_onMethodCall);
    _lastIndex = widget.currentIndex;
    _lastTint = resolveColorToArgb(_effectiveTint, context);
    _lastBg = resolveColorToArgb(widget.backgroundColor, context);
    _lastIsDark = _isDark;
    _lastItemsSignature = _itemsSignature();
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    if (call.method == 'valueChanged') {
      final args = call.arguments as Map?;
      final idx = (args?['index'] as num?)?.toInt();
      if (idx != null && idx != _lastIndex) {
        widget.onTap(idx);
        _lastIndex = idx;
      }
    }
    return null;
  }

  Future<void> _syncPropsToNativeIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;

    final idx = widget.currentIndex;
    if (_lastIndex != idx) {
      await ch.invokeMethod('setSelectedIndex', {'index': idx});
      _lastIndex = idx;
    }

    final tint = resolveColorToArgb(_effectiveTint, context);
    final bg = resolveColorToArgb(widget.backgroundColor, context);

    final style = <String, dynamic>{};
    if (_lastTint != tint && tint != null) {
      style['tint'] = tint;
      _lastTint = tint;
    }
    if (_lastBg != bg && bg != null) {
      style['backgroundColor'] = bg;
      _lastBg = bg;
    }
    if (style.isNotEmpty) {
      await ch.invokeMethod('setStyle', style);
    }

    // Avoid calling `setItems` on every rebuild.
    // Rebuilding tab items resets native selection state and may cause a
    // "double" or "weird" animation when users tap to switch tabs.
    final sig = _itemsSignature();
    if (_lastItemsSignature != sig) {
      final symbols = widget.items.map((e) => e.name).toList(growable: false);
      await ch.invokeMethod('setItems', {
        'labels': <String>[],
        'sfSymbols': symbols,
        'selectedIndex': widget.currentIndex,
      });
      _lastItemsSignature = sig;
    }
  }

  Future<void> _syncBrightnessIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;
    final isDark = _isDark;
    if (_lastIsDark != isDark) {
      await ch.invokeMethod('setBrightness', {'isDark': isDark});
      _lastIsDark = isDark;
    }
  }
}
