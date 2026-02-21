import 'package:flutter/widgets.dart';

/// Provides the HomePage bottom overlay inset (e.g. floating tab bar height)
/// to child pages.
class HomeBottomInsetScope extends InheritedWidget {
  const HomeBottomInsetScope({
    super.key,
    required this.bottomInset,
    required super.child,
  });

  final double bottomInset;

  static double of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<HomeBottomInsetScope>()
            ?.bottomInset ??
        0.0;
  }

  @override
  bool updateShouldNotify(HomeBottomInsetScope oldWidget) {
    return bottomInset != oldWidget.bottomInset;
  }
}
