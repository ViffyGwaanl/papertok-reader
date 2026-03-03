import 'package:flutter/widgets.dart';

/// Global route observer used to detect whether certain pages are already open.
///
/// This is used for iOS Shortcuts handoff UX (reuse existing chat window).
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
