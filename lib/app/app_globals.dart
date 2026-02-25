import 'package:flutter/widgets.dart';

/// Global navigator key for app-wide navigation.
///
/// Kept outside of `main.dart` to avoid circular imports between app services
/// and the app entry point.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
